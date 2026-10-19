class_name Planets
extends RefCounted
## Planets with air: each system's main world has a downport on its surface near its city (LocalSpace
## kind "world") and a rough landing field a few km off ("field"); Sol adds a downport on Mars ("mars").
## This is the data side: which worlds, their gravity, air, look and weather, the asymmetric hops to and
## from them, and the fresh food only they grow. Tuning: data/runtime/planets.json. Docs:
## docs/runtime/planets.md.

const PATH := "res://data/runtime/planets.json"
const KINDS := ["world", "field", "mars"]   ## LocalSpace site kinds on a planet's surface
const G0 := 9.81

static var _cfg: Dictionary = {}


static func config() -> Dictionary:
	if _cfg.is_empty():
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		_cfg = parsed if typeof(parsed) == TYPE_DICTIONARY else {}
	return _cfg


## The planet entries of a system, in order: [{kind, world, name, port, city, gravity_g, air, ...}].
static func entries(system_id: String) -> Array:
	return config().get("worlds", {}).get(system_id, [])


## The planet a site kind of a system is on ("field" is on the main world), or {}.
static func planet(system_id: String, kind: String) -> Dictionary:
	var want := "world" if kind == "field" else kind
	for e in entries(system_id):
		if String(e.kind) == want:
			return e
	return {}


## The site kinds a system has on planets: world and field for a main world, mars for Sol's Mars.
static func site_kinds(system_id: String) -> Array:
	var out := []
	for e in entries(system_id):
		out.append(String(e.kind))
		if String(e.kind) == "world" and e.has("field"):
			out.append("field")
	return out


static func is_planet_kind(kind: String) -> bool:
	return kind in KINDS


## Gravity on a planet site, m/s².
static func gravity(system_id: String, kind: String) -> float:
	return float(planet(system_id, kind).get("gravity_g", 1.0)) * G0


## Sea-level air density there, kg/m³ (0 for none).
static func density(system_id: String, kind: String) -> float:
	var p := planet(system_id, kind)
	return float(p.get("air", {}).get("density", 0.0)) * float(config().entry.density_kg_m3)


## Whether someone of `species` can breathe the air outside without a suit.
static func breathable(system_id: String, kind: String, species: String) -> bool:
	var b: Array = planet(system_id, kind).get("air", {}).get("breathable", [])
	return "all" in b or species in b


## The body a planet site is on, in the shape LocalSpace.body() gives for a moon: name, gravity, colours.
static func body(system_id: String, kind: String) -> Dictionary:
	var p := planet(system_id, kind)
	if p.is_empty():
		return {}
	return {"id": String(p.world), "name": String(p.name), "gravity_m_s2": gravity(system_id, kind), "ground": p.ground, "rock": p.rock,
			"planet": true, "air": p.air}


## A planet site's name: the port's for the downport, the field's for the field.
static func site_name(system_id: String, kind: String) -> String:
	var p := planet(system_id, kind)
	if kind == "field":
		return String(p.get("field", {}).get("name", "%s landing field" % String(p.get("name", ""))))
	return String(p.get("port", "%s Downport" % String(p.get("name", ""))))


## The delta-v and hours from one site kind to another when either is on a planet. Coming down costs
## little (the air brakes it); going up costs the climb. `pay_dv_kms` is the same both ways: the climb.
## {} when neither end is on a planet.
static func hop(system_id: String, from_kind: String, to_kind: String) -> Dictionary:
	var a_p := is_planet_kind(from_kind)
	var b_p := is_planet_kind(to_kind)
	if not a_p and not b_p:
		return {}
	var s: Dictionary = config().surface
	if from_kind == to_kind:
		return {}
	if (from_kind == "world" and to_kind == "field") or (from_kind == "field" and to_kind == "world"):
		return {"dv_kms": float(s.field_hop_dv_kms), "hours": int(s.field_hop_hours), "pay_dv_kms": float(s.field_hop_dv_kms)}
	if from_kind == "mars" or to_kind == "mars":
		var other := to_kind if from_kind == "mars" else from_kind
		var other_base := "world" if other == "field" else other
		var mh: Dictionary = config().get("mars_hops", {}).get(other_base if other_base != "world" else "world", {})
		if mh.is_empty():
			return {}
		var dv := float(mh.dv_kms)
		var up_m := up_dv(system_id, "mars")
		var down_m := float(s.down_dv_kms)
		# Mars's own climb or descent, plus the other end's if it's on Earth
		var out_dv := dv + (up_m if from_kind == "mars" else down_m)
		var pay := dv + up_m
		if other_base == "world":
			out_dv += up_dv(system_id, "world") if to_kind == "mars" else down_m
			pay += up_dv(system_id, "world")
		return {"dv_kms": snappedf(out_dv, 0.1), "hours": int(mh.hours), "pay_dv_kms": snappedf(pay, 0.1)}
	# One end on the main world (world or field), the other in space.
	var planet_kind := from_kind if a_p else to_kind
	var space_kind := to_kind if a_p else from_kind
	var going_up := a_p
	var up := up_dv(system_id, planet_kind)
	var down := float(s.down_dv_kms)
	var base_dv := 0.0
	var base_h := 0
	if space_kind == "port":
		base_dv = float(s.port_to_orbit_dv_kms)
		base_h = 1
	else:
		var h := LocalSpace.hop("port", space_kind)
		if h.is_empty():
			return {}
		base_dv = float(h.dv_kms)
		base_h = int(h.hours)
	var extra := 0.1 if planet_kind == "field" else 0.0
	var dv := base_dv + (up if going_up else down) + extra
	var hours := base_h + (int(s.up_hours) if going_up else int(s.down_hours))
	return {"dv_kms": snappedf(dv, 0.1), "hours": hours, "pay_dv_kms": snappedf(base_dv + up + extra, 0.1)}


## The climb from a planet site to orbit (km/s): heavier worlds cost more.
static func up_dv(system_id: String, kind: String) -> float:
	var g := float(planet(system_id, kind).get("gravity_g", 1.0))
	return float(config().surface.up_dv_kms) * sqrt(maxf(g, 0.05))


## Where the landing field is from the downport (x, z metres), the same every time.
static func field_xz(system_id: String) -> Vector2:
	var d := float(config().entry.get("field_distance_m", 5200.0))
	var a := float(absi(hash(system_id + "|field")) % 360) * PI / 180.0
	return Vector2(cos(a), sin(a)) * d


## Where the city is from the downport (x, z metres): off to one side, on the skyline.
static func city_xz(system_id: String, kind := "world") -> Vector2:
	var d := float(config().terrain.get("city_distance_m", 7000.0))
	var a := float(absi(hash(system_id + "|" + kind + "|city")) % 360) * PI / 180.0
	var f := field_xz(system_id)
	var c := Vector2(cos(a), sin(a)) * d
	if kind == "world" and c.angle_to(f) < 0.8 and c.angle_to(f) > -0.8:
		c = c.rotated(PI * 0.7)   # not on top of the field
	return c


# --- Weather ------------------------------------------------------------------------------------

## The weather at a planet site at a calendar hour: {kind, name, wind (Vector3, m/s, horizontal), gust,
## fog}. Deterministic: every six-hour window draws from the world's own mix; a solar storm in the
## system (Hazards) can whip it up into a gale.
static func weather(system_id: String, kind: String, hour: int) -> Dictionary:
	var p := planet(system_id, kind)
	var w: Dictionary = config().weather
	if p.is_empty():
		return {"kind": "calm", "name": "Calm", "wind": Vector3.ZERO, "gust": 0.0, "fog": 0.0, "speed": 0.0}
	var win := hour / int(w.window_hours)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("weather|%s|%s|%d" % [system_id, String(p.world), win])
	var mix: Array = p.get("weather", ["calm"])
	var k := String(mix[rng.randi() % mix.size()])
	if not Hazards.off:
		var storm := Hazards.storm_at(system_id, hour)
		if not storm.is_empty() and rng.randf() < float(w.get("solar_storm_gale", 0.6)) * float(storm.intensity):
			k = "gale"
	if Hazards.off:
		k = "calm"   # tests about something else: still air
	var kd: Dictionary = w.kinds.get(k, w.kinds.calm)
	var speed := rng.randf_range(float(kd.wind_m_s[0]), float(kd.wind_m_s[1]))
	if Hazards.off:
		speed = 0.0
	var a := rng.randf() * TAU
	return {"kind": k, "name": String(kd.name), "wind": Vector3(cos(a), 0, sin(a)) * speed, "gust": float(kd.gust),
			"fog": float(kd.fog), "speed": speed}


## The wind there now, with gusts: the steady wind plus a wandering push, `t` seconds into a flight.
static func wind_at(wx: Dictionary, t: float, altitude_m: float) -> Vector3:
	var base: Vector3 = wx.get("wind", Vector3.ZERO)
	if base == Vector3.ZERO:
		return base
	var up := 1.0 + clampf(altitude_m / 3000.0, 0.0, 1.5)   # stronger aloft
	var g := float(wx.get("gust", 0.0))
	var gx := sin(t * 0.37) * 0.6 + sin(t * 1.13 + 1.7) * 0.4
	var gz := cos(t * 0.29 + 0.4) * 0.6 + sin(t * 0.91 + 2.3) * 0.4
	return base * up * (1.0 + g * 0.5 * sin(t * 0.21)) + Vector3(gx, 0, gz) * base.length() * g


## Words for the weather: "Rain, wind 9 m/s from the north-west".
static func describe_weather(wx: Dictionary) -> String:
	var speed := float(wx.get("speed", 0.0))
	if speed < 1.0:
		return String(wx.get("name", "Calm"))
	var wind: Vector3 = wx.wind
	return "%s, wind %d m/s from the %s" % [String(wx.name), roundi(speed), _compass(-wind)]


static func _compass(v: Vector3) -> String:
	var names := ["north", "north-east", "east", "south-east", "south", "south-west", "west", "north-west"]
	var a := atan2(v.x, -v.z)   # -Z is north
	var i := posmod(roundi(a / (PI / 4.0)), 8)
	return names[i]


# --- Fresh food -----------------------------------------------------------------------------------

## What a load of fresh food is still worth after `hours` in the hold: full for its shelf life, then
## dropping, down to a floor (it's compost, but someone buys compost).
static func fresh_left(hours: float) -> float:
	var f: Dictionary = config().fresh
	var over := maxf(0.0, hours - float(f.fresh_hours))
	return maxf(float(f.spoil_floor), 1.0 - over * float(f.spoil_per_hour))


static func is_fresh(commodity: String) -> bool:
	return commodity == String(config().fresh.commodity)
