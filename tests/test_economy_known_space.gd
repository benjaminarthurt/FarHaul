extends SceneTree
## The full known-space economy: every freight good has a maker and a user, the world runs without breaking
## the ledger, and the goods actually move. Run:
##   godot --headless --path . --script res://tests/test_economy_known_space.gd   (about a minute)
## The scenario is generated: python3 tools/gen_known_space.py (roles in data/runtime/goods_roles.json,
## fleet in data/runtime/known_space_fleet.json). The probe tests/probe_known_space.gd prints fleet detail.

var fails := 0
const DAYS := 120
const WARM := 60

func check(ok: bool, msg: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + msg)
	if not ok:
		fails += 1

func _initialize() -> void:
	var roles: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/runtime/goods_roles.json"))
	var coms: Array = JSON.parse_string(FileAccess.get_file_as_string("res://data/world/commodities.json"))["commodities"]
	var sim := EconomySim.new()
	check(sim.load_all("res://data/world/", "res://data/runtime/", SimWorld.SCENARIO), "the game's scenario loads (%s)" % SimWorld.SCENARIO)

	print("== every freight good has a maker and a user")
	var makes := {}
	var uses := {}
	for f in sim.facilities.values():
		for com in f["items"]:
			if f["kind"] == "consumer" or f["kind"] == "distributor":
				uses[com] = true
			if f["kind"] == "supplier":
				makes[com] = true
	var missing: Array = []
	for c in coms:
		var id: String = c["id"]
		if roles["skip"].has(id):
			continue
		if not (makes.has(id) and uses.has(id)):
			missing.append(id)
	check(missing.is_empty(), "all %d freight goods are made and used somewhere%s" % [coms.size() - roles["skip"].size(), "" if missing.is_empty() else " (missing: %s)" % ", ".join(missing)])
	check(roles["skip"].has("survey_data") and not makes.has("survey_data"), "survey data is not hauled as freight")

	print("== the world runs")
	sim.run_days(WARM)
	var base_out := {}
	for f in sim.facilities.values():
		for com in f["items"]:
			base_out[f["id"] + "/" + com] = f["items"][com]["stockout_hours"]
	sim.run_days(DAYS - WARM)
	var s := sim.summary()
	check(s["violations"] == 0 and absf(float(s["cash_error"])) < 0.01, "ledger clean and money conserved over %d days" % DAYS)
	var k: Dictionary = s["contracts"]
	check(k["delivered"] > 1500, "%d contracts delivered" % k["delivered"])
	check(float(k["oldest_open_offer_hours"]) / 24.0 < 60.0, "no freight waits more than 60 days (oldest %.0f d)" % (float(k["oldest_open_offer_hours"]) / 24.0))

	var moved := {}
	for c in sim.contracts.values():
		if c["status"] == "delivered":
			moved[sim.lots[c["lot"]]["com"]] = true
	var still: Array = []
	for c in coms:
		var id: String = c["id"]
		if not roles["skip"].has(id) and not moved.has(id):
			still.append(id)
	check(still.size() <= 3, "nearly every good has moved freight (%d of %d untouched%s)" % [still.size(), coms.size() - roles["skip"].size(), "" if still.is_empty() else ": " + ", ".join(still)])

	var items := 0
	var short := 0
	for f in sim.facilities.values():
		if f["kind"] != "consumer":
			continue
		for com in f["items"]:
			items += 1
			var pct: float = 100.0 * (f["items"][com]["stockout_hours"] - base_out[f["id"] + "/" + com]) / float((DAYS - WARM) * 24)
			if pct > 10.0:
				short += 1
	check(float(short) / float(items) < 0.45, "%d of %d consumer items stocked out over 10%% of the time (limit 45%%: the far frontier and thin lanes run short by design)" % [short, items])

	var rev := 0.0
	var cost := 0.0
	var losers := 0
	for id in s["carriers"]:
		var cc: Dictionary = s["carriers"][id]
		rev += cc["revenue"]
		cost += cc["costs"]
		if cc["net_per_day"] < 0.0:
			losers += 1
	var margin := (rev - cost) / maxf(rev, 1.0)
	check(margin > 0.05 and margin < 0.32, "fleets earn a working margin overall (%.1f%%)" % (margin * 100.0))
	check(float(losers) / float(s["carriers"].size()) < 0.25, "fewer than a quarter of ships lose money (%d of %d)" % [losers, s["carriers"].size()])
	print("DONE fails=", fails)
	quit(1 if fails > 0 else 0)
