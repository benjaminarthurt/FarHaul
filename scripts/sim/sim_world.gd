class_name SimWorld
extends RefCounted
## The economy simulation as the game uses it: one living world per saved game, with the player's
## ship as a manually flown carrier. Session owns the instance; this class builds it, keeps the
## player's carrier in step with the real ship, and turns sim contracts into the freight-board shape
## the dock already understands (see Contracts).
##
## Time only passes when the player acts: departing, delivering or waiting. While they travel the
## rest of the economy keeps working, and every day the ship exists it costs wages and ownership.

const WORLD_DIR := "res://data/world/"
const RUNTIME_DIR := "res://data/runtime/"
const SCENARIO := "sim_scenario_hopewell.json"
const PLAYER := "player"
const WARMUP_DAYS := 14


## A fresh world with the player docked at `profile.system_id`. Runs a short warm-up so orders and
## shipments are already in flight on day one.
static func create(profile: Dictionary, ship: ShipData) -> EconomySim:
	var sim := EconomySim.new()
	if not sim.load_all(WORLD_DIR, RUNTIME_DIR, SCENARIO):
		return null
	sim.run_days(WARMUP_DAYS)
	var c := SimShip.profile(ship)
	c["id"] = PLAYER
	c["company"] = "player"
	c["home_system_id"] = String(profile.system_id)
	c["cash"] = float(profile.credits)
	c["min_margin"] = 0.0
	c["network"] = sim.net.adj.keys()
	c["level"] = SimShip.level(String(profile.get("difficulty", "normal")))
	c["manual"] = true
	sim._add_carrier(c)
	# Make sure there is something to haul on the first day: let the world run (at the sim's expense,
	# not the player's) until the home port has freight on the board.
	var cash0 := float(c["cash"])
	for i in 24 * 10:
		if sim.offers_at(PLAYER).size() >= 2:
			break
		sim.step_hour()
	var pc: Dictionary = sim.carriers[PLAYER]
	sim.cash_initial += cash0 - pc["cash"]
	pc["cash"] = cash0
	return sim


static func serialize(sim: EconomySim) -> String:
	return Marshalls.variant_to_base64(sim.to_state())  # lossless; var_to_str rounds floats to ~6 digits and breaks cash conservation


static func restore(text: String) -> EconomySim:
	var st: Variant = Marshalls.base64_to_variant(text)
	if typeof(st) != TYPE_DICTIONARY:
		return null
	var sim := EconomySim.new()
	if not sim.load_all(WORLD_DIR, RUNTIME_DIR, SCENARIO):
		return null
	sim.load_state(st)
	return sim


static func player(sim: EconomySim) -> Dictionary:
	return sim.carriers.get(PLAYER, {})


## Bring the sim's idea of the player's ship, money and position in line with the real game before
## anything runs: the builder may have changed the ship or spent credits since the last advance.
static func sync(sim: EconomySim, profile: Dictionary, ship: ShipData) -> void:
	var c := player(sim)
	if c.is_empty():
		return
	var fresh := SimShip.profile(ship)
	c["capacity_scu"] = fresh["capacity_scu"]
	c["capacity_kg"] = fresh["capacity_kg"]
	c["dry_mass_t"] = fresh["dry_mass_t"]
	c["crew"] = fresh["crew"]
	c["fixed"] = fresh["fixed_cr_per_day"]
	c["speed"] = fresh["ly_per_day"]
	c["fuel_units"] = fresh["fuel_units"]
	c["level"] = SimShip.level(String(profile.get("difficulty", "normal")))
	var credits := float(profile.credits)
	if absf(credits - c["cash"]) > 0.5:
		sim.cash_initial += credits - c["cash"]      # money the builder spent or paid in from outside the sim
		c["cash"] = credits
	if c["state"] == "idle":
		c["sys"] = String(profile.system_id)


## Freight on offer at `system_id`, in the board format: tonnes offered, credits per tonne after the
## player's difficulty level, and the sim contract id to accept.
static func board(sim: EconomySim, system_id: String, limit: int = 8) -> Array[Dictionary]:
	var c := player(sim)
	var out: Array[Dictionary] = []
	if c.is_empty() or c["sys"] != system_id:
		return out
	for k in sim.offers_at(PLAYER):
		var tonnes := float(k["mass_kg"]) / 1000.0
		if tonnes <= 0.0:
			continue
		var lot: Dictionary = sim.lots[k["lot"]]
		var goods: Dictionary = sim.commodities.get(lot["com"], {})
		var dest_sys: String = k["dest_sys"]
		var pay := sim.pay_for(PLAYER, k)
		out.append({
			"id": String(k.get("parent", k["id"])),
			"sim_contract": String(k.get("parent", k["id"])),
			"title": "%s to %s" % [goods.get("name", lot["com"]), dest_sys.replace("_", " ").capitalize()],
			"commodity": StringName(lot["com"]),
			"offer": snappedf(tonnes, 0.1),
			"rate": roundi(pay / tonnes),
			"origin_system_id": k["origin_sys"],
			"destination_system_id": dest_sys,
			"origin_port_id": k["origin_port"],
			"destination_port_id": k["dest_port"],
			"distance_ly": sim.net.path_ly(k["systems"]),
			"min_twr": 0.05,
			"deadline_days": maxf(0.0, float(k["deadline"] - sim.hour) / 24.0),
			"blurb": "Live freight: %s moving through the %s economy." % [goods.get("name", lot["com"]), dest_sys.replace("_", " ").capitalize()],
		})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.offer) * float(a.rate) > float(b.offer) * float(b.rate))
	return out.slice(0, mini(limit, out.size()))


## Cash the sim says the player has, rounded for display and for profile.credits.
static func credits(sim: EconomySim) -> int:
	return roundi(float(player(sim).get("cash", 0.0)))


static func day(sim: EconomySim) -> int:
	return sim.hour / 24


## The nearest other system with freight waiting (by route length), or "" when nothing is posted.
static func nearest_freight(sim: EconomySim) -> String:
	var c := player(sim)
	if c.is_empty():
		return ""
	var best := ""
	var best_ly := INF
	for k in sim.contracts.values():
		if k["status"] != "offered" or k["origin_sys"] == c["sys"]:
			continue
		var path := sim.net.path(c["sys"], k["origin_sys"])
		if path.is_empty():
			continue
		var ly := sim.net.path_ly(path)
		if ly < best_ly:
			best_ly = ly
			best = k["origin_sys"]
	return best



## What the ship costs every day it exists, crew and ownership after the difficulty level.
static func daily_cost(sim: EconomySim) -> float:
	var c := player(sim)
	if c.is_empty():
		return 0.0
	return float(c["crew"]) * float(c["wage"]) * sim._lv(c, "wage_mult") + float(c["fixed"]) * sim._lv(c, "ownership_mult")


## Whole days the player's cash would last if the ship did nothing.
static func runway_days(sim: EconomySim) -> int:
	var d := daily_cost(sim)
	return 9999 if d <= 0.0 else int(floorf(float(player(sim).get("cash", 0.0)) / d))


## Where the ship could fly empty from here: every system on a feasible route, with the trip's
## distance, time, estimated cost and how many freight offers wait there. Nearest first.
static func destinations(sim: EconomySim) -> Array[Dictionary]:
	var c := player(sim)
	var out: Array[Dictionary] = []
	if c.is_empty() or c["state"] != "idle":
		return out
	var freight := {}
	for k in sim.contracts.values():
		if k["status"] == "offered":
			freight[k["origin_sys"]] = int(freight.get(k["origin_sys"], 0)) + 1
	for s in sim.net.adj.keys():
		if s == c["sys"] or not (s in c["network"]):
			continue
		var path := sim.net.path(c["sys"], s)
		if path.is_empty() or not sim._path_feasible(c, path, 0.0):
			continue
		var t: Dictionary = sim._trip_parts(c, path, 0.0)
		var cost: float = float(t["fuel"]) * sim._lv(c, "fuel_price_mult") + float(t["fees"]) * sim._lv(c, "port_fee_mult") \
				+ float(t["wages"]) * sim._lv(c, "wage_mult") + float(t["fixed"]) * sim._lv(c, "ownership_mult")
		out.append({"system_id": s, "ly": sim.net.path_ly(path), "days": float(t["days"]), "cost": cost, "freight": int(freight.get(s, 0))})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.ly < b.ly)
	return out
