extends SceneTree
## The consistency sweep: every site of every system, on foot and from space. For each site it renders
## the place you walk (concourse, hab or hut) from where you arrive, and for each site in orbit the view
## as you undock and a three-quarter view of the station (run under xvfb-run, not --headless).
## xvfb-run -a godot --path . -s tests/capture_sweep.gd -- OUT [places|space|all] [system ...]
func _initialize() -> void:
	SaveSlots.dir = "user://test_saves_capture_sweep_%d" % OS.get_process_id()   # one per process, so batches can run side by side
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SaveSlots.dir))
	process_frame.connect(_run, CONNECT_ONE_SHOT)
func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var out := "/tmp/sweep_frames" if args.is_empty() else String(args[0])
	var mode := "all" if args.size() < 2 else String(args[1])
	var only: Array = args.slice(2)
	DirAccess.make_dir_recursive_absolute(out)
	Session.begin_new(2, "Pilot", "human", "normal", "roosevelt_independent_yards")
	Session.flight_job = {}
	for s in Worlds._load("systems.json").get("systems", []):
		var sys := String(s.id)
		if not only.is_empty() and not sys in only:
			continue
		Session.profile["system_id"] = sys
		for n in LocalSpace.nodes(sys):
			var kind := String(n.kind)
			Session.profile["port_id"] = String(n.id)
			if mode != "space":
				var p: Node = load(Session.PLACE_SCENE).instantiate()
				root.add_child(p)
				await process_frame
				var at: Vector3 = p.walker.pos
				p.walker.face(Vector3(1, 0, -0.25))
				p._apply_camera()
				await _shot(out, "%s_%s_place" % [sys, kind])
				p.queue_free()
				await process_frame
			if mode != "places" and not bool(n.get("surface", false)):
				var f: Node = load(Session.FLIGHT_SCENE).instantiate()
				root.add_child(f)
				await process_frame
				for i in 6:
					f._process(0.05)
				await _shot(out, "%s_%s_undock" % [sys, kind])
				f.set_process(false)
				var cam: Camera3D = f.camera
				cam.global_position = Vector3(-62, 30, -110)
				cam.look_at(Vector3(0, 0, -35), Vector3.UP)
				await _shot(out, "%s_%s_station" % [sys, kind])
				f.queue_free()
				await process_frame
	print("SWEEP DONE")
	quit(0)
func _shot(out: String, name: String) -> void:
	for i in 3:
		await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png("%s/%s.png" % [out, name])
	print("shot ", name)
