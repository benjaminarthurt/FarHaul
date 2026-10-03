class_name Worlds
extends RefCounted
## Lightweight access to world data used by menus and session state.
## JSON files are the source of truth for world data, while the small YARDS fallback and difficulty
## table stay in code for older saves and menu generation.

const DATA_DIR := "res://data/world/"
const YARDS_PATH := "res://data/world/yards.json"
const COORDINATES_PATH := "res://data/world/coordinates.json"
const MARKETS_PATH := "res://data/world/markets.json"
const COMMODITIES_PATH := "res://data/world/commodities.json"
const PORTS_PATH := "res://data/world/ports.json"

## A player can begin at their own species' home system, or at one of these shared places.
const SHARED_STARTS := ["concord", "new_houston", "port_meridian"]

## Placeholder shipyards for the systems a player can begin at. `at` says where in the system.
const YARDS := {
	"sol": {"name": "Earth Orbital Yards", "type": "Orbital yards", "at": "Earth orbit"},
	"keshar": {"name": "Prime Heavy Yards", "type": "Orbital yards", "at": "Keshar Prime orbit"},
	"ilos": {"name": "Ilos High Docks", "type": "Orbital docks", "at": "Ilos Prime orbit"},
	"veyara": {"name": "Veyara Floating Yards", "type": "Floating port yards", "at": "the oceans of Veyara Prime"},
	"orun": {"name": "Orun Deep Yards", "type": "Underground yards", "at": "below the surface of Orun Prime"},
	"concord": {"name": "Concord Open Docks", "type": "Orbital docks", "at": "Concord Prime orbit"},
	"new_houston": {"name": "Roosevelt Orbital Yards", "type": "Orbital yards", "at": "Roosevelt orbit"},
	"port_meridian": {"name": "Meridian Yards", "type": "Orbital settlement yards", "at": "Meridian Station"},
}

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

static var _cache := {}
static var _yards: Array = []
static var _yard_tiers: Dictionary = {}
static var _coordinates: Dictionary = {}
static var _markets: Dictionary = {}
static var _commodities: Dictionary = {}
static var _ports: Dictionary = {}


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
	# Older saves and tests name a system instead of a yard: use that system's starting yard.
	for y in _yards:
		if String(y.get("system_id", "")) == id and bool(y.get("starting_option", false)):
			return y
	for y in _yards:
		if String(y.get("system_id", "")) == id:
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


static func port(id: String) -> Dictionary:
	_load_indexed(PORTS_PATH, "ports", _ports)
	return _ports.get(id, {})


static func ports_in_system(system_id: String) -> Array:
	_load_indexed(PORTS_PATH, "ports", _ports)
	var out: Array = []
	for p in _ports.values():
		if String(p.system_id) == system_id:
			out.append(p)
	return out


static func primary_port(system_id: String) -> Dictionary:
	var found := ports_in_system(system_id)
	return found[0] if not found.is_empty() else {}


static func yard_system(yard_id: String) -> String:
	return String(yard(yard_id).get("system_id", ""))


static func _load(file: String) -> Dictionary:
	if not _cache.has(file):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(DATA_DIR + file))
		_cache[file] = parsed if typeof(parsed) == TYPE_DICTIONARY else {}
	return _cache[file]


static func _by_id(list: Array, id: String) -> Dictionary:
	for e in list:
		if e.get("id", "") == id:
			return e
	return {}


# --- Species -----------------------------------------------------------------------------------

static func species_list() -> Array:
	var out := []
	for s in _load("species.json").get("species", []):
		if s.get("playable", false):
			out.append(species(s.id))
	return out


## One species for display. Unknown ids (older saves) fall back to the first playable species.
static func species(id: String) -> Dictionary:
	var raw := _by_id(_load("species.json").get("species", []), id)
	if raw.is_empty():
		raw = _load("species.json").get("species", [{}])[0]
	var home := system(raw.get("home_system_id", ""))
	var bio: Dictionary = raw.get("biology", {})
	var civ: Dictionary = raw.get("civilization", {})
	var g: Variant = bio.get("native_gravity_g", null)
	return {
		"id": raw.get("id", ""),
		"name": raw.get("name", "Human"),
		"home_system_id": raw.get("home_system_id", ""),
		"home_system": home.get("name", ""),
		"homeworld": _homeworld_name(home, raw.get("homeworld_id", "")),
		"gravity": ("%s g" % str(g)) if g != null else "",
		"environment": bio.get("environment", ""),
		"identity": civ.get("identity", ""),
		"engineering": civ.get("engineering_style", ""),
		"strengths": civ.get("trade_strengths", []),
	}


static func _homeworld_name(sys: Dictionary, dest_id: String) -> String:
	for d in sys.get("destinations", []):
		if d.id == dest_id:
			return d.name
	return sys.get("name", "")


# --- Systems and starting places -----------------------------------------------------------------

static func system(id: String) -> Dictionary:
	return _by_id(_load("systems.json").get("systems", []), id)


## The places a player of this species can begin: their home system first, then the shared starts.
static func start_ids(species_id: String) -> Array:
	var out := [species(species_id).home_system_id]
	for s in SHARED_STARTS:
		if not out.has(s):
			out.append(s)
	return out


## Everything the UI wants to say about a system, with its yard. Unknown ids (older saves)
## fall back to Concord, the multispecies hub.
static func world(id: String) -> Dictionary:
	var sys := system(id)
	if sys.is_empty():
		sys = system("concord")
		id = "concord"
	var fallback: Dictionary = {"name": "%s Yard" % sys.name, "type": "Shipyard", "at": sys.name}
	var yd: Dictionary = YARDS.get(id, fallback).duplicate()
	# yards.json names the yard at this system when it has one; type and place come from the table.
	for y in yards():
		if String(y.get("system_id", "")) == id and bool(y.get("starting_option", false)):
			yd["name"] = y.get("name", yd.name)
			break
	var eco: Dictionary = sys.get("economy", {})
	var nar: Dictionary = sys.get("narrative", {})
	return {
		"id": id,
		"name": sys.name,
		"yard_name": yd.name,
		"yard_type": yd.type,
		"yard_at": yd.at,
		"blurb": nar.get("gameplay_identity", ""),
		"summary": nar.get("summary", ""),
		"population": population_text(int(sys.get("population", 0))),
		"exports": eco.get("exports", []),
		"imports": eco.get("imports", []),
		"corridors": corridor_names(id),
		"neighbours": neighbour_names(id),
	}


static func population_text(n: int) -> String:
	if n >= 1000000000:
		return _trim("%.1f" % (n / 1.0e9)) + " billion"
	if n >= 1000000:
		return _trim("%.1f" % (n / 1.0e6)) + " million"
	if n >= 1000:
		return "%d thousand" % int(n / 1000.0)
	return str(n)


static func race(id: String) -> Dictionary:
	return _by_id(RACES, id)


static func _trim(t: String) -> String:
	return t.trim_suffix(".0")


static func corridor_names(system_id: String) -> Array:
	var out := []
	for c in _load("corridors.json").get("corridors", []):
		if c.system_ids.has(system_id):
			out.append(c.name)
	return out


## Systems joined to this one by a direct route.
static func neighbour_names(system_id: String) -> Array:
	var out := []
	for r in _load("routes.json").get("routes", []):
		var other := ""
		if r.a == system_id:
			other = r.b
		elif r.b == system_id:
			other = r.a
		if other != "":
			out.append(system(other).get("name", other))
	return out


# --- Difficulty ----------------------------------------------------------------------------------

static func difficulty(id: String) -> Dictionary:
	for d in DIFFICULTIES:
		if d.id == id:
			return d
	return DIFFICULTIES[1]
