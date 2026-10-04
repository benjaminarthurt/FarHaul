extends SceneTree
## Renders the dock, the contract board and a local run for the info site (run under xvfb-run).
## xvfb-run -a godot --path . --rendering-driver opengl3 -s tests/capture_site.gd -- /tmp/site_frames
func _initialize() -> void:
	SaveSlots.dir = "user://test_saves_capture"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SaveSlots.dir))
	process_frame.connect(_run, CONNECT_ONE_SHOT)
func _run() -> void:
	var out := "/tmp/site_frames"
	for a in OS.get_cmdline_user_args():
		out = a
	DirAccess.make_dir_recursive_absolute(out)
	Session.begin_new(3, "Ren Calloway", "human", "normal", "roosevelt_independent_yards")
	var d: Node = load("res://scenes/dock.tscn").instantiate()
	root.add_child(d)
	await process_frame
	await process_frame
	d._show_contracts()
	await _shot(out, "dock_board")
	d.queue_free()
	await process_frame
	var local: Dictionary = {}
	for o in Contracts.offers_from(Session.system_id()):
		if String(o.get("origin_system_id", "")) == String(o.get("destination_system_id", "")):
			local = o
			break
	if local.is_empty():
		print("no local job")
		quit(1)
		return
	Session.accept_contract(local)
	Session.begin_local_flight()
	var f: Node = load("res://scenes/flight.tscn").instantiate()
	root.add_child(f)
	f.set_process(false)
	await process_frame
	for i in 20:
		f._process(0.1)
	await _shot(out, "flight_cruise")
	quit(0)
func _shot(out: String, name: String) -> void:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png("%s/%s.png" % [out, name])
	print("shot ", name)
