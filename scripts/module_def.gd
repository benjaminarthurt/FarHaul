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
	var floor_mat := _mat(color.darkened(0.35), 1.0)
	var ceil_mat := _mat(color.lightened(0.25), 0.3)
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
			_add_face(root, Vector3(c) * ShipGrid.CELL, d, has_socket_at(c, d), mat)


static func _mat(col: Color, alpha: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(col, alpha)
	m.roughness = 0.9
	if alpha < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
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
		# Open cube: twelve edge struts.
		var t := 0.18
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
					off[b] = sb * (h - t * 0.5)
					off[c] = sc * (h - t * 0.5)
					_add_box(root, off, strut, mat)
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
	elif shape == &"radiator":
		# Flat panel standing off the west face on a short stub.
		_add_box(root, Vector3(-1.1, 0, 0), Vector3(0.12, 2.6, 2.6), mat)
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
	else:
		var inset := Vector3.ONE * 0.4
		_add_box(root, Vector3(size - Vector3i.ONE) * ShipGrid.CELL * 0.5, Vector3(size) * ShipGrid.CELL - inset, mat)


func _add_box(root: Node3D, pos: Vector3, box_size: Vector3, mat: Material) -> void:
	var box := BoxMesh.new()
	box.size = box_size
	box.material = mat
	var mi := MeshInstance3D.new()
	mi.mesh = box
	mi.position = pos
	root.add_child(mi)
