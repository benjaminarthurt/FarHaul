extends SceneTree
## Every system has its own look (SystemStyle), and every system's concourse still works in it:
## all the desks are there and can be walked to from the gate, the people walking about keep to open
## floor, and the station's added structure in space leaves the approach to the collar clear.
## Run: godot --headless --path . --script res://tests/test_identity.gd
var fails := 0
func check(ok: bool, msg: String) -> void:
	if not ok:
		print("  FAIL " + msg)
		fails += 1
func _initialize() -> void:
	SaveSlots.dir = "user://test_saves_identity"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SaveSlots.dir))
	process_frame.connect(_run, CONNECT_ONE_SHOT)


## Flood-fill open floor on a 0.25 m grid from `from`; true for each target reached (within 0.4 m).
func _reachable(w: ShipWalk, from: Vector3, targets: Array, hw: float, hd: float) -> Array:
	var step := 0.25
	var key := func(x: int, z: int) -> int: return x * 100000 + z
	var start := Vector2i(roundi(from.x / step), roundi(from.z / step))
	var seen := {key.call(start.x, start.y): true}
	var queue: Array[Vector2i] = [start]
	var got := []
	got.resize(targets.size())
	got.fill(false)
	while not queue.is_empty():
		var c: Vector2i = queue.pop_back()
		var p := Vector3(c.x * step, 0, c.y * step)
		for i in targets.size():
			if not got[i] and Vector2(p.x, p.z).distance_to(Vector2(targets[i].x, targets[i].z)) <= 0.4:
				got[i] = true
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = c + d
			var k: int = key.call(n.x, n.y)
			if seen.has(k) or absf(n.x * step) > hw or absf(n.y * step) > hd:
				continue
			seen[k] = true
			if w.free_at(Vector3(n.x * step, 0, n.y * step)):
				queue.append(n)
	return got


func _run() -> void:
	Session.begin_new(2, "Pilot", "human", "normal", "roosevelt_independent_yards")
	var looks := {}
	var n_sys := 0
	for s in Worlds._load("systems.json").get("systems", []):
		var sys := String(s.id)
		var st := SystemStyle.for_system(sys)
		n_sys += 1
		for k in ["architecture", "tier", "role", "wall", "floor", "trim", "lamp", "width", "depth", "walkers", "crowd", "planet", "port_type"]:
			check(st.has(k), "%s's style has %s" % [sys, k])
		var home: Array = s.get("home_species_ids", [])
		if not home.is_empty():
			check(String(st.architecture) == String(home[0]), "%s is built in its home species' style" % sys)
		var look := "%s|%s|%s|%s" % [st.architecture, st.role, st.port_type, st.tier]
		check(not looks.has(look), "%s does not look the same as %s (%s)" % [sys, looks.get(look, ""), look])
		looks[look] = sys
		# The concourse, built in this style.
		var port := Worlds.primary_port(sys)
		Session.profile["system_id"] = sys
		Session.profile["port_id"] = String(port.id)
		var p: Node = load(Session.PLACE_SCENE).instantiate()
		root.add_child(p)
		await process_frame
		var hw := float(p.style.width) * 0.5
		var hd := float(p.style.depth) * 0.5
		var ids := []
		var spots := []
		for d in p.desks:
			ids.append(String(d.id))
			spots.append(d.pos)
			check(p.walker.free_at(d.pos), "%s: you can stand at the %s" % [sys, d.id])
		for want in ["freight", "fuel", "yard", "bar", "terminal", "gate"]:
			check(want in ids, "%s has its %s desk" % [sys, want])
		var got := _reachable(p.walker, p.walker.pos, spots, hw, hd)
		for i in got.size():
			check(bool(got[i]), "%s: the %s can be walked to from the gate" % [sys, ids[i]])
		check(p.walker.free_at(p.walker.pos), "%s: you arrive on open floor" % sys)
		check(p.strollers.size() == int(p.style.walkers), "%s has %d people walking about (%d)" % [sys, int(p.style.walkers), p.strollers.size()])
		for sr in p.strollers:
			for wp in sr.path:
				check(p.walker.free_at(wp), "%s: a walker's route stays on open floor at %s" % [sys, wp])
		p.queue_free()
		await process_frame
		# The station in space: its modules leave the approach along +Z clear.
		Session.flight_job = {}
		var f: Node = load(Session.FLIGHT_SCENE).instantiate()
		root.add_child(f)
		await process_frame
		var lane := AABB(Vector3(-9, -9, 0), Vector3(18, 18, 400))
		for b in f.world_c.boxes:
			check(not (b as AABB).intersects(lane), "%s: the station keeps the approach clear (%s)" % [sys, b])
		check(f.model.station_boxes.size() == f.world_c.boxes.size(), "%s: the flight model knows the station's modules" % sys)
		f.queue_free()
		await process_frame
	check(n_sys >= 18, "every system was checked (%d)" % n_sys)
	print("DONE fails=%d (%d systems, %d distinct looks)" % [fails, n_sys, looks.size()])
	quit(1 if fails > 0 else 0)
