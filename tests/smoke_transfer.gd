extends SceneTree
## A local run flown in the flight scene: the scene builds in transfer mode, the clock speeds up, and
## reaching the destination settles the run. Run: godot --headless --path . --script res://tests/smoke_transfer.gd
var fails := 0
func check(ok: bool, msg: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + msg)
	if not ok:
		fails += 1
func _initialize() -> void:
	SaveSlots.dir = "user://test_saves_transfersmoke"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SaveSlots.dir))
	process_frame.connect(_run, CONNECT_ONE_SHOT)
func _run() -> void:
	Session.begin_new(2, "Pilot", "human", "normal", "roosevelt_independent_yards")
	var job: Dictionary = {}
	for o in Contracts.offers_from(Session.system_id()):
		if bool(o.get("local", false)):
			job = o
			break
	check(not job.is_empty(), "a local run is posted")
	check(bool(Session.accept_contract(job).ok), "accepted and loaded")
	var origin := String(Session.profile.port_id)
	var cr0 := int(Session.profile.credits)
	check(bool(Session.begin_local_flight().ok) and not Session.flight_job.is_empty(), "the helm is handed the run")
	var f: Node = load("res://scenes/flight.tscn").instantiate()
	root.add_child(f)
	await process_frame
	check(f.xfer != null and not f.station.visible, "the scene is in transfer mode, no station")
	check(f.xfer.distance_m > 20000.0, "the destination is %.0f km away" % (f.xfer.distance_m / 1000.0))
	check(f.model.mass_t() > 40.0, "the ship flies loaded (%.1f t)" % f.model.mass_t())
	f.warp_index = 3
	check(f._warp() == 10, "time runs at x10 when the target is far")
	f._update_hud()
	check(f.hud.text.contains("TARGET") and f.beacon != null, "the HUD shows the target")
	# Skip the flight: put the ship at the destination, stopped, having burned some fuel.
	f.model.fuel_burned_t = 6.7
	f.model.fuel_t -= 6.7
	f.model.elapsed_s = 700.0
	f.model.pos = f.xfer.target
	f.model.vel = Vector3.ZERO
	await process_frame
	await process_frame
	check(f._arrived, "arriving stops the run")
	check(String(Session.profile.port_id) != origin and String(Session.active_contract().get("status", "")) == "arrived", "the ship is now at the destination site")
	check(int(Session.profile.credits) < cr0, "fuel and the berth fee were charged (%d cr)" % (cr0 - int(Session.profile.credits)))
	check(Session.flight_job.is_empty(), "the flight job is cleared")
	check(bool(Session.deliver_active_contract().ok), "and it can be delivered")
	check(absf(float(Session.sim.summary()["cash_error"])) < 0.01 and Session.sim.violations.is_empty(), "money conserved")
	print("DONE fails=", fails)
	quit(1 if fails > 0 else 0)
