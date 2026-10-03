extends SceneTree
## Solves each level's freight_pay_mult against the FULL simulation (the stand-in captains of
## test_player_economy.gd), then fits the quick probe's backhaul share to it. Stand-in behaviour does
## not depend on the multipliers, so one run per level gives the exact multiplier for a target margin.
##   godot --headless --path . -s tests/solve_levels_sim.gd
const DAYS := 150
const GOALS := {"easy": 0.31, "normal": 0.165, "hard": 0.02}

func _initialize() -> void:
	var ship := ShipData.new(ModuleLibrary.new())
	ShipPresets.build(ship)
	var prof := SimShip.profile(ship)
	var lv: Dictionary = SimShip.levels()
	var solved := {}
	var util := 0.0
	for L in lv["levels"]:
		var sim := EconomySim.new()
		sim.load_all("res://data/world/", "res://data/runtime/", SimWorld.SCENARIO)
		for i in 3:
			var c := prof.duplicate()
			c["id"] = "player_%d" % i
			c["company"] = "player"
			c["home_system_id"] = "new_houston"
			c["cash"] = 60000.0
			c["min_margin"] = 0.0
			c["first_look"] = true
			c["network"] = sim.net.adj.keys()
			c["level"] = L
			sim._add_carrier(c)
		sim.run_days(DAYS)
		var s := sim.summary()
		var rev := 0.0
		var cost := 0.0
		for i in 3:
			rev += s["carriers"]["player_%d" % i]["revenue"]
			cost += s["carriers"]["player_%d" % i]["costs"]
			util += float(s["carriers"]["player_%d" % i]["utilization"]) / 9.0
		var m := float(L["freight_pay_mult"])
		var k := float(sim.p["maintenance_reserve_fraction"]) * float(L["maintenance_mult"])
		var r1 := rev / m                                  # revenue per unit of pay multiplier
		var c0 := cost - k * rev                           # costs that do not scale with pay
		var goal: float = GOALS[L["id"]]
		var m_star := c0 / (r1 * (1.0 - k - goal))
		solved[L["id"]] = snappedf(m_star, 0.01)
		print(L["id"], " now ", m, " margin ", snappedf((rev - cost) / rev, 0.001), " -> multiplier ", solved[L["id"]])
	print("paid time ", snappedf(util, 0.01))
	# fit the probe's realised-rate premium to the simulation at the normal level
	var psim := EconomySim.new()
	psim.load_all("res://data/world/", "res://data/runtime/", SimWorld.SCENARIO)
	var normal := SimShip.level("normal").duplicate()
	normal["freight_pay_mult"] = solved["normal"]
	var lo := 0.5
	var hi := 6.0
	var bench: Dictionary = SimShip.levels()["benchmark"]
	for i in 30:
		var mid := (lo + hi) / 2.0
		var r := psim.probe_ship(prof, normal, {"utilisation": snappedf(util, 0.01), "backhaul_fraction": float(bench["backhaul_fraction"]), "rate_premium": mid})
		if r["margin"] < GOALS["normal"]:
			lo = mid
		else:
			hi = mid
	print("rate_premium fit ", snappedf((lo + hi) / 2.0, 0.01), " at backhaul ", bench["backhaul_fraction"], " (probe margin at normal reaches ", GOALS["normal"], ")")
	quit()
