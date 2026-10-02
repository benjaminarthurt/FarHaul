class_name Worlds
extends RefCounted
## Lightweight access to world data used by menus and session state.
## Canonical yards live in data/world/yards.json; this class keeps menu code independent of JSON parsing.

const YARDS_PATH := "res://data/world/yards.json"

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


static func _find(list: Array, id: String) -> Dictionary:
	for e in list:
		if e.id == id:
			return e
	return list[0]


static func race(id: String) -> Dictionary:
	return _find(RACES, id)


static func difficulty(id: String) -> Dictionary:
	return _find(DIFFICULTIES, id if id != "" else "normal")
