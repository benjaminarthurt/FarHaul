extends SceneTree
## Renders the shipyard palette with the makers' versions of each part, and a ship fitted out with a few.
## xvfb-run -a godot --path . --resolution 1280x720 -s tests/capture_makers.gd -- OUT
func _initialize() -> void:
	SaveSlots.dir = "user://test_saves_capture_makers_%d" % OS.get_process_id()
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
	var out := "/tmp/makers_frames" if args.is_empty() else String(args[0])
	DirAccess.make_dir_recursive_absolute(out)
	Session.begin_new(1, "Pilot", "human", "normal", "roosevelt_independent_yards")
	Session.profile["location"] = "shipyard"
	Session.profile["seen_welcome"] = true
	Session.save_profile()
	var b: Node = load(Session.YARD_SCENE).instantiate()
	root.add_child(b)
	current_scene = b
	await process_frame
	await process_frame
	for id in [&"radiator__orun_thermal_collective", &"radiator__aerial_massworks", &"tank__roosevelt_modular"]:
		b._select(b.library.order.find(id))
		var placed := false
		for x in range(-3, 4):
			for z in range(-3, 6):
				for r in 4:
					if not placed and b.ship.check_place(id, Vector3i(x, 0, z), r) == "":
						b.hover_active = true
						b.hover_cell = Vector3i(x, 0, z)
						b.hover_rot = r
						b.hover_error = ""
						b._on_click()
						placed = true
	b._select(b.library.order.find(&"engine__ilyan_vector_works"))
	var btn: Button = b.buttons[b.library.order.find(&"engine")]
	var scroll := btn.get_parent().get_parent() as ScrollContainer
	await process_frame
	if scroll != null:
		scroll.scroll_vertical = int(btn.position.y) - 180
	b._frame_ship(true)
	b.set_process(false)
	b.ghost.visible = false
	b.tip_panel.visible = false
	await _shot(out, "a_makers")
	quit(0)
