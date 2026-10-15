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
	f.model.braking = false
	r = await _http(HTTPClient.METHOD_GET, "/api/state", "", token)
	var stt: Dictionary = r.json.get("status", {})
	check((stt.get("parts", []) as Array).size() > 0 and stt.has("patch_kits") and stt.has("crew"), "the ship panel: parts, kits and crew (%d parts)" % (stt.get("parts", []) as Array).size())
	r = await _http(HTTPClient.METHOD_POST, "/api/cmd", JSON.stringify({"action": "retro", "value": 1}), token)
	check(not r.json.get("ok", true) and String(r.json.get("message", "")).contains("No braking thrusters"), "no braking thrusters fitted: the remote says so")
	f.model.retro_kn = 20.0
	f.model.rcs_x_kn = 10.0
	f.model.rcs_y_kn = 10.0
	r = await _http(HTTPClient.METHOD_POST, "/api/cmd", JSON.stringify({"action": "retro", "value": 1}), token)
	f._process(0.05)
	check(r.json.get("ok", false) and f.model.retro > 0.0, "holding the braking thrusters fires them (%.2f)" % f.model.retro)
	await _http(HTTPClient.METHOD_POST, "/api/cmd", JSON.stringify({"action": "retro", "value": 0}), token)
	f._process(0.05)
	check(f.model.retro == 0.0, "letting go stops them")
	await _http(HTTPClient.METHOD_POST, "/api/cmd", JSON.stringify({"action": "slide_left", "value": 1}), token)
	f._process(0.05)
	check(f.model.strafe.x < 0.0, "the slide pad fires the manoeuvring thrusters (%.2f)" % f.model.strafe.x)
	f.remote_slide_until = 0.0
	var t_end := Time.get_ticks_msec() + 700
	await _http(HTTPClient.METHOD_POST, "/api/cmd", JSON.stringify({"action": "retro", "value": 1}), token)
	while Time.get_ticks_msec() < t_end:
		await process_frame
	f._process(0.05)
	check(f.model.retro == 0.0, "and a hold that stops arriving runs out by itself (the phone lost signal)")
	r = await _http(HTTPClient.METHOD_POST, "/api/cmd", JSON.stringify({"action": "jump"}), token)
	check(not r.json.get("ok", true) and String(r.json.get("message", "")).contains("No jump"), "no jump planned on a run: %s" % r.json.get("message", ""))
	print("a space walk")
	f.model.throttle = 0.0
	f.get_up()
	f.walk.stand_in_airlock()
	f.use()
	r = await _http(HTTPClient.METHOD_GET, "/api/state", "", token)
	var eva: Dictionary = r.json.get("eva", {})
	check(f.eva != null and float(eva.get("air", 0.0)) > 0.0 and eva.has("tether_left") and eva.has("strain"), "out on the tether: air, tether and strain on the phone")
	r = await _http(HTTPClient.METHOD_POST, "/api/cmd", JSON.stringify({"action": "reel_in"}), token)
	check(r.json.get("ok", false) and f.eva == null, "reel me in: back aboard")
	r = await _http(HTTPClient.METHOD_POST, "/api/cmd", JSON.stringify({"action": "accept", "id": "x"}), token)
	check(not r.json.get("ok", true) and String(r.json.get("message", "")).contains("berth"), "desk business waits until you're berthed: %s" % r.json.get("message", ""))
	f.queue_free()
	await process_frame
	Session.flight_job = {}

	print("in port")
	Session.begin_new(2, "Pilot", "human", "normal", "roosevelt_independent_yards")
	var data := SaveSlots.read(Session.slot)
	var cabin := ShipData.new(ModuleLibrary.new())
	ShipPresets.build(cabin, ShipPresets.STARTER_CABIN)
	data["modules"] = (JSON.parse_string(cabin.to_json()) as Dictionary)["modules"]
	data["cargo"] = CargoManifest.new(cabin).to_dict()
	SaveSlots.write(Session.slot, data)
	Session.profile["hints_seen"] = ["welcome", "money", "crew"]
	Session.save_profile()
	var pl: Node = load(Session.PLACE_SCENE).instantiate()
	root.add_child(pl)
	current_scene = pl
	await process_frame
	r = await _http(HTTPClient.METHOD_GET, "/api/state", "", token)
	var port: Dictionary = r.json.get("port", {})
	check(r.json.get("scene", "") == "port" and (port.get("board", []) as Array).size() > 0 and (port.get("candidates", []) as Array).size() == 4 and r.json.has("status"),
			"berthed: the freight board, the bar and the ship panel (%d jobs)" % (port.get("board", []) as Array).size())
	var cand: Dictionary = port.candidates[0]
	r = await _http(HTTPClient.METHOD_POST, "/api/cmd", JSON.stringify({"action": "hire", "id": String(cand.id)}), token)
	check(r.json.get("ok", false) and Session.crew().size() == 1, "hire from the phone: %s" % r.json.get("message", ""))
	r = await _http(HTTPClient.METHOD_GET, "/api/state", "", token)
	check((r.json.status.crew as Array).size() == 1 and String(r.json.status.crew[0].doing).begins_with("Ashore"), "and they're on the crew list, ashore")
	r = await _http(HTTPClient.METHOD_POST, "/api/cmd", JSON.stringify({"action": "fire", "id": String(cand.id)}), token)
	check(r.json.get("ok", false) and Session.crew().is_empty(), "let go from the phone: %s" % r.json.get("message", ""))
	var kits := Session.patch_kits()
	r = await _http(HTTPClient.METHOD_POST, "/api/cmd", JSON.stringify({"action": "buy_patch_kit"}), token)
	check(r.json.get("ok", false) and Session.patch_kits() == kits + 1, "buy a patch kit")
	var job := {}
	for o in port.board:
		if String(o.get("kind", "")) in ["local", "freight"] and String(o.get("locked", "")) == "":
			job = o
			break
	r = await _http(HTTPClient.METHOD_POST, "/api/cmd", JSON.stringify({"action": "accept", "id": String(job.get("id", ""))}), token)
	check(r.json.get("ok", false) and not Session.active_contract().is_empty(), "take a job off the board: %s" % r.json.get("message", ""))
	r = await _http(HTTPClient.METHOD_GET, "/api/state", "", token)
	var active: Dictionary = r.json.port.get("active", {})
	check(bool(active.get("can_depart", false)) and (r.json.port.board as Array).all(func(o): return String(o.get("kind", "")) == "passenger"), "with a load aboard, the board gives way to the run (passengers can still ride along): depart on autopilot")
	var where0 := String(Session.profile.port_id)
	r = await _http(HTTPClient.METHOD_POST, "/api/cmd", JSON.stringify({"action": "depart"}), token)
	check(r.json.get("ok", false) and String(Session.profile.port_id) != where0, "depart from the phone: %s" % r.json.get("message", ""))
	for i in 4:
		await process_frame
	pl = current_scene
	r = await _http(HTTPClient.METHOD_POST, "/api/cmd", JSON.stringify({"action": "deliver"}), token)
	check(r.json.get("ok", false) and Session.active_contract().is_empty(), "and deliver: %s" % r.json.get("message", ""))
	for i in 4:
		await process_frame
	Session.profile["location"] = "shipyard"
	r = await _http(HTTPClient.METHOD_POST, "/api/cmd", JSON.stringify({"action": "wait"}), token)
	check(not r.json.get("ok", true), "not from the shipyard")
	Session.profile["location"] = "dock"
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
