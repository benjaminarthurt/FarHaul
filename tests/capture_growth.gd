extends SceneTree
## Frontier growth on screen: the trade report's Growth page after two months of a captain hauling to
## the home system's moon station, an abandoned fuel depot's concourse, the grown moon station's
## concourse, and the moon base hab at frontier and at core (the domes outside the window).
## xvfb-run -a godot --path . --resolution 1280x720 -s tests/capture_growth.gd -- OUT
func _initialize() -> void:
	SaveSlots.dir = "user://test_saves_capture_growth_%d" % OS.get_process_id()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SaveSlots.dir))
	process_frame.connect(_run, CONNECT_ONE_SHOT)


func _shot(out: String, name: String) -> void:
	for i in 3:
		await process_frame
	for i in 3:
		await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png("%s/%s.png" % [out, name])
	print("shot ", name)


func _place(at: String) -> Node:
	Session.profile["port_id"] = at
	Session.profile["location"] = "dock"
	Session.save_profile()
	var pl: Node = load(Session.PLACE_SCENE).instantiate()
	root.add_child(pl)
	current_scene = pl
	await process_frame
	await process_frame
	return pl


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var out := "/tmp/growth_frames" if args.is_empty() else String(args[0])
	DirAccess.make_dir_recursive_absolute(out)
	Session.begin_new(2, "Pilot", "human", "normal", "roosevelt_independent_yards")
	var sim := Session.sim
	var sys := Session.system_id()
	var home := String(Session.profile.port_id)
	var moon := sys + LocalSpace.SEP + "moon"
	var depot := sys + LocalSpace.SEP + "depot"
	for d in 60:
		Development.moved(sim, moon, 12.0)
		if d > 20:
			Development.site(sim, depot)["luck"] = -3.0   # its traffic stops coming
		sim.run_days(1)
	Session.profile["hints_seen"] = ["welcome", "money", "crew", "holding", "arrived", "hab", "hut", "trade"]
	var pl: Node = await _place(home)
	var r: TradeReport = TradeReport.find(self)
	if r == null:
		r = TradeReport.attach(pl)
	r.open("growth")
	await _shot(out, "a_growth")
	r.close()
	pl.queue_free()
	await process_frame
	var dp := Development.site(sim, depot)
	if not bool(dp.abandoned):   # sixty days may not be quite enough: finish it off
		dp["score"] = 0.3
		dp["abandoned"] = true
	pl = await _place(depot)
	await _shot(out, "b_abandoned_depot")
	pl.queue_free()
	await process_frame
	pl = await _place(moon)
	await _shot(out, "c_grown_moon_station")
	pl.queue_free()
	await process_frame
	var pad := sys + LocalSpace.SEP + "pad"
	var ps := Development.site(sim, pad)
	ps["score"] = 2.0
	pl = await _place(pad)
	pl.walker.face(Vector3(0, 0, -1))
	await _shot(out, "d_hab_frontier")
	pl.queue_free()
	await process_frame
	ps["score"] = 5.2
	pl = await _place(pad)
	pl.walker.face(Vector3(0, 0, -1))
	await _shot(out, "e_hab_core")
	quit(0)
