class_name StyleDressing
extends RefCounted
## Dresses a concourse in its system's style (SystemStyle): the architecture's structure and fittings,
## the tier's finish and wear, and props for what the system does. Everything solid stays within a
## metre of the north wall or the east end, clear of the desks, the walkways and the strollers' lanes.

static var _rng := RandomNumberGenerator.new()


static func dress(b: PlaceBuilder, sc: Node, st: Dictionary, w: float, d: float, h: float) -> void:
	_rng.seed = hash(String(st.system_id) + "|dress")
	var hw := w * 0.5
	var hd := d * 0.5
	match String(st.architecture):
		"kesh":
			_kesh(b, st, hw, hd, h)
		"ilyan":
			_ilyan(b, st, hw, hd, h)
		"vey":
			_vey(b, st, hw, hd, h)
		"orun":
			_orun(b, st, hw, hd, h)
		"patchwork":
			_patchwork(b, st, hw, hd, h)
		"human":
			_screens(b, st, hw, hd, h)
		"colonial":
			_colonial(b, st, hw, hd, h)
	if bool(st.get("banners", false)):
		_banners(b, st, hw, hd, h)
	_role_props(b, st, hw, hd)
	_site(b, st, hw, hd, h)
	if float(st.wear) >= 0.45:
		_wear(b, st, hw, hd, h, float(st.wear))


## Heavy steel columns along the window wall with orange bands, and hazard stripes along the walls.
static func _kesh(b: PlaceBuilder, st: Dictionary, hw: float, hd: float, h: float) -> void:
	var col := (st.wall as Color).darkened(0.2)
	for x in range(int(-hw) + 5, int(hw) - 2, 8):
		b._box(Vector3(x + 1.0, h * 0.5, -hd + 0.6), Vector3(0.9, h, 0.9), col)
		for y in [1.1, 2.3]:
			b._box(Vector3(x + 1.0, y, -hd + 0.6), Vector3(0.95, 0.18, 0.95), st.trim, false)
	for z in [-hd + 0.2, hd - 0.2]:
		var strip := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(hw * 2.0 - 0.6, 0.02, 0.35)
		bm.material = SurfaceTextures.hazard_material()
		strip.mesh = bm
		strip.position = Vector3(0, 0.012, z)
		b.sc.add_child(strip)


## A tall, light hall: slender columns, a gallery along the window wall and ribbons of teal light.
static func _ilyan(b: PlaceBuilder, st: Dictionary, hw: float, hd: float, h: float) -> void:
	for x in range(int(-hw) + 4, int(hw) - 2, 6):
		b._box(Vector3(x + 1.0, h * 0.5, -hd + 0.5), Vector3(0.18, h, 0.18), (st.wall as Color).lightened(0.2))
	b._box(Vector3(0, h * 0.62, -hd + 0.8), Vector3(hw * 2.0 - 0.6, 0.15, 1.5), (st.wall as Color).darkened(0.1), false)   # the gallery
	b._box(Vector3(0, h * 0.62 + 0.55, -hd + 1.5), Vector3(hw * 2.0 - 0.6, 0.9, 0.04), st.trim, false, true)   # its glowing rail
	for z in [-hd * 0.4, hd * 0.2]:
		b._box(Vector3(0, h - 0.6, z), Vector3(hw * 2.0 - 2.0, 0.05, 0.12), st.trim, false, true)


## Sea greens: a water channel glowing along the window wall, hanging plants and a humid haze.
static func _vey(b: PlaceBuilder, st: Dictionary, hw: float, hd: float, h: float) -> void:
	b._box(Vector3(0, 0.08, -hd + 0.75), Vector3(hw * 2.0 - 0.6, 0.16, 1.1), (st.wall as Color).darkened(0.3))   # the channel's kerb
	var water := MeshInstance3D.new()
	var wb := BoxMesh.new()
	wb.size = Vector3(hw * 2.0 - 0.8, 0.02, 0.9)
	var wm := StandardMaterial3D.new()
	wm.albedo_color = Color(0.15, 0.45, 0.5, 0.75)
	wm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	wm.emission_enabled = true
	wm.emission = Color(0.2, 0.7, 0.65)
	wm.emission_energy_multiplier = 0.6
	wm.metallic_specular = 1.0
	wm.roughness = 0.05
	wb.material = wm
	water.mesh = wb
	water.position = Vector3(0, 0.17, -hd + 0.75)
	b.sc.add_child(water)
	var leaf := b._mat(Color(0.2, 0.55, 0.4))
	for i in int(hw * 2.0 / 4.0):
		var mi := MeshInstance3D.new()
		var sp := SphereMesh.new()
		sp.radius = 0.4
		sp.height = 1.2
		sp.radial_segments = 8
		sp.rings = 4
		sp.material = leaf
		mi.mesh = sp
		mi.position = Vector3(-hw + 2.0 + i * 4.0, h - 0.9, -hd + 2.0 + float(i % 3) * 0.6)
		b.sc.add_child(mi)
	var env := _env(b.sc)
	if env != null:
		env.fog_enabled = true
		env.fog_light_color = Color(0.45, 0.65, 0.65)
		env.fog_density = 0.012


## Warm stone and low arches: ribs every four metres, and amber lamps.
static func _orun(b: PlaceBuilder, st: Dictionary, hw: float, hd: float, h: float) -> void:
	var stone := (st.wall as Color).darkened(0.15)
	for x in range(int(-hw) + 3, int(hw) - 1, 4):
		b._box(Vector3(x, h * 0.5, -hd + 0.35), Vector3(0.6, h, 0.5), stone)
		b._box(Vector3(x, h * 0.5, hd - 0.35), Vector3(0.6, h, 0.5), stone, false)
		b._box(Vector3(x, h - 0.35, 0), Vector3(0.6, 0.7, hd * 2.0), stone, false)
		for side in [-1.0, 1.0]:   # haunches where the rib meets the wall
			b._box(Vector3(x, h - 0.9, side * (hd - 0.9)), Vector3(0.6, 0.6, 1.2), stone, false)


## Every species' fittings side by side: odd coloured patches, vendors and hand-made signs.
static func _patchwork(b: PlaceBuilder, st: Dictionary, hw: float, hd: float, h: float) -> void:
	var tints := [Color(0.55, 0.35, 0.3), Color(0.3, 0.45, 0.55), Color(0.5, 0.5, 0.3), Color(0.35, 0.5, 0.4), Color(0.5, 0.4, 0.55)]
	for i in 10:
		var x := _rng.randf_range(-hw + 2.0, hw - 2.0)
		b._box(Vector3(x, h - 0.6, -hd + 0.17), Vector3(_rng.randf_range(1.5, 4.0), 1.0, 0.04), tints[i % tints.size()], false)
	var signs := ["NOODLES", "SPARES  ·  ALL HULLS", "HUMID ROOMS", "HEAVY-G BUNKS", "CREW WANTED", "CHARTS", "TEA", "SUIT REPAIR"]
	for i in signs.size():
		var l := Label3D.new()
		l.text = signs[i]
		l.font_size = 44
		l.pixel_size = 0.006
		l.modulate = tints[i % tints.size()].lightened(0.5)
		l.position = Vector3(-hw + 3.0 + i * (hw * 2.0 - 6.0) / signs.size(), h - 1.4 - 0.25 * (i % 2), -hd + 0.2)
		b.sc.add_child(l)
	b._box(Vector3(hw - 1.4, 0.55, -hd + 3.2), Vector3(1.0, 1.1, 1.8), Color(0.55, 0.3, 0.2))   # a vendor's cart
	b._box(Vector3(hw - 1.4, 1.6, -hd + 3.2), Vector3(1.2, 0.08, 2.0), st.trim, false)


## Clean information screens along the window wall.
static func _screens(b: PlaceBuilder, st: Dictionary, hw: float, hd: float, h: float) -> void:
	var lines := ["ARRIVALS", "DEPARTURES", "CUSTOMS  ·  DECLARE ALL CARGO", "PASSENGER TERMINAL"]
	for i in lines.size():
		var x := -hw + 4.0 + i * (hw * 2.0 - 8.0) / 3.0
		b._box(Vector3(x, h - 0.8, -hd + 0.2), Vector3(3.2, 0.9, 0.06), Color(0.05, 0.06, 0.08), false)
		var l := Label3D.new()
		l.text = lines[i]
		l.font_size = 40
		l.pixel_size = 0.005
		l.modulate = (st.trim as Color).lightened(0.3)
		l.position = Vector3(x, h - 0.8, -hd + 0.25)
		b.sc.add_child(l)


## Long banners in the accent colour hanging between the beams.
static func _banners(b: PlaceBuilder, st: Dictionary, hw: float, hd: float, h: float) -> void:
	for x in range(int(-hw) + 10, int(hw) - 6, 8):
		b._box(Vector3(x, h - 1.6, -hd + 1.0), Vector3(1.2, 2.6, 0.04), st.accent, false)
		b._box(Vector3(x, h - 2.85, -hd + 1.0), Vector3(1.2, 0.12, 0.05), (st.accent as Color).darkened(0.4), false)


## What the system does, stacked at the east end: crates, produce, ore, sample cases.
static func _role_props(b: PlaceBuilder, st: Dictionary, hw: float, hd: float) -> void:
	var role := String(st.role)
	var x := hw - 2.4
	match role:
		"industrial", "extraction":
			for i in 3:
				b._box(Vector3(x - i * 1.3, 0.6, -hd + 1.0), Vector3(1.1, 1.2, 1.1), [Color(0.5, 0.35, 0.2), Color(0.35, 0.4, 0.45), Color(0.55, 0.5, 0.25)][i])
			if role == "extraction":
				b._box(Vector3(x - 1.3, 1.5, -hd + 1.0), Vector3(1.0, 0.6, 1.0), Color(0.3, 0.27, 0.25))
		"agricultural":
			for i in 3:
				b._box(Vector3(x - i * 1.3, 0.45, -hd + 1.0), Vector3(1.1, 0.9, 0.9), Color(0.45, 0.35, 0.2))
				b._box(Vector3(x - i * 1.3, 0.95, -hd + 1.0), Vector3(1.0, 0.15, 0.8), Color(0.4, 0.65, 0.25), false)
		"research":
			for i in 2:
				b._box(Vector3(x - i * 1.6, 0.5, -hd + 1.0), Vector3(1.2, 1.0, 0.8), Color(0.2, 0.22, 0.26))
				b._box(Vector3(x - i * 1.6, 1.25, -hd + 1.0), Vector3(1.0, 0.5, 0.6), Color(0.4, 0.8, 1.0), false, true)
		"oceanic":   # live tanks for the catch
			for i in 2:
				b._box(Vector3(x - i * 1.7, 0.35, -hd + 1.0), Vector3(1.5, 0.7, 1.0), Color(0.25, 0.3, 0.32))
				b._box(Vector3(x - i * 1.7, 0.95, -hd + 1.0), Vector3(1.4, 0.5, 0.9), Color(0.2, 0.55, 0.65), false, true)
		"resource":   # ice and gas bottles
			for i in 4:
				b._cyl(Vector3(x - i * 0.9, 0.7, -hd + 1.0), 0.35, 1.4, [Color(0.75, 0.8, 0.85), Color(0.3, 0.55, 0.4)][i % 2])
		"boom_colony":   # prefab panels on a pallet, waiting for a buyer
			for i in 4:
				b._box(Vector3(x - 0.8, 0.12 + i * 0.12, -hd + 1.2), Vector3(2.6, 0.1, 1.4), Color(0.6, 0.55, 0.45).darkened(i * 0.06))
			b._box(Vector3(x - 3.2, 0.6, -hd + 1.0), Vector3(1.1, 1.2, 1.1), Color(0.55, 0.4, 0.2))
		"transit", "multispecies", "multispecies_hub":   # travellers' luggage heaped by the bar
			for i in 5:
				b._box(Vector3(x - (i % 3) * 0.7, 0.25 + (i / 3) * 0.45, -hd + 1.0 + (i % 2) * 0.4), Vector3(0.6, 0.4, 0.35),
						[Color(0.5, 0.25, 0.2), Color(0.25, 0.3, 0.5), Color(0.45, 0.45, 0.3)][i % 3])
		"capital":   # a planter of the home world's plants
			b._box(Vector3(x - 1.0, 0.35, -hd + 1.0), Vector3(3.0, 0.7, 1.0), (st.wall as Color).darkened(0.25))
			b._box(Vector3(x - 1.0, 0.8, -hd + 1.0), Vector3(2.8, 0.25, 0.8), (st.accent as Color).lerp(Color(0.25, 0.5, 0.3), 0.6), false)


## The system's working sites are dressed for their work, overhead or in the south-west corner by the
## gate where nothing else stands: a depot's fuel lines and gauges, a belt works' ore, a moon station's
## map of the base below and suit lockers.
static func _site(b: PlaceBuilder, st: Dictionary, hw: float, hd: float, h: float) -> void:
	var corner := Vector3(-hw + 1.3, 0, hd - 1.2)
	match String(st.get("site_kind", "port")):
		"depot":
			for k in 2:
				_pipe(b, Vector3(0, h - 0.45 - k * 0.32, hd * 0.35 + k * 0.4), hw * 2.0 - 0.6, 0.16, [Color(0.85, 0.7, 0.15), Color(0.3, 0.6, 0.35)][k])
			for i in 3:   # propellant gauges by the gate
				var x := corner.x + i * 0.8
				b._box(Vector3(x, 1.5, hd - 0.2), Vector3(0.6, 2.2, 0.06), Color(0.12, 0.13, 0.15), false)
				var level := 0.4 + 0.25 * i
				b._box(Vector3(x, 0.5 + 1.0 * level, hd - 0.25), Vector3(0.4, 2.0 * level, 0.04), Color(0.3, 1.0, 0.45), false, true)
		"belt":
			b._box(corner + Vector3(0, 0.3, 0), Vector3(1.6, 0.6, 1.4), Color(0.3, 0.3, 0.32))   # an ore chunk on its plinth
			var rock := MeshInstance3D.new()
			var sp := SphereMesh.new()
			sp.radius = 0.6
			sp.height = 1.0
			sp.radial_segments = 7
			sp.rings = 4
			sp.material = SurfaceTextures.rock_material(Color(0.5, 0.42, 0.36))
			rock.mesh = sp
			rock.position = corner + Vector3(0, 1.05, 0)
			rock.rotation = Vector3(0.4, 0.9, 0.1)
			b.sc.add_child(rock)
			_pipe(b, Vector3(0, h - 0.5, -hd * 0.1), hw * 2.0 - 0.6, 0.05, Color(0.3, 0.3, 0.3))   # the overhead conveyor's rail
			for x in range(int(-hw) + 3, int(hw) - 2, 3):
				b._box(Vector3(x, h - 0.85, -hd * 0.1), Vector3(0.8, 0.5, 0.6), Color(0.4, 0.33, 0.25), false)   # ore buckets
		"moon":
			b._box(Vector3(hw - 0.2, 1.9, -hd + 2.1), Vector3(0.06, 1.5, 2.4), Color(0.05, 0.06, 0.08), false)   # the base map, below the station's name
			b._box(Vector3(hw - 0.24, 1.9, -hd + 2.1), Vector3(0.04, 1.25, 2.1), Color(0.25, 0.55, 0.45), false, true)
			for i in 3:   # suit lockers by the gate
				b._box(corner + Vector3(i * 0.7, 1.0, 0.4), Vector3(0.6, 2.0, 0.4), Color(0.35, 0.4, 0.38))


## Hard use: stacked crates, stains on the floor, conduit run along the ceiling where panels came off,
## patched plates on the walls and a failing lamp or two.
static func _wear(b: PlaceBuilder, st: Dictionary, hw: float, hd: float, h: float, wear: float) -> void:
	for i in int(2 + wear * 4):
		var x := hw - 1.2 - (i % 3) * 1.15
		var y := 0.55 + (i / 3) * 1.1
		b._box(Vector3(x, y, hd - 4.2 + float(i % 2) * 0.1), Vector3(1.05, 1.05, 1.05), Color(0.42, 0.36, 0.26).darkened(_rng.randf() * 0.3), y < 1.0)
	var stain := StandardMaterial3D.new()
	stain.albedo_color = Color(0.05, 0.04, 0.03, 0.35)
	stain.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	stain.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	for i in int(wear * 8):   # stains, soft and see-through rather than black slabs
		var mi := MeshInstance3D.new()
		var pm := PlaneMesh.new()
		var r := _rng.randf_range(0.6, 1.4)
		pm.size = Vector2(r * _rng.randf_range(1.2, 2.2), r)
		pm.material = stain
		mi.mesh = pm
		mi.position = Vector3(_rng.randf_range(-hw + 2.0, hw - 2.0), 0.006 + i * 0.0005, _rng.randf_range(-hd + 1.0, hd - 1.0))
		mi.rotation.y = _rng.randf() * PI
		b.sc.add_child(mi)
	var pipe := (st.wall as Color).darkened(0.45)
	for k in 3:   # conduit along the ceiling
		_pipe(b, Vector3(0, h - 0.35 - k * 0.22, hd * 0.55 + k * 0.25), hw * 2.0 - 0.6, 0.08 + 0.03 * k, [pipe, Color(0.55, 0.3, 0.15), Color(0.3, 0.35, 0.3)][k])
	for i in int(wear * 10):   # patched wall plates in odd shades
		var x := _rng.randf_range(-hw + 2.0, hw - 2.0)
		var on_south := _rng.randf() < 0.5
		var y := _rng.randf_range(1.8, h - 1.0) if on_south else _rng.randf_range(0.35, 0.9)
		var z := (hd - 0.17) if on_south else (-hd + 0.17)
		b._box(Vector3(x, y, z), Vector3(_rng.randf_range(0.7, 1.6), _rng.randf_range(0.4, 0.9), 0.04), (st.wall as Color).darkened(_rng.randf_range(-0.15, 0.3)), false)
	var lamps: Array[OmniLight3D] = []
	for c in b.sc.get_children():
		if c is OmniLight3D:
			lamps.append(c)
	for i in int(wear * 3):
		if i < lamps.size():
			lamps[(i * 3 + 1) % lamps.size()].light_energy *= 0.25   # failing tubes


## A horizontal pipe along x, centred at `pos`.
static func _pipe(b: PlaceBuilder, pos: Vector3, length: float, radius: float, col: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = radius
	c.bottom_radius = radius
	c.height = length
	c.radial_segments = 10
	c.material = b._mat(col)
	mi.mesh = c
	mi.position = pos
	mi.rotation.z = PI * 0.5
	b.sc.add_child(mi)
	return mi


## A human colony's signature, by the work it does: the thing a pilot remembers the port by.
static func _colonial(b: PlaceBuilder, st: Dictionary, hw: float, hd: float, h: float) -> void:
	var trim: Color = st.trim
	match String(st.role):
		"industrial":   # an overhead crane rail down the hall, its trolley parked with a load on the hook
			var rz := -hd * 0.3
			b._box(Vector3(0, h - 0.45, rz), Vector3(hw * 2.0 - 1.0, 0.35, 0.3), Color(0.25, 0.25, 0.27), false)
			for x in range(int(-hw) + 6, int(hw) - 3, 8):
				b._box(Vector3(x, h - 0.2, rz), Vector3(0.25, 0.4, 0.25), Color(0.25, 0.25, 0.27), false)
			var tx := -hw * 0.45
			b._box(Vector3(tx, h - 0.75, rz), Vector3(1.2, 0.35, 0.7), trim, false)
			b._box(Vector3(tx, h - 1.3, rz), Vector3(0.04, 0.8, 0.04), Color(0.15, 0.15, 0.15), false)
			b._box(Vector3(tx, h - 2.0, rz), Vector3(2.4, 0.8, 1.0), Color(0.3, 0.42, 0.55), false)   # the load, well overhead
			for x in [-hw * 0.75, hw * 0.6]:
				b._box(Vector3(x, 1.1, -hd + 0.3), Vector3(0.5, 2.2, 0.25), trim, false)   # hazard posts on the window wall
		"agricultural":   # grow troughs hung from the ceiling under pink lamps, greenery spilling over
			for x in range(int(-hw) + 5, int(hw) - 3, 7):
				b._box(Vector3(x, h - 1.3, -hd * 0.45), Vector3(3.2, 0.3, 0.7), Color(0.4, 0.33, 0.24), false)
				b._box(Vector3(x, h - 1.08, -hd * 0.45), Vector3(3.0, 0.18, 0.55), Color(0.3, 0.6, 0.25), false)
				b._box(Vector3(x, h - 0.6, -hd * 0.45), Vector3(3.0, 0.06, 0.25), Color(0.95, 0.45, 0.85), false, true)
				var g := OmniLight3D.new()
				g.light_color = Color(1.0, 0.55, 0.9)
				g.light_energy = 0.35
				g.omni_range = 4.0
				g.position = Vector3(x, h - 0.9, -hd * 0.45)
				b.sc.add_child(g)
		"extraction":   # an ore track along the window wall, two loaded carts on it
			for z in [-hd + 0.55, -hd + 1.15]:
				b._box(Vector3(0, 0.04, z), Vector3(hw * 2.0 - 0.6, 0.08, 0.08), Color(0.45, 0.42, 0.4), false)
			for x in range(int(-hw) + 1, int(hw), 1):
				b._box(Vector3(x, 0.015, -hd + 0.85), Vector3(0.2, 0.03, 0.9), Color(0.25, 0.2, 0.15), false)
			for x in [-hw * 0.62, -hw * 0.5]:
				b._box(Vector3(x, 0.45, -hd + 0.85), Vector3(1.4, 0.7, 0.9), Color(0.35, 0.3, 0.28))
				b._box(Vector3(x, 0.85, -hd + 0.85), Vector3(1.2, 0.22, 0.75), Color(0.5, 0.42, 0.32), false)
		"research":   # sample cases along the window wall, each lit from within
			for x in range(int(-hw) + 6, int(hw) - 5, 9):
				b._box(Vector3(x, 0.5, -hd + 0.7), Vector3(1.4, 1.0, 0.7), Color(0.85, 0.87, 0.9))
				b._box(Vector3(x, 1.25, -hd + 0.7), Vector3(1.3, 0.5, 0.6), Color(0.6, 0.9, 1.0, 1.0), false, true)
				b._box(Vector3(x, 1.25, -hd + 0.7), Vector3(0.25, 0.3, 0.25), Color(0.9, 0.5, 0.3), false)
			b._box(Vector3(0, 0.3, hd - 0.17), Vector3(hw * 2.0 - 0.6, 0.06, 0.04), trim, false, true)
		"oceanic":   # tall tanks of sea water against the window, with fish in them
			var water := StandardMaterial3D.new()
			water.albedo_color = Color(0.15, 0.5, 0.65, 0.45)
			water.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			water.emission_enabled = true
			water.emission = Color(0.1, 0.45, 0.6)
			water.emission_energy_multiplier = 0.8
			var z := -hd + 0.9
			for xf in [-0.45, 0.6]:
				var x: float = xf * hw
				var tank := MeshInstance3D.new()
				var tb := BoxMesh.new()
				tb.size = Vector3(3.0, 2.6, 1.1)
				tb.material = water
				tank.mesh = tb
				tank.position = Vector3(x, 1.5, z)
				b.sc.add_child(tank)
				(b.sc.walker.furniture[0] as Array).append(Rect2(x - 1.5, z - 0.55, 3.0, 1.1))
				b._box(Vector3(x, 0.1, z), Vector3(3.1, 0.2, 1.2), Color(0.25, 0.3, 0.32), false)
				b._box(Vector3(x, 2.9, z), Vector3(3.1, 0.2, 1.2), Color(0.25, 0.3, 0.32), false)
				for f in 7:
					b._box(Vector3(x + _rng.randf_range(-1.3, 1.3), _rng.randf_range(0.6, 2.4), z + _rng.randf_range(-0.35, 0.35)),
							Vector3(0.3, 0.14, 0.06), [Color(1.0, 0.6, 0.2), Color(0.95, 0.9, 0.3), Color(0.9, 0.95, 1.0)][f % 3], false, true)
		"resource":   # frosted feed lines overhead with valve wheels
			for k in 3:
				_pipe(b, Vector3(0, h - 0.5 - k * 0.3, -hd * 0.2 + k * 0.35), hw * 2.0 - 0.6, 0.12, Color(0.78, 0.85, 0.9))
			for x in range(int(-hw) + 7, int(hw) - 3, 10):
				b._box(Vector3(x, h - 0.85, -hd * 0.2), Vector3(0.06, 0.55, 0.55), trim, false)
		"boom_colony":   # cargo containers turned into rooms, and strings of work lights
			for i in 2:
				var cx := -hw + 4.5 + i * 3.4
				b._box(Vector3(cx, 1.3, -hd + 1.05), Vector3(3.0, 2.6, 1.6), [Color(0.7, 0.35, 0.15), Color(0.2, 0.4, 0.55)][i])   # clear of the window lane
				b._box(Vector3(cx, 1.1, -hd + 1.87), Vector3(0.9, 1.9, 0.04), Color(0.1, 0.1, 0.1), false)
			for x in range(int(-hw) + 2, int(hw) - 1, 2):
				var sag := 0.35 * sin(float(x - int(-hw)) / 6.0 * PI) ** 2
				b._box(Vector3(x, h - 0.6 - sag, 0), Vector3(0.12, 0.12, 0.12), Color(1.0, 0.85, 0.5), false, true)
		"transit":   # a long departures board hung over the walkway
			var bx := -hw * 0.5   # clear of the freight board over the kiosk
			b._box(Vector3(bx, h - 1.2, 0.5), Vector3(8.0, 1.0, 0.12), Color(0.05, 0.05, 0.06), false)
			var l := Label3D.new()
			l.text = "DEPARTURES   ·   ALL BERTHS   ·   NO LOITERING"
			l.font_size = 48
			l.pixel_size = 0.006
			l.modulate = trim.lightened(0.3)
			l.position = Vector3(bx, h - 1.2, 0.43)
			l.rotation.y = PI
			b.sc.add_child(l)
			var l2 := l.duplicate() as Label3D
			l2.position = Vector3(bx, h - 1.2, 0.57)
			l2.rotation.y = 0
			b.sc.add_child(l2)


## A small room (the hab, the hut) in the system's style: a skirting light in its accent colour round
## the walls and one touch of the architecture, kept to the two free `corners`, the airlock at `gate`
## and the wall without a window (`back`: -1 north, +1 south).
static func dress_room(b: PlaceBuilder, st: Dictionary, w: float, d: float, h: float, corners: Array, gate: Vector3, back: float) -> void:
	_rng.seed = hash(String(st.get("system_id", "")) + "|room")
	var hw := w * 0.5
	var hd := d * 0.5
	var accent: Color = st.get("accent", Color(0.95, 0.65, 0.2))
	for z in [-hd + 0.17, hd - 0.17]:
		b._box(Vector3(0, 0.12, z), Vector3(w - 0.6, 0.06, 0.03), accent, false, true)
	for x in [-hw + 0.17, hw - 0.17]:
		b._box(Vector3(x, 0.12, 0), Vector3(0.03, 0.06, d - 0.6), accent, false, true)
	match String(st.get("architecture", "colonial")):
		"kesh":   # heavy corner columns, a hazard strip before the airlock
			for c in corners:
				b._box((c as Vector3) + Vector3(0, h * 0.5, 0), Vector3(0.8, h, 0.8), (st.wall as Color).darkened(0.25))
				b._box((c as Vector3) + Vector3(0, 1.2, 0), Vector3(0.85, 0.18, 0.85), accent, false)
			var strip := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3(0.5, 0.02, 2.4)
			bm.material = SurfaceTextures.hazard_material()
			strip.mesh = bm
			strip.position = gate + Vector3(1.0, 0.012, 0)
			b.sc.add_child(strip)
		"ilyan":   # ribbons of teal light overhead
			for z in [-d * 0.2, d * 0.2]:
				b._box(Vector3(0, h - 0.25, z), Vector3(w - 3.0, 0.05, 0.12), accent, false, true)
		"vey":   # hanging plants in the corners and a humid haze
			var leaf := b._mat(Color(0.2, 0.55, 0.4))
			for c in corners:
				var mi := MeshInstance3D.new()
				var sp := SphereMesh.new()
				sp.radius = 0.45
				sp.height = 1.2
				sp.material = leaf
				mi.mesh = sp
				mi.position = (c as Vector3) + Vector3(0, h - 0.9, 0)
				b.sc.add_child(mi)
			var env := _env(b.sc)
			if env != null:
				env.fog_enabled = true
				env.fog_light_color = Color(0.45, 0.65, 0.65)
				env.fog_density = 0.015
		"orun":   # stone ribs up the walls
			var stone := (st.wall as Color).darkened(0.15)
			for x in [-hw * 0.5, 0.0, hw * 0.5]:
				for z in [-hd + 0.3, hd - 0.3]:
					b._box(Vector3(x, h * 0.5, z), Vector3(0.5, h, 0.3), stone, false)
		"patchwork":   # hand-made signs
			var signs := ["TEA", "SUITS MENDED", "NO SPITTING"]
			for i in signs.size():
				var l := Label3D.new()
				l.text = signs[i]
				l.font_size = 40
				l.pixel_size = 0.0035
				l.modulate = [Color(1.0, 0.6, 0.5), Color(0.6, 0.85, 1.0), Color(1.0, 0.9, 0.5)][i]
				l.position = Vector3([-hw * 0.6, -hw * 0.3, hw * 0.6][i], h - 0.7, back * (hd - 0.2))
				l.rotation.y = PI if back > 0.0 else 0.0
				b.sc.add_child(l)
		"human":   # a clean screen of the base's notices
			b._box(Vector3(-hw * 0.5, h - 1.2, back * (hd - 0.19)), Vector3(2.4, 0.9, 0.06), Color(0.05, 0.06, 0.08), false)
			b._box(Vector3(-hw * 0.5, h - 1.2, back * (hd - 0.23)), Vector3(2.2, 0.75, 0.04), (st.trim as Color).darkened(0.7), false)
			var note := Label3D.new()
			note.text = "BASE NOTICES\nAIRLOCK DRILL 0600\nDUST WARNING: AMBER"
			note.font_size = 32
			note.pixel_size = 0.0035
			note.modulate = (st.trim as Color).lightened(0.4)
			note.position = Vector3(-hw * 0.5, h - 1.2, back * (hd - 0.26))
			note.rotation.y = PI if back > 0.0 else 0.0
			b.sc.add_child(note)


static func _env(sc: Node) -> Environment:
	for c in sc.get_children():
		if c is WorldEnvironment:
			return (c as WorldEnvironment).environment
	return null
