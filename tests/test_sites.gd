extends SceneTree
## More of the moon: the abandoned outpost, the ice mine and the glass crater; boulders and slopes as
## hazards on foot and when landing; ice cores and glass crystals and who buys them.
## Run: godot --headless --path . --script res://tests/test_sites.gd
var fails := 0
func check(ok: bool, msg: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + msg)
	if not ok:
		fails += 1
func _initialize() -> void:
	SaveSlots.dir = "user://test_saves_sites"
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
## Put the ship 1 m over (x, z), sinking at 1 m/s, level, and let it settle.
func _set_down(f: Node, x: float, z: float) -> void:
	var m: FlightModel = f.model
	m.landed = false
	m.damage = 0.0
	m.hazard = ""
	m.basis = Basis.IDENTITY
	m.pos = Vector3(x, m.terrain.height(x, z) + m.foot_m + 1.0, z)
	m.vel = Vector3(0, -1.0, 0)
	m.ang = Vector3.ZERO
	for i in 400:
		if m.landed:
			break
		m.step(0.05, Vector3.ZERO, 0.0, (m.gravity - 1.0 * (1.0 + m.vel.y)) / maxf(m.lift_accel(), 0.01))
func _run() -> void:
	Session.begin_new(2, "Pilot", "human", "normal", "roosevelt_independent_yards")
	var sys := Session.system_id()
	var sites := SurfaceSites.sites(sys)
	check(sites.size() == 3 and str(sites) == str(SurfaceSites.sites(sys)), "three extra sites, the same every time")
	var camp := SurfaceFinds.camp_xz()
	for s in sites:
		var p := Vector2(float(s.x), float(s.z))
		check(p.length() > 1400.0 and p.distance_to(camp) > 1200.0, "%s is %.1f km from the pad, %.1f km from the camp" % [s.name, p.length() / 1000.0, p.distance_to(camp) / 1000.0])
	var t := SurfaceTerrain.make(sys + LocalSpace.SEP + "moon", [camp] + SurfaceSites.pads(sys), SurfaceSites.craters(sys))
	var cr := SurfaceSites.site(sys, "crater")
	var cx := float(cr.x)
	var cz := float(cr.z)
	var r := float(SurfaceSites.config().crater_r_m)
	check(t.height(cx + r * 1.05, cz) - t.height(cx, cz) > 50.0, "the glass crater is deep (%.0f m)" % (t.height(cx + r * 1.05, cz) - t.height(cx, cz)))
	check(SurfaceSites.slope_deg(t, cx + r * 0.95, cz) > 30.0, "its walls are too steep to walk (%.0f°)" % SurfaceSites.slope_deg(t, cx + r * 0.95, cz))
	check(SurfaceSites.slope_deg(t, cx, cz) < 5.0, "its floor is nearly flat")
	var op := SurfaceSites.site(sys, "outpost")
	check(SurfaceSites.slope_deg(t, float(op.x), float(op.z)) < 1.0, "the outpost has a flat pad")
	var rocks := SurfaceSites.boulders(sys)
	var clear := true
	for b in rocks:
		for p in [Vector2.ZERO, camp, Vector2(float(op.x), float(op.z))]:
			if Vector2(b.x, b.y).distance_to(p) < 55.0:
				clear = false
	check(rocks.size() > 100 and clear, "%d boulders, none on a pad" % rocks.size())
	var kinds := {}
	for f in SurfaceFinds.list(sys, Session.day()):
		kinds[String(f.kind)] = int(kinds.get(String(f.kind), 0)) + 1
	check(int(kinds.get("ice", 0)) == 4 and int(kinds.get("rare", 0)) == 2 and int(kinds.get("salvage", 0)) == 2, "finds: %s" % [kinds])
	# Landing hazards, in the flight scene on this moon.
	_fit(ShipPresets.STARTER_LANDER)
	Session.profile["port_id"] = sys + LocalSpace.SEP + "pad"
	Session.save_profile()
	Session.flight_job = {}
	var f: Node = load(Session.FLIGHT_SCENE).instantiate()
	root.add_child(f)
	await process_frame
	await process_frame
	check(f.model.rocks.size() == rocks.size(), "the ship knows where the boulders are")
	_set_down(f, float(op.x), float(op.z))
	check(f.model.landed and f.model.hazard == "" and f.model.damage == 0.0, "a clean landing on the outpost's pad")
	var b0: Vector3 = rocks[0]
	_set_down(f, b0.x, b0.y)
	check(f.model.landed and f.model.damage > 0.1 and "boulder" in f.model.hazard, "setting down on a boulder: %s (%.0f%% damage)" % [f.model.hazard, f.model.damage * 100.0])
	_set_down(f, cx + r * 0.8, cz)
	check(f.model.damage > 0.05 and "slope" in f.model.hazard, "landing on the crater wall: %s" % f.model.hazard)
	# On foot in the crater.
	_set_down(f, cx, cz)
	check(f.model.landed and f.model.hazard == "", "a clean landing on the crater floor")
	f.get_up()
	f.walk_from_airlock()
	check(f.go_outside(), "out on the crater floor")
	var w: SurfaceWalker = f.suit
	w.place(Vector3(cx + r * 0.7, 0, cz))
	w.face(Vector3(1, 0, 0))
	for i in 600:
		w.step(0.05, Vector2(0, 1), true)
	check(Vector2(w.pos.x - cx, w.pos.z - cz).length() < r * 0.97, "the wall stops you walking out (%.0f m from the centre)" % Vector2(w.pos.x - cx, w.pos.z - cz).length())
	w.jet_accel = 1.4 * w.gravity
	w.jet_fuel = 4.0
	for i in 600:
		w.step(0.05, Vector2(0, 1), true, i % 120 < 90, i % 120 < 90)
		if i % 120 == 119:
			w.jet_fuel = 4.0   # topped up for the test, as if hopping in stages
	check(Vector2(w.pos.x - cx, w.pos.z - cz).length() > r * 1.0, "suit jets carry you up and out (%.0f m from the centre)" % Vector2(w.pos.x - cx, w.pos.z - cz).length())
	# Boulders on foot.
	var b1: Vector3 = rocks[5]
	w.jet_accel = 0.0
	w.place(Vector3(b1.x - b1.z - 3.0, 0, b1.y))
	w.face(Vector3(1, 0, 0))
	for i in 60:
		w.step(0.05, Vector2(0, 1))
	check(Vector2(w.pos.x - b1.x, w.pos.z - b1.y).length() >= b1.z + SurfaceWalker.RADIUS - 0.01, "you walk round a boulder, not through it")
	# Ice and crystals.
	var rare := {}
	var ice := {}
	for fd in Session.finds_here():
		if String(fd.kind) == "rare" and rare.is_empty():
			rare = fd
		if String(fd.kind) == "ice" and ice.is_empty():
			ice = fd
	w.place(Vector3(float(rare.x) + 0.5, 0, float(rare.z)))
	check(f.take_find() != "" and int(Session.finds_aboard().rare) == 1, "a glass crystal bagged on the crater floor")
	w.place(Vector3(float(ice.x) + 0.5, 0, float(ice.z)))
	check(f.take_find() != "" and int(Session.finds_aboard().ice) == 1, "an ice core cut at the mine")
	f.queue_free()
	await process_frame
	var lab := Session.finds_value({"sample": 1.4, "rare": 1.4, "salvage": 0.0, "ice": 0.0})
	var exch := Session.finds_value({"sample": 0.8, "salvage": 0.9, "ice": 1.3, "rare": 0.8})
	check(lab == roundi(2500 * 1.4) and exch == roundi(600 * 1.3 + 2500 * 0.8), "the lab pays %d for the crystal; the exchange %d for both" % [lab, exch])
	var sold := Session.sell_finds({"sample": 1.4, "rare": 1.4, "salvage": 0.0, "ice": 0.0})
	check(bool(sold.ok) and int(Session.finds_aboard().ice) == 1 and int(Session.finds_aboard().rare) == 0, "the lab keeps the ice in your locker: %s" % sold.message)
	print("DONE fails=", fails)
	quit(1 if fails > 0 else 0)
