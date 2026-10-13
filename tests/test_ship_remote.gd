extends SceneTree
## The ship remote (ShipRemote): off unless switched on; serves the page; only to devices on this
## network; pairs with the code (and locks out after five wrong ones); a new code unpairs everyone;
## and its commands go through the cockpit's own controls with the same rules.
## Run: godot --headless --path . --script res://tests/test_ship_remote.gd
var fails := 0
func check(ok: bool, msg: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + msg)
	if not ok:
		fails += 1
func _initialize() -> void:
	SaveSlots.dir = "user://test_saves_ship_remote_%d" % OS.get_process_id()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SaveSlots.dir))
	process_frame.connect(_run, CONNECT_ONE_SHOT)


## One HTTP request to the remote in this same process, pumping frames so the server can answer.
func _http(method: int, path: String, body := "", token := "") -> Dictionary:
	var c := HTTPClient.new()
	c.connect_to_host("127.0.0.1", ShipRemote.PORT)
	for i in 200:
		c.poll()
		if c.get_status() == HTTPClient.STATUS_CONNECTED:
			break
		await process_frame
	var headers := PackedStringArray(["Content-Type: application/json"])
	if token != "":
		headers.append("X-Remote-Token: " + token)
	c.request(method, path, headers, body)
	var out := PackedByteArray()
	for i in 400:
		c.poll()
		var st := c.get_status()
		if st == HTTPClient.STATUS_BODY:
			out.append_array(c.read_response_body_chunk())
		elif st != HTTPClient.STATUS_REQUESTING and c.has_response() and st != HTTPClient.STATUS_BODY:
			break
		elif st == HTTPClient.STATUS_DISCONNECTED or st == HTTPClient.STATUS_CONNECTION_ERROR:
			break
		await process_frame
	var text := out.get_string_from_utf8()
	var parsed = JSON.parse_string(text)
	return {"code": c.get_response_code(), "text": text, "json": parsed if typeof(parsed) == TYPE_DICTIONARY else {}}


func _run() -> void:
	check(GameSettings.DEFAULTS.remote == false, "the remote is off by default")
	check(ShipRemote.is_local("192.168.1.20") and ShipRemote.is_local("10.0.0.5") and ShipRemote.is_local("172.20.1.1")
			and ShipRemote.is_local("127.0.0.1") and ShipRemote.is_local("::ffff:192.168.0.3") and ShipRemote.is_local("fe80::1"),
			"private, loopback and link-local addresses count as this network")
	check(not ShipRemote.is_local("8.8.8.8") and not ShipRemote.is_local("172.32.0.1") and not ShipRemote.is_local("2001:db8::1"),
			"public addresses don't")
	GameSettings.set_value("remote", true)
	GameSettings.set_value("remote_code", "135790")
	Session.begin_new(2, "Pilot", "human", "normal", "roosevelt_independent_yards")
	Session.profile["system_id"] = "sol"
	Session.profile["port_id"] = String(Worlds.primary_port("sol").id)
	var dest := LocalSpace.node("sol__saturn")
	Session.flight_job = {"kind": "run", "contract_id": "remote", "dv_kms": 8.0, "hours": 96, "destination": String(dest.name), "key": "remote",
			"dest_kind": "saturn", "dest_id": "sol__saturn", "origin_kind": "port", "origin_id": String(Session.profile.port_id), "system_id": "sol"}
	var f: Node = load(Session.FLIGHT_SCENE).instantiate()
	root.add_child(f)
	current_scene = f
	await process_frame
	await process_frame
	check(ShipRemote.instance != null and ShipRemote.instance.status == "", "switched on, it starts with the flight (%s)" % (ShipRemote.instance.status if ShipRemote.instance else "none"))
	f.phase = "cruise"
	f.model.pos = f.xfer.target * 0.3
	f.model.vel = (f.xfer.target - f.model.pos).normalized() * 500.0
	f.model.basis = Basis(Vector3.UP, 0.6) * Basis.looking_at(f.xfer.target - f.model.pos)   # 34 degrees off
	var page: Dictionary = await _http(HTTPClient.METHOD_GET, "/")
	check(page.code == 200 and String(page.text).contains("Ship remote"), "it serves the page")
	var r: Dictionary = await _http(HTTPClient.METHOD_GET, "/api/state")
	check(r.code == 401, "the state needs pairing first (%d)" % r.code)
	r = await _http(HTTPClient.METHOD_POST, "/api/pair", JSON.stringify({"code": "000000"}))
	check(r.code == 403, "a wrong code is refused (%d)" % r.code)
	r = await _http(HTTPClient.METHOD_POST, "/api/pair", JSON.stringify({"code": "135790"}))
	var token := String(r.json.get("token", ""))
	check(r.code == 200 and token == ShipRemote.token_for("135790"), "the right code pairs and gives a token")
	r = await _http(HTTPClient.METHOD_GET, "/api/state", "", token)
	check(r.code == 200 and r.json.get("scene", "") == "flight" and r.json.has("run") and r.json.has("throttle") and r.json.has("prompt"),
			"paired, it gets the flight: gauges, the run and the prompt")
	r = await _http(HTTPClient.METHOD_GET, "/api/chart", "", token)
	check(r.code == 200 and (r.json.get("sites", []) as Array).size() == LocalSpace.nodes("sol").size(), "and the system chart")
	r = await _http(HTTPClient.METHOD_GET, "/api/chart?view=space", "", token)
	check(r.code == 200 and (r.json.get("systems", []) as Array).size() == Worlds.system_ids().size(), "and known space")
	r = await _http(HTTPClient.METHOD_POST, "/api/cmd", JSON.stringify({"action": "throttle", "value": 0.6}), token)
	check(r.json.get("ok", false) and is_equal_approx(f.model.throttle, 0.6), "the lever sets the throttle (%.2f)" % f.model.throttle)
	r = await _http(HTTPClient.METHOD_POST, "/api/cmd", JSON.stringify({"action": "course"}), token)
	check(not f.model.course_hold and String(r.json.get("message", "")).contains("5°"), "course hold follows the game: 34° off, refused (%s)" % r.json.get("message", ""))
	r = await _http(HTTPClient.METHOD_POST, "/api/cmd", JSON.stringify({"action": "dock"}), token)
	check(not r.json.get("ok", true) and not f.leaving, "docking out of range is refused")
	r = await _http(HTTPClient.METHOD_POST, "/api/cmd", JSON.stringify({"action": "brake"}), token)
	check(f.model.braking, "brake engages the braking autopilot")
	var before := int(f.warp_index)
	r = await _http(HTTPClient.METHOD_POST, "/api/cmd", JSON.stringify({"action": "warp_up"}), token)
	check(f.warp_index == before + 1 and f._warp() <= int(f._warp_limit().max), "time compression goes up, inside the game's cap")
	ShipRemote.new_code()
	r = await _http(HTTPClient.METHOD_GET, "/api/state", "", token)
	check(r.code == 401, "a new code unpairs the old token (%d)" % r.code)
	for i in 5:
		await _http(HTTPClient.METHOD_POST, "/api/pair", JSON.stringify({"code": "999999"}))
	r = await _http(HTTPClient.METHOD_POST, "/api/pair", JSON.stringify({"code": ShipRemote.code()}))
	check(r.code == 429, "five wrong codes lock the address out for a minute, even with the right one after (%d)" % r.code)
	GameSettings.set_value("remote", false)
	ShipRemote.sync(self)
	await process_frame
	check(ShipRemote.instance == null, "switched off, it stops")
	print("fails=%d" % fails)
	quit(1 if fails > 0 else 0)
