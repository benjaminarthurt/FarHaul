extends SceneTree
## Economy difficulty and ship-to-sim link. Run:
##   godot --headless --path . --script res://tests/test_economy_levels.gd
## The player's position near insolvency is a measured number, not a feeling: the starter ship's
## margin on the world's lanes must sit in each level's band.

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
	print("== ship profile from the builder")
	var lib := ModuleLibrary.new()
	var ship := ShipData.new(lib)
	ShipPresets.build(ship)
	var st := ShipStats.compute(ship)
	var prof := SimShip.profile(ship)
	check(is_equal_approx(prof["capacity_kg"], float(st["cargo_capacity"]) * 1000.0), "carrying mass comes from the hold tonnage (%.0f kg)" % prof["capacity_kg"])
	check(prof["capacity_scu"] > 0.0 and prof["capacity_scu"] <= prof["capacity_kg"] / 500.0, "volume is derived from tonnage (%.0f SCU)" % prof["capacity_scu"])
	check(prof["fuel_units"] > 0.0 and is_equal_approx(prof["dry_mass_t"], float(st["wet"])), "tanks and mass come from the ship")
	check(abs(prof["ly_per_day"] - 1.5) < 0.05, "starter flies at the reference speed (%.2f ly/day)" % prof["ly_per_day"])
	check(prof["fixed_cr_per_day"] > 0.0 and prof["fixed_cr_per_day"] < 200.0, "ownership cost scales with ship price (%.0f cr/day)" % prof["fixed_cr_per_day"])
	check(SimShip.profile(ship)["fixed_cr_per_day"] == prof["fixed_cr_per_day"], "profile is deterministic")

	print("== physical limits are enforced")
	var tiny := {"fuel_units": 5.0, "dry_mass_t": 29.3}
	check(not sim._path_feasible(tiny, ["new_houston", "sol"], 0.0), "a ship cannot make a jump its tank cannot cover")
	var roomy := {"fuel_units": 1.0e12, "dry_mass_t": 29.3}
	check(sim._path_feasible(roomy, ["new_houston", "sol"], 0.0), "unlimited-range carriers are unaffected")
	var fast := sim._leg_hours(6.0, 3.0)
	var slow := sim._leg_hours(6.0, 1.0)
	check(fast < slow and fast == 48 and slow == 144, "faster ships make the same leg in fewer hours")

	print("== difficulty levels put the starter ship where designed")
	var lv: Dictionary = SimShip.levels()
	var margins := {}
	for L in lv["levels"]:
		var r := sim.probe_ship(prof, L, lv["benchmark"])
		var band: Array = L["target_margin"]
		margins[L["id"]] = r["margin"]
		check(r["lanes"] > 0 and r["margin"] >= band[0] and r["margin"] <= band[1],
				"%s margin %.1f%% inside %.0f-%.0f%% (net %.0f cr/day)" % [L["id"], r["margin"] * 100.0, band[0] * 100.0, band[1] * 100.0, r["net_per_day"]])
	check(margins["easy"] > margins["normal"] and margins["normal"] > margins["hard"], "easy > normal > hard")
	var hard := SimShip.level("hard")
	var thin: Dictionary = lv["benchmark"].duplicate()
	thin["utilisation"] = 0.45
	check(sim.probe_ship(prof, hard, thin)["net_per_day"] < 0.0, "on hard, a captain who leaves the ship idle slides into the red")
	check(sim.probe_ship(prof, SimShip.level("easy"), thin)["net_per_day"] > -200.0, "easy forgives the same idling")
	check(SimShip.level("nonsense")["id"] == "normal", "unknown difficulty falls back to normal")
	print("DONE fails=", fails)
	quit(1 if fails > 0 else 0)
