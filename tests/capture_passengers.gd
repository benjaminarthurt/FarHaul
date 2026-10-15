extends SceneTree
## Renders passengers aboard a small liner (the stateroom, the quarters, a cabin), the freight office's
## passenger board, and the shipyard's new holds and cabins (run under xvfb-run, not --headless).
## xvfb-run -a godot --path . --resolution 1280x720 -s tests/capture_passengers.gd -- OUT
func _initialize() -> void:
	SaveSlots.dir = "user://test_saves_capture_pax_%d" % OS.get_process_id()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SaveSlots.dir))
	process_frame.connect(_run, CONNECT_ONE_SHOT)


func _shot(out: String, name: String) -> void:
	for i in 3:
		await process_frame
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png("%s/%s.png" % [out, name])
	print("shot ", name)


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var out := "/tmp/pax_frames" if args.is_empty() else String(args[0])
	DirAccess.make_dir_recursive_absolute(out)
	Session.begin_new(1, "Pilot", "human", "normal", "roosevelt_independent_yards")
	var data := SaveSlots.read(1)
	var ship := ShipData.new(ModuleLibrary.new())
	ShipPresets.build(ship, ShipPresets.STARTER_LINER)
	data["modules"] = (JSON.parse_string(ship.to_json()) as Dictionary)["modules"]
	data["cargo"] = CargoManifest.new(ship).to_dict()
	SaveSlots.write(1, data)
	SimWorld.sync(Session.sim, Session.profile, ship)
	var parties := [["Wren Achebe", 2, [3, 3], "ilyan"], ["Tam Kowal", 3, [2, 2, 2], "human"], ["Pia Reyes", 1, [2], "vey"], ["Hiro Osei", 2, [1, 1], "kesh"]]
	var list := []
	for i in parties.size():
		var p: Array = parties[i]
		list.append({"id": "cap-%d" % i, "person": p[0], "seats": p[1], "beds": p[2], "fare": 2000 * int(p[1]), "per_seat": 900, "local": false,
				"dest_port_id": "", "dest_system_id": "concord", "dest_name": "Concord", "booked_day": Session.day(), "due_day": Session.day() + 9,
				"hull_at_accept": 0.0, "species": p[3], "wants": 0})
	Session.profile["passengers"] = list
	Session.profile["hints_seen"] = ["welcome", "money", "crew", "holding", "arrived", "hab", "hut", "trade"]
	Session.save_profile()
	Session.flight_job = {}
	var f: Node = load("res://scenes/flight.tscn").instantiate()
	root.add_child(f)
	current_scene = f
	await process_frame
	f.get_up()
	f.pax_c.step()
	var shots := [
		["01_stateroom", Vector3(6.6, 0, 17.9), Vector3(-1, 0, -0.55), -0.05],
		["02_quarters", Vector3(1.6, 0, 10.0), Vector3(-0.35, 0, -1), -0.05],
		["03_cabin", Vector3(2.7, 0, 12.3), Vector3(1, 0, -0.12), -0.05],
		["04_quarters_pods", Vector3(-0.6, 0, 8.6), Vector3(1, 0, -0.4), -0.05],
	]
	for s in shots:
		f.walk.pos = s[1] + Vector3(0, ShipWalk.deck_y(0), 0)
		f.walk.face(s[2])
		f.walk.pitch = s[3]
		f._apply_pose()
		f.pax_c.step()
		f._update_hud()
		f._walk_prompt()
		await _shot(out, s[0])
	f.queue_free()
	await process_frame
	# A cargo bay, full, from the inside.
	var bay_ship := ShipData.new(ModuleLibrary.new())
	ShipPresets.build(bay_ship, [[&"cockpit", Vector3i(0, 0, 0), 0], [&"tee", Vector3i(0, 0, 1), 0], [&"airlock", Vector3i(1, 0, 1), 0],
			[&"cargo_bay_2x3", Vector3i(0, 0, 2), 0], [&"engineering", Vector3i(1, 0, 5), 0], [&"engine", Vector3i(1, 0, 6), 0],
			[&"radiator", Vector3i(2, 0, 5), 0], [&"radiator", Vector3i(0, 0, 5), 2], [&"tank", Vector3i(-1, 0, 2), 0]])
	bay_ship.add(&"door_cap", Vector3i(-1, 0, 3), 3)
	bay_ship.add(&"door_cap", Vector3i(2, 0, 3), 1)
	var full := CargoManifest.new(bay_ship)
	full.load(&"grain", 30.0)
	full.load(&"mining_equipment", 30.0)
	data = SaveSlots.read(1)
	data["modules"] = (JSON.parse_string(bay_ship.to_json()) as Dictionary)["modules"]
	data["cargo"] = full.to_dict()
	SaveSlots.write(1, data)
	Session.profile["passengers"] = []
	Session.save_profile()
	f = load("res://scenes/flight.tscn").instantiate()
	root.add_child(f)
	current_scene = f
	await process_frame
	f.get_up()
	f.walk.pos = Vector3(1.5, ShipWalk.deck_y(0), 6.4)
	f.walk.face(Vector3(0, 0, 1))
	f.walk.pitch = 0.05
	f._apply_pose()
	f._update_hud()
	f._walk_prompt()
	await _shot(out, "07_cargo_bay")
	f.queue_free()
	await process_frame
	Session.profile["passengers"] = list
	Session.save_profile()
	data = SaveSlots.read(1)
	data["modules"] = (JSON.parse_string(ship.to_json()) as Dictionary)["modules"]
	data["cargo"] = CargoManifest.new(ship).to_dict()
	SaveSlots.write(1, data)
	# The freight office: who's aboard and who's asking.
	Session.profile["location"] = "dock"
	Session.save_profile()
	var pl: Node = load(Session.PLACE_SCENE).instantiate()
	root.add_child(pl)
	current_scene = pl
	await process_frame
	pl.walker.pos = Vector3(10, 0, 1)
	pl.use_desk("freight")
	await _shot(out, "05_freight_office")
	pl.queue_free()
	await process_frame
	# The shipyard: the new holds and cabins in the palette, the liner beside them.
	Session.profile["passengers"] = []
	Session.profile["location"] = "shipyard"
	Session.profile["seen_welcome"] = true
	Session.save_profile()
	var b: Node = load(Session.YARD_SCENE).instantiate()
	root.add_child(b)
	current_scene = b
	await process_frame
	await process_frame
	b._select(b.library.order.find(&"pax_stateroom"))
	var btn: Button = b.buttons[b.library.order.find(&"cargo_hold")]
	var scroll := btn.get_parent().get_parent() as ScrollContainer
	await process_frame
	if scroll != null:
		scroll.scroll_vertical = int(btn.position.y) - 60
	b._frame_ship(true)
	b.set_process(false)
	b.ghost.visible = false
	b.tip_panel.visible = false
	await _shot(out, "06_yard_cabins")
	quit(0)
