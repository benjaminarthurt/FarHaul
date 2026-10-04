extends SceneTree
## Landing, headless: lander legs give lift; the autopilot sets the starter down on a moon pad from
## orbit; a drop without lift is a hard landing; a ship without legs cannot hover; it can take off again.
## Run: godot --headless --path . --script res://tests/test_landing.gd
var fails := 0
func check(ok: bool, msg: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + msg)
	if not ok:
		fails += 1
func _initialize() -> void:
	process_frame.connect(_run, CONNECT_ONE_SHOT)

func _model(steps: Array, cargo := 1.0) -> FlightModel:
	var ship := ShipData.new(ModuleLibrary.new())
	var err := ShipPresets.build(ship, steps)
	if err != "":
		print("  build error: ", err)
	var st := ShipStats.compute(ship, cargo)
	var m := FlightModel.from_stats(st)
	m.land_cfg = SurfaceTerrain.config()
	m.gravity = float(m.land_cfg.bodies.moon.gravity_m_s2)
	m.terrain = SurfaceTerrain.make("test_moon")
	m.station_solid = false
	return m

func _run() -> void:
	var ship := ShipData.new(ModuleLibrary.new())
	check(ShipPresets.build(ship, ShipPresets.STARTER_LANDER) == "", "the starter takes two lander legs")
	var st := ShipStats.compute(ship, 1.0)
	check(int(st.legs) == 2 and float(st.lift) == 140.0, "two legs, 140 kN of lift (%d, %.0f)" % [int(st.legs), float(st.lift)])
	check(float(st.lift_g) > 1.62 * 1.15, "a full hold can still hover on the moon (%.2f m/s² of lift)" % float(st.lift_g))
	check(float(st.foot_y) < -1.5, "the feet are under the hull (%.1f m)" % float(st.foot_y))
	var t := SurfaceTerrain.make("test_moon")
	check(absf(t.height(0, 0)) < 0.01 and absf(t.height(60, -40)) < 0.01, "the pad area is flat")
	var rough := 0.0
	for i in 20:
		rough = maxf(rough, absf(t.height(400 + i * 50, 300)))
	check(rough > 1.0, "the ground away from the pad has relief (%.1f m)" % rough)

	# Autoland from the descent start: 1200 m up, 900 m out, drifting at 25 m/s.
	var m := _model(ShipPresets.STARTER_LANDER)
	check(m.can_hover(), "the loaded lander can hover")
	m.pos = Vector3(900, 1200, 0)
	m.vel = Vector3(-25, 0, 0)
	m.basis = Basis.looking_at(Vector3(-1, 0, 0), Vector3.UP)
	m.autoland = true
	var fuel0 := m.fuel_t
	var t_s := 0.0
	while t_s < 900.0 and not m.landed and m.has_fuel():
		m.step(0.05)
		t_s += 0.05
	check(m.landed, "the autopilot lands (%.0f s, %.0f m from the pad)" % [t_s, Vector2(m.pos.x, m.pos.z).length()])
	check(m.on_pad(), "on the pad")
	check(m.damage == 0.0 and m.last_touchdown <= 3.0, "softly (touchdown %.2f m/s, damage %.3f)" % [m.last_touchdown, m.damage])
	check(fuel0 - m.fuel_t < 4.0, "for %.2f t of fuel" % (fuel0 - m.fuel_t))
	# Standing on the pad, nothing moves.
	var p0 := m.pos
	for i in 100:
		m.step(0.05)
	check(m.landed and m.pos.distance_to(p0) < 0.001, "stays put on its legs")
	# Lift off again.
	for i in 40:
		m.step(0.05, Vector3.ZERO, 0.0, 1.0)
	check(not m.landed and m.altitude() > 1.0, "full lift takes off (%.1f m up)" % m.altitude())

	# Dropped from 40 m with no lift: a hard landing.
	var d := _model(ShipPresets.STARTER_LANDER)
	d.pos = Vector3(0, 40.0 + d.foot_m, 0)
	for i in 400:
		d.step(0.05)
	check(d.damage > 0.0 and d.impacts > 0, "a 40 m drop damages the hull (%.3f)" % d.damage)

	# Manual: hold lift to settle at about 2 m/s.
	var h := _model(ShipPresets.STARTER_LANDER)
	h.pos = Vector3(10, 60.0 + h.foot_m, 10)
	for i in 4000:
		if h.landed:
			break
		var need := (h.gravity + (-2.0 - h.vel.y)) / h.lift_accel()
		h.step(0.05, Vector3.ZERO, 0.0, need)
	check(h.landed and h.damage == 0.0, "a steady 2 m/s descent on the lift jets lands cleanly")

	# The plain starter has no lift at all.
	var n := _model(ShipPresets.STARTER)
	check(not n.can_hover() and n.lift_kn == 0.0, "the starter without legs cannot hover")
	print("landing tests: %s" % ("FAIL (%d)" % fails if fails > 0 else "all passed"))
	quit(1 if fails > 0 else 0)
