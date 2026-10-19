class_name LocalSpace
extends RefCounted
## Freight inside one star system, flown on sublight engines alone. Every system has its main port
## and three more sites (fuel depot, moon base, belt works), plus the moon's pad and camp; Sol adds
## stations at Venus, Jupiter and Saturn, which are long hops that need big tanks. A hop costs delta-v and hours; the fuel
## burned comes from the rocket equation, so a heavy load or a long hop can be more than the tank
## holds. This is the only work a ship without an FTL drive can take. See data/runtime/local_space.json.

const PATH := "res://data/runtime/local_space.json"
const G0 := 9.81
const SEP := "__"
const KINDS := ["port", "depot", "moon", "belt", "pad", "camp"]   ## every system has these
const EXTRA := ["venus", "jovian", "saturn"]   ## only where a system lists them (Sol's planets): local_space.json "extra_sites"
const SURFACE := ["pad", "camp", "world", "field", "mars"]   ## on a surface: reached by landing, left by lifting off
const MOON_SURFACE := ["pad", "camp"]   ## on the moon's surface (the rest are on planets: Planets.KINDS)
const OUT_SITES := ["depot", "belt", "moon", "venus", "jovian", "saturn"]   ## working stations, not the front door

static var _cfg: Dictionary = {}
static var pay_override := -1.0   ## solver hook: replaces the level multiplier when >= 0


static func config() -> Dictionary:
	if _cfg.is_empty():
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		_cfg = parsed if typeof(parsed) == TYPE_DICTIONARY else {}
	return _cfg


## The sites of a system. The first is the real main port, so its id works everywhere port ids do.
static func nodes(system_id: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var main := Worlds.primary_port(system_id)
	var sys_name := String(Worlds.system(system_id).get("name", system_id.replace("_", " ").capitalize()))
	out.append({"id": String(main.get("id", system_id + SEP + "port")), "kind": "port", "system_id": system_id,
			"name": String(main.get("name", sys_name + " Port")), "type": String(main.get("type", "port"))})
	var kinds: Array = ["depot", "moon", "belt", "pad", "camp"]
	kinds.append_array(config().get("extra_sites", {}).get(system_id, []))
	for kind in kinds:
		out.append({"id": system_id + SEP + kind, "kind": kind, "system_id": system_id, "surface": kind in SURFACE,
				"name": "%s %s" % [sys_name, String(config()["kinds"][kind]["name"])], "type": kind})
	for kind in Planets.site_kinds(system_id):   # the downport on the main world, its landing field, Mars
		out.append({"id": system_id + SEP + kind, "kind": kind, "system_id": system_id, "surface": true, "planet": true,
				"name": Planets.site_name(system_id, kind), "type": kind})
	return out


static func is_surface(id: String) -> bool:
	return String(node(id).get("kind", "")) in SURFACE


## A site on a planet with air (a downport, its landing field, Mars), not the moon.
static func is_planet(id: String) -> bool:
	return Planets.is_planet_kind(String(node(id).get("kind", "")))


## The body a surface site kind is on: the planet for a downport or field, else the system's moon.
static func body_at(system_id: String, kind: String) -> Dictionary:
	if Planets.is_planet_kind(kind):
		return Planets.body(system_id, kind)
	return body(system_id)


## The body the system's moon base sits on (landing.json "bodies"), picked from the system id so it
## never changes: gravity, colours and a name.
static func body(system_id: String) -> Dictionary:
	var land := SurfaceTerrain.config()
	var kinds: Array = land.get("body_order", ["moon"])
	var key := String(kinds[absi(hash(system_id)) % kinds.size()])
	var real: Dictionary = SkyWorlds.moon_body(system_id)   # a moon people know (Sol's is Luna)
	if not real.is_empty():
		key = String(real.body)
	var b: Dictionary = land.get("bodies", {}).get(key, {}).duplicate()
	b["id"] = key
	if not real.is_empty():
		b["name"] = String(real.name)
	return b


## Whether a ship (stats: lift, wet) carrying `cargo_t` can land in this system: its lift jets must beat
## the body's gravity by the margin landing.json asks for. `kind` picks the surface (the moon's pad by
## default; a planet's downport or field needs much more).
static func can_land(stats: Dictionary, system_id: String, cargo_t: float = 0.0, kind := "pad") -> bool:
	var g := float(body_at(system_id, kind).get("gravity_m_s2", 1.62))
	var margin := float(SurfaceTerrain.config().get("min_lift_margin", 1.15))
	return float(stats.get("lift", 0.0)) / maxf(float(stats.get("wet", 1.0)) + cargo_t, 0.001) >= g * margin


## The most cargo the lift jets can set down on that surface (tonnes).
static func max_landing_cargo_t(stats: Dictionary, system_id: String, kind := "pad") -> float:
	var g := float(body_at(system_id, kind).get("gravity_m_s2", 1.62))
	var margin := float(SurfaceTerrain.config().get("min_lift_margin", 1.15))
	return float(stats.get("lift", 0.0)) / (g * margin) - float(stats.get("wet", 0.0))


## A site by id: a real port, or one of the synthetic sites. {} when the id is neither.
static func node(id: String) -> Dictionary:
	if SEP in id:
		var system_id := id.get_slice(SEP, 0)
		if Worlds.system(system_id).is_empty():
			return {}
		for n in nodes(system_id):
			if String(n["id"]) == id:
				return n
		return {}
	var p := Worlds.port(id)
	if p.is_empty():
		return {}
	for n in nodes(String(p.get("system_id", ""))):
		if String(n["id"]) == id:
			return n
	return {}


## The delta-v and hours from one kind of site to another. Moon and station hops are the same both ways;
## to and from a planet they aren't (Planets.hop), so `system_id` matters there.
static func hop(kind_a: String, kind_b: String, system_id := "") -> Dictionary:
	if kind_a == kind_b:
		return {}
	if Planets.is_planet_kind(kind_a) or Planets.is_planet_kind(kind_b):
		return Planets.hop(system_id, kind_a, kind_b)
	var order: Array = KINDS + EXTRA
	var a := order.find(kind_a)
	var b := order.find(kind_b)
	var key := "%s|%s" % [order[mini(a, b)], order[maxi(a, b)]]
	return config()["hops"].get(key, {})


static func exhaust_velocity() -> float:
	return float(config()["isp_s"]) * G0


## Propellant in tonnes for a burn of `dv_kms` by a ship of `mass_t` at the start.
static func burn_t(mass_t: float, dv_kms: float) -> float:
	return mass_t * (1.0 - exp(-dv_kms * 1000.0 / exhaust_velocity()))


## The most cargo (tonnes) the hop allows: the tank must cover the burn at the start mass.
## `wet_t` is dry plus full tanks without cargo. Negative when the hop is out of reach even empty.
static func max_cargo_t(wet_t: float, tank_t: float, dv_kms: float) -> float:
	var frac := 1.0 - exp(-dv_kms * 1000.0 / exhaust_velocity())
	return tank_t / frac - wet_t


## Jobs posted at `node_id` for the two-day window containing `day`. Deterministic, so the board is
## the same every time it is opened. `ship` carries wet, fuel (tank tonnes) and cargo_capacity.
## `taken` lists job ids already done in this window.
## `tag` and `window_days` give a separate, independently seeded set of runs (People uses "people", daily).
static func board(node_id: String, day: int, ship: Dictionary, level: Dictionary, taken: Array = [], tag := "local", window_days := 0, count := -1) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var here := node(node_id)
	if here.is_empty():
		return out
	var grown := Development.on(Session.sim)   # frontier growth: busier sites post more, empty ones nothing
	if grown and Development.abandoned(Session.sim, node_id):
		return out
	var b: Dictionary = config()["board"]
	var window := day / (window_days if window_days > 0 else int(b["refresh_days"]))
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("%s|%d" % [node_id, window]) if tag == "local" else hash("%s|%s|%d" % [tag, node_id, window])
	var goods := _goods()
	var others: Array[Dictionary] = []
	var sys := String(here["system_id"])
	for n in nodes(sys):
		if String(n["id"]) == node_id:
			continue
		if grown and Development.abandoned(Session.sim, String(n["id"])):
			continue   # nobody there to take it
		if not _lands_both(ship, sys, here, n, float(b["min_tonnes"]) * 0.5):
			continue   # surface work only shows to a ship that can land there (and lift off again)
		var reach := hop(String(here["kind"]), String(n["kind"]), sys)
		if reach.is_empty():
			continue
		# only post runs this ship's tank can lift a worthwhile load over
		if min(float(ship.get("cargo_capacity", 0.0)), max_cargo_t(float(ship["wet"]), float(ship["fuel"]), float(reach["dv_kms"]))) >= float(b["min_tonnes"]) * 0.5:
			others.append(n)
	if others.is_empty():
		return out
	var mult := float(level.get("local_pay_mult", 1.0)) if pay_override < 0.0 else pay_override
	var jobs := int(b["jobs_per_site"]) if count < 0 else count
	var weights := []   # a destination draws freight by its size against its canon size (all equal at canon)
	var total_w := 0.0
	if grown:
		jobs = maxi(1, roundi(float(jobs) * clampf(sqrt(_growth(node_id)), 0.4, 3.0)))
		for n in others:
			var wgt := _growth(String(n["id"]))
			weights.append(wgt)
			total_w += wgt
	for i in jobs:
		var dest: Dictionary = others[rng.randi() % others.size()] if not grown else _pick(others, weights, total_w, rng)
		var good: String = goods[rng.randi() % goods.size()]
		var fresh := false
		if Planets.is_planet_kind(String(here["kind"])) and String(here["kind"]) != "mars":
			fresh = rng.randf() < float(Planets.config().fresh.share_of_jobs)   # the farms send it up while it's fresh
			if fresh:
				good = String(Planets.config().fresh.commodity)
		var tonnes := snappedf(rng.randf_range(float(b["min_tonnes"]), float(b["max_tonnes"])), 0.5)
		var spread := 1.0 + rng.randf_range(-1.0, 1.0) * float(b["variance"])
		var id := "%s_%s_%d_%d" % [tag, node_id, window, i]
		if id in taken:
			continue
		var h := hop(String(here["kind"]), String(dest["kind"]), sys)
		var cap := minf(float(ship.get("cargo_capacity", 0.0)), max_cargo_t(float(ship["wet"]), float(ship["fuel"]), float(h["dv_kms"])))
		var surface := bool(dest.get("surface", false)) or bool(here.get("surface", false))
		var on_planet := Planets.is_planet_kind(String(dest["kind"])) or Planets.is_planet_kind(String(here["kind"]))
		if bool(dest.get("surface", false)):
			cap = minf(cap, max_landing_cargo_t(ship, sys, String(dest["kind"])))
		if bool(here.get("surface", false)):
			cap = minf(cap, max_landing_cargo_t(ship, sys, String(here["kind"])))
		if cap < float(b["min_tonnes"]) * 0.5:
			continue   # the tank (or the lift jets) cannot move a worthwhile load that far
		var info := Worlds.commodity(good)
		var value_factor := clampf(float(info.get("base_value", 500)) / 800.0, 0.85, 1.2)
		var rate := float(b["rate_cr_per_t_per_kms"]) * float(h.get("pay_dv_kms", h["dv_kms"])) * spread * value_factor * mult
		if on_planet:
			rate *= float(Planets.config().surface.get("surface_rate_mult", 1.6))
		elif surface:
			rate *= float(b.get("surface_rate_mult", 1.5))
		if fresh:
			rate *= float(Planets.config().fresh.rate_mult)
		out.append({
			"id": id,
			"local": true,
			"title": "%s to %s" % [info.get("name", good), dest["name"]],
			"commodity": StringName(good),
			"offer": minf(tonnes, snappedf(cap, 0.1)),
			"rate": roundi(rate),
			"origin_system_id": here["system_id"],
			"destination_system_id": here["system_id"],
			"origin_port_id": here["id"],
			"destination_port_id": dest["id"],
			"distance_ly": 0.0,
			"dv_kms": float(h["dv_kms"]),
			"hours": int(h["hours"]),
			"min_twr": 0.05,
			"deadline_days": float(b["deadline_days"]),
			"blurb": ("Fresh, and it won't stay that way: deliver within %d hours for full pay." % int(Planets.config().fresh.fresh_hours)) if fresh \
					else ("Planet run: needs lift for %.2f g, and a ship that doesn't mind heat." % _run_g(sys, here, dest)) if on_planet \
					else ("Surface run: needs lander legs." if surface else "Local run inside the system. Sublight, no drama."),
			"surface": surface,
			"planet": on_planet,
			"fresh": fresh,
		})
	return out


## Whether a ship can set a worthwhile load down at each surface end of a run, and lift off from it.
static func _lands_both(ship: Dictionary, sys: String, a: Dictionary, b: Dictionary, min_t: float) -> bool:
	for n in [a, b]:
		if bool(n.get("surface", false)) and max_landing_cargo_t(ship, sys, String(n["kind"])) < min_t:
			return false
	return true


## The strongest gravity at either end of a run, in g.
static func _run_g(sys: String, a: Dictionary, b: Dictionary) -> float:
	var g := 0.0
	for n in [a, b]:
		if Planets.is_planet_kind(String(n["kind"])):
			g = maxf(g, float(Planets.planet(sys, String(n["kind"])).get("gravity_g", 1.0)))
	return g


## A site's size now against its canon size: 2 when it has grown a stage, 0.5 when it has shrunk one.
static func _growth(site_id: String) -> float:
	return Development.pull(Session.sim, site_id) / maxf(0.001, pow(2.0, Development.canon_score(site_id) - 2.0))


static func _pick(others: Array[Dictionary], weights: Array, total: float, rng: RandomNumberGenerator) -> Dictionary:
	var even := true
	for w in weights:
		even = even and absf(float(w) - float(weights[0])) < 1e-6
	if even:   # nothing has grown or shrunk: the board is exactly the one it always was
		return others[rng.randi() % others.size()]
	var r := rng.randf() * total
	for i in others.size():
		r -= float(weights[i])
		if r <= 0.0:
			return others[i]
	return others[others.size() - 1]


static var _goods_cache: Array[String] = []


static func _goods() -> Array[String]:
	if _goods_cache.is_empty():
		var ok: Array = config()["eligible_containers"]
		var lib := CommodityLibrary.new()
		var ids: Array = lib.order.duplicate()
		ids.sort()
		for id in ids:
			var r := lib.record(id)
			if String(r.get("container_type", "")) in ok and not ("oversized" in r.get("handling", [])) and not ("hazardous" in r.get("handling", [])) \
					and not ("perishable" in r.get("handling", [])):   # fresh food only leaves the planets (Planets.fresh)
				_goods_cache.append(String(id))
	return _goods_cache
