extends SceneTree
## Danger without combat (scripts/sim/hazards.gd, scripts/flight/hazard_watch.gd, Rivals' claim-jumpers):
## storms come by schedule, more on the frontier, with forecasts, sensor warnings and surprises; debris
## fields lie across some routes, hurt more the faster you go, and less with the autopilot flying; an
## autopilot trip through them costs hull and radiators; storms hold the haulers in port and starve the
## outposts; in a flight a storm cooks the radiators and a field's rocks hit; claim-jumpers ignore your
## beacon, won't deal, and can be reported for a bounty.
## Run: godot --headless --path . --script res://tests/test_hazards.gd

var fails := 0


func check(ok: bool, what: String) -> void:
	print(("  ok    " if ok else "  FAIL  ") + what)
	if not ok:
		fails += 1


func _initialize() -> void:
	SaveSlots.dir = "user://test_saves_hazards_%d" % OS.get_process_id()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SaveSlots.dir))
	process_frame.connect(_run, CONNECT_ONE_SHOT)


func _first_storm(sys: String, from_h: int, warn := "any") -> Dictionary:
	for s in Hazards.storms(sys, from_h, from_h + 24 * 400):
		if warn == "any" or String(s.warn) == warn:
			return s
	return {}


func _wear_total() -> float:
	var t := 0.0
	for k in Session.wear():
		t += float(Session.wear()[k])
	return t


func _run() -> void:
	print("storms")
	var w := int(Hazards.config().storms.window_hours)
	var counts := {}
	for sys in ["sol", "lastlight"]:
		var n := 0
		for win in 2000:
			if not Hazards._storm_in(sys, win).is_empty():
				n += 1
		counts[sys] = n
	check(int(counts.lastlight) > int(counts.sol) * 2, "the frontier gets more storms than Sol (%d against %d in 2000 windows)" % [int(counts.lastlight), int(counts.sol)])
	var a := Hazards._storm_in("lastlight", 77)
	Hazards._cache.clear()
	check(a == Hazards._storm_in("lastlight", 77), "the same storm every time anyone looks")
	var kinds := {"forecast": 0, "sensors": 0, "": 0}
	for win in 3000:
		var s := Hazards._storm_in("talos", win)
		if not s.is_empty():
			kinds[String(s.warn)] = int(kinds[String(s.warn)]) + 1
	check(int(kinds.forecast) > 0 and int(kinds.sensors) > 0 and int(kinds[""]) > 0, "some forecast, some only on sensors, some unannounced (%s)" % str(kinds))
	var f := _first_storm("talos", 0, "forecast")
	check(Hazards.known("talos", int(f.warn_at) - 1).filter(func(x): return x.start == f.start).is_empty() and
			not Hazards.known("talos", int(f.warn_at)).filter(func(x): return x.start == f.start).is_empty(), "a forecast storm is known from its forecast on")
	var sn := _first_storm("talos", 0, "sensors")
	check(Hazards.known("talos", int(sn.warn_at)).filter(func(x): return x.start == sn.start).is_empty() and
			not Hazards.known("talos", int(sn.warn_at), true).filter(func(x): return x.start == sn.start).is_empty(), "a sensor-only storm shows only to the ship's sensors")
	var sp := _first_storm("talos", 0, "")
	check(Hazards.known("talos", int(sp.start) - 1, true).filter(func(x): return x.start == sp.start).is_empty() and not Hazards.storm_at("talos", int(sp.start)).is_empty(),
			"and some arrive with no warning at all")
	check(is_equal_approx(Hazards.exposure("talos", int(f.start), float(int(f.end) - int(f.start))), float(int(f.end) - int(f.start)) * float(f.intensity)), "a trip through the whole storm takes all of it")
	check(Hazards.exposure("talos", int(f.end), 3.0) == 0.0 or not Hazards.storm_at("talos", int(f.end)).is_empty(), "and none after it's over")

	print("debris")
	var field := {}
	var day := 0
	while field.is_empty() and day < 3000:
		field = Hazards.local_field("sol", "port", "moon", day)
		day += 30
	check(not field.is_empty() and field == Hazards.local_field("sol", "moon", "port", day - 30), "a field lies across the Sol port to moon hop some months, either way round")
	var slow := Hazards.hit_damage(100.0)
	var fast := Hazards.hit_damage(2000.0)
	check(fast > slow * 3.0 and Hazards.hit_damage(1e6) <= float(Hazards.config().debris.damage_max), "faster hurts more (%.3f at 100 m/s, %.3f at 2 km/s), up to a cap" % [slow, fast])
	check(is_equal_approx(Hazards.hit_rate_per_km(field, true), Hazards.hit_rate_per_km(field, false) * float(Hazards.config().debris.autopilot_rate)), "the autopilot hits about a third as often")
	var dense := {"density": 1.0, "radius_m": 4000.0, "along": 0.5, "offset": 0.0, "seed": 7}
	check(is_equal_approx(Hazards.crossing_km(dense), 8.0) and Hazards.crossing_km({"density": 1.0, "radius_m": 4000.0, "offset": 1.05}) == 0.0, "a route through the middle crosses its width; one that misses crosses none")
	var total := 0.0
	var hits := 0
	for i in 200:
		var r := Hazards.trip([], dense, false, "t%d" % i)
		total += float(r.hull)
		hits += int(r.hits)
	check(hits > 200 and total / 200.0 < 0.15, "threading a dense field on autopilot: %.1f hits and %.1f%% of the hull on average" % [hits / 200.0, total / 2.0])

	print("an autopilot trip")
	Session.begin_new(1, "Tester", "human", "normal", "roosevelt_independent_yards")
	var sys := Session.system_id()
	var data := SaveSlots.read(Session.slot)
	var loaded := Session._load_ship(data)
	var hull0 := float(Session.profile.get("hull_damage", 0.0))
	var rad0 := _wear_total()
	var st := _first_storm(sys, Session.sim.now_hour())
	var msg := Session._en_route(loaded.ship, [{"id": sys, "from_h": int(st.start), "hours": float(int(st.end) - int(st.start))}], dense, false, "test")
	check(float(Session.profile.hull_damage) > hull0 and _wear_total() > rad0, "a trip through a storm and a field costs hull and wear")
	check(msg.contains("solar storm") and msg.contains("debris"), "and says so: %s" % msg.strip_edges())

	print("the economy feels a storm")
	var sim := Session.sim
	var storm := _first_storm(sys, sim.now_hour() + 48)
	var keep_h := sim.hour
	sim.hour = int(storm.start) + 2 - sim.start_day * 24
	check(not sim._eligible({"network": [sys, "concord"]}, {"systems": [sys, "concord"]}), "nobody is dispatched to or from a system mid-storm")
	sim.hour = int(storm.start) - 30 - sim.start_day * 24
	check(sim._eligible({"network": [sys, "concord"]}, {"systems": [sys, "concord"]}) or not Hazards.storm_at("concord", sim.now_hour()).is_empty(), "but they are before it")
	var port := String(Worlds.primary_port(sys).id)
	sim.dev.day = -1
	Development.day_turned(sim)
	var calm := float(sim.dev.sites[port].npc)
	sim.hour = int(storm.start) + 2 - sim.start_day * 24
	Development.day_turned(sim)
	var during := float(sim.dev.sites[port].npc)
	check(during < calm * (1.0 - 0.8 * float(storm.intensity)) * 1.2, "the port's traffic dries up while it rages (%.2f against %.2f)" % [during, calm])
	sim.hour = keep_h

	print("in a flight")
	var fl: Node = load("res://scenes/flight.tscn").instantiate()
	root.add_child(fl)
	current_scene = fl
	await process_frame
	fl.set_process(false)
	var hw: HazardWatch = fl.hazard_c
	hw.start_h = int(storm.start) + 1
	var cool0: float = fl.model.cooling_now_kw()
	var hulls: float = fl.model.damage
	hw.step(600.0)
	check(fl.model.storm_cooling > 0.0 and fl.model.cooling_now_kw() < cool0, "a storm takes the radiators' cooling (%.0f kW from %.0f)" % [fl.model.cooling_now_kw(), cool0])
	check(fl.model.damage > hulls, "and a little hull")
	hw.start_h = int(storm.end) + 2
	hw.step(1.0)
	check(fl.model.storm_cooling == 0.0, "and gives it back when it's past")
	hw.field = dense
	hw.radius = 4000.0
	hw.centre = fl.model.pos
	hw._rng.seed = 3
	fl.model.vel = Vector3(0, 0, -1500)
	var d0: float = fl.model.damage
	for i in 40:
		hw.step(0.1)
	var by_hand: int = hw.hits
	check(by_hand > 0 and fl.model.damage > d0, "flying through a field at 1.5 km/s by hand: %d hits, %.0f%% of the hull" % [by_hand, (fl.model.damage - d0) * 100.0])
	hw.hits = 0
	fl.model.course_hold = true
	var sum_auto := 0
	var sum_hand := 0
	for trial in 30:
		fl.model.damage = 0.0   # a battered ship shuts down, autopilot and all
		hw._rng.seed = trial
		fl.model.course_hold = true
		hw.hits = 0
		for i in 40:
			hw.step(0.1)
		sum_auto += hw.hits
		fl.model.damage = 0.0
		hw._rng.seed = trial
		fl.model.course_hold = false
		hw.hits = 0
		for i in 40:
			hw.step(0.1)
		sum_hand += hw.hits
	check(sum_auto < sum_hand * 0.6, "the autopilot takes fewer hits than flying by hand (%d against %d)" % [sum_auto, sum_hand])
	fl.queue_free()
	await process_frame

	print("claim-jumpers")
	Session.flight_job = {}
	var f2: Node = load("res://scenes/flight.tscn").instantiate()
	root.add_child(f2)
	current_scene = f2
	await process_frame
	f2.set_process(false)
	var t: Traffic = f2.traffic_c
	t.cfg["derelicts"]["chance"] = 1.0
	t.rebuild(String(Session.profile.port_id))
	var rc := Rivals.cfg()
	rc["chance"] = 1.0
	rc["there_first"] = 0.0
	Hazards.config().jumpers["chance"] = 1.0
	Hazards.config().jumpers["patrol_chance"] = 0.0
	f2.comms_c.rivals = Rivals.new(f2.comms_c)
	var dr: Dictionary = t.derelicts[0]
	var wk: NpcShip = dr.ship
	Session.profile["claim_beacons"] = 2
	f2.model.pos = wk.global_position + Vector3(0, 0, 900)
	f2.model.vel = Vector3.ZERO
	for i in 2:
		f2.comms_c.step(0.1, 0.0)
	f2.comms_c.rivals._fire(String(dr.id_base))
	var rv: Dictionary = f2.comms_c.rivals._rival_for(dr)
	rv.t = 0.0
	for i in 3:
		f2.comms_c.step(0.1, 0.0)
	check(Rivals.jumping(rv), "a crew comes to a wreck under your beacon anyway")
	var c: Dictionary = {}
	for x in f2.comms_c.contacts():
		if String(x.kind) == "rival":
			c = x
	var ids := []
	for o in c.get("options", []):
		ids.append(String(o.id))
	check("report" in ids, "the radio offers to report them")
	var warn: Dictionary = f2.comms_c.rivals.act(c, "warn")
	check(String(warn.message).contains("don't deal") and String(rv.state) != "leaving", "telling them to clear off does nothing")
	for i in 600:
		f2.comms_c.step(1.0, 0.0)
		if int(rv.get("took", 0)) >= 2:
			break
	var rep: Dictionary = f2.comms_c.rivals.act(c, "report")
	check(bool(rep.ok) and bool(rv.reported), "reported: %s" % String(rep.message))
	var sett: Dictionary = f2.comms_c.settlement()
	check(int(sett.get("bounty_cr", 0)) > 0 and int(sett.rep) >= int(Hazards.config().jumpers.report_rep), "the port authority pays a bounty on what they took (%s cr) and your standing goes up" % ShipStats.commas(int(sett.get("bounty_cr", 0))))
	print("%d failed" % fails if fails else "all passed")
	quit(1 if fails else 0)
