extends SceneTree
## Renders the trade report's four pages in a port, after a few weeks of the economy and some work of
## the player's own.
## xvfb-run -a godot --path . --resolution 1280x720 -s tests/capture_trade.gd -- OUT
func _initialize() -> void:
	SaveSlots.dir = "user://test_saves_capture_trade_%d" % OS.get_process_id()
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
	var out := "/tmp/trade_frames" if args.is_empty() else String(args[0])
	DirAccess.make_dir_recursive_absolute(out)
	Session.begin_new(2, "Pilot", "human", "normal", "roosevelt_independent_yards")
	var sim := Session.sim
	# Some weeks of trade, with the player's own runs and a salvage sale mixed in.
	for d in 20:
		sim.run_days(1)
		if d % 3 == 0:
			SimStats.on_local(sim, Session.system_id(), 24.0, 9000.0 + d * 400.0)
		if d == 12:
			SimStats.on_salvage(sim, 13404.0, "new_houston_exchange", 0.6)
	var fl := TradeData.flows(sim, 7)
	if not (fl.lanes as Array).is_empty():   # and one interstellar delivery of the player's, on a busy lane
		var l: Dictionary = fl.lanes[0]
		var day := SimStats.today(sim)
		var key := "%s>%s" % [l.a, l.b]
		var f: Dictionary = day.flows.get(key, {"a": l.a, "b": l.b, "t": 0.0, "cr": 0.0, "player_t": 0.0, "coms": {}})
		f.player_t = 30.0
		day.flows[key] = f
		var life := SimStats.lifetime(sim)
		life.t = 30.0
		life.cr = 41000.0
		life.deliveries = 1
		life.relieved = 1
		life.systems[String(l.b)] = 30.0
		life.facilities["concord_exchange"] = 30.0
		day.player.cr = float(day.player.cr) + 41000.0
		day.player.t = 30.0
	Session.profile["location"] = "dock"
	Session.profile["hints_seen"] = ["welcome", "money", "crew", "holding", "arrived", "hab", "hut", "trade"]
	Session.save_profile()
	var pl: Node = load(Session.PLACE_SCENE).instantiate()
	root.add_child(pl)
	current_scene = pl
	await process_frame
	await process_frame
	var r: TradeReport = TradeReport.find(self)
	if r == null:
		r = TradeReport.attach(pl)
	r.open("overview")
	await _shot(out, "a_overview")
	r.show_page("flows")
	r._t = 3.0
	await _shot(out, "b_flows")
	r.show_page("companies")
	await _shot(out, "c_companies")
	r.show_page("you")
	await _shot(out, "d_you")
	quit(0)
