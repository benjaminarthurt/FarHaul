extends SceneTree
## Renders surface work: a survey point with the suit readout, the drill, and carrying a crate at the
## camp (run under xvfb-run, not --headless).
## xvfb-run -a godot --path . -s tests/capture_surface_work.gd -- /tmp/surface_work_frames
func _initialize() -> void:
	SaveSlots.dir = "user://test_saves_capture_sw"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SaveSlots.dir))
	process_frame.connect(_run, CONNECT_ONE_SHOT)
func _fit(preset: Array) -> void:
	var data := SaveSlots.read(Session.slot)
	var ship := ShipData.new(ModuleLibrary.new())
	ShipPresets.build(ship, preset)
	data["modules"] = (JSON.parse_string(ship.to_json()) as Dictionary)["modules"]
	data["cargo"] = CargoManifest.new(ship).to_dict()
	SaveSlots.write(Session.slot, data)
	SimWorld.sync(Session.sim, Session.profile, ship)
func _run() -> void:
	var out := "/tmp/surface_work_frames"
	for a in OS.get_cmdline_user_args():
		out = a
	DirAccess.make_dir_recursive_absolute(out)
	Session.begin_new(2, "Pilot", "human", "normal", "roosevelt_independent_yards")
	_fit(ShipPresets.STARTER_LANDER)
	var sys := Session.system_id()
	for g in ["o2_1", "scanner", "jetpack"]:
		Session.buy_gear(g)
	Session.profile["port_id"] = sys + LocalSpace.SEP + "pad"
	Session.save_profile()
	var m: Dictionary = Session.missions_here()[0]
	Session.take_mission(m)
	Session.suit_up = true
	var f: Node = load(Session.FLIGHT_SCENE).instantiate()
	root.add_child(f)
	await process_frame
	await process_frame
	var p: Array = m.points[0]
	f.suit.place(Vector3(float(p[0]) - 12.0, 0, float(p[1]) - 6.0))
	f.suit.face(Vector3(12, 0, 6).normalized())
	f.suit.pitch = -0.12
	f._process(0.016)
	await _shot(out, "01_mission_point")
	f.suit.place(Vector3(float(p[0]) + 0.5, 0, float(p[1])))
	f._process(0.016)
	await _shot(out, "02_at_point")
	f.queue_free()
	await process_frame
	Session.fail_mission("test")
	Session.profile["port_id"] = sys + LocalSpace.SEP + "camp"
	Session.profile["unloading"] = {"crates": 6, "done": 4}
	Session.save_profile()
	Session.suit_up = true
	f = load(Session.FLIGHT_SCENE).instantiate()
	root.add_child(f)
	await process_frame
	await process_frame
	f.ops._set_carrying(true)
	var d := SurfaceWork.drop_xz()
	f.suit.place(Vector3(d.x + 14, 0, d.y + 8))
	f.suit.face(Vector3(-14, 0, -8).normalized())
	f.suit.pitch = -0.2
	f._process(0.016)
	await _shot(out, "03_carrying_crate")
	quit(0)
func _shot(out: String, name: String) -> void:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png("%s/%s.png" % [out, name])
	print("shot ", name)
