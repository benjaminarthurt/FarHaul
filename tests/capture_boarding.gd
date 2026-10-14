extends SceneTree
## Renders boarding a derelict: its airlock door from outside, inside by the suit lamp, the log at the
## helm, and something to carry out.
## xvfb-run -a godot --path . --resolution 1280x720 -s tests/capture_boarding.gd -- OUT
func _initialize() -> void:
	SaveSlots.dir = "user://test_saves_capture_boarding_%d" % OS.get_process_id()
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
	var out := "/tmp/boarding_frames" if args.is_empty() else String(args[0])
	DirAccess.make_dir_recursive_absolute(out)
	Session.begin_new(1, "Pilot", "human", "normal", "roosevelt_independent_yards")
	Session.flight_job = {}
	var f: Node = load(Session.FLIGHT_SCENE).instantiate()
	root.add_child(f)
	current_scene = f
	await process_frame
	f.set_process(false)
	var t: Traffic = f.traffic_c
	t.cfg["derelicts"]["chance"] = 1.0
	t.rebuild(String(Session.profile.port_id))
	var d: Dictionary = {}
	for dd in t.derelicts:   # one with somebody aboard, if there is one
		var c := Wreckage.roll((dd.ship as NpcShip).ship, Boarding._ship_name(dd), bool(dd.deep), String(dd.id_base))
		if d.is_empty() or (c.items as Array).any(func(i): return String(i.kind) == "body"):
			d = dd
	var w: NpcShip = d.ship
	var door: Dictionary = (d.points as Array).filter(func(p): return String(p.kind) == "door")[0]
	f.model.pos = Vector3(0, 0, 3000)
	f.model.vel = Vector3.ZERO
	f.model.basis = Basis()
	f._apply_pose()
	f.get_up()
	f.walk.stand_in_airlock()
	f.use()
	# Their door, 6 m off, turned to face us.
	var hatch_world: Vector3 = f.view.global_transform * f.eva.hatch
	var out_dir: Vector3 = (hatch_world - f.model.pos).normalized()
	var n_world: Vector3 = w.body.global_basis * (door.normal as Vector3)
	w.global_basis = Basis(Quaternion(n_world.normalized(), -out_dir)) * w.global_basis
	var dw: Vector3 = w.body.global_transform * (door.pos as Vector3)
	w.global_position += (hatch_world + out_dir * 14.0) - dw
	dw = w.body.global_transform * (door.pos as Vector3)
	var to_view: Transform3D = f.view.global_transform.affine_inverse()
	var at: Vector3 = to_view * dw
	f.eva.pos = at + (f.eva.hatch - at).normalized() * 4.5 + Vector3(0, 0.4, 0)
	f.eva.face((at - f.eva.pos).normalized())
	f.eva.tool = "torch"
	f._apply_pose()
	f.foot_c._eva_step(0.016)
	f.foot_c._eva_hud()
	await _shot(out, "a_door")
	t.take(door)
	var bo: Boarding = f.foot_c.boarding
	bo.enter(d)
	bo.message_t = 0.0
	bo.walk.look(0.0, -0.05)
	f._apply_pose()
	bo.hud()
	await _shot(out, "b_inside")
	var near: Array = bo.items.filter(func(e): return String(e.item.kind) == "body")
	if near.is_empty():
		near = bo.items.filter(func(e): return String(e.item.kind) == "crate")
	if not near.is_empty():
		var p: Vector3 = near[0].pos
		var cell := ShipGrid.world_to_cell(p - Vector3(0, Interiors.FLOOR, 0))
		bo.walk.pos = p + (ShipGrid.cell_to_world(cell) - p).normalized() * 1.2 if (ShipGrid.cell_to_world(cell) - p).length() > 0.3 else p + Vector3(0, 0, 1.2)
		bo.walk.pos.y = p.y
		bo.walk._resolve()
		bo.walk.face(Vector3(p.x - bo.walk.pos.x, 0, p.z - bo.walk.pos.z).normalized())
		bo.walk.pitch = -0.6
		f._apply_pose()
		bo.hud()
		await _shot(out, "c_aboard")
	bo.walk.pos = bo.walk.helm_stand
	bo.walk.face(bo.walk.helm_face)
	bo.walk.pitch = -0.25
	bo.read_log()
	f._apply_pose()
	bo.hud()
	await _shot(out, "d_log")
	quit(0)
