class_name EconomySim
extends RefCounted
## Headless economy prototype. No graphics: a clock plus the world data.
## Follows data/runtime/simulation_tick.json order (subset):
##   advance clock -> consume -> produce -> procurement -> allocate shipments
##   -> markets -> company decisions -> contract offers -> carrier dispatch
##   -> advance freight -> validate invariants.
## Goods move only through SimLedger events; money only through _pay().
## Anything marked (assumed) in the scenario file is a placeholder to calibrate.

const SCU_MASS_FALLBACK_KG := 12000.0

var net := SimNetwork.new()
var ledger := SimLedger.new()
var commodities: Dictionary = {}
var market_mult: Dictionary = {}     # "system|commodity" -> baseline multiplier
var fuel_factor: Dictionary = {}     # system -> fuel price factor
var price_cfg: Dictionary = {}
var p: Dictionary = {}               # scenario params
var scu_mass_kg := SCU_MASS_FALLBACK_KG
var start_day := 0
var hour := 0
var facilities: Dictionary = {}
var carriers: Dictionary = {}
var lots: Dictionary = {}
var orders: Dictionary = {}
var contracts: Dictionary = {}
var events: Array = []
var violations: Array = []
var verbose := false
var world_cash := 0.0                # the rest of the economy (fuel, fees, wages, household income)
var cash_initial := 0.0
var _id := 0

# ---------------------------------------------------------------- loading

func load_all(world_dir: String, runtime_dir: String, scenario_file: String) -> bool:
	net.load_from(world_dir)
	var cd = SimNetwork.read_json(world_dir + "commodities.json")
	var md = SimNetwork.read_json(world_dir + "markets.json")
	var fd = SimNetwork.read_json(world_dir + "fuel_economy.json")
	var mr = SimNetwork.read_json(runtime_dir + "market_runtime.json")
	var ud = SimNetwork.read_json(runtime_dir + "units.json")
	var sc = SimNetwork.read_json(runtime_dir + scenario_file)
	if cd == null or md == null or fd == null or mr == null or sc == null:
		return false
	for c in cd["commodities"]:
		commodities[c["id"]] = c
	for m in md["markets"]:
		for e in m["commodities"]:
			market_mult[m["system_id"] + "|" + e["commodity_id"]] = float(e["price_multiplier"])
	for s in fd["system_supply"]:
		if s.get("price_factor") != null:   # frontier entries have no priced fuel
			fuel_factor[s["system_id"]] = float(s["price_factor"])
	price_cfg = mr["price_model"]["factors"]
	if ud != null:
		scu_mass_kg = float(ud["scu"].get("standard_max_gross_mass_kg", SCU_MASS_FALLBACK_KG))
	p = sc["params"]
	start_day = int(sc["start_day"])
	for f in sc["facilities"]:
		_add_facility(f)
	for c in sc["carriers"]:
		_add_carrier(c)
	return true

func _add_facility(f: Dictionary) -> void:
	var fac := {
		"id": f["id"], "name": f.get("name", f["id"]), "kind": f["kind"],
		"system_id": f["system_id"], "port_id": f["port_id"],
		"cash": float(f["cash"]), "income": float(f.get("income_cr_per_day", 0.0)),
		"reliability": float(f.get("reliability", 1.0)), "items": {}, "min_cash": float(f["cash"]),
		"goods_paid": 0.0, "freight_paid": 0.0,
	}
	for com in f["items"]:
		var s: Dictionary = f["items"][com]
		fac["items"][com] = {
			"reorder": float(s.get("reorder_point", 0)), "target": float(s.get("target_stock", 0)),
			"safety": float(s.get("safety_stock", 0)), "demand": float(s.get("daily_demand", 0)),
			"ema": float(s.get("daily_demand", 0)), "produce": float(s.get("produce_per_day", 0)),
			"max_stock": float(s.get("max_stock", 1e12)), "unit_cost": float(s.get("unit_cost", 0)),
			"price_mult": float(s.get("price_mult", 1.0)), "state": "normal",
			"lead_obs": 0.0, "outflow_ema": 0.0, "outflow_today": 0.0, "stockout_hours": 0, "unmet": 0.0, "consumed_today": 0.0, "min_on_hand": float(s.get("on_hand", 0)),
		}
		ledger.seed_stock(f["id"], com, float(s.get("on_hand", 0)))
	facilities[f["id"]] = fac
	cash_initial += fac["cash"]

func _add_carrier(c: Dictionary) -> void:
	var cr := {
		"id": c["id"], "company": c["company"], "sys": c["home_system_id"],
		"capacity_scu": float(c["capacity_scu"]), "dry_mass_t": float(c["dry_mass_t"]),
		"crew": int(c["crew"]), "wage": float(c["wage_cr_per_day"]), "fixed": float(c["fixed_cr_per_day"]),
		"cash": float(c["cash"]), "start_cash": float(c["cash"]), "min_margin": float(c["min_margin"]),
		"network": c["network"], "state": "idle", "queue": [], "job": [], "home": c["home_system_id"], "idle_since": 0,
		"revenue": 0.0, "costs": 0.0, "trips": 0, "delivered_scu": 0.0, "busy_hours": 0, "min_cash": float(c["cash"]),
	}
	carriers[c["id"]] = cr
	cash_initial += cr["cash"]

# ---------------------------------------------------------------- helpers

func _new_id(prefix: String) -> String:
	_id += 1
	return "%s_%04d" % [prefix, _id]

func day() -> int:
	return start_day + hour / 24

func stamp() -> String:
	return "D%d %02d:00" % [day(), hour % 24]

func _log(kind: String, fields: Dictionary = {}) -> void:
	var e := {"h": hour, "t": stamp(), "kind": kind}
	e.merge(fields)
	events.append(e)
	if verbose:
		var bits: Array = []
		for k in fields:
			var v = fields[k]
			bits.append("%s=%s" % [k, ("%.2f" % v) if v is float else str(v)])
		print("[%s] %-22s %s" % [e["t"], kind, " ".join(bits)])

func events_of(kind: String) -> Array:
	return events.filter(func(e): return e["kind"] == kind)

## Move money. Either side may be a facility, carrier or "world".
func _pay(from_id: String, to_id: String, amount: float) -> void:
	if amount == 0.0:
		return
	_adjust(from_id, -amount)
	_adjust(to_id, amount)

func _adjust(id: String, amount: float) -> void:
	if id == "world":
		world_cash += amount
	elif facilities.has(id):
		facilities[id]["cash"] += amount
		facilities[id]["min_cash"] = minf(facilities[id]["min_cash"], facilities[id]["cash"])
	elif carriers.has(id):
		var c: Dictionary = carriers[id]
		c["cash"] += amount
		c["min_cash"] = minf(c["min_cash"], c["cash"])
		if amount < 0.0:
			c["costs"] -= amount

func total_cash() -> float:
	var t := world_cash
	for f in facilities.values():
		t += f["cash"]
	for c in carriers.values():
		t += c["cash"]
	return t

func _scu(com: String, units: float) -> float:
	return units * float(commodities[com]["scu_per_unit"])

func _mass_kg(com: String, units: float) -> float:
	return units * float(commodities[com]["mass_kg_per_unit"])

## Units/day a facility plans around: its own use, or what it supplies to others.
func planning_demand(it: Dictionary) -> float:
	return maxf(it["ema"], it["outflow_ema"])

func cover_days(fid: String, com: String) -> float:
	var it: Dictionary = facilities[fid]["items"][com]
	var avail := ledger.available(fid, com)
	var d := planning_demand(it)
	if d <= 0.001:
		return INF
	return avail / d

## Estimated delivery time (days) for a typical replenishment of `com`: the fastest supplier
## that can actually fill it, or the slowest supplier when none can (stock-aware lead time).
func estimate_lead_days(fid: String, com: String) -> float:
	var buyer: Dictionary = facilities[fid]
	var need := maxf(1.0, planning_demand(buyer["items"][com]) * float(p["cycle_days"]))
	var best_fill := INF
	var worst := 0.0
	for f in facilities.values():
		if f["id"] == fid or f["kind"] == "consumer" or not f["items"].has(com):
			continue
		var segs := _segments(f["system_id"], buyer["system_id"], f["port_id"], buyer["port_id"])
		if segs.is_empty():
			continue
		var days := _est_hours(segs) / 24.0
		worst = maxf(worst, days)
		if ledger.available(f["id"], com) - f["items"][com]["safety"] >= need:
			best_fill = minf(best_fill, days)
	if best_fill < INF:
		return best_fill
	return worst if worst > 0.0 else 14.0

## Slowest nominal supplier path (days), used to bound how much observed lead time is trusted.
func worst_lead_days(fid: String, com: String) -> float:
	var buyer: Dictionary = facilities[fid]
	var worst := 0.0
	for f in facilities.values():
		if f["id"] == fid or f["kind"] == "consumer" or not f["items"].has(com):
			continue
		var segs := _segments(f["system_id"], buyer["system_id"], f["port_id"], buyer["port_id"])
		if not segs.is_empty():
			worst = maxf(worst, _est_hours(segs) / 24.0)
	return worst

## Effective reorder point / target: configured floors raised to cover lead time.
func policy(fid: String, com: String) -> Dictionary:
	var it: Dictionary = facilities[fid]["items"][com]
	if it["reorder"] <= 0.0:
		return {"reorder": 0.0, "target": it["target"]}
	var d := planning_demand(it)
	# Learn from real deliveries, but cap the correction so one slow patch cannot trigger a bullwhip.
	var est := estimate_lead_days(fid, com)
	# The cap is relative to the slowest real supplier path, not to the (often optimistic) nearest one,
	# because the nearest supplier is exactly the one that runs out when it matters.
	var cap := maxf(est * float(p["lead_learning_cap"]), worst_lead_days(fid, com) * float(p.get("lead_worst_cap", 1.7)))
	var lead := clampf(it["lead_obs"], est, cap)
	var reorder := maxf(it["reorder"], d * (lead + float(p["safety_days"])))
	var target := maxf(it["target"], reorder + d * float(p["cycle_days"]))
	return {"reorder": reorder, "target": target}

func shortage_state(fid: String, com: String) -> String:
	var it: Dictionary = facilities[fid]["items"][com]
	if ledger.available(fid, com) < 0.5 and it["demand"] > 0.0:
		return "out"
	var c := cover_days(fid, com)
	if c >= 14.0: return "normal"
	if c >= 7.0: return "tight"
	if c >= 3.0: return "short"
	return "critical"

## Local price: replacement-cost reference moved by stock cover (market_runtime.json).
func quote(fid: String, com: String) -> float:
	var f: Dictionary = facilities[fid]
	var it: Dictionary = f["items"][com]
	var ref: float = float(commodities[com]["base_value"]) * market_mult.get(f["system_id"] + "|" + com, 1.0) * it["price_mult"]
	var cover := cover_days(fid, com)
	var lo: float = price_cfg["inventory_cover_days"][0]
	var hi: float = price_cfg["inventory_cover_days"][1]
	var t := clampf(cover / 30.0, 0.0, 1.0)
	return ref * (1.0 + hi + (lo - hi) * t)

func _leg_hours(dist_ly: float) -> int:
	return int(ceil(dist_ly / float(p["ly_per_day"]) * 24.0))

func _path_hours(path: Array) -> int:
	var h := 0
	for i in range(path.size() - 1):
		h += _leg_hours(net.adj[path[i]][path[i + 1]])
		if i < path.size() - 2:
			h += int(p["port_dwell_hours"])
	return h

func _fuel_cost(from_sys: String, to_sys: String, ship_mass_t: float) -> float:
	var r := net.route(from_sys, to_sys)
	var coef: float = float(r.get("base_jump_fuel_units_per_mass_unit", 0.0))
	return coef * ship_mass_t * float(p["fuel_cr_per_unit"]) * fuel_factor.get(from_sys, 1.0)

func _port_fee(system_id: String) -> float:
	var port: Dictionary = net.ports.get(net.primary_port(system_id), {})
	return float(port.get("docking_fee", 0.0))

func _handling_cost(port_id: String, scu: float) -> float:
	var port: Dictionary = net.ports.get(port_id, {})
	return scu * float(p["handling_cr_per_scu"]) * float(port.get("cargo_handling_multiplier", 1.0))

## Cost of flying `path` for a ship; fuel, port fees and crew/fixed time.
func _trip_cost(ship: Dictionary, path: Array, cargo_mass_t: float) -> float:
	var cost := 0.0
	var per_day: float = ship["crew"] * ship["wage"] + ship["fixed"]
	for i in range(path.size() - 1):
		cost += _fuel_cost(path[i], path[i + 1], ship["dry_mass_t"] + cargo_mass_t)
		cost += _port_fee(path[i + 1])
	cost += _path_hours(path) / 24.0 * per_day
	return cost

# ---------------------------------------------------------------- routing and rates

func _segments(from_sys: String, to_sys: String, from_port: String, to_port: String) -> Array:
	var path := net.path(from_sys, to_sys)
	if path.is_empty():
		return []
	var cuts: Array = [0]
	for i in range(1, path.size() - 1):
		if path[i] in p["hub_systems"]:
			cuts.append(i)
	cuts.append(path.size() - 1)
	var segs: Array = []
	for k in range(cuts.size() - 1):
		var a: int = cuts[k]
		var b: int = cuts[k + 1]
		var sys: Array = path.slice(a, b + 1)
		segs.append({
			"systems": sys,
			"from_port": from_port if a == 0 else net.primary_port(path[a]),
			"to_port": to_port if b == path.size() - 1 else net.primary_port(path[b]),
		})
	return segs

func _est_hours(segs: Array) -> int:
	var h := 0
	for s in segs:
		h += int(p["dispatch_lag_hours"]) + _path_hours(s["systems"]) + 2 * int(p["loading_hours_base"])
	return h

func _urgency_modifier(buyer_id: String, com: String) -> float:
	match shortage_state(buyer_id, com):
		"out", "critical": return 2.0
		"short": return 1.5
		"tight": return 1.15
	return 1.0

func _segment_rate(systems: Array, scu: float, mass_kg: float, urgency: float) -> float:
	var ly := net.path_ly(systems)
	var chargeable := maxf(scu, mass_kg / scu_mass_kg)
	var mods := urgency
	for s in systems:
		if s in p["frontier_systems"]:
			mods *= float(p["frontier_modifier"])
			break
	var base: float = float(p["base_rate_cr_per_scu_ly"]) * chargeable * ly * mods
	var ref: Dictionary = p["reference_ship"]
	var refship := {"crew": ref["crew"], "wage": ref["wage_cr_per_day"], "fixed": ref["fixed_cr_per_day"], "dry_mass_t": ref["dry_mass_t"]}
	var floor_cost := _trip_cost(refship, systems, chargeable * scu_mass_kg / 1000.0) / float(ref["capacity_scu"]) * chargeable
	return maxf(floor_cost, base)

# ---------------------------------------------------------------- tick

func step_hour() -> void:
	hour += 1                                   # advance_clock
	_consume_and_produce()                      # consume + run_production + ledgers
	if hour % 24 == 0:
		_generate_procurement()                 # generate_procurement + allocate_shipments
		_update_markets()                       # update_markets
		_company_decisions()                    # run_company_decisions
		_escalate_open_contracts()              # generate_contract_offers (rate pressure)
	_dispatch_carriers()                        # dispatch_npc_carriers
	_advance_freight()                          # advance_freight
	var bad := ledger.check()                   # validate_invariants
	for b in bad:
		if not (b in violations):
			violations.append(b)
			_log("invariant_violation", {"detail": b})

func run_hours(n: int) -> void:
	for i in n:
		step_hour()

func run_days(n: int) -> void:
	run_hours(n * 24)

func _consume_and_produce() -> void:
	for f in facilities.values():
		for com in f["items"]:
			var it: Dictionary = f["items"][com]
			if it["demand"] > 0.0:
				var want: float = it["demand"] / 24.0
				var got := ledger.consume(f["id"], com, want)
				it["consumed_today"] += want    # demand, not fulfilment: shortages must not shrink the forecast
				if got < want - 1e-9:
					it["unmet"] += want - got
					it["stockout_hours"] += 1
			if it["produce"] > 0.0:
				var room: float = it["max_stock"] - ledger.on_hand(f["id"], com)
				var made := minf(it["produce"] / 24.0, maxf(room, 0.0))
				if made > 0.0:
					ledger.produce(f["id"], com, made)
					_pay(f["id"], "world", made * it["unit_cost"])
			it["min_on_hand"] = minf(it["min_on_hand"], ledger.on_hand(f["id"], com))
	for c in carriers.values():
		var per_hour: float = (c["crew"] * c["wage"] + c["fixed"]) / 24.0
		_pay(c["id"], "world", per_hour)
		if c["state"] != "idle":
			c["busy_hours"] += 1

# ---------------------------------------------------------------- procurement

func _inbound_units(fid: String, com: String) -> float:
	var t := 0.0
	for o in orders.values():
		if o["buyer"] == fid and o["com"] == com:
			t += o["units"] - o["received"]
	return t

## Inbound units that will land before the shelf is empty. A shipment due after the stock-out
## does not protect against it, so it should not stop a second, faster order.
func _inbound_in_time(fid: String, com: String, avail: float, demand: float) -> float:
	var runway_h := hour + int((avail / maxf(demand, 0.001) + float(p["safety_days"]) * 0.5) * 24.0)
	var t := 0.0
	for o in orders.values():
		if o["buyer"] == fid and o["com"] == com and o["eta"] <= runway_h:
			t += o["units"] - o["received"]
	return t

func _generate_procurement() -> void:
	for f in facilities.values():
		for com in f["items"]:
			var it: Dictionary = f["items"][com]
			if it["reorder"] <= 0.0:
				continue
			var pol := policy(f["id"], com)
			var avail := ledger.available(f["id"], com)
			var inbound := _inbound_units(f["id"], com)
			var protect := _inbound_in_time(f["id"], com, avail, planning_demand(it))
			if avail + protect > pol["reorder"] or avail + inbound > pol["target"]:
				continue
			# Never place a sliver order: each one is a lot, a contract and a carrier trip.
			var request := maxf(ceilf(pol["target"] - (avail + inbound)), ceilf(planning_demand(it) * float(p["cycle_days"]) * 0.75))
			if request < 1.0:
				continue
			_log("reorder_triggered", {"facility": f["id"], "commodity": com, "available": avail,
					"inbound": inbound, "reorder_point": pol["reorder"], "target": pol["target"],
					"daily_demand": planning_demand(it), "requested": request})
			_source(f["id"], com, request)

func _source(buyer_id: String, com: String, request: float) -> void:
	var buyer: Dictionary = facilities[buyer_id]
	var cands: Array = []
	for f in facilities.values():
		if f["id"] == buyer_id or f["kind"] == "consumer" or not f["items"].has(com):
			continue
		var alloc := floorf(ledger.available(f["id"], com) - f["items"][com]["safety"])
		if alloc < 1.0:
			continue
		var segs := _segments(f["system_id"], buyer["system_id"], f["port_id"], buyer["port_id"])
		if segs.is_empty():
			continue
		var price := quote(f["id"], com)
		var freight := 0.0
		for s in segs:
			freight += _segment_rate(s["systems"], _scu(com, 1.0), _mass_kg(com, 1.0), 1.0)
		var hours := _est_hours(segs)
		# Normally price dominates. Once the shelf will empty before this supplier could deliver,
		# every extra day of transit counts heavily against it.
		var late_days := maxf(0.0, hours / 24.0 - cover_days(buyer_id, com))
		var score: float = (price + freight) * (1.0 + hours / 24.0 * 0.01 + late_days * float(p.get("late_weight", 0.08))) / f["reliability"]
		cands.append({"f": f, "alloc": alloc, "price": price, "segs": segs, "hours": hours, "score": score, "freight": freight})
	cands.sort_custom(func(a, b): return a["score"] < b["score"])
	var remaining := request
	var demand: float = planning_demand(buyer["items"][com])
	var min_hours := 1 << 30
	for c in cands:
		min_hours = mini(min_hours, c["hours"])
	for c in cands:
		if remaining < 1.0:
			break
		# A slower supplier must also cover what the buyer burns while the shipment is en route.
		var extra: float = demand * maxf(0.0, float(c["hours"] - min_hours) / 24.0)
		var units := floorf(minf(c["alloc"], remaining + extra))
		if units < 1.0:
			continue
		_place_order(buyer, c["f"], com, units, c["price"], c["segs"], c["hours"], c["freight"])
		remaining -= units
	if remaining >= 1.0:
		_log("procurement_shortfall", {"facility": buyer_id, "commodity": com, "unsourced": remaining})

func _place_order(buyer: Dictionary, seller: Dictionary, com: String, units: float, price: float,
		segs: Array, est_hours: int, freight_unit: float) -> void:
	var oid := _new_id("order")
	var deadline := hour + int(ceil(est_hours * float(p["deadline_slack"]))) + 48
	var order := {"id": oid, "buyer": buyer["id"], "seller": seller["id"], "com": com, "units": units,
			"unit_price": price, "placed": hour, "deadline": deadline, "received": 0.0, "lots": [],
			"eta": hour + int(maxf(float(est_hours), float(buyer["items"][com]["lead_obs"]) * 24.0))}
	orders[oid] = order
	seller["items"][com]["outflow_today"] += units
	var lot_units: float = maxf(1.0, floorf(float(p["lot_size_scu"]) / float(commodities[com]["scu_per_unit"])))
	var left := units
	while left > 0.0:
		var u := minf(lot_units, left)
		left -= u
		if not ledger.reserve(seller["id"], com, u):
			_log("error", {"detail": "reserve failed", "order": oid})
			continue
		var lid := _new_id("lot")
		lots[lid] = {"id": lid, "order": oid, "com": com, "units": u, "scu": _scu(com, u),
				"mass_kg": _mass_kg(com, u), "segs": segs, "seg_i": 0, "holder": seller["id"], "status": "awaiting_carrier"}
		order["lots"].append(lid)
	_log("procurement_ordered", {"order": oid, "buyer": buyer["id"], "seller": seller["id"], "commodity": com,
			"units": units, "unit_price": price, "freight_est_per_unit": freight_unit,
			"deadline_day": start_day + deadline / 24, "supplier_selection": "landed_cost+lead_time+reliability"})
	_log("lots_allocated", {"order": oid, "lots": ",".join(order["lots"]), "count": order["lots"].size()})
	for lid in order["lots"]:
		_offer_contract(lots[lid])

# ---------------------------------------------------------------- contracts

func _offer_contract(lot: Dictionary) -> void:
	var seg: Dictionary = lot["segs"][lot["seg_i"]]
	var order: Dictionary = orders[lot["order"]]
	var urgency := _urgency_modifier(order["buyer"], lot["com"])
	var rate := _segment_rate(seg["systems"], lot["scu"], lot["mass_kg"], urgency)
	var cid := _new_id("contract")
	contracts[cid] = {"id": cid, "lot": lot["id"], "seg_i": lot["seg_i"], "systems": seg["systems"],
			"origin_port": seg["from_port"], "dest_port": seg["to_port"], "origin_sys": seg["systems"][0],
			"dest_sys": seg["systems"][seg["systems"].size() - 1], "scu": lot["scu"], "mass_kg": lot["mass_kg"],
			"rate": rate, "rate0": rate, "offered": hour, "deadline": order["deadline"], "status": "offered",
			"carrier": "", "accepted": -1, "delivered": -1}
	lot["status"] = "awaiting_carrier"
	_log("contract_offered", {"contract": cid, "lot": lot["id"], "order": lot["order"],
			"from": seg["from_port"], "to": seg["to_port"], "scu": lot["scu"], "rate": rate,
			"leg": "%d/%d" % [lot["seg_i"] + 1, lot["segs"].size()]})

func _escalate_open_contracts() -> void:
	for c in contracts.values():
		if c["status"] == "offered" and hour - c["offered"] >= 24:
			var cap: float = c["rate0"] * float(p["rate_cap_modifier"])
			c["rate"] = minf(c["rate"] * (1.0 + float(p["rate_escalation_per_day"])), cap)

func _update_markets() -> void:
	for f in facilities.values():
		for com in f["items"]:
			var it: Dictionary = f["items"][com]
			it["ema"] = 0.9 * it["ema"] + 0.1 * it["consumed_today"] if it["demand"] > 0.0 else it["ema"]
			it["consumed_today"] = 0.0
			it["outflow_ema"] = 0.96 * it["outflow_ema"] + 0.04 * it["outflow_today"] if f["kind"] != "consumer" else 0.0
			it["outflow_today"] = 0.0
			var st := shortage_state(f["id"], com)
			if st != it["state"]:
				_log("shortage_state", {"facility": f["id"], "commodity": com, "from": it["state"], "to": st,
						"available": ledger.available(f["id"], com), "price": quote(f["id"], com)})
				it["state"] = st

func _company_decisions() -> void:
	for f in facilities.values():
		if f["income"] > 0.0:
			_pay("world", f["id"], f["income"])

# ---------------------------------------------------------------- carriers

func _eligible(c: Dictionary, k: Dictionary) -> bool:
	for s in k["systems"]:
		if not (s in c["network"]):
			return false
	return true

func _dispatch_carriers() -> void:
	var offered: Array = []
	for k in contracts.values():
		if k["status"] == "offered":
			offered.append(k)
	offered.sort_custom(func(a, b): return a["offered"] < b["offered"])
	for c in carriers.values():
		if c["state"] != "idle":
			continue
		var best: Dictionary = {}
		var seen := {}
		for k in offered:
			if k["status"] != "offered" or not _eligible(c, k):
				continue
			var key: String = k["origin_port"] + ">" + k["dest_port"]
			if seen.has(key):
				continue
			seen[key] = true
			var bundle := _bundle(c, k, offered)
			var ev := _evaluate(c, bundle)
			if ev.is_empty():
				continue
			# Older freight gains priority so small or low-margin lots are not starved forever.
			var age_days := 0.0
			for b in bundle:
				age_days = maxf(age_days, (hour - b["offered"]) / 24.0)
			ev["score"] = ev["margin"] * (1.0 + age_days * 0.15)
			if best.is_empty() or ev["score"] > best["score"]:
				best = ev
		if not best.is_empty():
			_accept(c, best)
		elif c["sys"] != c["home"] and hour - c["idle_since"] >= int(p["idle_return_hours"]):
			_return_home(c)

## Idle ships with no work head back to their home port, where their freight originates.
func _return_home(c: Dictionary) -> void:
	var path := net.path(c["sys"], c["home"])
	if path.size() < 2:
		return
	c["state"] = "returning"
	c["job"] = []
	c["queue"] = []
	_queue_path(c, path, false)

func _bundle(c: Dictionary, first: Dictionary, offered: Array) -> Array:
	var out: Array = [first]
	var scu: float = first["scu"]
	var mass: float = first["mass_kg"]
	var cap_mass: float = c["capacity_scu"] * scu_mass_kg
	for k in offered:
		if k == first or k["status"] != "offered" or not _eligible(c, k):
			continue
		if k["origin_port"] != first["origin_port"] or k["dest_port"] != first["dest_port"]:
			continue
		if scu + k["scu"] <= c["capacity_scu"] and mass + k["mass_kg"] <= cap_mass:
			out.append(k)
			scu += k["scu"]
			mass += k["mass_kg"]
	return out

func _evaluate(c: Dictionary, bundle: Array) -> Dictionary:
	var first: Dictionary = bundle[0]
	if first["scu"] > c["capacity_scu"]:
		return {}
	var revenue := 0.0
	var scu := 0.0
	var mass := 0.0
	for k in bundle:
		revenue += k["rate"]
		scu += k["scu"]
		mass += k["mass_kg"]
	var repo := net.path(c["sys"], first["origin_sys"])
	if repo.is_empty():
		return {}
	for s in repo:
		if not (s in c["network"]):
			return {}
	var cost := _trip_cost(c, repo, 0.0) + _trip_cost(c, first["systems"], mass / 1000.0)
	var back := net.path(first["dest_sys"], c["home"])    # deadhead back to the home port
	if back.size() > 1:
		cost += _trip_cost(c, back, 0.0)
	cost += _handling_cost(first["origin_port"], scu) + _handling_cost(first["dest_port"], scu)
	var per_day: float = c["crew"] * c["wage"] + c["fixed"]
	cost += 2.0 * (float(p["loading_hours_base"]) + float(p["loading_hours_per_scu"]) * scu) / 24.0 * per_day
	cost += revenue * float(p["maintenance_reserve_fraction"])
	var margin := revenue - cost
	if revenue <= 0.0 or margin / revenue < c["min_margin"]:
		return {}
	return {"bundle": bundle, "margin": margin, "margin_frac": margin / revenue, "revenue": revenue, "repo": repo}

func _accept(c: Dictionary, ev: Dictionary) -> void:
	var bundle: Array = ev["bundle"]
	var first: Dictionary = bundle[0]
	c["job"] = []
	var scu := 0.0
	for k in bundle:
		k["status"] = "accepted"
		k["carrier"] = c["id"]
		k["accepted"] = hour
		c["job"].append(k["id"])
		scu += k["scu"]
		var lot: Dictionary = lots[k["lot"]]
		lot["status"] = "contracted"
		# Hub-yard lots are reserved when committed; first-leg lots were reserved at allocation.
		_log("contract_accepted", {"contract": k["id"], "carrier": c["id"], "lot": k["lot"], "rate": k["rate"],
				"margin_frac": ev["margin_frac"], "carrier_at": c["sys"]})
	c["state"] = "working"
	c["trips"] += 1
	c["queue"] = [{"type": "wait", "hours": int(p["dispatch_lag_hours"])}]
	var repo: Array = ev["repo"]
	_queue_path(c, repo, false)
	c["queue"].append({"type": "load"})
	_queue_path(c, first["systems"], true)
	c["queue"].append({"type": "unload"})

func _queue_path(c: Dictionary, path: Array, loaded: bool) -> void:
	for i in range(path.size() - 1):
		c["queue"].append({"type": "travel", "from": path[i], "to": path[i + 1],
				"hours": _leg_hours(net.adj[path[i]][path[i + 1]]), "loaded": loaded})
		if i < path.size() - 2:
			c["queue"].append({"type": "wait", "hours": int(p["port_dwell_hours"])})

func _advance_freight() -> void:
	for c in carriers.values():
		if c["state"] == "idle":
			continue
		if c["queue"].is_empty():
			_finish_job(c)
			continue
		var a: Dictionary = c["queue"][0]
		if not a.has("left"):
			_start_action(c, a)
		a["left"] -= 1
		if a["left"] <= 0:
			c["queue"].pop_front()
			_complete_action(c, a)
			if c["queue"].is_empty():
				_finish_job(c)

func _job_scu(c: Dictionary) -> float:
	var t := 0.0
	for kid in c["job"]:
		t += contracts[kid]["scu"]
	return t

func _job_mass_t(c: Dictionary) -> float:
	var t := 0.0
	for kid in c["job"]:
		t += contracts[kid]["mass_kg"]
	return t / 1000.0

func _start_action(c: Dictionary, a: Dictionary) -> void:
	match a["type"]:
		"wait":
			a["left"] = a["hours"]
		"load", "unload":
			a["left"] = int(ceil(float(p["loading_hours_base"]) + float(p["loading_hours_per_scu"]) * _job_scu(c)))
		"travel":
			a["left"] = a["hours"]
			var mass_t: float = c["dry_mass_t"] + (_job_mass_t(c) if a["loaded"] else 0.0)
			_pay(c["id"], "world", _fuel_cost(a["from"], a["to"], mass_t))
			if a["loaded"]:
				_log("departed", {"carrier": c["id"], "from": a["from"], "to": a["to"], "days": a["hours"] / 24.0})

func _complete_action(c: Dictionary, a: Dictionary) -> void:
	match a["type"]:
		"travel":
			c["sys"] = a["to"]
			_pay(c["id"], "world", _port_fee(a["to"]))
			if a["loaded"]:
				_log("arrived", {"carrier": c["id"], "system": a["to"]})
		"load":
			_pickup(c)
		"unload":
			_deliver(c)

func _pickup(c: Dictionary) -> void:
	for kid in c["job"]:
		var k: Dictionary = contracts[kid]
		var lot: Dictionary = lots[k["lot"]]
		var holder: String = lot["holder"]
		if not ledger.ship_out(holder, lot["com"], lot["units"]):
			_log("error", {"detail": "pickup failed", "lot": lot["id"], "holder": holder})
			continue
		ledger.receive("hold:" + c["id"], lot["com"], lot["units"])
		ledger.reserve("hold:" + c["id"], lot["com"], lot["units"])   # committed to its consignee
		lot["holder"] = "hold:" + c["id"]
		lot["status"] = "in_transit"
		k["status"] = "in_transit"
		_pay(orders[lot["order"]]["buyer"], "world", _handling_cost(k["origin_port"], lot["scu"]))
		_log("picked_up", {"contract": kid, "lot": lot["id"], "carrier": c["id"], "from": k["origin_port"],
				"units": lot["units"]})

func _deliver(c: Dictionary) -> void:
	for kid in c["job"]:
		var k: Dictionary = contracts[kid]
		var lot: Dictionary = lots[k["lot"]]
		var order: Dictionary = orders[lot["order"]]
		var buyer: Dictionary = facilities[order["buyer"]]
		if not ledger.ship_out(lot["holder"], lot["com"], lot["units"]):
			_log("error", {"detail": "delivery failed", "lot": lot["id"]})
			continue
		k["status"] = "delivered"
		k["delivered"] = hour
		_pay(buyer["id"], "world", _handling_cost(k["dest_port"], lot["scu"]))
		_pay(buyer["id"], c["id"], k["rate"])
		buyer["freight_paid"] += k["rate"]
		c["revenue"] += k["rate"]
		c["delivered_scu"] += lot["scu"]
		_log("carrier_paid", {"contract": kid, "carrier": c["id"], "payer": buyer["id"], "amount": k["rate"]})
		if lot["seg_i"] >= lot["segs"].size() - 1:
			ledger.receive(buyer["id"], lot["com"], lot["units"])
			lot["holder"] = buyer["id"]
			lot["status"] = "delivered"
			order["received"] += lot["units"]
			var lead_days: float = (hour - order["placed"]) / 24.0
			var bit: Dictionary = buyer["items"][lot["com"]]
			bit["lead_obs"] = lead_days if bit["lead_obs"] <= 0.0 else 0.7 * bit["lead_obs"] + 0.3 * lead_days
			var pay: float = lot["units"] * order["unit_price"]
			_pay(buyer["id"], order["seller"], pay)
			buyer["goods_paid"] += pay
			_log("received", {"facility": buyer["id"], "commodity": lot["com"], "lot": lot["id"], "units": lot["units"],
					"on_hand": ledger.on_hand(buyer["id"], lot["com"]), "order": order["id"]})
			_log("supplier_paid", {"order": order["id"], "supplier": order["seller"], "amount": pay})
		else:
			var yard: String = "yard:" + str(k["dest_port"])
			ledger.receive(yard, lot["com"], lot["units"])
			ledger.reserve(yard, lot["com"], lot["units"])
			lot["holder"] = yard
			lot["seg_i"] += 1
			lot["status"] = "at_hub"
			_pay(buyer["id"], "world", float(p["transfer_fee_cr_per_scu"]) * lot["scu"])
			_log("transfer_at_hub", {"lot": lot["id"], "hub": k["dest_port"], "units": lot["units"]})
			_offer_contract(lot)

func _finish_job(c: Dictionary) -> void:
	# Maintenance reserve on revenue earned this job is an ordinary running cost.
	var earned := 0.0
	for kid in c["job"]:
		earned += contracts[kid]["rate"]
	_pay(c["id"], "world", earned * float(p["maintenance_reserve_fraction"]))
	c["job"] = []
	c["queue"] = []
	c["state"] = "idle"
	c["idle_since"] = hour

# ---------------------------------------------------------------- reporting

func summary() -> Dictionary:
	var days := maxf(hour / 24.0, 1.0)
	var out := {"days": hour / 24.0, "facilities": {}, "carriers": {}}
	for f in facilities.values():
		for com in f["items"]:
			var it: Dictionary = f["items"][com]
			if f["kind"] == "consumer" or f["kind"] == "distributor":
				out["facilities"][f["id"]] = {"stockout_hours": it["stockout_hours"], "min_on_hand": it["min_on_hand"],
						"on_hand": ledger.on_hand(f["id"], com), "cash": f["cash"], "state": it["state"],
						"freight_to_goods": f["freight_paid"] / maxf(f["goods_paid"], 1.0)}
	var open := 0
	var late := 0
	var delivered := 0
	var transit_h := 0.0
	var oldest_offer := 0
	for k in contracts.values():
		if k["status"] == "delivered":
			delivered += 1
			transit_h += k["delivered"] - k["offered"]
			if k["delivered"] > k["deadline"]:
				late += 1
		elif k["status"] == "offered":
			open += 1
			oldest_offer = maxi(oldest_offer, hour - k["offered"])
	out["contracts"] = {"total": contracts.size(), "delivered": delivered, "open": open, "late": late,
			"avg_offer_to_delivery_days": (transit_h / delivered / 24.0) if delivered > 0 else 0.0,
			"oldest_open_offer_hours": oldest_offer}
	for c in carriers.values():
		out["carriers"][c["id"]] = {"net_cash": c["cash"] - c["start_cash"], "net_per_day": (c["cash"] - c["start_cash"]) / days,
				"revenue": c["revenue"], "costs": c["costs"], "trips": c["trips"],
				"utilization": c["busy_hours"] / maxf(float(hour), 1.0), "min_cash": c["min_cash"]}
	out["cash_error"] = total_cash() - cash_initial
	out["violations"] = violations.size()
	return out
