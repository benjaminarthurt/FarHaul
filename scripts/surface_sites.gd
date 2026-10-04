class_name SurfaceSites
extends RefCounted
## Places on a moon beyond the base pad and the mining camp, reached by flying the lander over and
## setting down by hand (no beacon, no pad but the outpost's old one), and the ground's hazards:
##
## - **abandoned outpost:** a dead survey station with its own cracked pad; salvage to strip.
## - **ice mine:** a worked-out pit; ice cores to cut, which the camp's exchange pays well for.
## - **glass crater:** a deep crater whose floor holds rare crystals. Its walls are too steep to walk:
##   bring suit jets, or land on the floor.
## - **boulders:** strewn around every site. The suit walks round them; a ship that sets down on one is
##   damaged.
## - **slopes:** the suit cannot climb ground steeper than `walk_slope_deg`; a ship that lands on ground
##   steeper than `land_slope_deg` slides and is damaged.
##
## Everything is placed from the system id, so the ground is the same every visit. Tuning: the "sites"
## block of data/runtime/landing.json.

static func config() -> Dictionary:
	return SurfaceTerrain.config().get("sites", {})


## The extra sites of this system's moon: [{id, name, x, z}].
static func sites(system_id: String) -> Array[Dictionary]:
	var cfg := config()
	var out: Array[Dictionary] = []
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(system_id + "|sites")
	var camp := SurfaceFinds.camp_xz()
	var away := camp.angle() + PI   # start on the side away from the camp
	var defs: Array = cfg.get("list", [])
	for i in defs.size():
		var d: Dictionary = defs[i]
		var a := away + (i - 1) * 1.1 + rng.randf_range(-0.25, 0.25)
		var r := rng.randf_range(float(d.dist_m[0]), float(d.dist_m[1]))
		out.append({"id": String(d.id), "name": String(d.name), "x": roundf(cos(a) * r), "z": roundf(sin(a) * r)})
	return out


static func site(system_id: String, id: String) -> Dictionary:
	for s in sites(system_id):
		if String(s.id) == id:
			return s
	return {}


## Extra flattened pads for the terrain (the outpost's).
static func pads(system_id: String) -> Array:
	var o := site(system_id, "outpost")
	return [] if o.is_empty() else [Vector2(float(o.x), float(o.z))]


## Extra craters for the terrain (the glass crater, and the ice mine's pit).
static func craters(system_id: String) -> Array:
	var cfg := config()
	var out := []
	var c := site(system_id, "crater")
	if not c.is_empty():
		out.append({"x": float(c.x), "z": float(c.z), "r": float(cfg.get("crater_r_m", 200.0)), "depth": float(cfg.get("crater_depth_m", 70.0))})
	var m := site(system_id, "ice_mine")
	if not m.is_empty():
		out.append({"x": float(m.x), "z": float(m.z), "r": float(cfg.get("pit_r_m", 60.0)), "depth": float(cfg.get("pit_depth_m", 9.0))})
	return out


## Boulders: Vector3(x, z, radius). Clusters around each site and the camp, none on a pad.
static func boulders(system_id: String) -> Array[Vector3]:
	var cfg := config()
	var out: Array[Vector3] = []
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(system_id + "|boulders")
	var centres: Array = [SurfaceFinds.camp_xz()]
	for s in sites(system_id):
		centres.append(Vector2(float(s.x), float(s.z)))
	var keep_clear: Array = [Vector2.ZERO, SurfaceFinds.camp_xz()] + pads(system_id)
	var pad_r := float(SurfaceTerrain.config().get("pad_flat_radius_m", 90.0)) * 0.5 + 15.0
	for c in centres:
		for i in int(cfg.get("boulders_per_site", 40)):
			var a := rng.randf() * TAU
			var d := rng.randf_range(20.0, float(cfg.get("boulder_field_m", 260.0)))
			var p: Vector2 = c + Vector2(cos(a), sin(a)) * d
			var ok := true
			for k in keep_clear:
				if p.distance_to(k) < pad_r:
					ok = false
			if ok:
				out.append(Vector3(p.x, p.y, rng.randf_range(0.6, float(cfg.get("boulder_max_r_m", 2.6)))))
	return out


## Finds at the extra sites, for SurfaceFinds.list: outpost salvage, ice cores, rare crystals.
static func finds(system_id: String, day: int) -> Array[Dictionary]:
	var cfg := config()
	var out: Array[Dictionary] = []
	var fc: Dictionary = SurfaceFinds.config()
	var o := site(system_id, "outpost")
	if not o.is_empty():
		var ww := day / int(fc.get("salvage_refresh_days", 20))
		out.append({"id": "%s|o|%d" % [system_id, ww], "kind": "salvage", "x": float(o.x) + 18.0, "z": float(o.z) - 12.0, "name": "Abandoned outpost",
				"units": int(cfg.get("outpost_salvage_units", 3))})
	var rng := RandomNumberGenerator.new()
	var m := site(system_id, "ice_mine")
	if not m.is_empty():
		var iw := day / int(cfg.get("ice_refresh_days", 10))
		rng.seed = hash("%s|ice|%d" % [system_id, iw])
		for i in int(cfg.get("ice_per_visit", 4)):
			var a := rng.randf() * TAU
			var d := rng.randf_range(5.0, float(cfg.get("pit_r_m", 60.0)) * 0.6)
			out.append({"id": "%s|i|%d|%d" % [system_id, iw, i], "kind": "ice", "x": float(m.x) + cos(a) * d, "z": float(m.z) + sin(a) * d, "name": "Ice core"})
	var c := site(system_id, "crater")
	if not c.is_empty():
		var rw := day / int(cfg.get("rare_refresh_days", 30))
		rng.seed = hash("%s|rare|%d" % [system_id, rw])
		for i in int(cfg.get("rare_per_visit", 2)):
			var a := rng.randf() * TAU
			var d := rng.randf_range(10.0, float(cfg.get("crater_r_m", 200.0)) * 0.35)
			out.append({"id": "%s|r|%d|%d" % [system_id, rw, i], "kind": "rare", "x": float(c.x) + cos(a) * d, "z": float(c.z) + sin(a) * d, "name": "Glass crystal"})
	return out


## Ground slope at (x, z), in degrees.
static func slope_deg(t: SurfaceTerrain, x: float, z: float) -> float:
	var e := 1.5
	var dx := (t.height(x + e, z) - t.height(x - e, z)) / (2.0 * e)
	var dz := (t.height(x, z + e) - t.height(x, z - e)) / (2.0 * e)
	return rad_to_deg(atan(Vector2(dx, dz).length()))
