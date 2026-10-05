extends SceneTree
## Renders the title screen, the station terminal and the shipyard (xvfb-run, not --headless).
## xvfb-run -a godot --path . -s tests/capture_menus.gd -- /tmp/menu_frames
func _initialize() -> void:
	SaveSlots.dir = "user://test_saves_capture_menus"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SaveSlots.dir))
	process_frame.connect(_run, CONNECT_ONE_SHOT)
func _run() -> void:
	var out := "/tmp/menu_frames"
	for a in OS.get_cmdline_user_args():
		out = a
	DirAccess.make_dir_recursive_absolute(out)
	Session.skip_intro = true
	var boot: Node = load(Session.BOOT_SCENE).instantiate()
	root.add_child(boot)
	await create_timer(1.2).timeout
	if boot.has_method("_show_menu"):
		boot._show_menu()
	await create_timer(0.6).timeout
	await _shot(out, "01_title")
	boot.queue_free()
	await process_frame
	Session.begin_new(2, "Pilot", "human", "normal", "roosevelt_independent_yards")
	var pl: Node = load(Session.PLACE_SCENE).instantiate()
	root.add_child(pl)
	await create_timer(0.5).timeout
	await _shot(out, "06_port_hint")
	(pl.get_node("GameMenu") as GameMenu).open()
	GameMenu.show_perf = true
	(pl.get_node("GameMenu") as GameMenu).perf.visible = true
	await create_timer(0.6).timeout
	await _shot(out, "07_port_menu")
	(pl.get_node("GameMenu") as GameMenu).close()
	GameMenu.show_perf = false
	pl.queue_free()
	await process_frame
	var d: Node = load(Session.DOCK_SCENE).instantiate()
	root.add_child(d)
	await create_timer(0.5).timeout
	await _shot(out, "02_terminal")
	d._show_contracts()
	await create_timer(0.3).timeout
	await _shot(out, "03_terminal_board")
	d.queue_free()
	await process_frame
	var y: Node = load(Session.YARD_SCENE).instantiate()
	root.add_child(y)
	await create_timer(0.8).timeout
	await _shot(out, "04_shipyard")
	y.welcome_panel.visible = false
	await create_timer(0.2).timeout
	await _shot(out, "05_shipyard_clear")
	quit(0)
func _shot(out: String, name: String) -> void:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png("%s/%s.png" % [out, name])
	print("shot ", name)
