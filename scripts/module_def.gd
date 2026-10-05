class_name ModuleDef
extends Resource
## Describes one kind of prefab ship section: footprint, connection points, engineering stats,
## and a visual factory.
##
## If `scene` is set it is used for the visuals (your real art, later). Otherwise a placeholder is
## generated: a hollow room for pressurised modules, or a simple solid shape for external ones.

const WALL_T := 0.12
const DOOR_HALF_W := 0.7  ## doorway is 1.4 m wide
const DOOR_TOP := 0.7  ## doorway top, measured up from the cell centre (floor is at -1.5)
const CRATE_COLORS := [  # worn shipping-container paints
	Color(0.62, 0.27, 0.20), Color(0.20, 0.38, 0.55), Color(0.68, 0.55, 0.20), Color(0.28, 0.45, 0.33),
]
const FACES := [
	Vector3i(1, 0, 0), Vector3i(-1, 0, 0),
	Vector3i(0, 1, 0), Vector3i(0, -1, 0),
	Vector3i(0, 0, 1), Vector3i(0, 0, -1),
]

@export var id: StringName
@export var display_name := ""
@export var scene: PackedScene  ## optional real art
@export var size := Vector3i(1, 1, 1)  ## cells occupied, before rotation
@export var sockets: Array[ModuleSocket] = []
@export var color := Color(0.6, 0.65, 0.7)  ## placeholder tint
@export var group: StringName = &"hull"  ## palette section: hull, cargo or external

@export_group("Engineering")
@export var pressurized := true  ## walkable hull (true) or external part like a tank or engine (false)
@export var shape: StringName = &"box"  ## placeholder look for external parts: frame, tank, radiator, engine, box
@export var mass := 1.0  ## tonnes, dry
@export var cost := 0  ## credits
@export var power := 0.0  ## kW: positive generates, negative consumes
@export var heat := 0.0  ## kW: positive is waste heat produced, negative is cooling capacity
@export var thrust := 0.0  ## kN, pushing the ship along the module's local -Z (forward)
@export var fuel := 0.0  ## tonnes of propellant held when full
@export var helm := false  ## true if the ship can be flown from here
@export var airlock := false  ## true if crew can get in and out of the ship here
@export var berths := 0  ## crew who can sleep aboard
@export var drive := 0.0  ## jump drive: fraction added to cruising speed (0.3 is +30%)
@export var lift := 0.0  ## kN of downward-firing lift jets (push the ship along +Y): needed to land
@export var cargo_slots := 0  ## standard containers this module can carry
@export var cargo_capacity := 0.0  ## tonnes of freight when every slot is full


func get_cells() -> Array[Vector3i]:
	var out: Array[Vector3i] = []
	for x in size.x:
		for y in size.y:
			for z in size.z:
				out.append(Vector3i(x, y, z))
	return out


func has_socket_at(c: Vector3i, d: Vector3i) -> bool:
	for s in sockets:
		if s.cell == c and s.dir == d:
			return true
	return false


## Build the 3D visuals, centred on the module's origin cell.
func build_visual() -> Node3D:
	if scene != null:
		return scene.instantiate() as Node3D
	var root := Node3D.new()
	if pressurized:
		_build_hollow(root)
	else:
		_build_external(root)
	return root


# --- Pressurised: hollow rooms with doorways ----------------------------------------------------

func _build_hollow(root: Node3D) -> void:
	var wall_mat := _mat(color, 1.0)
	var floor_mat := _mat(color.darkened(0.55), 1.0)
	var ceil_mat := _mat(color.darkened(0.2), 0.13)  # see-through so the builder can look inside
	var trim_mat := _mat(color.lerp(Color(0.50, 0.54, 0.60), 0.8), 1.0)
	var cells := get_cells()
	for c in cells:
		for d in FACES:
			if cells.has(c + d):
				continue  # interior face between two cells of this module
			var mat: Material = wall_mat
			if d.y > 0:
				mat = ceil_mat
			elif d.y < 0:
				mat = floor_mat
			var before := root.get_child_count()
			_add_face(root, Vector3(c) * ShipGrid.CELL, d, has_socket_at(c, d), mat)
			if d.y > 0:  # tag the see-through ceiling so a walking view can make it solid
				for i in range(before, root.get_child_count()):
					root.get_child(i).set_meta("ceiling", true)
	for c in cells:
		_add_frame_struts(root, Vector3(c) * ShipGrid.CELL, 0.16, trim_mat, 0.03)
	_add_details(root)
	var furnished := root.get_child_count()
	Interiors.dress(self, root)
	if cargo_slots > 0:
		_add_crates(root, cells)
	for i in range(furnished, root.get_child_count()):  # furniture and freight: things a walker bumps into
		root.get_child(i).set_meta("solid", true)
	for c in cells:  # a ceiling light in every cell, so rooms are lit from inside, not by the sun
		var lamp := OmniLight3D.new()
		lamp.position = Vector3(c) * ShipGrid.CELL + Vector3(0, ShipGrid.CELL * 0.5 - 0.35, 0)
		lamp.omni_range = 3.6
		lamp.omni_attenuation = 1.2
		lamp.light_energy = 0.9
		lamp.light_color = Color(1.0, 0.9, 0.78)
		lamp.shadow_enabled = false
		lamp.set_meta("interior_light", true)
		root.add_child(lamp)


## Small per-module set dressing so hulls don't read as blank boxes.
func _add_details(root: Node3D) -> void:
	var h := ShipGrid.CELL * 0.5
	if airlock:
		_add_hatch(root)
	if power > 50.0:  # reactor room: glowing vents on both sides
		for side in [-1.0, 1.0]:
			for k in 3:
				_add_box(root, Vector3(side * (h + 0.02), -0.5 + k * 0.5, 0), Vector3(0.08, 0.18, 1.8), _glow(Color(1.0, 0.5, 0.2)))
	var hazard := SurfaceTextures.hazard_material()  # warning stripes on every doorway threshold
	for sk in sockets:
		if sk.kind != ModuleSocket.DOOR or sk.dir.y != 0:
			continue
		var pos := Vector3(sk.cell) * ShipGrid.CELL + Vector3(sk.dir) * (h - 0.25) + Vector3(0, -h + WALL_T + 0.015, 0)
		var strip := Vector3(1.4, 0.03, 0.3) if sk.dir.z != 0 else Vector3(0.3, 0.03, 1.4)
		_add_box(root, pos, strip, hazard)
	if size.x * size.z > 1 and not cargo_slots > 0:  # big room: a lit floor strip
		_add_box(root, Vector3(0.0, -h + 0.14, 0), Vector3(0.12, 0.04, size.z * ShipGrid.CELL - 1.0), _glow(Color(0.7, 0.9, 1.0)))


## Outer airlock hatch on the wall opposite the door: dark leaf, hazard border, lit window, status lamp.
func _add_hatch(root: Node3D) -> void:
	var inner := Vector3i(1, 0, 0)
	for sk in sockets:
		if sk.kind == ModuleSocket.DOOR and sk.dir.y == 0:
			inner = sk.dir
			break
	var out := -inner
	var h := ShipGrid.CELL * 0.5
	# The same hatch twice: on the hull outside, and on the inside face of that wall for whoever walks in.
	for side in [1.0, -1.0]:
		var hatch := Node3D.new()
		hatch.position = Vector3(out) * ((h + 0.03) if side > 0.0 else (h - WALL_T - 0.05)) + Vector3(0, -0.15, 0)
		hatch.rotation.y = atan2(float(out.x) * side, float(out.z) * side)  # local +Z faces away from the wall
		root.add_child(hatch)
		_hatch_leaf(hatch)


func _hatch_leaf(hatch: Node3D) -> void:
	var leaf := _mat(color.darkened(0.45), 1.0)
	var stripes := SurfaceTextures.hazard_material()
	_add_box(hatch, Vector3.ZERO, Vector3(1.5, 2.0, 0.08), leaf)
	_add_box(hatch, Vector3(0, 1.07, 0.02), Vector3(1.7, 0.16, 0.1), stripes)
	_add_box(hatch, Vector3(0, -1.07, 0.02), Vector3(1.7, 0.16, 0.1), stripes)
	_add_box(hatch, Vector3(0.83, 0, 0.02), Vector3(0.16, 2.3, 0.1), stripes)
	_add_box(hatch, Vector3(-0.83, 0, 0.02), Vector3(0.16, 2.3, 0.1), stripes)
	_add_box(hatch, Vector3(0, 0.45, 0.06), Vector3(0.6, 0.4, 0.03), _glow(Color(0.45, 0.8, 1.0)))
	_add_box(hatch, Vector3(0.45, -0.3, 0.06), Vector3(0.12, 0.12, 0.03), _glow(Color(0.3, 1.0, 0.4)))
	_add_box(hatch, Vector3(0, -0.3, 0.06), Vector3(0.5, 0.1, 0.03), _mat(color.darkened(0.7), 1.0))  # wheel plate


static var _plumes := {}


## Exhaust: additive, unshaded, bright at the nozzle and fading to nothing along its length (the
## cylinder's v runs from its narrow far end, 0, to the nozzle, 1).
static func _plume(col: Color, core := false) -> StandardMaterial3D:
	var key := "%s|%s" % [col.to_html(), core]
	if _plumes.has(key):
		return _plumes[key]
	var g := Gradient.new()
	g.set_color(0, Color(0, 0, 0))
	g.set_color(1, col.lerp(Color(1, 1, 1), 0.6) if core else col)
	g.add_point(0.55, (col * (0.9 if core else 0.45)))
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill_from = Vector2(0, 0)
	tex.fill_to = Vector2(0, 1)
	tex.width = 4
	tex.height = 64
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.no_depth_test = false
	m.albedo_texture = tex
	m.texture_repeat = false   # no bleed of the bright nozzle end onto the far tip
	m.albedo_color = Color(1, 1, 1, 1)
	_plumes[key] = m
	return m


static func _glow(col: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.emission_enabled = true
	m.emission = col
	m.emission_energy_multiplier = 1.3
	return m

## Containers stacked along both sides of a walkable hold, leaving a 1.4 m aisle between them.
func _add_crates(root: Node3D, cells: Array[Vector3i]) -> void:
	var floor_y := -ShipGrid.CELL * 0.5 + WALL_T
	var crate := Vector3(0.7, 1.4, 1.4)
	var n := 0
	for c in cells:
		for side in [-1.0, 1.0]:
			var pos := Vector3(c) * ShipGrid.CELL + Vector3(side * 1.03, floor_y + crate.y * 0.5, 0)
			_add_container(root, pos, crate, CRATE_COLORS[n % CRATE_COLORS.size()], n, floor_y)
			n += 1


## A corrugated shipping container. The root node carries the slot number so a view can show fill.
func _add_container(root: Node3D, pos: Vector3, box: Vector3, col: Color, slot: int, bottom_y: float) -> void:
	var node := Node3D.new()
	node.position = pos
	node.set_meta("slot", slot)
	node.set_meta("bottom_y", bottom_y)
	node.set_meta("height", box.y)
	node.set_meta("colour", col)
	node.set_meta("width", box.x)
	var body := _add_box(node, Vector3.ZERO, box, _mat(col, 1.0))
	body.set_meta("paint", 1.0)
	var rib_t := 0.07
	var count := int(box.z / 0.35)
	for i in count:  # corrugation bands around the cross-section
		var z := (float(i) + 0.5) / float(count) * box.z - box.z * 0.5
		var rib := _add_box(node, Vector3(0, 0, z), Vector3(box.x + 0.05, box.y + 0.05, rib_t), _mat(col, 1.0))
		rib.set_meta("paint", 0.8)
	var frame := _mat(Color(0.12, 0.12, 0.14), 1.0)  # corner castings
	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			for sz in [-1.0, 1.0]:
				_add_box(node, Vector3(sx * box.x * 0.5, sy * box.y * 0.5, sz * box.z * 0.5), Vector3(0.1, 0.1, 0.1), frame)
	root.add_child(node)


static func _mat(col: Color, alpha: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(col, alpha)
	m.roughness = 0.8
	if alpha < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	else:
		SurfaceTextures.apply_panel(m)  # riveted plating
	return m


func _add_face(root: Node3D, center: Vector3, d: Vector3i, is_door: bool, mat: Material) -> void:
	var axis := 0
	if d.y != 0:
		axis = 1
	elif d.z != 0:
		axis = 2
	var sgn := float(d[axis])

	# Two tangent axes spanning the face: u (horizontal on a wall), v (vertical on a wall).
	var u_axis := 0
	var v_axis := 1
	if axis == 1:
		u_axis = 0
		v_axis = 2
	elif axis == 0:
		u_axis = 2
		v_axis = 1

	var h := ShipGrid.CELL * 0.5
	if not is_door and helm and axis != 1:
		# A flight deck needs to see out: a big windscreen at the front, a smaller window each side.
		var win := Rect2(-1.2, -0.2, 2.4, 1.2) if axis == 2 else Rect2(-0.55, -0.1, 1.1, 0.8)
		_add_windowed_wall(root, center, axis, sgn, u_axis, v_axis, win, mat)
		return
	if not is_door:
		_add_panel(root, center, axis, sgn, u_axis, v_axis, Rect2(-h, -h, ShipGrid.CELL, ShipGrid.CELL), mat)
		return

	# Doorway: a hole in the face, built from up to four strips around it.
	var hole: Rect2
	if axis == 1:
		hole = Rect2(-DOOR_HALF_W, -DOOR_HALF_W, DOOR_HALF_W * 2.0, DOOR_HALF_W * 2.0)
	else:
		hole = Rect2(-DOOR_HALF_W, -h, DOOR_HALF_W * 2.0, DOOR_TOP + h)
	var strips: Array[Rect2] = [
		Rect2(-h, -h, hole.position.x + h, ShipGrid.CELL),  # left
		Rect2(hole.end.x, -h, h - hole.end.x, ShipGrid.CELL),  # right
		Rect2(hole.position.x, hole.end.y, hole.size.x, h - hole.end.y),  # above
		Rect2(hole.position.x, -h, hole.size.x, hole.position.y + h),  # below
	]
	for r in strips:
		if r.size.x > 0.001 and r.size.y > 0.001:
			_add_panel(root, center, axis, sgn, u_axis, v_axis, r, mat)


## A solid wall with a rectangular window: four strips around the opening, a pane of glass in it,
## and a frame so the window reads from outside as well as in.
func _add_windowed_wall(root: Node3D, center: Vector3, axis: int, sgn: float, u_axis: int, v_axis: int, hole: Rect2, mat: Material) -> void:
	var h := ShipGrid.CELL * 0.5
	var strips: Array[Rect2] = [
		Rect2(-h, -h, hole.position.x + h, ShipGrid.CELL),
		Rect2(hole.end.x, -h, h - hole.end.x, ShipGrid.CELL),
		Rect2(hole.position.x, hole.end.y, hole.size.x, h - hole.end.y),
		Rect2(hole.position.x, -h, hole.size.x, hole.position.y + h),
	]
	for r in strips:
		if r.size.x > 0.001 and r.size.y > 0.001:
			_add_panel(root, center, axis, sgn, u_axis, v_axis, r, mat)
	var along := sgn * (h - WALL_T * 0.5)
	var pane := Vector3.ZERO
	pane[axis] = 0.03
	pane[u_axis] = hole.size.x
	pane[v_axis] = hole.size.y
	var off := Vector3.ZERO
	off[axis] = along
	off[u_axis] = hole.position.x + hole.size.x * 0.5
	off[v_axis] = hole.position.y + hole.size.y * 0.5
	_add_box(root, center + off, pane, Interiors.glass(Color(0.25, 0.4, 0.55), 0.16))
	# Frame: slightly proud of the outer face, in the module's trim colour.
	var trim := _mat(color.lerp(Color(0.50, 0.54, 0.60), 0.8), 1.0)
	var t := 0.07
	var out := sgn * (h + 0.015)
	var edges := [
		[Vector2(hole.position.x + hole.size.x * 0.5, hole.position.y - t * 0.5), Vector2(hole.size.x + t * 2.0, t)],
		[Vector2(hole.position.x + hole.size.x * 0.5, hole.end.y + t * 0.5), Vector2(hole.size.x + t * 2.0, t)],
		[Vector2(hole.position.x - t * 0.5, hole.position.y + hole.size.y * 0.5), Vector2(t, hole.size.y)],
		[Vector2(hole.end.x + t * 0.5, hole.position.y + hole.size.y * 0.5), Vector2(t, hole.size.y)],
	]
	for e in edges:
		var fb := Vector3.ZERO
		fb[axis] = 0.05
		fb[u_axis] = e[1].x
		fb[v_axis] = e[1].y
		var fo := Vector3.ZERO
		fo[axis] = out
		fo[u_axis] = e[0].x
		fo[v_axis] = e[0].y
		_add_box(root, center + fo, fb, trim)


func _add_panel(root: Node3D, center: Vector3, axis: int, sgn: float, u_axis: int, v_axis: int, r: Rect2, mat: Material) -> void:
	var box_size := Vector3.ZERO
	box_size[axis] = WALL_T
	box_size[u_axis] = r.size.x
	box_size[v_axis] = r.size.y
	var off := Vector3.ZERO
	off[axis] = sgn * (ShipGrid.CELL * 0.5 - WALL_T * 0.5)
	off[u_axis] = r.position.x + r.size.x * 0.5
	off[v_axis] = r.position.y + r.size.y * 0.5
	_add_box(root, center + off, box_size, mat)


# --- External parts: simple solid shapes -----------------------------------------------------------

func _build_external(root: Node3D) -> void:
	var mat := _mat(color, 1.0)
	var dark := _mat(color.darkened(0.4), 1.0)
	var h := ShipGrid.CELL * 0.5

	if shape == &"frame":
		_add_frame_struts(root, Vector3.ZERO, 0.22, mat)
		for sx in [-1.0, 1.0]:  # bolted corner plates
			for sy in [-1.0, 1.0]:
				for sz in [-1.0, 1.0]:
					_add_box(root, Vector3(sx, sy, sz) * (h - 0.12), Vector3(0.36, 0.36, 0.36), dark)
	elif shape == &"rack":
		# Open gantry along Z with two containers per cell, side by side.
		for z in size.z:
			var centre := Vector3(0, 0, z * ShipGrid.CELL)
			_add_frame_struts(root, centre, 0.22, mat)
			for k in 2:
				_add_container(root, centre + Vector3(-0.6 + 1.2 * k, 0, 0), Vector3(1.0, 2.2, 2.6),
					CRATE_COLORS[(z * 2 + k) % CRATE_COLORS.size()], z * 2 + k, -1.1)
	elif shape == &"tank":
		# Cylinder lying along Z through the middle of the footprint.
		var cyl := CylinderMesh.new()
		cyl.top_radius = 1.2
		cyl.bottom_radius = 1.2
		cyl.height = ShipGrid.CELL * size.z - 0.4
		cyl.material = mat
		var mi := MeshInstance3D.new()
		mi.mesh = cyl
		mi.rotation_degrees.x = 90.0
		mi.position = Vector3(0, 0, ShipGrid.CELL * (size.z - 1) * 0.5)
		root.add_child(mi)
		var half_len := (ShipGrid.CELL * size.z - 0.4) * 0.5
		var mid_z := ShipGrid.CELL * (size.z - 1) * 0.5
		for z in [mid_z - half_len + 0.25, mid_z, mid_z + half_len - 0.25]:
			var band := CylinderMesh.new()
			band.top_radius = 1.27
			band.bottom_radius = 1.27
			band.height = 0.16
			band.material = dark
			var bi := MeshInstance3D.new()
			bi.mesh = band
			bi.rotation_degrees.x = 90.0
			bi.position = Vector3(0, 0, z)
			root.add_child(bi)
		for side in [-1.0, 1.0]:  # stencilled name on both sides
			var label := Label3D.new()
			label.text = "FUEL"
			label.font_size = 56
			label.pixel_size = 0.006
			label.modulate = Color(0.12, 0.13, 0.16)
			label.outline_size = 0
			label.position = Vector3(side * 1.215, 0, mid_z)
			label.rotation_degrees.y = 90.0 * side
			root.add_child(label)
	elif shape == &"legs":
		# Lander legs under the hull: four splayed struts to footpads, lift-jet nozzles between them.
		var steel := _mat(Color(0.55, 0.57, 0.6), 1.0)
		for sx in [-1.0, 1.0]:
			for sz in [-1.0, 1.0]:
				var top := Vector3(sx * 0.9, h - 0.15, sz * 0.9)
				var foot := Vector3(sx * 1.3, -h + 0.12, sz * 1.3)
				var leg := _add_box(root, (top + foot) * 0.5, Vector3(0.16, top.distance_to(foot), 0.16), steel)
				leg.look_at_from_position((top + foot) * 0.5, foot, Vector3(1, 0, 0) if absf(sx) < 0.5 else Vector3(0, 0, 1))
				leg.rotate_object_local(Vector3.RIGHT, PI * 0.5)
				_add_box(root, foot + Vector3(0, -0.05, 0), Vector3(0.6, 0.1, 0.6), dark)
		_add_box(root, Vector3(0, h - 0.2, 0), Vector3(2.2, 0.3, 2.2), dark)  # mounting plate
		for k in 4:
			var a := k * PI * 0.5 + PI * 0.25
			var nz := Vector3(cos(a) * 0.5, h - 0.6, sin(a) * 0.5)
			var bell := CylinderMesh.new()
			bell.top_radius = 0.18
			bell.bottom_radius = 0.32
			bell.height = 0.5
			bell.material = mat
			var bi := MeshInstance3D.new()
			bi.mesh = bell
			bi.position = nz
			root.add_child(bi)
			var plume := CylinderMesh.new()  # lift exhaust, shown while the jets fire
			plume.top_radius = 0.3
			plume.bottom_radius = 0.04
			plume.height = 2.2
			plume.material = _plume(Color(0.55, 0.75, 1.0))
			plume.cap_top = false
			plume.cap_bottom = false
			var pi_ := MeshInstance3D.new()
			pi_.mesh = plume
			pi_.position = nz + Vector3(0, -1.35, 0)
			pi_.set_meta("lift_flame", true)
			pi_.visible = false
			root.add_child(pi_)
	elif shape == &"drive":
		# A heavy ring on a short spine: the jump coil.
		var ring := TorusMesh.new()
		ring.inner_radius = 0.75
		ring.outer_radius = 1.2
		ring.material = mat
		var ri := MeshInstance3D.new()
		ri.mesh = ring
		ri.rotation_degrees.x = 90.0
		root.add_child(ri)
		_add_box(root, Vector3(-0.9, 0, 0), Vector3(0.5, 0.5, 0.5), dark)
		_add_box(root, Vector3.ZERO, Vector3(0.5, 0.5, 0.5), _glow(Color(0.5, 0.8, 1.0)))
	elif shape == &"radiator":
		# Flat panel standing off the west face on a short stub.
		_add_box(root, Vector3(-1.1, 0, 0), Vector3(0.12, 2.6, 2.6), dark)
		for k in 6:  # cooling fins
			_add_box(root, Vector3(-1.2, -1.1 + k * 0.44, 0), Vector3(0.16, 0.3, 2.4), mat)
		_add_box(root, Vector3(-1.3, 0, 0), Vector3(0.3, 0.4, 0.4), dark)
	elif shape == &"engine":
		# Mount plate at the front (-Z), nozzle flaring toward the back (+Z).
		var bell := CylinderMesh.new()
		bell.top_radius = 1.2
		bell.bottom_radius = 0.5
		bell.height = 2.4
		bell.material = mat
		var mi := MeshInstance3D.new()
		mi.mesh = bell
		mi.rotation_degrees.x = 90.0
		mi.position = Vector3(0, 0, 0.2)
		root.add_child(mi)
		_add_box(root, Vector3(0, 0, -1.25), Vector3(1.4, 1.4, 0.5), dark)
		var exit_disc := CylinderMesh.new()  # hot throat glowing inside the bell
		exit_disc.top_radius = 1.0
		exit_disc.bottom_radius = 1.0
		exit_disc.height = 0.04
		exit_disc.material = _glow(Color(1.0, 0.55, 0.2))
		var di := MeshInstance3D.new()
		di.mesh = exit_disc
		di.rotation_degrees.x = 90.0
		di.position = Vector3(0, 0, 1.2)
		root.add_child(di)
		for k in 2:   # exhaust plume, only shown while burning: a wide glow and a hot core
			var flame := CylinderMesh.new()
			flame.top_radius = 0.15 if k == 0 else 0.05
			flame.bottom_radius = 0.95 if k == 0 else 0.45
			flame.height = 5.5 if k == 0 else 3.0
			flame.radial_segments = 16
			flame.cap_top = false
			flame.cap_bottom = false
			flame.material = _plume(Color(1.0, 0.55, 0.2) if k == 0 else Color(0.75, 0.85, 1.0), k == 1)
			var fi := MeshInstance3D.new()
			fi.mesh = flame
			fi.rotation_degrees.x = 90.0
			fi.position = Vector3(0, 0, 1.3 + flame.height * 0.5)
			fi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			fi.visible = false
			fi.set_meta("flame", true)
			root.add_child(fi)
	else:
		var inset := Vector3.ONE * 0.4
		_add_box(root, Vector3(size - Vector3i.ONE) * ShipGrid.CELL * 0.5, Vector3(size) * ShipGrid.CELL - inset, mat)
	Interiors.dress_external(self, root)


## Twelve edge struts of one cell, centred on `centre`.
func _add_frame_struts(root: Node3D, centre: Vector3, t: float, mat: Material, proud := 0.0) -> void:
	var h := ShipGrid.CELL * 0.5
	for a in 3:
		var b := (a + 1) % 3
		var c := (a + 2) % 3
		for sb in [-1, 1]:
			for sc in [-1, 1]:
				var strut := Vector3.ZERO
				strut[a] = ShipGrid.CELL
				strut[b] = t
				strut[c] = t
				var off := Vector3.ZERO
				off[b] = sb * (h - t * 0.5 + proud)
				off[c] = sc * (h - t * 0.5 + proud)
				_add_box(root, centre + off, strut, mat)


func _add_box(root: Node3D, pos: Vector3, box_size: Vector3, mat: Material) -> MeshInstance3D:
	var box := BoxMesh.new()
	box.size = box_size
	box.material = mat
	var mi := MeshInstance3D.new()
	mi.mesh = box
	mi.position = pos
	root.add_child(mi)
	return mi
