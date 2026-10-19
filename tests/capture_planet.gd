extends SceneTree
## Planets with air on screen: a run from New Houston's orbital terminal down to its surface port on
## Roosevelt, flown on the autopilot: the top of the air, the burn of the entry, the glide in over the
## land with the city on the skyline, the landing, standing outside, the terminal's window, and the
## same downport by night. xvfb-run -a godot --path . --resolution 1280x720 -s tests/capture_planet.gd -- OUT
var out := "/tmp/planet_frames"


func _initialize() -> void:
	SaveSlots.dir = "user://test_saves_capture_planet_%d" % OS.get_process_id()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SaveSlots.dir))
	process_frame.connect(_run, CONNECT_ONE_SHOT)


func _key(code: int) -> InputEventKey:
	var k := InputEventKey.new()
	k.keycode = code
	k.pressed = true
	return k


func _shot(name: String) -> void:
	for i in 3:
		await process_frame
	for i in 3:
		await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png("%s/%s.png" % [out, name])
	print("shot ", name)


func _fly_until(f: Node, cond: Callable, limit_s := 900.0) -> void:
	var t := 0.0
	while t < limit_s and not cond.call():
		f._process(0.05)
		t += 0.05
		if int(t * 20.0) % 200 == 0:
			await process_frame


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		out = String(args[0])
	DirAccess.make_dir_recursive_absolute(out)
	Hazards.off = true   # calm weather for the pictures
	Session.begin_new(2, "Pilot", "human", "normal", "roosevelt_independent_yards")
	Session.profile["hints_seen"] = ["welcome", "money", "crew", "holding", "arrived", "hab", "hut", "trade", "flight"]
	var data := SaveSlots.read(2)
	var ship := ShipData.new(ModuleLibrary.new())
	ShipPresets.build(ship, ShipPresets.STARTER_PLANET)
	data["modules"] = (JSON.parse_string(ship.to_json()) as Dictionary)["modules"]
	data["cargo"] = CargoManifest.new(ship).to_dict()
	SaveSlots.write(2, data)
	SimWorld.sync(Session.sim, Session.profile, ship)
	var job: Dictionary = {}
	for tries in 12:   # wait a board or two for a run down to the surface
		for o in Contracts.offers_from(Session.system_id()):
			if bool(o.get("local", false)) and String(LocalSpace.node(String(o.destination_port_id)).get("kind", "")) == "world":
				job = o
				break
		if not job.is_empty():
			break
		Session.sim.run_hours(48)
	print("job: ", job.get("title", "none"))
	if job.is_empty():
		quit(1)
		return
	var hod0 := PlanetScenery.local_hour("new_houston", Session.sim.now_hour())
	Session.sim.run_hours(int(fmod(24.0 + 9.0 - hod0, 24.0)))   # mid-morning on Roosevelt for the daylight shots
	Session.accept_contract(job)
	Session.begin_local_flight()
	var f: Node = load(Session.FLIGHT_SCENE).instantiate()
	root.add_child(f)
	current_scene = f
	await process_frame
	f.phase = "cruise"
	f.model.station_solid = false
	f.model.pos = f.xfer.target
	f.model.vel = Vector3.ZERO
	await process_frame
	await process_frame
	print("phase ", f.phase, " alt ", f.model.altitude())
	await _shot("a_entry_top")
	f._unhandled_input(_key(KEY_T))
	await _fly_until(f, func() -> bool: return f.model.heat_rate > 0.006 or f.model.altitude() < 30000.0)
	await _shot("b_entry_hot")
	f.chase = false
	f._apply_pose()
	await _shot("b2_entry_cockpit")
	f.chase = true
	await _fly_until(f, func() -> bool: return f.model.altitude() < 9000.0)
	await _shot("c_glide_9km")
	await _fly_until(f, func() -> bool: return f.model.altitude() < 700.0)
	await _shot("d_approach_700m")
	var tp0 := f.model.terrain as PlanetTerrain
	f.set_process(false)
	f.camera.look_at(Vector3(tp0.city_xz.x, tp0.city_h + 80.0, tp0.city_xz.y), Vector3.UP)
	await _shot("d2_city_from_700m")
	f.set_process(true)
	await _fly_until(f, func() -> bool: return f.model.landed)
	print("landed on pad: ", f.model.on_pad(), " heat peak ", f.model.skin_peak, " hull ", f.model.hull())
	await _shot("e_landed")
	f.get_up()
	f.go_outside()
	await process_frame
	var tp := f.model.terrain as PlanetTerrain
	f.suit.face(Vector3(tp.city_xz.x, 0, tp.city_xz.y) - f.suit.pos)
	f._apply_pose()
	f.set_process(false)
	f._update_hud()
	await _shot("f_outside_city")
	# The same downport by night: an hour when the sun's down.
	var hod := PlanetScenery.local_hour(f._system_id(), Session.sim.now_hour())
	f.model.elapsed_s += fmod(24.0 + 0.5 - hod, 24.0) * 3600.0   # to half past midnight
	f.land_c.update_planet(0.0)
	await _shot("g_outside_night")
	quit(0)
