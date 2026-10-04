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
const SCENARIO := "sim_scenario_known_space.json"
const PLAYER := "player"
const WARMUP_DAYS := 14
## The world after its warm-up is the same for every new game, so it is computed once and shipped
## (tests/make_warm_start.gd). The file carries a fingerprint of the data it was made from and is ignored
## if the world or runtime data has changed since; then the warm-up runs as before.
const WARM_START := "res://data/runtime/warm_start.bin"


## A fresh world with the player docked at `profile.system_id`. Runs a short warm-up so orders and
## shipments are already in flight on day one.
static func create(profile: Dictionary, ship: ShipData) -> EconomySim:
	var sim := warmed()
	if sim == null:
		return null
	var c := SimShip.profile(ship, {}, bool(profile.get("ftl_grandfathered", false)))
	c["id"] = PLAYER
	c["company"] = "player"
	c["home_system_id"] = String(profile.system_id)
	c["wage_cr_per_day"] = float(c["wage_cr_per_day"]) * SimShip.wage_index(String(profile.system_id))   # crew hired here are paid local rates
	c["cash"] = float(profile.credits)
	c["min_margin"] = 0.0
	c["network"] = sim.net.adj.keys()
	c["level"] = SimShip.level(String(profile.get("difficulty", "normal")))
	c["manual"] = true
	sim._add_carrier(c)
	# Make sure there is something to haul on the first day: let the world run (at the sim's expense,
	# not the player's) until the home port has freight on the board.
	var cash0 := float(c["cash"])
	# A sublight ship works the local board, which always has runs posted, so there is nothing to wait for.
	for i in (24 * 10 if bool(c.get("ftl", true)) else 0):
		if sim.offers_at(PLAYER).size() >= 2:
			break
		sim.step_hour()
	var pc: Dictionary = sim.carriers[PLAYER]
	sim.cash_initial += cash0 - pc["cash"]
	pc["cash"] = cash0
	return sim


## A world that has run its warm-up: from the shipped file when it matches the data, else computed.
static func warmed() -> EconomySim:
	var sim := EconomySim.new()
	if not sim.load_all(WORLD_DIR, RUNTIME_DIR, SCENARIO):
		return null
	var f := FileAccess.open_compressed(WARM_START, FileAccess.READ, FileAccess.COMPRESSION_ZSTD)
	if f != null:
		var stored: Variant = f.get_var()
		f.close()
		if typeof(stored) == TYPE_DICTIONARY and String(stored.get("fingerprint", "")) == data_fingerprint():
			sim.load_state(stored["state"])
			return sim
	sim.run_days(WARMUP_DAYS)
	return sim


## Writes the warm-start file for the current data (run by tests/make_warm_start.gd).
static func write_warm_start(path: String = WARM_START) -> bool:
	var sim := EconomySim.new()
	if not sim.load_all(WORLD_DIR, RUNTIME_DIR, SCENARIO):
		return false
	sim.run_days(WARMUP_DAYS)
	var f := FileAccess.open_compressed(path, FileAccess.WRITE, FileAccess.COMPRESSION_ZSTD)
	if f == null:
		return false
	f.store_var({"fingerprint": data_fingerprint(), "days": WARMUP_DAYS, "state": sim.to_state()})
	f.close()
	return true


## A hash of every data file the economy reads, so a stale warm start is never used.
static func data_fingerprint() -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_MD5)
	for dir in [WORLD_DIR, RUNTIME_DIR]:
		var names := Array(DirAccess.get_files_at(dir))
		names.sort()
		for n in names:
			if not String(n).ends_with(".json"):
				continue
			ctx.update(String(n).to_utf8_buffer())
			ctx.update(FileAccess.get_file_as_bytes(String(dir) + String(n)))
	ctx.update(str(WARMUP_DAYS).to_utf8_buffer())
	return ctx.finish().hex_encode()


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
	var fresh := SimShip.profile(ship, {}, bool(profile.get("ftl_grandfathered", false)))
	c["ftl"] = fresh["ftl"]
	c["capacity_scu"] = fresh["capacity_scu"]
	c["capacity_kg"] = fresh["capacity_kg"]
	c["dry_mass_t"] = fresh["dry_mass_t"]
	c["crew"] = fresh["crew"]
	c["wage"] = float(fresh["wage_cr_per_day"]) * SimShip.wage_index(String(c["home"]))
	c["fixed"] = fresh["fixed_cr_per_day"]
	c["speed"] = fresh["ly_per_day"]
	c["fuel_units"] = fresh["fuel_units"]
	c["burn"] = fresh["burn"]
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


## What each person aboard costs per day: role and pay after the home port's rate and the level.
static func payroll_lines(sim: EconomySim) -> Array[Dictionary]:
	var c := player(sim)
	var out: Array[Dictionary] = []
	if c.is_empty():
		return out
	var k := SimShip.wage_index(String(c["home"])) * sim._lv(c, "wage_mult")
	for r in SimShip.payroll(int(c["crew"])):
		out.append({"role": r["role"], "pay": float(r["pay"]) * k})
	return out


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


## What a flight costs once the ship is back: the fuel burned at the port's price, hull repairs, and
## the clock moving on by the hours it took. Charges go through the sim so money stays conserved.
## `price_mult` is the site's fuel price against the system's (LocalSpace site_fuel_price).
static func settle_flight(sim: EconomySim, fuel_burned_t: float, seconds: float, damage: float, ship_cost: float, price_mult: float = 1.0) -> Dictionary:
	var c := player(sim)
	if c.is_empty():
		return {"fuel_cost": 0, "repair_cost": 0, "hours": 0}
	var units := fuel_burned_t * float(SimShip.config()["fuel"]["units_per_tonne"])
	var fuel_cost: float = units * float(sim.p["fuel_cr_per_unit"]) * float(sim.fuel_factor.get(c["sys"], 1.0)) * sim._lv(c, "fuel_price_mult") * price_mult
	var tune := FlightModel.load_tuning()
	var repair_cost := clampf(damage, 0.0, 1.0) * ship_cost * float(tune.get("repair_cost_fraction_of_ship", 0.15)) * sim._lv(c, "maintenance_mult")
	sim._pay(PLAYER, "world", fuel_cost + repair_cost)
	var hours := int(seconds / 3600.0)
	if hours > 0:
		sim.run_hours(hours)
	return {"fuel_cost": roundi(fuel_cost), "repair_cost": roundi(repair_cost), "hours": hours}
