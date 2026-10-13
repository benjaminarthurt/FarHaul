extends SceneTree
## Renders the hull as it goes: sound, 60%, 30%, 10% and breached, from the chase camera and closer in.
## Run under xvfb-run, not --headless.
## xvfb-run -a godot --path . --resolution 1280x720 -s tests/capture_damage.gd -- /tmp/damage
func _initialize() -> void:
	SaveSlots.dir = "user://test_saves_capture_damage_%d" % OS.get_process_id()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SaveSlots.dir))
	process_frame.connect(_run, CONNECT_ONE_SHOT)
func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var out := "/tmp/damage" if args.is_empty() else String(args[0])
	DirAccess.make_dir_recursive_absolute(out)
	Session.begin_new(2, "Pilot", "human", "normal", "roosevelt_independent_yards")
	Session.flight_job = {}
	var f: Node = load(Session.FLIGHT_SCENE).instantiate()
	root.add_child(f)
	current_scene = f
	await process_frame
	f.model.pos = Vector3(400, 120, 900)
	for hull in [1.0, 0.6, 0.3, 0.1, 0.0]:
		f.model.damage = 1.0 - hull
		f._hull_warned = 0
		f.notice_s = 0.0
		for i in 40:   # let the vents and sparks get going
			await process_frame
		await _shot(out, "chase_%03d" % roundi(hull * 100.0))
		f.set_process(false)
		var cam: Camera3D = f.camera
		var ship: Vector3 = f.ship_root.global_position
		cam.global_position = ship + f.model.basis * Vector3(14, 7, 6)
		cam.look_at(ship, f.model.basis.y)
		await _shot(out, "close_%03d" % roundi(hull * 100.0))
		f.set_process(true)
	quit(0)
func _shot(out: String, name: String) -> void:
	for i in 4:
		await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png("%s/%s.png" % [out, name])
	print("shot ", name)
