extends SceneTree
## The pieces split out of the flight and port scenes, tested on their own without the scenes:
## MoonScenery builds a moon's ground and everything on it; Strollers walks people round a loop.
## Run: godot --headless --path . --script res://tests/test_components.gd
var fails := 0
func check(ok: bool, msg: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + msg)
	if not ok:
		fails += 1
func _initialize() -> void:
	process_frame.connect(_run, CONNECT_ONE_SHOT)
func _run() -> void:
	# MoonScenery, for a system with no game running (finds come from SurfaceFinds directly).
	var sys := "new_houston"
	var cfg := SurfaceTerrain.config()
	cfg["terrain_cells"] = 40   # a coarse ground is enough here
	var t := SurfaceTerrain.make(sys + LocalSpace.SEP + "moon", [SurfaceFinds.camp_xz()] + SurfaceSites.pads(sys), SurfaceSites.craters(sys))
	var rocks := SurfaceSites.boulders(sys)
	var m := MoonScenery.new()
	root.add_child(m)
	m.build(sys, t, cfg, LocalSpace.body(sys), rocks)
	var expect := 0
	for f in SurfaceFinds.list(sys, 0):
		if String(f.kind) != "salvage":
			expect += 1
	check(m.find_nodes.size() == expect, "every sample, ice core and crystal is placed (%d)" % m.find_nodes.size())
	check(m.pad_label != null and "MOON BASE" in m.pad_label.text, "the base pad has its name: %s" % (m.pad_label.text if m.pad_label else ""))
	var mm_count := 0
	for c in m.get_children():
		if c is MultiMeshInstance3D:
			mm_count = (c as MultiMeshInstance3D).multimesh.instance_count
	check(mm_count == rocks.size(), "all %d boulders are drawn" % rocks.size())
	var camp := m.camp_pos()
	check(is_equal_approx(camp.y, t.height(camp.x, camp.z)), "the camp sits on the ground")
	var first: String = m.find_nodes.keys()[0]
	m.hide_find(first)
	check(not (m.find_nodes[first] as Node3D).visible, "a taken find disappears")
	var below := 0
	for id in m.find_nodes:
		var n: Node3D = m.find_nodes[id]
		if absf(n.position.y - t.height(n.position.x, n.position.z)) > 0.01:
			below += 1
	check(below == 0, "finds lie on the ground")
	m.queue_free()
	# Strollers.
	var path := [Vector3(0, 0, 0), Vector3(6, 0, 0), Vector3(6, 0, 6), Vector3(0, 0, 6)]
	var fa := Figure.make(Color.GRAY, 1)
	var fb := Figure.make(Color.GRAY, 2)
	root.add_child(fa)
	root.add_child(fb)
	var list: Array[Dictionary] = [Strollers.make(fa, path, 0, 1.2), Strollers.make(fb, path, 2, 1.2)]
	check(fa.position == path[0] and fb.position == path[2], "strollers start on their waypoints")
	var far := Vector3(100, 0, 100)
	var travelled := 0.0
	var last := fa.position
	for i in 400:
		Strollers.step(list, 0.05, far)
		travelled += fa.position.distance_to(last)
		last = fa.position
	check(travelled > 12.0, "a stroller walks the loop (%.1f m in 20 s, with pauses)" % travelled)
	var off_path := 0
	for st in list:
		var q: Vector3 = st.fig.position
		if not (absf(q.x) < 0.01 or absf(q.x - 6) < 0.01 or absf(q.z) < 0.01 or absf(q.z - 6) < 0.01):
			off_path += 1
	check(off_path == 0, "they keep to the path between waypoints")
	# Blocked by someone standing in the way.
	var g := Figure.make(Color.GRAY, 3)
	root.add_child(g)
	var one: Array[Dictionary] = [Strollers.make(g, [Vector3(0, 0, 0), Vector3(10, 0, 0)], 0, 1.2)]
	Strollers.step(one, 0.05, Vector3(1.0, 0, 0))
	check(g.position.x == 0.0 and g.stride == 0.0, "a stroller waits when you are right in front")
	Strollers.step(one, 0.05, Vector3(-3.0, 0, 0))
	check(g.position.x > 0.0 and g.stride > 0.0, "and walks on when you are behind")
	var pushed := Strollers.push_out(one, g.position + Vector3(0.1, 0, 0))
	check(Vector2(pushed.x - g.position.x, pushed.z - g.position.z).length() >= 0.549, "you are pushed out of a stroller you walk into")
	print("DONE fails=", fails)
	quit(1 if fails > 0 else 0)
