extends SceneTree
## Renders arriving at a run's destination: the station and worlds there, not the ones you left.
## Default: Sol's port to the Saturn ring yards. Run under xvfb-run, not --headless.
## xvfb-run -a godot --path . --resolution 1280x720 -s tests/capture_arrival.gd -- /tmp/arrival [dest kind]
func _initialize() -> void:
	SaveSlots.dir = "user://test_saves_capture_arrival_%d" % OS.get_process_id()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SaveSlots.dir))
	process_frame.connect(_run, CONNECT_ONE_SHOT)
func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var out := "/tmp/arrival" if args.is_empty() else String(args[0])
	var kind := "saturn" if args.size() < 2 else String(args[1])
	DirAccess.make_dir_recursive_absolute(out)
	Session.begin_new(2, "Pilot", "human", "normal", "roosevelt_independent_yards")
	Session.profile["system_id"] = "sol"
	Session.profile["port_id"] = String(Worlds.primary_port("sol").id)
	var dest := LocalSpace.node("sol" + LocalSpace.SEP + kind)
	Session.flight_job = {"kind": "run", "contract_id": "capture", "dv_kms": float(LocalSpace.hop("port", kind).dv_kms), "hours": 90,
			"destination": String(dest.name), "key": "capture", "dest_kind": kind, "dest_id": String(dest.id),
			"origin_kind": "port", "origin_id": String(Session.profile.port_id), "system_id": "sol"}
	var f: Node = load(Session.FLIGHT_SCENE).instantiate()
	root.add_child(f)
	await process_frame
	await _shot(out, "0_leaving")
	f._begin_approach()
	f.set_process(false)
	await process_frame
	var cam: Camera3D = f.camera
	var ship: Vector3 = f.ship_root.global_position
	cam.global_position = ship + Vector3(-30, 14, 60)
	cam.look_at(f.station.global_position, Vector3.UP)
	await _shot(out, "1_arriving_" + kind)
	if f.planet != null:
		cam.look_at(f.planet.global_position, Vector3.UP)
		await _shot(out, "2_world_" + kind)
	quit(0)
func _shot(out: String, name: String) -> void:
	for i in 4:
		await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png("%s/%s.png" % [out, name])
	print("shot ", name)
