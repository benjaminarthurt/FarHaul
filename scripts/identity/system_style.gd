class_name SystemStyle
extends RefCounted
## What a system's places look like, worked out from the world data rather than drawn one by one, so a
## new system gets its character for free. Three things set it:
##
## - **architecture**, from the home species (or "colonial" for human-founded colonies, "patchwork"
##   for the multispecies hubs): colours, how heavy or light the structure is, ceiling height, lamps;
## - **tier**, from the system's classification (core, developed, outer, frontier, extreme frontier):
##   how big and how finished the port is, how many people are about, how worn it looks;
## - **role**, from the classification and the port type (industrial, agricultural, oceanic, research,
##   trade hub, transfer, frontier): the station's shape in space, the planet below, and the props.
##
## `for_system(id)` returns a plain dictionary (cached); the builders read it. See docs/runtime/identity.md.

const ARCH := {
	"colonial": {"wall": Color(0.42, 0.45, 0.5), "floor": Color(0.2, 0.21, 0.23), "trim": Color(0.95, 0.75, 0.2),
			"lamp": Color(1.0, 0.94, 0.85), "height": 1.0, "column": 0.35, "accent": Color(0.95, 0.65, 0.2),
			"station": Color(0.5, 0.52, 0.56), "desc": "modular plating, yellow trim"},
	"human": {"wall": Color(0.46, 0.48, 0.52), "floor": Color(0.22, 0.23, 0.25), "trim": Color(0.3, 0.6, 0.95),
			"lamp": Color(0.95, 0.97, 1.0), "height": 1.1, "column": 0.35, "accent": Color(0.3, 0.6, 0.95),
			"station": Color(0.6, 0.62, 0.66), "desc": "clean corporate panels, blue trim"},
	"kesh": {"wall": Color(0.3, 0.29, 0.28), "floor": Color(0.16, 0.15, 0.14), "trim": Color(0.9, 0.4, 0.1),
			"lamp": Color(1.0, 0.82, 0.6), "height": 0.86, "column": 0.9, "accent": Color(0.9, 0.4, 0.1),
			"station": Color(0.36, 0.34, 0.32), "desc": "massive dark steel, heavy columns, orange warning bands"},
	"ilyan": {"wall": Color(0.82, 0.84, 0.86), "floor": Color(0.55, 0.58, 0.6), "trim": Color(0.3, 0.9, 0.85),
			"lamp": Color(0.85, 0.97, 1.0), "height": 1.5, "column": 0.18, "accent": Color(0.3, 0.9, 0.85),
			"station": Color(0.85, 0.87, 0.9), "desc": "pale, tall and slender, teal light"},
	"vey": {"wall": Color(0.28, 0.45, 0.48), "floor": Color(0.14, 0.24, 0.27), "trim": Color(0.4, 0.95, 0.7),
			"lamp": Color(0.7, 0.95, 0.9), "height": 1.15, "column": 0.5, "accent": Color(0.4, 0.95, 0.7),
			"station": Color(0.3, 0.5, 0.52), "desc": "sea greens, water channels, humid haze"},
	"orun": {"wall": Color(0.5, 0.36, 0.26), "floor": Color(0.24, 0.17, 0.12), "trim": Color(1.0, 0.6, 0.25),
			"lamp": Color(1.0, 0.78, 0.5), "height": 0.8, "column": 0.6, "accent": Color(1.0, 0.6, 0.25),
			"station": Color(0.52, 0.4, 0.3), "desc": "warm stone, low arches, amber lamps"},
	"patchwork": {"wall": Color(0.38, 0.4, 0.44), "floor": Color(0.19, 0.2, 0.22), "trim": Color(0.9, 0.3, 0.6),
			"lamp": Color(1.0, 0.9, 0.85), "height": 1.0, "column": 0.4, "accent": Color(0.9, 0.3, 0.6),
			"station": Color(0.48, 0.47, 0.5), "desc": "every species' fittings side by side, signs everywhere"},
}

## Size and finish by tier: room width and depth (m), people walking, wear (0 polished, 1 battered).
const TIER := {
	"core": {"width": 56.0, "depth": 16.0, "walkers": 6, "wear": 0.0, "planters": true, "banners": true},
	"developed": {"width": 44.0, "depth": 14.0, "walkers": 3, "wear": 0.2, "planters": true, "banners": false},
	"outer": {"width": 36.0, "depth": 12.0, "walkers": 2, "wear": 0.45, "planters": false, "banners": false},
	"frontier": {"width": 30.0, "depth": 11.0, "walkers": 1, "wear": 0.7, "planters": false, "banners": false},
	"extreme_frontier": {"width": 26.0, "depth": 10.0, "walkers": 1, "wear": 0.9, "planters": false, "banners": false},
}

## The planet below by role (and the home worlds by name): its colour.
const PLANET := {
	"oceanic": Color(0.15, 0.32, 0.6), "agricultural": Color(0.35, 0.5, 0.28), "industrial": Color(0.42, 0.4, 0.38),
	"extraction": Color(0.45, 0.36, 0.3), "research": Color(0.55, 0.6, 0.68), "resource": Color(0.6, 0.62, 0.66),
	"boom_colony": Color(0.6, 0.45, 0.3), "transit": Color(0.35, 0.33, 0.4), "multispecies_hub": Color(0.38, 0.45, 0.55),
	"multispecies": Color(0.3, 0.3, 0.34),
	"sol": Color(0.22, 0.42, 0.62), "keshar": Color(0.55, 0.4, 0.25), "ilos": Color(0.7, 0.7, 0.62),
	"veyara": Color(0.1, 0.28, 0.5), "orun": Color(0.35, 0.28, 0.24),
}

## Human colonies are built from the same kit, so what tells them apart is the company livery of the
## work they do: wall and floor tint, trim and accent, lamp colour. Applied to colonial systems only.
const LIVERY := {
	"industrial": {"wall": Color(0.44, 0.45, 0.46), "trim": Color(0.98, 0.8, 0.1), "accent": Color(0.98, 0.8, 0.1),
			"lamp": Color(1.0, 0.93, 0.8)},
	"agricultural": {"wall": Color(0.56, 0.53, 0.45), "floor": Color(0.26, 0.24, 0.2), "trim": Color(0.45, 0.8, 0.3),
			"accent": Color(0.45, 0.8, 0.3), "lamp": Color(1.0, 0.92, 0.75)},
	"extraction": {"wall": Color(0.4, 0.36, 0.33), "floor": Color(0.2, 0.18, 0.16), "trim": Color(0.85, 0.45, 0.2),
			"accent": Color(0.85, 0.45, 0.2), "lamp": Color(1.0, 0.85, 0.65)},
	"research": {"wall": Color(0.7, 0.72, 0.75), "floor": Color(0.32, 0.34, 0.37), "trim": Color(0.35, 0.85, 1.0),
			"accent": Color(0.35, 0.85, 1.0), "lamp": Color(0.92, 0.97, 1.0)},
	"oceanic": {"wall": Color(0.4, 0.47, 0.52), "floor": Color(0.18, 0.22, 0.25), "trim": Color(0.25, 0.75, 0.85),
			"accent": Color(0.25, 0.75, 0.85), "lamp": Color(0.88, 0.96, 1.0)},
	"resource": {"wall": Color(0.48, 0.52, 0.56), "floor": Color(0.2, 0.22, 0.25), "trim": Color(0.6, 0.85, 1.0),
			"accent": Color(0.6, 0.85, 1.0), "lamp": Color(0.9, 0.95, 1.0)},
	"boom_colony": {"wall": Color(0.5, 0.42, 0.34), "floor": Color(0.22, 0.19, 0.16), "trim": Color(1.0, 0.55, 0.15),
			"accent": Color(1.0, 0.55, 0.15), "lamp": Color(1.0, 0.85, 0.6)},
	"transit": {"wall": Color(0.42, 0.42, 0.46), "floor": Color(0.2, 0.2, 0.22), "trim": Color(0.9, 0.25, 0.25),
			"accent": Color(0.9, 0.25, 0.25), "lamp": Color(1.0, 0.92, 0.85)},
}

static var _cache := {}


static func _tier(classes: Array) -> String:
	for t in ["extreme_frontier", "frontier", "outer", "core", "developed"]:
		if t in classes:
			return t
	return "developed"


static func _role(classes: Array) -> String:
	if "home_system" in classes:
		return "capital"
	for c in classes:
		if c in PLANET and not c in ["core", "home_system"]:
			return String(c)
	return "industrial"


## The style for a system: {architecture, tier, role, species, ...the ARCH and TIER entries..., planet,
## port_type, bar_name, landmark}.
static func for_system(system_id: String) -> Dictionary:
	if _cache.has(system_id):
		return _cache[system_id]
	var sys := Worlds.system(system_id)
	var classes: Array = sys.get("classification", [])
	var home: Array = sys.get("home_species_ids", [])
	var arch := "colonial"
	if not home.is_empty():
		arch = String(home[0])
	elif "multispecies_hub" in classes or "multispecies" in classes:
		arch = "patchwork"
	var tier := _tier(classes)
	var role := _role(classes)
	var out := {"system_id": system_id, "architecture": arch, "tier": tier, "role": role,
			"species": arch if arch in ["human", "kesh", "ilyan", "vey", "orun"] else "",
			"crowd": _crowd(arch)}
	out.merge(ARCH[arch])
	if arch == "colonial" and LIVERY.has(role):
		out.merge(LIVERY[role], true)
	out.merge(TIER[tier])
	out["planet"] = PLANET.get(system_id, PLANET.get(role, Color(0.4, 0.42, 0.45)))
	var port := Worlds.primary_port(system_id)
	out["port_type"] = String(port.get("type", "orbital_port"))
	out["services"] = port.get("services", [])
	out["traffic"] = String(port.get("traffic", "medium"))
	var landmark := _landmark(port)
	out["landmark"] = landmark
	out["bar_name"] = String(landmark.get("name", "Bar and bunks")) if String(landmark.get("type", "")).contains("bar") \
			or String(landmark.get("type", "")).contains("boarding") else "Bar and bunks"
	_cache[system_id] = out
	return out


## The style for a site in a system: the system's own for its main port; a step smaller and rougher for
## its fuel depot, belt works and moon station, which are working sites rather than the front door.
static func for_site(port_id: String) -> Dictionary:
	var n := LocalSpace.node(port_id)
	var sys := String(n.get("system_id", "")) if not n.is_empty() else String(Worlds.port(port_id).get("system_id", Session.system_id()))
	var st := for_system(sys).duplicate()
	var kind := String(n.get("kind", "port")) if not n.is_empty() else "port"
	st["site_kind"] = kind
	if kind in ["depot", "belt", "moon"]:
		var order := ["core", "developed", "outer", "frontier", "extreme_frontier"]
		var t: String = order[mini(order.find(String(st.tier)) + 1, order.size() - 1)]
		st.merge(TIER[t], true)
		st["tier"] = t
		st["bar_name"] = "Bar and bunks"
		st["landmark"] = {}   # the system's landmark is at its main port, not out here
		st["port_type"] = {"depot": "fuel_depot", "belt": "belt_works", "moon": "moon_station"}[kind]
	return st


## Who you see walking about: mostly the home species, with visitors (everyone at a hub).
static func _crowd(arch: String) -> Array:
	match arch:
		"human", "colonial":
			return ["human", "human", "human", "kesh", "ilyan"]
		"kesh":
			return ["kesh", "kesh", "kesh", "human", "orun"]
		"ilyan":
			return ["ilyan", "ilyan", "ilyan", "human", "vey"]
		"vey":
			return ["vey", "vey", "vey", "human", "ilyan"]
		"orun":
			return ["orun", "orun", "orun", "kesh", "human"]
	return ["human", "kesh", "ilyan", "vey", "orun"]


## A named place from local_color.json at this port's world, if there is one.
static func _landmark(port: Dictionary) -> Dictionary:
	var dest := String(port.get("destination_id", ""))
	var f := FileAccess.open("res://data/world/local_color.json", FileAccess.READ)
	if f == null:
		return {}
	var d: Variant = JSON.parse_string(f.get_as_text())
	if typeof(d) != TYPE_DICTIONARY:
		return {}
	for lc in d.get("local_color", []):
		var loc := String(lc.get("location_id", ""))
		if loc == dest or String(port.get("id", "")).begins_with(loc):
			return lc
	return {}
