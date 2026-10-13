extends SceneTree
## Renders the crew at their posts aboard while walking the ship (run under xvfb-run, not --headless).
## xvfb-run -a godot --path . --rendering-driver opengl3 -s tests/capture_crew.gd -- /tmp/crew_frames
func _initialize() -> void:
	SaveSlots.dir = "user://test_saves_capture_crew"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SaveSlots.dir))
	process_frame.connect(_run, CONNECT_ONE_SHOT)
func _run() -> void:
	var out := "/tmp/crew_frames"
	for a in OS.get_cmdline_user_args():
		out = a
	DirAccess.make_dir_recursive_absolute(out)
	Session.begin_new(2, "Pilot", "human", "normal", "roosevelt_independent_yards")
	Session.flight_job = {}
	var roster := []
	for r in ["pilot", "engineer", "loadmaster", "deck_tech"]:
		var c: Dictionary = Crew.candidates("capture", roster.size() * 7, 1.0)[0]
		c["role"] = r
		c["id"] = "cap-" + r
		c["line"] = (Crew.cfg().lines[r] as Array)[0]
		roster.append(c)
	Session.profile["crew"] = roster
	Session.save_profile()
	var f: Node = load("res://scenes/flight.tscn").instantiate()
	root.add_child(f)
	await process_frame
	f.get_up()
	f.crew_c.step(0.0)
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
		f.crew_c.step(0.0)
		f._update_hud()
		f._walk_prompt()
		await _shot(out, s[0])
	f.queue_free()
	await process_frame
	# The bar: your crew, and who's looking for a berth. A ship with two bunks and one hand aboard.
	var data := SaveSlots.read(Session.slot)
	var cabin := ShipData.new(ModuleLibrary.new())
	ShipPresets.build(cabin, ShipPresets.STARTER_CABIN)
	data["modules"] = (JSON.parse_string(cabin.to_json()) as Dictionary)["modules"]
	data["cargo"] = CargoManifest.new(cabin).to_dict()
	Session.profile["crew"] = [roster[1]]
	Session.profile["location"] = "dock"
	Session.profile["hints_seen"] = ["welcome", "money", "crew", "holding", "arrived", "hab", "hut"]
	data["profile"] = Session.profile
	SaveSlots.write(Session.slot, data)
	var p: Node = load(Session.PLACE_SCENE).instantiate()
	root.add_child(p)
	await process_frame
	p.walker.pos = Vector3(10, 0, 1)
	p.use_desk("bar")
	await _shot(out, "07_bar_crew")
	quit(0)
func _shot(out: String, name: String) -> void:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png("%s/%s.png" % [out, name])
	print("shot ", name)
