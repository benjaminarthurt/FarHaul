extends SceneTree
## The map (M): every system charts its bodies and places every site it can be flown to, the ship sits
## at its site or along its run, known space has every system and route, and M opens and closes it in
## flight and in port (where walking keys are held while it's open).
## Run: godot --headless --path . --script res://tests/test_star_map.gd
var fails := 0
func check(ok: bool, msg: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + msg)
	if not ok:
		fails += 1
func _initialize() -> void:
	SaveSlots.dir = "user://test_saves_star_map_%d" % OS.get_process_id()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SaveSlots.dir))
	process_frame.connect(_run, CONNECT_ONE_SHOT)
func _key(k: int) -> void:
	var e := InputEventKey.new()
	e.keycode = k
	e.physical_keycode = k
	e.pressed = true
	Input.parse_input_event(e)
	Input.flush_buffered_events()
func _run() -> void:
	var bad := []
	for sid in Worlds.system_ids():
		var c := StarMap.system_chart(sid)
		var sites := StarMap.site_positions(sid)
		if String(c.primary) == "" or sites.size() != LocalSpace.nodes(sid).size():
			bad.append(sid)
		for id in sites:
			var p: Vector2 = sites[id].pos
			if not p.is_finite() or p.length() > 4.0:
				bad.append("%s %s" % [sid, id])
	check(bad.is_empty(), "every system charts its main world and places all its sites (%s)" % [bad])
	var sol := StarMap.site_positions("sol")
	check(sol.has("sol__saturn") and sol.has("sol__jovian") and sol.has("sol__venus"), "Sol's outer stations are on the chart")
	var c := StarMap.system_chart("sol")
	var earth := Vector2.ZERO
	var saturn := Vector2.ZERO
	for b in c.bodies:
		if b.id == "earth":
			earth = b.pos
		if b.id == "saturn":
			saturn = b.pos
	check(saturn.length() > earth.length() * 2.5, "Saturn sits well outside Earth (%.2f vs %.2f)" % [saturn.length(), earth.length()])
	var port := String(Worlds.primary_port("sol").id)
	var mid := StarMap.ship_position("sol", {"site_id": port, "run": {"origin_id": port, "dest_id": "sol__saturn", "progress": 0.5}})
	check(mid.is_equal_approx(sol[port].pos.lerp(sol["sol__saturn"].pos, 0.5)), "on a run the ship sits along the route by its progress")
	check(StarMap.ship_position("sol", {"site_id": "sol__moon"}).is_equal_approx(sol["sol__moon"].pos), "docked, it sits at its site")
	var sp := StarMap.space_chart()
	check(sp.systems.size() == Worlds.system_ids().size() and sp.routes.size() > 10, "known space has every system (%d) and the routes (%d)" % [sp.systems.size(), sp.routes.size()])
	# M in flight and in port.
	Session.begin_new(2, "Pilot", "human", "normal", "roosevelt_independent_yards")
	Session.flight_job = {}
	var f: Node = load(Session.FLIGHT_SCENE).instantiate()
	root.add_child(f)
	await process_frame
	var sm: StarMap = f.star_map
	check(sm != null and not sm.is_open(), "flight has a map, closed")
	_key(KEY_M)
	check(sm.is_open(), "M opens it")
	var st: Dictionary = f.map_state()
	check(String(st.system_id) == Session.system_id() and st.has("where"), "the flight tells the map where it is (%s)" % st.get("where", ""))
	_key(KEY_TAB)
	check(sm.view == "space", "Tab goes to known space")
	sm._zoom_by(8.0)
	check(sm.view == "system", "zooming well in on known space comes back to the system")
	sm._zoom_by(0.3)
	check(sm.view == "space", "zooming well out of the system goes to known space")
	_key(KEY_M)
	check(not sm.is_open(), "M closes it")
	f.queue_free()
	await process_frame
	var p: Node = load(Session.PLACE_SCENE).instantiate()
	root.add_child(p)
	await process_frame
	var pm: StarMap = p.get_node_or_null("StarMap")
	check(pm != null and pm.blocks_keys, "the port has a map, and holds the walking keys while it's open")
	_key(KEY_M)
	check(pm.is_open() and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "M opens it in port and frees the mouse")
	_key(KEY_ESCAPE)
	check(not pm.is_open() and p.get_node("GameMenu").is_open() == false, "Esc closes the map, not the game menu behind it")
	print("fails=%d" % fails)
	quit(1 if fails > 0 else 0)
