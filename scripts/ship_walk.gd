class_name ShipWalk
extends RefCounted
## Walking inside the ship, as plain maths (no physics engine, tested headless in tests/test_walk.gd).
##
## Space is the ship's own layout space, the same space ShipView builds in: a cell is 3 m, forward is -Z,
## a deck is one cell high. The walker is a circle on the deck plate of one level. It is stopped by:
##   - hull walls: every side of every pressurised cell, except between two cells of the same module
##     and except a 1.4 m doorway where two modules' doors meet;
##   - furniture and freight: the footprint of everything the interiors put on the deck at body height
##     (seats, the dash, the reactor, bunks, containers), read from the built visuals so new rooms
##     need no extra data.
## Ladder shafts move the walker a deck up or down (`climb`). The deck has artificial gravity, so "down"
## is always the deck plate whatever the ship is doing.

const RADIUS := 0.25          ## shoulders, as a circle
const EYE := 1.65             ## eye height above the deck plate
const WALK_SPEED := 2.2       ## m/s
const RUN_SPEED := 4.0
const BODY_LOW := 0.1         ## furniture counts as an obstacle if it reaches between these heights
const BODY_HIGH := 1.5        ## above the deck (a hook hanging at head height does not stop you)
const REACH := 1.2            ## how close to stand to use the helm
const HATCH_REACH := 0.8      ## how close to a shaft's centre to climb

var walls := {}               ## level -> Array[Rect2] in (x, z)
var furniture := {}           ## level -> Array[Rect2]
var cells := {}               ## Vector3i -> module index, walkable cells only
var hatches := {}             ## Vector3i -> {"up": bool, "down": bool}
var names := {}               ## module index -> display name
var helm_seat := Vector3.INF  ## the pilot's seat, at deck level
var helm_face := Vector3(0, 0, -1)
var helm_stand := Vector3.INF ## where you stand up: on the cockpit's centre line, behind the seats
var airlock := Vector3.INF    ## centre of the airlock, at deck level
var airlock_face := Vector3(-1, 0, 0)  ## towards the airlock's inner door

var pos := Vector3.ZERO       ## feet, on the deck plate
var yaw := 0.0                ## 0 looks down -Z (towards the bow)
var pitch := 0.0


static func deck_y(level: int) -> float:
	return float(level) * ShipGrid.CELL + Interiors.FLOOR


## Builds the walkable space from the ship's data and (optionally) the ShipView already built from it,
## for the furniture. Without a view, rooms are empty boxes.
static func build(ship: ShipData, view: Node3D = null) -> ShipWalk:
	var w := ShipWalk.new()
	var lib := ship.library
	var door_at := {}   # "cell|dir" -> true for every door socket on a pressurised module
	for i in ship.modules.size():
		var m: Dictionary = ship.modules[i]
		var def := lib.get_def(m.id)
		if not def.pressurized:
			continue
		w.names[i] = def.display_name
		for c in ship.world_cells(m.id, m.cell, m.rot):
			w.cells[c] = i
		for s in ship.world_sockets(m.id, m.cell, m.rot):
			if s.kind == ModuleSocket.DOOR:
				door_at[_key(s.cell, s.dir)] = true
		var centre := ShipGrid.cell_to_world(m.cell)
		var turn := Basis(Vector3.UP, m.rot * PI / 2.0)
		if def.helm and w.helm_seat == Vector3.INF:
			w.helm_seat = centre + turn * Vector3(-0.62, 0, 0.15)
			w.helm_seat.y = deck_y(m.cell.y)
			w.helm_face = turn * Vector3(0, 0, -1)
			w.helm_stand = centre + turn * Vector3(0, 0, 0.9)
			w.helm_stand.y = w.helm_seat.y
		if def.airlock and w.airlock == Vector3.INF:
			w.airlock = centre
			w.airlock.y = deck_y(m.cell.y)
			for s in ship.world_sockets(m.id, m.cell, m.rot):
				if s.kind == ModuleSocket.DOOR and s.dir.y == 0:
					w.airlock_face = Vector3(s.dir)
	var h := ShipGrid.CELL * 0.5
	var inner := h - ModuleDef.WALL_T
	for c in w.cells:
		var level: int = c.y
		var mine: int = w.cells[c]
		var centre := ShipGrid.cell_to_world(c)
		for d in [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]:
			var n: Vector3i = c + d
			if w.cells.get(n, -1) == mine:
				continue  # inside one module: open floor
			var open: bool = door_at.has(_key(c, d)) and door_at.has(_key(n, -d)) and w.cells.has(n)
			w._add_wall(level, centre, d, inner, h, open)
		var up: bool = door_at.has(_key(c, Vector3i.UP)) and door_at.has(_key(c + Vector3i.UP, Vector3i.DOWN)) and w.cells.has(c + Vector3i.UP)
		var down: bool = door_at.has(_key(c, Vector3i.DOWN)) and door_at.has(_key(c + Vector3i.DOWN, Vector3i.UP)) and w.cells.has(c + Vector3i.DOWN)
		if up or down:
			w.hatches[c] = {"up": up, "down": down}
	if view != null:
		var kids := view.get_children()
		for i in mini(ship.modules.size(), kids.size()):
			if not w.names.has(i):
				continue
			var node: Node = kids[i]
			if node is Node3D:
				w._collect(node, (node as Node3D).transform, false, int(ship.modules[i].cell.y))
	return w


static func _key(c: Vector3i, d: Vector3i) -> String:
	return "%d,%d,%d|%d,%d,%d" % [c.x, c.y, c.z, d.x, d.y, d.z]


## One side of a cell: a slab from the inner face of the wall to the cell boundary, with a doorway
## left open in the middle when two doors meet there.
func _add_wall(level: int, centre: Vector3, d: Vector3i, inner: float, h: float, open: bool) -> void:
	var list: Array = walls.get(level, [])
	var t := h - inner
	var spans: Array = [[-h - t, h + t]]
	if open:
		spans = [[-h - t, -ModuleDef.DOOR_HALF_W], [ModuleDef.DOOR_HALF_W, h + t]]
	for sp in spans:
		var a: float = sp[0]
		var b: float = sp[1]
		var r: Rect2
		if d.x != 0:
			var x0 := centre.x + (inner if d.x > 0 else -h)
			r = Rect2(x0, centre.z + a, t, b - a)
		else:
			var z0 := centre.z + (inner if d.z > 0 else -h)
			r = Rect2(centre.x + a, z0, b - a, t)
		list.append(r)
	walls[level] = list


func _collect(node: Node, xf: Transform3D, solid: bool, level: int) -> void:
	if node is Node3D and not (node as Node3D).visible:
		return
	solid = solid or node.has_meta("solid")
	if solid and node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		var box: AABB = xf * (node as MeshInstance3D).mesh.get_aabb()
		var deck := deck_y(level)
		if box.end.y > deck + BODY_LOW and box.position.y < deck + BODY_HIGH:
			var list: Array = furniture.get(level, [])
			list.append(Rect2(box.position.x, box.position.z, box.size.x, box.size.z))
			furniture[level] = list
	for child in node.get_children():
		if child is Node3D:
			_collect(child, xf * (child as Node3D).transform, solid, level)


# --- Where to stand --------------------------------------------------------------------------------

func level() -> int:
	return roundi((pos.y - Interiors.FLOOR) / ShipGrid.CELL)


func cell() -> Vector3i:
	return Vector3i(roundi(pos.x / ShipGrid.CELL), level(), roundi(pos.z / ShipGrid.CELL))


func eye() -> Vector3:
	return pos + Vector3(0, EYE, 0)


## Which way the walker is looking, in ship space.
func look_basis() -> Basis:
	return Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, pitch)


func face(dir: Vector3) -> void:
	yaw = atan2(-dir.x, -dir.z)
	pitch = 0.0


## Just behind the pilot's seat, turned round to look down the ship.
func stand_at_helm() -> bool:
	if helm_seat == Vector3.INF:
		return false
	pos = helm_stand
	face(-helm_face)
	_resolve()
	return true


## In the middle of the airlock, facing the way into the ship.
func stand_in_airlock() -> bool:
	if airlock == Vector3.INF:
		return false
	pos = airlock
	face(airlock_face)
	_resolve()
	return true


func room() -> String:
	var i: int = cells.get(cell(), -1)
	return String(names.get(i, ""))


func near_helm() -> bool:
	return helm_seat != Vector3.INF and level() == roundi((helm_seat.y - Interiors.FLOOR) / ShipGrid.CELL) \
			and Vector2(pos.x - helm_seat.x, pos.z - helm_seat.z).length() <= REACH


func near_airlock() -> bool:
	return airlock != Vector3.INF and cell() == ShipGrid.world_to_cell(airlock - Vector3(0, Interiors.FLOOR, 0))


## The hatch the walker is standing at, or {} when there is none.
func hatch_here() -> Dictionary:
	var c := cell()
	if not hatches.has(c):
		return {}
	var centre := ShipGrid.cell_to_world(c)
	if Vector2(pos.x - centre.x, pos.z - centre.z).length() > HATCH_REACH:
		return {}
	return hatches[c]


## Through the hatch: up when looking up (or when only up is possible), otherwise down. Returns the new
## level's direction (+1, -1) or 0 if there is no way through here.
func climb() -> int:
	var hx := hatch_here()
	if hx.is_empty():
		return 0
	var dir := 0
	if bool(hx.up) and (pitch >= 0.0 or not bool(hx.down)):
		dir = 1
	elif bool(hx.down):
		dir = -1
	if dir == 0:
		return 0
	var c := cell() + Vector3i(0, dir, 0)
	var centre := ShipGrid.cell_to_world(c)
	pos = Vector3(centre.x, deck_y(c.y), centre.z)
	_resolve()
	return dir


# --- Moving -----------------------------------------------------------------------------------------

## `input`: x strafes right, y walks forward. Turning is done by changing yaw and pitch directly.
func step(dt: float, input: Vector2, run := false) -> void:
	if input.length() > 1.0:
		input = input.normalized()
	var speed := RUN_SPEED if run else WALK_SPEED
	var fwd := Vector3(-sin(yaw), 0, -cos(yaw))
	var right := Vector3(cos(yaw), 0, -sin(yaw))
	var move := (fwd * input.y + right * input.x) * speed * dt
	var n := maxi(1, ceili(move.length() / 0.1))   # small steps so nothing is skipped through
	for i in n:
		pos += move / float(n)
		_resolve()


func look(d_yaw: float, d_pitch: float) -> void:
	yaw = wrapf(yaw + d_yaw, -PI, PI)
	pitch = clampf(pitch + d_pitch, -1.45, 1.45)


## Push the walker's circle out of every wall and piece of furniture it overlaps.
func _resolve() -> void:
	var lv := level()
	var rects: Array = walls.get(lv, []) + furniture.get(lv, [])
	for it in 4:
		var p := Vector2(pos.x, pos.z)
		var moved := false
		for r in rects:
			var rr: Rect2 = r
			var q := Vector2(clampf(p.x, rr.position.x, rr.end.x), clampf(p.y, rr.position.y, rr.end.y))
			var off := p - q
			var dist := off.length()
			if dist >= RADIUS:
				continue
			if dist > 0.0001:
				p = q + off / dist * RADIUS
			else:  # centre inside the rectangle: leave by the nearest side
				var outs := [p.x - rr.position.x, rr.end.x - p.x, p.y - rr.position.y, rr.end.y - p.y]
				var k := 0
				for j in 4:
					if outs[j] < outs[k]:
						k = j
				match k:
					0: p.x = rr.position.x - RADIUS
					1: p.x = rr.end.x + RADIUS
					2: p.y = rr.position.y - RADIUS
					_: p.y = rr.end.y + RADIUS
			moved = true
		pos.x = p.x
		pos.z = p.y
		if not moved:
			break


## True if a circle at `p` (deck level of `p`) touches nothing. For tests and spawn checks.
func free_at(p: Vector3) -> bool:
	var lv := roundi((p.y - Interiors.FLOOR) / ShipGrid.CELL)
	for r in walls.get(lv, []) + furniture.get(lv, []):
		var rr: Rect2 = r
		var q := Vector2(clampf(p.x, rr.position.x, rr.end.x), clampf(p.z, rr.position.y, rr.end.y))
		if Vector2(p.x, p.z).distance_to(q) < RADIUS - 0.001:
			return false
	return true
