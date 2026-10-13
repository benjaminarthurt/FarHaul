class_name ShipRemote
extends Node
## The ship remote: a small web server inside the game, so a phone or tablet on the same network can be
## a second screen for the cockpit (gauges, the map, the controls). Off unless switched on in Settings.
##
## - It only answers devices on the local network (private addresses); anything else gets a 403.
## - A device pairs once with the six-digit code shown in Settings and the F10 menu, and gets a token
##   it keeps. "New code" in Settings revokes every paired device. Five wrong codes from one address
##   lock it out for a minute.
## - It follows the game: commands go through FlightScene.pilot(), the same code the keys use, with
##   the same limits (time compression caps, course hold's 5 degrees, docking range).
##
## Routes: GET / (the page, remote/index.html), POST /api/pair {code} -> {token},
## GET /api/state, GET /api/chart?view=system|space, POST /api/cmd {action, value}. Every /api call
## but pair needs the X-Remote-Token header. Plain HTTP, one request per connection.

const PORT := 8417
const PAGE := "res://remote/index.html"
const MAX_REQUEST := 16384

static var instance: ShipRemote

var server := TCPServer.new()
var status := ""                 ## "" when listening, else why not
var _clients: Array = []         ## {peer: StreamPeerTCP, buf: PackedByteArray, age: float}
var _fails := {}                 ## address -> [count, unlock time]
var _page := ""
var _last_seen := 0.0            ## when a paired device last asked for the state (seconds since start)


## Start or stop the remote to match the setting. Called as each scene opens (GameSettings.apply_scene).
static func sync(tree: SceneTree) -> void:
	var want := bool(GameSettings.get_value("remote"))
	if want and instance == null:
		instance = ShipRemote.new()
		instance.name = "ShipRemote"
		tree.root.add_child.call_deferred(instance)
	elif not want and instance != null:
		instance.queue_free()
		instance = null


## The six-digit pairing code, made once and kept in the settings.
static func code() -> String:
	var c := String(GameSettings.get_value("remote_code"))
	if c.length() != 6:
		c = new_code()
	return c


## A fresh code: every device paired with the old one has to pair again.
static func new_code() -> String:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var c := "%06d" % rng.randi_range(0, 999999)
	GameSettings.set_value("remote_code", c)
	return c


## The token a paired device sends back: tied to the code, so a new code revokes it.
static func token_for(c: String) -> String:
	return ("farhaul-remote|" + c).sha256_text().substr(0, 32)


## Addresses to type into the phone: this computer's private IPv4 addresses.
static func addresses() -> Array[String]:
	var out: Array[String] = []
	for a in IP.get_local_addresses():
		if a.contains(".") and is_local(a) and not a.begins_with("127.") and not a.begins_with("169.254."):
			out.append(a)
	out.sort()
	return out


## What to show the player: "http://192.168.1.20:8417  code 123456".
static func where() -> String:
	var a := addresses()
	return "http://%s:%d   code %s" % [a[0] if not a.is_empty() else "this-computer", PORT, code()]


## A device on this network: loopback, private and link-local addresses.
static func is_local(addr: String) -> bool:
	var a := addr.to_lower()
	if a == "::1" or a.begins_with("127.") or a.begins_with("10.") or a.begins_with("192.168.") or a.begins_with("169.254."):
		return true
	if a.begins_with("::ffff:"):
		return is_local(a.substr(7))
	if a.begins_with("172."):
		var second := int(a.get_slice(".", 1))
		return second >= 16 and second <= 31
	return a.begins_with("fe80:") or a.begins_with("fc") or a.begins_with("fd")


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS   # the F10 menu pauses the game; the remote still answers
	var err := server.listen(PORT, "*")
	status = "" if err == OK else "Port %d is busy: the remote can't start." % PORT
	if FileAccess.file_exists(PAGE):
		_page = FileAccess.get_file_as_string(PAGE)


func _exit_tree() -> void:
	server.stop()
	if instance == self:
		instance = null


## Whether a paired device has asked for the state in the last few seconds.
func connected() -> bool:
	return _last_seen > 0.0 and Time.get_ticks_msec() / 1000.0 - _last_seen < 5.0


func _process(delta: float) -> void:
	while server.is_listening() and server.is_connection_available():
		var peer := server.take_connection()
		if peer != null:
			_clients.append({"peer": peer, "buf": PackedByteArray(), "age": 0.0})
	for c in _clients.duplicate():
		var peer: StreamPeerTCP = c.peer
		peer.poll()
		c.age += delta
		if peer.get_status() != StreamPeerTCP.STATUS_CONNECTED or c.age > 5.0:
			peer.disconnect_from_host()
			_clients.erase(c)
			continue
		var n := peer.get_available_bytes()
		if n > 0:
			var got: Array = peer.get_partial_data(n)
			if int(got[0]) == OK:
				c.buf.append_array(got[1])
		var req := _parse(c.buf)
		if req.is_empty() and c.buf.size() < MAX_REQUEST:
			continue
		var reply := _answer(req, peer.get_connected_host()) if not req.is_empty() else _json(413, {"error": "Too big."})
		peer.put_data(reply)
		peer.disconnect_from_host()
		_clients.erase(c)


## A whole request once it has all arrived: {method, path, query, headers, body}, else {}.
static func _parse(buf: PackedByteArray) -> Dictionary:
	var text := buf.get_string_from_utf8()
	var end := text.find("\r\n\r\n")
	if end < 0:
		return {}
	var lines := text.substr(0, end).split("\r\n")
	var first := lines[0].split(" ")
	if first.size() < 2:
		return {"method": "BAD", "path": "", "query": "", "headers": {}, "body": ""}
	var headers := {}
	for i in range(1, lines.size()):
		var at := lines[i].find(":")
		if at > 0:
			headers[lines[i].substr(0, at).strip_edges().to_lower()] = lines[i].substr(at + 1).strip_edges()
	var length := int(headers.get("content-length", "0"))
	var body_bytes := buf.slice(text.substr(0, end + 4).to_utf8_buffer().size())
	if body_bytes.size() < length:
		return {}
	var target := String(first[1])
	return {"method": String(first[0]), "path": target.get_slice("?", 0), "query": target.get_slice("?", 1) if "?" in target else "",
			"headers": headers, "body": body_bytes.slice(0, length).get_string_from_utf8()}


func _answer(req: Dictionary, host: String) -> PackedByteArray:
	if not is_local(host):
		return _json(403, {"error": "The ship remote only answers devices on this network."})
	var path := String(req.path)
	if req.method == "GET" and (path == "/" or path == "/index.html"):
		return _reply(200, "text/html; charset=utf-8", _page.to_utf8_buffer())
	if path == "/api/pair" and req.method == "POST":
		return _pair(req, host)
	if path.begins_with("/api/"):
		if String(req.headers.get("x-remote-token", "")) != token_for(code()):
			return _json(401, {"error": "Not paired. Enter the code from the game's Settings."})
		match path:
			"/api/state":
				_last_seen = Time.get_ticks_msec() / 1000.0
				return _json(200, state())
			"/api/chart":
				return _json(200, chart(req.query.contains("view=space")))
			"/api/cmd":
				if req.method != "POST":
					return _json(405, {"error": "POST a command."})
				var cmd = JSON.parse_string(String(req.body))
				if typeof(cmd) != TYPE_DICTIONARY:
					return _json(400, {"error": "Commands are JSON."})
				return _json(200, command(String(cmd.get("action", "")), float(cmd.get("value", 0.0))))
	return _json(404, {"error": "Nothing here."})


func _pair(req: Dictionary, host: String) -> PackedByteArray:
	var now := Time.get_ticks_msec() / 1000.0
	var f: Array = _fails.get(host, [0, 0.0])
	if now < float(f[1]):
		return _json(429, {"error": "Too many wrong codes. Wait a minute."})
	var body = JSON.parse_string(String(req.body))
	var given := String(body.get("code", "")) if typeof(body) == TYPE_DICTIONARY else ""
	if given.strip_edges() != code():
		f[0] = int(f[0]) + 1
		if int(f[0]) >= 5:
			f = [0, now + 60.0]
		_fails[host] = f
		return _json(403, {"error": "Wrong code. It's in the game's Settings, and the F10 menu."})
	_fails.erase(host)
	return _json(200, {"token": token_for(code())})


## What the page shows: the game around you, and whatever the current scene adds (the flight's gauges
## and controls through remote_state()).
func state() -> Dictionary:
	var out := {"version": String(ProjectSettings.get_setting("application/config/version", "")), "scene": "menu",
			"where": "At the title screen", "system_id": Session.system_id() if Session.slot >= 0 else "",
			"site_id": String(Session.profile.get("port_id", "")) if Session.slot >= 0 else ""}
	if Session.slot >= 0:
		out.merge({"credits": int(Session.profile.get("credits", 0)), "day": Session.day(), "captain": String(Session.profile.get("name", "")),
				"system_name": String(Worlds.system(Session.system_id()).get("name", "")),
				"site_name": String(LocalSpace.node(String(Session.profile.get("port_id", ""))).get("name", ""))}, true)
	var scene := get_tree().current_scene if get_tree() != null else null
	if scene != null and scene.has_method("remote_state"):
		out.merge(scene.remote_state(), true)
	elif Session.slot >= 0:
		out.scene = "dock"
		out.where = "Docked"
	return out


func command(action: String, value: float) -> Dictionary:
	var scene := get_tree().current_scene if get_tree() != null else null
	if scene == null or not scene.has_method("remote_command"):
		return {"ok": false, "message": "Nothing to fly from here. Take the helm first."}
	return scene.remote_command(action, value)


## The map's data: the system chart (bodies and sites) or known space, from StarMap's layout.
func chart(space: bool) -> Dictionary:
	if space:
		var sp := StarMap.space_chart()
		var systems := []
		for sid in sp.systems:
			var s: Dictionary = sp.systems[sid]
			systems.append({"id": sid, "name": String(s.name), "x": s.pos.x, "y": s.pos.y, "tier": String(s.tier)})
		return {"view": "space", "systems": systems, "routes": sp.routes}
	var sid := Session.system_id() if Session.slot >= 0 else "sol"
	var c := StarMap.system_chart(sid)
	var bodies := []
	for b in c.bodies:
		bodies.append({"id": String(b.id), "name": String(b.name), "type": String(b.type), "x": b.pos.x, "y": b.pos.y,
				"orbit": float(b.orbit), "parent": String(b.parent), "giant": bool(b.giant), "ring": bool(b.ring)})
	var sites := []
	var pos := StarMap.site_positions(sid)
	for id in pos:
		sites.append({"id": id, "name": StarMap._short(sid, String(pos[id].name)), "kind": String(pos[id].kind), "x": pos[id].pos.x, "y": pos[id].pos.y})
	return {"view": "system", "system_id": sid, "system_name": String(Worlds.system(sid).get("name", sid)), "primary": String(c.primary),
			"bodies": bodies, "sites": sites}


static func _json(code_: int, data: Variant) -> PackedByteArray:
	return _reply(code_, "application/json", JSON.stringify(data).to_utf8_buffer())


static func _reply(code_: int, kind: String, body: PackedByteArray) -> PackedByteArray:
	var reason: String = {200: "OK", 400: "Bad Request", 401: "Unauthorized", 403: "Forbidden", 404: "Not Found", 405: "Method Not Allowed",
			413: "Payload Too Large", 429: "Too Many Requests"}.get(code_, "OK")
	var head := "HTTP/1.1 %d %s\r\nContent-Type: %s\r\nContent-Length: %d\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n" % [code_, reason, kind, body.size()]
	var out := head.to_utf8_buffer()
	out.append_array(body)
	return out
