extends SceneTree
## Renders frames of the jump sequence to PNGs (needs a display: run under xvfb-run, not --headless).
## xvfb-run -a godot --path . --rendering-driver opengl3 -s tests/capture_jump.gd -- /tmp/jump_frames
func _initialize() -> void:
	SaveSlots.dir = "user://test_saves_capture"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SaveSlots.dir))
	process_frame.connect(_run, CONNECT_ONE_SHOT)
func _run() -> void:
	var out := "/tmp/jump_frames"
	for a in OS.get_cmdline_user_args():
		out = a
	DirAccess.make_dir_recursive_absolute(out)
	Session.begin_new(2, "Pilot", "human", "normal", "roosevelt_independent_yards")
	var data := SaveSlots.read(2)
	var ship := ShipData.new(ModuleLibrary.new())
	ShipPresets.build(ship, ShipPresets.STARTER_FTL)
	data["modules"] = (JSON.parse_string(ship.to_json()) as Dictionary)["modules"]
	data["cargo"] = CargoManifest.new(ship).to_dict()
	SaveSlots.write(2, data)
	SimWorld.sync(Session.sim, Session.profile, ship)
	for o in Contracts.offers_from(Session.system_id()):
		if o.has("sim_contract") and String(o.destination_system_id) != Session.system_id():
			Session.accept_contract(o)
			break
	Session.begin_jump_flight()
	var f: Node = load("res://scenes/flight.tscn").instantiate()
	root.add_child(f)
	f.set_process(false)
	await process_frame
	f.model.pos = Vector3(0, 0, 4000)
	f.model.vel = Vector3.ZERO
	f._apply_pose()
	f._update_hud()
	await _shot(f, out, "00_clear")
	f._unhandled_input(_key(KEY_J))
	var marks := {20: "01_spool", 50: "02_accel_start", 70: "03_accel_mid", 83: "04_accel_end", 88: "05_flash_rise", 92: "06_flash_peak", 96: "07_decel_start", 110: "08_decel_mid", 125: "09_decel_late", 140: "10_approach"}
	for i in range(1, 150):
		f._process(0.1)
		if marks.has(i):
			await _shot(f, out, marks[i])
	quit(0)
func _key(code: int) -> InputEventKey:
	var k := InputEventKey.new()
	k.keycode = code
	k.pressed = true
	return k
func _shot(f: Node, out: String, name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := root.get_viewport().get_texture().get_image()
	img.save_png("%s/%s.png" % [out, name])
	print("shot ", name, " phase=", f.phase, " streak=", snappedf(f.fx.streak, 0.01) if f.fx else "-", " fov=", snappedf(f.camera.fov, 0.1), " flash=", f.flash_rect.color if f.flash_rect else "-", " size=", f.flash_rect.size if f.flash_rect else "-")
