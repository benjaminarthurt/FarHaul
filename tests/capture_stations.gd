extends SceneTree
## Renders every system's main station from outside, three-quarters from behind so the ring, the
## modules and the world below show together (run under xvfb-run, not --headless).
## xvfb-run -a godot --path . -s tests/capture_stations.gd -- /tmp/station_frames [system ...]
func _initialize() -> void:
	SaveSlots.dir = "user://test_saves_capture_stations"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SaveSlots.dir))
	process_frame.connect(_run, CONNECT_ONE_SHOT)
func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var out := "/tmp/station_frames" if args.is_empty() else String(args[0])
	DirAccess.make_dir_recursive_absolute(out)
	var only: Array = args.slice(1)
	Session.begin_new(2, "Pilot", "human", "normal", "roosevelt_independent_yards")
	Session.flight_job = {}
	for s in Worlds._load("systems.json").get("systems", []):
		var sys := String(s.id)
		if not only.is_empty() and not sys in only:
			continue
		var port := Worlds.primary_port(sys)
		if port.is_empty():
			continue
		Session.profile["system_id"] = sys
		Session.profile["port_id"] = String(port.id)
		var f: Node = load(Session.FLIGHT_SCENE).instantiate()
		root.add_child(f)
		await process_frame
		f.set_process(false)
		var cam: Camera3D = f.camera
		cam.global_position = Vector3(-62, 30, -110)
		cam.look_at(Vector3(0, 0, -35), Vector3.UP)
		await _shot(out, sys + "_station")
		f.queue_free()
		await process_frame
	quit(0)
func _shot(out: String, name: String) -> void:
	for i in 3:
		await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png("%s/%s.png" % [out, name])
	print("shot ", name)
