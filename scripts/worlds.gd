class_name Worlds
extends RefCounted
## Lightweight access to world data used by menus and session state.
## Canonical yards live in data/world/yards.json; this class keeps menu code independent of JSON parsing.

const YARDS_PATH := "res://data/world/yards.json"
const COORDINATES_PATH := "res://data/world/coordinates.json"
const MARKETS_PATH := "res://data/world/markets.json"
const COMMODITIES_PATH := "res://data/world/commodities.json"

const RACES := [
	{"id": "human", "name": "Human", "blurb": "Adaptable, commercially diverse and comfortable with mixed engineering standards."},
	{"id": "kesh", "name": "Kesh", "blurb": "High-gravity natives with a tradition of heavy, conservative and exceptionally durable engineering."},
	{"id": "ilyan", "name": "Ilyan", "blurb": "Low-gravity natives known for mass-efficient structures, precision engineering and propulsion."},
	{"id": "vey", "name": "Vey", "blurb": "Semi-aquatic people renowned for life support, water systems and environmental engineering."},
	{"id": "orun", "name": "Orun", "blurb": "Communal subterranean engineers specializing in compact systems, thermal control and automation."},
]

const DIFFICULTIES := [
	{"id": "easy", "name": "Easy", "funds": 220000, "blurb": "Start with 220,000 credits."},
	{"id": "normal", "name": "Normal", "funds": 150000, "blurb": "Start with 150,000 credits."},
	{"id": "hard", "name": "Hard", "funds": 110000, "blurb": "Start with 110,000 credits. The starter ship leaves you very little."},
]

static var _yards: Array = []
static var _yard_tiers: Dictionary = {}
static var _coordinates: Dictionary = {}
static var _markets: Dictionary = {}
static var _commodities: Dictionary = {}


static func _load_yards() -> void:
	if not _yards.is_empty():
		return
	if not FileAccess.file_exists(YARDS_PATH):
		push_error("Missing world data: %s" % YARDS_PATH)
		return
	var file := FileAccess.open(YARDS_PATH, FileAccess.READ)
	var parsed = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("Invalid yards JSON: %s" % YARDS_PATH)
		return
	_yards = parsed.get("yards", [])
	_yard_tiers = parsed.get("yard_tiers", {})


static func yards() -> Array:
	_load_yards()
	return _yards


static func starting_yards() -> Array:
	_load_yards()
	var result: Array = []
	for y in _yards:
		if bool(y.get("starting_option", false)):
			result.append(y)
	return result if not result.is_empty() else _yards


static func yard(id: String) -> Dictionary:
	_load_yards()
	for y in _yards:
		if y.id == id:
			return y
	return _yards[0] if not _yards.is_empty() else {}


static func yard_tier(id: String) -> Dictionary:
	_load_yards()
	return _yard_tiers.get(id, {"name": id})


static func _load_indexed(path: String, array_key: String, cache: Dictionary) -> void:
	if not cache.is_empty():
		return
	if not FileAccess.file_exists(path):
		push_error("Missing world data: %s" % path)
		return
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("Invalid world JSON: %s" % path)
		return
	for record in parsed.get(array_key, []):
		cache[String(record.id)] = record


static func coordinate(system_id: String) -> Dictionary:
	_load_indexed(COORDINATES_PATH, "systems", _coordinates)
	return _coordinates.get(system_id, {})


static func distance_ly(a: String, b: String) -> float:
	var ca := coordinate(a)
	var cb := coordinate(b)
	if ca.is_empty() or cb.is_empty():
		return -1.0
	var dx := float(ca.x) - float(cb.x)
	var dy := float(ca.y) - float(cb.y)
	var dz := float(ca.z) - float(cb.z)
	return sqrt(dx * dx + dy * dy + dz * dz)


static func market(system_id: String) -> Dictionary:
	_load_indexed(MARKETS_PATH, "markets", _markets)
	for m in _markets.values():
		if String(m.system_id) == system_id:
			return m
	return {}


static func commodity(id: String) -> Dictionary:
	_load_indexed(COMMODITIES_PATH, "commodities", _commodities)
	return _commodities.get(id, {})


static func yard_system(yard_id: String) -> String:
	return String(yard(yard_id).get("system_id", ""))


static func _find(list: Array, id: String) -> Dictionary:
	for e in list:
		if e.id == id:
			return e
	return list[0]


static func race(id: String) -> Dictionary:
	return _find(RACES, id)


static func difficulty(id: String) -> Dictionary:
	return _find(DIFFICULTIES, id if id != "" else "normal")
