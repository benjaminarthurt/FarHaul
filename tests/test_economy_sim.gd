extends SceneTree
## Headless economy tests. Run:
##   godot --headless --path . --script res://tests/test_economy_sim.gd
## Milestone: Hopewell filters chain runs without any manual outcome.

var fails := 0

func check(ok: bool, msg: String) -> void:
	if ok:
		print("  ok   ", msg)
	else:
		print("  FAIL ", msg)
		fails += 1

func _make() -> EconomySim:
	var sim := EconomySim.new()
	var ok := sim.load_all("res://data/world/", "res://data/runtime/", "sim_scenario_hopewell.json")
	if not ok:
		print("FAIL: could not load data")
		quit(1)
	return sim

func _first_index(evs: Array, pred: Callable) -> int:
	for i in evs.size():
		if pred.call(evs[i]):
			return i
	return -1

func _initialize() -> void:
	print("== filter shortage propagates (Hopewell)")
	var sim := _make()
	sim.verbose = "--verbose" in OS.get_cmdline_user_args() or OS.get_environment("FARHAUL_SIM_VERBOSE") != ""
	var start_stock := sim.ledger.on_hand("hopewell_water_one", "filters")
	check(start_stock == 47.0, "Hopewell starts at 47 filters")
	var hours := 0
	while hours < 24 * 40:
		sim.step_hour()
		hours += 1
		if not sim.events_of("received").filter(func(e): return e["facility"] == "hopewell_water_one").is_empty():
			break
	var ev := sim.events
	var reorder := _first_index(ev, func(e): return e["kind"] == "reorder_triggered" and e["facility"] == "hopewell_water_one")
	var ordered := _first_index(ev, func(e): return e["kind"] == "procurement_ordered" and e["buyer"] == "hopewell_water_one")
	var lots := _first_index(ev, func(e): return e["kind"] == "lots_allocated")
	var offered := _first_index(ev, func(e): return e["kind"] == "contract_offered")
	var accepted := _first_index(ev, func(e): return e["kind"] == "contract_accepted")
	var picked := _first_index(ev, func(e): return e["kind"] == "picked_up")
	var arrived := _first_index(ev, func(e): return e["kind"] == "arrived")
	var received := _first_index(ev, func(e): return e["kind"] == "received" and e["facility"] == "hopewell_water_one")
	var cpaid := _first_index(ev, func(e): return e["kind"] == "carrier_paid")
	var spaid := _first_index(ev, func(e): return e["kind"] == "supplier_paid")
	check(reorder >= 0, "consumption crosses the reorder point")
	check(ordered > reorder, "procurement places an order after the trigger")
	check(lots > ordered, "supplier allocates physical lots")
	check(offered > lots, "freight requirement enters the contract pipeline")
	check(accepted > offered, "a carrier accepts the contract")
	check(picked > accepted, "cargo is picked up")
	check(arrived > picked, "shipment travels the network")
	check(received > arrived, "Hopewell receives the lot")
	check(cpaid > 0 and spaid > 0, "carrier and supplier are paid")
	var h_ev: Dictionary = ev[reorder]
	check(float(h_ev["available"]) <= float(h_ev["reorder_point"]), "trigger fires at or below the reorder point")
	# The seed example starts Hopewell at 47 filters / 13.4 per day = 3.5 days of cover while the
	# fastest lead time is 4.3 days, so a short stock-out is built into the example itself.
	var out_h: int = sim.summary()["facilities"]["hopewell_water_one"]["stockout_hours"]
	check(out_h <= 72, "starting emergency stock-out is bounded (%d h)" % out_h)
	check(sim.violations.is_empty(), "ledger invariants held every hour")
	var rec: Dictionary = ev[received]
	print("  first Hopewell receipt on ", rec["t"], " (day ", (rec["h"] / 24), " of sim), on_hand ", snappedf(rec["on_hand"], 0.1))


	print("== stock only rises through receive/produce events")
	var sim2 := _make()
	var guard_ok := true
	var prev := sim2.ledger.on_hand("hopewell_water_one", "filters")
	var seen_receive := 0
	for i in 24 * 30:
		sim2.step_hour()
		var now := sim2.ledger.on_hand("hopewell_water_one", "filters")
		var n_recv := sim2.events_of("received").filter(func(e): return e["facility"] == "hopewell_water_one").size()
		if now > prev + 1e-9 and n_recv == seen_receive:
			guard_ok = false
		seen_receive = n_recv
		prev = now
	check(guard_ok, "Hopewell inventory never increases without a receipt")

	print("== cargo mass lowers acceleration is covered by ship tests (not in this sim)")

	print("== 180 day run without the player")
	var run := _make()
	run.run_days(180)
	var s := run.summary()
	var hours_total := 180.0 * 24.0
	print("  consumer / distributor stock-outs and freight cost relative to goods value:")
	for fid in s["facilities"]:
		var fs: Dictionary = s["facilities"][fid]
		print("    %-28s stock-out %5.1f%%  freight/goods %.2f" % [fid, 100.0 * fs["stockout_hours"] / hours_total, fs["freight_to_goods"]])
	print("  carriers (net cash per day):")
	var nets: Array = []
	for cid in s["carriers"]:
		var cs: Dictionary = s["carriers"][cid]
		nets.append(cs["net_per_day"])
		print("    %-26s %8.0f cr/day  utilization %.2f  trips %d" % [cid, cs["net_per_day"], cs["utilization"], cs["trips"]])
	print("  contracts: ", s["contracts"])
	check(not run.events_of("transfer_at_hub").is_empty(), "multi-leg lots from New Houston transfer at Concord / Port Meridian")
	check(run.violations.is_empty(), "no ledger violations in 180 days")
	check(absf(s["cash_error"]) < 0.01, "money is conserved (error %.6f cr)" % s["cash_error"])
	# Calibration targets. Hopewell has the shortest supply line; the outer consumers are looser.
	check(s["facilities"]["hopewell_water_one"]["stockout_hours"] <= 0.10 * hours_total, "Hopewell stock-out under 10% of the time")
	for fid in ["beacon_heatplant", "tank_farm_coop"]:
		check(s["facilities"][fid]["stockout_hours"] <= 0.12 * hours_total, "%s frontier stock-out under 12%%" % fid)
	check(s["facilities"]["meridian_chandlers_union"]["stockout_hours"] <= 0.03 * hours_total, "distributor stock-out under 3%")
	check(s["contracts"]["delivered"] > 100, "freight actually flows (%d delivered)" % s["contracts"]["delivered"])
	check(s["contracts"]["oldest_open_offer_hours"] < 24 * 10, "no contract sits unserved for 10 days")
	nets.sort()
	check(nets[nets.size() / 2] > 0.0, "median carrier is solvent on ordinary work (%.0f cr/day)" % nets[nets.size() / 2])
	print("DONE fails=", fails)
	quit(1 if fails > 0 else 0)
