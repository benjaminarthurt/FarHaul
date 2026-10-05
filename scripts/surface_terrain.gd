class_name SurfaceTerrain
extends RefCounted
## The ground of a moon around its landing pad: gentle rolling relief and a few craters, flattened
## around the pad at the origin. Deterministic (same seed, same moon), pure maths for the physics and a
## mesh builder for the view. Heights are metres, with the pad at y = 0.

var seed_value := 0
var relief := 18.0
var flat_r := 90.0
var craters: Array = []   # {x, z, r, depth}
var pads: Array = []      # {x, z, r}: graded flat around each landing site


static func config() -> Dictionary:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://data/runtime/landing.json"))
	return parsed if typeof(parsed) == TYPE_DICTIONARY else {}


## `key` picks the moon (same key, same ground). The base pad is always at the origin; `extra_pads` adds
## other flattened sites as Vector2(x, z) (the mining camp).
## `extra_craters` adds fixed craters ({x, z, r, depth}) such as SurfaceSites' glass crater.
static func make(key: String, extra_pads: Array = [], extra_craters: Array = []) -> SurfaceTerrain:
	var cfg := config()
	var t := SurfaceTerrain.new()
	t.seed_value = hash(key)
	t.relief = float(cfg.get("terrain_relief_m", 18.0))
	t.flat_r = float(cfg.get("pad_flat_radius_m", 90.0))
	t.pads.append({"x": 0.0, "z": 0.0, "r": t.flat_r})
	for p in extra_pads:
		t.pads.append({"x": float(p.x), "z": float(p.y), "r": t.flat_r * 0.5})
	var rng := RandomNumberGenerator.new()
	rng.seed = t.seed_value
	for i in 14:
		var a := rng.randf() * TAU
		var d := rng.randf_range(t.flat_r * 2.5, 1800.0)
		var cx := cos(a) * d
		var cz := sin(a) * d
		var clear := true
		for p in t.pads:
			if Vector2(cx - float(p.x), cz - float(p.z)).length() < float(p.r) * 2.5 + 160.0:
				clear = false
		if not clear:
			continue
		t.craters.append({"x": cos(a) * d, "z": sin(a) * d, "r": rng.randf_range(40.0, 160.0), "depth": rng.randf_range(4.0, 14.0)})
	t.craters.append_array(extra_craters)
	return t


## Ground height at (x, z).
func height(x: float, z: float) -> float:
	var s := float(seed_value % 1000) * 0.37
	var h := relief * (0.5 * sin(x * 0.0021 + s) * cos(z * 0.0017 - s)
			+ 0.3 * sin((x + z) * 0.0053 + s * 2.0)
			+ 0.2 * cos((x - z) * 0.011 - s))
	for c in craters:
		var d := Vector2(x - float(c.x), z - float(c.z)).length() / float(c.r)
		if d < 1.3:
			if d < 1.0:
				h -= float(c.depth) * (1.0 - d * d)          # bowl
			else:
				h += float(c.depth) * 0.35 * (1.3 - d) / 0.3  # raised rim
	# Graded flat around each pad.
	var blend := 1.0
	for p in pads:
		var r := Vector2(x - float(p.x), z - float(p.z)).length()
		blend = minf(blend, smoothstep(float(p.r), float(p.r) * 2.0, r))
	return h * blend


## The ground as a mesh: a grid `size` metres across with `cells` squares a side, centred on the pad.
func build_mesh(size: float, cells: int, ground: Color, rock: Color) -> MeshInstance3D:
	var step := size / float(cells)
	var half := size * 0.5
	var n1 := cells + 1
	var hs := PackedFloat32Array()   # each grid height once (it was four times per square)
	hs.resize(n1 * n1)
	for i in n1:
		for j in n1:
			hs[i * n1 + j] = height(-half + i * step, -half + j * step)
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()
	verts.resize(cells * cells * 6)
	norms.resize(cells * cells * 6)
	cols.resize(cells * cells * 6)
	var w := 0
	for i in cells:
		for j in cells:
			var x0 := -half + i * step
			var z0 := -half + j * step
			var q := [Vector3(x0, hs[i * n1 + j], z0), Vector3(x0 + step, hs[(i + 1) * n1 + j], z0),
					Vector3(x0 + step, hs[(i + 1) * n1 + j + 1], z0 + step), Vector3(x0, hs[i * n1 + j + 1], z0 + step)]
			for tri in [[0, 1, 2], [0, 2, 3]]:
				var a: Vector3 = q[tri[0]]
				var b: Vector3 = q[tri[1]]
				var c: Vector3 = q[tri[2]]
				var n := (c - a).cross(b - a).normalized()
				var mid := (a + b + c) / 3.0
				var patch := 0.5 + 0.25 * sin(mid.x * 0.0071 + mid.z * 0.0043) + 0.25 * sin(mid.x * 0.019 - mid.z * 0.023 + 1.7)
				var col := ground.lerp(rock, clampf((1.0 - n.y) * 6.0, 0.0, 1.0)) * (0.86 + 0.28 * patch)   # broad lighter and darker patches
				col.a = 1.0
				for v in [a, b, c]:
					verts[w] = v
					norms[w] = n
					cols[w] = col
					w += 1
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_COLOR] = cols
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 1.0
	mesh.surface_set_material(0, mat)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	return mi
