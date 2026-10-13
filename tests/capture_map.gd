extends SceneTree
## Renders the map (M): Sol's system chart partway through a run to the Saturn ring yards, known space
## with a jump being flown, and the chart from a port in another system. Run under xvfb-run.
## xvfb-run -a godot --path . --resolution 1280x720 -s tests/capture_map.gd -- /tmp/map_frames
func _initialize() -> void:
	SaveSlots.dir = "user://test_saves_capture_map_%d" % OS.get_process_id()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SaveSlots.dir))
	process_frame.connect(_run, CONNECT_ONE_SHOT)
func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var out := "/tmp/map_frames" if args.is_empty() else String(args[0])
	DirAccess.make_dir_recursive_absolute(out)
	Session.begin_new(2, "Pilot", "human", "normal", "roosevelt_independent_yards")
	# A run from Earth's port to the Saturn ring yards, 40% of the way, nose a little off.
	Session.profile["system_id"] = "sol"
	Session.profile["port_id"] = String(Worlds.primary_port("sol").id)
	var dest := LocalSpace.node("sol__saturn")
	Session.flight_job = {"kind": "run", "contract_id": "map", "dv_kms": 8.0, "hours": 96, "destination": String(dest.name), "key": "map",
			"dest_kind": "saturn", "dest_id": "sol__saturn", "origin_kind": "port", "origin_id": String(Session.profile.port_id), "system_id": "sol"}
	var f: Node = load(Session.FLIGHT_SCENE).instantiate()
	root.add_child(f)
	await process_frame
	f.phase = "cruise"
	f.model.pos = f.xfer.target * 0.4
	f.model.vel = (f.xfer.target - f.model.pos).normalized().rotated(Vector3.UP, 0.15) * 2600.0
	f.model.basis = Basis(Vector3.UP, 0.35) * Basis.looking_at(f.xfer.target - f.model.pos)
	f.warp_index = 2
	f.set_process(false)
	f.star_map.open()
	await _shot(out, "1_sol_run_to_saturn")
	f.star_map.view = "space"
	f.star_map.chart.queue_redraw()
	await _shot(out, "2_known_space")
	f.star_map.close()
	f.queue_free()
	await process_frame
	# A jump from New Houston to Concord, not yet made.
	Session.profile["system_id"] = "new_houston"
	Session.profile["port_id"] = String(Worlds.primary_port("new_houston").id)
	Session.flight_job = {"kind": "jump", "contract_id": "map", "destination": "Concord", "dest_system": "concord", "ly": 6.0, "key": "map", "jumped": false}
	f = load(Session.FLIGHT_SCENE).instantiate()
	root.add_child(f)
	await process_frame
	f.set_process(false)
	f.star_map.open()
	f.star_map.view = "space"
	f.star_map.zoom.space = 1.6
	f.star_map.chart.queue_redraw()
	await _shot(out, "3_jump_new_houston_to_concord")
	f.star_map.close()
	f.queue_free()
	await process_frame
	Session.flight_job = {}
	# On foot in Keshar's port.
	Session.profile["system_id"] = "keshar"
	Session.profile["port_id"] = String(Worlds.primary_port("keshar").id)
	var p: Node = load(Session.PLACE_SCENE).instantiate()
	root.add_child(p)
	await process_frame
	var sm: StarMap = p.get_node("StarMap")
	sm.open()
	await _shot(out, "4_keshar_port")
	quit(0)
func _shot(out: String, name: String) -> void:
	for i in 3:
		await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png("%s/%s.png" % [out, name])
	print("shot ", name)
