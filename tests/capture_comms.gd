extends SceneTree
## Renders the radio: the comms panel at the station with clearance coming through, a hauler alongside
## with fuel, and a mayday out on a run (run under xvfb-run, not --headless).
## xvfb-run -a godot --path . --resolution 1280x720 -s tests/capture_comms.gd -- OUT
func _initialize() -> void:
	SaveSlots.dir = "user://test_saves_capture_comms_%d" % OS.get_process_id()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SaveSlots.dir))
	process_frame.connect(_run, CONNECT_ONE_SHOT)


func _shot(out: String, name: String) -> void:
	for i in 3:
		await process_frame
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png("%s/%s.png" % [out, name])
	print("shot ", name)


## Run the radio until line `n` of the queue is part way through being said.
func _until_said(f: Node, frac := 0.6) -> void:
	for i in 600:
		await process_frame
		var c: Dictionary = f.comms_c.current
		if not c.is_empty() and String(c.get("text", "")) != "" and String(c.get("who", "")) != "YOU" and float(c.t) > float(c.dur) * frac:
			return


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var out := "/tmp/comms_frames" if args.is_empty() else String(args[0])
	DirAccess.make_dir_recursive_absolute(out)
	Session.begin_new(1, "Pilot", "human", "normal", "roosevelt_independent_yards")
	Session.profile["ship_name"] = "Second Thoughts"
	Session.profile["hints_seen"] = ["welcome", "money", "crew", "holding", "arrived", "hab", "hut", "trade"]
	Session.save_profile()
	Session.flight_job = {}
	Comms.cfg()["clearance"]["hold_chance"] = 0.0
	var f: Node = load("res://scenes/flight.tscn").instantiate()
	root.add_child(f)
	current_scene = f
	await process_frame
	f.model.pos = Vector3(14, 6, 210)
	f.model.basis = Basis.looking_at((Vector3(0, 0, 32) - f.model.pos).normalized(), Vector3.UP)
	f.model.vel = Vector3.ZERO
	f.chase = true
	f._apply_pose()
	f.comms_panel.open()
	f.comms_c.act("control", "clearance")
	await _until_said(f, 0.55)
	await _shot(out, "01_clearance")
	# A hauler alongside with fuel.
	f.comms_panel.close()
	f.model.fuel_t -= 5.0
	f.model.fuel_burned_t += 5.0
	var hauler: Dictionary = {}
	for c in f.comms_c.contacts():
		if String(c.kind) == "hauler":
			hauler = c
	if not hauler.is_empty():
		f.comms_c.act(String(hauler.id), "fuel")
		f.comms_c.fuel_deal.stage = "transfer"   # skip the trip over
		f.set_process(false)
		for i in 400:   # the radio and the hose, by hand, with the camera off to one side
			f.comms_c.step(0.05, 0.05)
			f._apply_pose()
			var h: NpcShip = f.comms_c.fuel_deal.ship
			f.camera.global_position = f.model.pos + f.model.basis * Vector3(-30, 18, 34)
			f.camera.look_at((f.model.pos + h.global_position) * 0.5, Vector3.UP)
			await process_frame
			var c: Dictionary = f.comms_c.current
			if not c.is_empty() and String(c.get("who", "")) == String(f.comms_c.fuel_deal.name) and float(c.t) > float(c.dur) * 0.6:
				break
		await _shot(out, "02_fuel_alongside")
		f.set_process(true)
	f.queue_free()
	await process_frame
	# A mayday out on a run.
	var job: Dictionary = {}
	for o in Contracts.offers_from(Session.system_id()):
		if bool(o.get("local", false)) and not bool(o.get("surface", false)) and String(LocalSpace.node(String(o.destination_port_id)).get("kind", "")) != "moon":
			job = o
			break
	Session.accept_contract(job)
	Session.begin_local_flight()
	Comms.cfg()["distress"]["chance"] = 1.0
	f = load("res://scenes/flight.tscn").instantiate()
	root.add_child(f)
	current_scene = f
	await process_frame
	f.model.pos = Vector3(0, 0, 4000)
	await process_frame
	await process_frame
	var s: NpcShip = f.comms_c.distress.get("ship", null)
	if s != null:
		var to: Vector3 = s.global_position - f.model.pos
		f.model.pos = s.global_position - to.normalized() * 180.0 + Vector3(0, 12, 0)
		f.model.basis = Basis.looking_at(to.normalized(), Vector3.UP)
		f.model.vel = Vector3.ZERO
		f.chase = true
	f._apply_pose()
	f.comms_panel.open()
	f.set_process(false)
	for i in 600:
		f.comms_c.step(0.05, 0.05)
		f._apply_pose()
		f.traffic_c.step(0.0)
		if s != null:   # from just behind them, your ship coming up beyond
			var back: Vector3 = (s.global_position - f.model.pos).normalized()
			var side: Vector3 = back.cross(Vector3.UP).normalized()
			f.camera.global_position = s.global_position + back * 70.0 + Vector3(0, 16, 0) + side * 20.0
			f.camera.look_at(s.global_position - side * 22.0, Vector3.UP)
		await process_frame
		var c: Dictionary = f.comms_c.current
		if not c.is_empty() and String(c.get("who", "")).begins_with("DISTRESS") and float(c.t) > float(c.dur) * 0.7:
			break
	await _shot(out, "03_mayday")
	quit(0)
