class_name Reputation
## What people think of you (0.20.0), kept as three kinds of memory:
##
## - **places**: every port, base, camp, downport and field keeps its own score, moved by the work you do
##   there (deliveries, passengers, rush jobs, cancellations, missions). Only that place knows.
## - **species**: the Kesh, Ilyan, Vey, Orun and humans each hold a view, made from what you did for their
##   people and stations (a share, `species_share`, of each deed).
## - **authorities**: each system's traffic control and port authority keeps a record: fines, unannounced
##   landings and ignored maydays against you, rescues and reports for you.
##
## Standing at a place = its own score + the mean of its peoples' views + its system's record, as heard
## there. Word travels: a deed is known at once in its own system and reaches other systems along the
## routes, as long as traffic takes to get there (`lag_hours`). Bad marks fade (`bad_fade_per_week`).
##
## State lives in `profile.reputation` = {places, species, auth, log, faded_h}; `log` holds deeds whose
## news is still travelling: [{h, sys, sp: {species: points}, auth}]. Tuning: data/runtime/reputation.json.
## See docs/runtime/reputation.md.

const PATH := "res://data/runtime/reputation.json"

static var _cfg: Dictionary = {}
static var _lag: Dictionary = {}       ## "a>b" -> hours for news to get from system a to system b
static var _max_lag: Dictionary = {}   ## system -> hours until everyone has heard


static func cfg() -> Dictionary:
	if _cfg.is_empty():
		var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		_cfg = d if typeof(d) == TYPE_DICTIONARY else {}
	return _cfg


## The state in `profile` (made, or carried over from a save before 0.20.0, on first use).
static func state(profile: Dictionary) -> Dictionary:
	if typeof(profile.get("reputation")) == TYPE_DICTIONARY:
		return profile["reputation"]
	var st := {"places": {}, "species": {}, "auth": {}, "log": [], "faded_h": -1}
	var old := float(profile.get("rep", 0))   # the one score before 0.20.0: it was earned here, mostly
	if old > 0.0:
		var site := String(profile.get("port_id", ""))
		if site != "":
			st.places[site] = old
		for sp in peoples(String(profile.get("system_id", ""))):
			st.species[sp] = old * float(cfg().get("species_share", 0.5))
	profile["reputation"] = st
	return st


## Who lives at a system's sites: its home species, or the species that settled it, or humans.
static func peoples(system_id: String) -> Array:
	var sys := Worlds.system(system_id)
	var home: Array = sys.get("home_species_ids", [])
	if home != null and not home.is_empty():
		return home
	var origin: Array = sys.get("origin_species_ids", [])
	if origin != null and not origin.is_empty():
		return origin
	return ["human"]


static func system_of(site_id: String) -> String:
	var n := LocalSpace.node(site_id)
	if not n.is_empty():
		return String(n.get("system_id", ""))
	if LocalSpace.SEP in site_id:
		return site_id.get_slice(LocalSpace.SEP, 0)
	return String(Worlds.port(site_id).get("system_id", ""))


# --- News --------------------------------------------------------------------------------------------

## Hours for word to get from system `a` to system `b`: the route as traffic flies it, plus a few hours
## of gossip at each end. Systems off the network hear after `unreachable_lag_days`.
static func lag_hours(a: String, b: String, sim: EconomySim = null) -> int:
	if a == b:
		return 0
	var key := "%d|%s>%s" % [sim.get_instance_id() if sim != null else 0, a, b]   # a new game's sim, or none, works it out again
	if _lag.has(key):
		return int(_lag[key])
	var c := cfg()
	var h := int(c.get("unreachable_lag_days", 30)) * 24
	if sim != null:
		var p := sim.net.path(a, b)
		if not p.is_empty():
			h = sim._path_hours(p)
	else:
		var ly := Worlds.distance_ly(a, b)
		if ly > 0.0:
			h = int(ceil(ly / float(c.get("news_ly_per_day", 1.5)) * 24.0))
	h += int(c.get("news_lag_hours", 6))
	_lag[key] = h
	return h


static func _everyone_heard(sys: String, sim: EconomySim) -> int:
	var key := "%d|%s" % [sim.get_instance_id() if sim != null else 0, sys]
	if _max_lag.has(key):
		return int(_max_lag[key])
	var m := 0
	for s in Worlds.system_ids():
		m = maxi(m, lag_hours(sys, s, sim))
	_max_lag[key] = m
	return m


static func heard(e: Dictionary, at_sys: String, now_h: int, sim: EconomySim = null) -> bool:
	return now_h >= int(e.h) + lag_hours(String(e.sys), at_sys, sim)


# --- Keeping it ---------------------------------------------------------------------------------------

## Fold news everyone has heard into the totals, and fade bad marks. Called before every look.
static func tick(st: Dictionary, now_h: int, sim: EconomySim = null) -> void:
	var c := cfg()
	var share := float(c.get("authority_share_elsewhere", 0.75))
	var keep := []
	for e in st.log:
		if now_h < int(e.h) + _everyone_heard(String(e.sys), sim):
			keep.append(e)
			continue
		for sp in (e.sp as Dictionary):
			st.species[sp] = float(st.species.get(sp, 0.0)) + float(e.sp[sp])
		var a := float(e.get("auth", 0.0))
		if a != 0.0:
			for s in Worlds.system_ids():
				if e.has("settled_h") and (s == String(e.sys) or not heard(e, s, int(e.settled_h), sim)):
					continue   # settled before word got there
				st.auth[s] = float(st.auth.get(s, 0.0)) + (a if s == String(e.sys) else a * share)
	st.log = keep
	var last := int(st.get("faded_h", -1))
	if last < 0:
		st.faded_h = now_h
		return
	if now_h - last < 24:
		return
	var f := pow(1.0 - float(c.get("bad_fade_per_week", 0.1)), float(now_h - last) / (24.0 * 7.0))
	for book in ["places", "species", "auth"]:
		var d: Dictionary = st[book]
		for k in d.keys():
			if float(d[k]) < 0.0:
				d[k] = float(d[k]) * f
	st.faded_h = now_h


## Record a deed worth `points` done at `site_id` (in `system_id`) at hour `now_h`. `kind` picks where
## the points go (reputation.json "deeds": work, radio, record, rescue); `species` names who you helped or
## let down, when it isn't the people of the place.
static func record(st: Dictionary, now_h: int, system_id: String, site_id: String, points: float, kind := "work",
		species: Array = [], sim: EconomySim = null) -> void:
	if points == 0.0:
		return
	tick(st, now_h, sim)
	var c := cfg()
	var goes: Array = (c.get("deeds", {}) as Dictionary).get(kind, ["place", "species"])
	if "place" in goes and site_id != "":
		st.places[site_id] = clampf(float(st.places.get(site_id, 0.0)) + points, -_limit(), _limit())
	var e := {"h": now_h, "sys": system_id, "sp": {}, "auth": 0.0}
	if "species" in goes:
		var who := species if not species.is_empty() else peoples(system_id)
		for sp in who:
			e.sp[String(sp)] = points * float(c.get("species_share", 0.5))
	if "authority" in goes:
		e.auth = points
	if not (e.sp as Dictionary).is_empty() or float(e.auth) != 0.0:
		st.log.append(e)


static func _limit() -> float:
	return float(cfg().get("limit", 100))


# --- Looking ------------------------------------------------------------------------------------------

## A species' view of you, as heard in `at_sys` by `now_h`.
static func species_view(st: Dictionary, sp: String, at_sys: String, now_h: int, sim: EconomySim = null) -> float:
	var v := float(st.species.get(sp, 0.0))
	for e in st.log:
		if (e.sp as Dictionary).has(sp) and heard(e, at_sys, now_h, sim):
			v += float(e.sp[sp])
	return v


## `at_sys`'s authorities' record of you: their own deeds at once, other systems' as word arrives.
static func authority_view(st: Dictionary, at_sys: String, now_h: int, sim: EconomySim = null) -> float:
	var v := float(st.auth.get(at_sys, 0.0))
	var share := float(cfg().get("authority_share_elsewhere", 0.75))
	for e in st.log:
		var a := float(e.get("auth", 0.0))
		if a == 0.0:
			continue
		var by := mini(now_h, int(e.get("settled_h", now_h)))   # a settled mark only counts where it had arrived by then
		if String(e.sys) == at_sys:
			if not e.has("settled_h"):
				v += a
		elif heard(e, at_sys, by, sim):
			v += a * share
	return v


## The parts of your standing at `site_id`: {place, species, authority, total}.
static func parts(st: Dictionary, site_id: String, now_h: int, sim: EconomySim = null) -> Dictionary:
	tick(st, now_h, sim)
	var sys := system_of(site_id)
	var place := float(st.places.get(site_id, 0.0))
	var who := peoples(sys)
	var spv := 0.0
	for sp in who:
		spv += species_view(st, String(sp), sys, now_h, sim)
	spv /= maxf(1.0, float(who.size()))
	var auth := authority_view(st, sys, now_h, sim)
	return {"place": place, "species": spv, "authority": auth, "total": clampf(place + spv + auth, -_limit(), _limit())}


static func standing(st: Dictionary, site_id: String, now_h: int, sim: EconomySim = null) -> float:
	return float(parts(st, site_id, now_h, sim).total)


## The name of a standing: Barred, Unwelcome, Doubtful, Unknown, Known, Trusted, Respected.
static func tier(points: float) -> String:
	var name := "Unknown"
	var tiers: Array = cfg().get("tiers", [])
	for t in tiers:   # at or below a negative threshold
		if float(t[0]) < 0.0 and points <= float(t[0]):
			return String(t[1])
	for t in tiers:   # at or above a positive one
		if float(t[0]) > 0.0 and points >= float(t[0]):
			name = String(t[1])
	return name


## The next tier up and the points it needs ({} at the top).
static func next_tier(points: float) -> Dictionary:
	var here := tier(points)
	var steps := []   # where each tier starts, going up: just above a negative threshold, or at a positive one
	for t in cfg().get("tiers", []):
		var at := float(t[0])
		if at < 0.0:
			steps.append(at + 0.01)
		elif at > 0.0:
			steps.append(at)
	steps.sort()
	for x in steps:
		if float(x) > points and tier(float(x)) != here:
			return {"name": tier(float(x)), "points": float(x)}
	return {}


static func at_least(points: float, name: String) -> bool:
	return rank(tier(points)) >= rank(name)


static func rank(name: String) -> int:
	var i := 0
	for t in cfg().get("tiers", []):
		if String(t[1]) == name:
			return i
		i += 1
	return 3


static func _curve(key: String, points: float) -> float:
	var pts: Array = cfg().get(key, [])
	if pts.is_empty():
		return 1.0
	if points <= float(pts[0][0]):
		return float(pts[0][1])
	for i in range(1, pts.size()):
		if points <= float(pts[i][0]):
			var a: Array = pts[i - 1]
			var b: Array = pts[i]
			return lerpf(float(a[1]), float(b[1]), (points - float(a[0])) / (float(b[0]) - float(a[0])))
	return float(pts[-1][1])


## What work pays here, against the usual (0.7 Barred to 1.25 Respected).
static func pay_mult(points: float) -> float:
	return _curve("pay_mult", points)


## What fees, fuel and repairs cost here, against the usual (1.6 Barred to 0.88 Respected).
static func fee_mult(points: float) -> float:
	return _curve("fee_mult", points)


static func tier_note(name: String) -> String:
	return String((cfg().get("tier_notes", {}) as Dictionary).get(name, ""))


## What settling your record with `sys`'s authorities costs (0 when it's clean), before the fee level.
static func settle_cost(st: Dictionary, sys: String, now_h: int, sim: EconomySim = null) -> int:
	tick(st, now_h, sim)
	var v := authority_view(st, sys, now_h, sim)
	if v >= 0.0:
		return 0
	return int(ceil(-v)) * int(cfg().get("settle_cr_per_point", 400))


## Clear `sys`'s record of what's against you. Marks other systems had already heard stand there; word
## that hadn't arrived yet never does.
static func settle(st: Dictionary, sys: String, now_h: int, sim: EconomySim = null) -> void:
	tick(st, now_h, sim)
	for e in st.log:
		if String(e.sys) == sys and float(e.get("auth", 0.0)) < 0.0 and not e.has("settled_h"):
			e["settled_h"] = now_h   # cleared here; elsewhere, only what had already arrived by now stands
	var v := authority_view(st, sys, now_h, sim)
	if v < 0.0:
		st.auth[sys] = float(st.auth.get(sys, 0.0)) - v
