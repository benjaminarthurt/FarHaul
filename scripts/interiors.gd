class_name Interiors
extends RefCounted
## Set dressing that gives each kind of module its own look: seats and consoles in the cockpit, a
## reactor in engineering, bunks and a galley in the crew room, suit lockers in the airlock, and so on.
## All primitives, no art assets. Materials are shared so a ship with many modules stays cheap.
##
## Coordinates are in the module's own space: the origin cell is centred on (0, 0, 0), a cell is
## 3 m a side, "forward" is -Z, and FLOOR is the top of the deck plate.

const H := 1.5
const FLOOR := -1.38
const WALL_IN := 1.38  ## inner face of a wall, measured from the cell centre

static var _cache: Dictionary = {}


# --- Entry points ---------------------------------------------------------------------------------

static func dress(def: ModuleDef, root: Node3D) -> void:
	match String(def.id):
		"cockpit":
			_cockpit(root)
		"engineering":
			_engineering(root)
		"airlock":
			_airlock(root)
		"room_2x2":
			_crew_room(root)
		"corridor", "corner", "tee", "shaft":
			_connector(def, root)
		_:
			if def.cargo_slots > 0:
				_hold(root)


static func dress_external(def: ModuleDef, root: Node3D) -> void:
	var metal := flat(Color(0.20, 0.22, 0.26), 0.5, 0.5)
	var copper := flat(Color(0.72, 0.42, 0.20), 0.4, 0.7)
	var yellow := flat(Color(0.90, 0.72, 0.10), 0.6)
	match String(def.shape):
		"tank":
			var mid_z := ShipGrid.CELL * (def.size.z - 1) * 0.5
			var half := (ShipGrid.CELL * def.size.z - 0.4) * 0.5
			for z in [mid_z - half * 0.55, mid_z + half * 0.55]:  # saddles the vessel rests in
				_b(root, Vector3(0, -1.2, z), Vector3(2.0, 0.3, 0.3), metal)
				_b(root, Vector3(0, -1.38, z), Vector3(2.6, 0.12, 0.5), metal)
			_cyl(root, Vector3(0.62, 1.12, mid_z), 0.07, half * 2.0 - 0.4, copper, 2)  # feed line along the top
			_cyl(root, Vector3(0.62, 1.2, mid_z), 0.12, 0.2, metal)  # valve body
			_cyl(root, Vector3(0.62, 1.36, mid_z), 0.22, 0.03, flat(Color(0.8, 0.15, 0.1), 0.5))  # handwheel
			_b(root, Vector3(0, 0.0, mid_z + half + 0.05), Vector3(0.5, 0.5, 0.12), metal)  # fill port
		"radiator":
			for z in [-1.15, 1.15]:  # coolant manifolds feeding the fins
				_cyl(root, Vector3(-1.05, 0, z), 0.07, 2.5, copper)
			_b(root, Vector3(-1.45, 0, 0), Vector3(0.08, 2.0, 0.08), metal)
			_b(root, Vector3(-1.3, 1.35, 0), Vector3(0.1, 0.05, 2.4), flat(Color(0.8, 0.15, 0.1), 0.6))  # hot edge marking
		"engine":
			for s in [-1.0, 1.0]:  # gimbal actuators from the mount plate to the bell
				_cyl(root, Vector3(s * 0.75, 0.0, -0.45), 0.07, 1.0, metal, 2)
				_cyl(root, Vector3(s * 0.75, 0.0, -0.1), 0.11, 0.25, copper, 2)
			_cyl(root, Vector3(0, 0.95, -0.7), 0.25, 0.7, metal, 0)  # turbopump
			for s in [-1.0, 1.0]:
				_cyl(root, Vector3(s * 0.3, 0.62, -0.7), 0.06, 0.5, copper)
		"rack":
			for z in def.size.z:
				var zc := z * ShipGrid.CELL
				for dz in [-0.6, 0.6]:  # tie-down bars across the container tops
					_b(root, Vector3(0, 1.16, zc + dz), Vector3(2.6, 0.06, 0.06), yellow)
			_b(root, Vector3(-1.4, 1.4, -1.4), Vector3(0.14, 0.14, 0.14), glow(Color(1.0, 0.2, 0.15), 1.6))
			_b(root, Vector3(1.4, 1.4, -1.4), Vector3(0.14, 0.14, 0.14), glow(Color(0.2, 1.0, 0.3), 1.6))
		"frame":
			_cyl(root, Vector3(1.2, 1.35, 1.2), 0.03, 0.5, metal)  # little whip antenna
			_b(root, Vector3(1.2, 1.6, 1.2), Vector3(0.07, 0.07, 0.07), glow(Color(1.0, 0.3, 0.2), 1.5))


# --- Cockpit: windscreen, dash with screens, two seats, throttles, overhead switches ---------------

static func _cockpit(root: Node3D) -> void:
	var dark := flat(Color(0.10, 0.12, 0.15), 0.6, 0.3)
	var trim := flat(Color(0.24, 0.27, 0.32), 0.6, 0.3)
	var metal := flat(Color(0.16, 0.17, 0.2), 0.5, 0.5)

	# Windscreen: the glass is part of the hull wall (see ModuleDef); these are the inner mullions.
	for x in [-0.4, 0.4]:
		_b(root, Vector3(x, 0.4, -WALL_IN + 0.06), Vector3(0.08, 1.2, 0.08), trim)
	_b(root, Vector3(0, 1.02, -WALL_IN + 0.06), Vector3(2.5, 0.08, 0.08), trim)

	# Dash: solid body, sloped top carrying screens and rows of switches.
	_b(root, Vector3(0, FLOOR + 0.42, -1.12), Vector3(2.8, 0.84, 0.7), dark)
	var top := Node3D.new()
	top.position = Vector3(0, FLOOR + 0.92, -1.08)
	top.rotation_degrees.x = 16.0
	root.add_child(top)
	_b(top, Vector3.ZERO, Vector3(2.8, 0.1, 0.84), trim)
	var screen_cols := [Color(0.3, 0.85, 1.0), Color(0.3, 1.0, 0.5), Color(1.0, 0.7, 0.2), Color(0.3, 0.85, 1.0)]
	var screen_x := [-1.05, -0.38, 0.38, 1.05]
	for i in 4:
		_b(top, Vector3(screen_x[i], 0.06, -0.14), Vector3(0.55, 0.02, 0.34), dark)
		_b(top, Vector3(screen_x[i], 0.075, -0.14), Vector3(0.48, 0.01, 0.27), glow(screen_cols[i], 1.1))
	_buttons(top, Vector3(-1.2, 0.05, 0.16), 13, 2, 0.2, 0.12, 3, 1.0)

	# Overhead panel: rows of toggles and breakers above the pilots.
	var over := Node3D.new()
	over.position = Vector3(0, 1.12, -1.0)
	over.rotation_degrees.x = 14.0
	root.add_child(over)
	_b(over, Vector3.ZERO, Vector3(2.1, 0.1, 0.8), trim)
	_buttons(over, Vector3(-0.95, -0.05, -0.25), 12, 4, 0.17, 0.16, 11, -1.0)

	# Pilot and co-pilot.
	for x in [-0.62, 0.62]:
		_chair(root, Vector3(x, FLOOR, 0.15), 0.0, Color(0.30, 0.38, 0.52))
		_cyl(root, Vector3(x, FLOOR + 0.62, -0.5), 0.035, 0.5, metal)  # control column
		_b(root, Vector3(x, FLOOR + 0.9, -0.5), Vector3(0.42, 0.05, 0.05), metal)  # yoke bar
		for s in [-1.0, 1.0]:
			_b(root, Vector3(x + s * 0.2, FLOOR + 0.95, -0.5), Vector3(0.06, 0.16, 0.06), metal)

	# Centre pedestal with throttle levers.
	_b(root, Vector3(0, FLOOR + 0.2, -0.25), Vector3(0.34, 0.4, 1.0), dark)
	var lever_cols := [Color(0.85, 0.15, 0.12), Color(0.95, 0.7, 0.15), Color(0.85, 0.86, 0.84)]
	for i in 3:
		var lx := -0.1 + i * 0.1
		_b(root, Vector3(lx, FLOOR + 0.5, -0.5 + i * 0.07), Vector3(0.025, 0.2, 0.025), metal)
		_b(root, Vector3(lx, FLOOR + 0.62, -0.5 + i * 0.07), Vector3(0.07, 0.07, 0.07), flat(lever_cols[i], 0.5))
	_b(root, Vector3(0, FLOOR + 0.41, 0.0), Vector3(0.22, 0.01, 0.3), glow(Color(0.3, 0.85, 1.0), 0.9))  # pedestal display

	# Breaker panels on both side walls.
	for s in [-1.0, 1.0]:
		_b(root, Vector3(s * (WALL_IN - 0.04), -0.2, 0.3), Vector3(0.08, 1.2, 1.5), dark)
		for r in 4:
			for c in 5:
				_b(root, Vector3(s * (WALL_IN - 0.1), -0.65 + r * 0.28, -0.3 + c * 0.25), Vector3(0.03, 0.07, 0.1), _light(r, c, 5))
	_b(root, Vector3(0, 1.4, -0.2), Vector3(1.0, 0.03, 0.1), glow(Color(1.0, 0.92, 0.75), 0.45))
	_label(root, "FLIGHT DECK", Vector3(0, 1.1, WALL_IN), 180.0, Color(0.85, 0.82, 0.7))


static func _chair(root: Node3D, pos: Vector3, yaw: float, col: Color) -> void:
	var n := Node3D.new()
	n.position = pos
	n.rotation_degrees.y = yaw
	root.add_child(n)
	var fabric := flat(col, 0.9)
	var metal := flat(Color(0.15, 0.16, 0.19), 0.5, 0.4)
	_cyl(n, Vector3(0, 0.03, 0), 0.3, 0.06, metal)
	_cyl(n, Vector3(0, 0.22, 0), 0.06, 0.4, metal)
	_b(n, Vector3(0, 0.46, 0), Vector3(0.58, 0.12, 0.58), fabric)
	var back := _b(n, Vector3(0, 0.92, 0.3), Vector3(0.58, 0.85, 0.12), fabric)
	back.rotation_degrees.x = -8.0
	_b(n, Vector3(0, 1.42, 0.34), Vector3(0.34, 0.22, 0.1), fabric)
	for s in [-1.0, 1.0]:
		_b(n, Vector3(s * 0.33, 0.7, 0.0), Vector3(0.08, 0.06, 0.5), metal)
		_b(n, Vector3(s * 0.33, 0.58, 0.18), Vector3(0.06, 0.2, 0.06), metal)


# --- Engineering: reactor core, plumbing, pumps, control cabinets ---------------------------------

static func _engineering(root: Node3D) -> void:
	var steel := flat(Color(0.36, 0.38, 0.42), 0.45, 0.6)
	var dark := flat(Color(0.12, 0.13, 0.15), 0.6, 0.3)
	var copper := flat(Color(0.72, 0.42, 0.20), 0.4, 0.7)
	var blue := flat(Color(0.25, 0.45, 0.70), 0.5, 0.3)
	var cz := 0.1

	_b(root, Vector3(0, FLOOR + 0.012, cz), Vector3(2.0, 0.024, 2.0), SurfaceTextures.hazard_material())
	_cyl(root, Vector3(0, FLOOR + 0.1, cz), 0.85, 0.2, dark)
	_cyl(root, Vector3(0, -0.93, cz), 0.62, 0.5, steel)  # lower housing
	_cyl(root, Vector3(0, 1.07, cz), 0.62, 0.5, steel)  # upper housing
	_cyl(root, Vector3(0, 0.07, cz), 0.36, 1.5, glow(Color(1.0, 0.62, 0.25), 1.7))  # the core itself
	for k in 4:
		var a := k * PI * 0.5 + PI * 0.25
		_b(root, Vector3(cos(a) * 0.46, 0.07, cz + sin(a) * 0.46), Vector3(0.08, 1.5, 0.08), dark)
	for s in [-1.0, 1.0]:
		_cyl(root, Vector3(s * 0.99, 0.95, cz), 0.11, 0.9, copper, 0)  # hot leg
		_cyl(root, Vector3(s * 0.99, -0.85, cz), 0.11, 0.9, blue, 0)  # cold return
		_cyl(root, Vector3(s * 1.3, 0.05, cz), 0.09, 1.8, steel)  # riser tying them together
		_cyl(root, Vector3(s * 1.0, FLOOR + 0.45, 1.0), 0.3, 0.9, steel)  # coolant pump
		_cyl(root, Vector3(s * 1.0, FLOOR + 0.95, 1.0), 0.2, 0.1, dark)
		_b(root, Vector3(s * 0.7, FLOOR + 0.5, 1.0), Vector3(0.28, 0.06, 0.06), copper)
		_b(root, Vector3(s * 1.0, FLOOR + 0.6, 0.7), Vector3(0.1, 0.1, 0.03), glow(Color(0.3, 1.0, 0.4), 1.0))

	# Control cabinets along the back wall.
	for i in 3:
		var x := -0.95 + i * 0.95
		_b(root, Vector3(x, FLOOR + 0.95, 1.15), Vector3(0.85, 1.9, 0.45), dark)
		if i == 1:
			_b(root, Vector3(x, FLOOR + 1.3, 0.92), Vector3(0.62, 0.42, 0.02), glow(Color(0.3, 1.0, 0.55), 1.0))
			_buttons_wall(root, Vector3(x - 0.3, FLOOR + 0.7, 0.92), 6, 2, 0.12, 0.1, 5)
		else:
			_buttons_wall(root, Vector3(x - 0.32, FLOOR + 1.5, 0.92), 6, 6, 0.12, 0.12, 20 + i)
	_label(root, "REACTOR", Vector3(0, 1.05, WALL_IN), 180.0, Color(0.9, 0.55, 0.25))


# --- Airlock: bench with helmets, suit lockers, gauge panel ---------------------------------------

static func _airlock(root: Node3D) -> void:
	var dark := flat(Color(0.12, 0.13, 0.15), 0.6, 0.3)
	var steel := flat(Color(0.52, 0.55, 0.60), 0.6, 0.1)
	var white := flat(Color(0.86, 0.87, 0.84), 0.5)
	var strip := SurfaceTextures.hazard_material()

	_b(root, Vector3(0.1, FLOOR + 0.45, -1.15), Vector3(1.9, 0.08, 0.4), steel)  # bench
	for x in [-0.7, 0.9]:
		_b(root, Vector3(x, FLOOR + 0.22, -1.15), Vector3(0.08, 0.44, 0.34), dark)
	for x in [-0.4, 0.3]:  # two helmets waiting on the bench
		var sph := SphereMesh.new()
		sph.radius = 0.17
		sph.height = 0.34
		sph.radial_segments = 12
		sph.rings = 6
		sph.material = white
		var mi := MeshInstance3D.new()
		mi.mesh = sph
		mi.position = Vector3(x, FLOOR + 0.67, -1.12)
		root.add_child(mi)
		_b(root, Vector3(x, FLOOR + 0.68, -0.97), Vector3(0.22, 0.1, 0.06), glow(Color(1.0, 0.8, 0.4), 1.0))

	for i in 3:  # tall suit lockers
		var x := -0.6 + i * 0.6
		_b(root, Vector3(x, FLOOR + 0.98, 1.11), Vector3(0.56, 1.96, 0.5), steel)
		_b(root, Vector3(x, FLOOR + 0.98, 0.855), Vector3(0.03, 1.8, 0.015), dark)
		_b(root, Vector3(x + 0.08, FLOOR + 1.0, 0.855), Vector3(0.04, 0.2, 0.025), dark)
		_b(root, Vector3(x - 0.16, FLOOR + 1.78, 0.85), Vector3(0.07, 0.04, 0.02), glow(Color(0.3, 1.0, 0.4) if i != 2 else Color(1.0, 0.7, 0.2), 1.1))

	# Pressure panel above the bench.
	_b(root, Vector3(0.1, 0.1, -WALL_IN + 0.03), Vector3(0.95, 0.42, 0.05), dark)
	for k in 3:
		var c: Color = [Color(0.3, 1.0, 0.4), Color(1.0, 0.7, 0.2), Color(1.0, 0.25, 0.2)][k]
		_b(root, Vector3(-0.2 + k * 0.3, 0.1, -WALL_IN + 0.07), Vector3(0.12, 0.12, 0.03), glow(c, 1.2))
	_label(root, "AIRLOCK", Vector3(0.1, 0.7, -WALL_IN + 0.01), 0.0, Color(0.85, 0.82, 0.7))
	_b(root, Vector3(1.18, FLOOR + 0.015, 0.0), Vector3(0.3, 0.03, 1.4), strip)  # threshold at the outer hatch
	_cyl(root, Vector3(0, 1.42, 0), 0.08, 0.05, glow(Color(1.0, 0.6, 0.15), 0.8))  # amber beacon


# --- Crew room: bunks, table, galley, lockers, desk -----------------------------------------------
# The 2x2 room spans x -1.5..4.5, z -1.5..4.5 (doors: N at x=0, W at z=3, E at z=0, S at x=3).

static func _crew_room(root: Node3D) -> void:
	var dark := flat(Color(0.12, 0.13, 0.15), 0.6, 0.3)
	var steel := flat(Color(0.52, 0.55, 0.60), 0.6, 0.1)
	var wood := flat(Color(0.52, 0.38, 0.24), 0.8)
	var white := flat(Color(0.86, 0.87, 0.84), 0.5)

	_bunk(root, Vector3(3.2, FLOOR, -0.98), 90.0, 1.6)
	_bunk(root, Vector3(4.05, FLOOR, 2.3), 0.0, 2.0)

	# Table with two stools.
	_b(root, Vector3(1.5, FLOOR + 0.75, 1.5), Vector3(1.3, 0.06, 0.8), wood)
	_cyl(root, Vector3(1.5, FLOOR + 0.36, 1.5), 0.07, 0.72, steel)
	_cyl(root, Vector3(1.5, FLOOR + 0.03, 1.5), 0.3, 0.06, steel)
	for x in [0.6, 2.4]:
		_cyl(root, Vector3(x, FLOOR + 0.22, 1.5), 0.2, 0.44, flat(Color(0.55, 0.22, 0.18), 0.9))

	# Galley along the south wall.
	var gz := 4.08
	_b(root, Vector3(0.7, FLOOR + 0.45, gz), Vector3(2.4, 0.9, 0.6), steel)
	_b(root, Vector3(0.7, FLOOR + 0.92, gz), Vector3(2.4, 0.05, 0.62), dark)
	for x in [0.25, 0.62]:  # hob
		_cyl(root, Vector3(x, FLOOR + 0.96, gz), 0.15, 0.02, glow(Color(1.0, 0.45, 0.15), 1.2))
	_b(root, Vector3(1.35, FLOOR + 0.93, gz), Vector3(0.5, 0.03, 0.4), steel)  # sink
	_cyl(root, Vector3(1.35, FLOOR + 1.1, gz + 0.2), 0.02, 0.3, steel)
	_b(root, Vector3(-1.1, FLOOR + 0.9, gz), Vector3(0.62, 1.8, 0.62), white)  # fridge
	_b(root, Vector3(-1.1, FLOOR + 1.3, gz - 0.32), Vector3(0.03, 0.4, 0.03), dark)
	_b(root, Vector3(0.7, 0.55, 4.2), Vector3(2.4, 0.6, 0.35), steel)  # upper cabinets
	for x in [0.1, 0.7, 1.3]:
		_b(root, Vector3(x, 0.55, 4.02), Vector3(0.015, 0.55, 0.02), dark)
	_label(root, "GALLEY", Vector3(0.7, 1.0, 4.37), 180.0, Color(0.85, 0.82, 0.7))

	# Lockers along the north wall.
	for i in 3:
		var x := 1.05 + i * 0.52
		_b(root, Vector3(x, FLOOR + 0.95, -WALL_IN + 0.25), Vector3(0.5, 1.9, 0.5), steel)
		_b(root, Vector3(x, FLOOR + 0.95, -WALL_IN + 0.51), Vector3(0.02, 1.7, 0.015), dark)
	_label(root, "CREW", Vector3(1.55, 0.95, -WALL_IN + 0.01), 0.0, Color(0.85, 0.82, 0.7))

	# Desk with a screen against the west wall.
	_b(root, Vector3(-1.15, FLOOR + 0.75, 0.9), Vector3(0.6, 0.06, 1.4), wood)
	for z in [0.3, 1.5]:
		_b(root, Vector3(-1.15, FLOOR + 0.36, z), Vector3(0.5, 0.72, 0.06), steel)
	_b(root, Vector3(-1.3, FLOOR + 1.08, 0.9), Vector3(0.05, 0.4, 0.62), dark)
	_b(root, Vector3(-1.27, FLOOR + 1.08, 0.9), Vector3(0.015, 0.32, 0.54), glow(Color(0.3, 0.85, 1.0), 0.9))
	_chair(root, Vector3(-0.45, FLOOR, 0.9), 90.0, Color(0.30, 0.20, 0.16))

	for p in [Vector3(1.5, 1.4, 0.2), Vector3(1.5, 1.4, 3.0)]:
		_b(root, p, Vector3(0.9, 0.03, 0.1), glow(Color(1.0, 0.92, 0.75), 0.45))


static func _bunk(root: Node3D, pos: Vector3, yaw: float, length: float) -> void:
	var n := Node3D.new()
	n.position = pos
	n.rotation_degrees.y = yaw
	root.add_child(n)
	var frame := flat(Color(0.52, 0.55, 0.60), 0.6, 0.1)
	var mattress := flat(Color(0.78, 0.76, 0.68), 0.9)
	var blanket := flat(Color(0.20, 0.34, 0.52), 0.95)
	var w := 0.8
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			_b(n, Vector3(sx * (w * 0.5), 0.9, sz * (length * 0.5)), Vector3(0.06, 1.8, 0.06), frame)
	for y in [0.42, 1.28]:
		_b(n, Vector3(0, y, 0), Vector3(w, 0.1, length), frame)
		_b(n, Vector3(0, y + 0.1, 0.0), Vector3(w - 0.06, 0.1, length - 0.06), mattress)
		_b(n, Vector3(0, y + 0.16, length * 0.15), Vector3(w - 0.08, 0.04, length * 0.65), blanket)
		_b(n, Vector3(0, y + 0.18, -length * 0.4), Vector3(0.5, 0.08, 0.3), flat(Color(0.9, 0.9, 0.86), 0.9))  # pillow
	_b(n, Vector3(w * 0.5, 1.5, 0.0), Vector3(0.03, 0.12, length * 0.7), frame)  # upper guard rail
	for i in 5:  # ladder rungs at the foot
		_b(n, Vector3(0.0, 0.3 + i * 0.28, length * 0.5 + 0.02), Vector3(0.4, 0.03, 0.03), frame)


# --- Cargo hold: gantry, hoist, aisle markings ----------------------------------------------------

static func _hold(root: Node3D) -> void:
	var yellow := flat(Color(0.90, 0.72, 0.10), 0.6)
	var dark := flat(Color(0.12, 0.13, 0.15), 0.6, 0.3)
	var strip := SurfaceTextures.hazard_material()
	var length := 5.4
	var zc := ShipGrid.CELL * 0.5  # the hold is two cells long, so its middle is half a cell on
	for sx in [-1.0, 1.0]:
		_b(root, Vector3(sx * 0.62, FLOOR + 0.012, zc), Vector3(0.1, 0.024, length), strip)
	_b(root, Vector3(0, 1.3, zc), Vector3(0.16, 0.18, length), yellow)  # overhead gantry rail
	_b(root, Vector3(0, 1.18, zc + 0.7), Vector3(0.5, 0.2, 0.6), dark)  # trolley
	_cyl(root, Vector3(0, 0.7, zc + 0.7), 0.02, 0.8, dark)  # chain
	_b(root, Vector3(0, 0.25, zc + 0.7), Vector3(0.14, 0.16, 0.1), yellow)  # hook block
	for p in [Vector3(0.5, 1.42, zc - 1.1), Vector3(-0.5, 1.42, zc + 1.4)]:
		_b(root, p, Vector3(0.3, 0.03, 0.2), glow(Color(1.0, 0.92, 0.75), 0.45))
	for z in [zc - 1.4, zc + 1.4]:  # lashing rings in the deck
		_cyl(root, Vector3(0, FLOOR + 0.01, z), 0.1, 0.02, dark)


# --- Corridors, corners, tees and the ladder shaft ------------------------------------------------

static func _connector(def: ModuleDef, root: Node3D) -> void:
	var pipe_a := flat(Color(0.25, 0.45, 0.70), 0.5, 0.3)
	var pipe_b := flat(Color(0.55, 0.57, 0.60), 0.5, 0.6)
	var dark := flat(Color(0.12, 0.13, 0.15), 0.6, 0.3)
	var open: Array[Vector3i] = []
	for sk in def.sockets:
		if sk.kind == ModuleSocket.DOOR and sk.dir.y == 0:
			open.append(sk.dir)
	_b(root, Vector3(0, 1.4, 0), Vector3(0.6, 0.03, 0.2), glow(Color(1.0, 0.92, 0.75), 0.45))
	for d in open:
		var v := Vector3(d)
		var side := Vector3(-v.z, 0, v.x)
		var axis := 0 if d.x != 0 else 2
		_cyl(root, v * 0.75 + side * 0.95 + Vector3(0, 1.2, 0), 0.07, 1.5, pipe_a, axis)
		_cyl(root, v * 0.75 - side * 0.95 + Vector3(0, 1.2, 0), 0.05, 1.5, pipe_b, axis)
		var run := Vector3(1.5, 0.05, 0.4) if d.x != 0 else Vector3(0.4, 0.05, 1.5)
		_b(root, v * 0.75 + Vector3(0, 1.42, 0), run, dark)
		var grate := Vector3(1.5, 0.012, 0.8) if d.x != 0 else Vector3(0.8, 0.012, 1.5)
		_b(root, v * 0.75 + Vector3(0, FLOOR + 0.006, 0), grate, dark)

	var blank := 0
	for d in [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]:
		if open.has(d):
			continue
		var wall := Node3D.new()  # local +Z points into the room
		wall.position = Vector3(d) * WALL_IN
		wall.rotation.y = atan2(-float(d.x), -float(d.z))
		root.add_child(wall)
		if def.id == &"shaft" and d == Vector3i(-1, 0, 0):
			_ladder(wall)
		else:
			_wall_item(wall, _hash(blank, d.x * 3 + d.z, String(def.id).length()) % 4)
		blank += 1

	if def.id == &"shaft":  # hazard frame around the hatch in the floor
		var hz := SurfaceTextures.hazard_material()
		for s in [-1.0, 1.0]:
			_b(root, Vector3(0, FLOOR + 0.012, s * 0.78), Vector3(1.7, 0.024, 0.12), hz)
			_b(root, Vector3(s * 0.78, FLOOR + 0.012, 0), Vector3(0.12, 0.024, 1.44), hz)


static func _ladder(wall: Node3D) -> void:
	var yellow := flat(Color(0.90, 0.72, 0.10), 0.6)
	for s in [-1.0, 1.0]:
		_b(wall, Vector3(s * 0.24, 0.05, 0.1), Vector3(0.05, 2.9, 0.05), yellow)
	for i in 9:
		_b(wall, Vector3(0, FLOOR + 0.3 + i * 0.32, 0.1), Vector3(0.5, 0.04, 0.04), yellow)
	_b(wall, Vector3(0, 0.5, 0.04), Vector3(0.6, 0.02, 0.02), flat(Color(0.12, 0.13, 0.15), 0.6))


## Local space: +Z into the room, y relative to the cell centre.
static func _wall_item(wall: Node3D, kind: int) -> void:
	var dark := flat(Color(0.12, 0.13, 0.15), 0.6, 0.3)
	var steel := flat(Color(0.52, 0.55, 0.60), 0.6, 0.1)
	var white := flat(Color(0.86, 0.87, 0.84), 0.5)
	var red := flat(Color(0.78, 0.14, 0.12), 0.5)
	match kind:
		0:  # equipment locker
			_b(wall, Vector3(0, FLOOR + 0.9 - 0.0, 0.2), Vector3(0.9, 1.8, 0.4), steel)
			_b(wall, Vector3(0, FLOOR + 0.9, 0.405), Vector3(0.02, 1.6, 0.012), dark)
			_b(wall, Vector3(0.3, FLOOR + 1.7, 0.41), Vector3(0.07, 0.04, 0.02), glow(Color(0.3, 1.0, 0.4), 1.1))
		1:  # wall display
			_b(wall, Vector3(0, 0.15, 0.04), Vector3(0.86, 0.56, 0.06), dark)
			_b(wall, Vector3(0, 0.15, 0.075), Vector3(0.76, 0.46, 0.01), glow(Color(0.2, 0.6, 0.8), 0.5))
		2:  # extinguisher and first-aid box
			_cyl(wall, Vector3(0.45, -0.2, 0.12), 0.09, 0.45, red)
			_cyl(wall, Vector3(0.45, 0.06, 0.12), 0.04, 0.08, dark)
			_b(wall, Vector3(-0.35, -0.05, 0.07), Vector3(0.4, 0.34, 0.14), white)
			_b(wall, Vector3(-0.35, -0.05, 0.145), Vector3(0.2, 0.06, 0.012), red)
			_b(wall, Vector3(-0.35, -0.05, 0.145), Vector3(0.06, 0.2, 0.012), red)
		_:  # junction box with conduits
			_b(wall, Vector3(0, 0.0, 0.08), Vector3(0.7, 0.9, 0.16), dark)
			for r in 3:
				for c in 3:
					_b(wall, Vector3(-0.2 + c * 0.2, 0.25 - r * 0.2, 0.165), Vector3(0.07, 0.07, 0.02), _light(r, c, 7))
			_cyl(wall, Vector3(0.0, 0.9, 0.08), 0.05, 0.9, steel)


# --- Small helpers --------------------------------------------------------------------------------

static func _hash(a: int, b: int, c: int) -> int:
	return absi((a * 73856093) ^ (b * 19349663) ^ (c * 83492791))


## One indicator: most are dark, some glow green, amber, red or cyan.
static func _light(r: int, c: int, seed_value: int) -> Material:
	var v := _hash(r, c, seed_value) % 100
	if v < 14:
		return glow(Color(0.3, 1.0, 0.4), 1.0)
	if v < 26:
		return glow(Color(1.0, 0.7, 0.2), 1.0)
	if v < 32:
		return glow(Color(1.0, 0.25, 0.2), 1.0)
	if v < 40:
		return glow(Color(0.3, 0.85, 1.0), 1.0)
	return flat(Color(0.2, 0.22, 0.26).lerp(Color(0.38, 0.4, 0.44), float(v % 7) / 7.0), 0.6, 0.2)


## Grid of switches lying flat on a (possibly tilted) parent. `up` is +1 on top faces, -1 on undersides.
static func _buttons(parent: Node3D, origin: Vector3, cols: int, rows: int, dx: float, dz: float, seed_value: int, up: float) -> void:
	for r in rows:
		for c in cols:
			var size := Vector3(0.06, 0.035, 0.06)
			_b(parent, origin + Vector3(c * dx, up * 0.02, r * dz), size, _light(r, c, seed_value))


## Grid of lamps on a wall facing -Z (so they are seen from the room side at smaller z).
static func _buttons_wall(parent: Node3D, origin: Vector3, cols: int, rows: int, dx: float, dy: float, seed_value: int) -> void:
	for r in rows:
		for c in cols:
			_b(parent, origin + Vector3(c * dx, r * dy, 0), Vector3(0.07, 0.07, 0.02), _light(r, c, seed_value))


static func flat(col: Color, rough := 0.75, metal := 0.0) -> StandardMaterial3D:
	var key := "f%s|%s|%s" % [col.to_html(), rough, metal]
	if _cache.has(key):
		return _cache[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = rough
	m.metallic = minf(metal, 0.2)  # strong metal goes black against a dark sky
	_cache[key] = m
	return m


static func glow(col: Color, energy := 1.2) -> StandardMaterial3D:
	var key := "g%s|%s" % [col.to_html(), energy]
	if _cache.has(key):
		return _cache[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.emission_enabled = true
	m.emission = col
	m.emission_energy_multiplier = energy
	_cache[key] = m
	return m


static func glass(col: Color, alpha: float) -> StandardMaterial3D:
	var key := "t%s|%s" % [col.to_html(), alpha]
	if _cache.has(key):
		return _cache[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(col, alpha)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.emission_enabled = true
	m.emission = col
	m.emission_energy_multiplier = 0.35
	m.roughness = 0.1
	_cache[key] = m
	return m


static func _b(root: Node3D, pos: Vector3, size: Vector3, mat: Material) -> MeshInstance3D:
	var box := BoxMesh.new()
	box.size = size
	box.material = mat
	var mi := MeshInstance3D.new()
	mi.mesh = box
	mi.position = pos
	root.add_child(mi)
	return mi


## Cylinder along Y (axis 1), X (axis 0) or Z (axis 2).
static func _cyl(root: Node3D, pos: Vector3, radius: float, height: float, mat: Material, axis := 1) -> MeshInstance3D:
	var c := CylinderMesh.new()
	c.top_radius = radius
	c.bottom_radius = radius
	c.height = height
	c.radial_segments = 12
	c.rings = 1
	c.material = mat
	var mi := MeshInstance3D.new()
	mi.mesh = c
	mi.position = pos
	if axis == 0:
		mi.rotation_degrees.z = 90.0
	elif axis == 2:
		mi.rotation_degrees.x = 90.0
	root.add_child(mi)
	return mi


## Stencilled text on a wall. `yaw` 0 faces +Z (for a north wall), 180 faces -Z (for a south wall).
static func _label(root: Node3D, text: String, pos: Vector3, yaw: float, col: Color) -> void:
	var l := Label3D.new()
	l.text = text
	l.font_size = 48
	l.pixel_size = 0.005
	l.modulate = col
	l.outline_size = 0
	l.position = pos
	l.rotation_degrees.y = yaw
	root.add_child(l)
