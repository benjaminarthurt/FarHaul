class_name ModuleLibrary
extends RefCounted
## The catalogue of placeable modules. For now they're defined in code with placeholder
## visuals; later you can swap in real ModuleDef .tres files with `scene` set.
##
## Units: mass in tonnes, cost in credits, power and heat in kW, thrust in kN.

const DIR_N := Vector3i(0, 0, -1)  # ship front
const DIR_S := Vector3i(0, 0, 1)  # ship back
const DIR_E := Vector3i(1, 0, 0)
const DIR_W := Vector3i(-1, 0, 0)
const DIR_U := Vector3i(0, 1, 0)
const DIR_D := Vector3i(0, -1, 0)

var defs: Dictionary = {}  # StringName -> ModuleDef
var order: Array[StringName] = []  # display order for the palette


func _init() -> void:
	_add_defaults()


func register(def: ModuleDef) -> void:
	defs[def.id] = def
	order.append(def.id)


func get_def(id: StringName) -> ModuleDef:
	return defs.get(id)


func has_def(id: StringName) -> bool:
	return defs.has(id)


func _def(id: StringName, label: String, size: Vector3i, col: Color, socket_list: Array, stats: Dictionary = {}) -> void:
	var d := ModuleDef.new()
	d.id = id
	d.display_name = label
	d.size = size
	d.color = col
	for s in socket_list:
		d.sockets.append(s)
	for key in stats:
		d.set(key, stats[key])
	register(d)


func _door(c: Vector3i, d: Vector3i) -> ModuleSocket:
	return ModuleSocket.make(c, d, ModuleSocket.DOOR)


func _mount(c: Vector3i, d: Vector3i) -> ModuleSocket:
	return ModuleSocket.make(c, d, ModuleSocket.MOUNT)


func _add_defaults() -> void:
	var o := Vector3i.ZERO
	var one := Vector3i(1, 1, 1)
	var steel := Color(0.40, 0.44, 0.50)

	# --- Pressurised hull (walkable) ---
	_def(&"corridor", "Corridor", one, steel,
		[_door(o, DIR_N), _door(o, DIR_S)],
		{"mass": 0.8, "cost": 2000})
	_def(&"corner", "Corner", one, steel,
		[_door(o, DIR_N), _door(o, DIR_E)],
		{"mass": 0.8, "cost": 2200})
	_def(&"tee", "T-junction", one, steel,
		[_door(o, DIR_N), _door(o, DIR_S), _door(o, DIR_E)],
		{"mass": 1.0, "cost": 2600})
	_def(&"shaft", "Ladder shaft", one, Color(0.55, 0.50, 0.28),
		[_door(o, DIR_U), _door(o, DIR_D), _door(o, DIR_N), _door(o, DIR_S)],
		{"mass": 1.2, "cost": 3000})
	_def(&"room_2x2", "Crew quarters 2x2", Vector3i(2, 1, 2), Color(0.30, 0.45, 0.40),
		[
			_door(Vector3i(0, 0, 0), DIR_N), _door(Vector3i(1, 0, 1), DIR_S),
			_door(Vector3i(0, 0, 1), DIR_W), _door(Vector3i(1, 0, 0), DIR_E),
		],
		{"mass": 4.0, "cost": 9000, "berths": 2})
	_def(&"bunk", "Crew bunk", one, Color(0.30, 0.45, 0.40),
		[_door(o, DIR_N), _door(o, DIR_S)],
		{"mass": 1.0, "cost": 3000, "berths": 1})
	_def(&"cockpit", "Cockpit", one, Color(0.28, 0.42, 0.62),
		[_door(o, DIR_S)],
		{"mass": 2.0, "cost": 12000, "power": -3.0, "heat": 3.0, "helm": true, "berths": 1})
	_def(&"engineering", "Engineering", one, Color(0.55, 0.28, 0.25),
		[_door(o, DIR_N)],
		{"mass": 6.0, "cost": 30000, "power": 100.0, "heat": 120.0})

	# Airlock: the crew's way in and out. Door on the west face, outer hatch on the east.
	_def(&"airlock", "Airlock", one, Color(0.50, 0.47, 0.24),
		[_door(o, DIR_W)],
		{"mass": 1.5, "cost": 9000, "power": -1.0, "airlock": true})

	# --- Cargo ---
	# Hold: pressurised and walkable, so freight is protected and can be reached from inside.
	_def(&"cargo_hold", "Cargo hold 1x2", Vector3i(1, 1, 2), Color(0.38, 0.43, 0.35),
		[_door(Vector3i(0, 0, 0), DIR_N), _door(Vector3i(0, 0, 1), DIR_S)],
		{"group": &"cargo", "mass": 3.0, "cost": 6000, "cargo_slots": 4, "cargo_capacity": 24.0})
	# Rack: bare gantry carrying full-size containers outside. Cheap and big, but exposed.
	_def(&"cargo_rack", "Cargo rack 1x2", Vector3i(1, 1, 2), Color(0.30, 0.32, 0.36),
		[
			_mount(Vector3i(0, 0, 0), DIR_N), _mount(Vector3i(0, 0, 1), DIR_S),
			_mount(Vector3i(0, 0, 0), DIR_E), _mount(Vector3i(0, 0, 1), DIR_E),
			_mount(Vector3i(0, 0, 0), DIR_W), _mount(Vector3i(0, 0, 1), DIR_W),
			_mount(Vector3i(0, 0, 0), DIR_U), _mount(Vector3i(0, 0, 1), DIR_U),
			_mount(Vector3i(0, 0, 0), DIR_D), _mount(Vector3i(0, 0, 1), DIR_D),
		],
		{"group": &"cargo", "pressurized": false, "shape": &"rack", "mass": 1.2, "cost": 4000,
			"cargo_slots": 4, "cargo_capacity": 40.0})

	# --- External parts (not walkable; bolt onto frames or bare hull faces) ---
	_def(&"frame", "Frame", one, Color(0.32, 0.34, 0.38),
		[
			_mount(o, DIR_N), _mount(o, DIR_S), _mount(o, DIR_E),
			_mount(o, DIR_W), _mount(o, DIR_U), _mount(o, DIR_D),
		],
		{"group": &"external", "pressurized": false, "shape": &"frame", "mass": 0.4, "cost": 1500})
	_def(&"tank", "Fuel tank 1x2", Vector3i(1, 1, 2), Color(0.72, 0.72, 0.68),
		[
			_mount(Vector3i(0, 0, 0), DIR_N), _mount(Vector3i(0, 0, 1), DIR_S),
			_mount(Vector3i(0, 0, 0), DIR_E), _mount(Vector3i(0, 0, 1), DIR_E),
			_mount(Vector3i(0, 0, 0), DIR_W), _mount(Vector3i(0, 0, 1), DIR_W),
		],
		{"group": &"external", "pressurized": false, "shape": &"tank", "mass": 1.0, "cost": 4000, "fuel": 10.0})
	_def(&"radiator", "Radiator", one, Color(0.55, 0.58, 0.62),
		[_mount(o, DIR_W)],
		{"group": &"external", "pressurized": false, "shape": &"radiator", "mass": 0.6, "cost": 3000, "heat": -60.0})
	_def(&"engine", "Engine", one, Color(0.80, 0.45, 0.20),
		[_mount(o, DIR_N)],
		{"group": &"external", "pressurized": false, "shape": &"engine", "mass": 3.0, "cost": 20000,
			"thrust": 80.0, "power": -15.0, "heat": 25.0})
	# Jump drive: bolts on like any external part and makes the ship faster between stars. It needs
	# power and sheds heat, and its mass counts against thrust-to-weight like everything else.
	_def(&"jump_drive", "Jump drive", one, Color(0.35, 0.50, 0.75),
		[_mount(o, DIR_W)],
		{"group": &"external", "pressurized": false, "shape": &"drive", "mass": 4.0, "cost": 45000,
			"drive": 0.30, "power": -40.0, "heat": 50.0})
