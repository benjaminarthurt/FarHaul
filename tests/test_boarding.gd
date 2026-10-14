extends SceneTree
## Boarding derelicts (Wreckage, Boarding, Salvage.stow, PortAuthority): what's aboard and the log, the
## airlock door cut with the torch, walking the dark wreck, carrying out the flight recorder and the
## dead, survivors needing a berth, and handing it all in at a port.
## Run: godot --headless --path . --script res://tests/test_boarding.gd
var fails := 0
func check(ok: bool, msg: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + msg)
	if not ok:
		fails += 1


func _initialize() -> void:
	SaveSlots.dir = "user://test_saves_boarding_%d" % OS.get_process_id()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SaveSlots.dir))
	process_frame.connect(_run, CONNECT_ONE_SHOT)


var f: Node
var t: Traffic


func _point(id: String) -> Dictionary:
	for p in t.salvage_points():
		if String(p.id) == id:
			return p
	return {}


## Up to point `id`, 14 m out from our hatch, and work it with `tool`.
func _work(id: String, tool: String) -> String:
	var p := _point(id)
	if p.is_empty():
		return "gone"
	var w: NpcShip = (p.derelict as Dictionary).ship
	var hatch_world: Vector3 = f.view.global_transform * f.eva.hatch
	w.global_position += (hatch_world + (hatch_world - f.model.pos).normalized() * 14.0) - (p.world as Vector3)
	p = _point(id)
	var to_view: Transform3D = f.view.global_transform.affine_inverse()
	f.eva.pos = to_view * (p.world as Vector3) + (f.eva.hatch - to_view * (p.world as Vector3)).normalized() * 1.0
	f.foot_c.eva_work(0.05, false)
	var r := ""
	for k in 600:
		r = f.foot_c.eva_work(0.05, true, tool)
		if r != "working":
			break
	f.foot_c.eva_work(0.05, false)
	return r


func _home() -> void:
	f.eva.pos = f.eva.hatch
	f.foot_c._stow_refused = ""
	f.foot_c._eva_step(0.05)


func _walk_to(b: Boarding, p: Vector3) -> void:
	b.walk.pos = p
	b.walk._resolve()


func _run() -> void:
	print("what's aboard")
	var lib := ModuleLibrary.new()
	var hauler := ShipData.new(lib)
	ShipPresets.build(hauler, ShipPresets.NPC_HAULER)
	var a := Wreckage.roll(hauler, "Cantor", false, "x|1")
	var b2 := Wreckage.roll(hauler, "Cantor", false, "x|1")
	check(JSON.stringify(a) == JSON.stringify(b2), "the same wreck holds the same every time")
	var items: Array = a.items
	check(items.filter(func(i): return String(i.kind) == "recorder").size() == 1, "a flight recorder")
	check(int(items.filter(func(i): return String(i.kind) == "recorder")[0].at) == int(a.helm), "at the helm")
	check((a.log as Array).size() >= 4, "and the log:\n      " + "\n      ".join(PackedStringArray(a.log)))
	var crates := items.filter(func(i): return String(i.kind) == "crate")
	check(not crates.is_empty() and crates.all(func(i): return lib.get_def(hauler.modules[int(i.at)].id).cargo_slots > 0), "crates in the holds")
	var survivors := 0
	var bodies := 0
	var deep_s := 0
	for k in 200:
		var r := Wreckage.roll(hauler, "Test", false, "near|%d" % k)
		survivors += (r.items as Array).filter(func(i): return String(i.kind) == "survivor").size()
		bodies += (r.items as Array).filter(func(i): return String(i.kind) == "body").size()
		deep_s += (Wreckage.roll(hauler, "Test", true, "deep|%d" % k).items as Array).filter(func(i): return String(i.kind) == "survivor").size()
	check(survivors > 0 and survivors < 40 and deep_s > survivors, "survivors are rare, and likelier on a ship stranded far out (%d near, %d deep, in 200)" % [survivors, deep_s])
	check(bodies > 50, "and most wrecks lost somebody (%d in 200)" % bodies)

	print("their door")
	Session.begin_new(1, "Tester", "human", "normal", "roosevelt_independent_yards")
	Session.flight_job = {}
	f = load(Session.FLIGHT_SCENE).instantiate()
	root.add_child(f)
	current_scene = f
	await process_frame
	f.set_process(false)
	t = f.traffic_c
	t.cfg["derelicts"]["chance"] = 1.0
	t.rebuild(String(Session.profile.port_id))
	var d: Dictionary = t.derelicts[0]
	var door := (d.points as Array).filter(func(p): return String(p.kind) == "door")
	check(door.size() == 1 and (door[0].marker as Node3D).visible, "every derelict has an airlock door, marked")
	var door_id := String(door[0].id)
	f.model.pos = Vector3(0, 0, 3000)
	f.model.vel = Vector3.ZERO
	f.model.ang = Vector3.ZERO
	f.model.basis = Basis()
	f._apply_pose()
	f.get_up()
	f.walk.stand_in_airlock()
	f.use()
	check(f.eva != null, "out on the tether")
	var res := _work(door_id, "wrench")
	check(res.contains("torch"), "the wrench won't open it: %s" % res)
	res = _work(door_id, "torch")
	check(res == "done" and (Session.profile.get("salvage_taken", []) as Array).has(door_id), "torched open, and the save knows")
	check(String(_point(door_id).kind) == "enter" and (door[0].open_mark as Node3D).visible, "now it's a way in")
	res = _work(door_id, "wrench")
	var bo: Boarding = f.foot_c.boarding
	check(bo.active and bo.walk != null and bo.walk.near_airlock(), "and in we go: standing in their airlock")
	f._apply_pose()
	check(f.camera.global_position.distance_to(bo.ship().body.global_transform * bo.walk.eye()) < 0.01, "looking out of our own eyes, inside their ship")
	check(bo.items.size() == (bo.contents.items as Array).size(), "everything's where they left it (%d things)" % bo.items.size())
	var lit := 0
	for c in bo.view.get_children():
		if c is OmniLight3D:
			lit += 1
	check(lit > 0 and bo._lamp != null, "lit by the emergency lights and the suit lamp")
	var o2 := float(f.eva.o2)
	f.foot_c._eva_step(1.0)
	check(f.eva.o2 < o2, "the suit's air keeps ticking")

	print("the log")
	_walk_to(bo, bo.walk.helm_stand)
	check(bo.read_log() == "reading" and bo._log_label.text.contains("Last entry"), "L at the helm: the log")
	f.foot_c._eva_hud()
	check(f.prompt.text.contains("done reading"), "and put down again: %s" % f.prompt.text)
	bo.read_log()

	print("the flight recorder")
	var rec: Dictionary = bo.items.filter(func(e): return String(e.item.kind) == "recorder")[0]
	_walk_to(bo, rec.pos)
	bo.message_t = 0.0
	f.foot_c._eva_hud()
	check(f.prompt.text.contains("flight recorder"), "in reach: %s" % f.prompt.text)
	check(bo.use() == "taken" and f.eva.carrying == 1 and String(f.eva.carry.kind) == "recorder", "taken")
	var other: Array = bo.items.filter(func(e): return String(e.item.kind) in ["crate", "supplies"])
	if not other.is_empty():
		_walk_to(bo, other[0].pos)
		check(bo.use() == "full", "one thing at a time")
	_walk_to(bo, bo.walk.airlock)
	check(bo.use() == "left" and not bo.active and f.eva.carrying == 1, "out through their airlock, still holding it")
	var wreck_world: Vector3 = (d.ship as NpcShip).global_position
	check((f.view.global_transform * f.eva.pos).distance_to(wreck_world) < 40.0, "drifting just outside their door")
	_home()
	check(PortAuthority.recorders().size() == 1 and f.eva.carrying == 0, "stowed: %s" % f.eva.message)

	print("the crew")
	f.foot_c.boarding.enter(d)
	var bodies_here: Array = bo.items.filter(func(e): return String(e.item.kind) == "body")
	check(bo.items.filter(func(e): return String(e.item.kind) == "recorder").is_empty(), "back inside: the recorder's gone from the helm")
	if bodies_here.is_empty():   # this wreck's crew all got away: stow someone from another wreck instead
		var body2 := {"kind": "body", "name": "Marcus Byrne", "ship": "Ledger Line", "tonnes": 0.2}
		check(Salvage.room_for(body2) == "" and bool(Salvage.stow(body2).ok), "(nobody died aboard this one; another wreck's crew, stowed)")
		var m0: CargoManifest = Session._load_ship(SaveSlots.read(Session.slot)).manifest
		check(PortAuthority.remains().size() == 1 and m0.total_of(Salvage.REMAINS) > 0.1, "in the hold, %.1f t, for the port authority" % m0.total_of(Salvage.REMAINS))
	else:
		var body: Dictionary = bodies_here[0]
		_walk_to(bo, body.pos)
		bo.message_t = 0.0
		f.foot_c._eva_hud()
		check(f.prompt.text.contains(String(body.item.name)), "%s" % f.prompt.text)
		check(bo.use() == "taken" and String(f.eva.carry.kind) == "body", "carried out with care")
		_walk_to(bo, bo.walk.airlock)
		bo.use()
		_home()
		var m: CargoManifest = Session._load_ship(SaveSlots.read(Session.slot)).manifest
		check(PortAuthority.remains().size() == 1 and m.total_of(Salvage.REMAINS) > 0.1, "in the hold, %.1f t, for the port authority" % m.total_of(Salvage.REMAINS))
	print("nobody's left behind for want of a bed")
	var survivor := {"kind": "survivor", "name": "Ama Okoro", "species": "human", "role": "engineer", "skill": 3, "wage": 400, "line": "", "ship": "Cantor"}
	check(Salvage.room_for(survivor) == "", "the starter's only bunk is yours, but there's the jump seat")
	var sr := Salvage.stow(survivor)
	check(bool(sr.ok) and String(sr.message).contains("jump seat") and PortAuthority.rescued().size() == 1, "%s" % sr.message)
	var st0 := Session.ship_stats(Session._load_ship(SaveSlots.read(Session.slot)).ship)
	check(Session.free_berths(st0) == -1 and People.seats(st0) == 0, "nobody's hired or booked into it")
	var second := survivor.duplicate()
	second["name"] = "Teodor Lusk"
	check(Salvage.room_for(second).contains("Report"), "a second has nowhere: %s" % Salvage.room_for(second))
	if not bo.active:
		bo.enter(d)
	_walk_to(bo, bo.walk.helm_stand)
	var entry := {"id": "test|in|99", "item": second, "pos": bo.walk.pos, "node": Node3D.new()}
	bo.items.append(entry)
	bo.view.add_child(entry.node)
	bo.message_t = 0.0
	f.foot_c._eva_hud()
	check(f.prompt.text.contains("report them"), "so E reports them: %s" % f.prompt.text)
	check(bo.take(entry) == "reported" and PortAuthority.reported().size() == 1 and f.eva.carrying == 0, "%s" % bo.message)
	check((Session.profile.get("salvage_taken", []) as Array).has("test|in|99"), "and the port's boat has them now")
	var data := SaveSlots.read(Session.slot)
	var cabin := ShipData.new(lib)
	ShipPresets.build(cabin, ShipPresets.STARTER_CABIN)
	data["modules"] = (JSON.parse_string(cabin.to_json()) as Dictionary)["modules"]
	SaveSlots.write(Session.slot, data)
	var st := Session.ship_stats(Session._load_ship(SaveSlots.read(Session.slot)).ship)
	check(Session.free_berths(st) == int(st.berths) - 2, "with crew quarters, they've a bunk (%d free)" % Session.free_berths(st))

	print("out of air inside")
	f.foot_c.boarding.leave()
	f.foot_c.boarding.enter(d)
	f.eva.o2 = 0.5
	f.foot_c._eva_step(1.0)
	check(not bo.active and f.eva == null, "the winch drags you out and home")

	print("the same day")
	t.rebuild(String(Session.profile.port_id))
	check(String(_point(door_id).kind) == "enter", "their door stays open")
	f.queue_free()
	await process_frame

	print("handing it in")
	var credits := int(Session.profile.credits)
	var bounty := PortAuthority.recorder_total()
	var r := PortAuthority.hand_in_recorders()
	check(bool(r.ok) and int(Session.profile.credits) == credits + bounty and PortAuthority.recorders().is_empty(), "the insurer pays: %s" % r.message)
	if not PortAuthority.remains().is_empty():
		credits = int(Session.profile.credits)
		r = PortAuthority.hand_over_remains()
		var m2: CargoManifest = Session._load_ship(SaveSlots.read(Session.slot)).manifest
		check(bool(r.ok) and int(Session.profile.credits) > credits and m2.total_of(Salvage.REMAINS) < 0.001, "the port authority takes them home: %s" % r.message)
	credits = int(Session.profile.credits)
	r = PortAuthority.collect_finders()
	check(bool(r.ok) and int(Session.profile.credits) == credits + PortAuthority.finder_fee() and PortAuthority.reported().is_empty(), "a finder's fee for the one you reported: %s" % r.message)
	credits = int(Session.profile.credits)
	var rep := int(Session.profile.get("rep", 0))
	check(not bool(PortAuthority.sign_on(0).ok), "paperwork first")
	r = PortAuthority.hand_over(0)
	check(bool(r.ok) and int(Session.profile.credits) == credits + int(PortAuthority.cfg().rescue_bounty) and int(Session.profile.get("rep", 0)) > rep, "a rescue bounty and standing: %s" % r.message)
	var crew_n := Session.crew().size()
	r = PortAuthority.sign_on(0)
	check(bool(r.ok) and Session.crew().size() == crew_n + 1 and PortAuthority.rescued().is_empty(), "and they sign on, no fee: %s" % r.message)
	Salvage.stow(survivor)
	PortAuthority.hand_over(0)
	r = PortAuthority.see_off(0)
	check(bool(r.ok) and PortAuthority.rescued().is_empty(), "or go their own way: %s" % r.message)
	var ps: Dictionary = ShipRemote.port_state()
	check(ps.has("authority"), "the phone sees the port authority too")
	print("DONE fails=", fails)
	quit(1 if fails > 0 else 0)
