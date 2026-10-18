class_name SimStats
extends RefCounted
## The economy's memory, for the trade report (TradeReport): what moved where each day and what it was
## paid, how prices and shortages stood, and what the player has done to it all. Kept in
## `EconomySim.stats` (saved with the sim):
##   days:   the last KEEP_DAYS days, oldest first: {day, freight_cr, goods_cr, t, deliveries,
##           flows: {"A>B": {a, b, t, cr, player_t, coms: {com: t}}}, coms: {com: t delivered},
##           companies: {company: freight cr}, player: {t, cr, local_t, local_cr, salvage_cr, relieved},
##           prices: {system: price index, 1.0 = reference}, short: {system: items short or worse}}
##   player: the player's lifetime totals: {t, cr, deliveries, local_t, local_cr, local_runs, salvage_cr,
##           relieved, systems: {system: t}, facilities: {facility: t}, since_day}
## Recording never moves goods or money: the sim behaves the same with or without it.

const KEEP_DAYS := 30
const TIGHT := ["out", "critical", "short"]


static func _blank(day: int) -> Dictionary:
	return {"day": day, "freight_cr": 0.0, "goods_cr": 0.0, "t": 0.0, "deliveries": 0, "flows": {}, "coms": {},
			"companies": {}, "player": {"t": 0.0, "cr": 0.0, "local_t": 0.0, "local_cr": 0.0, "salvage_cr": 0.0, "relieved": 0},
			"prices": {}, "short": {}}


## Today's record, started if the day has turned.
static func today(sim: EconomySim) -> Dictionary:
	var days: Array = sim.stats.get("days", [])
	if days.is_empty() or int(days.back().day) != sim.day():
		days.append(_blank(sim.day()))
		while days.size() > KEEP_DAYS:
			days.pop_front()
		sim.stats["days"] = days
	return days.back()


static func lifetime(sim: EconomySim) -> Dictionary:
	if not sim.stats.has("player"):
		sim.stats["player"] = {"t": 0.0, "cr": 0.0, "deliveries": 0, "local_t": 0.0, "local_cr": 0.0, "local_runs": 0,
				"salvage_cr": 0.0, "relieved": 0, "systems": {}, "facilities": {}, "since_day": sim.day()}
	return sim.stats["player"]


static func _add(d: Dictionary, key: String, v: float) -> void:
	d[key] = float(d.get(key, 0.0)) + v


## A carrier finished a leg (EconomySim._deliver): `paid` for `lot` from k.origin_sys to k.dest_sys.
static func on_leg(sim: EconomySim, k: Dictionary, lot: Dictionary, c: Dictionary, paid: float) -> void:
	var day := today(sim)
	var t := float(lot["mass_kg"]) / 1000.0
	var player := String(c["id"]) == SimWorld.PLAYER
	day["freight_cr"] = float(day["freight_cr"]) + paid
	day["t"] = float(day["t"]) + t
	day["deliveries"] = int(day["deliveries"]) + 1
	var a := String(k["origin_sys"])
	var b := String(k["dest_sys"])
	var key := "%s>%s" % [a, b]
	var fl: Dictionary = day["flows"].get(key, {"a": a, "b": b, "t": 0.0, "cr": 0.0, "player_t": 0.0, "coms": {}})
	fl["t"] = float(fl["t"]) + t
	fl["cr"] = float(fl["cr"]) + paid
	_add(fl["coms"], String(lot["com"]), t)
	if player:
		fl["player_t"] = float(fl["player_t"]) + t
	day["flows"][key] = fl
	_add(day["companies"], String(c.get("company", "")), paid)
	if player:
		_add(day["player"], "t", t)
		_add(day["player"], "cr", paid)
		var life := lifetime(sim)
		_add(life, "t", t)
		_add(life, "cr", paid)
		life["deliveries"] = int(life["deliveries"]) + 1
		_add(life["systems"], b, t)
		# frontier growth: freight into a system's port supplies it; freight out of one is its trade
		Development.moved(sim, String(Worlds.primary_port(b).get("id", "")), t)
		Development.moved(sim, String(Worlds.primary_port(a).get("id", "")), t, true)


## Goods reached the facility that ordered them. `before` is its shortage state for them beforehand;
## `carrier` brought the last leg.
static func on_received(sim: EconomySim, buyer: Dictionary, com: String, mass_t: float, pay: float, before: String, carrier: String) -> void:
	var day := today(sim)
	day["goods_cr"] = float(day["goods_cr"]) + pay
	_add(day["coms"], com, mass_t)
	if carrier != SimWorld.PLAYER:
		return
	var life := lifetime(sim)
	_add(life["facilities"], String(buyer["id"]), mass_t)
	if before in TIGHT:
		day["player"]["relieved"] = int(day["player"]["relieved"]) + 1
		life["relieved"] = int(life["relieved"]) + 1


## The player finished an in-system run (Session._deliver_local): `t` tonnes for `cr` in `system`.
static func on_local(sim: EconomySim, system: String, t: float, cr: float) -> void:
	var day := today(sim)
	_add(day["player"], "local_t", t)
	_add(day["player"], "local_cr", cr)
	var life := lifetime(sim)
	_add(life, "local_t", t)
	_add(life, "local_cr", cr)
	life["local_runs"] = int(life["local_runs"]) + 1
	if t > 0.0:
		_add(life["systems"], system, t)


## The player sold salvage (Salvage.sell): `cr`, and `t` tonnes of it onto `buyer`'s shelf if a facility bought it.
static func on_salvage(sim: EconomySim, cr: float, buyer: String = "", t: float = 0.0) -> void:
	_add(today(sim)["player"], "salvage_cr", cr)
	var life := lifetime(sim)
	_add(life, "salvage_cr", cr)
	if buyer != "" and t > 0.0:
		_add(life["facilities"], buyer, t)


## Price against the reference for `com` at `fid`: 1.0 is the going rate, 1.3 is 30% dear.
static func price_ratio(sim: EconomySim, fid: String, com: String) -> float:
	var f: Dictionary = sim.facilities[fid]
	var it: Dictionary = f["items"][com]
	var ref: float = float(sim.commodities[com]["base_value"]) * float(sim.market_mult.get(String(f["system_id"]) + "|" + com, 1.0)) * float(it["price_mult"])
	return sim.quote(fid, com) / ref if ref > 0.0 else 1.0


## Once a day (EconomySim.step_hour at midnight): each system's price index (mean price ratio over what
## its buyers use) and how many of their goods are short or worse, onto the new day's record.
static func day_turned(sim: EconomySim) -> void:
	var day := today(sim)
	var sums := {}
	var counts := {}
	var short := {}
	for f in sim.facilities.values():
		if String(f["kind"]) == "supplier":
			continue
		var sys := String(f["system_id"])
		for com in f["items"]:
			var it: Dictionary = f["items"][com]
			if float(it["demand"]) <= 0.0:
				continue
			_add(sums, sys, price_ratio(sim, String(f["id"]), String(com)))
			_add(counts, sys, 1.0)
			if String(it["state"]) in TIGHT:
				short[sys] = int(short.get(sys, 0)) + 1
	for sys in sums:
		day["prices"][sys] = float(sums[sys]) / maxf(float(counts[sys]), 1.0)
	day["short"] = short
