extends SceneTree
func _initialize():
	var sim := EconomySim.new()
	sim.load_all("res://data/world/", "res://data/runtime/", "sim_scenario_hopewell.json")
	var ship := ShipData.new(ModuleLibrary.new())
	ShipPresets.build(ship)
	var prof := SimShip.profile(ship)
	var lv = JSON.parse_string(FileAccess.get_file_as_string("res://data/runtime/economy_levels.json"))
	var sec := {"easy": {"fuel_price_mult":0.9,"port_fee_mult":0.9,"wage_mult":1.0,"ownership_mult":0.9,"maintenance_mult":0.9},
		"normal": {"fuel_price_mult":1.0,"port_fee_mult":1.0,"wage_mult":1.0,"ownership_mult":1.0,"maintenance_mult":1.0},
		"hard": {"fuel_price_mult":1.15,"port_fee_mult":1.2,"wage_mult":1.1,"ownership_mult":1.15,"maintenance_mult":1.15}}
	var goal := {"easy": 0.29, "normal": 0.15, "hard": 0.03}
	for L in lv["levels"]:
		var id: String = L["id"]
		for k in sec[id]: L[k] = sec[id][k]
		var lo := 0.3; var hi := 3.0
		for i in 40:
			var mid := (lo+hi)/2.0
			L["freight_pay_mult"] = mid
			var m: float = sim.probe_ship(prof, L, lv["benchmark"])["margin"]
			if m < goal[id]: lo = mid
			else: hi = mid
		L["freight_pay_mult"] = snappedf((lo+hi)/2.0, 0.01)
		var r = sim.probe_ship(prof, L, lv["benchmark"])
		print(id, " ", L["freight_pay_mult"], " margin ", snappedf(r["margin"],0.001), " net/day ", snappedf(r["net_per_day"],1))
	quit()
