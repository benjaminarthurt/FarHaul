extends SceneTree
## Walking the port: the concourse builds with its desks, walls stop you, the freight desk takes a job,
## the fuel desk repairs the hull at the port's rate, the pad's hab has a survey lab that pays more for
## samples, and the camp's hut has a foreman and an exchange.
## Run: godot --headless --path . --script res://tests/smoke_place.gd
var fails := 0
func check(ok: bool, msg: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + msg)
	if not ok:
		fails += 1
func _initialize() -> void:
	SaveSlots.dir = "user://test_saves_place"
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
func _open() -> Node:
	var p: Node = load(Session.PLACE_SCENE).instantiate()
	root.add_child(p)
	await process_frame
	await process_frame
	return p
func _close(p: Node) -> void:
	p.queue_free()
	await process_frame
func _ids(p: Node) -> Array:
	var out := []
	for d in p.desks:
		out.append(String(d.id))
	return out
func _buttons(p: Node) -> Array:
	var out := []
	for c in p.panel_list.get_children():
		if c is Button and not c.is_queued_for_deletion():
			out.append(c)
	return out
func _stand_at(p: Node, id: String) -> void:
	for d in p.desks:
		if String(d.id) == id:
			p.walker.pos = Vector3(d.pos.x, 0, d.pos.z)
## Standing people are solid too (a rect 0.6 m square around them); strollers may brush past those.
func _is_person_rect(p: Node, r: Rect2) -> bool:
	return is_equal_approx(r.size.x, 0.6) and is_equal_approx(r.size.y, 0.6)
func _run() -> void:
	Session.begin_new(2, "Pilot", "human", "normal", "roosevelt_independent_yards")
	check(Session.scene_path() == Session.PLACE_SCENE, "the dock is now the walkable place")
	var p: Node = await _open()
	check(p.kind == "concourse", "a port has a concourse")
	var ids := _ids(p)
	for want in ["freight", "fuel", "yard", "bar", "terminal", "gate"]:
		check(want in ids, "the concourse has a %s desk" % want)
	# Walls hold.
	var start: Vector3 = p.walker.pos
	p.walker.face(Vector3(-1, 0, 0))
	for i in 200:
		p.walker.step(0.05, Vector2(0, 1), true)
	check(p.walker.pos.x > -22.0 and p.walker.pos.x < start.x, "the end wall stops you (x %.2f)" % p.walker.pos.x)
	# Travellers walk about, and their paths stay clear of the furniture.
	check(p.strollers.size() == 3, "three travellers walk the concourse")
	var f0: Figure = p.strollers[0].fig
	var p0: Vector3 = f0.position
	var blocked := false
	p.walker.pos = Vector3(-20.5, 0, 6.0)   # out of their way
	for i in 600:
		p._move_strollers(0.05)
		for st in p.strollers:
			var q: Vector3 = st.fig.position
			for r in p.walker.furniture[0]:
				if (r as Rect2).grow(-0.05).has_point(Vector2(q.x, q.z)) and not _is_person_rect(p, r):
					blocked = true
	check(f0.position.distance_to(p0) > 1.0, "they move (%.1f m in 30 s)" % f0.position.distance_to(p0))
	check(not blocked, "no one walks through a desk, bench or planter")
	# People at the bar.
	p.use_desk("bar")
	await process_frame
	var asks := 0
	for b in _buttons(p):
		for k in ["RUSH", "PASSENGER", "SEALED"]:
			if String(b.text).begins_with(k):
				asks += 1
	check(asks == Session.people_here().size() and asks > 0, "%d people ask for work at the bar" % asks)
	p.close_desk()
	# Desks in reach.
	_stand_at(p, "freight")
	check(String(p.desk_in_reach().get("id", "")) == "freight", "standing at the freight office brings it in reach")
	p.use_desk("freight")
	await process_frame
	var jobs := 0
	for b in _buttons(p):
		if String(b.text).begins_with("LOCAL") or String(b.text).begins_with("SURFACE"):
			jobs += 1
	check(p.panel.visible and jobs > 0, "the freight office lists %d jobs" % jobs)
	var first: Button = null
	for b in _buttons(p):
		if String(b.text).begins_with("LOCAL"):
			first = b
			break
	if first != null:
		first.pressed.emit()
		await process_frame
	check(not Session.active_contract().is_empty(), "taking a job at the desk makes it the active contract")
	var acts := []
	for b in _buttons(p):
		acts.append(String(b.text))
	check("FLY THE RUN YOURSELF" in acts and "DEPART ON AUTOPILOT" in acts, "the desk then offers to fly it or send it (%s)" % [acts])
	p.close_desk()
	# Repairs.
	Session.profile["hull_damage"] = 0.3
	var cost := Session.repair_cost()
	check(cost > 0, "a damaged hull costs %d cr to fix here" % cost)
	var before := int(Session.profile.credits)
	p.use_desk("fuel")
	await process_frame
	var fix: Button = null
	for b in _buttons(p):
		if String(b.text).begins_with("REPAIR"):
			fix = b
	check(fix != null and not fix.disabled, "the fuel desk offers the repair")
	if fix != null:
		fix.pressed.emit()
		await process_frame
	check(float(Session.profile.get("hull_damage", 1.0)) == 0.0 and int(Session.profile.credits) == before - cost, "the repair is paid for (%d → %d cr)" % [before, int(Session.profile.credits)])
	check(String(p.panel_status.text).begins_with("Hull repaired"), "the desk says so")
	var gate_acts := []
	p.use_desk("gate")
	await process_frame
	for b in _buttons(p):
		gate_acts.append(String(b.text))
	check("FLY THE RUN" in gate_acts and "TAKE THE HELM" in gate_acts and "GO ABOARD AND WALK THE SHIP" in gate_acts, "the gate leads aboard (%s)" % [gate_acts])
	p.close_desk()
	await _close(p)
	# Through the gate and aboard on foot.
	Session.flight_job = {}
	Session.walk_aboard = true
	var f: Node = load(Session.FLIGHT_SCENE).instantiate()
	root.add_child(f)
	await process_frame
	await process_frame
	check(f.walking and not Session.walk_aboard, "going aboard puts you on your feet in the ship")
	f.queue_free()
	await process_frame
	# Site prices.
	var sys := Session.system_id()
	check(Session.site_fuel_mult(sys + LocalSpace.SEP + "camp") > Session.site_fuel_mult(String(Session.profile.port_id)), "fuel at the camp costs more than at the port")
	# The pad's hab.
	_fit(ShipPresets.STARTER_LANDER)
	Session.profile["contract"] = {}
	Session.profile["port_id"] = sys + LocalSpace.SEP + "pad"
	Session.profile["samples"] = 3
	Session.profile["salvage"] = 1
	Session.save_profile()
	p = await _open()
	check(p.kind == "hab", "the base pad has the hab")
	ids = _ids(p)
	for want in ["dispatch", "lab", "store", "fuel", "terminal", "gate"]:
		check(want in ids, "the hab has a %s desk" % want)
	before = int(Session.profile.credits)
	p.use_desk("lab")
	await process_frame
	for b in _buttons(p):
		if String(b.text).begins_with("SELL"):
			b.pressed.emit()
	await process_frame
	var lab_paid := int(Session.profile.credits) - before
	check(lab_paid == roundi(3 * SurfaceFinds.value("sample") * 1.4), "the lab pays 1.4 times for samples (%d cr)" % lab_paid)
	check(int(Session.profile.get("salvage", 0)) == 1, "the lab leaves the salvage in the locker")
	p.close_desk()
	p.use_desk("store")
	await process_frame
	var gear := 0
	for b in _buttons(p):
		if not String(b.text).begins_with("CLOSE"):
			gear += 1
	check(gear == SurfaceWork.GEAR_ORDER.size(), "the suit store sells %d pieces of kit" % gear)
	_buttons(p)[0].pressed.emit()
	await process_frame
	check("o2_1" in Session.gear_owned(), "buying the bigger air tank at the store: %s" % p.panel_status.text)
	p.close_desk()
	p.use_desk("dispatch")
	await process_frame
	var work := 0
	for b in _buttons(p):
		for k in ["PLACE SURVEY", "REACH A SURVEYOR", "FIX A STALLED"]:
			if String(b.text).begins_with(k):
				work += 1
	check(work == Session.missions_here().size() and work > 0, "dispatch posts %d surface missions" % work)
	p.close_desk()
	p.use_desk("gate")
	await process_frame
	var suit := false
	for b in _buttons(p):
		suit = suit or String(b.text).begins_with("SUIT UP")
	check(suit, "the airlock offers to suit up and go outside")
	p.close_desk()
	await _close(p)
	# The camp's hut.
	Session.profile["port_id"] = sys + LocalSpace.SEP + "camp"
	Session.save_profile()
	p = await _open()
	check(p.kind == "hut", "the camp has the foreman's hut")
	ids = _ids(p)
	for want in ["foreman", "exchange", "terminal", "gate"]:
		check(want in ids, "the hut has its %s" % want)
	before = int(Session.profile.credits)
	p.use_desk("exchange")
	await process_frame
	for b in _buttons(p):
		if String(b.text).begins_with("SELL"):
			b.pressed.emit()
	await process_frame
	check(int(Session.profile.credits) - before == roundi(SurfaceFinds.value("salvage") * 0.9), "the exchange buys the salvage cheaply")
	await _close(p)
	print("DONE fails=", fails)
	quit(1 if fails > 0 else 0)
