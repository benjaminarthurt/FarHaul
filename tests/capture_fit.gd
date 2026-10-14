extends SceneTree
## Renders the shipyard with salvaged parts in the hold: the FROM YOUR HOLD palette section, and a
## salvaged engine just fitted.
## xvfb-run -a godot --path . --resolution 1280x720 -s tests/capture_fit.gd -- OUT
func _initialize() -> void:
	SaveSlots.dir = "user://test_saves_capture_fit_%d" % OS.get_process_id()
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
	var out := "/tmp/fit_frames" if args.is_empty() else String(args[0])
	DirAccess.make_dir_recursive_absolute(out)
	Session.begin_new(1, "Pilot", "human", "normal", "roosevelt_independent_yards")
	var lib := ModuleLibrary.new()
	Salvage.stow({"kind": "part", "module": "engine", "tonnes": lib.get_def(&"engine").mass, "condition": 0.62, "failed": false})
	Salvage.stow({"kind": "part", "module": "radiator", "tonnes": lib.get_def(&"radiator").mass, "condition": 0.81, "failed": false})
	Salvage.stow({"kind": "part", "module": "jump_drive", "tonnes": lib.get_def(&"jump_drive").mass, "condition": 0.08, "failed": true})
	Session.profile["location"] = "shipyard"
	Session.profile["seen_welcome"] = true
	Session.save_profile()
	var b: Node = load(Session.YARD_SCENE).instantiate()
	root.add_child(b)
	current_scene = b
	await process_frame
	await process_frame
	var k := -1
	for i in b._salvage_parts().size():
		if String(b._salvage_parts()[i].module) == "radiator":
			k = i
	b._select_salvage(k)
	var found := false
	for x in range(-3, 4):
		for z in range(-3, 6):
			var c := Vector3i(x, 0, z)
			for r in 4:
				if not found and b.ship.check_place(&"radiator", c, r) == "":
					found = true
					b.hover_active = true
					b.hover_cell = c
					b.hover_rot = r
	b.hover_error = ""
	b._on_click()
	b._refresh_info()
	var msg: String = b.message
	b._select_salvage(0)
	b.message = msg
	b._refresh_info()
	b._frame_ship(true)
	b.set_process(false)
	b.ghost.visible = false
	b.tip_panel.visible = false
	await _shot(out, "a_fit")
	quit(0)
