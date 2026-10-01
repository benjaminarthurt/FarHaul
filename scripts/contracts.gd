class_name Contracts
extends RefCounted
## Freight jobs for the shipyard loop. A contract offers some tonnes of one commodity at a rate per
## tonne. If the ship can't carry it all, it takes what fits and the rest is left behind.
## Running a contract is simulated until flight exists: `check` says whether the ship is fit to go.
## Placeholder numbers, tune freely.

const LIST := [
	{"title": "Water for Kestrel Station", "commodity": &"water", "offer": 20.0, "rate": 450.0, "min_twr": 0.05,
		"blurb": "A cistern ran dry. Anything with an engine will do."},
	{"title": "Ore to the Smelters", "commodity": &"ore", "offer": 60.0, "rate": 380.0, "min_twr": 0.08,
		"blurb": "More ore than a small ship can lift. Take what you can."},
	{"title": "Food for Marrow Camp", "commodity": &"food", "offer": 30.0, "rate": 900.0, "min_twr": 0.15,
		"blurb": "People are waiting. Needs a decent burn."},
	{"title": "Machinery for the Frontier", "commodity": &"machinery", "offer": 80.0, "rate": 650.0, "min_twr": 0.10,
		"blurb": "Heavy and valuable. Bring a big hold."},
	{"title": "Rush Electronics", "commodity": &"electronics", "offer": 25.0, "rate": 1800.0, "min_twr": 0.25,
		"blurb": "Pays well, but only a fast ship gets there in time."},
]


static func get_contract(index: int) -> Dictionary:
	return LIST[clampi(index, 0, LIST.size() - 1)]


## Tonnes this contract would actually pay for with the current load.
static func payable_tonnes(manifest: CargoManifest, c: Dictionary) -> float:
	return minf(manifest.total_of(c.commodity), c.offer)


static func pay(manifest: CargoManifest, c: Dictionary) -> int:
	return roundi(payable_tonnes(manifest, c) * c.rate)


## The most this contract could pay this ship: as much as the ship has room for.
static func best_pay(manifest: CargoManifest, c: Dictionary) -> int:
	return roundi(minf(manifest.capacity(), c.offer) * c.rate)


## Requirements as [{label, ok, detail}] in the order they should be shown.
static func check(stats: Dictionary, manifest: CargoManifest, c: Dictionary) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	rows.append(_row("Cockpit", stats.has_helm, "" if stats.has_helm else "nothing to fly it from"))
	rows.append(_row("Engines", stats.thrust_fwd > 0.0, "" if stats.thrust_fwd > 0.0 else "no thrust"))
	rows.append(_row("Hull sealed", stats.open_doors == 0, "%d open doorways" % stats.open_doors))
	rows.append(_row("Airlock", stats.airlocks > 0, "" if stats.airlocks > 0 else "none fitted"))
	rows.append(_row("Power", stats.power_use <= stats.power_gen,
		"%.0f of %.0f kW" % [stats.power_use, stats.power_gen]))
	rows.append(_row("Cooling", stats.heat_gen <= stats.cooling,
		"%.0f made, %.0f cooled kW" % [stats.heat_gen, stats.cooling]))
	rows.append(_row("T/W loaded %.2f" % c.min_twr, stats.twr_loaded >= c.min_twr,
		"you have %.2f" % stats.twr_loaded))
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
