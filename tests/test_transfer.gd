extends SceneTree
## Flown local runs, headless: the plan matches the rocket equation, a clean burn-and-brake arrives,
## sloppy flying costs more fuel, and running out of fuel strands the ship.
## Run: godot --headless --path . --script res://tests/test_transfer.gd

var fails := 0

func check(ok: bool, msg: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + msg)
	if not ok:
		fails += 1

## Fly the textbook run: point at the target, full burn, flip at the brake point, stop.
func fly(stats: Dictionary, t: TransferFlight, sloppy: bool) -> Dictionary:
	var m := FlightModel.from_stats(stats)
	m.station_solid = false
	m.pos = Vector3.ZERO
	var dir := t.direction
	m.basis = Basis.looking_at(dir, Vector3.UP)
	var braking := false
	var dt := 0.1
	var steps := 0
	while steps < 60000 and not t.arrived(m) and m.has_fuel():
		steps += 1
		if not braking and t.brake_now(m):
			braking = true
			m.braking = true   # the ship's own autopilot: flip to retrograde and burn
		if not braking:
			m.throttle = 1.0
		if braking and not m.braking:
			break   # the autopilot has stopped the ship
		m.step(dt)
	return {"model": m, "arrived": t.arrived(m), "steps": steps}

func closing(m: FlightModel, t: TransferFlight) -> float:
	return t.closing(m)

func _init() -> void:
	var ship := ShipData.new(ModuleLibrary.new())
	ShipPresets.build(ship)
	var lib_stats := ShipStats.compute(ship, 0.0)
	var cargo_ship := ShipData.new(ModuleLibrary.new())
	ShipPresets.build(cargo_ship)
	var mf := CargoManifest.new(cargo_ship)
	mf.load(&"grain", 24.0)
	var loaded_stats := ShipStats.compute(cargo_ship, 1.0, mf)

	print("the plan")
	var dv := 1.2
	var t := TransferFlight.plan(loaded_stats, dv, "x")
	var est := LocalSpace.burn_t(float(loaded_stats.wet) + 24.0, dv)
	check(t.distance_m > 20000.0 and t.distance_m < 2.0e6, "sites are %.0f km apart" % (t.distance_m / 1000.0))
	check(absf(t.ideal_burn_t - est) / est < 0.03, "a perfect run burns %.2f t, the board's estimate is %.2f t" % [t.ideal_burn_t, est])
	check(t.ideal_seconds > 60.0 and t.ideal_seconds < 3000.0, "and takes %.0f s of flying" % t.ideal_seconds)
	check(TransferFlight.plan(loaded_stats, dv, "x").target == t.target and TransferFlight.plan(loaded_stats, dv, "y").target != t.target, "the heading is fixed per job")
	check(TransferFlight.plan(lib_stats, dv, "x").distance_m < t.distance_m * 1.6 and TransferFlight.plan(lib_stats, 3.0, "x").distance_m > t.distance_m, "longer hops are farther")

	print("flying it")
	var r := fly(loaded_stats, t, false)
	var m: FlightModel = r.model
	check(bool(r.arrived), "a clean burn-and-brake arrives (range %.0f m, %.1f m/s)" % [t.range_to(m), m.speed()])
	var used := m.fuel_burned_t
	check(absf(used - est) / est < 0.08, "fuel used %.2f t is close to the estimate %.2f t" % [used, est])
	check(m.fuel_t > 0.0, "with %.2f t left in the tank" % m.fuel_t)

	print("running dry")
	var thin := loaded_stats.duplicate()
	thin["fuel"] = 2.0
	var t2 := TransferFlight.plan(loaded_stats, dv, "x")
	var r2 := fly(thin, t2, false)
	check(not bool(r2.arrived) and not r2.model.has_fuel(), "a ship short of fuel does not arrive and ends dry")

	print("no station to hit")
	var m3 := FlightModel.from_stats(loaded_stats)
	m3.station_solid = false
	m3.pos = Vector3(0, 0, 10)
	m3.step(0.1)
	check(m3.impacts == 0 and m3.damage == 0.0, "nothing is solid on a transfer")

	print("DONE fails=", fails)
	quit(1 if fails > 0 else 0)
