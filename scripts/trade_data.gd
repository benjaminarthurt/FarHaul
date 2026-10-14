class_name TradeData
extends RefCounted
## What the trade report (TradeReport) shows, worked out from the economy simulation and its history
## (SimStats). Plain data, so it can be tested without drawing anything.

const TIGHT_ORDER := {"out": 0, "critical": 1, "short": 2}


static func system_name(sid: String) -> String:
	return String(Worlds.system(sid).get("name", sid))


static func facility_name(sim: EconomySim, fid: String) -> String:
	return String(sim.facilities.get(fid, {}).get("name", fid)).replace(" (assumed)", "")


static func company_name(id: String) -> String:
	if id == SimWorld.PLAYER:
		return "You"
	return id.replace("_", " ").capitalize()


static func goods_name(com: String) -> String:
	return Salvage.clib().label(StringName(com))


static func days(sim: EconomySim) -> Array:
	return sim.stats.get("days", []) if sim != null else []


## Sum of `key` over the last `n` day records, skipping the `skip` most recent.
static func _sum(ds: Array, key: String, n: int, skip := 0) -> float:
	var t := 0.0
	var end := ds.size() - skip
	for i in range(maxi(0, end - n), maxi(0, end)):
		t += float(ds[i].get(key, 0.0))
	return t


static func _pct(now: float, before: float) -> float:
	return (now - before) / before if before > 0.0 else 0.0


# --- Overview -----------------------------------------------------------------------------------

## Headline numbers, the daily series behind them, the carriers at work, the tightest shelves and the
## systems whose prices moved most this week.
static func overview(sim: EconomySim) -> Dictionary:
	var ds := days(sim)
	var out := {"day": sim.day(), "series": {"freight_cr": [], "goods_cr": [], "t": [], "player_cr": []}}
	for d in ds:
		out.series.freight_cr.append(float(d.freight_cr))
		out.series.goods_cr.append(float(d.goods_cr))
		out.series.t.append(float(d.t))
		out.series.player_cr.append(float(d.player.cr) + float(d.player.local_cr))
	for key in ["freight_cr", "goods_cr", "t", "deliveries"]:
		var week := _sum(ds, key, 7)
		out[key] = {"week": week, "prev": _sum(ds, key, 7, 7), "change": _pct(week, _sum(ds, key, 7, 7))}
	var working := 0
	var loaded := 0
	var npc := 0
	var npc_cash := 0.0
	for c in sim.carriers.values():
		if bool(c.get("manual", false)):
			continue
		npc += 1
		npc_cash += float(c["cash"])
		if String(c["state"]) != "idle":
			working += 1
			if not c["queue"].is_empty() and String(c["queue"][0].get("type", "")) == "travel" and bool(c["queue"][0].get("loaded", false)):
				loaded += 1
	var fac_cash := 0.0
	for f in sim.facilities.values():
		fac_cash += float(f["cash"])
	var open := 0
	var moving := 0
	for k in sim.contracts.values():
		match String(k["status"]):
			"offered":
				open += 1
			"accepted", "in_transit":
				moving += 1
	out["carriers"] = {"total": npc, "working": working, "loaded": loaded, "cash": npc_cash}
	out["facility_cash"] = fac_cash
	out["contracts"] = {"open": open, "moving": moving}
	out["tight"] = tight(sim, 8)
	out["movers"] = price_movers(sim, 6)
	return out


## The buyers running lowest, worst first: [{facility, name, system, system_name, state (their worst),
## goods: [names, worst first], cover_days (least), price (dearest ratio)}]. Out of stock beats critical
## beats short, then fewest days of cover.
static func tight(sim: EconomySim, limit := 8) -> Array:
	var by := {}
	for f in sim.facilities.values():
		if String(f["kind"]) == "supplier":
			continue
		for com in f["items"]:
			var it: Dictionary = f["items"][com]
			var st := String(it["state"])
			if not TIGHT_ORDER.has(st) or float(it["demand"]) <= 0.0:
				continue
			var fid := String(f["id"])
			var cover := minf(sim.cover_days(fid, String(com)), 999.0)
			var r: Dictionary = by.get(fid, {"facility": fid, "name": facility_name(sim, fid), "system": String(f["system_id"]),
					"system_name": system_name(String(f["system_id"])), "state": st, "items": [], "cover_days": cover, "price": 0.0})
			r.items.append({"goods": goods_name(String(com)), "rank": int(TIGHT_ORDER[st]) * 1000.0 + cover})
			if int(TIGHT_ORDER[st]) < int(TIGHT_ORDER[r.state]):
				r.state = st
			r.cover_days = minf(float(r.cover_days), cover)
			r.price = maxf(float(r.price), SimStats.price_ratio(sim, fid, String(com)))
			by[fid] = r
	var rows := []
	for fid in by:
		var r: Dictionary = by[fid]
		var items: Array = r.items
		items.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.rank) < float(b.rank))
		r["goods"] = items.map(func(i: Dictionary) -> String: return String(i.goods))
		r.erase("items")
		rows.append(r)
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(TIGHT_ORDER[a.state]) != int(TIGHT_ORDER[b.state]):
			return int(TIGHT_ORDER[a.state]) < int(TIGHT_ORDER[b.state])
		if (a.goods as Array).size() != (b.goods as Array).size():
			return (a.goods as Array).size() > (b.goods as Array).size()
		return float(a.cover_days) < float(b.cover_days))
	return rows.slice(0, limit)


## Systems whose price index moved most over the week: [{system, name, now, before, change}].
static func price_movers(sim: EconomySim, limit := 6) -> Array:
	var ds := days(sim)
	if ds.size() < 2:
		return []
	var now: Dictionary = ds.back().prices
	if now.is_empty() and ds.size() >= 2:
		now = ds[ds.size() - 2].prices
	var then: Dictionary = ds[maxi(0, ds.size() - 8)].prices
	var rows := []
	for sid in now:
		if not then.has(sid):
			continue
		rows.append({"system": String(sid), "name": system_name(String(sid)), "now": float(now[sid]), "before": float(then[sid]),
				"change": _pct(float(now[sid]), float(then[sid]))})
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return absf(float(a.change)) > absf(float(b.change)))
	return rows.slice(0, limit)


# --- Flows --------------------------------------------------------------------------------------

## Freight over the last `n` days by lane, each system's tonnes in and out, and every ship's position
## right now.
## lanes: [{a, b, t, cr, player_t, top: goods name}] heaviest first; systems: {sid: {in_t, out_t, cr_in, cr_out}};
## ships: [{a, b, progress, loaded, player, company}] (a == b: in port).
static func flows(sim: EconomySim, n := 7) -> Dictionary:
	var ds := days(sim)
	var lanes := {}
	var systems := {}
	for i in range(maxi(0, ds.size() - n), ds.size()):
		for key in ds[i].flows:
			var fl: Dictionary = ds[i].flows[key]
			var l: Dictionary = lanes.get(key, {"a": String(fl.a), "b": String(fl.b), "t": 0.0, "cr": 0.0, "player_t": 0.0, "coms": {}})
			l.t = float(l.t) + float(fl.t)
			l.cr = float(l.cr) + float(fl.cr)
			l.player_t = float(l.player_t) + float(fl.player_t)
			for com in fl.coms:
				l.coms[com] = float(l.coms.get(com, 0.0)) + float(fl.coms[com])
			lanes[key] = l
			for end in [["a", "out_t", "cr_out"], ["b", "in_t", "cr_in"]]:
				var sid := String(fl[end[0]])
				var s: Dictionary = systems.get(sid, {"in_t": 0.0, "out_t": 0.0, "cr_in": 0.0, "cr_out": 0.0})
				s[end[1]] = float(s[end[1]]) + float(fl.t)
				s[end[2]] = float(s[end[2]]) + float(fl.cr)   # freight money: paid by buyers at b, earned hauling out of a
				systems[sid] = s
	var rows := []
	for key in lanes:
		var l: Dictionary = lanes[key]
		var top := ""
		var best := -1.0
		for com in l.coms:
			if float(l.coms[com]) > best:
				best = float(l.coms[com])
				top = String(com)
		l["top"] = goods_name(top) if top != "" else ""
		l.erase("coms")
		rows.append(l)
	rows.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return float(x.t) > float(y.t))
	return {"lanes": rows, "systems": systems, "ships": ships(sim), "days": mini(n, ds.size())}


## Every carrier: where it is, or how far along the jump it's making.
static func ships(sim: EconomySim) -> Array:
	var out := []
	for c in sim.carriers.values():
		var row := {"a": String(c["sys"]), "b": String(c["sys"]), "progress": 0.0, "loaded": false, "player": String(c["id"]) == SimWorld.PLAYER,
				"company": String(c.get("company", ""))}
		if not c["queue"].is_empty():
			var a: Dictionary = c["queue"][0]
			if String(a.get("type", "")) == "travel" and a.has("left"):
				row.a = String(a["from"])
				row.b = String(a["to"])
				row.progress = clampf(1.0 - float(a["left"]) / maxf(float(a["hours"]), 1.0), 0.0, 1.0)
				row.loaded = bool(a.get("loaded", false))
		out.append(row)
	return out


# --- Companies ----------------------------------------------------------------------------------

## Each carrier company: [{id, name, ships, working, cash, net, revenue_30, share, trips, player}], by
## freight earned over the last 30 days, the player among them.
static func companies(sim: EconomySim) -> Array:
	var ds := days(sim)
	var earned := {}
	var total := 0.0
	for d in ds:
		for co in d.companies:
			earned[co] = float(earned.get(co, 0.0)) + float(d.companies[co])
			total += float(d.companies[co])
		earned["player"] = float(earned.get("player", 0.0)) + float(d.player.local_cr)   # in-system runs pay too
		total += float(d.player.local_cr)
	var by := {}
	for c in sim.carriers.values():
		var co := String(c.get("company", ""))
		var r: Dictionary = by.get(co, {"id": co, "name": company_name(co) if co != "player" else "You", "ships": 0, "working": 0, "cash": 0.0, "net": 0.0,
				"trips": 0, "player": co == "player"})
		r.ships = int(r.ships) + 1
		if String(c["state"]) != "idle":
			r.working = int(r.working) + 1
		r.cash = float(r.cash) + float(c["cash"])
		r.net = float(r.net) + float(c["cash"]) - float(c["start_cash"])
		r.trips = int(r.trips) + int(c["trips"])
		by[co] = r
	var rows := []
	for co in by:
		var r: Dictionary = by[co]
		r["revenue_30"] = float(earned.get(co, 0.0))
		r["share"] = float(r.revenue_30) / total if total > 0.0 else 0.0
		rows.append(r)
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.revenue_30) > float(b.revenue_30))
	for i in rows.size():
		rows[i]["rank"] = i + 1
	return rows


# --- You ----------------------------------------------------------------------------------------

## The player's mark on the economy: lifetime totals, the last 30 days against everyone, who they've
## supplied and where.
static func player(sim: EconomySim) -> Dictionary:
	var life := SimStats.lifetime(sim)
	var ds := days(sim)
	var mine := 0.0
	var all := 0.0
	var t30 := 0.0
	var series := []
	for d in ds:
		var p: Dictionary = d.player
		var cr := float(p.cr) + float(p.local_cr)
		mine += cr
		all += float(d.freight_cr) + float(p.local_cr)
		t30 += float(p.t) + float(p.local_t)
		series.append(cr + float(p.salvage_cr))
	var fac := []
	for fid in life.facilities:
		if sim.facilities.has(fid):
			var f: Dictionary = sim.facilities[fid]
			fac.append({"facility": String(fid), "name": facility_name(sim, String(fid)), "system_name": system_name(String(f["system_id"])), "t": float(life.facilities[fid])})
	fac.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.t) > float(b.t))
	var sys := []
	for sid in life.systems:
		sys.append({"system": String(sid), "name": system_name(String(sid)), "t": float(life.systems[sid])})
	sys.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.t) > float(b.t))
	var rank := 0
	var cos := companies(sim)
	for r in cos:
		if bool(r.player):
			rank = int(r.rank)
	return {"t": float(life.t) + float(life.local_t), "cr": float(life.cr) + float(life.local_cr), "interstellar_t": float(life.t), "local_t": float(life.local_t),
			"deliveries": int(life.deliveries) + int(life.local_runs), "relieved": int(life.relieved), "salvage_cr": float(life.salvage_cr),
			"days": sim.day() - int(life.get("since_day", sim.day())), "share_30": mine / all if all > 0.0 else 0.0, "cr_30": mine, "t_30": t30,
			"series": series, "facilities": fac.slice(0, 6), "facility_count": fac.size(), "systems": sys.slice(0, 6), "system_count": sys.size(),
			"rank": rank, "companies": cos.size()}
