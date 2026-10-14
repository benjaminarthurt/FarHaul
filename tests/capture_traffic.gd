extends SceneTree
## Renders other ships: the parked ones behind the station, one leaving, a derelict with its salvage
## panels, and a space walk over to it with the torch.
## xvfb-run -a godot --path . --resolution 1280x720 -s tests/capture_traffic.gd -- OUT
func _initialize() -> void:
	SaveSlots.dir = "user://test_saves_capture_traffic_%d" % OS.get_process_id()
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
	var out := "/tmp/traffic_frames" if args.is_empty() else String(args[0])
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
	t.cfg["derelicts"]["chance"] = 1.0
	t.rebuild(String(Session.profile.port_id))
	var cam: Camera3D = f.camera
	f.hud.get_parent().visible = false
	# The port from out front: the station with ships parked behind it.
	cam.global_position = Vector3(90, 40, 160)
	cam.look_at(Vector3(0, 0, -40), Vector3.UP)
	t.step(0.05)
	await _shot(out, "a_port_traffic")
	var ps: NpcShip = t.parked[0]   # close by a parked ship, the station beyond
	cam.global_position = ps.global_position + Vector3(-18, 9, 34)
	cam.look_at(ps.global_position.lerp(Vector3.ZERO, 0.35), Vector3.UP)
	t.step(0.05)
	await _shot(out, "a2_parked_close")
	# A ship leaving, burning out.
	if not t.movers.is_empty():
		var m: Dictionary = t.movers[0]
		m.rest = 0.0
		m.out = true
		m.state = "rest"
		t.step(0.1)
		for i in 15:
			t.step(1.0)
		var s: NpcShip = m.ship
		cam.global_position = s.global_position + s.basis * Vector3(14, 6, 30)
		cam.look_at(s.global_position, Vector3.UP)
		await _shot(out, "b_leaving")
	# The derelict.
	var w: NpcShip = t.derelicts[0].ship
	cam.global_position = w.global_position + Vector3(22, 10, 26)
	cam.look_at(w.global_position, Vector3.UP)
	t.step(0.05)
	await _shot(out, "c_derelict")
	# From the helm, far off: its tag.
	f.model.pos = w.global_position + Vector3(0, 300, 2500)
	f._apply_pose()
	cam.global_position = f.model.pos + Vector3(0, 12, 40)   # a chase view from behind the ship
	cam.look_at(w.global_position, Vector3.UP)
	t.step(0.05)
	await _shot(out, "d_derelict_tag")
	# Out on the tether, torch in hand, at a salvage panel.
	f.model.pos = Vector3(0, 0, 3000)
	f.model.vel = Vector3.ZERO
	f.model.basis = Basis()
	f._apply_pose()
	f.get_up()
	f.walk.stand_in_airlock()
	f.use()
	var p: Dictionary = t.salvage_points()[0]
	var hatch_world: Vector3 = f.view.global_transform * f.eva.hatch
	var out_dir: Vector3 = (hatch_world - f.model.pos).normalized()
	var n_world: Vector3 = w.body.global_basis * (p.point.normal as Vector3)
	w.global_basis = Basis(Quaternion(n_world.normalized(), -out_dir)) * w.global_basis   # turn the panel to face the hatch
	p = t.salvage_points()[0]
	w.global_position += (hatch_world + out_dir * 12.0) - (p.world as Vector3)
	p = t.salvage_points()[0]
	var to_view: Transform3D = f.view.global_transform.affine_inverse()
	var at: Vector3 = to_view * (p.world as Vector3)
	f.eva.pos = at + (f.eva.hatch - at).normalized() * 1.6
	f.eva.face((at - f.eva.pos).normalized())
	f.eva.tool = "torch"
	for i in 30:
		f.foot_c.eva_work(0.05, true, "torch")
	f.foot_c._eva_step(0.016)
	f.foot_c.eva_work(0.05, true, "torch")
	f._apply_pose()
	f.foot_c._eva_tools(0.05)
	f._walk_prompt() if false else null
	await _shot(out, "e_cutting")
	quit(0)
