extends SceneTree
## Renders the worlds you see from a system's sites (run under xvfb-run, not --headless): every site
## in orbit for one system (Sol by default: Earth, Luna, Mars, Venus, Jupiter, Saturn and its rings), or
## just the main port of every system with "all".
## xvfb-run -a godot --path . --resolution 1280x720 -s tests/capture_sol.gd -- /tmp/sol_frames [system|all]
func _initialize() -> void:
	SaveSlots.dir = "user://test_saves_capture_sol_%d" % OS.get_process_id()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SaveSlots.dir))
	process_frame.connect(_run, CONNECT_ONE_SHOT)
func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var out := "/tmp/sol_frames" if args.is_empty() else String(args[0])
	var which := "sol" if args.size() < 2 else String(args[1])
	DirAccess.make_dir_recursive_absolute(out)
	Session.begin_new(2, "Pilot", "human", "normal", "roosevelt_independent_yards")
	Session.flight_job = {}
	var stops: Array = []   # [system, port id, kind]
	if which == "all":
		for sid in SkyWorlds.data().systems:
			stops.append([sid, String(Worlds.primary_port(sid).id), "port"])
	else:
		for n in LocalSpace.nodes(which):
			if not bool(n.get("surface", false)):
				stops.append([which, String(n.id), String(n.kind)])
	for stop in stops:
		var sys := String(stop[0])
		var kind := String(stop[2])
		Session.profile["system_id"] = sys
		Session.profile["port_id"] = String(stop[1])
		var f: Node = load(Session.FLIGHT_SCENE).instantiate()
		root.add_child(f)
		await process_frame
		f.set_process(false)
		for c in f.find_children("*", "CanvasLayer", true, false):
			(c as CanvasLayer).visible = false
		var cam: Camera3D = f.camera
		var p: Node3D = f.planet
		if p != null and p.visible:
			cam.global_position = f.ship_root.global_position + Vector3(0, 6, 22)
			cam.look_at(p.global_position, Vector3.UP)
			cam.fov = 60.0
			await _shot(out, "%s_%s_world" % [sys, kind])
			# The ship in front with the world behind it: stand off the ship on the side away from the world.
			var ship: Vector3 = f.ship_root.global_position
			var to_world := (p.global_position - ship).normalized()
			var side := to_world.cross(Vector3.UP).normalized()
			cam.global_position = ship - to_world * 30.0 + side * 9.0 + Vector3.UP * 3.0
			cam.look_at(ship + to_world * 8.0, Vector3.UP)
			await _shot(out, "%s_%s_ship_and_world" % [sys, kind])
		f.queue_free()
		await process_frame
	quit(0)
func _shot(out: String, name: String) -> void:
	for i in 4:
		await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png("%s/%s.png" % [out, name])
	print("shot ", name)
