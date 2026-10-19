extends SceneTree
## A tour of the planets with air: for each world, the autopilot brings a loaded planet starter down from the
## top of the air; a shot of the ground and the city from about 1.5 km up, and one from the pad. Daylight.
## xvfb-run -a godot --path . --resolution 1280x720 -s tests/capture_worlds.gd -- OUT sys1 sys2 ...
var out := "/tmp/world_frames"


func _initialize() -> void:
	SaveSlots.dir = "user://test_saves_capture_worlds_%d" % OS.get_process_id()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SaveSlots.dir))
	process_frame.connect(_run, CONNECT_ONE_SHOT)


func _shot(name: String) -> void:
	for i in 3:
		await process_frame
	for i in 3:
		await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png("%s/%s.png" % [out, name])
	print("shot ", name)


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var systems := ["sol", "pelagos", "talos", "ilos", "keshar", "tidemark"]
	if not args.is_empty():
		out = String(args[0])
	if args.size() > 1:
		systems = args.slice(1)
	DirAccess.make_dir_recursive_absolute(out)
	Hazards.off = true
	Session.begin_new(2, "Pilot", "human", "normal", "roosevelt_independent_yards")
	var data := SaveSlots.read(2)
	var ship := ShipData.new(ModuleLibrary.new())
	ShipPresets.build(ship, ShipPresets.STARTER_PLANET)
	data["modules"] = (JSON.parse_string(ship.to_json()) as Dictionary)["modules"]
	data["cargo"] = CargoManifest.new(ship).to_dict()
	SaveSlots.write(2, data)
	for entry in systems:
		var sys := String(entry).get_slice(":", 0)
		var wx := String(entry).get_slice(":", 1) if String(entry).contains(":") else ""
		var kind := "world"
		var hod := PlanetScenery.local_hour(String(sys), Session.sim.now_hour())
		Session.sim.run_hours(int(fmod(24.0 + 10.0 - hod, 24.0)))   # mid-morning there
		Session.flight_job = {"kind": "run", "contract_id": "tour", "dv_kms": 0.6, "hours": 3, "destination": Planets.site_name(String(sys), kind),
				"key": "tour-" + String(sys), "dest_kind": kind, "dest_id": String(sys) + "__" + kind, "origin_kind": "port",
				"origin_id": String(Worlds.primary_port(String(sys)).id), "system_id": String(sys)}
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
		f.model.autoentry = true
		if wx != "":   # a given weather for the pictures: "pelagos:rain"
			var kd: Dictionary = Planets.config().weather.kinds[wx]
			f.weather = {"kind": wx, "name": String(kd.name), "wind": Vector3(7, 0, 4), "gust": float(kd.gust), "fog": float(kd.fog), "speed": 8.0}
		var t := 0.0
		while t < 900.0 and f.model.altitude() > 1500.0:
			f._process(0.05)
			t += 0.05
			if int(t * 20.0) % 300 == 0:
				await process_frame
		var tp := f.model.terrain as PlanetTerrain
		f.set_process(false)
		f.camera.global_position = f.model.pos + Vector3(0, 30, 0)
		f.camera.look_at(Vector3(tp.city_xz.x, tp.city_h, tp.city_xz.y), Vector3.UP)
		f.land_c.update_planet(0.0)
		await _shot("%s%s_a_air" % [sys, wx])
		f.set_process(true)
		while t < 1300.0 and not f.model.landed:
			f._process(0.05)
			t += 0.05
			if int(t * 20.0) % 300 == 0:
				await process_frame
		print(sys, " landed ", f.model.landed, " on pad ", f.model.on_pad(), " hull ", f.model.hull())
		f.set_process(false)
		f.camera.global_position = f.model.pos + Vector3(0, 6, 0) - (Vector3(tp.city_xz.x, 0, tp.city_xz.y).normalized() * 40.0)
		f.camera.look_at(Vector3(tp.city_xz.x, tp.city_h + 60.0, tp.city_xz.y), Vector3.UP)
		await _shot("%s%s_b_pad" % [sys, wx])
		f.queue_free()
		await process_frame
		await process_frame
	quit(0)
