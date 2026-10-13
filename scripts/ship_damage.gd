class_name ShipDamage
extends Node3D
## What a battered hull looks like from outside (ShipView.set_damage): scorch marks that spread over
## the skin as the hull goes, vapour venting from cracked plates once the tanks leak (below 50% hull),
## and sparks from torn wiring below 25%. A breached hull (0%) does all of it at once.
##
## The marks sit on the outward faces of the pressurised compartments, the same faces ShipSkin plates,
## picked in a fixed order for each ship so a dent stays where it was from one flight to the next.

const MAX_SCORCH := 16
const SCORCH_SIZE := 2.6
const VENT_FROM := 0.5        ## hull left at which the first vent opens (the fuel leak starts)
const SPARK_FROM := 0.25      ## and the first sparks

var sites: Array = []          ## {pos, normal} on the skin, in ShipView's frame, in the order they go
var damage := -1.0
var _scorches: Array[Decal] = []
var _vents: Array[CPUParticles3D] = []
var _sparks: Array[CPUParticles3D] = []
var _spark_wait := 0.0
var _rng := RandomNumberGenerator.new()

static var _scorch_tex: ImageTexture


## Where marks can go on `ship`: the middle of each outward face of a pressurised compartment, nudged
## off-centre, in an order shuffled the same way every time for this layout.
static func skin_sites(ship: ShipData) -> Array:
	var press := ShipSkin.pressurised_cells(ship)
	var out := []
	var rng := RandomNumberGenerator.new()
	rng.seed = 7919 + press.size() * 131
	var keys := press.keys()
	keys.sort()
	for c in keys:
		for d in ShipSkin.DIRS:
			if press.has(c + d):
				continue
			var axis := 0 if d.x != 0 else (1 if d.y != 0 else 2)
			var jitter := Vector3(rng.randf_range(-0.5, 0.5), rng.randf_range(-0.5, 0.5), rng.randf_range(-0.5, 0.5))
			jitter[axis] = 0.0
			out.append({"pos": Vector3(c) * ShipGrid.CELL + Vector3(d) * ShipSkin._outer() + jitter, "normal": Vector3(d), "key": rng.randf()})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.key) < float(b.key))
	return out


func setup(ship: ShipData) -> void:
	name = "Damage"
	sites = skin_sites(ship)
	_rng.seed = 4242
	for i in mini(sites.size(), MAX_SCORCH):
		var s: Dictionary = sites[i]
		var dc := Decal.new()
		dc.texture_albedo = scorch_texture()
		dc.size = Vector3(SCORCH_SIZE, 0.4, SCORCH_SIZE) * _rng.randf_range(0.7, 1.25)
		dc.position = s.pos
		dc.basis = _facing(s.normal).rotated(s.normal, _rng.randf() * TAU)
		dc.albedo_mix = 1.0
		dc.upper_fade = 0.1
		dc.lower_fade = 0.1
		dc.visible = false
		add_child(dc)
		_scorches.append(dc)
	for i in mini(sites.size(), 3):   # vents on the last-picked sites, sparks on the first few
		var s: Dictionary = sites[sites.size() - 1 - i]
		var v := _vent()
		v.position = s.pos
		v.basis = _facing(s.normal)
		add_child(v)
		_vents.append(v)
	for i in mini(sites.size(), 2):
		var s: Dictionary = sites[i]
		var sp := _spark()
		sp.position = s.pos + s.normal * 0.05
		sp.basis = _facing(s.normal)
		add_child(sp)
		_sparks.append(sp)


## A basis whose +Y is `n` (decals project down their -Y; particles here fly up their +Y).
static func _facing(n: Vector3) -> Basis:
	var up := n.normalized()
	var side := Vector3.FORWARD if absf(up.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT
	var x := side.cross(up).normalized()
	return Basis(x, up, x.cross(up).normalized())


## 0 pristine .. 1 breached. Shows marks in proportion; cheap to call every frame.
func set_damage(d: float) -> void:
	d = clampf(d, 0.0, 1.0)
	if absf(d - damage) < 0.004:
		return
	damage = d
	var hull := 1.0 - d
	var marks := roundi(d * float(_scorches.size()))
	for i in _scorches.size():
		_scorches[i].visible = i < marks
		_scorches[i].modulate = Color(1, 1, 1, clampf(0.8 + d * 0.4, 0.0, 1.0))
	var vents := 0
	if hull < VENT_FROM:
		vents = 1 if hull >= 0.25 else (2 if hull > 0.001 else 3)
	for i in _vents.size():
		_vents[i].emitting = i < vents
		_vents[i].initial_velocity_max = 2.0 + 4.0 * d
	for i in _sparks.size():
		_sparks[i].set_meta("live", hull < SPARK_FROM and (i == 0 or hull <= 0.001))


func _process(delta: float) -> void:
	_spark_wait -= delta
	if _spark_wait > 0.0:
		return
	_spark_wait = _rng.randf_range(0.6, 2.4) * (0.5 if damage >= 0.999 else 1.0)
	for sp in _sparks:
		if bool(sp.get_meta("live", false)) and _rng.randf() < 0.7:
			sp.restart()
			sp.emitting = true


static func _vent() -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = 120
	p.lifetime = 1.8
	p.local_coords = true          # the ship can be doing km/s: keep the plume with it
	p.emitting = false
	p.direction = Vector3.UP
	p.spread = 14.0
	p.gravity = Vector3.ZERO
	p.initial_velocity_min = 1.5
	p.initial_velocity_max = 4.0
	p.damping_min = 0.6
	p.damping_max = 1.2
	p.scale_amount_min = 0.5
	p.scale_amount_max = 0.9
	var grow := Curve.new()
	grow.add_point(Vector2(0, 0.3))
	grow.add_point(Vector2(1, 2.6))
	p.scale_amount_curve = grow
	var fade := Gradient.new()
	fade.set_color(0, Color(0.92, 0.95, 1.0, 0.35))
	fade.set_color(1, Color(0.92, 0.95, 1.0, 0.0))
	p.color_ramp = fade
	var q := QuadMesh.new()
	q.size = Vector2(1.1, 1.1)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = _puff_texture()
	q.material = m
	p.mesh = q
	return p


static func _spark() -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = 40
	p.lifetime = 0.55
	p.one_shot = true
	p.explosiveness = 0.92
	p.local_coords = true
	p.emitting = false
	p.direction = Vector3.UP
	p.spread = 70.0
	p.gravity = Vector3.ZERO
	p.initial_velocity_min = 3.0
	p.initial_velocity_max = 9.0
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.0
	var fade := Gradient.new()
	fade.set_color(0, Color(1.0, 0.9, 0.55, 1.0))
	fade.set_color(1, Color(1.0, 0.35, 0.08, 0.0))
	p.color_ramp = fade
	var b := BoxMesh.new()
	b.size = Vector3(0.05, 0.05, 0.4)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.vertex_color_use_as_albedo = true
	b.material = m
	p.mesh = b
	p.particle_flag_align_y = true
	return p


## A sooty blotch with ragged edges, made once.
static func scorch_texture() -> ImageTexture:
	if _scorch_tex != null:
		return _scorch_tex
	var n := 128
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var noise := FastNoiseLite.new()
	noise.seed = 11
	noise.frequency = 0.045
	noise.fractal_octaves = 4
	for y in n:
		for x in n:
			var u := (float(x) / (n - 1)) * 2.0 - 1.0
			var v := (float(y) / (n - 1)) * 2.0 - 1.0
			var r := sqrt(u * u + v * v)
			var nz := noise.get_noise_2d(x, y)
			var edge := clampf((1.0 - r + nz * 0.55) * 1.6, 0.0, 1.0)
			var core := clampf((0.45 - r + nz * 0.3) * 3.0, 0.0, 1.0)
			var a := minf(1.0, edge * 1.3) * (0.8 + 0.2 * core)
			var tone := lerpf(0.16, 0.035, core)   # browned at the rim, black in the middle
			img.set_pixel(x, y, Color(tone * 1.15, tone * 0.95, tone * 0.8, a))
	_scorch_tex = ImageTexture.create_from_image(img)
	return _scorch_tex


static func _puff_texture() -> ImageTexture:
	var n := 32
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	for y in n:
		for x in n:
			var r := Vector2(x - n * 0.5 + 0.5, y - n * 0.5 + 0.5).length() / (n * 0.5)
			img.set_pixel(x, y, Color(1, 1, 1, clampf(1.0 - r, 0.0, 1.0) ** 2))
	return ImageTexture.create_from_image(img)
