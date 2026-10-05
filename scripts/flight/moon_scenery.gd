class_name MoonScenery
extends Node3D
## Everything built on a moon's ground for the flight scene: the ground mesh, the base pad with its
## lights, domes and name, the mining camp, the wrecked lander, the outpost, ice mine and glass crater
## with their boulders (SurfaceSites), and the finds lying about (SurfaceFinds). It only builds; the
## flight scene and SurfaceOps decide what happens there. Can be built on its own in a test.

var system_id := ""
var terrain: SurfaceTerrain
var land_cfg: Dictionary = {}
var body: Dictionary = {}
var rocks: Array[Vector3] = []
var pad_label: Label3D            ## the base's name over its pad (hidden up close by the flight scene)
var find_nodes := {}              ## find id -> its node on the ground


## Build it all. `ground` is a prebuilt ground mesh (from a worker thread), or null to build one here.
func build(sys: String, t: SurfaceTerrain, cfg: Dictionary, b: Dictionary, boulders: Array[Vector3], ground: MeshInstance3D = null) -> void:
	system_id = sys
	terrain = t
	land_cfg = cfg
	body = b
	rocks = boulders
	var g := ground if ground != null else ground_mesh(t, cfg, b)
	g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF   # receives shadows; casting onto itself only made acne
	g.material_override = SurfaceTextures.ground_material()
	add_child(g)
	_build_base_pad()
	_build_camp()
	_build_wreck()
	_build_sites()
	_build_finds()


## The ground as a mesh, in this body's colours (safe to call on a worker thread).
static func ground_mesh(t: SurfaceTerrain, cfg: Dictionary, b: Dictionary) -> MeshInstance3D:
	var gc: Array = b.get("ground", [0.42, 0.41, 0.40])
	var rc: Array = b.get("rock", [0.30, 0.29, 0.28])
	return t.build_mesh(float(cfg.get("terrain_size_m", 4000.0)), int(cfg.get("terrain_cells", 96)),
			Color(float(gc[0]), float(gc[1]), float(gc[2])), Color(float(rc[0]), float(rc[1]), float(rc[2])))


## Where the mining camp's pad is on the ground.
func camp_pos() -> Vector3:
	var c := SurfaceFinds.camp_xz()
	return Vector3(c.x, terrain.height(c.x, c.y), c.y)


## A find taken: its crystal goes from the ground.
func hide_find(id: String) -> void:
	if find_nodes.has(id):
		(find_nodes[id] as Node3D).visible = false


func _build_base_pad() -> void:
	var pad_r := float(land_cfg.get("pad_radius_m", 25.0))
	var pad := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = pad_r
	disc.bottom_radius = pad_r + 1.0
	disc.height = 0.4
	disc.material = Interiors.flat(Color(0.33, 0.34, 0.36), 0.9)
	pad.mesh = disc
	pad.position = Vector3(0, 0.05, 0)
	add_child(pad)
	var ring := MeshInstance3D.new()
	var tor := TorusMesh.new()
	tor.inner_radius = pad_r - 1.4
	tor.outer_radius = pad_r - 0.6
	tor.material = SurfaceTextures.hazard_material()
	ring.mesh = tor
	ring.position = Vector3(0, 0.26, 0)
	ring.scale = Vector3(1, 0.05, 1)
	add_child(ring)
	for k in 12:   # edge lights, easy to find from above
		var lamp := MeshInstance3D.new()
		var b := BoxMesh.new()
		b.size = Vector3(0.6, 0.4, 0.6)
		b.material = Interiors.glow(Color(1.0, 0.75, 0.3) if k % 2 == 0 else Color(0.4, 0.9, 1.0), 2.0)
		lamp.mesh = b
		var ang := k * TAU / 12.0
		lamp.position = Vector3(cos(ang), 0, sin(ang)) * (pad_r + 1.5) + Vector3(0, 0.4, 0)
		add_child(lamp)
	var sys_name := String(Worlds.system(system_id).get("name", system_id.capitalize()))
	var label := Label3D.new()
	label.text = "%s MOON BASE  PAD 1" % sys_name.to_upper()
	label.font_size = 40
	label.fixed_size = true
	label.pixel_size = 0.0012
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.modulate = Color(1.0, 0.8, 0.4)
	label.position = Vector3(0, 14, 0)
	add_child(label)
	pad_label = label
	# The base itself: a few domes and boxes off to the side of the pad.
	var hab := Interiors.flat(Color(0.78, 0.77, 0.72), 0.7)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(system_id)
	for i in 6:
		var at := Vector3(rng.randf_range(45, 80), 0, rng.randf_range(-40, 40)).rotated(Vector3.UP, rng.randf() * TAU)
		var mi := MeshInstance3D.new()
		if i % 2 == 0:
			var dome := SphereMesh.new()
			dome.radius = rng.randf_range(5, 9)
			dome.height = dome.radius
			dome.is_hemisphere = true
			dome.material = hab
			mi.mesh = dome
		else:
			var box := BoxMesh.new()
			box.size = Vector3(rng.randf_range(6, 14), rng.randf_range(3, 6), rng.randf_range(6, 12))
			box.material = hab
			mi.mesh = box
			at.y = box.size.y * 0.5
		mi.position = at
		add_child(mi)
		var light := MeshInstance3D.new()
		var lb := BoxMesh.new()
		lb.size = Vector3(1.2, 0.5, 0.2)
		lb.material = Interiors.glow(Color(1.0, 0.85, 0.5), 1.5)
		light.mesh = lb
		light.position = at + Vector3(0, 2.0, 0)
		add_child(light)


## The mining camp: a rough pad marked with four flares, a drill rig, ore skips and a pressurised hut.
func _build_camp() -> void:
	var c := camp_pos()
	var root := Node3D.new()
	root.position = c
	add_child(root)
	var rough := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = 16.0
	disc.bottom_radius = 17.0
	disc.height = 0.2
	disc.material = Interiors.flat(Color(0.3, 0.27, 0.22), 1.0)
	rough.mesh = disc
	root.add_child(rough)
	for k in 4:
		var flare := MeshInstance3D.new()
		var b := BoxMesh.new()
		b.size = Vector3(0.4, 0.8, 0.4)
		b.material = Interiors.glow(Color(1.0, 0.35, 0.2), 2.2)
		flare.mesh = b
		var ang := k * TAU / 4.0 + PI * 0.25
		flare.position = Vector3(cos(ang), 0, sin(ang)) * 17.5 + Vector3(0, 0.4, 0)
		root.add_child(flare)
	var steel := Interiors.flat(Color(0.5, 0.45, 0.32), 0.6, 0.3)
	var rig := MeshInstance3D.new()   # drill derrick
	var tower := BoxMesh.new()
	tower.size = Vector3(3, 18, 3)
	tower.material = steel
	rig.mesh = tower
	rig.position = Vector3(40, 9, 12)
	root.add_child(rig)
	var hut := MeshInstance3D.new()
	var hb := BoxMesh.new()
	hb.size = Vector3(10, 4, 6)
	hb.material = Interiors.flat(Color(0.7, 0.62, 0.42), 0.8)
	hut.mesh = hb
	hut.position = Vector3(-35, 2, -18)
	root.add_child(hut)
	for i in 5:   # ore skips
		var skip := MeshInstance3D.new()
		var sb := BoxMesh.new()
		sb.size = Vector3(3, 2, 5)
		sb.material = Interiors.flat(Color(0.45, 0.3, 0.2), 0.9)
		skip.mesh = sb
		skip.position = Vector3(30 + i * 4.0, 1, -25)
		root.add_child(skip)
	var label := Label3D.new()
	label.text = "MINING CAMP  (no beacon: land by hand)"
	label.font_size = 36
	label.fixed_size = true
	label.pixel_size = 0.0012
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.modulate = Color(1.0, 0.55, 0.35)
	label.position = Vector3(0, 12, 0)
	root.add_child(label)


## A lander that came down hard near the camp: a broken hull on its side and scattered parts.
func _build_wreck() -> void:
	var w := SurfaceFinds.wreck_xz()
	var root := Node3D.new()
	root.position = Vector3(w.x, terrain.height(w.x, w.y), w.y)
	add_child(root)
	var hull := Interiors.flat(Color(0.42, 0.45, 0.5), 0.7, 0.4)
	SurfaceTextures.apply_panel(hull)   # plating, like a ship's hull
	var burnt := Interiors.flat(Color(0.12, 0.11, 0.1), 0.9)
	var body := MeshInstance3D.new()
	var bb := BoxMesh.new()
	bb.size = Vector3(6, 3, 9)
	bb.material = hull
	body.mesh = bb
	body.position = Vector3(0, 1.0, 0)
	body.rotation_degrees = Vector3(8, 25, 62)
	root.add_child(body)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(system_id + "wreck")
	for i in 9:
		var part := MeshInstance3D.new()
		var pb := BoxMesh.new()
		pb.size = Vector3(rng.randf_range(0.6, 2.4), rng.randf_range(0.3, 1.2), rng.randf_range(0.6, 3.0))
		pb.material = hull if i % 3 else burnt
		part.mesh = pb
		part.position = Vector3(rng.randf_range(-14, 14), 0.3, rng.randf_range(-14, 14))
		part.rotation_degrees = Vector3(rng.randf_range(-30, 30), rng.randf() * 360.0, rng.randf_range(-30, 30))
		root.add_child(part)
	var label := Label3D.new()
	label.text = "WRECK"
	label.font_size = 32
	label.fixed_size = true
	label.pixel_size = 0.0012
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.modulate = Color(0.85, 0.85, 0.9)
	label.position = Vector3(0, 7, 0)
	root.add_child(label)


## The outpost, the ice mine and the glass crater (SurfaceSites), each with a name you can see from the
## air, and the boulders strewn round them.
func _build_sites() -> void:
	var sys := system_id
	var hull := Interiors.flat(Color(0.55, 0.55, 0.52), 0.8)
	var dark := Interiors.flat(Color(0.18, 0.17, 0.16), 0.9)
	for st in SurfaceSites.sites(sys):
		var root := Node3D.new()
		root.position = Vector3(float(st.x), terrain.height(float(st.x), float(st.z)), float(st.z))
		add_child(root)
		match String(st.id):
			"outpost":
				var pad := MeshInstance3D.new()
				var disc := CylinderMesh.new()
				disc.top_radius = 14.0
				disc.bottom_radius = 14.5
				disc.height = 0.2
				disc.material = dark
				pad.mesh = disc
				root.add_child(pad)
				for k in 3:   # domes, one caved in
					var dome := MeshInstance3D.new()
					var sph := SphereMesh.new()
					sph.radius = 6.0 - k
					sph.height = (6.0 - k) * (0.6 if k == 1 else 1.0)
					sph.is_hemisphere = true
					sph.material = hull
					dome.mesh = sph
					dome.position = Vector3(18.0 + k * 9.0, 0, -12.0 + k * 7.0)
					root.add_child(dome)
				var mast := MeshInstance3D.new()
				var mb := BoxMesh.new()
				mb.size = Vector3(0.5, 12, 0.5)
				mb.material = hull
				mast.mesh = mb
				mast.position = Vector3(-16, 6, 10)
				mast.rotation_degrees = Vector3(0, 0, 14)
				root.add_child(mast)
			"ice_mine":
				var frost := MeshInstance3D.new()
				var fd := CylinderMesh.new()
				fd.top_radius = 34.0
				fd.bottom_radius = 34.0
				fd.height = 0.15
				fd.material = Interiors.flat(Color(0.78, 0.86, 0.92), 0.4)
				frost.mesh = fd
				frost.position = Vector3(0, 0.3, 0)
				root.add_child(frost)
				var rig := MeshInstance3D.new()
				var rb := BoxMesh.new()
				rb.size = Vector3(2, 10, 2)
				rb.material = Interiors.flat(Color(0.5, 0.42, 0.3), 0.7)
				rig.mesh = rb
				rig.position = Vector3(48, terrain.height(float(st.x) + 48.0, float(st.z)) - root.position.y + 5.0, 0)
				root.add_child(rig)
		var label := Label3D.new()
		label.text = String(st.name).to_upper()
		label.font_size = 34
		label.fixed_size = true
		label.pixel_size = 0.0012
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.modulate = Color(0.85, 0.8, 0.65)
		label.position = Vector3(0, 30 if String(st.id) == "crater" else 14, 0)
		root.add_child(label)
	# Boulders, all in one multimesh.
	var rocks := rocks
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var rock := SphereMesh.new()
	rock.radius = 1.0
	rock.height = 1.4
	rock.radial_segments = 7
	rock.rings = 4
	var body := body
	var gc: Array = body.get("ground", [0.42, 0.41, 0.40])
	var rc: Array = body.get("rock", [0.3, 0.29, 0.28])
	rock.material = SurfaceTextures.rock_material(Color(float(gc[0]), float(gc[1]), float(gc[2])).lerp(Color(float(rc[0]), float(rc[1]), float(rc[2])), 0.4).lightened(0.25))
	mm.mesh = rock
	mm.instance_count = rocks.size()
	for i in rocks.size():
		var r: Vector3 = rocks[i]
		var b := Basis(Vector3.UP, float(i) * 1.7).scaled(Vector3(r.z, r.z * 0.8, r.z * 1.1))
		mm.set_instance_transform(i, Transform3D(b, Vector3(r.x, terrain.height(r.x, r.y) + r.z * 0.25, r.y)))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	add_child(mmi)




## Rock samples: glowing crystals with a small tag, skipped once taken.
func _build_finds() -> void:
	find_nodes.clear()
	for f in (Session.finds_here() if Session.slot >= 0 else SurfaceFinds.list(system_id, 0)):
		if String(f.kind) == "salvage" or bool(f.get("taken", false)):
			continue
		var look: Array = {"sample": [Color(0.35, 0.95, 0.85), "SAMPLE", Vector3(0.5, 0.9, 0.5)], "ice": [Color(0.75, 0.9, 1.0), "ICE CORE", Vector3(0.6, 0.6, 0.6)],
				"rare": [Color(1.0, 0.45, 0.95), "GLASS CRYSTAL", Vector3(0.7, 1.4, 0.7)]}.get(String(f.kind), [Color.WHITE, "FIND", Vector3.ONE * 0.5])
		var x := float(f.x)
		var z := float(f.z)
		var node := Node3D.new()
		node.position = Vector3(x, terrain.height(x, z), z)
		_find_mesh(node, String(f.kind), look[0], look[2], hash(String(f.id)))
		var tag := Label3D.new()
		tag.text = look[1]
		tag.font_size = 28
		tag.fixed_size = true
		tag.pixel_size = 0.0012
		tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		tag.modulate = look[0].lightened(0.2)
		tag.position = Vector3(0, 1.6, 0)
		node.add_child(tag)
		add_child(node)
		find_nodes[String(f.id)] = node


## What a find looks like on the ground: a cluster of pointed crystals (samples, glass), or a frosted
## core of ice half-buried in a little pile of grit.
func _find_mesh(node: Node3D, kind: String, col: Color, size: Vector3, seed_v: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var glow := Interiors.glow(col, 1.2 if kind == "rare" else 0.9)
	var grit := MeshInstance3D.new()   # the little mound it sits in
	var mound := SphereMesh.new()
	mound.radius = size.x * 0.9
	mound.height = size.x * 0.5
	mound.radial_segments = 8
	mound.rings = 3
	mound.material = SurfaceTextures.rock_material(Color(0.5, 0.48, 0.46))
	grit.mesh = mound
	grit.position = Vector3(0, -size.x * 0.12, 0)
	node.add_child(grit)
	if kind == "ice":
		var core := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = size.x * 0.32
		cyl.bottom_radius = size.x * 0.38
		cyl.height = size.y * 1.2
		cyl.radial_segments = 6
		cyl.material = glow
		core.mesh = cyl
		core.rotation_degrees = Vector3(rng.randf_range(50, 70), rng.randf() * 360.0, 0)
		core.position = Vector3(0, size.y * 0.2, 0)
		node.add_child(core)
		return
	for i in (5 if kind == "rare" else 3):   # pointed crystals leaning out from the middle
		var shard := MeshInstance3D.new()
		var c := CylinderMesh.new()
		var h := size.y * rng.randf_range(0.55, 1.0)
		c.top_radius = 0.0
		c.bottom_radius = size.x * rng.randf_range(0.14, 0.22)
		c.height = h
		c.radial_segments = 5
		c.rings = 1
		c.material = glow
		shard.mesh = c
		var lean := Vector3(rng.randf_range(-25, 25), rng.randf() * 360.0, rng.randf_range(-25, 25)) if i > 0 else Vector3.ZERO
		shard.rotation_degrees = lean
		shard.position = Vector3(rng.randf_range(-0.12, 0.12), h * 0.45, rng.randf_range(-0.12, 0.12))
		node.add_child(shard)
