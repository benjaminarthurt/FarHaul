class_name Contracts
extends RefCounted
## Data-driven freight opportunities generated from market supply/demand and known routes.
## These are deterministic offers for now: dynamic stock, deadlines and reputation can layer on later.


static func offers_from(system_id: String, limit: int = 8) -> Array[Dictionary]:
	# In a saved game the board is the live economy: real stock moving between real facilities.
	if Session.sim != null:
		if Session.slot >= 0:
			var loaded := Session._load_ship(SaveSlots.read(Session.slot))
			if not loaded.is_empty():
				Session._sync_sim(loaded.ship)
		var live := SimWorld.board(Session.sim, system_id, limit)
		if not live.is_empty():
			return live
		# Outside the slice the live economy covers (or when nothing is posted), fall back to the
		# scheduled market freight below so every port still has something to haul.
	var origin := Worlds.market(system_id)
	if origin.is_empty():
		return []
	var offers: Array[Dictionary] = []
	for route in _routes_from(system_id):
		var destination_id := String(route.b) if String(route.a) == system_id else String(route.a)
		var destination := Worlds.market(destination_id)
		if destination.is_empty():
			continue
		for source_row in origin.get("commodities", []):
			if int(source_row.get("stock", 0)) < 3:
				continue
			var target_row := _market_row(destination, String(source_row.commodity_id))
			if target_row.is_empty() or int(target_row.get("demand", 0)) < 4:
				continue
			var goods := Worlds.commodity(String(source_row.commodity_id))
			if goods.is_empty():
				continue
			var tonnes := maxf(1.0, float(goods.get("mass_kg_per_unit", 1000)) / 1000.0)
			var spread := maxf(0.08, float(target_row.price_multiplier) - float(source_row.price_multiplier))
			var distance := float(route.get("distance_ly", Worlds.distance_ly(system_id, destination_id)))
			var rate := roundi(float(goods.base_value) * (0.10 + spread * 0.32) + distance * 45.0)
			var amount := clampf(12.0 + float(target_row.demand) * 8.0 + distance * 1.5, tonnes, 120.0)
			offers.append({
				"id": "%s_%s_%s" % [system_id, destination_id, source_row.commodity_id],
				"title": "%s to %s" % [goods.name, destination_id.replace("_", " ").capitalize()],
				"commodity": StringName(source_row.commodity_id),
				"offer": snappedf(amount, 0.1),
				"rate": rate,
				"origin_system_id": system_id,
				"destination_system_id": destination_id,
				"origin_port_id": String(Worlds.primary_port(system_id).get("id", "")),
				"destination_port_id": String(Worlds.primary_port(destination_id).get("id", "")),
				"distance_ly": distance,
				"min_twr": 0.05,
				"blurb": "Market freight generated from local surplus and destination demand."
			})
	offers.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.rate) > int(b.rate))
	return offers.slice(0, mini(limit, offers.size()))


static func _routes_from(system_id: String) -> Array:
	var path := "res://data/world/routes.json"
	if not FileAccess.file_exists(path):
		return []
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	var out: Array = []
	if typeof(parsed) == TYPE_DICTIONARY:
		for r in parsed.get("routes", []):
			if String(r.a) == system_id or String(r.b) == system_id:
				out.append(r)
	return out


static func _market_row(market: Dictionary, commodity_id: String) -> Dictionary:
	for row in market.get("commodities", []):
		if String(row.commodity_id) == commodity_id:
			return row
	return {}


static func get_contract(index: int, system_id: String = "new_houston") -> Dictionary:
	var list := offers_from(system_id)
	return list[clampi(index, 0, list.size() - 1)] if not list.is_empty() else {}


static func payable_tonnes(manifest: CargoManifest, c: Dictionary) -> float:
	return minf(manifest.total_of(c.commodity), c.offer)


static func pay(manifest: CargoManifest, c: Dictionary) -> int:
	return roundi(payable_tonnes(manifest, c) * c.rate)


static func best_pay(manifest: CargoManifest, c: Dictionary) -> int:
	return roundi(minf(manifest.capacity(), c.offer) * c.rate)


static func check(stats: Dictionary, manifest: CargoManifest, c: Dictionary) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	rows.append(_row("Cockpit", stats.has_helm, "" if stats.has_helm else "nothing to fly it from"))
	rows.append(_row("Engines", stats.thrust_fwd > 0.0, "" if stats.thrust_fwd > 0.0 else "no thrust"))
	rows.append(_row("Hull sealed", stats.open_doors == 0, "%d open doorways" % stats.open_doors))
	rows.append(_row("Airlock", stats.airlocks > 0, "" if stats.airlocks > 0 else "none fitted"))
	rows.append(_row("Power", stats.power_use <= stats.power_gen, "%.0f of %.0f kW" % [stats.power_use, stats.power_gen]))
	rows.append(_row("Cooling", stats.heat_gen <= stats.cooling, "%.0f made, %.0f cooled kW" % [stats.heat_gen, stats.cooling]))
	rows.append(_row("T/W loaded %.2f" % c.min_twr, stats.twr_loaded >= c.min_twr, "you have %.2f" % stats.twr_loaded))
	var aboard := manifest.total_of(c.commodity)
	rows.append(_row("Cargo aboard", aboard > 0.0, "%.1f of %.0f t offered" % [aboard, c.offer]))
	return rows


static func ready(rows: Array[Dictionary]) -> bool:
	for r in rows:
		if not r.ok:
			return false
	return true


static func _row(label: String, ok: bool, detail: String) -> Dictionary:
	return {"label": label, "ok": ok, "detail": detail}
