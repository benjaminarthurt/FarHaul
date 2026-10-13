extends SceneTree
## Braking thrusters: an optional bolt-on (like lander legs) that fires toward the bow and pushes the
## ship backward. Mounting, stats, the B key's physics, the braking autopilot stopping nose-on with
## them, and their plumes.
## Run: godot --headless --path . --script res://tests/test_retro_thrusters.gd
var fails := 0
func check(ok: bool, msg: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + msg)
	if not ok:
		fails += 1
func _initialize() -> void:
	process_frame.connect(_run, CONNECT_ONE_SHOT)


func _ship(retro_cell := Vector3i(-1, 0, 0), rot := 0) -> ShipData:
	var ship := ShipData.new(ModuleLibrary.new())
	ShipPresets.build(ship)
	if retro_cell != Vector3i(99, 99, 99):
		var err := ship.add(&"retro_thrusters", retro_cell, rot)
		if err != "":
			print("    add: ", err)
	return ship


func _run() -> void:
	var lib := ModuleLibrary.new()
	var d := lib.get_def(&"retro_thrusters")
	check(d != null and d.retro > 0.0 and not d.pressurized and d.group == &"external", "braking thrusters are an external part (%.0f kN)" % (d.retro if d else 0.0))
	check(d.retro < lib.get_def(&"engine").thrust * 0.5, "a fraction of a main engine")

	var plain := ShipStats.compute(_ship(Vector3i(99, 99, 99)), 0.0)
	check(float(plain.retro) == 0.0, "optional: the starter has none")
	var side := _ship()
	check(side.modules.size() == 11, "they bolt onto the cockpit's bare side")
	var st := ShipStats.compute(side, 0.0)
	check(is_equal_approx(float(st.retro), d.retro) and float(st.retro_a) > 0.0, "the ship gets %.0f kN of braking, %.2f m/s²" % [float(st.retro), float(st.retro_a)])
	var ok_warn := true
	for w in st.warnings:
		if String(w).contains("braking"):
			ok_warn = false
	check(ok_warn, "facing the bow, no complaint")
	var nose := _ship(Vector3i(0, 0, -1))
	check(nose.modules.size() == 11 and is_equal_approx(float(ShipStats.compute(nose, 0.0).retro), d.retro), "or on the nose, ahead of the cockpit")
	var back := _ship(Vector3i(-1, 0, 0), 2)
	var bst := ShipStats.compute(back, 0.0)
	var warned := false
	for w in bst.warnings:
		if String(w).contains("braking thrusters"):
			warned = true
	check(back.modules.size() == 11 and float(bst.retro) == 0.0 and warned, "turned round, they don't brake, and the builder says so")
	check(ShipStats.format(st).contains("Braking"), "the stats panel lists them")

	print("in flight")
	var m := FlightModel.from_stats(st)
	m.station_solid = false
	m.pos = Vector3(0, 0, 5000)
	m.vel = m.forward() * 5.0
	var f0 := m.fuel_t
	for i in 50:
		m.step(0.02, Vector3.ZERO, 0.0, 0.0, 1.0)
	var a := float(st.retro) / m.mass_t()
	check(absf((5.0 - m.vel.dot(m.forward())) - a * 1.0) < 0.05 and m.fuel_t < f0, "B for a second takes %.2f m/s off, nose on, and burns fuel" % (5.0 - m.vel.dot(m.forward())))
	var b0 := m.basis
	m.vel = m.forward() * 4.0
	m.braking = true
	m.step(0.02)
	check(m.brake_state == "retro" and m.retro > 0.0 and m.throttle == 0.0, "the braking autopilot uses them when moving nose-first and slow")
	for i in 3000:
		m.step(0.02)
		if not m.braking:
			break
	check(not m.braking and m.speed() < 0.2 and m.basis.is_equal_approx(b0), "and stops the ship without turning it round")
	var n := FlightModel.from_stats(plain)
	n.station_solid = false
	n.vel = n.forward() * 4.0
	n.braking = true
	n.step(0.02)
	check(n.brake_state != "retro", "without them, the old flip-and-burn (%s)" % n.brake_state)
	var fast := FlightModel.from_stats(st)
	fast.station_solid = false
	fast.vel = fast.forward() * 400.0
	fast.braking = true
	fast.step(0.02)
	check(fast.brake_state != "retro", "and when they're too weak for the speed, the main engine does it (%s)" % fast.brake_state)
	m.damage = 1.0
	m.vel = m.forward() * 3.0
	m.step(0.5, Vector3.ZERO, 0.0, 0.0, 1.0)
	check(is_equal_approx(m.vel.dot(m.forward()), 3.0), "a breached hull has no braking either")

	print("plumes")
	var view := ShipView.new()
	view.skin = true
	root.add_child(view)
	view.rebuild(side)
	view.set_retro_flames(true)
	check(view._retro_flames.size() == 2 and view._retro_flames[0].visible, "both nozzles light up")
	view.set_retro_flames(false)
	check(not view._retro_flames[0].visible, "and go out")
	var body: Node3D = null
	for c in view.get_children():
		var b := c.get_node_or_null("Body")
		if b != null:
			body = b
	check(body != null and body.position.x > 1.0 and absf(body.rotation.z - PI * 0.5) < 0.01,
			"low profile: bolted beside the cockpit, the fairing lies against the hull on its side (%s)" % (str(body.position) if body else "none"))
	print("DONE fails=", fails)
	quit(1 if fails > 0 else 0)
