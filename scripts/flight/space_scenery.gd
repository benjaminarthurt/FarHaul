class_name SpaceScenery
extends RefCounted
## Space around the ship: the sky, sun and ambient light, the dust motes that show motion, and the
## station the ship docks at with its rings, lights and name.

var sc: FlightScene   ## the scene this works on


func _init(scene: FlightScene) -> void:
	sc = scene


func _build_world() -> void:
	var env := Environment.new()
	sc.world_env = env
	env.background_mode = Environment.BG_SKY
	env.sky = SpaceSky.make()
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.glow_intensity = 0.8
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.4, 0.45, 0.58)
	env.ambient_light_energy = 0.55
	var we := WorldEnvironment.new()
	we.environment = env
	sc.add_child(we)
	sc.sun = DirectionalLight3D.new()
	sc.sun.rotation_degrees = Vector3(-30, 40, 0)
	sc.sun.light_color = Color(1.0, 0.94, 0.85)
	sc.sun.light_energy = 1.4
	sc.add_child(sc.sun)
	sc.station = sc._make_station()
	sc.add_child(sc.station)
	_build_planet()
	# Drifting markers give the eye something to measure speed against.
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.7, 0.8, 1.0)
	for i in 160:
		var m := MeshInstance3D.new()
		var s := SphereMesh.new()
		s.radius = 0.35
		s.height = 0.7
		s.radial_segments = 6
		s.rings = 3
		s.material = mat
		m.mesh = s
		m.position = Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)).normalized() * rng.randf_range(60.0, 700.0)
		sc.add_child(m)
		sc.sparks.append(m)


## The orbital dock at the origin: a spine, a spinning ring and a lit docking collar, in the system's
## style (SystemStyle): its colours and how heavy or slender it is from the architecture, extra
## structure from the port type, and how busy it is from the tier. Everything added stays behind the
## ring or outside it, so the approach to the collar along +Z stays clear.
var style := {}


func _make_station() -> Node3D:
	style = SystemStyle.for_site(String(Session.profile.get("port_id", "")))
	var root := Node3D.new()
	var base: Color = style.get("station", Color(0.42, 0.46, 0.52))
	var steel := Interiors.flat(base.darkened(0.1), 0.7, 0.3)
	var dark := Interiors.flat(base.darkened(0.25), 0.7, 0.3)
	var column := float(style.get("column", 0.35))
	var spine := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 5.0
	cyl.bottom_radius = 5.0
	cyl.height = 60.0
	cyl.material = steel
	spine.mesh = cyl
	spine.rotation_degrees.x = 90.0
	root.add_child(spine)
	var ring := Node3D.new()                       # spins about the spine (Z); everything on it is in the XY plane
	root.add_child(ring)
	var band := MeshInstance3D.new()
	var tor := TorusMesh.new()                     # a torus lies flat by default: stand it up to face along Z
	tor.inner_radius = sc.STATION_RADIUS - 3.0 * (0.6 + column)
	tor.outer_radius = sc.STATION_RADIUS
	tor.material = dark
	band.mesh = tor
	band.rotation_degrees.x = 90.0
	ring.add_child(band)
	ring.set_meta("spin", true)
	var spoke_w := 0.6 + 2.2 * column
	for k in 4:
		var spoke := MeshInstance3D.new()
		var b := BoxMesh.new()
		b.size = Vector3(spoke_w, sc.STATION_RADIUS, spoke_w)
		b.material = steel
		spoke.mesh = b
		spoke.rotation.z = k * PI / 2.0
		spoke.position = Vector3(sin(k * PI / 2.0), -cos(k * PI / 2.0), 0) * sc.STATION_RADIUS * 0.5
		ring.add_child(spoke)
	var lamp_col: Color = style.get("lamp", Color(1.0, 0.85, 0.5))
	for k in 16:      # lit windows around the ring
		var win := MeshInstance3D.new()
		var wb := BoxMesh.new()
		wb.size = Vector3(2.4, 1.2, 3.2)
		wb.material = Interiors.glow(lamp_col.lerp(Color(1.0, 0.85, 0.5), 0.4), 1.4)
		win.mesh = wb
		var a := k * TAU / 16.0
		win.position = Vector3(cos(a), sin(a), 0) * (sc.STATION_RADIUS - 1.5)
		win.rotation.z = a
		ring.add_child(win)
	var collar := MeshInstance3D.new()
	var ct := TorusMesh.new()
	ct.inner_radius = 6.2
	ct.outer_radius = 7.2
	ct.material = Interiors.glow((style.get("trim", Color(0.35, 0.85, 1.0)) as Color).lerp(Color(0.35, 0.85, 1.0), 0.3), 1.6)
	collar.mesh = ct
	collar.rotation_degrees.x = 90.0
	collar.position = Vector3(0, 0, 32)
	root.add_child(collar)
	_build_modules(root, steel, dark)
	_build_architecture(root, steel, dark)
	_build_port_type(root, steel, dark)
	var label := Label3D.new()
	label.text = String(Session.port().get("name", "DOCK")).to_upper()
	label.font_size = 96
	label.pixel_size = 0.07
	label.outline_size = 12
	label.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	label.position = Vector3(0, sc.STATION_RADIUS + 16.0, -10.0)
	label.modulate = (style.get("accent", Color(1.0, 0.8, 0.4)) as Color).lerp(Color(1.0, 0.8, 0.4), 0.35).lightened(0.15)
	root.add_child(label)
	sc.station_label = label
	return root


## How many of a thing a station of this tier has: `by_tier` lists core..extreme frontier.
func _count(by_tier: Array) -> int:
	var order := ["core", "developed", "outer", "frontier", "extreme_frontier"]
	return int(by_tier[clampi(order.find(String(style.get("tier", "developed"))), 0, by_tier.size() - 1)])


## The species' hand: heavy bands, slender masts, bulbs, stacked discs, or bolted-on oddments.
func _build_architecture(root: Node3D, steel: Material, dark: Material) -> void:
	var accent: Color = style.get("accent", Color(1.0, 0.6, 0.2))
	var site := String(style.get("site_kind", "port"))
	var at_port := not site in ["depot", "belt", "moon"]   # out-sites keep the space aft for their own works
	match String(style.get("architecture", "colonial")):
		"kesh":   # massive: a second, heavier rear block and orange warning bands round the spine
			if at_port:
				_solid(root, Vector3(0, 0, -58), Vector3(22, 22, 10), dark)
			for z in [-24.0, -12.0, 12.0, 24.0]:
				var t := MeshInstance3D.new()
				var tm := TorusMesh.new()
				tm.inner_radius = 4.9
				tm.outer_radius = 5.6
				tm.material = Interiors.flat(accent, 0.6)
				t.mesh = tm
				t.rotation_degrees.x = 90.0
				t.position = Vector3(0, 0, z)
				root.add_child(t)
		"ilyan":   # slender: a second fine ring behind the first and a long needle mast aft
			var r2 := MeshInstance3D.new()
			var tm := TorusMesh.new()
			tm.inner_radius = sc.STATION_RADIUS * 0.7 - 0.6
			tm.outer_radius = sc.STATION_RADIUS * 0.7
			tm.material = Interiors.glow(accent, 1.2)
			r2.mesh = tm
			r2.rotation_degrees.x = 90.0
			r2.position = Vector3(0, 0, -16)
			root.add_child(r2)
			if site == "belt":
				return
			var mast := MeshInstance3D.new()
			var mc := CylinderMesh.new()
			mc.top_radius = 0.2
			mc.bottom_radius = 1.0
			mc.height = 60.0
			mc.material = steel
			mast.mesh = mc
			mast.rotation_degrees.x = 90.0
			mast.position = Vector3(0, 0, -80)
			root.add_child(mast)
			_lamp(root, Vector3(0, 0, -110), accent, 1.6)
		"vey":   # rounded: habitat bulbs clustered behind the ring, lit sea-green
			for k in 3:
				var a := k * TAU / 3.0 + 0.5
				var at := Vector3(cos(a) * 9.0, sin(a) * 9.0, -18.0)
				var mi := MeshInstance3D.new()
				var sp := SphereMesh.new()
				sp.radius = 5.5
				sp.height = 11.0
				sp.material = steel
				mi.mesh = sp
				mi.position = at
				root.add_child(mi)
				boxes.append(AABB(at - Vector3.ONE * 5.0, Vector3.ONE * 10.0))
				_lamp(root, at + Vector3(cos(a), sin(a), 0) * 5.6, accent, 1.2)
		"orun":   # stacked: three thick discs on the spine behind the ring, with amber windows
			for k in 3:
				var z := -12.0 - k * 6.0
				var mi := MeshInstance3D.new()
				var cm := CylinderMesh.new()
				cm.top_radius = 13.0 - k * 1.5
				cm.bottom_radius = 13.0 - k * 1.5
				cm.height = 3.2
				cm.material = dark if k % 2 == 0 else steel
				mi.mesh = cm
				mi.rotation_degrees.x = 90.0
				mi.position = Vector3(0, 0, z)
				root.add_child(mi)
				var r := 13.0 - k * 1.5
				boxes.append(AABB(Vector3(-r, -r, z - 1.6), Vector3(r * 2.0, r * 2.0, 3.2)))
				for w in 10:
					var a := w * TAU / 10.0
					_lamp(root, Vector3(cos(a) * r, sin(a) * r, z), accent, 0.7)
		"patchwork":   # oddments from every yard bolted on wherever they would fit
			var rng := RandomNumberGenerator.new()
			rng.seed = hash(String(style.get("system_id", "")) + "|patch")
			var tints := [Color(0.55, 0.35, 0.3), Color(0.3, 0.45, 0.55), Color(0.5, 0.5, 0.3), Color(0.35, 0.5, 0.4), Color(0.5, 0.4, 0.55)]
			for k in (7 if at_port else 3):
				var a := rng.randf() * TAU
				var size := Vector3(rng.randf_range(3, 7), rng.randf_range(3, 7), rng.randf_range(4, 10))
				_solid(root, Vector3(cos(a) * rng.randf_range(10, 15), sin(a) * rng.randf_range(10, 15), rng.randf_range(-50, -24)), size,
						Interiors.flat(tints[k % tints.size()], 0.8))


## What the port is for, in its shape: container yards, smelters, docking arms, a busy berth ring,
## the scaffold of a frontier dock, or the tether of a transfer platform down to the surface. A
## system's other sites are their own kind: a fuel depot's tanks, a belt works' captured asteroid,
## a moon station's dishes and landers.
func _build_port_type(root: Node3D, steel: Material, dark: Material) -> void:
	var t := String(style.get("port_type", "orbital_port"))
	if t.contains("freight"):   # a long container yard aft
		var cols := [Color(0.7, 0.35, 0.2), Color(0.25, 0.4, 0.6), Color(0.6, 0.55, 0.25), Color(0.35, 0.5, 0.35)]
		for j in _count([6, 5, 4, 3, 2]):
			for side in [-1.0, 1.0]:
				_solid(root, Vector3(side * 5.0, 0, -54 - j * 5.0), Vector3(4.0, 8.0, 4.4), Interiors.flat(cols[(j + int(side + 1.0)) % 4], 0.8))
		_solid(root, Vector3(0, 0, -54 - _count([6, 5, 4, 3, 2]) * 2.5), Vector3(1.4, 1.4, _count([6, 5, 4, 3, 2]) * 5.0 + 4.0), dark)
	if t.contains("industrial"):   # smelter stacks with glowing vents, and radiator fins
		for side in [-1.0, 1.0]:
			_solid(root, Vector3(side * 14.0, 12.0, -44), Vector3(6, 14, 6), dark)
			_lamp(root, Vector3(side * 14.0, 19.5, -44), Color(1.0, 0.45, 0.1), 3.0)
			for f in 4:
				_solid(root, Vector3(side * 14.0, -6.0 - f * 3.0, -44), Vector3(18, 0.3, 6), Interiors.flat(Color(0.45, 0.3, 0.28), 0.6, 0.5))
	if t.contains("trade"):   # a berth ring out behind, busy with visiting ships
		var cols := [Color(0.7, 0.35, 0.2), Color(0.25, 0.4, 0.6), Color(0.6, 0.55, 0.25), Color(0.35, 0.5, 0.35), Color(0.55, 0.4, 0.55)]
		var n := _count([10, 8, 6, 5, 4])
		for k in n:
			var a := k * TAU / n
			var at := Vector3(cos(a), sin(a), 0) * 20.0 + Vector3(0, 0, -62)
			_solid(root, at, Vector3(3.5, 3.5, 8.0), Interiors.flat(cols[k % cols.size()], 0.7))
			_lamp(root, at + Vector3(0, 0, 4.3), Color(1.0, 0.7, 0.3), 0.6)
		var br := MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = 17.0
		tm.outer_radius = 18.5
		tm.material = steel
		br.mesh = tm
		br.rotation_degrees.x = 90.0
		br.position = Vector3(0, 0, -62)
		root.add_child(br)
	if t.contains("transfer"):   # docking arms radiating aft, each with its own collar
		for k in 4:
			var a := PI * 0.25 + k * PI * 0.5
			var dir := Vector3(cos(a), sin(a), 0)
			_solid(root, dir * 15.0 + Vector3(0, 0, -36), Vector3(absf(dir.x) * 14.0 + 2.0, absf(dir.y) * 14.0 + 2.0, 2.0), steel)
			var c := MeshInstance3D.new()
			var ct := TorusMesh.new()
			ct.inner_radius = 2.2
			ct.outer_radius = 2.8
			ct.material = Interiors.glow(Color(0.35, 0.85, 1.0), 1.4)
			c.mesh = ct
			c.position = dir * 23.0 + Vector3(0, 0, -36)
			c.rotation.z = a
			root.add_child(c)
	if t == "fuel_depot":   # banded propellant spheres round the spine, and a fuelling boom
		var accent: Color = style.get("accent", Color(0.9, 0.6, 0.2))
		var tank := Interiors.flat((style.get("station", Color(0.6, 0.6, 0.62)) as Color).lightened(0.15), 0.5, 0.3)
		for k in 6:
			var a := k * TAU / 6.0 + (0.5 if k % 2 == 1 else 0.0)
			var at := Vector3(cos(a) * 12.0, sin(a) * 12.0, -44.0 if k % 2 == 0 else -56.0)
			var mi := MeshInstance3D.new()
			var sp := SphereMesh.new()
			sp.radius = 5.0
			sp.height = 10.0
			sp.material = tank
			mi.mesh = sp
			mi.position = at
			root.add_child(mi)
			boxes.append(AABB(at - Vector3.ONE * 4.6, Vector3.ONE * 9.2))
			var band := MeshInstance3D.new()
			var tm := TorusMesh.new()
			tm.inner_radius = 4.9
			tm.outer_radius = 5.3
			tm.material = Interiors.flat(accent, 0.6)
			band.mesh = tm
			band.position = at
			root.add_child(band)
		_solid(root, Vector3(20, 0, -30), Vector3(26, 1.4, 1.4), steel)   # the fuelling boom
		_lamp(root, Vector3(33.5, 0, -30), Color(0.3, 1.0, 0.4), 1.2)
	if t == "belt_works":   # a captured asteroid, a smelter and a conveyor between them, rubble about
		var rock_col := Color(0.42, 0.38, 0.34)
		var rock := MeshInstance3D.new()
		var sp := SphereMesh.new()
		sp.radius = 15.0
		sp.height = 30.0
		sp.radial_segments = 14
		sp.rings = 8
		sp.material = SurfaceTextures.rock_material(rock_col)
		rock.mesh = sp
		rock.scale = Vector3(1.25, 0.85, 1.0)
		rock.rotation = Vector3(0.3, 0.7, 0.2)
		rock.position = Vector3(0, -4, -88)
		root.add_child(rock)
		boxes.append(AABB(Vector3(-17, -17, -103), Vector3(34, 26, 30)))
		_solid(root, Vector3(0, -2, -58), Vector3(12, 10, 12), dark)   # the smelter
		_lamp(root, Vector3(0, 4, -58), Color(1.0, 0.45, 0.1), 2.6)
		_solid(root, Vector3(0, -9, -66), Vector3(2.4, 1.2, 26), steel)   # conveyor to the rock
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(String(style.get("system_id", "")) + "|rubble")
		for k in 18:
			var r := MeshInstance3D.new()
			var rs := SphereMesh.new()
			rs.radius = rng.randf_range(0.8, 3.0)
			rs.height = rs.radius * 2.0
			rs.radial_segments = 6
			rs.rings = 3
			rs.material = sp.material
			r.mesh = rs
			var a := rng.randf() * TAU
			r.position = Vector3(cos(a) * rng.randf_range(22, 45), sin(a) * rng.randf_range(22, 45), rng.randf_range(-110, -50))
			root.add_child(r)
	if t == "moon_station":   # dishes listening to the base below, and landers on their cradles
		for side in [-1.0, 1.0]:
			_solid(root, Vector3(side * 6.0, 14.0, -40), Vector3(0.8, 12.0, 0.8), steel)
			var dish := MeshInstance3D.new()
			var cm := CylinderMesh.new()
			cm.top_radius = 5.0
			cm.bottom_radius = 1.0
			cm.height = 2.0
			cm.material = Interiors.flat(Color(0.85, 0.86, 0.88), 0.5)
			dish.mesh = cm
			dish.position = Vector3(side * 6.0, 21.0, -40)
			dish.rotation = Vector3(0.6, 0, side * 0.4)
			root.add_child(dish)
			var lander := Interiors.flat((style.get("accent", Color(0.9, 0.6, 0.2)) as Color).darkened(0.2), 0.7)
			_solid(root, Vector3(side * 14.0, -6.0, -36), Vector3(5.0, 4.0, 5.0), lander)
			for lx in [-1.8, 1.8]:
				_solid(root, Vector3(side * 14.0 + lx, -9.0, -36), Vector3(0.3, 2.4, 0.3), steel)
			_lamp(root, Vector3(side * 14.0, -3.6, -36), Color(1.0, 0.8, 0.4), 0.7)
	if t.contains("frontier"):   # bare scaffold round the rear module, still being built out
		var sm := Interiors.flat(Color(0.55, 0.5, 0.4), 0.8, 0.4)
		for x in [-11.0, 11.0]:
			for y in [-11.0, 11.0]:
				_solid(root, Vector3(x, y, -36), Vector3(0.5, 0.5, 18), sm)
		for z in [-28.0, -36.0, -44.0]:
			for y in [-11.0, 11.0]:
				_solid(root, Vector3(0, y, z), Vector3(22, 0.4, 0.4), sm)
		_lamp(root, Vector3(11, 11, -27), Color(1.0, 0.6, 0.2), 1.0)


## Solid boxes a part of the station takes up, for the flight model (station frame).
var boxes: Array[AABB] = []


func _solid(root: Node3D, pos: Vector3, size: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	b.material = mat
	mi.mesh = b
	mi.position = pos
	root.add_child(mi)
	boxes.append(AABB(pos - size * 0.5, size))
	return mi


func _lamp(root: Node3D, pos: Vector3, col: Color, size := 0.8) -> void:
	var mi := MeshInstance3D.new()
	var sp := SphereMesh.new()
	sp.radius = size * 0.5
	sp.height = size
	sp.radial_segments = 8
	sp.rings = 4
	sp.material = Interiors.glow(col, 3.0)
	mi.mesh = sp
	mi.position = pos
	root.add_child(mi)


## The working station behind the ring, away from the docking collar at +Z: a rear module with cargo
## stacks round it, two long solar wings, a few small ships berthed on the ring, and navigation
## lights at the extremities so it reads at a distance.
func _build_modules(root: Node3D, steel: Material, dark: Material) -> void:
	var hull := Interiors.flat(style.get("station", Color(0.5, 0.52, 0.56)), 0.7, 0.3)
	SurfaceTextures.apply_panel(hull)
	var panel_mat := Interiors.flat(Color(0.12, 0.16, 0.3), 0.3, 0.6)
	_solid(root, Vector3(0, 0, -36), Vector3(16, 16, 12), hull)                     # rear module
	_solid(root, Vector3(0, 0, -46), Vector3(8, 8, 8), dark)
	var crate_cols := [Color(0.7, 0.35, 0.2), Color(0.25, 0.4, 0.6), Color(0.6, 0.55, 0.25), Color(0.35, 0.5, 0.35)]
	var at_port := not String(style.get("site_kind", "port")) in ["depot", "belt", "moon"]
	for k in (4 if at_port else 0):   # cargo stacks on the rear module's sides (ports only)
		var a := k * PI * 0.5
		var out := Vector3(cos(a), sin(a), 0)
		for j in _count([3, 3, 2, 2, 1]):
			_solid(root, out * 11.0 + Vector3(0, 0, -32 - j * 4.2) + out.cross(Vector3(0, 0, 1)) * 0.0,
					Vector3(absf(out.x) * 5.0 + absf(out.y) * 6.0 + 0.1, absf(out.y) * 5.0 + absf(out.x) * 6.0 + 0.1, 3.8),
					Interiors.flat(crate_cols[(k + j) % 4], 0.8))
	for side in ([-1.0, 1.0] if _count([2, 2, 2, 1, 1]) == 2 else [1.0]):   # solar wings (one at the frontier)
		_solid(root, Vector3(side * 26.0, 0, -40), Vector3(28, 0.8, 1.2), steel)
		for p in 3:
			_solid(root, Vector3(side * (18.0 + p * 10.0), 0, -40), Vector3(9.0, 0.3, 16.0), panel_mat)
		_lamp(root, Vector3(side * 41.0, 0, -40), Color(1.0, 0.25, 0.2) if side < 0.0 else Color(0.3, 1.0, 0.4), 1.4)
	for k in (_count([4, 3, 2, 1, 1]) if at_port else 1):   # small ships berthed on the ring's outer face
		var a := PI * 0.25 + k * PI * 0.5
		var at := Vector3(cos(a), sin(a), 0) * (sc.STATION_RADIUS + 4.5) + Vector3(0, 0, -2.0)
		_solid(root, at, Vector3(4.0, 4.0, 9.0), Interiors.flat(crate_cols[k], 0.7))
		_lamp(root, at + Vector3(0, 0, 4.8), Color(1.0, 0.7, 0.3), 0.7)
	for z in [-52.0, 30.0]:   # white strobes fore and aft
		_lamp(root, Vector3(0, 6.0, z), Color(1, 1, 1), 1.0)
	for k in 8:   # floodlights round the rear module
		var a := k * TAU / 8.0
		_lamp(root, Vector3(cos(a) * 8.4, sin(a) * 8.4, -29.8), Color(1.0, 0.9, 0.7), 0.6)


## The system's world, far off beyond the station.
func _build_planet() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(Session.system_id())
	var hues := [Color(0.35, 0.55, 0.85), Color(0.7, 0.55, 0.38), Color(0.45, 0.62, 0.45), Color(0.75, 0.72, 0.68), Color(0.6, 0.4, 0.35)]
	var planet := MeshInstance3D.new()
	var sph := SphereMesh.new()
	sph.radius = 1400.0
	sph.height = 2800.0
	sph.radial_segments = 64
	sph.rings = 32
	var pm := StandardMaterial3D.new()
	pm.albedo_color = (style.get("planet", hues[rng.randi() % hues.size()]) as Color).darkened(0.2) if not style.is_empty() \
			else (hues[rng.randi() % hues.size()] as Color).darkened(0.45)
	pm.albedo_texture = SurfaceTextures.regolith()
	pm.uv1_scale = Vector3(8, 4, 1)
	pm.roughness = 1.0
	pm.rim_enabled = true
	pm.rim = 0.7
	pm.rim_tint = 0.3
	sph.material = pm
	planet.mesh = sph
	# Off to one side of the sun, so it shows a lit face and a night side rather than a full disc.
	var to_sun := -(sc.sun.global_transform.basis.z if sc.sun.is_inside_tree() else Basis.from_euler(sc.sun.rotation) * Vector3(0, 0, 1))
	var dir := (Basis(Vector3.UP, deg_to_rad(105.0)) * Vector3(to_sun.x, 0, to_sun.z).normalized()).normalized()
	planet.position = dir * 3600.0 + Vector3(0, -1400.0, 0)
	planet.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	sc.add_child(planet)
	sc.planet = planet
	var pt := String(style.get("port_type", ""))
	if pt.begins_with("surface") or pt.begins_with("floating"):   # a transfer platform: its tether runs down to the world
		_tether(planet.position)


## A space elevator's cable from the rear of the station down to the world's surface. It hangs from
## the planet node, so it hides with the world when you are down on a moon.
func _tether(world_centre: Vector3) -> void:
	var from := Vector3(0, -6, -36)
	var to := world_centre + (from - world_centre).normalized() * 1400.0
	var mi := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = 0.6
	c.bottom_radius = 0.6
	c.height = from.distance_to(to)
	c.radial_segments = 8
	c.material = Interiors.flat((style.get("station", Color(0.5, 0.5, 0.5)) as Color).darkened(0.2), 0.6, 0.4)
	mi.mesh = c
	sc.planet.add_child(mi)
	mi.position = (from + to) * 0.5 - world_centre
	var dir := (to - from).normalized()
	mi.basis = Basis(Quaternion(Vector3.UP, dir))
	for k in 12:   # marker lamps down the cable
		_lamp(sc.planet, from.lerp(to, float(k + 1) / 40.0) - world_centre, Color(1.0, 0.3, 0.2), 1.6)
