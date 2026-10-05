extends SceneTree
## Renders flying in space: leaving the station in the chase view, the cockpit view, a local run's
## cruise, and the approach and docking at the far station (xvfb-run, not --headless).
## xvfb-run -a godot --path . -s tests/capture_space.gd -- /tmp/space_frames
func _initialize() -> void:
	SaveSlots.dir = "user://test_saves_capture_space"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SaveSlots.dir))
	process_frame.connect(_run, CONNECT_ONE_SHOT)
func _run() -> void:
	var out := "/tmp/space_frames"
	for a in OS.get_cmdline_user_args():
		out = a
	DirAccess.make_dir_recursive_absolute(out)
	Session.begin_new(2, "Pilot", "human", "normal", "roosevelt_independent_yards")
	Session.flight_job = {}
	var f: Node = load(Session.FLIGHT_SCENE).instantiate()
	root.add_child(f)
	await process_frame
	for i in 10:
		f._process(0.05)
	await _shot(out, "01_at_station_chase")
	var cam: Camera3D = f.camera
	f.set_process(false)
	cam.global_position = f.model.pos * 1.6 + Vector3(0, 40, 0)
	cam.look_at(Vector3.ZERO, Vector3.UP)
	await _shot(out, "00_station_view")
	f.set_process(true)
	f.model.throttle = 1.0
	for i in 80:
		f._process(0.05)
	await _shot(out, "02_leaving_burn")
	f.chase = false
	f._apply_pose()
	await _shot(out, "03_cockpit_view")
	f.queue_free()
	await process_frame
	var job: Dictionary = {}
	for o in Contracts.offers_from(Session.system_id()):
		if bool(o.get("local", false)):
			job = o
	Session.accept_contract(job)
	Session.begin_local_flight()
	f = load(Session.FLIGHT_SCENE).instantiate()
	root.add_child(f)
	await process_frame
	f.model.pos = f.model.pos.normalized() * 3200.0
	f.phase = "cruise"
	f.model.basis = Basis.looking_at((f.xfer.target - f.model.pos).normalized(), Vector3.UP)
	f.model.throttle = 0.6
	for i in 10:
		f._process(0.05)
	await _shot(out, "04_cruise")
	f._begin_approach(600.0)
	f.model.basis = Basis.looking_at(-f.model.pos.normalized(), Vector3.UP)
	for i in 10:
		f._process(0.05)
	await _shot(out, "05_approach")
	f._begin_approach(120.0)
	for i in 10:
		f._process(0.05)
	await _shot(out, "06_docking_close")
	quit(0)
func _shot(out: String, name: String) -> void:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png("%s/%s.png" % [out, name])
	print("shot ", name)
