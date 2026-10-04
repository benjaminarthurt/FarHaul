extends SceneTree
## Renders the mining camp, the wreck and a sample on foot (run under xvfb-run): /tmp/surface_frames.
func _initialize() -> void:
	SaveSlots.dir = "user://test_saves_capture_surface"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SaveSlots.dir))
	process_frame.connect(_run, CONNECT_ONE_SHOT)
func _shot(n: String) -> void:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("/tmp/surface_frames")
	root.get_viewport().get_texture().get_image().save_png("/tmp/surface_frames/%s.png" % n)
func _run() -> void:
	Session.begin_new(2, "Pilot", "human", "normal", "roosevelt_independent_yards")
	var data := SaveSlots.read(2)
	var ship := ShipData.new(ModuleLibrary.new())
	ShipPresets.build(ship, ShipPresets.STARTER_LANDER)
	data["modules"] = (JSON.parse_string(ship.to_json()) as Dictionary)["modules"]
	SaveSlots.write(2, data)
	Session.profile["port_id"] = Session.system_id() + LocalSpace.SEP + "camp"
	Session.save_profile()
	Session.flight_job = {}
	var f: Node = load("res://scenes/flight.tscn").instantiate()
	root.add_child(f)
	await process_frame
	await _shot("01_camp_chase")
	f.get_up()
	f.walk.stand_in_airlock()
	f.use()
	var w := SurfaceFinds.wreck_xz()
	f.suit.place(Vector3(w.x - 14.0, 0, w.y - 10.0))
	f.suit.face(Vector3(14, 0, 10).normalized())
	f.suit.pitch = -0.1
	f._apply_pose()
	f._update_hud()
	await _shot("02_wreck")
	for x in Session.finds_here():
		if String(x.kind) == "sample":
			var c := SurfaceFinds.camp_xz()
			if Vector2(float(x.x) - c.x, float(x.z) - c.y).length() < 400.0:
				f.suit.place(Vector3(float(x.x) - 3.0, 0, float(x.z) - 1.0))
				f.suit.face(Vector3(3, 0, 1).normalized())
				f.suit.pitch = -0.3
				break
	f._apply_pose()
	f._update_hud()
	await _shot("03_sample")
	quit(0)
