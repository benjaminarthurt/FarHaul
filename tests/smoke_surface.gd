extends SceneTree
## Surface work, end to end: surface jobs show only to a lander, a run from the port to the mining camp
## ends in a hand landing there (no beacon), the next run lifts off from the camp to the base's station,
## the helm at a surface site starts on the pad, samples and salvage are picked up on foot and sold, and
## the moons differ from system to system. Run: godot --headless --path . --script res://tests/smoke_surface.gd
var fails := 0
func check(ok: bool, msg: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + msg)
	if not ok:
		fails += 1
func _initialize() -> void:
	SaveSlots.dir = "user://test_saves_surface"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SaveSlots.dir))
	process_frame.connect(_run, CONNECT_ONE_SHOT)
func _key(code: int) -> InputEventKey:
	var k := InputEventKey.new()
	k.keycode = code
	k.pressed = true
	return k
func _fit(preset: Array) -> void:
	var data := SaveSlots.read(2)
	var ship := ShipData.new(ModuleLibrary.new())
	ShipPresets.build(ship, preset)
	data["modules"] = (JSON.parse_string(ship.to_json()) as Dictionary)["modules"]
	data["cargo"] = CargoManifest.new(ship).to_dict()
	SaveSlots.write(2, data)
	SimWorld.sync(Session.sim, Session.profile, ship)
func _surface_jobs() -> Array:
	var out := []
	for o in Contracts.offers_from(Session.system_id()):
		if bool(o.get("surface", false)):
			out.append(o)
	return out
## Hold the lift jets to come down at about 1.5 m/s onto the pad below.
func _hand_land(f: Node) -> void:
	for i in 6000:
		if f.model.landed:
			return
		var need: float = (f.model.gravity + (-1.5 - f.model.vel.y)) / f.model.lift_accel()
		f.model.step(0.05, Vector3.ZERO, 0.0, need)
func _run() -> void:
	Session.begin_new(2, "Pilot", "human", "normal", "roosevelt_independent_yards")
	var sys := Session.system_id()
	check(_surface_jobs().is_empty(), "the starter (no legs) sees no surface work")
	_fit(ShipPresets.STARTER_LANDER)
	var jobs := _surface_jobs()
	check(not jobs.is_empty(), "a lander sees surface jobs (%d)" % jobs.size())
	var camp_job: Dictionary = {}
	for o in jobs:
		if LocalSpace.node(String(o.destination_port_id)).get("kind", "") == "camp":
			camp_job = o
	if camp_job.is_empty():
		for o in jobs:
			camp_job = o
	check(not camp_job.is_empty(), "a run to a surface site is posted (%s)" % String(camp_job.get("title", "")))
	var plain := 0.0
	for o in Contracts.offers_from(sys):
		if bool(o.get("local", false)) and not bool(o.get("surface", false)) and float(o.dv_kms) > 0.0:
			plain = float(o.rate) / float(o.dv_kms)
	check(float(camp_job.rate) / float(camp_job.dv_kms) > plain * 1.2, "surface work pays more per tonne-km/s")
	check(bool(Session.accept_contract(camp_job).ok), "accepted")
	var dest_kind := String(LocalSpace.node(String(camp_job.destination_port_id)).kind)
	check(bool(Session.begin_local_flight().ok), "the helm is handed the run")
	var f: Node = load("res://scenes/flight.tscn").instantiate()
	root.add_child(f)
	await process_frame
	check(f.phase == "depart" and f._dv_space < float(camp_job.dv_kms), "it leaves the port first; %.1f of %.1f km/s is in space" % [f._dv_space, float(camp_job.dv_kms)])
	f.phase = "cruise"
	f.model.station_solid = false
	f.model.pos = f.xfer.target
	f.model.vel = Vector3.ZERO
	await process_frame
	await process_frame
	check(f.phase == "descent" and f._target_kind == dest_kind, "arriving brings the descent onto the %s" % dest_kind)
	if dest_kind == "camp":
		f._unhandled_input(_key(KEY_ESCAPE))
		check(not f.model.autoland, "the camp has no beacon: no autopilot")
	f.model.pos = f.model.pad + Vector3(6, 40 + f.model.foot_m, 4)
	f.model.vel = Vector3.ZERO
	_hand_land(f)
	check(f.model.landed and f.model.on_pad() and f.model.damage == 0.0, "landed by hand on the %s's pad" % dest_kind)
	f._unhandled_input(_key(KEY_F))
	check(f.leaving and String(Session.profile.port_id) == String(camp_job.destination_port_id), "unloaded: the ship is now at %s" % String(Session.profile.port_id))
	check(bool(Session.deliver_active_contract().ok), "delivered")
	f.queue_free()
	await process_frame
	# Lift off from the surface to the base's station.
	var up: Dictionary = {}
	for o in Contracts.offers_from(sys):
		if LocalSpace.node(String(o.destination_port_id)).get("kind", "") == "moon":
			up = o
	check(not up.is_empty(), "the surface board has a run up to the base's station")
	check(bool(Session.accept_contract(up).ok) and bool(Session.begin_local_flight().ok), "accepted and handed to the helm")
	var g: Node = load("res://scenes/flight.tscn").instantiate()
	root.add_child(g)
	await process_frame
	check(g.phase == "ascent" and g.model.landed and g.model.on_pad(), "the run starts on the surface pad, landed")
	g._unhandled_input(_key(KEY_ESCAPE))
	check(g.auto_ascent, "Esc lifts off on auto")
	var t := 0.0
	while t < 600.0 and g.phase == "ascent":
		g._process(0.05)
		t += 0.05
	check(g.phase == "approach" and g.station.visible and g.model.gravity == 0.0, "clear of the moon (%.0f s), it approaches the base's station" % t)
	g._unhandled_input(_key(KEY_ESCAPE))
	check(g.leaving and String(Session.profile.port_id).ends_with("__moon"), "docked at the station (%s)" % String(Session.profile.port_id))
	check(bool(Session.deliver_active_contract().ok), "delivered")
	g.queue_free()
	await process_frame
	# The helm on the surface: put the ship on the base pad and take the helm.
	Session.profile["port_id"] = sys + LocalSpace.SEP + "pad"
	Session.save_profile()
	Session.flight_job = {}
	var h: Node = load("res://scenes/flight.tscn").instantiate()
	root.add_child(h)
	await process_frame
	check(h.phase == "descent" and h.model.landed and h.model.on_pad(), "the helm at the pad starts on the pad")
	# Walk out and pick things up.
	h.get_up()
	h.walk.stand_in_airlock()
	check(h.use() == "outside", "out on the surface")
	var finds: Array = Session.finds_here()
	var sample: Dictionary = {}
	for x in finds:
		if String(x.kind) == "sample" and Vector2(float(x.x), float(x.z)).length() < 600.0:
			sample = x
			break
	check(not sample.is_empty(), "samples lie near the base")
	h.suit.place(Vector3(float(sample.x) + 0.5, 0, float(sample.z)))
	h._update_hud()
	check(h.prompt.text.contains("take the sample"), "the prompt offers it (%s)" % h.prompt.text)
	h._suit_input(_key(KEY_E))
	check(int(Session.finds_aboard().samples) == 1, "bagged one sample")
	h._suit_input(_key(KEY_E))
	check(int(Session.finds_aboard().samples) == 1, "a sample can only be taken once")
	var w := SurfaceFinds.wreck_xz()
	h.suit.place(Vector3(w.x + 3.0, 0, w.y))
	check(h.take_find() != "" and int(Session.finds_aboard().salvage) == 2, "stripped two salvage parts from the wreck")
	h.suit.place(h.suit_hatch)
	h.come_aboard()
	h.walk.stand_at_helm()
	h.sit_down()
	h._unhandled_input(_key(KEY_F))
	check(h.leaving, "F on the pad shuts down")
	var cr0 := int(Session.profile.credits)
	var sold := Session.sell_finds()
	check(bool(sold.ok) and int(Session.profile.credits) - cr0 == 350 + 2 * 1400, "sold at the dock: %s" % sold.message)
	# Different worlds.
	var kinds := {}
	var heavy := ""
	for sid in Session.sim.net.adj.keys():
		var b := LocalSpace.body(String(sid))
		kinds[String(b.id)] = true
		if String(b.id) == "heavy":
			heavy = String(sid)
	check(kinds.size() >= 3, "moons differ across systems (%s)" % ", ".join(PackedStringArray(kinds.keys())))
	var lander := ShipData.new(ModuleLibrary.new())
	ShipPresets.build(lander, ShipPresets.STARTER_LANDER)
	var st := ShipStats.compute(lander, 0.0)
	if heavy != "":
		check(LocalSpace.can_land(st, sys) and LocalSpace.max_landing_cargo_t(st, heavy) < LocalSpace.max_landing_cargo_t(st, sys), "a heavy moon takes more lift: %.1f t there against %.1f t here" % [LocalSpace.max_landing_cargo_t(st, heavy), LocalSpace.max_landing_cargo_t(st, sys)])
	print("DONE fails=", fails)
	quit(1 if fails > 0 else 0)
