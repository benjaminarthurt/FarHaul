extends SceneTree
## Frontier growth (scripts/sim/development.gd): sites start at their canon size; the same world grows the
## same way every time; hauling to Luna grows it in weeks; a site nobody supplies empties and is
## abandoned (no desks, no freight, a pump and fittings to strip); stages give their services and prices;
## a grown system makes and uses more; growth survives a save; the trade report's Growth page and the
## radio's news see it; and a living world with nobody playing moves, but not wildly.
## Run: godot --headless --path . --script res://tests/test_development.gd   (about a minute)

var fails := 0


func check(ok: bool, what: String) -> void:
	print(("  ok    " if ok else "  FAIL  ") + what)
	if not ok:
		fails += 1


func _initialize() -> void:
	SaveSlots.dir = "user://test_saves_dev_%d" % OS.get_process_id()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SaveSlots.dir))
	process_frame.connect(_run, CONNECT_ONE_SHOT)


func _world() -> EconomySim:
	var sim := SimWorld.warmed()
	Development.enable(sim)
	return sim


func _run() -> void:
	print("canon sizes")
	var sim := _world()
	check(Development.on(sim) and sim.dev.sites.size() > 80, "every site in known space is tracked (%d)" % sim.dev.sites.size())
	var sol_port := String(Worlds.primary_port("sol").id)
	check(Development.site_stage(sim, sol_port) == 5, "Sol's port starts at core")
	check(Development.site_stage(sim, "sol__moon") == 4 and Development.site_stage(sim, "sol__pad") == 3, "its moon station a step down, the pad two")
	var plain := EconomySim.new()
	check(not Development.on(plain) and plain.scale("sol") == 1.0, "a sim without growth (the calibration tests') is untouched")

	print("the same every time")
	var a := _world()
	var b := _world()
	a.run_days(20)
	b.run_days(20)
	var same := true
	for id in a.dev.sites:
		same = same and is_equal_approx(float(a.dev.sites[id].score), float(b.dev.sites[id].score))
	check(same, "two runs of the same world grow the same")

	print("hauling to Luna")
	var hauled := _world()
	var left := _world()
	for d in 30:
		Development.moved(hauled, "sol__moon", 10.0)
		hauled.run_days(1)
		left.run_days(1)
	var luna := Development.site(hauled, "sol__moon")
	var luna_alone := Development.site(left, "sol__moon")
	check(float(luna.score) > float(luna_alone.score) + 0.4, "10 t a day for a month grows Luna well past where it got alone (%.2f against %.2f)" % [float(luna.score), float(luna_alone.score)])
	check(Development.site_stage(hauled, "sol__moon") == 5, "Luna's station is core within the month")
	check(Development.has(hauled, "sol__moon", "yard"), "and a core station opens a shipyard")
	check(Development.price_mult(hauled, "sol__moon") < Development.price_mult(left, "sol__moon") or Development.site_stage(left, "sol__moon") == 5, "fuel and repairs there get cheaper")
	var past := TradeData.growth(hauled, "sol")
	var row := {}
	for r in past.sites:
		if String(r.id) == "sol__moon":
			row = r
	check(not row.is_empty() and float(row.you_share) > 0.3, "the Growth page shows your share of its supply (%d%%)" % roundi(float(row.get("you_share", 0.0)) * 100.0))
	var grew := false
	for e in Development.recent(hauled, 30):
		grew = grew or (String(e.site) == "sol__moon" and int(e.to) > int(e.from))
	check(grew, "and the change is on the record for the news")

	print("nobody supplies it")
	var s2 := _world()
	var camp := "talos__camp"
	var cs := Development.site(s2, camp)
	cs["luck"] = -4.0   # its traffic stops coming
	var days := 0
	while not Development.abandoned(s2, camp) and days < 200:
		cs["luck"] = -4.0
		s2.run_days(1)
		days += 1
	check(Development.abandoned(s2, camp), "a camp nobody supplies is abandoned (%d days)" % days)
	check(not Development.has(s2, camp, "freight") and not Development.has(s2, camp, "passengers"), "and has no freight or passengers")
	check(Development.price_mult(s2, camp) >= 2.0, "the pump charges double")
	var lost := false
	for e in Development.recent(s2, 200, "talos"):
		lost = lost or (String(e.site) == camp and int(e.to) == 0)
	check(lost, "the abandonment is on the record")

	print("stages and services")
	var cfg: Dictionary = Development.config()
	check(Development.stage(0.3) == 0 and Development.stage(1.0) == 1 and Development.stage(2.6) == 3 and Development.stage(7.0) == 5, "scores map to stages, and nothing caps a score")
	var st := _world()
	var s := Development.site(st, "sol__belt")
	for i in 6:
		s["score"] = float(i) if i > 0 else 0.2
		s["abandoned"] = i == 0
		var stage := Development.site_stage(st, "sol__belt")
		var want_pass := stage >= int(cfg.services.passengers)
		var want_crew := stage >= int(cfg.services.crew)
		check(Development.has(st, "sol__belt", "passengers") == want_pass and Development.has(st, "sol__belt", "crew") == want_crew,
				"%s: passengers %s, crew %s" % [Development.stage_name(stage), "yes" if want_pass else "no", "yes" if want_crew else "no"])

	print("a grown system makes and uses more")
	var g := _world()
	var sys: Dictionary = g.dev.systems["talos"]
	var before := g.scale("talos")
	sys["score"] = float(sys.canon) + 1.0
	g._scale = {}
	check(is_equal_approx(before, 1.0) and is_equal_approx(g.scale("talos"), 2.0), "one stage up doubles what Talos makes and uses")
	var used := {}
	for f in g.facilities.values():
		if String(f.system_id) == "talos":
			for com in f.items:
				used[String(f.id) + com] = float(f.items[com].consumed_today)
	g.step_hour()
	var more := true
	for f in g.facilities.values():
		if String(f.system_id) == "talos":
			for com in f.items:
				var it: Dictionary = f.items[com]
				if float(it.demand) > 0.0 and used.has(String(f.id) + com):
					more = more and absf(float(it.consumed_today) - float(used[String(f.id) + com]) - float(it.demand) * 2.0 / 24.0) < 1e-6
	check(more, "its exchange draws twice the demand an hour")
	var bad := g.ledger.check()
	check(bad.is_empty(), "and the ledger still balances")

	print("saved and loaded")
	var keep := _world()
	keep.run_days(5)
	Development.moved(keep, "sol__moon", 3.0)
	var text := SimWorld.serialize(keep)
	var back := SimWorld.restore(text)
	check(back != null and Development.on(back) and is_equal_approx(float(back.dev.sites["sol__moon"].score), float(keep.dev.sites["sol__moon"].score))
			and is_equal_approx(float(back.dev.today.get("sol__moon", 0.0)), 3.0), "growth comes back with the save, today's hauling included")

	print("in a game")
	Session.begin_new(1, "Pilot", "human", "normal", "roosevelt_independent_yards")
	check(Development.on(Session.sim), "a new game grows")
	var home := String(Session.profile.port_id)
	var sys_id := Session.system_id()
	var ship := {"wet": 40.0, "fuel": 10.0, "cargo_capacity": 24.0, "lift": 2000.0}
	var lv := SimShip.level("normal")
	var board := LocalSpace.board(home, Session.day(), ship, lv)
	check(not board.is_empty(), "the home port posts local runs")
	var depot := sys_id + LocalSpace.SEP + "depot"
	var dep := Development.site(Session.sim, depot)
	dep["score"] = 0.2
	dep["abandoned"] = true
	var to_depot := 0
	for i in 6:
		for j in LocalSpace.board(home, Session.day() + i * 2, ship, lv):
			if String(j.destination_port_id) == depot:
				to_depot += 1
	check(to_depot == 0, "nobody posts freight to an abandoned depot")
	check(LocalSpace.board(depot, Session.day(), ship, lv).is_empty(), "and it posts none")
	Session.profile["port_id"] = depot
	var stripped := Session.strip_fittings()
	var again := Session.strip_fittings()
	check(bool(stripped.ok) and not bool(again.ok) and int(Session.profile.get("salvage", 0)) >= 3, "its fittings strip for salvage, once in a while: %s" % String(again.message))
	var style := SystemStyle.for_site(depot)
	check(bool(style.abandoned) and int(style.walkers) == 0, "its concourse is empty")
	var p: Node = load(Session.PLACE_SCENE).instantiate()
	root.add_child(p)
	await process_frame
	var ids := []
	for d in p.desks:
		ids.append(String(d.id))
	check("strip" in ids and "fuel" in ids and "gate" in ids and not ("freight" in ids) and not ("bar" in ids), "and only a pump, the fittings and the gate are left: %s" % str(ids))
	p.queue_free()
	await process_frame
	Session.profile["port_id"] = home
	Development._event(Session.sim, depot, dep, 2, 0)
	var lines: Dictionary = Comms.cfg().lines
	check(Development.recent(Session.sim, 21, sys_id).size() >= 1 and lines.has("news_empty") and lines.has("news_grew") and lines.has("news_shrank"),
			"this week's abandonment is news in the system, and the radio has words for it")

	print("nobody playing, half a year")
	var w := _world()
	var start := {}
	for id in w.dev.sites:
		start[id] = Development.site_stage(w, id)
	w.run_days(180)
	var up := 0
	var down := 0
	var ports_gone := 0
	for id in w.dev.sites:
		var now := Development.site_stage(w, id)
		up += 1 if now > int(start[id]) else 0
		down += 1 if now < int(start[id]) else 0
		if String(w.dev.sites[id].kind) == "port" and now == 0:
			ports_gone += 1
	var n: int = w.dev.sites.size()
	check(up > 0 and down > 0, "some sites grow and some shrink on their own (%d up, %d down)" % [up, down])
	check(float(up + down) / float(n) < 0.45, "but most hold their size (%d of %d changed)" % [up + down, n])
	check(ports_gone == 0, "and no main port empties")
	check(w.violations.is_empty(), "the ledger is clean after half a year of growth")
	print("%d failed" % fails if fails else "all passed")
	quit(1 if fails else 0)
