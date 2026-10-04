extends SceneTree
## Renders views from inside the ship while walking (run under xvfb-run, not --headless).
## xvfb-run -a godot --path . --rendering-driver opengl3 -s tests/capture_walk.gd -- /tmp/walk_frames
func _initialize() -> void:
	SaveSlots.dir = "user://test_saves_capture_walk"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SaveSlots.dir))
	process_frame.connect(_run, CONNECT_ONE_SHOT)
func _run() -> void:
	var out := "/tmp/walk_frames"
	for a in OS.get_cmdline_user_args():
		out = a
	DirAccess.make_dir_recursive_absolute(out)
	Session.begin_new(2, "Pilot", "human", "normal", "roosevelt_independent_yards")
	Session.flight_job = {}
	var f: Node = load("res://scenes/flight.tscn").instantiate()
	root.add_child(f)
	await process_frame
	f.get_up()
	var shots := [
		["01_helm_aft", Vector3(0.0, 0, 0.9), Vector3(0, 0, 1), 0.0],
		["02_cockpit_fwd", Vector3(0.0, 0, 1.0), Vector3(0, 0, -1), -0.1],
		["03_tee_to_airlock", Vector3(-0.6, 0, 3.0), Vector3(1, 0, 0), 0.0],
		["04_hold_aisle", Vector3(0, 0, 4.9), Vector3(0, 0, 1), 0.0],
		["05_engineering", Vector3(0, 0, 10.8), Vector3(0, 0, 1), 0.05],
		["06_airlock", Vector3(2.6, 0, 3.0), Vector3(1, 0, 0), 0.0],
	]
	for s in shots:
		f.walk.pos = s[1] + Vector3(0, ShipWalk.deck_y(0), 0)
		f.walk.face(s[2])
		f.walk.pitch = s[3]
		f._apply_pose()
		f._update_hud()
		await _shot(out, s[0])
	quit(0)
func _shot(out: String, name: String) -> void:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png("%s/%s.png" % [out, name])
	print("shot ", name)
