class_name LocalSpace
extends RefCounted
## Freight inside one star system, flown on sublight engines alone. Every system has its main port
## and three more sites (fuel depot, moon base, belt works). A hop costs delta-v and hours; the fuel
## burned comes from the rocket equation, so a heavy load or a long hop can be more than the tank
## holds. This is the only work a ship without an FTL drive can take. See data/runtime/local_space.json.

const PATH := "res://data/runtime/local_space.json"
const G0 := 9.81
const SEP := "__"
const KINDS := ["port", "depot", "moon", "belt", "pad", "camp"]
const SURFACE := ["pad", "camp"]   ## on the moon's surface: reached by landing, left by lifting off

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
	for kind in ["depot", "moon", "belt", "pad", "camp"]:
		out.append({"id": system_id + SEP + kind, "kind": kind, "system_id": system_id, "surface": kind in SURFACE,
				"name": "%s %s" % [sys_name, String(config()["kinds"][kind]["name"])], "type": kind})
	return out


static func is_surface(id: String) -> bool:
	return String(node(id).get("kind", "")) in SURFACE


## The body the system's moon base sits on (landing.json "bodies"), picked from the system id so it
## never changes: gravity, colours and a name.
static func body(system_id: String) -> Dictionary:
	var land := SurfaceTerrain.config()
	var kinds: Array = land.get("body_order", ["moon"])
	var key := String(kinds[absi(hash(system_id)) % kinds.size()])
	var b: Dictionary = land.get("bodies", {}).get(key, {}).duplicate()
	b["id"] = key
	return b


## Whether a ship (stats: lift, wet) carrying `cargo_t` can land in this system: its lift jets must beat
## the body's gravity by the margin landing.json asks for.
static func can_land(stats: Dictionary, system_id: String, cargo_t: float = 0.0) -> bool:
	var g := float(body(system_id).get("gravity_m_s2", 1.62))
	var margin := float(SurfaceTerrain.config().get("min_lift_margin", 1.15))
	return float(stats.get("lift", 0.0)) / maxf(float(stats.get("wet", 1.0)) + cargo_t, 0.001) >= g * margin


## The most cargo the lift jets can set down in this system (tonnes).
static func max_landing_cargo_t(stats: Dictionary, system_id: String) -> float:
	var g := float(body(system_id).get("gravity_m_s2", 1.62))
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


static func hop(kind_a: String, kind_b: String) -> Dictionary:
	if kind_a == kind_b:
		return {}
	var a := KINDS.find(kind_a)
	var b := KINDS.find(kind_b)
	var key := "%s|%s" % [KINDS[mini(a, b)], KINDS[maxi(a, b)]]
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
static func board(node_id: String, day: int, ship: Dictionary, level: Dictionary, taken: Array = []) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var here := node(node_id)
	if here.is_empty():
		return out
	var b: Dictionary = config()["board"]
	var window := day / int(b["refresh_days"])
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("%s|%d" % [node_id, window])
	var goods := _goods()
	var others: Array[Dictionary] = []
	var sys := String(here["system_id"])
	var lander := max_landing_cargo_t(ship, sys) >= float(b["min_tonnes"]) * 0.5
	for n in nodes(sys):
		if String(n["id"]) == node_id:
			continue
		if (bool(n.get("surface", false)) or bool(here.get("surface", false))) and not lander:
			continue   # surface work only shows to a ship that can land
		var reach := hop(String(here["kind"]), String(n["kind"]))
		# only post runs this ship's tank can lift a worthwhile load over
		if min(float(ship.get("cargo_capacity", 0.0)), max_cargo_t(float(ship["wet"]), float(ship["fuel"]), float(reach["dv_kms"]))) >= float(b["min_tonnes"]) * 0.5:
			others.append(n)
	if others.is_empty():
		return out
	var mult := float(level.get("local_pay_mult", 1.0)) if pay_override < 0.0 else pay_override
	for i in int(b["jobs_per_site"]):
		var dest: Dictionary = others[rng.randi() % others.size()]
		var good: String = goods[rng.randi() % goods.size()]
		var tonnes := snappedf(rng.randf_range(float(b["min_tonnes"]), float(b["max_tonnes"])), 0.5)
		var spread := 1.0 + rng.randf_range(-1.0, 1.0) * float(b["variance"])
		var id := "local_%s_%d_%d" % [node_id, window, i]
		if id in taken:
			continue
		var h := hop(String(here["kind"]), String(dest["kind"]))
		var cap := minf(float(ship.get("cargo_capacity", 0.0)), max_cargo_t(float(ship["wet"]), float(ship["fuel"]), float(h["dv_kms"])))
		var surface := bool(dest.get("surface", false)) or bool(here.get("surface", false))
		if surface:
			cap = minf(cap, max_landing_cargo_t(ship, sys))
		if cap < float(b["min_tonnes"]) * 0.5:
			continue   # the tank (or the lift jets) cannot move a worthwhile load that far
		var info := Worlds.commodity(good)
		var value_factor := clampf(float(info.get("base_value", 500)) / 800.0, 0.85, 1.2)
		var rate := float(b["rate_cr_per_t_per_kms"]) * float(h["dv_kms"]) * spread * value_factor * mult
		if surface:
			rate *= float(b.get("surface_rate_mult", 1.5))
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
			"blurb": "Surface run: needs lander legs." if surface else "Local run inside the system, sublight.",
			"surface": surface,
		})
	return out


static var _goods_cache: Array[String] = []


static func _goods() -> Array[String]:
	if _goods_cache.is_empty():
		var ok: Array = config()["eligible_containers"]
		var lib := CommodityLibrary.new()
		var ids: Array = lib.order.duplicate()
		ids.sort()
		for id in ids:
			var r := lib.record(id)
			if String(r.get("container_type", "")) in ok and not ("oversized" in r.get("handling", [])) and not ("hazardous" in r.get("handling", [])):
				_goods_cache.append(String(id))
	return _goods_cache
