extends SceneTree
## Every system has its own look (SystemStyle), and every site in every system still works in it: all
## the desks are there and can be walked to from the way in, the people walking about keep to open
## floor, and each station's added structure in space leaves the approach to the collar clear.
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


const DESKS := {
	"port": ["freight", "fuel", "yard", "bar", "terminal", "gate"],
	"depot": ["freight", "fuel", "bar", "terminal", "gate"], "moon": ["freight", "fuel", "bar", "terminal", "gate"],
	"belt": ["freight", "fuel", "bar", "terminal", "gate"],
	"pad": ["dispatch", "lab", "store", "fuel", "terminal", "gate"], "camp": ["foreman", "exchange", "terminal", "gate"],
}
var n_sites := 0
var n_stations := 0


## One site, on foot and (in orbit) from space.
func _site(sys: String, n: Dictionary) -> void:
	var kind := String(n.kind)
	var at := "%s %s" % [sys, kind]
	Session.profile["port_id"] = String(n.id)
	var p: Node = load(Session.PLACE_SCENE).instantiate()
	root.add_child(p)
	await process_frame
	n_sites += 1
	var ids := []
	var spots := []
	for d in p.desks:
		ids.append(String(d.id))
		spots.append(d.pos)
		check(p.walker.free_at(d.pos), "%s: you can stand at the %s" % [at, d.id])
	for want in DESKS[kind]:
		check(want in ids, "%s has its %s desk" % [at, want])
	var got := _reachable(p.walker, p.walker.pos, spots, 40.0, 40.0)
	for i in got.size():
		check(bool(got[i]), "%s: the %s can be walked to from the way in" % [at, ids[i]])
	check(p.walker.free_at(p.walker.pos), "%s: you arrive on open floor" % at)
	if p.kind == "concourse":
		check(p.strollers.size() == int(p.style.walkers), "%s has %d people walking about (%d)" % [at, int(p.style.walkers), p.strollers.size()])
	for sr in p.strollers:
		for wp in sr.path:
			check(p.walker.free_at(wp), "%s: a walker's route stays on open floor at %s" % [at, wp])
	p.queue_free()
	await process_frame
	if bool(n.get("surface", false)):
		return
	var f: Node = load(Session.FLIGHT_SCENE).instantiate()   # the station: its modules leave the approach along +Z clear
	root.add_child(f)
	await process_frame
	n_stations += 1
	var lane := AABB(Vector3(-9, -9, 0), Vector3(18, 18, 400))
	for b in f.world_c.boxes:
		check(not (b as AABB).intersects(lane), "%s: the station keeps the approach clear (%s)" % [at, b])
	check(f.model.station_boxes.size() == f.world_c.boxes.size(), "%s: the flight model knows the station's modules" % at)
	check(String(f.world_c.style.get("port_type", "")) != "" , "%s: the station has a type" % at)
	f.queue_free()
	await process_frame


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
		Session.profile["system_id"] = sys
		for n in LocalSpace.nodes(sys):   # every site: the port, depot, moon station, belt works, pad and camp
			await _site(sys, n)
	check(n_sys >= 18, "every system was checked (%d)" % n_sys)
	check(n_sites == n_sys * 6, "every site was walked (%d)" % n_sites)
	print("DONE fails=%d (%d systems, %d distinct looks, %d places, %d stations)" % [fails, n_sys, looks.size(), n_sites, n_stations])
	quit(1 if fails > 0 else 0)
