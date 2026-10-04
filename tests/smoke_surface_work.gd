extends SceneTree
## Work on foot: buying suit gear, taking a timed surface mission at the hab and doing it outside, a
## drill fixed by holding E, running out of time and out of air, the suit jets and scanner, and
## unloading at the camp by hand or by the camp crew.
## Run: godot --headless --path . --script res://tests/smoke_surface_work.gd
var fails := 0
func check(ok: bool, msg: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + msg)
	if not ok:
		fails += 1
func _initialize() -> void:
	SaveSlots.dir = "user://test_saves_surface_work"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SaveSlots.dir))
	process_frame.connect(_run, CONNECT_ONE_SHOT)
func _fit(preset: Array) -> void:
	var data := SaveSlots.read(Session.slot)
	var ship := ShipData.new(ModuleLibrary.new())
	ShipPresets.build(ship, preset)
	data["modules"] = (JSON.parse_string(ship.to_json()) as Dictionary)["modules"]
	data["cargo"] = CargoManifest.new(ship).to_dict()
	SaveSlots.write(Session.slot, data)
	SimWorld.sync(Session.sim, Session.profile, ship)
func _outside() -> Node:
	Session.flight_job = {}
	Session.suit_up = true
	var f: Node = load(Session.FLIGHT_SCENE).instantiate()
	root.add_child(f)
	await process_frame
	await process_frame
	return f
func _close(f: Node) -> void:
	f.queue_free()
	await process_frame
func _goto(f: Node, x: float, z: float) -> void:
	f.suit.place(Vector3(x + 0.4, 0, z))
func _key(code: int, down: bool) -> void:
	var k := InputEventKey.new()
	k.keycode = code
	k.physical_keycode = code
	k.pressed = down
	Input.parse_input_event(k)
	Input.flush_buffered_events()
func _find_mission(kind: String) -> Dictionary:
	for i in 40:
		for m in Session.missions_here():
			if String(m.kind) == kind and not bool(m.taken):
				return m
		Session.wait_days(1)
	return {}
func _run() -> void:
	Session.begin_new(2, "Pilot", "human", "normal", "roosevelt_independent_yards")
	_fit(ShipPresets.STARTER_LANDER)
	var sys := Session.system_id()
	Session.profile["port_id"] = sys + LocalSpace.SEP + "pad"
	Session.save_profile()
	# The store.
	check(not bool(Session.buy_gear("o2_2").ok), "twin tanks need the bigger tank first")
	var cr := int(Session.profile.credits)
	check(bool(Session.buy_gear("o2_1").ok) and int(Session.profile.credits) == cr - 4000, "bought the bigger air tank for 4,000 cr")
	check(bool(Session.buy_gear("scanner").ok) and bool(Session.buy_gear("boots").ok), "bought a scanner and grip boots")
	check(not bool(Session.buy_gear("scanner").ok), "a second scanner is refused")
	# A mission at the pad.
	var ms := Session.missions_here()
	check(not ms.is_empty(), "the hab posts surface work (%d)" % ms.size())
	var m := _find_mission("survey")
	check(not m.is_empty(), "a survey turns up")
	var r := Session.take_mission(m)
	check(bool(r.ok) and not Session.mission().is_empty(), "taken: %s" % r.message)
	var f: Node = await _outside()
	check(f.outside and f.ops != null, "suiting up puts you outside")
	check(is_equal_approx(f.ops.o2_max, 1500.0), "the bigger tank gives 25 minutes of air (%.0f s)" % f.ops.o2_max)
	check(is_equal_approx(f.suit.speed_mult, 1.3), "grip boots: 30% faster")
	check(not f.ops.scan().is_empty(), "the scanner points to the mission: %s" % [f.ops.scan()])
	check(f.ops.point_nodes.size() == 3, "three survey points are marked")
	cr = int(Session.profile.credits)
	var rep := int(Session.profile.get("rep", 0))
	var pts: Array = m.points
	for p in pts:
		_goto(f, float(p[0]), float(p[1]))
		f.ops.step(0.5, false)
		f.ops.use()
	check(Session.mission().is_empty(), "all three beacons set: %s" % f.ops.message)
	check(int(Session.profile.credits) == cr + int(m.pay) and int(Session.profile.rep) == rep + 2, "paid %d cr and standing +2" % int(m.pay))
	# Out of time.
	var m2 := _find_mission("rescue")
	if m2.is_empty():
		m2 = _find_mission("survey")
	Session.take_mission(m2)
	f.ops.begin_outing()
	rep = int(Session.profile.rep)
	for i in 10:
		f.ops.step(float(m2.limit_s) / 9.0, false)
	check(Session.mission().is_empty() and int(Session.profile.rep) == maxi(0, rep - 2), "the clock runs out: %s" % f.ops.message)
	# Out of air.
	f.ops.begin_outing()
	_goto(f, 200.0, 200.0)
	cr = int(Session.profile.credits)
	f.ops.o2 = 0.05
	f.ops.step(0.1, false)
	check(not f.outside and int(Session.profile.credits) == cr - 800, "out of air: dragged aboard for 800 cr")
	await _close(f)
	# Jets.
	Session.buy_gear("jetpack")
	f = await _outside()
	_goto(f, 60.0, 60.0)
	f.suit.step(0.05, Vector2.ZERO, false, true, false)
	var plain := 0.0
	for i in 200:
		f.suit.step(0.05, Vector2.ZERO)
		plain = maxf(plain, f.suit.pos.y - f.model.terrain.height(f.suit.pos.x, f.suit.pos.z))
	f.suit.step(0.05, Vector2.ZERO, false, true, true)
	var jet := 0.0
	for i in 300:
		f.suit.step(0.05, Vector2.ZERO, false, true, true)
		jet = maxf(jet, f.suit.pos.y - f.model.terrain.height(f.suit.pos.x, f.suit.pos.z))
	check(jet > plain * 3.0 and f.suit.jet_fuel <= 0.0, "suit jets: %.1f m up against %.1f m for a jump, then empty" % [jet, plain])
	await _close(f)
	# The camp: a drill, and unloading.
	Session.profile["port_id"] = sys + LocalSpace.SEP + "camp"
	Session.save_profile()
	var drill := _find_mission("drill")
	check(not drill.is_empty(), "the camp foreman posts a stalled drill")
	if not drill.is_empty():
		Session.take_mission(drill)
		f = await _outside()
		check(f.ops.site == "camp" and f.ops.point_nodes.size() == 1, "the drill is marked at the camp")
		_goto(f, float(drill.points[0][0]), float(drill.points[0][1]))
		cr = int(Session.profile.credits)
		_key(KEY_E, true)
		for i in 60:
			f.ops.step(0.1, false)
		_key(KEY_E, false)
		check(Session.mission().is_empty() and int(Session.profile.credits) == cr + int(drill.pay), "holding E for five seconds frees it: %s" % f.ops.message)
		await _close(f)
	# Unloading by hand.
	Session.profile["port_id"] = sys + LocalSpace.SEP + "pad"
	Session.save_profile()
	var job: Dictionary = {}
	for i in 30:
		for o in Contracts.offers_from(sys):
			if String(o.destination_port_id) == sys + LocalSpace.SEP + "camp":
				job = o
		if not job.is_empty():
			break
		Session.wait_days(1)
	check(not job.is_empty(), "a run from the pad to the camp")
	if not job.is_empty():
		Session.accept_contract(job)
		var c := Session.active_contract()
		Session.depart_active_contract()
		check(Session.surface_site() == "camp", "at the camp with the load")
		r = Session.start_manual_unload()
		var n := SurfaceWork.crates_for(float(c.accepted_tonnes))
		check(bool(r.ok) and int(Session.unloading().crates) == n, "%d crates to carry" % n)
		f = await _outside()
		cr = int(Session.profile.credits)
		var hour: int = Session.sim.hour
		var d := SurfaceWork.drop_xz()
		for i in n:
			f.suit.place(f.suit_hatch)
			f.ops.use()
			if i == 0:
				check(f.ops.carrying and is_equal_approx(f.suit.speed_mult, 1.3 * 0.6) and not f.suit.can_jump, "a crate in your arms: slower, no jumping")
			_goto(f, d.x, d.y)
			f.ops.use()
		check(Session.active_contract().is_empty() and Session.unloading().is_empty(), "the last crate delivers the load: %s" % f.ops.message)
		var full := int(c.pay_total) + roundi(int(c.pay_total) * 0.25)
		check(int(Session.profile.credits) - cr == full and Session.sim.hour == hour, "full pay with the surface bonus, and no hours lost (%d cr)" % (int(Session.profile.credits) - cr))
		await _close(f)
	# The crew instead.
	Session.profile["port_id"] = sys + LocalSpace.SEP + "pad"
	Session.save_profile()
	job = {}
	for i in 30:
		for o in Contracts.offers_from(sys):
			if String(o.destination_port_id) == sys + LocalSpace.SEP + "camp":
				job = o
		if not job.is_empty():
			break
		Session.wait_days(1)
	if not job.is_empty():
		Session.accept_contract(job)
		var c := Session.active_contract()
		Session.depart_active_contract()
		var hour: int = Session.sim.hour
		r = Session.deliver_active_contract()
		var gross := int(c.pay_total) + roundi(int(c.pay_total) * 0.25)
		var fee := roundi(gross * 0.15)
		check(int(r.payment) == gross - fee and Session.sim.hour - hour >= 8, "the camp crew take %d cr and 8 hours: %s" % [fee, r.message])
	print("DONE fails=", fails)
	quit(1 if fails > 0 else 0)
