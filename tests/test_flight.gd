extends SceneTree
## Flight model checks, headless: acceleration, fuel, delta-v, turning, the braking autopilot, docking.
## Run: godot --headless --path . --script res://tests/test_flight.gd

var fails := 0

func check(ok: bool, msg: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + msg)
	if not ok:
		fails += 1

func _init() -> void:
	var ship := ShipData.new(ModuleLibrary.new())
	ShipPresets.build(ship)
	var stats := ShipStats.compute(ship, 0.0)
	var m := FlightModel.from_stats(stats)
	m.place_at_dock()

	print("the ship")
	check(m.mass_t() > 15.0 and m.fuel_t >= 9.9, "starter %.1f t wet with %.1f t of fuel" % [m.mass_t(), m.fuel_t])
	check(m.thrust_kn > 0.0 and m.max_accel() > 1.0, "full thrust gives %.2f m/s^2" % m.max_accel())
	check(m.forward().dot(Vector3(0, 0, 1)) > 0.99, "it leaves the dock facing away")
	check(m.pos.length() >= 100.0 and m.speed() == 0.0, "and starts clear of the station, at rest")

	print("thrust and fuel")
	var mass0 := m.mass_t()
	var a0 := m.max_accel()
	for i in 600:
		m.step(0.1, Vector3.ZERO, 1.0 if i == 0 else 0.0)  # one tick of throttle up, then hold
	check(m.throttle > 0.0 and m.speed() > 0.0, "burning builds speed (%.1f m/s)" % m.speed())
	for i in 100:
		m.step(0.1, Vector3.ZERO, 1.0)
	check(m.throttle == 1.0, "throttle reaches full")
	m.step(0.1)
	check(m.fuel_t < 10.0 and m.mass_t() < mass0, "fuel burns and the ship gets lighter (%.2f t left)" % m.fuel_t)
	check(m.max_accel() > a0, "a lighter ship accelerates harder (%.2f vs %.2f)" % [m.max_accel(), a0])
	check(m.vel.dot(Vector3(0, 0, 1)) > 0.0, "it flies the way it points")

	print("delta-v")
	var f := FlightModel.from_stats(stats)
	f.place_at_dock()
	var dv := f.delta_v()
	check(dv > 1000.0, "the starter can change speed by %.0f m/s" % dv)
	f.throttle = 1.0
	var t := 0.0
	while f.has_fuel() and t < 5000.0:
		f.step(0.5)
		t += 0.5
	check(f.has_fuel() == false, "the tanks run dry after %.0f s (predicted %.0f s)" % [t, FlightModel.from_stats(stats).burn_seconds()])
	check(absf(f.speed() - dv) < dv * 0.02, "burning everything gains %.0f m/s, as predicted (%.0f)" % [f.speed(), dv])
	var v1 := f.speed()
	f.throttle = 1.0
	f.step(1.0)
	check(f.throttle == 0.0 and absf(f.speed() - v1) < 0.001, "no fuel, no thrust")

	print("turning")
	var s := FlightModel.from_stats(stats)
	s.place_at_dock()
	for i in 20:
		s.step(0.1, Vector3(0, 1, 0))
	check(absf(s.ang.y) > 0.3, "yaw input spins the ship (%.2f rad/s)" % s.ang.y)
	var heading := s.forward()
	for i in 200:
		s.step(0.1)
	check(s.ang.length() < 0.01, "the assist damps the spin when you let go")
	check(s.forward().dot(heading) < 0.999, "and the ship has turned")
	var light := FlightModel.from_stats(stats)
	var heavy := FlightModel.from_stats(stats)
	heavy.cargo_t = 40.0
	for x in [light, heavy]:
		x.place_at_dock()
		for i in 10:
			x.step(0.1, Vector3(1, 0, 0))
	check(absf(heavy.ang.x) < absf(light.ang.x), "a loaded ship turns slower (%.2f vs %.2f rad/s)" % [absf(heavy.ang.x), absf(light.ang.x)])

	print("braking autopilot")
	var b := FlightModel.from_stats(stats)
	b.place_at_dock()
	b.vel = Vector3(30, -10, 55)           # drifting fast, not pointing the way it is going
	b.braking = true
	var secs := 0.0
	while b.braking and secs < 400.0:
		b.step(0.1)
		secs += 0.1
	check(not b.braking and b.speed() < 0.2, "it stops a %.0f m/s drift in %.0f s" % [Vector3(30, -10, 55).length(), secs])
	check(b.fuel_t > 8.0, "using %.2f t of fuel" % (10.0 - b.fuel_t))

	print("docking")
	var d := FlightModel.from_stats(stats)
	d.place_at_dock()
	check(not d.can_dock(), "too far away to dock at the start")
	d.pos = Vector3(0, 0, 40)
	d.vel = Vector3(0, 0, -2)
	check(d.can_dock(), "close and slow can dock")
	d.vel = Vector3(0, 0, -12)
	check(not d.can_dock(), "close but fast cannot")

	print("DONE fails=", fails)
	quit(1 if fails > 0 else 0)
