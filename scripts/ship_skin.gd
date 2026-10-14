class_name ShipSkin
extends RefCounted
## The outer hull a ship wears in flight and on the menus (not in the builder, which needs to see
## inside). Built from the ship's layout, so any design gets one:
##
## - every outward face of a pressurised compartment gets a hull plate just outside its wall, so
##   nothing inside shows from space;
## - every convex edge between two outward faces gets a quarter-round fillet, and every convex corner
##   a rounded cap, so boxy rooms read as one curved hull; inside corners meet square;
## - plates leave openings for what belongs outside: cockpit windows, the airlock's outer hatch and
##   reactor vents; unused doorways and deck hatches are plated over;
## - each compartment takes the roundest curve its openings allow (big on plain rooms, tight round
##   a windscreen);
## - external parts (engines, radiators, tanks, cargo racks, frames, legs) are not skinned at all.

const GAP := 0.5             ## the hull stands this far off the pressure wall, like a fairing
const T := 0.06              ## skin thickness
const RADIUS := 1.2          ## fillet radius on a plain compartment: well rounded
const BOX_REACH := 1.54      ## how far a compartment's own walls and edge struts reach from its centre
const RADIUS_MIN := 0.15     ## the least, where openings run close to the edges (a windscreen)
const CLEAR := 0.06          ## kept between an opening and where the curve starts
const HULL := Color(0.60, 0.62, 0.66)
const TINT := 0.18           ## how much of each module's own colour shows through the hull paint

const DIRS: Array[Vector3i] = [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 1, 0), Vector3i(0, -1, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]


## World cells of the ship's pressurised compartments (cell -> true).
static func pressurised_cells(ship: ShipData) -> Dictionary:
	var out := {}
	for m in ship.modules:
		if ship.library.get_def(m.id).pressurized:
			for c in ship.world_cells(m.id, m.cell, m.rot):
				out[c] = true
	return out


## How far to move an external part so it mounts on the skin rather than inside it: out by the
## hull's thickness, away from each side it touches a compartment. Parts below the hull (lander legs)
## stay where they are, so their feet still meet the ground where the flight model expects.
static func mount_offset(ship: ShipData, m: Dictionary, press: Dictionary) -> Vector3:
	var def: ModuleDef = ship.library.get_def(m.id)
	if def.pressurized or def.seal:   # door caps stay on the pressure wall, under the hull (a porthole's hole is lined)
		return Vector3.ZERO
	var push := Vector3i.ZERO
	for c in ship.world_cells(m.id, m.cell, m.rot):
		for d in [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1), Vector3i(0, -1, 0)]:
			if press.has(c + d):
				push -= d   # touching a compartment on that side: move away from it
	var out := Vector3(signi(push.x), signi(push.y), signi(push.z))
	if out.y < 0.0:
		out.y = 0.0
	return out * (GAP + T)


## The skin for `ship`, in the same frame as ShipView's module nodes (cell centres at cell * CELL).
static func build(ship: ShipData) -> Node3D:
	var root := Node3D.new()
	root.name = "Skin"
	var press := {}   # world cell -> {def, rot, origin}
	for m in ship.modules:
		var def: ModuleDef = ship.library.get_def(m.id)
		if not def.pressurized:
			continue
		for c in ship.world_cells(m.id, m.cell, m.rot):
			press[c] = {"def": def, "rot": int(m.rot), "origin": m.cell, "id": m.id}
	var mats := {}
	var done_edges := {}
	var done_corners := {}
	for c in press:
		var info: Dictionary = press[c]
		var def: ModuleDef = info.def
		var mat := _material(def.color, mats)
		var r := _radius(ship, press, c, info)
		for d in DIRS:
			if press.has(c + d):
				continue   # inside the hull: a wall between two compartments
			_face(root, ship, press, c, d, info, r, mat)
			for e in DIRS:   # fillets along this face's convex edges
				if e == d or e == -d or press.has(c + e):
					continue
				var key := _edge_key(c, d, e)
				if done_edges.has(key):
					continue
				done_edges[key] = true
				_fillet(root, ship, press, c, d, e, r, mat)
		for dx in [-1, 1]:   # rounded caps on convex corners
			for dy in [-1, 1]:
				for dz in [-1, 1]:
					var ex := Vector3i(dx, 0, 0)
					var ey := Vector3i(0, dy, 0)
					var ez := Vector3i(0, 0, dz)
					if press.has(c + ex) or press.has(c + ey) or press.has(c + ez):
						continue
					var corner := Vector3(c) * ShipGrid.CELL + Vector3(dx, dy, dz) * ShipGrid.CELL * 0.5
					var ck := "%s" % corner
					if done_corners.has(ck):
						continue
					done_corners[ck] = true
					_corner(root, c, Vector3(dx, dy, dz), r, mat)
	return root


## The roundest fillet a compartment can take while its openings stay on flat plating: the curve
## starts _outer() - r from the centre, so every opening must end inside that.
static func _radius(ship: ShipData, press: Dictionary, c: Vector3i, info: Dictionary) -> float:
	var r := RADIUS
	for d in DIRS:
		if press.has(c + d):
			continue
		for hole in _holes(ship, c, d, info):
			var reach := maxf(maxf(absf(hole.position.x), absf(hole.end.x)), maxf(absf(hole.position.y), absf(hole.end.y)))
			r = minf(r, _outer() - reach - CLEAR)
	# The curve must stay outside the compartment's own square corners, or they poke through it.
	var o := _outer()
	r = minf(r, (o * sqrt(3.0) - BOX_REACH * sqrt(3.0)) / (sqrt(3.0) - 1.0))
	r = minf(r, (o * sqrt(2.0) - BOX_REACH * sqrt(2.0)) / (sqrt(2.0) - 1.0))
	return maxf(r, RADIUS_MIN)


static func _material(col: Color, cache: Dictionary) -> StandardMaterial3D:
	var key := col.to_html()
	if not cache.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = HULL.lerp(col, TINT)
		m.roughness = 0.55
		m.metallic = 0.35
		SurfaceTextures.apply_panel(m)
		cache[key] = m
	return cache[key]


## Where the skin's outer surface sits, from a cell centre.
static func _outer() -> float:
	return ShipGrid.CELL * 0.5 + GAP + T


## The two in-plane axes of a face with normal axis `axis`: (u, v), v vertical on walls.
static func _uv(axis: int) -> Vector2i:
	if axis == 0:
		return Vector2i(2, 1)
	if axis == 2:
		return Vector2i(0, 1)
	return Vector2i(0, 2)


static func _axis(d: Vector3i) -> int:
	return 0 if d.x != 0 else (1 if d.y != 0 else 2)


## One outward face: a plate, inset where a fillet takes over at a convex edge, run to the cell's
## edge where the hull carries on flat into the next compartment, with any openings left open.
static func _face(root: Node3D, ship: ShipData, press: Dictionary, c: Vector3i, d: Vector3i, info: Dictionary, r: float, mat: Material) -> void:
	var axis := _axis(d)
	var uv := _uv(axis)
	var h := ShipGrid.CELL * 0.5
	var lim := {}
	for k in 2:
		var ax: int = uv[k]
		for s in [-1, 1]:
			var e := Vector3i.ZERO
			e[ax] = s
			var edge := h              # carries on flat into the next compartment's plate
			if not press.has(c + e):
				edge = _outer() - r    # convex: the fillet carries the curve round
			elif press.has(c + e + d):
				edge = h               # inside corner: run on under the neighbour's skin, so no seam opens
			lim["%d%d" % [k, s]] = edge
	var area := Rect2(-float(lim["0-1"]), -float(lim["1-1"]), float(lim["0-1"]) + float(lim["01"]), float(lim["1-1"]) + float(lim["11"]))
	var holes := _holes(ship, c, d, info)
	var rects: Array[Rect2] = [area]
	for hole in holes:   # cut each opening out of whatever plate pieces it touches
		var next: Array[Rect2] = []
		for a in rects:
			next.append_array(_cut(a, hole))
		rects = next
	var centre := Vector3(c) * ShipGrid.CELL + Vector3(d) * (h + GAP + T * 0.5)
	for hole in holes:   # line each opening from the wall out to the skin, so it reads as a thick hull
		_liner(root, Vector3(c) * ShipGrid.CELL, d, axis, uv, hole, mat)
	for a in rects:
		if a.size.x < 0.02 or a.size.y < 0.02:
			continue
		var size := Vector3.ZERO
		size[axis] = T
		size[uv.x] = a.size.x
		size[uv.y] = a.size.y
		var off := Vector3.ZERO
		off[uv.x] = a.position.x + a.size.x * 0.5
		off[uv.y] = a.position.y + a.size.y * 0.5
		_box(root, centre + off, size, mat)


## `a` with `hole` taken out: up to four rectangles round it.
static func _cut(a: Rect2, hole: Rect2) -> Array[Rect2]:
	if not a.intersects(hole):
		return [a]
	var out: Array[Rect2] = []
	var x0 := maxf(a.position.x, hole.position.x)
	var x1 := minf(a.end.x, hole.end.x)
	out.append(Rect2(a.position.x, a.position.y, x0 - a.position.x, a.size.y))     # left
	out.append(Rect2(x1, a.position.y, a.end.x - x1, a.size.y))                       # right
	out.append(Rect2(x0, a.position.y, x1 - x0, maxf(hole.position.y, a.position.y) - a.position.y))   # below
	out.append(Rect2(x0, minf(hole.end.y, a.end.y), x1 - x0, a.end.y - minf(hole.end.y, a.end.y)))       # above
	return out


## Openings in an outward face, in its (u, v) frame. Every opening the modules make is symmetric
## left to right, so only the face's axis in the module's own frame matters, not the turn.
static func _holes(ship: ShipData, c: Vector3i, d: Vector3i, info: Dictionary) -> Array[Rect2]:
	var def: ModuleDef = info.def
	var local_d := ShipGrid.rotate_cell(d, (4 - int(info.rot)) % 4)
	var local_c := ShipGrid.rotate_cell(c - Vector3i(info.origin), (4 - int(info.rot)) % 4)
	var out: Array[Rect2] = []
	var h := ShipGrid.CELL * 0.5
	# An unused doorway or deck hatch on the outside is plated over: the hull stays closed.
	if def.helm and local_d.y == 0:   # windscreen and side windows, with their frames
		var m := 0.1
		if local_d.z != 0:
			out.append(Rect2(-1.2 - m, -0.2 - m, 2.4 + m * 2.0, 1.2 + m * 2.0))
		else:
			out.append(Rect2(-0.55 - m, -0.1 - m, 1.1 + m * 2.0, 0.8 + m * 2.0))
	if def.airlock and local_d.y == 0:   # the outer hatch faces away from the airlock's door
		var inner := Vector3i(1, 0, 0)
		for sk in def.sockets:
			if sk.kind == ModuleSocket.DOOR and sk.dir.y == 0:
				inner = sk.dir
				break
		if local_d == -inner:
			out.append(Rect2(-0.95, -1.4, 1.9, 2.5))
	if def.power > 50.0 and local_d.x != 0:   # reactor vents glowing on both sides
		out.append(Rect2(-1.0, -0.7, 2.0, 1.4))
	var nb := c + d   # a porthole cap over a doorway here: its window shows through the hull
	if d.y == 0 and ship.occupied.has(nb):
		var cap: Dictionary = ship.modules[ship.occupied[nb]]
		var cdef: ModuleDef = ship.library.get_def(cap.id)
		if cdef.seal and cdef.shape == &"cap_window" and ship._faces(cap, nb, -d):
			out.append(Rect2(ModuleDef.PORTHOLE.position - Vector2(0.07, 0.07), ModuleDef.PORTHOLE.size + Vector2(0.14, 0.14)))
	return out


## A quarter-round along the edge between outward faces d and e of cell c. It runs the cell's length,
## stopping short where a corner cap takes over, carrying on into the next compartment, or, at an
## inside corner, running on until it meets the other compartment's hull, point by point round the
## curve, so the two curves close on each other even when their radii differ.
static func _fillet(root: Node3D, ship: ShipData, press: Dictionary, c: Vector3i, d: Vector3i, e: Vector3i, r: float, mat: Material) -> void:
	var along := Vector3i.ONE - Vector3i(absi(d.x), absi(d.y), absi(d.z)) - Vector3i(absi(e.x), absi(e.y), absi(e.z))
	var a := _axis(along)
	var h := ShipGrid.CELL * 0.5
	var o := _outer()
	var seg := 10
	var ends := []   # per end: an array of seg + 1 distances from the cell centre along the edge
	for s in [-1, 1]:
		var step := Vector3i.ZERO
		step[a] = s
		var nb := c + step
		var row := []
		var closes_d := press.has(nb + d)
		var closes_e := press.has(nb + e)
		for i in seg + 1:
			var th := PI * 0.5 * i / seg
			var dist := h   # carries on flat into the next compartment's curve, or both sides closed
			if not press.has(nb):
				dist = o - r   # the end of the hull: the corner cap takes over
			elif closes_d != closes_e:
				# An inside corner: the compartment at nb + f faces us with its hull, flat up to its
				# own curve. Run on until this point of the curve meets that surface.
				var f := d if closes_d else e
				var q: Vector3i = nb + f
				var rq := _radius(ship, press, q, press[q])
				var up := (o - r) + r * (sin(th) if closes_d else cos(th))   # height along the other direction
				var reach := o
				if up > o - rq:
					var k := up - (o - rq)
					reach = (o - rq) + sqrt(maxf(0.0, rq * rq - k * k))
				dist = ShipGrid.CELL - reach
			row.append(dist)
		ends.append(row)
	# Only the outer quarter of the round: a whole cylinder would poke back through the pressure
	# walls into the compartment, where the crew would find it.
	var base := Vector3(c) * ShipGrid.CELL + (Vector3(d) + Vector3(e)) * (o - r)
	var rows: Array = []
	var norms: Array = []
	for k in 2:
		var row: Array[Vector3] = []
		var nrow: Array[Vector3] = []
		for i in seg + 1:
			var th := PI * 0.5 * i / seg
			var n := Vector3(d) * cos(th) + Vector3(e) * sin(th)
			var end := Vector3.ZERO
			end[a] = float(ends[k][i]) * (-1.0 if k == 0 else 1.0)
			row.append(base + end + n * r)
			nrow.append(n)
		rows.append(row)
		norms.append(nrow)
	_patch(root, rows, norms, mat)


## The four sides of an opening's recess, from the pressure wall out through the skin.
static func _liner(root: Node3D, base: Vector3, d: Vector3i, axis: int, uv: Vector2i, hole: Rect2, mat: Material) -> void:
	var h := ShipGrid.CELL * 0.5
	var depth := GAP + T
	var mid := base + Vector3(d) * (h + depth * 0.5)
	var t := 0.04
	var sides := [
		[Vector2(hole.position.x - t * 0.5, hole.position.y + hole.size.y * 0.5), Vector2(t, hole.size.y)],
		[Vector2(hole.end.x + t * 0.5, hole.position.y + hole.size.y * 0.5), Vector2(t, hole.size.y)],
		[Vector2(hole.position.x + hole.size.x * 0.5, hole.position.y - t * 0.5), Vector2(hole.size.x + t * 2.0, t)],
		[Vector2(hole.position.x + hole.size.x * 0.5, hole.end.y + t * 0.5), Vector2(hole.size.x + t * 2.0, t)],
	]
	for sd in sides:
		var size := Vector3.ZERO
		size[axis] = depth
		size[uv.x] = sd[1].x
		size[uv.y] = sd[1].y
		var off := Vector3.ZERO
		off[uv.x] = sd[0].x
		off[uv.y] = sd[0].y
		_box(root, mid + off, size, mat)


## A rounded cap where three outward faces meet: one eighth of a sphere, the outside only.
static func _corner(root: Node3D, c: Vector3i, dir: Vector3, r: float, mat: Material) -> void:
	var base := Vector3(c) * ShipGrid.CELL + dir * (_outer() - r)
	var seg := 8
	var rows: Array = []
	var norms: Array = []
	for j in seg + 1:
		var lat := PI * 0.5 * j / seg   # 0 at the horizontal edge, up to the pole on y
		var row: Array[Vector3] = []
		var nrow: Array[Vector3] = []
		for i in seg + 1:
			var lon := PI * 0.5 * i / seg
			var n := Vector3(dir.x * cos(lat) * cos(lon), dir.y * sin(lat), dir.z * cos(lat) * sin(lon))
			row.append(base + n * r)
			nrow.append(n)
		rows.append(row)
		norms.append(nrow)
	_patch(root, rows, norms, mat)


## A curved sheet through a grid of points with outward normals, wound to face outward.
static func _patch(root: Node3D, rows: Array, norms: Array, mat: Material) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for j in rows.size() - 1:
		var r0: Array = rows[j]
		var r1: Array = rows[j + 1]
		for i in r0.size() - 1:
			var q := [[r0[i], norms[j][i]], [r0[i + 1], norms[j][i + 1]], [r1[i + 1], norms[j + 1][i + 1]], [r1[i], norms[j + 1][i]]]
			for tri in [[0, 1, 2], [0, 2, 3]]:
				var p0: Vector3 = q[tri[0]][0]
				var p1: Vector3 = q[tri[1]][0]
				var p2: Vector3 = q[tri[2]][0]
				var n: Vector3 = q[tri[0]][1] + q[tri[1]][1] + q[tri[2]][1]
				var order: Array = tri
				if (p1 - p0).cross(p2 - p0).dot(n) > 0.0:   # Godot draws clockwise faces as the front
					order = [tri[0], tri[2], tri[1]]
				for k in order:
					var v: Vector3 = q[k][0]
					st.set_normal(q[k][1])
					st.set_uv(Vector2(v.x + v.z, v.y) / ShipGrid.CELL)
					st.add_vertex(v)
	st.set_material(mat)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	root.add_child(mi)


static func _box(root: Node3D, pos: Vector3, size: Vector3, mat: Material) -> void:
	var b := BoxMesh.new()
	b.size = size
	b.material = mat
	var mi := MeshInstance3D.new()
	mi.mesh = b
	mi.position = pos
	root.add_child(mi)


static func _edge_key(c: Vector3i, d: Vector3i, e: Vector3i) -> String:
	var p := Vector3(c) * 2.0 + Vector3(d) + Vector3(e)   # the edge's midpoint, in half cells
	return "%s" % p
