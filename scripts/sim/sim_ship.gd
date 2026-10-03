class_name SimShip
extends RefCounted
## Turns a ship from the builder into the physical numbers the economy simulation needs.
## All tuning lives in data/runtime/ship_economy.json; nothing about a particular ship is hard-coded.

const CONFIG_PATH := "res://data/runtime/ship_economy.json"


static var _populations := {}


static func config() -> Dictionary:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(CONFIG_PATH))
	return parsed if typeof(parsed) == TYPE_DICTIONARY else {}


## Crew a hold of `cargo_tonnes` needs: the minimum plus one more for each block of space.
static func crew_for(cargo_tonnes: float, cfg: Dictionary = {}) -> int:
	if cfg.is_empty():
		cfg = config()
	var crew_cfg: Dictionary = cfg["crew"]
	var scu := cargo_tonnes * 1000.0 / float(cfg["cargo"]["nominal_kg_per_scu"])
	return int(crew_cfg["minimum"]) + int(floor(scu / float(crew_cfg["scu_per_extra_crew"])))


## The roles aboard a crew of `n`, with each one's daily pay before the regional index: the captain (the
## owner, on a draw), then an engineer, then hands.
static func payroll(n: int, cfg: Dictionary = {}) -> Array[Dictionary]:
	if cfg.is_empty():
		cfg = config()
	var w: Dictionary = cfg.get("wages", {})
	var out: Array[Dictionary] = []
	if n <= 0:
		return out
	var roles: Dictionary = w.get("role_wage_cr_per_day", {})
	var flat := float(cfg["crew"]["wage_cr_per_day"])
	out.append({"role": "Captain (owner's draw)", "pay": float(w.get("owner_draw_cr_per_day", flat))})
	for i in range(1, n):
		var role := "engineer" if i == 1 else "hand"
		out.append({"role": role.capitalize(), "pay": float(roles.get(role, flat))})
	return out


## Pay level of a system's labour market against the reference port (1.0). Bigger, richer systems pay more.
static func wage_index(system_id: String, cfg: Dictionary = {}) -> float:
	if cfg.is_empty():
		cfg = config()
	var r: Dictionary = cfg.get("wages", {}).get("regional", {})
	if r.is_empty():
		return 1.0
	if _populations.is_empty():
		var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://data/world/systems.json"))
		if typeof(parsed) == TYPE_DICTIONARY:
			for sys in parsed.get("systems", []):
				_populations[String(sys["id"])] = float(sys.get("population", 0.0))
	var pop: float = float(_populations.get(system_id, 0.0))
	if pop <= 0.0:
		return 1.0
	var idx := 1.0 + float(r["per_decade"]) * (log(pop / float(r["reference_population"])) / log(10.0))
	return clampf(idx, float(r["min"]), float(r["max"]))


## `ship` is a ShipData. Returns a carrier-shaped dictionary (see EconomySim._add_carrier) plus a few
## display fields. `cfg` defaults to ship_economy.json.
static func profile(ship: ShipData, cfg: Dictionary = {}) -> Dictionary:
	if cfg.is_empty():
		cfg = config()
	var st := ShipStats.compute(ship)
	var crew_cfg: Dictionary = cfg["crew"]
	var own: Dictionary = cfg["ownership"]
	var spd: Dictionary = cfg["speed"]
	var scu := float(st["cargo_capacity"]) * 1000.0 / float(cfg["cargo"]["nominal_kg_per_scu"])
	var crew := crew_for(float(st["cargo_capacity"]), cfg)
	var annual := float(own["insurance_annual"]) + float(own["financed_share"]) * float(own["interest_annual"]) + float(own["depreciation_annual"])
	var fixed := float(st["cost"]) * annual / 365.0 + float(own["berth_and_misc_cr_per_day"])
	var twr := float(st["twr"])
	var ly_day := clampf(float(spd["reference_ly_per_day"]) * pow(maxf(twr, 0.0001) / float(spd["reference_twr"]), float(spd["exponent"])),
			float(spd["min_ly_per_day"]), float(spd["max_ly_per_day"]))
	ly_day = minf(ly_day * (1.0 + float(st.get("drive", 0.0))), float(spd.get("max_with_drive_ly_per_day", spd["max_ly_per_day"])))
	return {
		"capacity_scu": scu,
		"capacity_kg": float(st["cargo_capacity"]) * 1000.0,
		"dry_mass_t": float(st["wet"]),      # dry plus full tanks: what the drive pushes when empty
		"crew": crew,
		"wage_cr_per_day": _average_wage(crew, cfg),     # per crew member, before the regional index
		"fixed_cr_per_day": fixed,
		"ly_per_day": ly_day,
		"fuel_units": float(st["fuel"]) * float(cfg["fuel"]["units_per_tonne"]),
		"ship_cost": float(st["cost"]),
		"twr": twr,
		"berths": int(st.get("berths", 0)),
		"burn": 1.0 + float(st.get("drive", 0.0)) * float(spd.get("fuel_burn_per_drive_speed", 0.0)),
	}


const LEVELS_PATH := "res://data/runtime/economy_levels.json"


static func levels() -> Dictionary:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(LEVELS_PATH))
	return parsed if typeof(parsed) == TYPE_DICTIONARY else {}


## The economy level for a difficulty id (easy / normal / hard). Unknown ids get normal.
static func _average_wage(crew: int, cfg: Dictionary) -> float:
	var total := 0.0
	for r in payroll(crew, cfg):
		total += float(r["pay"])
	return total / maxf(1.0, float(crew))


static func level(id: String) -> Dictionary:
	var all := levels()
	var fallback := {}
	for L in all.get("levels", []):
		if L["id"] == id:
			return L
		if L["id"] == "normal":
			fallback = L
	return fallback
