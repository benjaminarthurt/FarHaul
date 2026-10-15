extends SceneTree
## Renders a rival salvage tug at a wreck you've beaconed, cutting at it, with the radio open
## (run under xvfb-run, not --headless).
## xvfb-run -a godot --path . --resolution 1280x720 -s tests/capture_rivals.gd -- OUT
func _initialize() -> void:
	SaveSlots.dir = "user://test_saves_capture_rivals_%d" % OS.get_process_id()
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
	var out := "/tmp/rival_frames" if args.is_empty() else String(args[0])
	DirAccess.make_dir_recursive_absolute(out)
	Session.begin_new(1, "Pilot", "human", "normal", "roosevelt_independent_yards")
	Session.profile["ship_name"] = "Second Thoughts"
	Session.profile["hints_seen"] = ["welcome", "money", "crew", "holding", "arrived", "hab", "hut", "trade"]
	Session.save_profile()
	Session.flight_job = {}
	var f: Node = load("res://scenes/flight.tscn").instantiate()
	root.add_child(f)
	current_scene = f
	await process_frame
	f.set_process(false)
	var t: Traffic = f.traffic_c
	t.cfg["derelicts"]["chance"] = 1.0
	t.rebuild(String(Session.profile.port_id))
	var rc := Rivals.cfg()
	rc["chance"] = 1.0
	rc["there_first"] = 0.0
	f.comms_c.rivals = Rivals.new(f.comms_c)
	var d: Dictionary = t.derelicts[0]
	for x in t.derelicts:   # the biggest wreck
		if (x.ship as NpcShip).radius > (d.ship as NpcShip).radius:
			d = x
	var w: NpcShip = d.ship
	f.model.pos = w.global_position + Vector3(20, 10, w.radius * 2.0 + 45.0)
	f.model.basis = Basis.looking_at((w.global_position - f.model.pos).normalized(), Vector3.UP)
	f.model.vel = Vector3.ZERO
	f.comms_c.step(0.1, 0.0)
	for c in f.comms_c.contacts():
		if String(c.kind) == "wreck" and String(c.id) == "wreck:" + String(d.id_base):
			f.comms_c.act(String(c.id), "beacon")
	var r: Dictionary = f.comms_c.rivals._rival_for(d)
	for i in 400:
		f.comms_c.step(2.0, 0.05)
		if String(r.get("state", "")) == "working":
			break
	f.comms_c.queue.clear()
	f.comms_c.current = {}
	r.cut = 10.0
	f.comms_c.act("rival:" + String(d.id_base), "split")
	f.comms_panel.open()
	f.chase = true
	for i in 600:
		f.comms_c.step(0.05, 0.05)
		f.comms_c.rivals._work(r, 0.0)
		f._apply_pose()
		t.step(0.0)
		var mid: Vector3 = w.global_position.lerp((r.ship as NpcShip).global_position, 0.4)
		f.camera.global_position = f.model.pos + f.model.basis * Vector3(-14, 10, 26)
		var fwd: Vector3 = (mid - f.camera.global_position).normalized()
		f.camera.look_at(mid + fwd.cross(Vector3.UP).normalized() * -0.0 + (fwd.cross(Vector3.UP).normalized()) * mid.distance_to(f.camera.global_position) * 0.32, Vector3.UP)
		await process_frame
		var c: Dictionary = f.comms_c.current
		if not c.is_empty() and String(c.get("who", "")).begins_with("Salvage") and float(c.t) > float(c.dur) * 0.6:
			break
	await _shot(out, "01_rival")
	quit(0)
