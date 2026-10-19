class_name Hazards
extends RefCounted
## Danger without combat: solar storms that come and go in each system, debris fields lying across
## some routes, and (in Rivals) claim-jumpers. Everything here is worked out from the system or route
## and the time, so the same storm and the same field are there for everyone who looks, every time.
## Tuning: data/runtime/hazards.json. Docs: docs/runtime/hazards.md.

const PATH := "res://data/runtime/hazards.json"

static var _cfg: Dictionary = {}
static var off := false   ## tests about something else turn the weather and the rocks off
static var _cache: Dictionary = {}   ## "sys|window" -> storm or {}


static func config() -> Dictionary:
	if _cfg.is_empty():
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		_cfg = parsed if typeof(parsed) == TYPE_DICTIONARY else {}
	return _cfg


# --- Solar storms -----------------------------------------------------------------------------------

## The storm a system has in a ten-day window, if any: {system_id, start, end (hours), intensity 0-1,
## warn: "forecast" | "sensors" | "", warn_at (hour it shows up)}. At most one per window.
static func _storm_in(sys: String, window: int) -> Dictionary:
	if off:
		return {}
	var key := "%s|%d" % [sys, window]
	if _cache.has(key):
		return _cache[key]
	var c: Dictionary = config().storms
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("storm|" + key)
	var out := {}
	var tier := SystemStyle.canon_tier(sys)
	if rng.randf() < float(c.chance.get(tier, 0.2)):
		var w := int(c.window_hours)
		var hours := rng.randi_range(int(c.hours[0]), int(c.hours[1]))
		var start := window * w + rng.randi_range(0, maxi(0, w - hours))
		var warn := ""
		var lead := 0
		if rng.randf() < float(c.forecast_chance):
			warn = "forecast"
			lead = rng.randi_range(int(c.forecast_lead_hours[0]), int(c.forecast_lead_hours[1]))
		elif rng.randf() < float(c.sensor_chance):
			warn = "sensors"
			lead = rng.randi_range(int(c.sensor_lead_hours[0]), int(c.sensor_lead_hours[1]))
		out = {"system_id": sys, "start": start, "end": start + hours, "intensity": snappedf(rng.randf_range(float(c.intensity[0]), float(c.intensity[1])), 0.01),
				"warn": warn, "warn_at": start - lead}
	if _cache.size() > 4000:
		_cache.clear()
	_cache[key] = out
	return out


## The storms a system has that overlap hours [from, to).
static func storms(sys: String, from_h: int, to_h: int) -> Array:
	var out := []
	var w := int(config().storms.window_hours)
	for win in range(floori(float(from_h) / w) - 1, floori(float(to_h) / w) + 1):
		var s := _storm_in(sys, win)
		if not s.is_empty() and int(s.end) > from_h and int(s.start) < to_h:
			out.append(s)
	return out


## The storm raging in a system at an hour, or {}.
static func storm_at(sys: String, hour: int) -> Dictionary:
	var l := storms(sys, hour, hour + 1)
	return {} if l.is_empty() else l[0]


## Storms anyone would know about at `hour`: raging now, or forecast and not yet over (the radio, the
## trade report and port notices). `sensors` adds ones the ship's own sensors have picked up.
static func known(sys: String, hour: int, sensors := false) -> Array:
	var out := []
	for s in storms(sys, hour, hour + 24 * 4):
		var raging := int(s.start) <= hour
		var told := String(s.warn) == "forecast" or (sensors and String(s.warn) == "sensors")
		if raging or (told and hour >= int(s.warn_at)):
			out.append(s)
	return out


## Hours of storm a trip in `sys` from `from_h` for `hours` flies through, weighted by intensity.
static func exposure(sys: String, from_h: int, hours: float) -> float:
	var to_h := from_h + ceili(hours)
	var e := 0.0
	for s in storms(sys, from_h, to_h):
		e += float(mini(int(s.end), to_h) - maxi(int(s.start), from_h)) * float(s.intensity)
	return maxf(0.0, e)


## Words for a storm: "now, until day 41" or "from day 39, about 2 days".
static func describe(s: Dictionary, hour: int) -> String:
	if int(s.start) <= hour:
		return "raging now, until day %d" % (int(s.end) / 24)
	var days := maxf(0.5, float(int(s.end) - int(s.start)) / 24.0)
	return "from day %d, about %s" % [int(s.start) / 24, ("%d days" % roundi(days)) if days >= 1.5 else "a day"]


# --- Debris fields --------------------------------------------------------------------------------

## The debris field across a local hop between two kinds of site this month, or {}: {density 0-1,
## radius_m, along (fraction of the way), offset (from the route, in radii, signed), seed}.
static func local_field(sys: String, kind_a: String, kind_b: String, day: int) -> Dictionary:
	if Planets.is_planet_kind(kind_a) and Planets.is_planet_kind(kind_b) and Landing.body_key(kind_a) == Landing.body_key(kind_b):
		return {}   # a hop across a planet's ground never leaves the air: no rocks up there
	var ks := [kind_a, kind_b]
	ks.sort()
	return _field("local|%s|%s|%s" % [sys, ks[0], ks[1]], day, float(config().debris.local_chance))


## The debris field on an interstellar lane this month, or {}.
static func lane_field(a: String, b: String, day: int) -> Dictionary:
	var ks := [a, b]
	ks.sort()
	return _field("lane|%s|%s" % [ks[0], ks[1]], day, float(config().debris.lane_chance))


static func _field(key: String, day: int, chance: float) -> Dictionary:
	if off:
		return {}
	var c: Dictionary = config().debris
	var window := day / int(c.window_days)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("debris|%s|%d" % [key, window])
	if rng.randf() >= chance:
		return {}
	return {"density": snappedf(rng.randf_range(float(c.density[0]), float(c.density[1])), 0.01),
			"radius_m": roundf(rng.randf_range(float(c.radius_m[0]), float(c.radius_m[1]))),
			"along": rng.randf_range(float(c.along[0]), float(c.along[1])),
			"offset": rng.randf_range(-1.1, 1.1), "seed": rng.randi(), "key": key}


## Expected hits per km flown through a field (autopilot or not).
static func hit_rate_per_km(field: Dictionary, autopilot: bool) -> float:
	var c: Dictionary = config().debris
	return float(field.density) * float(c.hits_per_km_flown) * (float(c.autopilot_rate) if autopilot else 1.0)


## The hull a hit takes at a closing speed (fraction of the hull).
static func hit_damage(speed_m_s: float) -> float:
	var c: Dictionary = config().debris
	return minf(float(c.damage_max), float(c.damage_base) + absf(speed_m_s) * float(c.damage_per_m_s))


## How far a straight route crosses a field (km): a chord at its offset from the centre.
static func crossing_km(field: Dictionary) -> float:
	var d := absf(float(field.offset))
	if d >= 1.0:
		return 0.0
	return 2.0 * float(field.radius_m) * sqrt(1.0 - d * d) / 1000.0


## A run flown from the desk on autopilot through a field: how many hits, and the hull they cost.
## `rng` decides (seeded by the caller from the run). Lanes have no geometry: their mean is set.
static func desk_crossing(field: Dictionary, rng: RandomNumberGenerator, lane := false) -> Dictionary:
	if field.is_empty():
		return {"hits": 0, "damage": 0.0}
	var c: Dictionary = config().debris
	var mean := float(c.lane_hits_mean) * float(field.density) * float(c.autopilot_rate) if lane \
			else hit_rate_per_km(field, true) * crossing_km(field)
	var hits := _poisson(mean, rng)
	var dmg := 0.0
	for i in hits:
		dmg += hit_damage(float(c.desk_speed_m_s) * rng.randf_range(0.6, 1.4))
	return {"hits": hits, "damage": dmg}


static func _poisson(mean: float, rng: RandomNumberGenerator) -> int:
	if mean <= 0.0:
		return 0
	var l := exp(-mean)
	var k := 0
	var p := 1.0
	while true:
		p *= rng.randf()
		if p <= l:
			return k
		k += 1
		if k > 50:
			return k
	return k


# --- What a trip ran into ---------------------------------------------------------------------------

## Everything a trip flown on autopilot ran into: storms in the systems it crossed (`systems`: [{id,
## from_h, hours}]), and debris (`field`, local or lane). Returns {hull, radiator, hits, storm_h, lines}
## for the caller to apply and report. Deterministic in `seed_key`.
static func trip(systems: Array, field: Dictionary, lane: bool, seed_key: String) -> Dictionary:
	var c: Dictionary = config().storms
	var out := {"hull": 0.0, "radiator": 0.0, "hits": 0, "storm_h": 0.0, "lines": []}
	var exposure_h := 0.0
	for s in systems:
		exposure_h += exposure(String(s.id), int(s.from_h), float(s.hours))
	if exposure_h > 0.0:
		out.storm_h = exposure_h
		out.radiator = exposure_h * float(c.radiator_wear_per_hour)
		out.hull = exposure_h * float(c.hull_per_hour)
		(out.lines as Array).append("Flew through a solar storm: the radiators took %d%% wear%s." % [roundi(float(out.radiator) * 100.0),
				" and the hull %d%%" % roundi(float(out.hull) * 100.0) if float(out.hull) >= 0.005 else ""])
	if not field.is_empty():
		var rng := RandomNumberGenerator.new()
		rng.seed = hash("trip|" + seed_key)
		var d := desk_crossing(field, rng, lane)
		out.hits = int(d.hits)
		out.hull = float(out.hull) + float(d.damage)
		if int(d.hits) > 0:
			(out.lines as Array).append("The autopilot threaded a debris field and missed most of it: %d hit%s, %d%% of the hull." % [int(d.hits), "" if int(d.hits) == 1 else "s", roundi(float(d.damage) * 100.0)])
		else:
			(out.lines as Array).append("The autopilot threaded a debris field without a scratch.")
	return out
