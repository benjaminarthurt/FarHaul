extends SceneTree
## Renders the concourse, the pad's hab and the camp's hut (run under xvfb-run, not --headless).
## xvfb-run -a godot --path . -s tests/capture_place.gd -- /tmp/place_frames
func _initialize() -> void:
	SaveSlots.dir = "user://test_saves_capture_place"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SaveSlots.dir))
	process_frame.connect(_run, CONNECT_ONE_SHOT)
func _run() -> void:
	var out := "/tmp/place_frames"
	for a in OS.get_cmdline_user_args():
		out = a
	DirAccess.make_dir_recursive_absolute(out)
	Session.begin_new(2, "Pilot", "human", "normal", "roosevelt_independent_yards")
	var sys := Session.system_id()
	var home := String(Session.profile.port_id)
	var views := {
		"port": [["01_concourse_gate", Vector3(-19.5, 0, 0), Vector3(1, 0.0, 0.0)], ["02_concourse_desks", Vector3(-8, 0, -4), Vector3(0.2, 0, 1)], ["03_concourse_bar", Vector3(10, 0, 1), Vector3(0.6, 0, 1)]],
		"pad": [["04_hab", Vector3(-7.5, 0, 0), Vector3(1, 0, 0.2)], ["05_hab_lab", Vector3(2, 0, 0), Vector3(1, 0, -0.3)]],
		"camp": [["06_hut", Vector3(-4.8, 0, -1), Vector3(1, 0, 0.1)]],
	}
	for k in views:
		Session.profile["port_id"] = home if k == "port" else sys + LocalSpace.SEP + k
		Session.save_profile()
		var p: Node = load(Session.PLACE_SCENE).instantiate()
		root.add_child(p)
		await process_frame
		for v in views[k]:
			p.walker.pos = v[1]
			p.walker.face(v[2])
			p._apply_camera()
			await _shot(out, v[0])
		if k == "port":
			p.walker.pos = Vector3(-14, 0, 5)
			p.use_desk("freight")
			await _shot(out, "07_freight_desk")
			p.close_desk()
			p.use_desk("bar")
			await _shot(out, "08_bar_people")
			p.close_desk()
		p.queue_free()
		await process_frame
	quit(0)
func _shot(out: String, name: String) -> void:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png("%s/%s.png" % [out, name])
	print("shot ", name)
