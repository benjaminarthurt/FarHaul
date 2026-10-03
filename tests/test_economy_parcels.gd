extends SceneTree
## Small ships in the economy sim. Run:
##   godot --headless --path . --script res://tests/test_economy_parcels.gd
## A ship smaller than a 40 SCU lot must still be able to haul freight, by taking part of a lot.

var fails := 0

func check(ok: bool, msg: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + msg)
	if not ok:
		fails += 1

func _initialize() -> void:
	var sim := EconomySim.new()
	if not sim.load_all("res://data/world/", "res://data/runtime/", "sim_scenario_hopewell.json"):
		print("FAIL: could not load data")
		quit(1)
		return
	var ship := ShipData.new(ModuleLibrary.new())
	ShipPresets.build(ship, ShipPresets.STARTER_FTL)
	var prof := SimShip.profile(ship)
	check(prof["capacity_scu"] < 40.0, "the starter (%.0f SCU) is smaller than a standard lot" % prof["capacity_scu"])
	for i in 2:
		var c := prof.duplicate()
		c["id"] = "starter_proxy_%d" % i
		c["company"] = "starter_proxy"
		c["home_system_id"] = "new_houston"
		c["cash"] = 60000.0
		c["min_margin"] = 0.0
		c["network"] = ["new_houston", "concord", "sol", "hesperus", "carver", "bradbury", "port_meridian"]
		sim._add_carrier(c)
	var cash0 := sim.total_cash()
	sim.run_days(150)
	var splits := sim.events_of("contract_split")
	check(splits.size() > 0, "oversize lots are split into parcels (%d splits)" % splits.size())
	var s := sim.summary()
	var small_trips := 0
	var small_rev := 0.0
	for i in 2:
		small_trips += int(s["carriers"]["starter_proxy_%d" % i]["trips"])
		small_rev += float(s["carriers"]["starter_proxy_%d" % i]["revenue"])
	check(small_trips > 0 and small_rev > 0.0, "small ships win freight (%d trips, %.0f cr)" % [small_trips, small_rev])
	check(s["violations"] == 0, "no ledger violations with parcels")
	check(absf(float(s["cash_error"])) < 0.01, "money still conserved (%.6f cr)" % s["cash_error"])
	var lot_mismatch := 0
	for oid in sim.orders:
		var o: Dictionary = sim.orders[oid]
		var units := 0.0
		for lid in o["lots"]:
			units += sim.lots[lid]["units"]
		if absf(units - float(o["units"])) > 0.001:
			lot_mismatch += 1
	check(lot_mismatch == 0, "every order's lots still add up to the units ordered")
	var over := 0
	for k in sim.contracts.values():
		var lot: Dictionary = sim.lots[k["lot"]]
		if int(k["seg_i"]) != int(lot["seg_i"]) and k["status"] == "delivered":
			continue   # an earlier leg of a multi-hop trip is history: the lot may have been split since
		if absf(float(k["scu"]) - float(lot["scu"])) > 0.001:
			over += 1
	check(over == 0, "contract and lot sizes agree after splitting")
	check(s["contracts"]["delivered"] > 100, "the wider economy keeps flowing (%d delivered)" % s["contracts"]["delivered"])
	print("DONE fails=", fails)
	quit(1 if fails > 0 else 0)
