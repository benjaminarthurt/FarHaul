class_name ShipGrid
extends RefCounted
## Grid maths shared by everything that touches ship layout.
## One cell is a cube CELL metres on a side. A cell's coordinates refer to its CENTRE.
## Ship front is -Z (Godot's "forward"), up is +Y.

const CELL := 3.0


## Rotate a cell offset or direction by `rot` quarter-turns around Y.
## Matches Node3D.rotation.y = rot * PI / 2, so data and visuals always agree.
static func rotate_cell(v: Vector3i, rot: int) -> Vector3i:
	var turns := ((rot % 4) + 4) % 4
	for i in turns:
		v = Vector3i(v.z, v.y, -v.x)
	return v


static func cell_to_world(c: Vector3i) -> Vector3:
	return Vector3(c) * CELL


static func world_to_cell(p: Vector3) -> Vector3i:
	return Vector3i((p / CELL).round())
