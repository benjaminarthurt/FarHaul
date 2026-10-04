extends SceneTree
## Sublight play: a starter with no FTL drive works inside its system.
## Run: godot --headless --path . --script res://tests/test_local_space.gd

var fails := 0

func check(ok: bool, msg: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + msg)
	if not ok:
		fails += 1

func _initialize() -> void:
	SaveSlots.dir = "user://test_saves_local"
	for f in DirAccess.get_files_at(SaveSlots.dir):
		DirAccess.remove_absolute(SaveSlots.dir + "/" + f)
	process_frame.connect(_run, CONNECT_ONE_SHOT)

func _run() -> void:
	print("sites and hops")
	var ns := LocalSpace.nodes("new_houston")
	check(ns.size() == 6 and String(ns[0].kind) == "port", "six sites (port, depot, moon base, belt, base pad, mining camp), the first is the main port")
	check(LocalSpace.is_surface(String(ns[4].id)) and LocalSpace.is_surface(String(ns[5].id)) and not LocalSpace.is_surface(String(ns[2].id)), "the pad and the camp are on the surface, the base station is not")
	check(String(ns[0].id) == String(Worlds.primary_port("new_houston").get("id", "")), "the main port keeps its real id")
	check(String(LocalSpace.node(String(ns[2].id)).get("kind", "")) == "moon", "synthetic ids resolve back to their site")
	check(LocalSpace.node("nowhere__moon").is_empty() and LocalSpace.node("nope").is_empty(), "unknown ids give nothing")
	var sym := true
	for a in LocalSpace.KINDS:
		for b in LocalSpace.KINDS:
			if a != b and LocalSpace.hop(a, b) != LocalSpace.hop(b, a):
				sym = false
	check(sym, "hops are the same both ways")

	print("rocket equation")
	var ve := LocalSpace.exhaust_velocity()
	check(absf(ve - 8829.0) < 1.0, "exhaust velocity %.0f m/s" % ve)
	check(absf(LocalSpace.burn_t(50.0, 1.2) - 50.0 * (1.0 - exp(-1.2 * 1000.0 / ve))) < 1e-6, "burn follows m(1-exp(-dv/ve))")
	check(LocalSpace.burn_t(60.0, 1.2) > LocalSpace.burn_t(40.0, 1.2), "heavier ships burn more")
	var cap := LocalSpace.max_cargo_t(29.3, 10.0, 1.2)
	check(absf(LocalSpace.burn_t(29.3 + cap, 1.2) - 10.0) < 1e-6, "max cargo burns exactly a full tank (%.1f t)" % cap)
	check(LocalSpace.max_cargo_t(29.3, 10.0, 5.5) < 0.0, "the belt is out of reach for the starter's tank")

	print("the board")
	var ship_stats := {"wet": 29.3, "fuel": 10.0, "cargo_capacity": 24.0}
	var lvl := {"local_pay_mult": 1.0}
	var a := LocalSpace.board(String(ns[0].id), 10, ship_stats, lvl)
	var b := LocalSpace.board(String(ns[0].id), 10, ship_stats, lvl)
	var c := LocalSpace.board(String(ns[0].id), 11, ship_stats, lvl)
	check(not a.is_empty() and a.size() <= 6, "jobs are posted (%d)" % a.size())
	check(JSON.stringify(a) == JSON.stringify(b), "the board is the same every time it is opened")
	check(JSON.stringify(a) == JSON.stringify(c), "and holds for the two-day window")
	check(JSON.stringify(a) != JSON.stringify(LocalSpace.board(String(ns[0].id), 14, ship_stats, lvl)), "then it changes")
	var sane := true
	for j in a:
		if float(j.offer) <= 0.0 or float(j.offer) > 24.0 or int(j.rate) <= 0 or String(j.destination_port_id) == String(j.origin_port_id) or not bool(j.local):
			sane = false
		if LocalSpace.burn_t(29.3 + float(j.offer), float(j.dv_kms)) > 10.0 + 1e-6:
			sane = false
	check(sane, "every job fits the hold and the tank")
	var taken := LocalSpace.board(String(ns[0].id), 10, ship_stats, lvl, [String(a[0].id)])
	check(taken.size() == a.size() - 1, "a job already done is not posted again")

	print("a sublight captain in a saved game")
	check(Session.begin_new(0, "Test Captain", "human", "normal", "roosevelt_independent_yards"), "new game")
	check(not bool(SimWorld.player(Session.sim)["ftl"]), "the starter has no FTL drive")
	check(float(SimWorld.player(Session.sim)["speed"]) == 0.0, "and no interstellar speed")
	check(bool(Session.profile.get("ftl_rules", 0) == 1) and not bool(Session.profile.get("ftl_grandfathered", false)), "new games use the FTL rules")
	check(SimWorld.destinations(Session.sim).is_empty(), "no systems are reachable")
	check(not bool(Session.travel_empty("sol").ok), "cannot fly empty between stars")
	var board := Contracts.offers_from("new_houston")
	var only_local := not board.is_empty()
	for o in board:
		if not o.has("local") and String(o.origin_system_id) != String(o.destination_system_id):
			only_local = false
	check(only_local, "the board holds only in-system work (%d jobs)" % board.size())
	var job: Dictionary = {}
	for o in board:
		if bool(o.get("local", false)):
			job = o
			break
	check(not job.is_empty(), "a local run is posted")
	if job.is_empty():
		print("DONE fails=", fails)
		quit(1)
		return
	var cr0 := int(Session.profile.credits)
	var h0 := Session.sim.hour
	var acc := Session.accept_contract(job)
	check(bool(acc.ok) and float(Session.active_contract().get("accepted_tonnes", 0)) > 0.0, "accept and load: %s" % acc.message)
	var dep := Session.depart_active_contract()
	check(bool(dep.ok), "depart: %s" % dep.message)
	check(Session.sim.hour == h0 + int(job.hours), "the hop took %d hours" % int(job.hours))
	check(String(Session.profile.port_id) == String(job.destination_port_id), "now at the destination site")
	check(Session.port().get("name", "") != "", "the dock can name the site: %s" % String(Session.port().get("name", "")))
	check(int(Session.profile.credits) < cr0, "fuel, fees and running costs came out first")
	var mid := int(Session.profile.credits)
	var dl := Session.deliver_active_contract()
	check(bool(dl.ok) and Session.active_contract().is_empty(), "deliver: %s" % dl.message)
	check(int(Session.profile.credits) > mid, "the consignee paid")
	check(absf(float(Session.sim.summary()["cash_error"])) < 0.01 and Session.sim.violations.is_empty(), "money conserved")
	var again := Contracts.offers_from("new_houston")
	var seen := false
	for o in again:
		if String(o.get("id", "")) == String(job.id):
			seen = true
	check(not seen, "the finished job is gone from the board")

	print("flying empty between sites")
	var sites := Session.local_sites()
	check(not sites.is_empty() and float(sites[0].cost) > 0.0, "reachable sites listed (%d)" % sites.size())
	var hs := Session.sim.hour
	var cs := int(Session.profile.credits)
	var tgt := String(sites[0].id)
	var rp := Session.local_reposition(tgt)
	check(bool(rp.ok) and String(Session.profile.port_id) == tgt and Session.sim.hour == hs + int(sites[0].hours), "repositioned: %s" % rp.message)
	check(int(Session.profile.credits) < cs and absf(float(Session.sim.summary()["cash_error"])) < 0.01, "it cost money and the books balance")
	check(not bool(Session.local_reposition("nowhere__belt").ok), "an unreachable site is refused")
	var price := Session.drive_price()
	check(price > 40000 and price < 60000, "a first drive costs about %d cr" % price)

	print("a flown run that does not arrive")
	var j2: Dictionary = {}
	for o in Contracts.offers_from("new_houston"):
		if bool(o.get("local", false)):
			j2 = o
			break
	check(not j2.is_empty() and bool(Session.accept_contract(j2).ok), "take another run")
	var site0 := String(Session.profile.port_id)
	var cr1 := int(Session.profile.credits)
	check(bool(Session.begin_local_flight().ok), "hand it to the helm")
	Session.finish_local_flight(0.5, 600.0, 0.0, false, false)
	check(String(Session.profile.port_id) == site0 and String(Session.active_contract().get("status", "")) == "loaded", "turning back leaves the load aboard at the start")
	var turned := cr1 - int(Session.profile.credits)
	check(turned > 0, "fuel and time cost %d cr" % turned)
	check(bool(Session.begin_local_flight().ok), "and it can be flown again")
	var cr2 := int(Session.profile.credits)
	Session.finish_local_flight(0.5, 600.0, 0.0, false, true)
	check(cr2 - int(Session.profile.credits) > turned, "a tow costs more than turning back (%d cr)" % (cr2 - int(Session.profile.credits)))
	check(not bool(Session.begin_local_flight().ok) == false, "still flyable after a tow")
	Session.flight_job = {}
	check(bool(Session.depart_active_contract().ok) and bool(Session.deliver_active_contract().ok), "or take the autopilot and deliver")

	print("old saves keep their jump ability")
	var data := SaveSlots.read(0)
	var p: Dictionary = data["profile"]
	p.erase("ftl_rules")
	p.erase("ftl_grandfathered")
	data["profile"] = p
	SaveSlots.write(0, data)
	Session.sim = null
	Session.slot = -1
	check(Session.load_slot(0), "load")
	check(bool(Session.profile.get("ftl_grandfathered", false)), "a save without the marker is grandfathered")
	var ship := ShipData.new(ModuleLibrary.new())
	ship.from_json(JSON.stringify(SaveSlots.read(0)))
	SimWorld.sync(Session.sim, Session.profile, ship)
	check(bool(SimWorld.player(Session.sim)["ftl"]) and float(SimWorld.player(Session.sim)["speed"]) > 0.5, "it can still jump (%.2f ly/day)" % float(SimWorld.player(Session.sim)["speed"]))
	Session.profile["credits"] = -5000
	check(Session.insolvent() and bool(Session.restructure().ok), "bankruptcy")
	check(not bool(Session.profile.get("ftl_grandfathered", false)), "the bank's hauler is sublight again")

	print("DONE fails=", fails)
	quit(1 if fails > 0 else 0)
