extends SceneTree
## Danger on screen: a debris field ahead on a flown local run (from 12 km and from inside) and the
## cockpit in a solar storm.
## xvfb-run -a godot --path . --resolution 1280x720 -s tests/capture_hazards.gd -- OUT
func _initialize() -> void:
	SaveSlots.dir = "user://test_saves_capture_hazards_%d" % OS.get_process_id()
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
	var out := "/tmp/hazard_frames" if args.is_empty() else String(args[0])
	DirAccess.make_dir_recursive_absolute(out)
	Session.begin_new(2, "Pilot", "human", "normal", "roosevelt_independent_yards")
	Session.profile["hints_seen"] = ["welcome", "money", "crew", "holding", "arrived", "hab", "hut", "trade", "flight"]
	var job: Dictionary = {}
	for o in Contracts.offers_from(Session.system_id()):
		if bool(o.get("local", false)):
			job = o
	Session.accept_contract(job)
	Session.begin_local_flight()
	var f: Node = load(Session.FLIGHT_SCENE).instantiate()
	root.add_child(f)
	current_scene = f
	await process_frame
	f.set_process(false)
	var hw: HazardWatch = f.hazard_c
	if hw.root != null:
		hw.root.queue_free()
	hw.field = {"density": 0.8, "radius_m": 3000.0, "along": 0.5, "offset": 0.2, "seed": 11}
	hw.radius = 3000.0
	f.model.pos = Vector3(0, 0, 60000)
	f.model.basis = Basis.IDENTITY
	f.station.visible = false
	hw.centre = f.model.pos + Vector3(0, 0, -12000)
	hw._build_cloud()
	f._apply_pose()
	f.say("Debris field reported on this run: 12 km out, 6 km across. Go round it, slow down, or let the autopilot (V or X) thread it.", 8.0)
	f._update_hud()
	await _shot(out, "a_field_ahead")
	f.model.pos = hw.centre + Vector3(300, 100, 1200)
	f._apply_pose()
	f.say("Debris strike at 1,480 m/s: 3% of the hull.", 3.0)
	f._update_hud()
	await _shot(out, "b_inside_field")
	quit(0)
