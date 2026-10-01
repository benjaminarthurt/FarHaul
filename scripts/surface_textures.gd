class_name SurfaceTextures
extends RefCounted
## Procedural surface detail, generated in code so there are no image assets to manage.
## Textures are greyscale-ish and get tinted by the material's colour. They are mapped in object
## space (triplanar), so panel size on screen stays the same however big a box is.

const PANEL_TILE_M := 1.5  # one panel texture covers this many metres
const HAZARD_TILE_M := 0.6

static var _panel: ImageTexture
static var _hazard: ImageTexture


## Riveted, scuffed plating with seam lines.
static func panel() -> ImageTexture:
	if _panel != null:
		return _panel
	var n := 128
	var img := Image.create(n, n, false, Image.FORMAT_RGB8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for y in n:
		for x in n:
			var v := 0.90 + rng.randf_range(-0.035, 0.035)  # fine grain
			if x < 3 or y < 3 or x >= n - 2 or y >= n - 2:
				v *= 0.55  # seam
			elif x < 5 or y < 5:
				v *= 1.06  # lit lip next to the seam
			img.set_pixel(x, y, Color(v, v, v))
	for corner in [Vector2i(12, 12), Vector2i(n - 13, 12), Vector2i(12, n - 13), Vector2i(n - 13, n - 13)]:
		_dot(img, corner, 3.5, 0.62)  # rivets
		_dot(img, corner + Vector2i(-1, -1), 1.5, 1.08)
	for i in 14:  # scratches and scuffs
		var p := Vector2(rng.randf_range(8, n - 8), rng.randf_range(8, n - 8))
		var dir := Vector2.from_angle(rng.randf_range(0.0, TAU))
		var length := rng.randf_range(5.0, 18.0)
		var shade := rng.randf_range(0.72, 0.85) if rng.randf() < 0.7 else 1.08
		for t in int(length):
			var q := p + dir * t
			var qi := Vector2i(roundi(q.x), roundi(q.y))
			if qi.x > 4 and qi.y > 4 and qi.x < n - 3 and qi.y < n - 3:
				var c := img.get_pixelv(qi)
				img.set_pixelv(qi, Color(c.r * shade, c.g * shade, c.b * shade))
	for y in n:  # grime gathering along the bottom edge of each panel
		for x in n:
			var g := smoothstep(0.75, 1.0, float(y) / float(n)) * 0.12
			var c := img.get_pixel(x, y)
			img.set_pixel(x, y, Color(c.r - g, c.g - g, c.b - g))
	img.generate_mipmaps()
	_panel = ImageTexture.create_from_image(img)
	return _panel


## Yellow and black warning stripes.
static func hazard() -> ImageTexture:
	if _hazard != null:
		return _hazard
	var n := 64
	var img := Image.create(n, n, false, Image.FORMAT_RGB8)
	for y in n:
		for x in n:
			var band := int(floor(float(x + y) / 16.0)) % 2
			img.set_pixel(x, y, Color(0.92, 0.72, 0.10) if band == 0 else Color(0.07, 0.07, 0.08))
	img.generate_mipmaps()
	_hazard = ImageTexture.create_from_image(img)
	return _hazard


static func _dot(img: Image, c: Vector2i, r: float, shade: float) -> void:
	for dy in range(-ceili(r), ceili(r) + 1):
		for dx in range(-ceili(r), ceili(r) + 1):
			if Vector2(dx, dy).length() <= r:
				var p := c + Vector2i(dx, dy)
				var col := img.get_pixelv(p)
				img.set_pixelv(p, Color(col.r * shade, col.g * shade, col.b * shade))


## Give a material plating. Safe to call on any StandardMaterial3D.
static func apply_panel(mat: StandardMaterial3D) -> void:
	mat.albedo_texture = panel()
	mat.uv1_triplanar = true
	mat.uv1_scale = Vector3.ONE / PANEL_TILE_M


static func hazard_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = hazard()
	m.uv1_triplanar = true
	m.uv1_scale = Vector3.ONE / HAZARD_TILE_M
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	m.roughness = 0.8
	return m
