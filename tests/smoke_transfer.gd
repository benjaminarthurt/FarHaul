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
	check(f.xfer != null and f.phase == "depart" and f.station.visible, "the run starts undocking from the origin station")
	check(f.xfer.distance_m > 20000.0, "the destination is %.0f km away" % (f.xfer.distance_m / 1000.0))
	check(f.model.cargo_t > 1.0, "the ship flies loaded (%.1f t of cargo, %.1f t in all)" % [f.model.cargo_t, f.model.mass_t()])
	var pk := InputEventKey.new()
	pk.keycode = KEY_PERIOD
	pk.pressed = true
	f._unhandled_input(pk)
	f._unhandled_input(pk)
	f._unhandled_input(pk)
	check(f.warp_index == 3, "the period key speeds time up (x%d)" % int(f.WARPS[f.warp_index]))
	check(f._warp() == 1, "no time compression while leaving the station")
	f.model.pos = Vector3(0, 0, 4000)   # clear of the station
	await process_frame
	check(f.phase == "cruise" and not f.station.visible, "clear of the station the run is in cruise")
	check(f._warp() == 10, "time runs at x10 when the target is far")
	var ck := InputEventKey.new()
	ck.keycode = KEY_COMMA
	ck.pressed = true
	f._unhandled_input(ck)
	check(f.warp_index == 2, "the comma key slows it again")
	f.warp_index = 3
	f._update_hud()
	check(f.hud.text.contains("TARGET") and f.beacon != null, "the HUD shows the target")
	# Skip the cruise: put the ship at the destination, stopped, having burned some fuel.
	f.model.fuel_burned_t = 6.7
	f.model.fuel_t -= 6.7
	f.model.elapsed_s = 700.0
	f.model.pos = f.xfer.target
	f.model.vel = Vector3.ZERO
	await process_frame
	await process_frame
	check(f.phase == "approach" and f.station.visible and f.station_label.text != "", "arriving at the marker brings up the destination station (%s)" % f.station_label.text)
	check(absf(f.model.pos.length() - 1500.0) < 1.0 and f.model.speed() < 0.01, "the ship is at rest 1.5 km off the collar")
	check(String(Session.profile.port_id) == origin, "the run is not settled until the ship docks")
	check(f._warp() == 1 and f.hud.text.contains("APPROACH"), "approach reads as an approach")
	# Dock: nose down the axis, close and slow.
	f.model.pos = Vector3(0, 0, 50)
	f.model.basis = Basis.looking_at(Vector3(0, 0, -1), Vector3.UP)
	f.model.vel = Vector3(0, 0, -1)
	var key := InputEventKey.new()
	key.keycode = KEY_F
	key.pressed = true
	f._unhandled_input(key)
	check(f._arrived, "docking completes the run")
	check(String(Session.profile.port_id) != origin and String(Session.active_contract().get("status", "")) == "arrived", "the ship is now at the destination site")
	check(int(Session.profile.credits) < cr0, "fuel and the berth fee were charged (%d cr)" % (cr0 - int(Session.profile.credits)))
	check(Session.flight_job.is_empty(), "the flight job is cleared")
	check(bool(Session.deliver_active_contract().ok), "and it can be delivered")
	check(absf(float(Session.sim.summary()["cash_error"])) < 0.01 and Session.sim.violations.is_empty(), "money conserved")
	print("DONE fails=", fails)
	quit(1 if fails > 0 else 0)
