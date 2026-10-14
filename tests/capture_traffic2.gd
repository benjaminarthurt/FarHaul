extends SceneTree
## Renders 0.10.1's traffic: a ship in orbit with the planet behind it, the survey ship, a station pod,
## and a dead ship out on a run's route.
## xvfb-run -a godot --path . --resolution 1280x720 -s tests/capture_traffic2.gd -- OUT
func _initialize() -> void:
	SaveSlots.dir = "user://test_saves_capture_traffic2_%d" % OS.get_process_id()
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
	var out := "/tmp/traffic2_frames" if args.is_empty() else String(args[0])
	DirAccess.make_dir_recursive_absolute(out)
	Session.begin_new(2, "Pilot", "human", "normal", "roosevelt_independent_yards")
	Session.profile["system_id"] = "sol"
	Session.profile["port_id"] = String(Worlds.primary_port("sol").id)
	Session.save_profile()
	Session.flight_job = {}
	var f: Node = load(Session.FLIGHT_SCENE).instantiate()
	root.add_child(f)
	await process_frame
	f.set_process(false)
	var t: Traffic = f.traffic_c
	var cam: Camera3D = f.camera
	f.hud.get_parent().visible = false
	t.step(0.05)
	# In orbit: the ship over the planet's limb.
	var o: Dictionary = t.orbiters[1]
	var s: NpcShip = o.ship
	var w: Node3D = o.world
	var up := (s.global_position - w.global_position).normalized()
	cam.global_position = s.global_position + up * 10.0 + s.global_basis.z * 26.0 + s.global_basis.x * 14.0
	cam.look_at(s.global_position - up * 8.0, up)
	t.step(0.05)
	await _shot(out, "a_orbiter")
	# The survey ship on its way.
	for m in t.movers:
		if (m.ship as NpcShip).title.begins_with("SURVEY"):
			m.rest = 0.0
			m.out = true
			m.state = "rest"
			t.step(0.1)
			for i in 12:
				t.step(1.0)
			var sv: NpcShip = m.ship
			cam.global_position = sv.global_position + sv.basis * Vector3(16, 7, 28)
			cam.look_at(sv.global_position, Vector3.UP)
			await _shot(out, "b_survey")
	# A pod on its errand.
	var pm: Dictionary = t.pods[0]
	pm.rest = 0.0
	t.step(0.1)
	t.step(1.6)
	var pod: NpcShip = pm.ship
	cam.global_position = pod.global_position + Vector3(7, 4, 12)
	cam.look_at(pod.global_position.lerp(t.parked[int(pm.home)].global_position, 0.15), Vector3.UP)
	t.step(0.0)
	await _shot(out, "c_pod")
	f.queue_free()
	await process_frame
	# Out on a run: a dead ship that dropped out of a failed jump.
	var dest := LocalSpace.node("sol__saturn")
	Session.flight_job = {"kind": "run", "contract_id": "x", "dv_kms": 8.0, "hours": 96, "destination": String(dest.name), "key": "capture-deep",
			"dest_kind": "saturn", "dest_id": "sol__saturn", "origin_kind": "port", "origin_id": String(Session.profile.port_id), "system_id": "sol"}
	f = load(Session.FLIGHT_SCENE).instantiate()
	root.add_child(f)
	await process_frame
	f.set_process(false)
	t = f.traffic_c
	(t.cfg.deep as Dictionary)["chance"] = 1.0
	f.phase = "cruise"
	f.station.visible = false
	f.model.station_solid = false
	f.model.pos = f.xfer.target * 0.05
	t.passer_wait = 1.0e9
	t.step(0.05)
	var d: NpcShip = null
	for dd in t.derelicts:
		if bool(dd.deep):
			d = dd.ship
	cam = f.camera
	f.hud.get_parent().visible = false
	cam.global_position = d.global_position + Vector3(16, 7, 19)
	cam.look_at(d.global_position, Vector3.UP)
	f.model.pos = cam.global_position
	t.step(0.05)
	await _shot(out, "d_deep_wreck")
	quit(0)
