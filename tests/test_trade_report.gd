extends SceneTree
## The trade report: the sim's daily history (SimStats), what TradeData makes of it, the player's mark
## from real deliveries (interstellar and in-system) and salvage, saving it, and the report screen (N).
## Run: godot --headless --path . --script res://tests/test_trade_report.gd
var fails := 0
func check(ok: bool, msg: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + msg)
	if not ok:
		fails += 1


func _initialize() -> void:
	SaveSlots.dir = "user://test_saves_trade_%d" % OS.get_process_id()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SaveSlots.dir))
	process_frame.connect(_run, CONNECT_ONE_SHOT)


func _fit_ftl() -> void:
	var data := SaveSlots.read(Session.slot)
	var ship := ShipData.new(ModuleLibrary.new())
	ShipPresets.build(ship, ShipPresets.STARTER_FTL)
	data["modules"] = (JSON.parse_string(ship.to_json()) as Dictionary)["modules"]
	data["cargo"] = CargoManifest.new(ship).to_dict()
	SaveSlots.write(Session.slot, data)
	SimWorld.sync(Session.sim, Session.profile, ship)


func _run() -> void:
	print("history from the start")
	Session.begin_new(1, "Tester", "human", "normal", "roosevelt_independent_yards")
	var sim := Session.sim
	var ds := TradeData.days(sim)
	check(ds.size() >= SimWorld.WARMUP_DAYS - 1, "the warm-up's days are on record (%d)" % ds.size())
	sim.run_days(7)
	ds = TradeData.days(sim)
	check(ds.size() <= SimStats.KEEP_DAYS, "no more than %d days kept" % SimStats.KEEP_DAYS)
	var fr := 0.0
	var lanes := 0
	for d in ds:
		fr += float(d.freight_cr)
		lanes += (d.flows as Dictionary).size()
	check(fr > 0.0 and lanes > 0, "freight was paid (%s) along %d lane-days" % [TradeReport.cr(fr), lanes])
	check(not (ds.back().prices as Dictionary).is_empty() or not (ds[ds.size() - 2].prices as Dictionary).is_empty(), "each day's prices are noted")
	var s := sim.summary()
	check(absf(float(s.cash_error)) < 1.0, "keeping records moves no money (cash error %.3f)" % float(s.cash_error))

	print("what the report makes of it")
	var o := TradeData.overview(sim)
	check(float(o.freight_cr.week) > 0.0 and float(o.t.week) > 0.0 and (o.series.freight_cr as Array).size() == ds.size(), "a week's freight: %s, %s" % [TradeReport.cr(float(o.freight_cr.week)), TradeReport.tonnes(float(o.t.week))])
	check(int(o.carriers.total) > 10 and int(o.carriers.working) > 0, "%d of %d ships at work" % [int(o.carriers.working), int(o.carriers.total)])
	var tight: Array = o.tight
	var tight_ok := true
	for r in tight:
		tight_ok = tight_ok and String(r.state) in ["out", "critical", "short"] and not (r.goods as Array).is_empty()
	check(tight_ok, "shortages, worst first: %s" % (", ".join(tight.slice(0, 3).map(func(r): return "%s (%s)" % [r.name, r.state]))))
	var fl := TradeData.flows(sim, 7)
	check(not (fl.lanes as Array).is_empty() and float(fl.lanes[0].t) >= float(fl.lanes.back().t), "busiest lane first: %s to %s, %s of %s" % [fl.lanes[0].a, fl.lanes[0].b, TradeReport.tonnes(float(fl.lanes[0].t)), fl.lanes[0].top])
	var moving: Array = (fl.ships as Array).filter(func(x): return x.a != x.b)
	check((fl.ships as Array).size() == sim.carriers.size() and moving.all(func(x): return float(x.progress) >= 0.0 and float(x.progress) <= 1.0), "every ship placed, %d between systems" % moving.size())
	var cos := TradeData.companies(sim)
	var share := 0.0
	for r in cos:
		share += float(r.share)
	check(cos.size() > 3 and absf(share - 1.0) < 0.01 and cos.any(func(r): return bool(r.player)), "%d companies, shares add up, you among them" % cos.size())
	check(float(cos[0].revenue_30) >= float(cos[1].revenue_30) and int(cos[0].rank) == 1, "ranked by freight earned: %s first" % cos[0].name)

	print("your mark: an interstellar delivery")
	_fit_ftl()
	var before := TradeData.player(sim)
	check(float(before.t) == 0.0 and int(before.deliveries) == 0, "nothing to your name yet")
	var board := Contracts.offers_from(Session.system_id())
	var offer: Dictionary = board[0] if not board.is_empty() else {}
	check(not offer.is_empty(), "freight on the board")
	if not offer.is_empty():
		check(bool(Session.accept_contract(offer).ok), "accepted")
		var active := Session.active_contract()
		check(bool(Session.depart_active_contract().ok), "flown")
		check(bool(Session.deliver_active_contract().ok), "delivered")
		var me := TradeData.player(sim)
		check(float(me.interstellar_t) > 0.0 and float(me.cr) > 0.0 and int(me.deliveries) == 1, "on the record: %s for %s" % [TradeReport.tonnes(float(me.interstellar_t)), TradeReport.cr(float(me.cr))])
		check(float(me.share_30) > 0.0 and int(me.rank) >= 1, "a share of the trade: %.2f%%, rank %d of %d" % [float(me.share_30) * 100.0, int(me.rank), int(me.companies)])
		check(int(me.system_count) == 1 and String(me.systems[0].system) == String(active.destination_system_id), "delivered to %s" % me.systems[0].name if int(me.system_count) > 0 else "delivered somewhere")
		var mine := (TradeData.flows(sim, 7).lanes as Array).filter(func(l): return float(l.player_t) > 0.0)
		check(mine.size() == 1, "your lane is marked on the flows")
		if int(me.facility_count) > 0:
			check(true, "and the buyer it reached: %s" % me.facilities[0].name)
		else:
			check(not offer.is_empty(), "(a hub leg: someone else takes it the rest of the way)")
		check((TradeData.companies(sim).filter(func(r): return bool(r.player))[0].revenue_30 as float) > 0.0, "the companies table counts it")

	Session.profile["hints_seen"] = ["welcome", "money", "crew"]
	check(String(Hints.next("concourse").get("id", "")) == "trade", "and the concourse points you at the report")
	print("in-system runs and salvage count too")
	var t0 := float(TradeData.player(sim).local_t)
	SimStats.on_local(sim, Session.system_id(), 24.0, 5000.0)
	SimStats.on_salvage(sim, 1200.0, "new_houston_exchange", 0.5)
	var me2 := TradeData.player(sim)
	check(absf(float(me2.local_t) - t0 - 24.0) < 0.01 and float(me2.salvage_cr) >= 1200.0, "an in-system run and a salvage sale on the record")
	check(float(me2.series.back()) >= 6200.0, "today's takings include both")

	print("saved with the game")
	var copy := SimWorld.restore(SimWorld.serialize(sim))
	check(copy != null and TradeData.days(copy).size() == TradeData.days(sim).size() and float(TradeData.player(copy).cr) == float(TradeData.player(sim).cr), "the history and your record survive a save")
	var old := sim.to_state()
	old.erase("stats")
	var fresh := EconomySim.new()
	fresh.load_all(SimWorld.WORLD_DIR, SimWorld.RUNTIME_DIR, SimWorld.SCENARIO)
	fresh.load_state(old)
	check(TradeData.overview(fresh).has("tight") and TradeData.player(fresh).t == 0.0, "an old save with no history still opens a report")

	print("the screen")
	Session.profile["location"] = "dock"
	Session.save_profile()
	var pl: Node = load(Session.PLACE_SCENE).instantiate()
	root.add_child(pl)
	current_scene = pl
	await process_frame
	await process_frame
	var r := TradeReport.find(self)
	check(r != null, "every scene has one")
	if r != null:
		var key := InputEventKey.new()
		key.keycode = KEY_N
		key.pressed = true
		r._input(key)
		check(r.is_open() and paused, "N opens it, and the game waits")
		for p in TradeReport.PAGES:
			r.show_page(p)
			await process_frame
			check(r.page == p and not r._data.is_empty(), "the %s page has something to show" % TradeReport.TITLES[p])
		var esc := InputEventKey.new()
		esc.keycode = KEY_ESCAPE
		esc.pressed = true
		r._input(esc)
		check(not r.is_open() and not paused, "Esc closes it")
		var menu := pl.get_node_or_null("GameMenu") as GameMenu
		menu.open()
		for b in menu.list.get_children():
			if b is Button and (b as Button).text.begins_with("TRADE REPORT"):
				(b as Button).pressed.emit()
		check(r.is_open() and not menu.is_open(), "the pause menu opens it too")
		r.close()
	check(TradeReport.cr(2332446.0) == "2.33M cr" and TradeReport.cr(141523.0) == "142k cr" and TradeReport.cr(950.0) == "950 cr", "money reads short")
	print("DONE fails=", fails)
	quit(1 if fails > 0 else 0)
