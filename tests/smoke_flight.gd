extends SceneTree
## The flight scene builds, flies, and returns to the dock. Run: godot --headless --path . --script res://tests/smoke_flight.gd
var fails := 0
func check(ok: bool, msg: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + msg)
	if not ok:
		fails += 1
func _initialize() -> void:
	SaveSlots.dir = "user://test_saves_flightsmoke"
	process_frame.connect(_run, CONNECT_ONE_SHOT)
func _run() -> void:
	Session.begin_new(2, "Pilot", "human", "normal", "roosevelt_independent_yards")
	var f: Node = load("res://scenes/flight.tscn").instantiate()
	root.add_child(f)
	await process_frame
	check(f.model != null and f.ship_root.get_child_count() > 0, "the scene builds the ship (%d modules)" % int(f.stats.modules))
	check(f.model.pos.length() > 100.0, "the ship starts clear of the dock")
	f.model.throttle = 1.0
	for i in 60:
		await process_frame
	check(f.model.speed() > 0.0 and f.model.fuel_t < f.model.dry_t + 100.0, "it moves under power (%.1f m/s)" % f.model.speed())
	check(f.hud.text.contains("SPEED"), "the HUD reads out speed and fuel")
	f.model.braking = true
	f.model.throttle = 0.0
	f.chase = false
	f._apply_pose()
	check(f.camera.current, "cockpit camera works")
	f.model.pos = Vector3(0, 0, 50)
	f.model.basis = Basis.looking_at(Vector3(0, 0, -1), Vector3.UP)
	f.model.vel = Vector3(0, 0, -1)
	f._update_hud()
	check(f.prompt.text.contains("dock"), "prompt offers docking when close and slow")
	print("DONE fails=", fails)
	quit(1 if fails > 0 else 0)
