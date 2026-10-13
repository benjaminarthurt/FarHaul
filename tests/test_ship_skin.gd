extends SceneTree
## The outer hull (ShipSkin) and the engine (EngineParts): the skin covers the compartments from
## outside without reaching into them, leaves the windscreen open, carries the external parts out on
## its surface, and only appears when asked (flight and menus, not the builder). The engine has an
## open bell with a hot throat, and its plume grows with the throttle.
## Run: godot --headless --path . --script res://tests/test_ship_skin.gd
var fails := 0
func check(ok: bool, msg: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + msg)
	if not ok:
		fails += 1


func _initialize() -> void:
	process_frame.connect(_run, CONNECT_ONE_SHOT)


func _meshes(n: Node, out: Array) -> void:
	if n is MeshInstance3D:
		out.append(n)
	for c in n.get_children():
		_meshes(c, out)


func _verts(mi: MeshInstance3D) -> PackedVector3Array:
	var m := mi.mesh
	var arrays: Array = (m as PrimitiveMesh).get_mesh_arrays() if m is PrimitiveMesh else m.surface_get_arrays(0)
	var out := PackedVector3Array()
	for v in arrays[Mesh.ARRAY_VERTEX]:
		out.append(mi.transform * v)
	return out


## Rays from the space between the pressure walls and the skin, in 26 directions, must all hit the
## skin or a compartment (which stands in for its own walls): one that gets away is a hole in the hull.
## The openings are lined from wall to skin, so they don't count.
func _leaks(ship: ShipData, press: Dictionary, meshes: Array) -> Array:
	var infos := {}
	for m in ship.modules:
		var def: ModuleDef = ship.library.get_def(m.id)
		for c in ship.world_cells(m.id, m.cell, m.rot):
			infos[c] = {"def": def, "rot": int(m.rot), "origin": m.cell, "id": m.id}
	var body := StaticBody3D.new()
	root.add_child(body)
	for mi in meshes:
		var shape := (mi as MeshInstance3D).mesh.create_trimesh_shape()
		shape.backface_collision = true
		var cs := CollisionShape3D.new()
		cs.shape = shape
		cs.transform = (mi as MeshInstance3D).transform
		body.add_child(cs)
	for c in press:
		var cs := CollisionShape3D.new()
		var b := BoxShape3D.new()
		b.size = Vector3.ONE * ShipGrid.CELL
		cs.shape = b
		cs.position = ShipGrid.cell_to_world(c)
		body.add_child(cs)
	await physics_frame
	await physics_frame
	var space := root.get_world_3d().direct_space_state
	var h := ShipGrid.CELL * 0.5
	var gap := h + 0.25
	var dirs: Array[Vector3] = []
	for x in [-1, 0, 1]:
		for y in [-1, 0, 1]:
			for z in [-1, 0, 1]:
				if x != 0 or y != 0 or z != 0:
					dirs.append(Vector3(x, y, z).normalized())
	var points: Array[Vector3] = []
	var axes := [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 1, 0), Vector3i(0, -1, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]
	for c in press:
		var centre := ShipGrid.cell_to_world(c)
		for d in axes:
			if press.has(c + d):
				continue
			var u := Vector3i(absi(d.y) + absi(d.z), absi(d.x), 0) if d.z == 0 else Vector3i(1, 0, 0)
			var v := Vector3i(Vector3i(1, 1, 1) - Vector3i(absi(d.x), absi(d.y), absi(d.z)) - u)
			var holes: Array[Rect2] = ShipSkin._holes(ship, c, d, infos[c])
			var uv := ShipSkin._uv(ShipSkin._axis(d))
			for i in range(-2, 3):
				for j in range(-2, 3):
					var p := centre + Vector3(d) * gap + Vector3(u) * (i * 0.7) + Vector3(v) * (j * 0.7)
					var local := p - centre
					var in_hole := false
					for hole in holes:   # an opening is meant to be open
						if hole.grow(0.05).has_point(Vector2(local[uv.x], local[uv.y])):
							in_hole = true
					if not in_hole:
						points.append(p)
			for e in axes:   # out along each convex edge
				if e == d or e == -d or press.has(c + e):
					continue
				points.append(centre + (Vector3(d) + Vector3(e)) * (h + 0.1))   # inside even the roundest curve
	var leaks := []
	for p in points:
		for dir in dirs:
			var q := PhysicsRayQueryParameters3D.create(p, p + dir * 40.0)
			if space.intersect_ray(q).is_empty():
				leaks.append([p, dir])
	body.queue_free()
	return leaks


func _covered(boxes: Array, p: Vector3) -> bool:
	for b in boxes:
		if (b as AABB).grow(0.01).has_point(p):
			return true
	return false


func _run() -> void:
	for preset in [["starter", ShipPresets.STARTER], ["ftl", ShipPresets.STARTER_FTL], ["lander", ShipPresets.STARTER_LANDER]]:
		print(preset[0])
		var ship := ShipData.new(ModuleLibrary.new())
		ShipPresets.build(ship, preset[1])
		var bare := ShipView.new()
		root.add_child(bare)
		bare.rebuild(ship)
		check(bare.get_node_or_null("Skin") == null, "no skin in the builder's view")
		var view := ShipView.new()
		view.skin = true
		root.add_child(view)
		view.rebuild(ship)
		var skin: Node3D = view.get_node_or_null("Skin")
		check(skin != null, "flight view wears a skin")
		if skin == null:
			continue
		var press := ShipSkin.pressurised_cells(ship)
		var h := ShipGrid.CELL * 0.5
		var meshes: Array = []
		_meshes(skin, meshes)
		var boxes: Array = []
		var intrusions := 0
		for mi in meshes:
			var vs := _verts(mi)
			var box := AABB(vs[0], Vector3.ZERO)
			for v in vs:
				box = box.expand(v)
				for c in press:
					var d: Vector3 = (v - ShipGrid.cell_to_world(c)).abs()
					if d.x < h - 0.02 and d.y < h - 0.02 and d.z < h - 0.02:
						intrusions += 1
			boxes.append(box)
		check(intrusions == 0, "nothing of the skin reaches inside a compartment (%d vertices did)" % intrusions)
		var leaks: Array = await _leaks(ship, press, meshes)
		check(leaks.is_empty(), "the hull is sealed: no way out from the gap between wall and skin (%d leaks, first %s)" % [leaks.size(), str(leaks.slice(0, 3))])
		# Every outward top face is plated over.
		var bare_tops := 0
		var tops := 0
		for c in press:
			if not press.has(c + Vector3i.UP):
				tops += 1
				if not _covered(boxes, ShipGrid.cell_to_world(c) + Vector3.UP * (ShipSkin._outer() - ShipSkin.T * 0.5)):
					bare_tops += 1
		check(tops > 0 and bare_tops == 0, "all %d roofs are plated (%d bare)" % [tops, bare_tops])
		# The windscreen stays open: the middle of the helm's outward window is not plated.
		var helm_open := 0
		var helm_faces := 0
		for m in ship.modules:
			var def: ModuleDef = ship.library.get_def(m.id)
			if not def.helm:
				continue
			var info := {"def": def, "rot": int(m.rot), "origin": m.cell, "id": m.id}
			for c in ship.world_cells(m.id, m.cell, m.rot):
				for d in [Vector3i(0, 0, -1), Vector3i(0, 0, 1), Vector3i(1, 0, 0), Vector3i(-1, 0, 0)]:
					if press.has(c + d) or ShipSkin._holes(ship, c, d, info).is_empty():
						continue
					helm_faces += 1
					var p := ShipGrid.cell_to_world(c) + Vector3(d) * (ShipSkin._outer() - ShipSkin.T * 0.5) + Vector3.UP * 0.4
					if not _covered(boxes, p):
						helm_open += 1
		check(helm_faces > 0 and helm_open == helm_faces, "helm windows are left open (%d of %d)" % [helm_open, helm_faces])
		# External parts stand out on the skin; compartments stay put.
		var moved := 0
		var still := 0
		for i in ship.modules.size():
			var m: Dictionary = ship.modules[i]
			var off := ShipSkin.mount_offset(ship, m, press)
			var node: Node3D = view.get_child(i)
			if ship.library.get_def(m.id).pressurized:
				still += 1 if off == Vector3.ZERO else 0
			elif off != Vector3.ZERO:
				moved += 1
				check(node.position.is_equal_approx(ShipGrid.cell_to_world(m.cell) + off), "%s is mounted out on the skin" % m.id)
		check(moved > 0, "some external parts are mounted out on the skin (%d)" % moved)
		bare.queue_free()
		view.queue_free()

	print("engine")
	var ship := ShipData.new(ModuleLibrary.new())
	ShipPresets.build(ship, ShipPresets.STARTER)
	var view := ShipView.new()
	view.skin = true
	root.add_child(view)
	view.rebuild(ship)
	var flames: Array = view._flames
	check(not flames.is_empty(), "the engine has a plume")
	var throat := []
	var stack: Array = [view]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n.has_meta("throat"):
			throat.append(n)
		stack.append_array(n.get_children())
	check(not throat.is_empty(), "the bell has a glowing throat deep inside")
	view.set_flames(true)
	view.set_throttle(0.1)
	view._process(0.016)
	var low: float = (flames[0] as Node3D).scale.y
	view.set_throttle(1.0)
	view._process(0.016)
	var high: float = (flames[0] as Node3D).scale.y
	check(high > low * 1.5, "the plume grows with the throttle (%.2f -> %.2f)" % [low, high])
	var mi: GeometryInstance3D = (flames[0] as Node3D).get_child(0)
	check(is_equal_approx(float(mi.get_instance_shader_parameter("power")), 1.0), "and burns brighter at full throttle")
	view.queue_free()

	print("fails=%d" % fails)
	quit(1 if fails > 0 else 0)
