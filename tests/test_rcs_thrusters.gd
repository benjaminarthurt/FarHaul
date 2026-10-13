extends SceneTree
## Manoeuvring thrusters: an optional bolt-on that slides the ship sideways and up or down without
## turning it (Ctrl + arrows). Mounting, stats, the physics, the braking autopilot using them to take out
## drift, the right nozzles lighting, and the keys.
## Run: godot --headless --path . --script res://tests/test_rcs_thrusters.gd
var fails := 0
func check(ok: bool, msg: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + msg)
	if not ok:
		fails += 1
func _initialize() -> void:
	SaveSlots.dir = "user://test_saves_rcs_%d" % OS.get_process_id()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SaveSlots.dir))
	process_frame.connect(_run, CONNECT_ONE_SHOT)


func _ship(extra: Array) -> ShipData:
	var ship := ShipData.new(ModuleLibrary.new())
	ShipPresets.build(ship)
	for e in extra:
		var err := ship.add(e[0], e[1], e[2])
		if err != "":
			print("    add ", e, ": ", err)
	return ship


func _run() -> void:
	var d := ModuleLibrary.new().get_def(&"rcs_thrusters")
	check(d != null and d.rcs > 0.0 and d.group == &"external", "manoeuvring thrusters are an external part (%.0f kN each way)" % (d.rcs if d else 0.0))
	var plain := ShipStats.compute(_ship([]), 0.0)
	check(float(plain.rcs_x) == 0.0 and float(plain.rcs_y) == 0.0, "optional: the starter has none")
	var ship := _ship([[&"rcs_thrusters", Vector3i(-1, 0, 0), 0], [&"rcs_thrusters", Vector3i(0, 1, 2), 0]])
	check(ship.modules.size() == 12, "they bolt onto the hull")
	var st := ShipStats.compute(ship, 0.0)
	check(is_equal_approx(float(st.rcs_x), 2.0 * d.rcs) and is_equal_approx(float(st.rcs_y), 2.0 * d.rcs), "two pods: %.0f kN sideways, %.0f up and down" % [float(st.rcs_x), float(st.rcs_y)])
	check(ShipStats.format(st).contains("Manoeuvring"), "the stats panel lists them")
	var turned := ShipStats.compute(_ship([[&"rcs_thrusters", Vector3i(-1, 0, 0), 1]]), 0.0)
	var warned := false
	for w in turned.warnings:
		if String(w).contains("Manoeuvring thrusters"):
			warned = true
	check(float(turned.rcs_x) == 0.0 and float(turned.rcs_y) > 0.0 and warned, "turned a quarter round, no sideways push, and the builder says so")

	print("in flight")
	var m := FlightModel.from_stats(st)
	m.station_solid = false
	m.pos = Vector3(0, 0, 5000)
	var b0 := m.basis
	var f0 := m.fuel_t
	for i in 50:
		m.step(0.02, Vector3.ZERO, 0.0, 0.0, 0.0, Vector2(1, 0))
	var a := float(st.rcs_x) / m.mass_t()
	check(absf(m.vel.dot(m.basis.x) - a) < 0.02 and absf(m.vel.dot(m.forward())) < 0.001 and m.basis.is_equal_approx(b0) and m.fuel_t < f0,
			"a second of Ctrl + Right slides %.2f m/s right, no turn, some fuel" % m.vel.dot(m.basis.x))
	m.vel = Vector3.ZERO
	for i in 50:
		m.step(0.02, Vector3.ZERO, 0.0, 0.0, 0.0, Vector2(0, -1))
	check(m.vel.dot(m.basis.y) < -0.1 and absf(m.vel.dot(m.basis.x)) < 0.001, "Ctrl + Down slides down")
	var n := FlightModel.from_stats(plain)
	n.station_solid = false
	n.step(1.0, Vector3.ZERO, 0.0, 0.0, 0.0, Vector2(1, 1))
	check(n.vel == Vector3.ZERO, "without them, nothing happens")

	print("with braking thrusters, the autopilot takes out the drift")
	var both := ShipStats.compute(_ship([[&"rcs_thrusters", Vector3i(-1, 0, 0), 0], [&"retro_thrusters", Vector3i(0, 1, 0), 0]]), 0.0)
	var k := FlightModel.from_stats(both)
	k.station_solid = false
	k.vel = k.forward() * 3.0 + k.basis.x * 0.8 + k.basis.y * -0.4
	var kb := k.basis
	k.braking = true
	for i in 4000:
		k.step(0.02)
		if not k.braking:
			break
	check(not k.braking and k.speed() < 0.2 and k.basis.is_equal_approx(kb), "stopped dead, nose still on, drift gone (%.2f m/s)" % k.speed())

	print("nozzles")
	var view := ShipView.new()
	view.skin = true
	root.add_child(view)
	view.rebuild(ship)
	view.set_rcs(Vector2(1, 0))
	var lit := 0
	var total := view._rcs_flames.size()
	for p in view._rcs_flames:
		if (p[0] as Node3D).visible:
			lit += 1
			if (p[1] as Vector3).dot(Vector3.RIGHT) < 0.9:
				lit += 100
	check(total == 6 and lit == 2, "sliding right lights one nozzle per pod, the ones pushing right (%d of %d)" % [lit, total])
	view.set_rcs(Vector2.ZERO)
	lit = 0
	for p in view._rcs_flames:
		lit += 1 if (p[0] as Node3D).visible else 0
	check(lit == 0, "and they go out")

	print("keys")
	Session.begin_new(2, "Pilot", "human", "normal", "roosevelt_independent_yards")
	var data := SaveSlots.read(2)
	data["modules"] = (JSON.parse_string(ship.to_json()) as Dictionary)["modules"]
	data["cargo"] = CargoManifest.new(ship).to_dict()
	SaveSlots.write(2, data)
	Session.flight_job = {}
	var f: Node = load(Session.FLIGHT_SCENE).instantiate()
	root.add_child(f)
	await process_frame
	check(f.model.rcs_x_kn > 0.0 and f.help.text.contains("Ctrl+arrows"), "the flight knows about them, and so does the key strip")
	print("DONE fails=", fails)
	quit(1 if fails > 0 else 0)
