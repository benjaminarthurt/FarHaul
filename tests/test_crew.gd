extends SceneTree
## Crew (Crew, CrewWork): people looking for work at a bar, with names in their own people's styles;
## hiring (a free berth and a day's pay up front) and letting go (two days' severance); wages on the
## daily running costs; a ship that needs more hands than it has can't take freight; and what each role
## is worth: the engineer slows wear and services parts, the deck tech fixes the hull (same rules as a
## space walk), the pilot flies leaner and takes the brake point, the loadmaster saves the load and the
## camp crew's share, the steward earns better fares.
## Run: godot --headless --path . --script res://tests/test_crew.gd
var fails := 0
func check(ok: bool, msg: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + msg)
	if not ok:
		fails += 1
func _initialize() -> void:
	SaveSlots.dir = "user://test_saves_crew_%d" % OS.get_process_id()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SaveSlots.dir))
	process_frame.connect(_run, CONNECT_ONE_SHOT)


func _fit(preset: Array) -> String:
	var data := SaveSlots.read(Session.slot)
	var ship := ShipData.new(ModuleLibrary.new())
	var err := ShipPresets.build(ship, preset)
	data["modules"] = (JSON.parse_string(ship.to_json()) as Dictionary)["modules"]
	data["cargo"] = CargoManifest.new(ship).to_dict()
	SaveSlots.write(Session.slot, data)
	SimWorld.sync(Session.sim, Session.profile, ship)
	return err


func _ship() -> ShipData:
	return Session._load_ship(SaveSlots.read(Session.slot)).ship


func _person(role: String, skill: int) -> Dictionary:
	return {"id": "t-%s-%d" % [role, skill], "name": "Test %s" % role.capitalize(), "species": "human", "role": role, "skill": skill,
			"wage": roundi(Crew.base_wage(role, skill)), "line": "", "hired_day": 0}


func _run() -> void:
	print("people looking for work")
	var a := Crew.candidates("roosevelt_orbital_freight", 5, 1.0)
	var b := Crew.candidates("roosevelt_orbital_freight", 5, 1.0)
	var roles := {}
	var named := true
	for i in a.size():
		roles[String(a[i].role)] = true
		named = named and String(a[i].name).contains(" ") and String(a[i].name) == String(b[i].name)
	check(a.size() == 4 and roles.size() >= 3 and named, "four people at the bar, a spread of jobs, with full names, the same all day: %s" % ", ".join(a.map(func(p): return "%s (%s %d)" % [p.name, p.role, p.skill])))
	check(Crew.candidates("roosevelt_orbital_freight", 6, 1.0)[0].name != a[0].name or Crew.candidates("roosevelt_orbital_freight", 6, 1.0)[1].name != a[1].name, "and different people tomorrow")
	check(Crew.candidates("roosevelt_orbital_freight", 5, 1.0, [String(a[0].id)]).size() == 3, "someone hired (or let go) isn't offered again")
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var styles := {}
	for sp in ["human", "kesh", "ilyan", "vey", "orun"]:
		styles[sp] = Crew.make_name(sp, rng)
	check(String(styles.orun).contains(" of ") and String(styles.kesh).split(" ").size() == 2 and String(styles.human).split(" ").size() == 2, "names in each people's own style: %s" % str(styles.values()))
	var counts := [0, 0, 0, 0, 0, 0]
	for d in 200:
		for p in Crew.candidates("x", d, 1.0):
			counts[int(p.skill)] += 1
	check(counts[2] > counts[5] and counts[1] > 0 and counts[5] > 0, "skill 1 to 5, mostly middling and a few good (%s)" % [counts.slice(1)])
	check(is_equal_approx(Crew.base_wage("engineer", 5), 400.0 * 1.3) and is_equal_approx(Crew.base_wage("steward", 1), 280.0 * 0.9), "better hands cost more")

	print("what they're worth")
	var eng := [_person("engineer", 5)]
	check(is_equal_approx(Crew.wear_mult(eng), 0.6) and is_equal_approx(Crew.wear_mult([]), 1.0), "a skill 5 engineer: parts wear at 60%")
	check(is_equal_approx(Crew.fuel_mult([_person("pilot", 3)]), 0.88) and is_equal_approx(Crew.time_mult([_person("pilot", 3)]), 0.88), "a skill 3 pilot: 12% less fuel and time")
	check(is_equal_approx(Crew.cargo_hurt_mult([_person("loadmaster", 4)]), 0.4) and is_equal_approx(Crew.fare_mult([_person("steward", 2)]), 1.1), "a loadmaster saves the load, a steward earns better fares")
	check(Crew.skill([_person("pilot", 2), _person("pilot", 4)], "pilot") == 4, "two of a kind: the better one counts")
	check(Crew.pick_mark([1, 2, 3], 0.3, 0) == 2 and Crew.pick_mark([1, 3], 0.3, 0) == -1 and Crew.pick_mark([1, 3], 0.3, 1) == 1 and Crew.pick_mark([2], 0.5, 9) == -1,
			"the deck tech's rules: plating first, holes need a kit, nothing past 50%")

	print("hiring and firing")
	Session.begin_new(2, "Test Captain", "human", "normal", "roosevelt_independent_yards")
	check((Session.profile.get("crew", null) as Array) != null and Session.crew().is_empty() and Session.crew_aboard() == 1, "a new captain flies alone")
	var cands := Session.crew_candidates()
	check(cands.size() == 4, "the bar has people looking for a berth")
	var r := Session.hire(String(cands[0].id))
	check(not bool(r.ok) and String(r.message).contains("bunk"), "the starter has one bunk, and it's yours: %s" % r.message)
	check(_fit(ShipPresets.STARTER_CABIN) == "", "fit two crew bunks")
	Session.profile["hints_seen"] = ["welcome"]
	check(Hints._fits("crew", {}), "an empty bunk: the concourse points you at the bar")
	var cr := int(Session.profile.credits)
	var cost0 := SimWorld.daily_cost(Session.sim)
	var first: Dictionary = cands[0]
	r = Session.hire(String(first.id))
	var mult := float(SimShip.level("normal").get("wage_mult", 1.0))
	check(bool(r.ok) and Session.crew().size() == 1 and cr - int(Session.profile.credits) == roundi(float(first.wage) * mult), "signed on for a day's pay up front: %s" % r.message)
	check(absf(SimWorld.daily_cost(Session.sim) - cost0 - float(first.wage) * mult) < 1.0, "their wage goes on the running costs (%.0f -> %.0f cr/day)" % [cost0, SimWorld.daily_cost(Session.sim)])
	var lines := SimWorld.payroll_lines(Session.sim)
	check(lines.size() == 2 and String(lines[1].role).contains(String(first.name)), "the payroll names them: %s" % [lines])
	check(not Session.crew_candidates().any(func(p): return String(p.id) == String(first.id)), "and they've left the bar")
	r = Session.hire(String(Session.crew_candidates()[0].id))
	check(bool(r.ok) and Session.crew_aboard() == 3, "a second hand for the second bunk")
	r = Session.hire(String(Session.crew_candidates()[0].id))
	check(not bool(r.ok) and String(r.message).contains("bunk"), "and no third: %s" % r.message)
	var who: Dictionary = Session.crew()[0]
	cr = int(Session.profile.credits)
	r = Session.fire(String(who.id))
	check(bool(r.ok) and Session.crew().size() == 1 and cr - int(Session.profile.credits) == roundi(float(who.wage) * 2.0 * mult), "let go with two days' severance: %s" % r.message)
	check(not Session.crew_candidates().any(func(p): return String(p.id) == String(who.id)), "and they don't come crawling back the same day")
	Session.fire(String(Session.crew()[0].id))

	print("a ship that needs hands")
	var st := Session.ship_stats(_ship())
	st["crew_needed"] = 3
	var job := {"min_twr": 0.0, "offer": 1.0, "commodity": "water", "origin_system_id": "a", "destination_system_id": "a"}
	var rows := Contracts.check(st, Session._load_ship(SaveSlots.read(Session.slot)).manifest, job)
	var row: Dictionary = rows.filter(func(x): return String(x.label) == "Crew aboard")[0]
	check(not bool(row.ok) and String(row.detail).contains("hire"), "a ship needing three aboard won't take freight with one: %s" % row.detail)

	print("on the way, between trips")
	Session.profile["crew"] = [_person("deck_tech", 3), _person("engineer", 3)]
	Session.profile["hull_damage"] = 0.8
	Session.profile["hull_patches"] = []
	Session.profile["patch_kits"] = 1
	var w := {}
	for p in Wear.parts(_ship(), {}):
		w[String(p.key)] = 0.9
	Session.profile["wear"] = w
	Session.save_profile()
	r = Session.wait_days(1)
	var fixed := (Session.profile.hull_patches as Array).size()
	check(fixed > 0 and float(Session.profile.hull_damage) < 0.8 and r.message.contains("In port"), "a day in port: the deck tech fixed %d marks and the engineer saw to the parts: %s" % [fixed, r.message])
	check(Session.patch_kits() == 1 and (Session.profile.hull_patches as Array).all(func(i): return not ShipDamage.needs_kit(int(i))), "loose plating first, which is free: the patch kit is kept for the holes")
	Session.profile["hull_damage"] = 0.8
	Session.profile["hull_patches"] = [0, 2, 4, 6, 8, 10, 12, 14]   # all the plating's done: only holes left
	Session.wait_days(1)
	check(Session.patch_kits() == 0 and (Session.profile.hull_patches as Array).filter(func(i): return ShipDamage.needs_kit(int(i))).size() == 1, "then one hole with the one kit, and the other holes wait for kits")
	var worst := 0.0
	for k in Session.wear():
		worst = maxf(worst, float(Session.wear()[k]))
	check(worst < 0.9, "worn parts serviced (worst now %d%%)" % Wear.condition(worst))
	Session.profile["hull_damage"] = 0.55
	Session.profile["hull_patches"] = []
	Session.wait_days(3)
	check(is_equal_approx(Session.hull(), 0.5), "but no further than 50%%: %d%%" % roundi(Session.hull() * 100.0))
	for k in w:
		w[k] = 1.0
	Session.profile["wear"] = w.duplicate()
	Session.profile["spares_kits"] = 1
	Session.wait_days(1)
	var revived := 0
	for k in Session.wear():
		if float(Session.wear()[k]) < 1.0:
			revived += 1
	check(revived == 1 and Session.spares_kits() == 0, "a failed part comes back only with a spares kit (%d revived)" % revived)

	print("the pilot, between trips")
	Session.profile["wear"] = {}
	Session.profile["hull_damage"] = 0.0
	Session.profile["crew"] = []
	Session.save_profile()
	var sites := Session.local_sites()
	var cost_alone := float(sites[0].cost)
	Session.profile["crew"] = [_person("pilot", 5)]
	var cost_pilot := float(Session.local_sites()[0].cost)
	check(cost_pilot < cost_alone, "a pilot burns less getting there (%.0f vs %.0f cr)" % [cost_pilot, cost_alone])
	Session.profile["crew"] = []
	Session.save_profile()
	Session._sync_sim(_ship())
	var speed0 := float(Session.sim.carriers[SimWorld.PLAYER].speed)
	var burn0 := float(Session.sim.carriers[SimWorld.PLAYER].burn)
	Session.profile["crew"] = [_person("pilot", 5)]
	Session._sync_sim(_ship())
	check(float(Session.sim.carriers[SimWorld.PLAYER].burn) < burn0 and (speed0 == 0.0 or float(Session.sim.carriers[SimWorld.PLAYER].speed) > speed0), "and between stars: faster and leaner")
	Session.profile["crew"] = []
	Session.save_profile()

	print("old saves")
	Session.profile.erase("crew")
	Session.save_profile()
	check(Session.load_slot(2) and Session.profile.has("crew") and Session.crew().size() == maxi(0, SimShip.crew_for(float(ShipStats.compute(_ship()).cargo_capacity)) - 1),
			"a save from before named crew gets the hands its ship needed, by name")
	var old := Session.profile.duplicate(true)
	Session.profile.erase("crew")
	Session._migrate_crew(_ship(), 2)   # a bigger ship's two hands
	var mig := Session.crew()
	check(mig.size() == 2 and String(mig[0].role) == "engineer" and String(mig[1].role) == "deck_tech" and String(mig[0].name).contains(" "), "a ship that needed two hands keeps an engineer and a deck tech: %s, %s" % [mig[0].name, mig[1].name])
	Session.profile = old

	print("in flight")
	Session.profile["crew"] = [_person("deck_tech", 5), _person("engineer", 5)]
	Session.profile["hull_damage"] = 0.8
	Session.profile["hull_patches"] = []
	Session.profile["patch_kits"] = 0
	Session.profile["spares_kits"] = 0
	w = {}
	for p in Wear.parts(_ship(), {}):
		w[String(p.key)] = 0.85
	Session.profile["wear"] = w
	Session.save_profile()
	Session.flight_job = {}
	var f: Node = load(Session.FLIGHT_SCENE).instantiate()
	root.add_child(f)
	current_scene = f
	await process_frame
	f.set_process(false)
	f.model.pos = Vector3(0, 0, 3000)
	f.model.vel = Vector3(0, 0, 40)
	f.model.throttle = 0.0
	f._update_hud()
	check(f.hud.text.contains("CREW") and f.hud.text.contains("DECK TECH"), "the HUD lists the crew")
	f.get_up()
	f.crew_c.step(0.0)
	check(f.crew_c.figures.size() == 2 and f.crew_c.figures.all(func(x): return x.visible), "walk the ship and they're at their posts")
	f.walk.pos = f.crew_c.figures[0].position + Vector3(0.5, 0, 0)
	check(f.crew_c.near_line().contains("TEST"), "walk up to one and they have something to say: %s" % f.crew_c.near_line())
	f.sit_down()
	f.crew_c.step(0.0)
	check(not f.crew_c.figures[0].visible, "and from the helm you don't see through walls")
	var d0: float = f.model.damage
	f.crew_c.step(60.0)
	check(f.model.damage < d0 and f.crew_c.jobs >= 1 and f.notice.contains("Test"), "engines quiet: the deck tech goes out and fixes a mark: %s" % f.notice)
	var shown_before: int = f.view._damage.visible_marks().size()
	f.model.throttle = 0.8
	var d1: float = f.model.damage
	f.crew_c.step(60.0)
	check(is_equal_approx(f.model.damage, d1), "under thrust, nobody goes outside")
	f.model.throttle = 0.0
	var w0: float = f.wear.values().max()
	f.crew_c.engineer_t = 1000.0
	f.crew_c.step(0.01)
	check(float(f.wear.values().min()) < w0 or float(f.wear.values().max()) < w0, "the engineer services a worn part in flight: %s" % f.notice)
	var before_wear: float = f.wear.values().reduce(func(acc, x): return acc + float(x), 0.0)
	f.model.throttle = 1.0
	var plain := {}
	plain.merge(f.wear)
	f._wear_step(10.0)
	var gained: float = f.wear.values().reduce(func(acc, x): return acc + float(x), 0.0) - before_wear
	check(gained > 0.0 and is_equal_approx(f.crew_c.wear_mult, 0.6), "and everything wears slower with them aboard (x%.1f)" % f.crew_c.wear_mult)
	f.model.throttle = 0.0
	f.crew_c.after_jump(72.0)
	check(f.model.damage < d1 and shown_before > 0, "three days' jump: the crew worked the whole way")
	f.queue_free()
	await process_frame

	print("the pilot at the helm")
	Session.profile["crew"] = [_person("pilot", 3)]
	Session.profile["hull_damage"] = 0.0
	Session.profile["wear"] = {}
	Session.save_profile()
	f = load(Session.FLIGHT_SCENE).instantiate()
	root.add_child(f)
	current_scene = f
	await process_frame
	f.set_process(false)
	f.model.pos = Vector3(0, 0, 3000)
	f.model.throttle = 0.6
	f.get_up()
	f.walk.stand_in_airlock()
	f.use()
	check(f.eva != null and is_equal_approx(f.model.throttle, 0.0) and f.foot_c._eva_ui != null, "out of the airlock: the pilot cut the engines first")
	f.eva.pos = f.eva.hatch
	var q := InputEventKey.new()
	q.keycode = KEY_Q
	q.pressed = true
	f._unhandled_input(q)
	f.queue_free()
	await process_frame
	var job2: Dictionary = {}
	for o in Contracts.offers_from(Session.system_id()):
		if bool(o.get("local", false)) and String(o.get("person_kind", "")) == "":
			job2 = o
	var ok := bool(Session.accept_contract(job2).ok) and bool(Session.begin_local_flight().ok)
	check(ok, "a run to fly")
	f = load(Session.FLIGHT_SCENE).instantiate()
	root.add_child(f)
	current_scene = f
	await process_frame
	f.set_process(false)
	var to0: Vector3 = (f.xfer.target - f.model.pos).normalized()
	f.phase = "cruise"
	f.station.visible = false
	f.model.station_solid = false
	f.model.pos = f.xfer.target - to0 * 5000000.0
	f.model.vel = to0 * 1200.0
	f.model.basis = Basis.looking_at(to0, Vector3.UP)
	f.get_up()
	f._process(0.05)
	check(not f.model.braking and not f.xfer.brake_now(f.model), "far out, the pilot lets her coast")
	f.model.pos = f.xfer.target - to0 * 400000.0
	var t := 0.0
	while t < 600.0 and not f.model.braking:
		f._process(0.05)
		t += 0.05
	check(f.model.braking and f.model.brake_to == f.xfer.target and f.walking, "the captain's off having a sandwich: the pilot takes the brake point (%.0f s): %s" % [t, f.notice])
	f.queue_free()
	await process_frame
	Session.flight_job = {}

	print("delivering")
	var data := SaveSlots.read(Session.slot)
	data.erase("active_contract")
	SaveSlots.write(Session.slot, data)
	Session.profile["crew"] = [_person("loadmaster", 4)]
	Session.flight_extra = {"cargo_hurt": 0.5}
	var c := {"person_kind": ""}
	var note := Session._settle_hull({}, c, 100000.0)
	check(absf(float(c.get("cargo_hurt", 0.0)) - 0.2) < 0.001, "a loadmaster's lashings: half the load would have been dented, a fifth is (%s)" % note.strip_edges())
	Session.profile["crew"] = [_person("steward", 4)]
	Session.profile["flight_extra"] = {}
	Session.save_profile()
	var fare := {}
	for i in 25:
		for j in Session.people_here():
			if String(j.person_kind) == "passenger" and int(j.seats) == 1 and int(j.get("wants", 0)) == 0 and not j.has("locked"):
				fare = j
		if not fare.is_empty():
			break
		Session.wait_days(1)
	check(not fare.is_empty(), "a passenger wants the one bunk left")
	if not fare.is_empty():
		r = Session.accept_contract(fare)
		check(bool(r.ok), "aboard: %s" % r.message)
		var rep0 := int(Session.profile.get("rep", 0))
		r = Session.local_reposition(String(fare.destination_port_id))   # passengers ride along: no contract needed
		check(String(r.message).contains("care") and int(Session.profile.get("rep", 0)) > rep0, "looked after by the steward: a better fare, and they say so: %s" % r.message)
	Session.profile["crew"] = []
	check(absf(float(Session.sim.summary()["cash_error"])) < 0.01, "money conserved")
	print("DONE fails=", fails)
	quit(1 if fails > 0 else 0)
