class_name Worlds
extends RefCounted
## New-game choices, read from the world data in data/world/ (species, systems, routes, corridors).
## The JSON files are the source of truth. Only the yard names below and the difficulty
## table live in code, because the world data does not describe shipyards or difficulty yet.
##
## Species affect biology, ergonomics and heritage, not career bonuses, so choosing one gives no
## gameplay advantage yet.

const DATA_DIR := "res://data/world/"

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

const DIFFICULTIES := [
	{"id": "easy", "name": "Easy", "funds": 220000, "blurb": "Start with 220,000 credits."},
	{"id": "normal", "name": "Normal", "funds": 150000, "blurb": "Start with 150,000 credits."},
	{"id": "hard", "name": "Hard", "funds": 110000, "blurb": "Start with 110,000 credits. The starter ship leaves you very little."},
]

static var _cache := {}


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
	var yard: Dictionary = YARDS.get(id, {"name": "%s Yard" % sys.name, "type": "Shipyard", "at": sys.name})
	var eco: Dictionary = sys.get("economy", {})
	var nar: Dictionary = sys.get("narrative", {})
	return {
		"id": id,
		"name": sys.name,
		"yard_name": yard.name,
		"yard_type": yard.type,
		"yard_at": yard.at,
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
