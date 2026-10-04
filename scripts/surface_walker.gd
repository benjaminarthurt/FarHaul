class_name SurfaceWalker
extends RefCounted
## On foot outside the ship on a moon, in a suit. Plain maths like ShipWalk: the walker's feet follow the
## terrain, low gravity makes jumps long and slow, and the landed ship is a solid block of cells you walk
## round (in the ship's own frame, so any heading works).

const RADIUS := 0.35
const EYE := 1.7

var terrain: SurfaceTerrain
var gravity := 1.62
var walk_speed := 1.6
var run_speed := 2.6
var jump_speed := 2.2
var pos := Vector3.ZERO          ## feet, world
var vel_y := 0.0
var yaw := 0.0
var pitch := 0.0
var on_ground := true
var ship_origin := Vector3.ZERO  ## where the ship's layout origin sits in the world, and how it is turned
var ship_basis := Basis.IDENTITY
var ship_cells: Array[Vector3i] = []


## `cells`: every occupied cell of the ship (hull and external parts) in layout coordinates.
static func make(t: SurfaceTerrain, g: float, cells: Array[Vector3i], origin: Vector3, b: Basis) -> SurfaceWalker:
	var w := SurfaceWalker.new()
	w.terrain = t
	w.gravity = g
	w.ship_cells = cells
	w.ship_origin = origin
	w.ship_basis = b
	var cfg := SurfaceTerrain.config()
	w.walk_speed = float(cfg.get("suit_walk_m_s", 1.6))
	w.run_speed = w.walk_speed * 1.6
	w.jump_speed = float(cfg.get("suit_jump_m_s", 2.2))
	return w


func eye() -> Vector3:
	return pos + Vector3(0, EYE, 0)


func look_basis() -> Basis:
	return Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, pitch)


func look(d_yaw: float, d_pitch: float) -> void:
	yaw = wrapf(yaw + d_yaw, -PI, PI)
	pitch = clampf(pitch + d_pitch, -1.45, 1.45)


func face(dir: Vector3) -> void:
	yaw = atan2(-dir.x, -dir.z)
	pitch = 0.0


## Put the walker down at `p` (feet on the ground).
func place(p: Vector3) -> void:
	pos = Vector3(p.x, terrain.height(p.x, p.z), p.z)
	vel_y = 0.0
	on_ground = true
	_resolve()


func step(dt: float, input: Vector2, run := false, jump := false) -> void:
	if input.length() > 1.0:
		input = input.normalized()
	var speed := run_speed if run else walk_speed
	var fwd := Vector3(-sin(yaw), 0, -cos(yaw))
	var right := Vector3(cos(yaw), 0, -sin(yaw))
	var move := (fwd * input.y + right * input.x) * speed * dt
	if jump and on_ground:
		vel_y = jump_speed
		on_ground = false
	vel_y -= gravity * dt
	var n := maxi(1, ceili(move.length() / 0.1))
	for i in n:
		pos += move / float(n)
		_resolve()
	pos.y += vel_y * dt
	var g := terrain.height(pos.x, pos.z)
	if pos.y <= g:
		pos.y = g
		vel_y = 0.0
		on_ground = true
	elif pos.y > g + 0.05:
		on_ground = false


## Keep out of the ship: push the walker's circle out of every ship cell its body overlaps.
func _resolve() -> void:
	var inv := ship_basis.inverse()
	var local := inv * (pos - ship_origin)
	var h := ShipGrid.CELL * 0.5
	var moved := false
	for c in ship_cells:
		var centre := Vector3(c) * ShipGrid.CELL
		if local.y + EYE < centre.y - h or local.y > centre.y + h:
			continue   # passing under or over this cell
		var lo := Vector2(centre.x - h, centre.z - h)
		var hi := Vector2(centre.x + h, centre.z + h)
		var p := Vector2(local.x, local.z)
		var q := Vector2(clampf(p.x, lo.x, hi.x), clampf(p.y, lo.y, hi.y))
		var off := p - q
		var d := off.length()
		if d >= RADIUS:
			continue
		if d > 0.0001:
			p = q + off / d * RADIUS
		else:
			var outs := [p.x - lo.x, hi.x - p.x, p.y - lo.y, hi.y - p.y]
			var k := 0
			for j in 4:
				if outs[j] < outs[k]:
					k = j
			match k:
				0: p.x = lo.x - RADIUS
				1: p.x = hi.x + RADIUS
				2: p.y = lo.y - RADIUS
				_: p.y = hi.y + RADIUS
		local.x = p.x
		local.z = p.y
		moved = true
	if moved:
		var back := ship_origin + ship_basis * local
		pos.x = back.x
		pos.z = back.z


func distance_to(p: Vector3) -> float:
	return Vector2(pos.x - p.x, pos.z - p.z).length()
