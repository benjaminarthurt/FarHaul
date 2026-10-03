extends SceneTree
## Diagnostic (not a pass/fail test): runs the known-space scenario and prints fleet and stock health.
##   godot --headless --path . -s tests/probe_known_space.gd -- 120

func _initialize() -> void:
	var days := 120
	for a in OS.get_cmdline_user_args():
		if a.is_valid_int():
			days = int(a)
	var sim := EconomySim.new()
	if not sim.load_all("res://data/world/", "res://data/runtime/", "sim_scenario_known_space.json"):
		print("load failed")
		quit(1)
		return
	var t0 := Time.get_ticks_msec()
	var warm := 60
	sim.run_days(warm)
	var base_out := {}
	for f in sim.facilities.values():
		for com in f["items"]:
			base_out[f["id"] + "/" + com] = f["items"][com]["stockout_hours"]
	sim.run_days(days - warm)
	print("ran %d days in %.1fs" % [days, (Time.get_ticks_msec() - t0) / 1000.0])
	var s := sim.summary()
	var comp := {}
	for id in s["carriers"]:
		var cc: Dictionary = s["carriers"][id]
		var co: String = sim.carriers[id]["company"]
		var g: Dictionary = comp.get(co, {"n": 0, "rev": 0.0, "cost": 0.0, "util": 0.0, "net": 0.0, "lose": 0})
		g["n"] += 1; g["rev"] += cc["revenue"]; g["cost"] += cc["costs"]; g["util"] += cc["utilization"]; g["net"] += cc["net_per_day"]
		if cc["net_per_day"] < 0.0: g["lose"] += 1
		comp[co] = g
	for co in comp:
		var g: Dictionary = comp[co]
		print("  %-30s ships %2d  util %.2f  margin %5.1f%%  net/ship/day %6.0f  losers %d" % [co, g["n"], g["util"] / g["n"], 100.0 * (g["rev"] - g["cost"]) / maxf(g["rev"], 1.0), g["net"] / g["n"], g["lose"]])
	var k: Dictionary = s["contracts"]
	print("contracts total %d delivered %d open %d late %d oldest open %.1f d, avg %.1f d" % [k["total"], k["delivered"], k["open"], k["late"], k["oldest_open_offer_hours"] / 24.0, k["avg_offer_to_delivery_days"]])
	var worst := []
	var tot := 0
	var bad := 0
	for f in sim.facilities.values():
		if f["kind"] != "consumer":
			continue
		for com in f["items"]:
			var it: Dictionary = f["items"][com]
			var pct: float = 100.0 * (it["stockout_hours"] - base_out[f["id"] + "/" + com]) / float((days - warm) * 24)
			tot += 1
			if pct > 10.0:
				bad += 1
			worst.append([pct, "%s/%s" % [f["id"], com]])
	worst.sort_custom(func(a, b): return a[0] > b[0])
	print("consumer items %d, stocked out >10%% of the time: %d" % [tot, bad])
	for i in mini(12, worst.size()):
		print("   %5.1f%%  %s" % [worst[i][0], worst[i][1]])
	var shortfalls := sim.events_of("procurement_shortfall").size()
	print("procurement shortfalls %d, violations %d, cash error %.2f" % [shortfalls, s["violations"], s["cash_error"]])
	var sup := []
	for f in sim.facilities.values():
		if f["kind"] == "supplier":
			sup.append("%s %.0fk" % [f["id"], f["cash"] / 1000.0])
	print("supplier cash:", ", ".join(sup))
	quit()
