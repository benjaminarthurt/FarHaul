class_name PlaceBuilder
extends RefCounted
## Builds the place you are berthed at: the room, its lights and furniture, the desks with someone
## behind each, the gate aboard, signs, the freight board, people (Figure) standing and walking, and
## the view through the concourse window of your own ship. The walls and furniture it adds become the
## walker's collision rects (walker.walls / walker.furniture).

var sc: PlaceScene   ## the scene this works on


func _init(scene: PlaceScene) -> void:
	sc = scene


func _build_env() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = SpaceSky.make()
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.glow_intensity = 0.7
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.58, 0.65)
	env.ambient_light_energy = 0.35
	var we := WorldEnvironment.new()
	we.environment = env
	sc.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, 30, 0)
	sun.light_energy = 0.6 if sc.kind == "concourse" else 0.15
	sun.set_meta("no_shadow", true)
	sc.add_child(sun)


func _mat(col: Color, glow := false) -> StandardMaterial3D:
	var key := "%s|%s" % [col.to_html(), glow]
	if not sc._mats.has(key):
		sc._mats[key] = Interiors.glow(col, 1.4) if glow else Interiors.flat(col, 0.8)
	return sc._mats[key]


## A box in the world; `solid` makes it something the walker bumps into.
func _box(pos: Vector3, size: Vector3, col: Color, solid := true, glow := false) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	b.material = _mat(col, glow)
	mi.mesh = b
	mi.position = pos
	sc.add_child(mi)
	if solid:
		(sc.walker.furniture[0] as Array).append(Rect2(pos.x - size.x * 0.5, pos.z - size.z * 0.5, size.x, size.z))
	return mi


## An upright cylinder (bottles, tanks, posts); solid by its bounding square.
func _cyl(pos: Vector3, radius: float, height: float, col: Color, solid := true) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = radius
	c.bottom_radius = radius
	c.height = height
	c.radial_segments = 12
	c.material = _mat(col)
	mi.mesh = c
	mi.position = pos
	sc.add_child(mi)
	if solid:
		(sc.walker.furniture[0] as Array).append(Rect2(pos.x - radius, pos.z - radius, radius * 2.0, radius * 2.0))
	return mi


## A room: floor, ceiling and four walls. `window` cuts a long window in the north wall (-1) or the
## south wall (+1); 0 for none.
func _room(w: float, d: float, h: float, wall: Color, floor_col: Color, window := 0.0, ceiling := true) -> void:
	var fl := _box(Vector3(0, -0.1, 0), Vector3(w, 0.2, d), floor_col, false)
	var fm := Interiors.flat(floor_col, 0.75)
	SurfaceTextures.apply_panel(fm)   # deck plating
	(fl.mesh as BoxMesh).material = fm
	if ceiling:
		_box(Vector3(0, h + 0.1, 0), Vector3(w, 0.2, d), wall.darkened(0.25), false)
	for side in [-1.0, 1.0]:
		_wall(Vector3(side * w * 0.5, h * 0.5, 0), Vector3(0.3, h, d), wall)
		if side == window:
			var sill := minf(1.2, h * 0.3)
			var top := minf(1.2, h * 0.25)
			_wall(Vector3(0, sill * 0.5, side * d * 0.5), Vector3(w, sill, 0.3), wall)
			_wall(Vector3(0, h - top * 0.5, side * d * 0.5), Vector3(w, top, 0.3), wall)
			var glass := MeshInstance3D.new()
			var gb := BoxMesh.new()
			gb.size = Vector3(w, h - sill - top, 0.05)
			gb.material = Interiors.glass(Color(0.3, 0.45, 0.6), 0.12)
			glass.mesh = gb
			glass.position = Vector3(0, sill + (h - sill - top) * 0.5, side * d * 0.5)
			sc.add_child(glass)
			for x in range(int(-w * 0.5) + 4, int(w * 0.5), 6):   # window mullions
				_box(Vector3(x, sill + (h - sill - top) * 0.5, side * (d * 0.5 - 0.05)), Vector3(0.2, h - sill - top, 0.2), wall.darkened(0.3), false)
		else:
			_wall(Vector3(0, h * 0.5, side * d * 0.5), Vector3(w, h, 0.3), wall)
	for x in range(int(-w * 0.5) + 4, int(w * 0.5) - 1, 8):   # ceiling lights
		for z in [-d * 0.25, d * 0.25]:
			if ceiling:
				_box(Vector3(x, h - 0.05, z), Vector3(2.4, 0.08, 0.5), Color(1.0, 0.95, 0.85), false, true)
			var lamp := OmniLight3D.new()
			lamp.position = Vector3(x, h - 0.6, z)
			lamp.omni_range = 9.0
			lamp.light_energy = 1.1
			lamp.light_color = sc.style.get("lamp", Color(1.0, 0.94, 0.85))
			sc.add_child(lamp)
	(sc.walker.walls[0] as Array).append(Rect2(-w * 0.5 - 1.0, -d * 0.5 - 1.0, 1.0 + 0.15, d + 2.0))
	(sc.walker.walls[0] as Array).append(Rect2(w * 0.5 - 0.15, -d * 0.5 - 1.0, 1.15, d + 2.0))
	(sc.walker.walls[0] as Array).append(Rect2(-w * 0.5 - 1.0, -d * 0.5 - 1.0, w + 2.0, 1.15))
	(sc.walker.walls[0] as Array).append(Rect2(-w * 0.5 - 1.0, d * 0.5 - 0.15, w + 2.0, 1.15))


func _wall(pos: Vector3, size: Vector3, col: Color) -> void:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	var m := Interiors.flat(col, 0.85)
	SurfaceTextures.apply_panel(m)
	b.material = m
	mi.mesh = b
	mi.position = pos
	sc.add_child(mi)


## A desk: counter, lit sign and someone behind it. `face` points from the counter into the room.
func _desk(id: String, label: String, pos: Vector3, face: Vector3, col: Color, staffed := true) -> void:
	var across := Vector3(-face.z, 0, face.x)
	var size := Vector3(absf(across.x) * 3.2 + absf(face.x) * 0.9, 1.1, absf(across.z) * 3.2 + absf(face.z) * 0.9)
	_box(pos + Vector3(0, 0.55, 0), size, Color(0.22, 0.24, 0.28))
	_box(pos + Vector3(0, 1.12, 0), size + Vector3(0.1, 0.04, 0.1), col.darkened(0.2), false)
	var sign_pos := pos - face * 1.2 + Vector3(0, 2.9, 0)
	_box(sign_pos, Vector3(absf(across.x) * 3.0 + 0.1, 0.7, absf(across.z) * 3.0 + 0.1), col, false, true)
	var text := Label3D.new()
	text.text = label.to_upper()
	text.font_size = 56
	text.pixel_size = 0.006
	text.outline_size = 0
	text.modulate = Color(0.08, 0.08, 0.1)
	text.position = sign_pos + face * 0.08
	text.rotation.y = atan2(face.x, face.z)
	sc.add_child(text)
	if staffed:
		_person(pos - face * 0.8, face, col)
	sc.desks.append({"id": id, "label": label, "pos": pos + face * 1.25})


## Through the concourse window: your own ship at the end of a boarding arm, the station's trusses
## and lights, and the system's world hanging in space.
func _window_view() -> void:
	var outside := Node3D.new()
	outside.name = "WindowView"
	sc.add_child(outside)
	if Session.slot >= 0:
		var loaded := Session._load_ship(SaveSlots.read(Session.slot))
		if not loaded.is_empty():
			var view := ShipView.new()
			outside.add_child(view)
			view.rebuild(loaded.ship, loaded.manifest)
			sc._ship_data = loaded.ship
			view.set_interior(false)
			view.rotation.y = -PI * 0.5            # lying along the window, nose to the east
			view.position = Vector3(-4.0, 2.4, -float(sc.style.depth) * 0.5 - 10.0)
			sc.ship_outside = view
	var hull := Interiors.flat((sc.style.station as Color).darkened(0.15), 0.8)
	SurfaceTextures.apply_panel(hull)
	var dark := _mat((sc.style.station as Color).darkened(0.6))
	# The boarding arm from the concourse out to the ship's airlock hatch.
	var wall_z := -float(sc.style.depth) * 0.5 - 0.15
	var hatch := Vector3(-4.0, 2.4, wall_z - 7.0)
	if sc.ship_outside != null and sc._ship_data != null:
		for m in sc._ship_data.modules:
			if String(m.id) == "airlock":
				var local := ShipGrid.cell_to_world(m.cell) - Vector3(0, ShipGrid.CELL * 0.5, 0)
				hatch = sc.ship_outside.position + sc.ship_outside.basis * (local + Vector3(ShipGrid.CELL * 0.5, 0, 0))
	var arm_len := absf(hatch.z - wall_z)
	_box_in(outside, Vector3(hatch.x, hatch.y + 1.0, (hatch.z + wall_z) * 0.5), Vector3(2.0, 2.2, arm_len), hull)
	for k in 3:
		_box_in(outside, Vector3(hatch.x, hatch.y + 1.0, wall_z - arm_len * (k + 0.5) / 3.0), Vector3(2.7, 2.7, 0.35), dark)
	# The station's spine and trusses running away under and over the window.
	_box_in(outside, Vector3(0, -9.0, -30.0), Vector3(120.0, 4.0, 6.0), dark)
	for x in range(-50, 60, 12):
		_box_in(outside, Vector3(x, -3.0, -32.0), Vector3(0.5, 12.0, 0.5), hull)
		var lamp := _box_in(outside, Vector3(x, 3.2, -32.0), Vector3(0.6, 0.6, 0.6), _mat(Color(1.0, 0.3, 0.2), true))
		lamp.set_meta("blink", x)
	_box_in(outside, Vector3(0, 9.0, -30.0), Vector3(140.0, 1.2, 1.2), hull)
	# The world below.
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(Session.system_id())
	var planet := MeshInstance3D.new()
	var sph := SphereMesh.new()
	sph.radius = 700.0
	sph.height = 1400.0
	sph.radial_segments = 48
	sph.rings = 24
	var pm := StandardMaterial3D.new()
	pm.albedo_color = sc.style.planet
	pm.albedo_texture = SurfaceTextures.regolith()
	pm.uv1_scale = Vector3(6, 3, 1)
	pm.roughness = 1.0
	pm.rim_enabled = true
	pm.rim = 0.6
	pm.rim_tint = 0.2
	sph.material = pm
	planet.mesh = sph
	planet.position = Vector3(rng.randf_range(-900, 600), -780.0, -3200.0)
	planet.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	outside.add_child(planet)


func _box_in(parent: Node3D, pos: Vector3, size: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	b.material = mat
	mi.mesh = b
	mi.position = pos
	parent.add_child(mi)
	return mi


## Someone walking a loop of waypoints, pausing now and then.
func _add_stroller(path: Array, col: Color, n: int, species := "") -> void:
	var f := Figure.make(col, hash("stroller|%d|%d" % [n, Session.day()]), false, species)
	sc.add_child(f)
	sc.people.append(f)
	sc.strollers.append(Strollers.make(f, path, n % path.size(), 1.05 + 0.12 * n, float(n)))


## A person (Figure) facing `face`, solid to walk into.
func _person(at: Vector3, face: Vector3, col: Color, seated := false) -> Figure:
	var seed_v := hash("%s|%s" % [at, Session.day()])
	var crowd: Array = sc.style.get("crowd", ["human"])
	var f := Figure.make(col, seed_v, seated, String(crowd[absi(seed_v) % crowd.size()]))
	f.position = at
	f.rotation.y = atan2(-face.x, -face.z)
	sc.add_child(f)
	sc.people.append(f)
	if not seated:
		(sc.walker.furniture[0] as Array).append(Rect2(at.x - 0.3, at.z - 0.3, 0.6, 0.6))
	return f


## A painted walkway line on the floor between two points.
func _walk_line(from: Vector3, to: Vector3) -> void:
	var mid := (from + to) * 0.5
	var along := to - from
	var size := Vector3(absf(along.x) + 0.12, 0.012, absf(along.z) + 0.12)
	var col: Color = (sc.style.get("trim", Color(0.95, 0.75, 0.2)) as Color).darkened(0.1) if sc.kind == "concourse" else Color(0.85, 0.65, 0.18)
	_box(Vector3(mid.x, 0.006, mid.z), size, col, false)


## A planter: a box of soil with a few round shrubs.
func _planter(at: Vector3) -> void:
	_box(at + Vector3(0, 0.3, 0), Vector3(1.6, 0.6, 0.8), Color(0.32, 0.33, 0.36))
	var leaf := _mat(Color(0.22, 0.48, 0.25))
	for i in 3:
		var mi := MeshInstance3D.new()
		var sph := SphereMesh.new()
		sph.radius = 0.32 + 0.06 * i
		sph.height = (0.32 + 0.06 * i) * 1.6
		sph.radial_segments = 8
		sph.rings = 4
		sph.material = leaf
		mi.mesh = sph
		mi.position = at + Vector3(-0.5 + i * 0.5, 0.75 + 0.05 * i, 0)
		sc.add_child(mi)


## A rack of glowing grow-trays.
func _hydro_rack(at: Vector3) -> void:
	_box(at + Vector3(0, 1.1, 0), Vector3(0.6, 2.2, 1.8), Color(0.55, 0.56, 0.58))
	for k in 3:
		_box(at + Vector3(0.1, 0.5 + k * 0.65, 0), Vector3(0.45, 0.2, 1.6), Color(0.3, 0.7, 0.3))
		_box(at + Vector3(0.1, 0.78 + k * 0.65, 0), Vector3(0.45, 0.03, 1.6), Color(0.85, 0.45, 1.0), false, true)


## A hanging screen listing the freight posted here, both sides.
func _freight_board(at: Vector3, face := Vector3(0, 0, 1)) -> void:
	var across := Vector3(-face.z, 0, face.x)
	_box(at, Vector3(absf(across.x) * 4.6 + 0.12, 1.5, absf(across.z) * 4.6 + 0.12), Color(0.08, 0.09, 0.11), false)
	for c in [-1.0, 1.0]:   # hanging cables
		_box(at + across * c * 2.0 + Vector3(0, 1.3, 0), Vector3(0.04, 1.1, 0.04), Color(0.2, 0.2, 0.22), false)
	var lines := PackedStringArray(["FREIGHT POSTED HERE"])
	var offers := Contracts.offers_from(Session.system_id()) if Session.slot >= 0 else []
	for o in offers.slice(0, 5):
		var dest := String(LocalSpace.node(String(o.destination_port_id)).get("name", "")) if bool(o.get("local", false)) else String(Worlds.port(String(o.destination_port_id)).get("name", ""))
		lines.append("%s  %.1f t  %s cr/t" % [dest.trim_prefix(String(Worlds.system(Session.system_id()).get("name", "")) + " ").substr(0, 22), float(o.offer), ShipStats.commas(int(o.rate))])
	if offers.is_empty():
		lines.append("NOTHING POSTED TODAY")
	for side in [1.0, -1.0]:
		var l := Label3D.new()
		l.text = "\n".join(lines)
		l.font_size = 32
		l.pixel_size = 0.0056
		l.modulate = Color(1.0, 0.75, 0.3)
		l.outline_size = 0
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.position = at + face * side * 0.08
		l.rotation.y = atan2(face.x * side, face.z * side)
		sc.add_child(l)


## The gate back aboard: a lit door with your ship's name over it.
func _gate(pos: Vector3, face: Vector3, label: String) -> void:
	var across := Vector3(-face.z, 0, face.x)
	_box(pos + Vector3(0, 1.5, 0) - face * 0.1, Vector3(absf(across.x) * 2.4 + 0.2, 3.0, absf(across.z) * 2.4 + 0.2), Color(0.3, 0.33, 0.38), false)
	_box(pos + Vector3(0, 1.4, 0) + face * 0.06, Vector3(absf(across.x) * 1.8 + 0.05, 2.6, absf(across.z) * 1.8 + 0.05), Color(0.15, 0.17, 0.2), false)
	_box(pos + Vector3(0, 3.3, 0) + face * 0.1, Vector3(absf(across.x) * 3.4 + 0.1, 0.5, absf(across.z) * 3.4 + 0.1), Brand.AMBER, false, true)
	var text := Label3D.new()
	text.text = label
	text.font_size = 44
	text.pixel_size = 0.006
	text.outline_size = 0
	text.modulate = Color(0.08, 0.08, 0.1)
	text.position = pos + Vector3(0, 3.3, 0) + face * 0.2
	text.rotation.y = atan2(face.x, face.z)
	sc.add_child(text)
	sc.desks.append({"id": "gate", "label": "your ship: %s" % Session.ship_label(), "pos": pos + face * 1.3})


func _big_sign(text: String, pos: Vector3, yaw: float, scale := 1.0) -> void:
	var l := Label3D.new()
	l.text = text
	l.font_size = 120
	l.pixel_size = minf(0.008, 12.0 / (maxf(1.0, text.length()) * 120.0 * 0.62))   # fit a long sc.name on the wall
	l.modulate = Brand.AMBER
	l.position = pos
	l.rotation.y = yaw
	sc.add_child(l)


func _place_name() -> String:
	return String(sc.site.get("name", LocalSpace.node(String(Session.profile.get("port_id", ""))).get("name", "Station"))).to_upper()


func _build_concourse() -> void:
	var st: Dictionary = sc.style
	var w := float(st.width)
	var d := float(st.depth)
	var h := 5.0 * float(st.height)
	var hw := w * 0.5
	var hd := d * 0.5
	_room(w, d, h, st.wall, st.floor, -1.0)
	var face_n := Vector3(0, 0, -1)
	var dz := hd - 1.8
	var bar_x := w * 0.32
	_desk("freight", "Freight office", Vector3(-w * 0.32, 0, dz), face_n, Color(0.95, 0.65, 0.2))
	_desk("fuel", "Fuel and repairs", Vector3(-w * 0.11, 0, dz), face_n, Color(0.4, 0.8, 1.0))
	if String(st.get("site_kind", "port")) == "port":
		_desk("yard", "Shipyard", Vector3(w * 0.09, 0, dz), face_n, Color(0.9, 0.85, 0.4))
	_desk("bar", String(st.bar_name), Vector3(bar_x, 0, dz), face_n, Color(0.85, 0.35, 0.3))
	for k in 4:   # bar stools
		_box(Vector3(bar_x - 3.0 + k * 2.0, 0.4, dz - 1.5), Vector3(0.45, 0.8, 0.45), Color(0.6, 0.25, 0.2))
	var asking := Session.people_here() if Session.slot >= 0 else []
	var jackets := [Color(0.3, 0.5, 0.75), Color(0.55, 0.7, 0.35), Color(0.7, 0.45, 0.65)]
	var desk_xs := [-w * 0.32, -w * 0.11, w * 0.09]
	var spots := []
	for sx in [bar_x - 4.2, bar_x + 3.9, bar_x - 5.8, bar_x + 5.4]:   # beside the bar, never in front of another desk
		var x := clampf(float(sx), -hw + 1.5, hw - 1.5)
		var clear := true
		for dx in desk_xs:
			clear = clear and absf(x - float(dx)) > 1.8
		for o in spots:
			clear = clear and absf(x - float(o)) > 1.0
		if clear:
			spots.append(x)
	for i in mini(asking.size(), mini(3, spots.size())):   # the people with work, waiting by the bar
		_person(Vector3(float(spots[i]), 0, hd - 2.9), Vector3(0, 0, -1), jackets[i])
	# The terminal kiosk in the middle, and benches.
	var kz := -0.1 * d
	_box(Vector3(0, 0.75, kz), Vector3(0.8, 1.5, 0.5), Color(0.16, 0.17, 0.2))
	_box(Vector3(0, 1.3, kz + 0.26), Vector3(0.6, 0.4, 0.04), Color(0.3, 0.85, 1.0), false, true)
	sc.desks.append({"id": "terminal", "label": "Station terminal", "pos": Vector3(0, 0, kz + 1.0)})
	for x in [-w * 0.2, w * 0.2]:
		_box(Vector3(x, 0.25, -hd + 3.5), Vector3(4.0, 0.5, 0.8), Color(0.35, 0.3, 0.28))
	_walk_line(Vector3(-hw + 1.0, 0, 0), Vector3(hw - 2.0, 0, 0))   # the walkway down the middle, and a line to each desk
	for x in [-w * 0.32, -w * 0.11, w * 0.09, bar_x]:
		_walk_line(Vector3(x, 0, 0.2), Vector3(x, 0, dz - 1.6))
	if bool(st.planters):
		for f in [-0.39, -0.05, 0.16, 0.43]:
			_planter(Vector3(w * f, 0, -hd + 1.4))
	var beam := 0.25 + 0.35 * float(st.column)   # roof beams, heavier in heavier styles
	for x in range(int(-hw) + 6, int(hw) - 3, 8):
		_box(Vector3(x, h - 0.2, 0), Vector3(beam, beam, d), (st.wall as Color).darkened(0.35), false)
	_freight_board(Vector3(0, minf(3.4, h - 1.4), kz), Vector3(1, 0, 0))
	_window_view()
	StyleDressing.dress(self, sc, st, w, d, h)
	# Travellers walking the concourse: loops along the window lane and the middle lane, crossing
	# between them clear of the benches and the kiosk.
	var lane_n := -hd + 2.3
	var lane_m := 0.08 * d
	var crowd: Array = st.crowd
	for n in int(st.walkers):
		var sx := 1.0 if n % 2 == 0 else -1.0
		var a := (0.4 - 0.03 * (n % 3)) * w
		var b := (0.3 - 0.02 * (n % 2)) * w
		var path := [Vector3(-a * sx, 0, lane_n), Vector3(a * sx, 0, lane_n), Vector3(b * sx, 0, lane_m), Vector3(-b * sx, 0, lane_m)]
		_add_stroller(path, [Color(0.45, 0.42, 0.55), Color(0.6, 0.5, 0.35), Color(0.3, 0.45, 0.4), Color(0.5, 0.3, 0.3), Color(0.35, 0.35, 0.45), Color(0.55, 0.55, 0.5)][n % 6], n + 1, String(crowd[n % crowd.size()]))
	_gate(Vector3(-hw + 0.2, 0, 0), Vector3(1, 0, 0), "BERTH 3  %s" % Session.ship_label().to_upper())
	_big_sign(_place_name(), Vector3(hw - 0.3, minf(3.2, h - 1.6), 0), -PI * 0.5)
	if not (st.landmark as Dictionary).is_empty() and String(st.bar_name) != String(st.landmark.get("name", "")):
		_big_sign("%s  →" % String(st.landmark.name).to_upper(), Vector3(hw - 0.3, minf(3.2, h - 1.6) - 1.1, 0), -PI * 0.5, 0.55)
	sc.walker.pos = Vector3(-hw + 2.5, 0, 0)
	sc.walker.face(Vector3(1, 0, 0))


## The system's colours pulled into a room's own: `k` of the way from `base` to the style's.
func _tint(base: Color, key: String, k: float) -> Color:
	return base.lerp(sc.style.get(key, base) as Color, k)


func _build_hab() -> void:
	var hab_wall := _tint(Color(0.7, 0.69, 0.64), "wall", 0.45)
	_room(20.0, 20.0, 4.5, hab_wall, _tint(Color(0.32, 0.31, 0.3), "floor", 0.5), -1.0, false)
	_moon_outside(Vector3(0, 0, -10.0), Vector3(0, 0, -1))
	var dome := MeshInstance3D.new()   # the dome over the room
	var sph := SphereMesh.new()
	sph.radius = 14.0
	sph.height = 14.0
	sph.is_hemisphere = true
	sph.material = Interiors.flat(hab_wall.lightened(0.03), 0.9)
	(sph.material as StandardMaterial3D).cull_mode = BaseMaterial3D.CULL_DISABLED
	dome.mesh = sph
	dome.position = Vector3(0, 4.5, 0)
	dome.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	sc.add_child(dome)
	_desk("dispatch", "Dispatch", Vector3(0, 0, -8.2), Vector3(0, 0, 1), Color(0.95, 0.65, 0.2))
	_desk("lab", "Survey lab", Vector3(8.2, 0, -2), Vector3(-1, 0, 0), Color(0.4, 1.0, 0.8))
	_desk("store", "Suit store", Vector3(8.2, 0, 5), Vector3(-1, 0, 0), Color(0.6, 0.6, 1.0))
	_desk("fuel", "Pad fuel and repairs", Vector3(0, 0, 8.2), Vector3(0, 0, -1), Color(0.4, 0.8, 1.0))
	_box(Vector3(-2, 0.75, 1), Vector3(0.8, 1.5, 0.5), Color(0.16, 0.17, 0.2))
	_box(Vector3(-2, 1.3, 1.26), Vector3(0.6, 0.4, 0.04), Color(0.3, 0.85, 1.0), false, true)
	sc.desks.append({"id": "terminal", "label": "Base terminal", "pos": Vector3(-2, 0, 2)})
	for z in [-7.0, -4.5, 4.5, 7.0]:   # hydroponic racks either side of the airlock
		_hydro_rack(Vector3(-9.2, 0, z))
	_walk_line(Vector3(-9, 0, 0), Vector3(7, 0, 0))
	_freight_board(Vector3(3.5, 3.0, 0), Vector3(-1, 0, 0))
	var crowd: Array = sc.style.get("crowd", ["human"])
	_add_stroller([Vector3(-6, 0, -3), Vector3(4, 0, -5.5), Vector3(5, 0, 5.5), Vector3(-5, 0, 4)], Color(0.85, 0.85, 0.82), 6, String(crowd[0]))   # a technician in whites, starting across the room
	_gate(Vector3(-9.8, 0, 0), Vector3(1, 0, 0), "AIRLOCK  PAD 1")
	_big_sign(_place_name(), Vector3(0, 3.95, 9.8), PI)
	sc.walker.pos = Vector3(-7.5, 0, 0)
	sc.walker.face(Vector3(1, 0, 0))


func _build_hut() -> void:
	_room(14.0, 9.0, 3.4, _tint(Color(0.62, 0.55, 0.4), "wall", 0.35), _tint(Color(0.25, 0.22, 0.18), "floor", 0.35), 1.0)
	_moon_outside(Vector3(0, 0, 4.5), Vector3(0, 0, 1))
	_desk("foreman", "Foreman", Vector3(0, 0, -2.9), Vector3(0, 0, 1), Color(1.0, 0.55, 0.3))
	_desk("exchange", "Ore and parts exchange", Vector3(5.4, 0, 1.5), Vector3(-1, 0, 0), Color(0.8, 0.7, 0.4))
	_box(Vector3(1.5, 0.75, 3.6), Vector3(0.8, 1.5, 0.5), Color(0.16, 0.17, 0.2))
	sc.desks.append({"id": "terminal", "label": "Camp terminal", "pos": Vector3(1.5, 0, 2.6)})
	for i in 3:   # crates
		_box(Vector3(-3.5 + i * 1.3, 0.6, 3.6), Vector3(1.1, 1.2, 1.1), Color(0.45, 0.35, 0.2))
	_box(Vector3(-2.0, 0.75, -0.4), Vector3(1.8, 0.08, 1.0), Color(0.4, 0.33, 0.24))   # a table, a worker on a break
	_box(Vector3(-2.0, 0.37, -0.4), Vector3(0.12, 0.74, 0.12), Color(0.25, 0.22, 0.2), false)
	_box(Vector3(-2.0, 0.45, -1.25), Vector3(0.5, 0.06, 0.5), Color(0.3, 0.3, 0.32), false)
	_person(Vector3(-2.0, 0, -1.2), Vector3(0, 0, 1), Color(0.75, 0.45, 0.2), true)
	for i in 4:   # suit lockers on the back wall
		_box(Vector3(2.6 + i * 0.7, 1.0, -4.15), Vector3(0.6, 2.0, 0.4), Color(0.35, 0.4, 0.38))
	_gate(Vector3(-6.8, 0, 0), Vector3(1, 0, 0), "AIRLOCK")
	sc.walker.pos = Vector3(-4.8, 0, -1)
	sc.walker.face(Vector3(1, 0, 0))


## Outside a hab or hut window: the moon's ground in its own colours, rocks, your ship on its pad, and
## the base's other buildings, lit by a hard sun of their own (visual layer 2), while the room stays
## lit from inside. `wall` is the window wall's centre and `out` points outward.
func _moon_outside(wall: Vector3, out: Vector3) -> void:
	var sys := Session.system_id()
	var body := LocalSpace.body(sys)
	var gc: Array = body.get("ground", [0.42, 0.41, 0.40])
	var rc: Array = body.get("rock", [0.3, 0.29, 0.28])
	var ground_col := Color(float(gc[0]), float(gc[1]), float(gc[2]))
	var outside := Node3D.new()
	outside.name = "Outside"
	sc.add_child(outside)
	var gm := StandardMaterial3D.new()
	gm.albedo_color = ground_col
	gm.albedo_texture = SurfaceTextures.regolith()
	gm.uv1_triplanar = true
	gm.uv1_world_triplanar = true
	gm.uv1_scale = Vector3.ONE / SurfaceTextures.REGOLITH_TILE_M
	gm.roughness = 1.0
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(3000, 3000)
	pm.material = gm
	ground.mesh = pm
	ground.position = wall + out * 1500.0 + Vector3(0, -0.15, 0)
	outside.add_child(ground)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(sys + "|window")
	var rock := SurfaceTextures.rock_material(ground_col.lerp(Color(float(rc[0]), float(rc[1]), float(rc[2])), 0.4).lightened(0.25))
	var across := Vector3(-out.z, 0, out.x)
	for i in 40:   # boulders strewn out to the horizon
		var mi := MeshInstance3D.new()
		var sp := SphereMesh.new()
		var r := rng.randf_range(0.4, 2.6)
		sp.radius = r
		sp.height = r * 1.3
		sp.radial_segments = 7
		sp.rings = 4
		sp.material = rock
		mi.mesh = sp
		mi.position = wall + out * rng.randf_range(12.0, 300.0) + across * rng.randf_range(-150.0, 150.0) + Vector3(0, r * 0.2, 0)
		outside.add_child(mi)
	var domes := Interiors.flat(Color(0.72, 0.71, 0.66), 0.9)
	for k in 3:   # the base's other buildings
		var dm := MeshInstance3D.new()
		var sph := SphereMesh.new()
		sph.radius = 7.0 - k * 1.5
		sph.height = (7.0 - k * 1.5) * 2.0
		sph.is_hemisphere = true
		sph.material = domes
		dm.mesh = sph
		dm.position = wall + out * (60.0 + k * 25.0) + across * (-45.0 + k * 38.0)
		outside.add_child(dm)
	# Your ship on its pad, out beyond the glass.
	if Session.slot >= 0:
		var loaded := Session._load_ship(SaveSlots.read(Session.slot))
		if not loaded.is_empty():
			var pad := MeshInstance3D.new()
			var disc := CylinderMesh.new()
			disc.top_radius = 14.0
			disc.bottom_radius = 14.5
			disc.height = 0.2
			disc.material = Interiors.flat(Color(0.3, 0.31, 0.33), 0.9)
			pad.mesh = disc
			var at := wall + out * 34.0 + across * 8.0
			pad.position = at
			outside.add_child(pad)
			var view := ShipView.new()
			outside.add_child(view)
			view.rebuild(loaded.ship, loaded.manifest)
			view.set_interior(false)
			view.rotation.y = atan2(across.x, across.z)
			var stats := ShipStats.compute(loaded.ship)
			view.position = at + Vector3(0, float(stats.get("foot_y", -1.5)) * -1.0 + 0.1, 0) - view.basis * Vector3(stats.com.x, 0, stats.com.z)
	_layer_two(outside)
	var sun := DirectionalLight3D.new()   # the moon's hard daylight, for what is outside only
	sun.rotation_degrees = Vector3(-28, 35, 0)
	sun.light_energy = 1.05
	sun.light_cull_mask = 2
	sun.set_meta("no_shadow", true)
	sc.add_child(sun)


func _layer_two(node: Node) -> void:
	if node is VisualInstance3D:
		(node as VisualInstance3D).layers = 2
	for c in node.get_children():
		_layer_two(c)
