class_name SurfaceFinds
extends RefCounted
## Things worth walking out for on a moon: rock samples scattered around the base pad and the mining camp
## (a lab buys them), and a wrecked lander near the camp whose parts can be stripped and sold. Where they
## lie is fixed by the system and a time window, so the ground is the same every visit and fresh finds
## turn up as the windows roll over. Positions are on the moon's ground plane (x, z), base pad at the origin.

static func config() -> Dictionary:
	return SurfaceTerrain.config().get("finds", {})


static func camp_xz() -> Vector2:
	var off: Array = SurfaceTerrain.config().get("camp_offset_m", [2600.0, -1500.0])
	return Vector2(float(off[0]), float(off[1]))


static func wreck_xz() -> Vector2:
	return camp_xz() + Vector2(620.0, 430.0)


## Every find on this system's moon for `day`: {id, kind ("sample" or "salvage"), x, z, name}.
static func list(system_id: String, day: int) -> Array[Dictionary]:
	var cfg := config()
	var out: Array[Dictionary] = []
	var sw := day / int(cfg.get("sample_refresh_days", 10))
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("%s|samples|%d" % [system_id, sw])
	var kinds: Array = cfg.get("sample_names", ["Rock core"])
	var around := [[Vector2.ZERO, 140.0, 520.0], [camp_xz(), 90.0, 360.0]]
	var n := 0
	for site in around:
		for i in int(cfg.get("samples_per_site", 5)):
			var a := rng.randf() * TAU
			var d := rng.randf_range(float(site[1]), float(site[2]))
			var p: Vector2 = site[0] + Vector2(cos(a), sin(a)) * d
			out.append({"id": "%s|s|%d|%d" % [system_id, sw, n], "kind": "sample", "x": p.x, "z": p.y,
					"name": String(kinds[rng.randi() % kinds.size()])})
			n += 1
	var ww := day / int(cfg.get("salvage_refresh_days", 20))
	var w := wreck_xz()
	out.append({"id": "%s|w|%d" % [system_id, ww], "kind": "salvage", "x": w.x, "z": w.y, "name": "Wrecked lander"})
	return out


static func value(kind: String) -> int:
	return int(config().get("sample_cr" if kind == "sample" else "salvage_cr", 350))


static func units(kind: String) -> int:
	return 1 if kind == "sample" else int(config().get("salvage_units", 2))
