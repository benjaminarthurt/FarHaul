extends SceneTree
## Planets with air (scripts/planets.gd, scripts/flight/planet_terrain.gd, the air in FlightModel): which
## worlds have a downport and a field, the hops to and from them (cheap down, dear up, paid the same), the
## board (only for ships with the lift, fresh food only from the planets, and it spoils), the ground (the
## same every visit, flat where it should be, sea and platforms), the weather, who can breathe the air,
## and the entry: belly first it brakes and stays cool, nose first it burns, the autopilot brings a ship
## down onto the pad on every kind of world, and a heat shield runs cooler.
## Run: godot --headless --path . --script res://tests/test_planets.gd

var fails := 0


func check(ok: bool, what: String) -> void:
	print(("  ok    " if ok else "  FAIL  ") + what)
	if not ok:
		fails += 1


func _initialize() -> void:
	process_frame.connect(_run, CONNECT_ONE_SHOT)


func _ship(preset: Array) -> Dictionary:
	var s := ShipData.new(ModuleLibrary.new())
	ShipPresets.build(s, preset)
	return ShipStats.compute(s, 1.0)


## A ship at the top of a planet's air, aimed the way the flight scene aims it, flown down by the entry
## autopilot (or held nose first by hand). Returns what happened.
func _entry(sys: String, kind: String, mode := "auto", shield := -1.0, cargo := -1.0) -> Dictionary:
	var st := _ship(ShipPresets.STARTER_PLANET)
	var m := FlightModel.from_stats(st)
	if cargo >= 0.0:
		m.cargo_t = cargo
	if shield >= 0.0:
		m.shield = shield
	m.land_cfg = SurfaceTerrain.config().duplicate()
	var e: Dictionary = Planets.config().entry
	for k in ["autoland_cruise_m_s", "touchdown_speed_m_s", "landing_zone_m", "sea_damage"]:
		m.land_cfg[k] = e[k]
	var t := PlanetTerrain.make_planet(sys, Landing.body_key(kind))
	m.terrain = t
	m.station_solid = false
	m.gravity = Planets.gravity(sys, kind)
	var p := Planets.planet(sys, kind)
	m.air = {"density": Planets.density(sys, kind), "scale_m": float(p.air.scale_km) * 1000.0, "cd_flat": float(e.cd_flat),
			"cd_nose": float(e.cd_nose), "heat_k": float(e.heat_k), "nose_mult": float(e.heat_nose_mult), "shed": float(e.heat_shed_per_s),
			"damage_per_s": float(e.heat_damage_per_s), "shield_cut": 1.0 - 1.0 / float(e.shield_tolerance)}
	m.pad = Vector3(t.field_xz.x, t.field_h, t.field_xz.y) if kind == "field" else Vector3(0, t.port_h, 0)
	var thin := clampf(sqrt(float(p.air.density)), 0.35, 1.0)
	var v0 := float(e.start_speed_m_s) * thin
	var gamma := deg_to_rad(float(e.start_angle_deg))
	var alt0 := float(e.start_altitude_m) * clampf(float(p.air.scale_km) / 8.5, 0.7, 1.2)
	var dir := Vector3(0.6, 0, 0.8)
	var vel := dir * v0 * cos(gamma) + Vector3.DOWN * v0 * sin(gamma)
	m.pos = m.pad - dir * (Landing.entry_range(m, alt0, vel) + float(e.aim_short_m))
	m.pos.y = alt0
	m.vel = vel
	m.basis = Landing.belly_basis(vel, dir)
	m.autoentry = mode == "auto"
	var fuel0 := m.fuel_t
	var tt := 0.0
	while tt < 1200.0 and not m.landed and not m.disabled():
		var turn := Vector3.ZERO
		if mode == "nose":
			turn = m._point(m.vel - m.wind)["turn"]
		m.step(0.1, turn)
		tt += 0.1
		if m.autoland and kind == "field":
			pass   # the field's own pad is the target here; the test drives it like a beacon
	return {"landed": m.landed, "on_pad": m.on_pad(), "peak": m.skin_peak, "damage": m.damage, "fuel": fuel0 - m.fuel_t, "t": tt,
			"burn_s": m.burn_s, "sea": m.sea}


func _run() -> void:
	print("which worlds")
	var with_world := 0
	for sys in Worlds.system_ids():
		var kinds := Planets.site_kinds(sys)
		if "world" in kinds:
			with_world += 1
			check("field" in kinds and not Planets.planet(sys, "world").is_empty(), "%s: a downport and a field on %s" % [sys, String(Planets.planet(sys, "world").name)])
	check(with_world == 15, "15 systems have a main world to land on (%d)" % with_world)
	for sys in ["carver", "port_meridian", "waystation"]:
		check(Planets.site_kinds(sys).is_empty(), "%s lives in habitats: no planet to land on" % sys)
	check("mars" in Planets.site_kinds("sol") and LocalSpace.is_planet("sol__mars"), "Sol has a downport on Mars too")
	check(String(LocalSpace.node("new_houston__world").name) == "New Houston Surface Port", "Roosevelt's downport is the canon's New Houston Surface Port")
	check(LocalSpace.is_surface("sol__world") and LocalSpace.is_planet("sol__field") and not LocalSpace.is_planet("sol__pad"), "downports and fields are surface sites on a planet; the moon pad isn't")

	print("hops")
	var down := LocalSpace.hop("port", "world", "sol")
	var up := LocalSpace.hop("world", "port", "sol")
	check(float(down.dv_kms) < float(up.dv_kms) * 0.5, "coming down costs far less than going up (%.1f against %.1f km/s)" % [float(down.dv_kms), float(up.dv_kms)])
	check(is_equal_approx(float(down.pay_dv_kms), float(up.pay_dv_kms)), "and pays the same either way")
	check(float(LocalSpace.hop("world", "port", "keshar").dv_kms) > float(up.dv_kms), "Keshar's heavy gravity makes the climb dearer than Earth's")
	check(float(LocalSpace.hop("world", "port", "ilos").dv_kms) < float(up.dv_kms), "and Ilos's light one cheaper")
	check(not LocalSpace.hop("world", "field", "sol").is_empty() and float(LocalSpace.hop("world", "field", "sol").dv_kms) < 1.0, "downport to field is a short hop")
	check(not LocalSpace.hop("mars", "port", "sol").is_empty() and not LocalSpace.hop("pad", "mars", "sol").is_empty(), "Mars is reached from everywhere in Sol")
	for a in LocalSpace.KINDS:
		for b in LocalSpace.KINDS:
			if a != b and LocalSpace.hop(a, b) != LocalSpace.hop(b, a):
				check(false, "station and moon hops are still the same both ways (%s, %s)" % [a, b])

	print("the board")
	var lv := SimShip.level("normal")
	var starter := _ship(ShipPresets.STARTER)
	var lander := _ship(ShipPresets.STARTER_LANDER)
	var planet := _ship(ShipPresets.STARTER_PLANET)
	starter["cargo_mass"] = 0.0
	var seen_plain := 0
	var seen_lander := 0
	var seen_planet := 0
	var fresh_far := 0
	for d in range(0, 40, 2):
		for j in LocalSpace.board("roosevelt_orbital_freight", d, starter, lv):
			seen_plain += 1 if bool(j.planet) else 0
		for j in LocalSpace.board("roosevelt_orbital_freight", d, lander, lv):
			seen_lander += 1 if bool(j.planet) else 0
		for j in LocalSpace.board("roosevelt_orbital_freight", d, planet, lv):
			seen_planet += 1 if bool(j.planet) else 0
			fresh_far += 1 if bool(j.fresh) else 0
	check(seen_plain == 0 and seen_lander == 0, "a ship without the lift for a planet never sees planet runs (%d, %d)" % [seen_plain, seen_lander])
	check(seen_planet > 5, "a ship with heavy legs does (%d over 20 boards)" % seen_planet)
	check(fresh_far == 0, "fresh food isn't posted from a station")
	var fresh := 0
	var fresh_rate := 0.0
	var plain_rate := 0.0
	var plain := 0
	for d in range(0, 40, 2):
		for j in LocalSpace.board("new_houston__world", d, planet, lv):
			if String(j.destination_port_id) == "roosevelt_orbital_freight":
				if bool(j.fresh):
					fresh += 1
					fresh_rate += float(j.rate)
				else:
					plain += 1
					plain_rate += float(j.rate)
	check(fresh > 0 and plain > 0 and fresh_rate / fresh > plain_rate / plain, "fresh produce goes up from the downport, and pays better (%.0f against %.0f cr/t)" % [fresh_rate / maxf(1, fresh), plain_rate / maxf(1, plain)])
	check(Planets.fresh_left(10.0) == 1.0 and Planets.fresh_left(60.0) < 1.0 and Planets.fresh_left(500.0) == float(Planets.config().fresh.spoil_floor), "fresh food keeps for its shelf life, then loses value, down to compost")
	var kesh := LocalSpace.max_landing_cargo_t(planet, "keshar", "world")
	var earth := LocalSpace.max_landing_cargo_t(planet, "sol", "world")
	check(kesh < earth and kesh > 0.0, "the same ship lands less on Keshar than on Earth (%.0f t against %.0f t)" % [kesh, earth])
	var rows := []
	for r in Contracts.check(planet, CargoManifest.new(ShipData.new(ModuleLibrary.new())), {"surface": true, "origin_system_id": "keshar", "destination_system_id": "keshar", "origin_port_id": "keshar_highport", "destination_port_id": "keshar__world", "offer": 40.0, "min_twr": 0.0, "commodity": &"grain"}):
		if String(r.get("label", r.get("name", ""))).begins_with("Lift for"):
			rows.append(r)
	check(rows.size() == 1 and not bool(rows[0].get("ok", true)), "the contract check wants lift for 1.35 g on Keshar, and 40 t is too much")

	print("the ground")
	var t1 := PlanetTerrain.make_planet("sol", "world")
	var t2 := PlanetTerrain.make_planet("sol", "world")
	check(is_equal_approx(t1.height(3100.0, -7200.0), t2.height(3100.0, -7200.0)), "the same ground every visit")
	check(absf(t1.height(20.0, -30.0) - t1.port_h) < 0.01 and absf(t1.height(t1.field_xz.x + 15.0, t1.field_xz.y) - t1.field_h) < 0.01, "the downport's pad and the field are graded flat")
	check(t1.city_xz.length() > 4000.0 and t1.city_xz.distance_to(t1.field_xz) > 3000.0, "the city stands a few km off, away from the field")
	var tm := PlanetTerrain.make_planet("tidemark", "world")
	check(tm.platform and not tm.is_water(0.0, 0.0) and tm.is_water(15000.0, 9000.0), "Tidemark is open sea, with the downport on a platform")
	var dry := PlanetTerrain.make_planet("talos", "world")
	check(not dry.is_water(15000.0, 9000.0), "Talos is dry land")

	print("air and weather")
	check(Planets.breathable("keshar", "world", "kesh") and not Planets.breathable("keshar", "world", "human"), "Keshar's air is breathable to the Kesh and nobody else")
	check(not Planets.breathable("sol", "mars", "human") and Planets.breathable("sol", "world", "orun"), "nobody breathes on Mars; anyone on Earth")
	var w1 := Planets.weather("tidemark", "world", 1002)
	check(Planets.weather("tidemark", "world", 1004).kind == w1.kind and (w1.wind as Vector3).is_equal_approx(Planets.weather("tidemark", "world", 1004).wind), "the weather holds for its six hours, the same for everyone")
	var gales := 0
	for h in range(0, 24 * 60, 6):
		if float(Planets.weather("tidemark", "world", h).speed) >= 17.0:
			gales += 1
	var calm := 0
	for h in range(0, 24 * 60, 6):
		if float(Planets.weather("hesperus", "world", h).speed) >= 17.0:
			calm += 1
	check(gales > calm, "storm-prone Tidemark blows gales more often than Hesperus (%d against %d)" % [gales, calm])
	Hazards.off = true
	check(float(Planets.weather("tidemark", "world", 1000).speed) == 0.0, "Hazards.off stills the wind for tests about something else")
	Hazards.off = false

	print("coming down")
	var earth_auto := _entry("sol", "world")
	check(bool(earth_auto.landed) and bool(earth_auto.on_pad) and float(earth_auto.damage) < 0.01, "Earth on the autopilot: down on the pad, unhurt (%.0f s, %.1f t of fuel, heat peak %d%%)" % [float(earth_auto.t), float(earth_auto.fuel), roundi(float(earth_auto.peak) * 100.0)])
	check(float(earth_auto.peak) < 1.0 and float(earth_auto.peak) > 0.4, "belly first it runs warm, not over the limit")
	var bare := _entry("sol", "world", "auto", 0.0)
	check(float(bare.peak) > float(earth_auto.peak), "with no heat shield it runs hotter (%d%% against %d%%)" % [roundi(float(bare.peak) * 100.0), roundi(float(earth_auto.peak) * 100.0)])
	var nose := _entry("sol", "world", "nose")
	check(float(nose.peak) > 2.0 and float(nose.burn_s) > 10.0 and float(nose.damage) > 0.5, "nose first it burns (heat peak %d%%, %.0f s over the limit, hull %d%% gone)" % [roundi(float(nose.peak) * 100.0), float(nose.burn_s), roundi(float(nose.damage) * 100.0)])
	var mars := _entry("sol", "mars")
	check(bool(mars.on_pad) and float(mars.damage) < 0.01 and float(mars.peak) < 0.2, "Mars's thin air hardly heats or brakes: the jets do the work, and land her (%.1f t)" % float(mars.fuel))
	check(float(mars.fuel) > float(earth_auto.fuel), "which costs more fuel than Earth")
	for sys in ["ilos", "veyara", "tidemark", "foundry", "lastlight"]:
		var r := _entry(sys, "world")
		check(bool(r.on_pad) and float(r.damage) < 0.01, "%s on the autopilot: on the pad (%.0f s, %.1f t)" % [sys, float(r.t), float(r.fuel)])
	var heavy := _entry("keshar", "world", "auto", -1.0, 4.0)
	check(bool(heavy.on_pad) and float(heavy.damage) < 0.05, "Keshar at 1.35 g with a light load: down on the pad")
	print("%d failed" % fails if fails else "all passed")
	quit(1 if fails else 0)
