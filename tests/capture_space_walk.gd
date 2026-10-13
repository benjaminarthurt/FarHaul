extends SceneTree
## Renders a space walk: stepping out of the hatch, a scorch mark to fix, working on it, the welded patch,
## and the suit far out on the tether looking back at the ship.
## xvfb-run -a godot --path . --resolution 1280x720 -s tests/capture_space_walk.gd -- /tmp/eva
func _initialize() -> void:
	SaveSlots.dir = "user://test_saves_capture_eva_%d" % OS.get_process_id()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SaveSlots.dir))
	process_frame.connect(_run, CONNECT_ONE_SHOT)
func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var out := "/tmp/eva" if args.is_empty() else String(args[0])
	DirAccess.make_dir_recursive_absolute(out)
	Session.begin_new(2, "Pilot", "human", "normal", "roosevelt_independent_yards")
	Session.profile["hull_damage"] = 0.7
	Session.profile["patch_kits"] = 3
	var ship := ShipData.new(ModuleLibrary.new())
	ShipPresets.build(ship)
	var wear := {}
	for p in Wear.parts(ship, {}):
		wear[String(p.key)] = 1.0 if String(p.kind) == "engine" else 0.82
	Session.profile["wear"] = wear
	Session.profile["spares_kits"] = 1
	Session.save_profile()
	Session.flight_job = {}
	var f: Node = load(Session.FLIGHT_SCENE).instantiate()
	root.add_child(f)
	current_scene = f
	await process_frame
	f.model.pos = Vector3(400, 120, 2500)
	f.get_up()
	f.walk.stand_in_airlock()
	f.use()
	f.eva.face(f.walk.airlock_face)
	f.eva.look(0.0, -0.25)
	await _frames(f, 20)
	await _shot(out, "01_out_of_the_hatch")
	f.set_process(false)   # hold still for the camera: poses and the HUD are refreshed by hand below
	var marks: Dictionary = f.foot_c._eva_marks()
	var pick := -1
	for i in marks:
		if not ShipDamage.needs_kit(i) and (f.view._damage.sites[i].normal as Vector3).y > 0.5:
			pick = i
			break
	if pick < 0:
		pick = marks.keys()[0]
	var site: Dictionary = f.view._damage.sites[pick]
	f.eva.pos = (site.pos as Vector3) + (site.normal as Vector3) * 1.6 + Vector3(0.8, 0, 0.8)
	f.eva.vel = Vector3.ZERO
	var to: Vector3 = (site.pos as Vector3) - f.eva.pos
	f.eva.yaw = atan2(-to.x, -to.z)
	f.eva.pitch = asin(clampf(to.normalized().y, -1.0, 1.0))
	await _frames(f, 5)
	await _shot(out, "02_a_mark_to_fix")
	for k in 40:
		f.foot_c.eva_work(0.05, true, "wrench")
	f.foot_c._eva_tools(0.05)
	f.foot_c._update_eva_ui()
	f._update_hud()
	await _frames(f, 1)
	f.foot_c._eva_tools(0.05)
	await _shot(out, "03_wrench_at_work")
	for k in 200:
		if f.foot_c.eva_work(0.05, true, "wrench") == "done":
			break
	f.foot_c.eva_work(0.05, false)
	await _frames(f, 5)
	await _shot(out, "04_seated")
	var hole := -1
	for i in f.foot_c._eva_marks():
		if ShipDamage.needs_kit(i):
			hole = i
			break
	var hs: Dictionary = f.view._damage.sites[hole]
	f.eva.pos = (hs.pos as Vector3) + (hs.normal as Vector3) * 1.5 + Vector3(0.5, 0.3, 0.6)
	var to2: Vector3 = (hs.pos as Vector3) - f.eva.pos
	f.eva.yaw = atan2(-to2.x, -to2.z)
	f.eva.pitch = asin(clampf(to2.normalized().y, -1.0, 1.0))
	for k in 30:
		f.foot_c.eva_work(0.05, true, "torch")
	f._update_hud()
	f.foot_c._eva_tools(0.05)
	await _frames(f, 1)
	f.foot_c._eva_tools(0.05)
	print("torch lit: ", f.foot_c._flame.visible, " work_on ", f.eva.work_on, " t ", f.eva.work_t)
	await _shot(out, "04b_torch_on_a_hole")
	for k in 300:
		if f.foot_c.eva_work(0.05, true, "torch") == "done":
			break
	f.foot_c.eva_work(0.05, false)
	f.foot_c._eva_tools(0.05)
	await _frames(f, 3)
	await _shot(out, "04c_patched")
	var engine_t := -1
	for t in f.foot_c._eva_parts():
		if String(f.foot_c._part(int(t)).kind) == "engine":
			engine_t = int(t)
	var ep: Vector3 = f.foot_c._part_pos(engine_t - OnFoot.PART)
	f.eva.pos = ep + Vector3(-3.0, 2.5, -1.0)
	var to3: Vector3 = ep - f.eva.pos
	f.eva.yaw = atan2(-to3.x, -to3.z)
	f.eva.pitch = asin(clampf(to3.normalized().y, -1.0, 1.0))
	f.eva.message_t = 0.0
	f.foot_c._eva_tools(0.05)
	await _frames(f, 3)
	f.foot_c._eva_tools(0.05)
	await _shot(out, "04d_failed_engine")
	f.eva.pos = f.eva.anchor + (-f.walk.airlock_face + Vector3(0, 0.6, 0.3)).normalized() * 26.0
	var back: Vector3 = Vector3(0, 0, 4) - f.eva.pos
	f.eva.yaw = atan2(-back.x, -back.z)
	f.eva.pitch = asin(clampf(back.normalized().y, -1.0, 1.0))
	f.eva.strain = 0.7
	f.foot_c._update_eva_ui()
	f._update_hud()
	await _frames(f, 2)
	f.eva.strain = 0.7
	f.foot_c._update_eva_ui()
	await _shot(out, "05_end_of_the_tether")
	quit(0)
func _frames(f: Node, n: int) -> void:
	for i in n:
		if not f.is_processing():
			f._apply_pose()
			f._update_hud()
			f.foot_c._eva_tether()
			f.foot_c._update_eva_ui()
		await process_frame
func _shot(out: String, name: String) -> void:
	for i in 4:
		await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png("%s/%s.png" % [out, name])
	print("shot ", name)
