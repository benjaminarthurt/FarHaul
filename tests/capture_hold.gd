extends SceneTree
## Renders 0.10.2's derelict holds: the sealed hatch, the hold open with its contents drifting out, a crate
## in hand on the way home, and the freight office buying the salvage.
## xvfb-run -a godot --path . --resolution 1280x720 -s tests/capture_hold.gd -- OUT
func _initialize() -> void:
	SaveSlots.dir = "user://test_saves_capture_hold_%d" % OS.get_process_id()
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
	var out := "/tmp/hold_frames" if args.is_empty() else String(args[0])
	DirAccess.make_dir_recursive_absolute(out)
	Session.begin_new(2, "Pilot", "human", "normal", "roosevelt_independent_yards")
	Session.profile["hints_seen"] = ["welcome", "money", "crew", "holding", "arrived", "hab", "hut"]
	Session.save_profile()
	Session.flight_job = {}
	var f: Node = load(Session.FLIGHT_SCENE).instantiate()
	root.add_child(f)
	await process_frame
	f.set_process(false)
	var t: Traffic = f.traffic_c
	t.cfg["derelicts"]["chance"] = 1.0
	t.rebuild(String(Session.profile.port_id))
	var d: Dictionary = t.derelicts[0]
	var w: NpcShip = d.ship
	var hatch: Dictionary = {}
	for p in d.points:
		if String(p.kind) == "hatch":
			hatch = p
	# Out on the tether, the hatch turned to face us, 10 m off.
	f.model.pos = Vector3(0, 0, 3000)
	f.model.vel = Vector3.ZERO
	f.model.basis = Basis()
	f._apply_pose()
	f.get_up()
	f.walk.stand_in_airlock()
	f.use()
	var hatch_world: Vector3 = f.view.global_transform * f.eva.hatch
	var out_dir: Vector3 = (hatch_world - f.model.pos).normalized()
	var n_world: Vector3 = w.body.global_basis * (hatch.normal as Vector3)
	w.global_basis = Basis(Quaternion(n_world.normalized(), -out_dir)) * w.global_basis
	var hw: Vector3 = w.body.global_transform * (hatch.pos as Vector3)
	w.global_position += (hatch_world + out_dir * 16.0) - hw
	hw = w.body.global_transform * (hatch.pos as Vector3)
	var to_view: Transform3D = f.view.global_transform.affine_inverse()
	var at: Vector3 = to_view * hw
	f.eva.pos = at + (f.eva.hatch - at).normalized() * 3.2 + Vector3(0, 0.6, 0)
	f.eva.face((at - f.eva.pos).normalized())
	f.eva.tool = "torch"
	f._apply_pose()
	f.foot_c._eva_step(0.016)
	f.foot_c._eva_hud()
	await _shot(out, "a_hatch_sealed")
	t.take(hatch)
	for i in 3:
		t.step(0.5)
	f.eva.pos = at + (f.eva.hatch - at).normalized() * 7.5 + Vector3(0, 1.2, 0)
	f.eva.face((at - f.eva.pos).normalized())
	f.eva.tool = "wrench"
	f._apply_pose()
	f.foot_c._eva_step(0.016)
	f.foot_c._eva_hud()
	await _shot(out, "b_hold_open")
	# A third-person look at the open wreck.
	f.foot_c._tools.visible = false
	var side := out_dir.cross(Vector3.UP).normalized()
	f.camera.global_position = hw - out_dir * 9.0 + side * 5.0 + Vector3(0, 3.5, 0)
	f.camera.look_at(hw - out_dir * 2.0, Vector3.UP)
	f.hud.get_parent().visible = false
	await _shot(out, "c_hold_outside")
	f.queue_free()
	await process_frame
	# Some salvage in the hold, and the freight office.
	Salvage.stow({"kind": "crate", "commodity": "electronics", "tonnes": 1.2})
	Salvage.stow({"kind": "crate", "commodity": "filters", "tonnes": 1.8})
	Salvage.stow({"kind": "part", "module": "engine", "tonnes": 3.0, "condition": 0.62})
	Session.profile["location"] = "dock"
	Session.save_profile()
	var pl: Node = load(Session.PLACE_SCENE).instantiate()
	root.add_child(pl)
	await process_frame
	pl.walker.pos = Vector3(10, 0, 1)
	pl.use_desk("freight")
	await process_frame
	await process_frame
	var sc_node: ScrollContainer = pl.panel_list.get_parent() as ScrollContainer
	if sc_node != null:
		sc_node.scroll_vertical = 100000
	await _shot(out, "d_freight_salvage")
	pl.use_desk("yard")
	await _shot(out, "e_yard_parts")
	quit(0)
