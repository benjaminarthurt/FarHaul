extends SceneTree
## Renders braking thrusters (beside the cockpit and on top) and manoeuvring thrusters (on the hold and under
## the airlock corridor), cold, braking and sliding right, from ahead and to the side.
## xvfb-run -a godot --path . --resolution 1280x720 -s tests/capture_retro.gd -- /tmp/retro
func _initialize() -> void:
	SaveSlots.dir = "user://test_saves_capture_retro_%d" % OS.get_process_id()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SaveSlots.dir))
	process_frame.connect(_run, CONNECT_ONE_SHOT)
func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var out := "/tmp/retro" if args.is_empty() else String(args[0])
	DirAccess.make_dir_recursive_absolute(out)
	Session.begin_new(2, "Pilot", "human", "normal", "roosevelt_independent_yards")
	var data := SaveSlots.read(2)
	var ship := ShipData.new(ModuleLibrary.new())
	ShipPresets.build(ship)
	ship.add(&"retro_thrusters", Vector3i(-1, 0, 0), 0)
	ship.add(&"retro_thrusters", Vector3i(0, 1, 0), 0)
	ship.add(&"rcs_thrusters", Vector3i(0, 1, 2), 0)
	ship.add(&"rcs_thrusters", Vector3i(0, -1, 1), 0)
	data["modules"] = (JSON.parse_string(ship.to_json()) as Dictionary)["modules"]
	data["cargo"] = CargoManifest.new(ship).to_dict()
	SaveSlots.write(2, data)
	Session.flight_job = {}
	var f: Node = load(Session.FLIGHT_SCENE).instantiate()
	root.add_child(f)
	current_scene = f
	await process_frame
	f.model.pos = Vector3(400, 120, 900)
	f.model.vel = f.model.forward() * 6.0
	f.set_process(false)
	var cam: Camera3D = f.camera
	for pair in [["cold", 0.0, Vector2.ZERO], ["firing", 1.0, Vector2.ZERO], ["close_firing", 1.0, Vector2.ZERO], ["sliding_right", 0.0, Vector2(1, 0)], ["sliding_up", 0.0, Vector2(0, 1)], ["close_sliding_left", 0.0, Vector2(-1, 0)]]:
		f.model.retro = pair[1]
		f.view.set_retro_flames(pair[1] > 0.0)
		f.view.set_rcs(pair[2])
		f._apply_pose()
		var ship_at: Vector3 = f.ship_root.global_position
		cam.global_position = ship_at + f.model.basis * (Vector3(-7, 4, -7) if String(pair[0]).begins_with("close") else (Vector3(-16, 6, -14) if not String(pair[0]).begins_with("sliding") else Vector3(-5, 9, -20)))
		cam.look_at(ship_at + f.model.basis * Vector3(0, 0, -2), f.model.basis.y)
		await _shot(out, "ahead_" + String(pair[0]))
	f.set_process(true)
	f.model.braking = true
	for i in 30:
		await process_frame
	f.set_process(false)
	f._update_hud()
	f.chase = true
	f._apply_pose()
	await _shot(out, "chase_autopilot")
	print("state ", f.model.brake_state, " retro ", f.model.retro)
	quit(0)
func _shot(out: String, name: String) -> void:
	for i in 4:
		await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png("%s/%s.png" % [out, name])
	print("shot ", name)
