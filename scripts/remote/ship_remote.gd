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
## - In port it can do what the desks do (port_state(), port_command()): take freight, depart on
##   autopilot, deliver, wait a day, hire and let go crew, buy kits and repairs. Through Session, the
##   same calls the desks make.
##
## Routes: GET / (the page, remote/index.html), POST /api/pair {code} -> {token},
## GET /api/state, GET /api/chart?view=system|space, POST /api/cmd {action, value, id}. Every /api call
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
var _port_cache := {}            ## the last port_state(), reused while nothing has changed (it reads the save)
var _port_key := ""
var _port_t := 0.0


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
				return _json(200, command(String(cmd.get("action", "")), float(cmd.get("value", 0.0)), String(cmd.get("id", ""))))
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
	if _in_port(scene):
		var now := Time.get_ticks_msec() / 1000.0
		var k := "%d|%d|%s|%d|%s|%d" % [int(Session.profile.get("credits", 0)), Session.day(), String(Session.profile.get("port_id", "")), Session.crew().size(),
				String(Session.active_contract().get("status", "")), Session.patch_kits() * 10 + Session.spares_kits() + Passengers.count() * 1000]
		if k != _port_key or now - _port_t > 5.0:
			_port_cache = port_state()
			_port_key = k
			_port_t = now
		out["port"] = _port_cache
		var loaded := Session._load_ship(SaveSlots.read(Session.slot))
		if not loaded.is_empty():
			var c := Session.active_contract()
			out["status"] = status_block(loaded.ship, Session.wear(), Session.hull(), _crew_in_port(),
					{"cargo_t": float(c.get("accepted_tonnes", 0.0)) if String(c.get("person_kind", "")) != "passenger" else 0.0})
	return out


## In a saved game, berthed, and not in the shipyard or a flight: the desks' business is open.
func _in_port(scene: Node) -> bool:
	if Session.slot < 0 or Session.sim == null or String(Session.profile.get("location", "dock")) == "shipyard" or scene == null:
		return false
	return scene.scene_file_path in [Session.PLACE_SCENE, Session.DOCK_SCENE]


func command(action: String, value: float, id := "") -> Dictionary:
	var scene := get_tree().current_scene if get_tree() != null else null
	if action in PORT_ACTIONS:
		if not _in_port(scene):
			return {"ok": false, "message": "That's desk business: berth first." if scene is FlightScene else "Not from here. Be in port, on your feet or at the terminal."}
		var r := port_command(action, id)
		_port_key = ""
		_after_port(scene, action, r)
		return r
	if scene == null or not scene.has_method("remote_command"):
		return {"ok": false, "message": "Nothing to fly from here. Take the helm first."}
	if action == "comms" and scene is FlightScene:   # say something on the radio: id is "contact|option"
		return (scene as FlightScene).comms_c.act_id(id)
	return scene.remote_command(action, value)


# --- The ship's state, for the status panel --------------------------------------------------------

## One block for the page's ship panel, in port or in flight: hull, crew and what they're doing, every
## working part's condition, kits aboard, cargo and fuel.
## `crew_rows`: [{name, role, role_name, skill, doing}]. `extra`: {cargo_t, fuel, fuel_max}.
static func status_block(ship: ShipData, wear: Dictionary, hull: float, crew_rows: Array, extra: Dictionary = {}) -> Dictionary:
	var parts := []
	for p in Wear.parts(ship, wear):
		parts.append({"name": String(p.name), "condition": Wear.condition(float(p.wear)), "failed": float(p.wear) >= 1.0,
				"worn": float(p.wear) >= float(Wear.cfg().get("worn_at", 0.75))})
	var st := ShipStats.compute(ship)
	var out := {"hull": hull, "crew": crew_rows, "aboard": 1 + crew_rows.size(), "berths": int(st.get("berths", 0)),
			"parts": parts, "patch_kits": Session.patch_kits(), "patch_kit_max": Session.patch_kit_max(),
			"spares_kits": Session.spares_kits(), "spares_kit_max": int(Wear.cfg().get("spares_kit_max", 4)),
			"cargo_t": float(extra.get("cargo_t", 0.0)), "cargo_max": float(st.get("cargo_capacity", 0.0))}
	if extra.has("fuel"):
		out["fuel"] = float(extra.fuel)
		out["fuel_max"] = float(extra.fuel_max)
	var c := Session.active_contract() if Session.slot >= 0 else {}
	if not c.is_empty():
		out["load"] = String(c.get("title", ""))
	return out


static func _crew_in_port() -> Array:
	var out := []
	for p in Session.crew():
		var r := String(p.get("role", ""))
		out.append({"name": String(p.get("name", "")), "role": r, "role_name": Crew.role_name(r), "skill": int(p.get("skill", 1)),
				"doing": "Ashore, %s" % ["at the bar", "asleep in a bunk", "complaining about the coffee", "haggling at the market", "writing home"][absi(hash(String(p.get("id", "")) + str(Session.day()))) % 5]})
	return out


# --- In port: the desks from the phone ------------------------------------------------------------

const PORT_ACTIONS := ["accept", "depart", "hard_burn", "deliver", "cancel", "wait", "hire", "fire", "buy_patch_kit", "buy_spares_kit", "repair", "overhaul", "sell_cargo", "sell_parts", "hand_in_recorders", "hand_over_remains", "hand_over", "sign_on", "see_off", "collect_finders"]


## What the desks offer right now: the active contract and what can be done with it, the freight board
## and people with work, the crew and who's looking for a berth, and the repair desk's prices.
static func port_state() -> Dictionary:
	var out := {"insolvent": Session.insolvent()}
	var loaded := Session._load_ship(SaveSlots.read(Session.slot))
	var stats := Session.ship_stats(loaded.ship) if not loaded.is_empty() else {}
	var c := Session.active_contract()
	var here := String(Session.profile.get("port_id", ""))
	if not c.is_empty():
		var local := bool(c.get("local", false))
		var arrived := String(c.get("status", "")) == "arrived"
		var at_start := String(c.get("origin_port_id", "")) == here if local else String(c.get("origin_system_id", "")) == Session.system_id()
		var at_end := (String(c.get("destination_port_id", "")) == here or (bool(c.get("surface", false)) and LocalSpace.is_surface(here))) if local \
				else String(c.get("destination_system_id", "")) == Session.system_id()
		var pax := String(c.get("person_kind", "")) == "passenger"
		out["active"] = {"title": String(c.get("title", "")), "passengers": pax, "seats": int(c.get("seats", 0)),
				"tonnes": float(c.get("accepted_tonnes", c.get("offer", 0.0))), "pay": int(c.get("pay_total", 0)),
				"to": _dest_name(c), "arrived": arrived, "can_depart": at_start and not arrived and Session.depart_block() == "",
				"depart_why": Session.depart_block() if at_start and not arrived else "", "hard_burn": at_start and not arrived and c.has("due_hour"),
				"can_deliver": arrived and at_end, "camp": arrived and at_end and Session.surface_site() == "camp" and not pax,
				"can_cancel": Session.cancel_block() == "", "cancel_fee": Session.cancel_fee(),
				"due_in_h": int(c.due_hour) - int(Session.sim.hour) if c.has("due_hour") and Session.sim != null else -9999}
	var board := []
	if not Session.insolvent():
		if c.is_empty():
			for o in Contracts.offers_from(Session.system_id()):
				board.append(_offer_row(o, stats))
		for j in Session.people_here():   # passengers ride along, contract or not
			if c.is_empty() or String(j.get("person_kind", "")) == "passenger":
				board.append(_offer_row(j, stats))
		for j in Passengers.long_haul():
			board.append(_offer_row(j, stats))
	out["board"] = board
	out["passengers"] = Passengers.aboard().map(func(b: Dictionary) -> Dictionary:
		return {"who": String(b.person), "seats": int(b.seats), "to": String(b.dest_name), "beds": Passengers.beds_text(b.beds), "fare": int(b.fare),
				"late": Session.day() > int(b.get("due_day", 1 << 30))})
	var cands := []
	var free := Session.free_berths(stats) if not stats.is_empty() else 0
	var mult := float(SimShip.level(String(Session.profile.get("difficulty", "normal"))).get("wage_mult", 1.0))
	for p in Session.crew_candidates():
		cands.append({"id": String(p.id), "name": String(p.name), "species": String(Worlds.species(String(p.species)).name), "role": String(p.role),
				"role_name": Crew.role_name(String(p.role)), "skill": int(p.skill), "wage": roundi(float(p.wage) * mult),
				"fee": roundi(float(p.wage) * float(Crew.cfg().get("hire_fee_days", 1)) * mult), "line": String(p.line),
				"does": String(Crew.role(String(p.role)).get("does", ""))})
	var crew := []
	for p in Session.crew():
		crew.append({"id": String(p.id), "name": String(p.name), "role": String(p.role), "role_name": Crew.role_name(String(p.role)), "skill": int(p.skill),
				"wage": roundi(float(p.wage) * mult), "severance": roundi(float(p.wage) * float(Crew.cfg().get("severance_days", 2)) * mult),
				"does": String(Crew.role(String(p.role)).get("does", ""))})
	out["crew"] = crew
	out["candidates"] = cands
	out["free_berths"] = maxi(0, free)
	out["crew_needed"] = int(stats.get("crew_needed", 1))
	out["shop"] = {"repair": Session.repair_cost(), "overhaul": Session.overhaul_cost(), "patch_kit": Session.patch_kit_price(),
			"spares_kit": Session.spares_kit_price(), "hull": Session.hull(), "parts": Wear.summary(loaded.ship, Session.wear()) if not loaded.is_empty() else ""}
	var sc_lines := []
	for l in Salvage.cargo_aboard(loaded.get("manifest", null)):
		sc_lines.append("%.1f t of %s" % [float(l.tonnes), Salvage.clib().label(StringName(String(l.commodity))).to_lower()])
	var sp_lines := []
	for pt in Salvage.parts_aboard(loaded.get("manifest", null)):
		sp_lines.append(Salvage.describe(pt))
	out["authority"] = {"recorders": PortAuthority.recorders().size(), "recorder_cr": PortAuthority.recorder_total(),
			"remains": PortAuthority.remains().map(func(d: Dictionary) -> String: return String(d.name)), "recovery_cr": PortAuthority.recovery_total(),
			"rescued": PortAuthority.rescued().map(func(w: Dictionary) -> Dictionary: return {"name": String(w.name), "handed": bool(w.get("handed", false)), "role": Crew.role_name(String(w.role))}),
			"bounty": int(PortAuthority.cfg().get("rescue_bounty", 6000)), "reported": PortAuthority.reported().size(),
			"finder_cr": PortAuthority.finder_fee() * PortAuthority.reported().size()}
	out["salvage"] = {"cargo": sc_lines, "cargo_value": Salvage.cargo_value() if not sc_lines.is_empty() else 0,
			"parts": sp_lines, "parts_value": Salvage.parts_value() if not sp_lines.is_empty() else 0}
	out["can_wait"] = c.is_empty() and not Session.insolvent()
	return out


static func _dest_name(c: Dictionary) -> String:
	if bool(c.get("local", false)):
		return String(LocalSpace.node(String(c.get("destination_port_id", ""))).get("name", "the site"))
	return String(Worlds.port(String(c.get("destination_port_id", ""))).get("name", String(c.get("destination_system_id", ""))))


static func _offer_row(o: Dictionary, stats: Dictionary) -> Dictionary:
	var pax := String(o.get("person_kind", "")) == "passenger"
	var local := bool(o.get("local", false))
	var row := {"id": String(o.get("id", "")), "kind": String(o.get("person_kind", "")) if o.has("person_kind") else ("surface" if bool(o.get("surface", false)) else ("local" if local else "freight")),
			"what": "%d seat%s" % [int(o.seats), "" if int(o.seats) == 1 else "s"] if pax else String(Worlds.commodity(String(o.get("commodity", ""))).get("name", o.get("commodity", ""))),
			"to": _dest_name(o), "tonnes": 0.0 if pax else float(o.get("offer", 0.0)),
			"pay": maxi(Passengers.fare_now(o, stats), int(o.get("per_seat", 0)) * int(o.get("seats", 1))) if pax else roundi(float(o.get("offer", 0.0)) * float(o.get("rate", 0.0))),
			"time": "%d h" % int(o.get("hours", 0)) if local else "%.2f ly" % float(o.get("distance_ly", 0.0)),
			"person": String(o.get("person", "")), "line": String(o.get("line", "")),
			"locked": String(o.get("locked", "")) if not pax or o.has("locked") or stats.is_empty() else Passengers.why_not(o, stats)}
	if local and not stats.is_empty() and not pax:
		row["fuel"] = roundi(float(Session.local_trip_cost(stats, float(o.get("offer", 0.0)), float(o.get("dv_kms", 0.0))).total))
	return row


## Do one desk thing. `id` is the offer or person it's about.
static func port_command(action: String, id: String) -> Dictionary:
	match action:
		"accept":
			for o in Contracts.offers_from(Session.system_id()) + Session.people_here() + Passengers.long_haul():
				if String(o.get("id", "")) == id:
					return Session.accept_contract(o)
			return {"ok": false, "message": "That job's gone. Someone quicker took it."}
		"depart":
			return Session.depart_active_contract()
		"hard_burn":
			return Session.depart_active_contract(true)
		"deliver":
			return Session.deliver_active_contract()
		"cancel":
			return Session.cancel_contract()
		"wait":
			return Session.wait_days(1)
		"hire":
			return Session.hire(id)
		"fire":
			return Session.fire(id)
		"buy_patch_kit":
			return Session.buy_patch_kits(1)
		"buy_spares_kit":
			return Session.buy_spares_kit()
		"repair":
			return Session.repair_hull()
		"overhaul":
			return Session.overhaul_parts()
		"sell_cargo":
			return Salvage.sell("cargo")
		"sell_parts":
			return Salvage.sell("parts")
		"hand_in_recorders":
			return PortAuthority.hand_in_recorders()
		"hand_over_remains":
			return PortAuthority.hand_over_remains()
		"hand_over":
			return PortAuthority.hand_over(int(id))
		"sign_on":
			return PortAuthority.sign_on(int(id))
		"see_off":
			return PortAuthority.see_off(int(id))
		"collect_finders":
			return PortAuthority.collect_finders()
	return {"ok": false, "message": "The desks don't do that."}


## Keep the game's own screen honest after the phone changed something: the open desk redraws, and
## when the ship has moved or a day has passed the place rebuilds around you.
static func _after_port(scene: Node, action: String, r: Dictionary) -> void:
	if scene == null or not bool(r.get("ok", false)):
		return
	if action in ["depart", "hard_burn", "wait", "deliver", "cancel"] and scene.is_inside_tree():
		Session.flash = String(r.get("message", ""))
		scene.get_tree().reload_current_scene.call_deferred()
	elif scene.has_method("_refill"):
		scene._refill()


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
