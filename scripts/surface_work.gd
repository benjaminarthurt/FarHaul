class_name SurfaceWork
extends RefCounted
## Work on foot on a moon (data/runtime/surface_work.json):
##
## - **the suit:** air that runs down while you are outside (faster when running), and gear bought at a
##   hab's suit store: bigger air tanks, grip boots, a ground scanner and suit jets;
## - **surface missions:** timed jobs posted at the hab's dispatch desk (around the base pad) and the
##   camp foreman (around the camp): place survey beacons, reach a surveyor whose suit is failing, fix
##   a stalled drill;
## - **unloading at the camp:** the camp has no crane. Pay its crew, or carry the crates yourself.
##
## Positions are on the moon's ground plane (x, z) with the base pad at the origin, as in SurfaceFinds.

const PATH := "res://data/runtime/surface_work.json"
const GEAR_ORDER := ["o2_1", "o2_2", "boots", "scanner", "jetpack"]

static var _cfg: Dictionary = {}


static func config() -> Dictionary:
	if _cfg.is_empty():
		var f := FileAccess.open(PATH, FileAccess.READ)
		if f != null:
			var d: Variant = JSON.parse_string(f.get_as_text())
			if typeof(d) == TYPE_DICTIONARY:
				_cfg = d
	return _cfg


static func suit_cfg() -> Dictionary:
	return config().get("suit", {})


static func gear(id: String) -> Dictionary:
	return config().get("gear", {}).get(id, {})


static func has(owned: Array, id: String) -> bool:
	return id in owned


## Seconds of air in a full suit with this gear.
static func o2_capacity(owned: Array) -> float:
	var s := suit_cfg()
	var tanks := (1 if has(owned, "o2_1") else 0) + (1 if has(owned, "o2_2") else 0)
	return float(s.get("o2_s", 900)) + tanks * float(s.get("o2_per_tank_s", 600))


## Where a surface site sits on the moon's ground plane.
static func site_xz(kind: String) -> Vector2:
	return SurfaceFinds.camp_xz() if kind == "camp" else Vector2.ZERO


## Missions posted at a surface site (`kind` "pad" or "camp") of `system_id` for `day`:
## {id, kind, site, title, blurb, points: [[x, z], ...], limit_s, pay, rep, hold_s}.
static func offered(system_id: String, site: String, day: int, taken: Array = []) -> Array[Dictionary]:
	var m: Dictionary = config().get("missions", {})
	var out: Array[Dictionary] = []
	var window := day / int(m.get("refresh_days", 2))
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("%s|%s|missions|%d" % [system_id, site, window])
	var kinds := ["survey", "rescue"] if site == "pad" else ["drill", "survey", "rescue"]
	var centre := site_xz(site)
	for i in int(m.get("per_site", 2)):
		var kind: String = kinds[(i + rng.randi()) % kinds.size()]
		var k: Dictionary = m.kinds[kind]
		var id := "mission|%s|%s|%d|%d" % [system_id, site, window, i]
		var pts: Array = []
		var walk := 0.0
		var prev := centre
		var base_a := rng.randf() * TAU
		for p in int(k.points):
			var a := base_a + p * rng.randf_range(0.5, 1.1)
			var d := rng.randf_range(float(k.range_m[0]), float(k.range_m[1]))
			var q := centre + Vector2(cos(a), sin(a)) * d
			pts.append([snappedf(q.x, 0.1), snappedf(q.y, 0.1)])
			walk += prev.distance_to(q)
			prev = q
		walk += prev.distance_to(centre)   # and back to the ship
		var limit := walk / float(m.get("time_walk_m_s", 1.6)) * float(m.get("time_margin", 1.5)) + float(m.get("time_extra_s", 90))
		if kind == "drill":
			limit += float(k.get("hold_s", 5.0))
		out.append({"id": id, "kind": kind, "site": site, "system_id": system_id, "title": String(k.title), "blurb": String(k.blurb),
				"points": pts, "limit_s": roundf(limit), "walk_m": roundf(walk),
				"pay": roundi(maxf(float(k.pay_min), walk * float(k.pay_cr_per_m)) / 50.0) * 50, "rep": int(k.rep),
				"hold_s": float(k.get("hold_s", 0.0)), "taken": id in taken})
	return out


static func unload_cfg() -> Dictionary:
	return config().get("unload", {})


## The spot by the camp's hut where crates are stacked.
static func drop_xz() -> Vector2:
	var off: Array = unload_cfg().get("drop_offset_m", [-26.0, -10.0])
	return SurfaceFinds.camp_xz() + Vector2(float(off[0]), float(off[1]))


static func crates_for(tonnes: float) -> int:
	return maxi(1, ceili(tonnes / float(unload_cfg().get("crate_t", 2.0))))


## "4:05" from seconds.
static func clock(s: float) -> String:
	var t := maxi(0, int(ceilf(s)))
	return "%d:%02d" % [t / 60, t % 60]
