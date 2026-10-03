extends SceneTree
## The difficulty levels, checked in the full simulation rather than the quick probe. Three starter-class
## ships work the Hopewell economy for 180 days at each level and must land in that level's margin band.
## Run: godot --headless --path . --script res://tests/test_player_economy.gd   (about two minutes)

var fails := 0

func check(ok: bool, msg: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + msg)
	if not ok:
		fails += 1

func _initialize() -> void:
	var ship := ShipData.new(ModuleLibrary.new())
	ShipPresets.build(ship)
	var prof := SimShip.profile(ship)
	var margins := {}
	for L in SimShip.levels()["levels"]:
		var sim := EconomySim.new()
		sim.load_all("res://data/world/", "res://data/runtime/", "sim_scenario_hopewell.json")
		for i in 3:
			var c := prof.duplicate()
			c["id"] = "player_%d" % i
			c["company"] = "player"
			c["home_system_id"] = "new_houston"
			c["cash"] = 60000.0
			c["min_margin"] = 0.0
			c["network"] = ["new_houston", "concord", "sol", "hesperus", "carver", "bradbury", "port_meridian"]
			c["level"] = L
			sim._add_carrier(c)
		sim.run_days(180)
		var s := sim.summary()
		var rev := 0.0
		var cost := 0.0
		var net := 0.0
		for i in 3:
			var cc: Dictionary = s["carriers"]["player_%d" % i]
			rev += cc["revenue"]
			cost += cc["costs"]
			net += cc["net_per_day"]
		var m := (rev - cost) / maxf(rev, 1.0)
		margins[L["id"]] = m
		var band: Array = L["target_margin"]
		check(m >= band[0] - 0.02 and m <= band[1] + 0.02, "%s: simulated margin %.1f%% near %.0f-%.0f%% (%.0f cr/day per ship)" % [L["id"], m * 100.0, band[0] * 100.0, band[1] * 100.0, net / 3.0])
		check(s["violations"] == 0 and absf(float(s["cash_error"])) < 0.01, "%s: ledger clean and money conserved" % L["id"])
	check(margins["easy"] > margins["normal"] and margins["normal"] > margins["hard"], "easy > normal > hard in the simulation")
	print("DONE fails=", fails)
	quit(1 if fails > 0 else 0)
