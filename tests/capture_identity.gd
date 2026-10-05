extends SceneTree
## Renders every system's main concourse from the gate, across to the window and back from the far end, then its\n## moon base's hab and its mining camp's hut, so each system's style can be
## checked side by side (run under xvfb-run, not --headless).
## xvfb-run -a godot --path . -s tests/capture_identity.gd -- /tmp/identity_frames [system ...]
func _initialize() -> void:
	SaveSlots.dir = "user://test_saves_capture_identity"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SaveSlots.dir))
	process_frame.connect(_run, CONNECT_ONE_SHOT)
func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var out := "/tmp/identity_frames" if args.is_empty() else String(args[0])
	DirAccess.make_dir_recursive_absolute(out)
	var only: Array = args.slice(1)
	Session.begin_new(2, "Pilot", "human", "normal", "roosevelt_independent_yards")
	for s in Worlds._load("systems.json").get("systems", []):
		var sys := String(s.id)
		if not only.is_empty() and not sys in only:
			continue
		var port := Worlds.primary_port(sys)
		if port.is_empty():
			continue
		Session.profile["system_id"] = sys
		Session.profile["port_id"] = String(port.id)
		var p: Node = load(Session.PLACE_SCENE).instantiate()
		root.add_child(p)
		await process_frame
		var hw := float(p.style.width) * 0.5
		var hd := float(p.style.depth) * 0.5
		p.walker.pos = Vector3(-hw + 2.5, 0, 0)
		p.walker.face(Vector3(1, 0, -0.08))
		p._apply_camera()
		await _shot(out, sys + "_a_gate")
		p.walker.pos = Vector3(-hw * 0.3, 0, hd - 4.0)
		p.walker.face(Vector3(0.35, 0, -1))
		p._apply_camera()
		await _shot(out, sys + "_b_window")
		p.walker.pos = Vector3(hw - 3.0, 0, 0.5)
		p.walker.face(Vector3(-1, 0, 0.12))
		p._apply_camera()
		await _shot(out, sys + "_c_back")
		p.queue_free()
		await process_frame
		for k in [["pad", Vector3(-7.5, 0, 0), Vector3(1, 0, -0.35)], ["camp", Vector3(-4.8, 0, -1), Vector3(1, 0, 0.35)]]:   # the moon's hab and the camp's hut
			var id: String = sys + LocalSpace.SEP + String(k[0])
			if LocalSpace.node(id).is_empty():
				continue
			Session.profile["port_id"] = id
			var q: Node = load(Session.PLACE_SCENE).instantiate()
			root.add_child(q)
			await process_frame
			q.walker.pos = k[1]
			q.walker.face(k[2])
			q._apply_camera()
			await _shot(out, "%s_d_%s" % [sys, k[0]])
			q.queue_free()
			await process_frame
func _shot(out: String, name: String) -> void:
	for i in 3:
		await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png("%s/%s.png" % [out, name])
	print("shot ", name)
