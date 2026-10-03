extends SceneTree
## A flown star jump: undock, fly clear, engage the drive, the stars streak, the flash, the drop out in
## the destination system and the docking there. Run: godot --headless --path . --script res://tests/smoke_jump.gd
var fails := 0
func check(ok: bool, msg: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + msg)
	if not ok:
		fails += 1
func _key(code: int) -> InputEventKey:
	var k := InputEventKey.new()
	k.keycode = code
	k.pressed = true
	return k
func _initialize() -> void:
	SaveSlots.dir = "user://test_saves_jumpsmoke"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SaveSlots.dir))
	process_frame.connect(_run, CONNECT_ONE_SHOT)
func _run() -> void:
	Session.begin_new(2, "Pilot", "human", "normal", "roosevelt_independent_yards")
	var data := SaveSlots.read(2)
	var ship := ShipData.new(ModuleLibrary.new())
	ShipPresets.build(ship, ShipPresets.STARTER_FTL)
	data["modules"] = (JSON.parse_string(ship.to_json()) as Dictionary)["modules"]
	data["cargo"] = CargoManifest.new(ship).to_dict()
	SaveSlots.write(2, data)
	SimWorld.sync(Session.sim, Session.profile, ship)
	var offer: Dictionary = {}
	for o in Contracts.offers_from(Session.system_id()):
		if o.has("sim_contract") and String(o.destination_system_id) != Session.system_id():
			offer = o
			break
	check(not offer.is_empty(), "interstellar freight is posted")
	check(bool(Session.accept_contract(offer).ok), "accepted and loaded")
	var origin_system := Session.system_id()
	var day0 := Session.day()
	var cr0 := int(Session.profile.credits)
	check(bool(Session.begin_jump_flight().ok) and String(Session.flight_job.kind) == "jump", "the helm is handed the jump")
	var f: Node = load("res://scenes/flight.tscn").instantiate()
	root.add_child(f)
	await process_frame
	check(f.phase == "depart" and f.fx != null and not f.fx.visible, "the flight starts at the dock, drive cold")
	check(f._jump_blocker() != "", "too close to the station to jump (%s)" % f._jump_blocker())
	f._unhandled_input(_key(KEY_J))
	check(f.phase == "depart", "J does nothing while the blocker stands")
	f.model.pos = Vector3(0, 0, 4000)
	f.model.vel = Vector3(0, 0, 500)
	check(f._jump_blocker() != "", "too fast to jump (%s)" % f._jump_blocker())
	f.model.vel = Vector3.ZERO
	check(f._jump_blocker() == "", "clear and slow: the drive can engage")
	f._update_hud()
	check(f.prompt.text.begins_with("J:"), "the prompt offers the jump: %s" % f.prompt.text)
	f._unhandled_input(_key(KEY_J))
	check(f.phase == "spool" and f.fx.visible, "J starts the spool and the star field appears")
	var steps := 0
	var saw_warp := false
	var saw_decel := false
	while f.phase != "approach" and steps < 400:
		steps += 1
		f._process(0.1)
		if f.phase == "warp":
			saw_warp = true
		if f.phase == "decel":
			saw_decel = true
	check(saw_warp and saw_decel, "the sequence runs spool, warp, flash, decel (%d steps)" % steps)
	check(f.jump_peak_streak >= 0.99, "the stars stretch into full streaks")
	check(f.jump_peak_fov >= 110.0, "the view widens to %.0f degrees" % f.jump_peak_fov)
	check(f.jump_peak_flash >= 0.98, "the screen flashes white")
	check(f.audio.events == ["engage", "boom", "settle"], "the sound cues play in order: %s" % str(f.audio.events))
	check(not f.audio.active and f.audio.hum.volume_db <= -79.0, "and the loops are silent when the jump ends")
	check(f.audio.hum.stream != null and f.audio.whine.stream != null and f.audio.rush.stream != null and f.audio.cues["boom"].stream != null, "every sound file loaded")
	check(f._jump_committed and bool(f._jump_result.get("ok", false)), "the trip ran at the flash: %s" % String(f._jump_result.get("message", "")))
	check(Session.system_id() != origin_system and Session.day() > day0, "the ship is in another system, %d days on" % (Session.day() - day0))
	check(f.phase == "approach" and f.station.visible and absf(f.camera.fov - 70.0) < 0.5 and not f.fx.visible, "it drops out into a docking approach, view back to normal")
	check(f.station_label.text == String(Session.flight_job.destination).to_upper(), "the station is the destination's: %s" % f.station_label.text)
	check(int(Session.profile.credits) < cr0, "the trip's running costs were charged")
	f.model.pos = Vector3(0, 0, 50)
	f.model.basis = Basis.looking_at(Vector3(0, 0, -1), Vector3.UP)
	f.model.vel = Vector3(0, 0, -1)
	f._unhandled_input(_key(KEY_F))
	check(f._arrived and Session.flight_job.is_empty(), "docking closes out the flight")
	check(String(Session.active_contract().get("status", "")) == "arrived", "the contract has arrived")
	check(bool(Session.deliver_active_contract().ok), "and it can be delivered")
	check(absf(float(Session.sim.summary()["cash_error"])) < 0.01 and Session.sim.violations.is_empty(), "money conserved")
	print("DONE fails=", fails)
	quit(1 if fails > 0 else 0)
