class_name PlanetTerrain
extends SurfaceTerrain
## The ground of a planet round its downport: about 40 km of land (or sea) worked out from the world's
## seed, the same every visit. A coarse height map covers the whole area (built once, on a worker
## thread) and a finer noise adds the small hills you land among; `height()` is the two together, so the
## physics and the near ground mesh agree to the centimetre. Sea level is y = 0. The downport's pad, the
## landing field and the city are graded flat; past the edge of the map the land settles to its average.
## The kind of land comes from planets.json "land": coast, islands, ocean, plains, desert, rock,
## escarpment, plateau or volcanic.

var system_id := ""
var kind := "world"
var land := "plains"
var size_m := 40000.0
var map_px := 512
var hmap := PackedFloat32Array()
var sea_on := false
var port_h := 0.0          ## the downport's pad height above the sea
var field_xz := Vector2.ZERO
var field_h := 0.0
var city_xz := Vector2.ZERO
var city_h := 0.0
var platform := false       ## the pad stands on a platform over open water (an ocean world)
var _noise := FastNoiseLite.new()
var _detail := FastNoiseLite.new()
var _flats: Array = []       ## {x, z, r, h}: graded flat round the pad, the field and the city
var _avg := 0.0


static func make_planet(system_id_: String, kind_: String) -> PlanetTerrain:
	var p := Planets.planet(system_id_, kind_)
	var t := PlanetTerrain.new()
	t.system_id = system_id_
	t.kind = kind_
	t.land = String(p.get("land", "plains"))
	t.relief = float(p.get("relief_m", 150.0))
	t.sea_on = bool(p.get("sea", false))
	var tc: Dictionary = Planets.config().terrain
	t.size_m = float(tc.size_m)
	t.map_px = int(tc.map_px)
	t.seed_value = hash("planet|" + system_id_ + "|" + kind_)
	t._noise.seed = t.seed_value
	t._noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	t._noise.frequency = 1.0 / 9000.0
	t._noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	t._noise.fractal_octaves = 5
	t._detail.seed = t.seed_value + 7
	t._detail.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	t._detail.frequency = 1.0 / 260.0
	t._detail.fractal_type = FastNoiseLite.FRACTAL_FBM
	t._detail.fractal_octaves = 3
	t.platform = t.land == "ocean"
	if kind_ != "mars":
		t.field_xz = Planets.field_xz(system_id_)
	t.city_xz = Planets.city_xz(system_id_, kind_)
	t._build_map()
	return t


## The raw land before anything is graded flat, metres above the sea.
func _raw(x: float, z: float) -> float:
	var n := _noise.get_noise_2d(x, z)   # about -1..1
	match land:
		"coast":   # land rising one way, sea the other, the port near the shore
			var lean := (x * 0.6 + z * 0.8) / 14000.0
			return relief * (n * 1.1 + 0.35 + lean)
		"islands":
			return relief * (n * 1.6 - 0.35) + relief * 0.9 * _bump(x, z, 0.0, 0.0, 2600.0)
		"ocean":
			return -60.0 + 40.0 * n
		"desert":
			var dune := absf(sin((x * 0.7 + z * 0.3) / 380.0 + n * 3.0))
			return relief * (0.55 + n * 0.5) + relief * 0.06 * dune
		"rock":
			return relief * (0.6 + n * 0.7 + 0.3 * absf(_noise.get_noise_2d(x * 3.0, z * 3.0)))
		"escarpment":   # great steps: flat benches between cliffs
			var e := (n + 1.0) * 2.5
			var step := floorf(e)
			var f := e - step
			return relief * 0.4 * (step + smoothstep(0.75, 0.95, f))
		"plateau":   # high flat ground cut by deep valleys
			var r := 1.0 - absf(n)
			return relief * (0.3 + 0.7 * smoothstep(0.25, 0.45, r))
		"volcanic":
			var cone := 0.0
			var rng := RandomNumberGenerator.new()
			rng.seed = seed_value
			for i in 4:
				var cx := rng.randf_range(-15000.0, 15000.0)
				var cz := rng.randf_range(-15000.0, 15000.0)
				var d := Vector2(x - cx, z - cz).length() / rng.randf_range(2500.0, 4500.0)
				if d < 1.0:
					cone = maxf(cone, (1.0 - d) * (1.0 - d) * 2.2 - (0.6 if d < 0.12 else 0.0))
			return relief * (0.35 + n * 0.45 + cone)
		_:   # plains: long gentle swells
			return relief * (0.5 + n * 0.6)


static func _bump(x: float, z: float, cx: float, cz: float, r: float) -> float:
	var d := Vector2(x - cx, z - cz).length() / r
	return 0.0 if d >= 1.0 else (1.0 - d * d) * (1.0 - d * d)


func _build_map() -> void:
	# Where the flat places sit, at the height the land has there (never under the sea, bar a platform).
	var tc: Dictionary = Planets.config().terrain
	port_h = maxf(_raw(0.0, 0.0), 8.0) if not platform else 14.0
	_flats = [{"x": 0.0, "z": 0.0, "r": float(tc.port_flat_m), "h": port_h}]
	if kind != "mars":
		field_h = maxf(_raw(field_xz.x, field_xz.y), 6.0) if not platform else 12.0
		_flats.append({"x": field_xz.x, "z": field_xz.y, "r": float(tc.field_flat_m), "h": field_h})
	city_h = maxf(_raw(city_xz.x, city_xz.y), 6.0) if not platform else 0.0
	if not platform:
		_flats.append({"x": city_xz.x, "z": city_xz.y, "r": float(tc.city_flat_m) * 0.5, "h": city_h, "soft": true})
	hmap.resize(map_px * map_px)
	var step := size_m / float(map_px - 1)
	var half := size_m * 0.5
	var total := 0.0
	for i in map_px:
		for j in map_px:
			var x := -half + i * step
			var z := -half + j * step
			var h := _raw(x, z)
			hmap[i * map_px + j] = h
			total += h
	_avg = total / float(hmap.size())


## The coarse land at (x, z), from the map (bilinear), settling to the average past its edge.
func _map(x: float, z: float) -> float:
	var half := size_m * 0.5
	var fx := (x + half) / size_m * float(map_px - 1)
	var fz := (z + half) / size_m * float(map_px - 1)
	var out := maxf(maxf(-fx, fx - float(map_px - 1)), maxf(-fz, fz - float(map_px - 1)))
	var i := clampi(int(floorf(fx)), 0, map_px - 2)
	var j := clampi(int(floorf(fz)), 0, map_px - 2)
	var u := clampf(fx - float(i), 0.0, 1.0)
	var v := clampf(fz - float(j), 0.0, 1.0)
	var h00 := hmap[i * map_px + j]
	var h10 := hmap[(i + 1) * map_px + j]
	var h01 := hmap[i * map_px + j + 1]
	var h11 := hmap[(i + 1) * map_px + j + 1]
	var h := lerpf(lerpf(h00, h10, u), lerpf(h01, h11, u), v)
	if out > 0.0:
		h = lerpf(h, _avg, clampf(out / 40.0, 0.0, 1.0))
	return h


## Ground height at (x, z): the land, with the pad, field and city graded flat. Over the sea this is the
## sea bed; `surface()` is what a ship meets.
func ground(x: float, z: float) -> float:
	var h := _map(x, z) + relief * 0.04 * _detail.get_noise_2d(x, z)
	for f in _flats:
		var d := Vector2(x - float(f.x), z - float(f.z)).length()
		var r := float(f.r)
		if d < r * 2.2:
			var k := smoothstep(r, r * 2.2, d)
			if bool(f.get("soft", false)):
				k = 0.4 + 0.6 * k   # the city keeps a little of its lie
			h = lerpf(float(f.h), h, k)
	return h


## What a ship touches down on at (x, z): the ground, or the sea's surface where that's higher.
func height(x: float, z: float) -> float:
	var g := ground(x, z)
	if platform and _on_platform(x, z):
		return g
	return maxf(g, 0.0) if sea_on else g


func is_water(x: float, z: float) -> bool:
	if not sea_on:
		return false
	if platform and _on_platform(x, z):
		return false
	return ground(x, z) < 0.0


## On an ocean world the pad and the field stand on platforms over the water.
func _on_platform(x: float, z: float) -> bool:
	if Vector2(x, z).length() < float(Planets.config().terrain.port_flat_m) * 0.7:
		return true
	return kind != "mars" and Vector2(x - field_xz.x, z - field_xz.y).length() < float(Planets.config().terrain.field_flat_m) * 0.8


## The ground as one mesh over a square: `centre` (x, z), `size` metres across, `cells` squares a side,
## in the planet's colours (vertex colours by height, slope and shore). Safe on a worker thread. `coarse`
## uses the map only (the far ground); otherwise the fine detail too.
func planet_mesh(centre: Vector2, size: float, cells: int, look: Dictionary, coarse := false) -> ArrayMesh:
	var stepm := size / float(cells)
	var n1 := cells + 1
	var verts := PackedVector3Array()
	var cols := PackedColorArray()
	var norms := PackedVector3Array()
	verts.resize(n1 * n1)
	cols.resize(n1 * n1)
	norms.resize(n1 * n1)
	var low := _c(look.get("ground", [0.4, 0.4, 0.3]))
	var high := _c(look.get("high", [0.5, 0.5, 0.45]))
	var rock := _c(look.get("rock", [0.35, 0.33, 0.3]))
	var shore := _c(look.get("shore", [0.6, 0.55, 0.45]))
	var x0 := centre.x - size * 0.5
	var z0 := centre.y - size * 0.5
	var hs := PackedFloat32Array()
	hs.resize(n1 * n1)
	for i in n1:
		for j in n1:
			var x := x0 + i * stepm
			var z := z0 + j * stepm
			hs[i * n1 + j] = _map(x, z) if coarse else ground(x, z)
	for i in n1:
		for j in n1:
			var x := x0 + i * stepm
			var z := z0 + j * stepm
			var h := hs[i * n1 + j]
			var hl := hs[maxi(i - 1, 0) * n1 + j]
			var hr := hs[mini(i + 1, cells) * n1 + j]
			var hd := hs[i * n1 + maxi(j - 1, 0)]
			var hu := hs[i * n1 + mini(j + 1, cells)]
			var nrm := Vector3(hl - hr, 2.0 * stepm, hd - hu).normalized()
			var k := i * n1 + j
			verts[k] = Vector3(x, h, z)
			norms[k] = nrm
			var t := clampf((h - relief * 0.2) / maxf(relief * 1.2, 1.0), 0.0, 1.0)
			var col := low.lerp(high, t)
			col = col.lerp(rock, clampf((1.0 - nrm.y) * 5.0, 0.0, 1.0))
			if sea_on and h < 4.0:
				col = shore.lerp(shore.darkened(0.45), clampf(-h / 30.0, 0.0, 1.0))
			var patch := 0.5 + 0.25 * sin(x * 0.0013 + z * 0.0009) + 0.25 * sin(x * 0.0041 - z * 0.0037 + 1.7)
			col = col * (0.88 + 0.24 * patch)
			col.a = 1.0
			cols[k] = col
	var idx := PackedInt32Array()
	idx.resize(cells * cells * 6)
	var w := 0
	for i in cells:
		for j in cells:
			var a := i * n1 + j
			var b := (i + 1) * n1 + j
			var c := (i + 1) * n1 + j + 1
			var d := i * n1 + j + 1
			idx[w] = a; idx[w + 1] = b; idx[w + 2] = c   # clockwise seen from above: Godot's front face
			idx[w + 3] = a; idx[w + 4] = c; idx[w + 5] = d
			w += 6
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_COLOR] = cols
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


static func _c(a) -> Color:
	var arr: Array = a
	return Color(float(arr[0]), float(arr[1]), float(arr[2]))
