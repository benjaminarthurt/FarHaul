extends SceneTree
## Renders the ship from outside in flight (station hidden), from several angles, with the engines
## burning in the rear views, plus close-ups of the engine; for each preset given (starter, ftl,
## lander). Run under xvfb-run, not --headless.
## xvfb-run -a godot --path . --resolution 1280x720 -s tests/capture_ship_skin.gd -- OUT [preset ...]
func _initialize() -> void:
	SaveSlots.dir = "user://test_saves_capture_skin_%d" % OS.get_process_id()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SaveSlots.dir))
	process_frame.connect(_run, CONNECT_ONE_SHOT)
func _shot(out: String, name: String) -> void:
	for i in 3:
		await process_frame
	for i in 3:
		await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png("%s/%s.png" % [out, name])
	print("shot ", name)
func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var out := "/tmp/skin_frames" if args.is_empty() else String(args[0])
	var presets: Array = args.slice(1)
	if presets.is_empty():
		presets = ["starter", "ftl", "lander"]
	DirAccess.make_dir_recursive_absolute(out)
	Session.begin_new(2, "Pilot", "human", "normal", "roosevelt_independent_yards")
	Session.flight_job = {}
	for p in presets:
		var f: Node = load(Session.FLIGHT_SCENE).instantiate()
		root.add_child(f)
		await process_frame
		f.set_process(false)
		f.station.visible = false
		f.hud.get_parent().visible = false
		var ship := ShipData.new(ModuleLibrary.new())
		ShipPresets.build(ship, {"starter": ShipPresets.STARTER, "ftl": ShipPresets.STARTER_FTL, "lander": ShipPresets.STARTER_LANDER}[p])
		f.view.rebuild(ship)
		var c: Vector3 = f.ship_root.global_position
		var b: Basis = f.ship_root.global_basis
		var cam: Camera3D = f.camera
		var views := [["a_front", Vector3(9, 6, -14), false], ["b_side", Vector3(17, 2, 1), false], ["c_top", Vector3(3, 18, 2), false],
				["d_rear", Vector3(-9, 5, 18), true], ["e_below", Vector3(-8, -9, -4), false], ["f_engine", Vector3(3, 2, 12), true], ["g_chase", Vector3(0, 6, 26), true], ["h_side_burn", Vector3(20, 3, 9), true], ["i_airlock_top", Vector3(7, 7, -3), false], ["j_airlock_below", Vector3(7, -6, -3), false]]
		for v in views:
			f.view.set_flames(bool(v[2]))
			f.view.set_throttle(1.0)   # burning flat out
			var look_at := c + b * (Vector3(0, 0, 8) if v[0] == "f_engine" else (Vector3(0, 1.5, -10) if v[0] == "g_chase" else (Vector3(0, 0, 10) if v[0] == "h_side_burn" else (Vector3(2.2, 0.5, 1.2) if v[0].begins_with("i_") or v[0].begins_with("j_") else Vector3.ZERO))))
			cam.global_position = c + b * v[1]
			cam.look_at(look_at, b.y)
			await _shot(out, "%s_%s" % [p, v[0]])
		f.queue_free()
		await process_frame
	quit(0)
