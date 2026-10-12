extends SceneTree
## Finding the way on a run, and the braking autopilot.
## - X on a run turns tail-first, coasts while there is room, then burns to stop at the target: the
##   run arrives (the approach starts) from early, from the brake point, with sideways drift, and at
##   x25 time. Started too late it says it will overshoot, and stops past the target.
## - Off screen, the target gets an arrow round the edge (and a travel arrow when travel points
##   elsewhere); the markers carry labels; the readouts give the course error.
## Run: godot --headless --path . --script res://tests/test_nav_brake.gd
var fails := 0
func check(ok: bool, msg: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + msg)
	if not ok:
		fails += 1
func _initialize() -> void:
	SaveSlots.dir = "user://test_saves_nav_brake"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SaveSlots.dir))
	process_frame.connect(_run, CONNECT_ONE_SHOT)
func _x(f: Node) -> void:
	var e := InputEventKey.new()
	e.keycode = KEY_X
	e.pressed = true
	f._unhandled_input(e)
func _run() -> void:
	Session.begin_new(2, "Pilot", "human", "normal", "roosevelt_independent_yards")
	var job: Dictionary = {}
	for o in Contracts.offers_from(Session.system_id()):
		if bool(o.get("local", false)):
			job = o
	Session.accept_contract(job)
	Session.begin_local_flight()
	var f: Node = load(Session.FLIGHT_SCENE).instantiate()
	root.add_child(f)
	await process_frame
	f.set_process(false)
	var full: float = f.model.fuel_t
	var to0: Vector3 = (f.xfer.target - f.model.pos).normalized()
	var side := to0.cross(Vector3.UP).normalized()
	var target0: Vector3 = f.xfer.target
	for case in [["early", 400000.0, 0.0, 0], ["at the brake point", 330000.0, 0.0, 0], ["drifting sideways", 400000.0, 40.0, 0], ["at x25", 400000.0, 20.0, 4], ["too late", 150000.0, 0.0, 0]]:
		f.xfer.target = target0
		f.phase = "cruise"
		f.station.visible = false
		f.model.station_solid = false
		f.model.fuel_t = full
		f.model.pos = target0 - to0 * float(case[1])
		f.model.vel = to0 * 1200.0 + side * float(case[2])
		f.model.basis = Basis.looking_at(to0, Vector3.UP)
		f.model.ang = Vector3.ZERO
		f.model.braking = false
		f.set_warp(int(case[3]))
		_x(f)
		check(f.model.braking and f.model.brake_to == target0, "%s: X sets the autopilot to stop at the target" % case[0])
		var t := 0.0
		var said := ""
		var states := {}
		while t < 1500.0 and f.model.braking and f.phase == "cruise":
			f._process(0.05)
			t += 0.05
			states[f.model.brake_state] = true
			if said == "" and f.brake_status().contains("overshoot"):
				said = f.brake_status()
		if case[0] == "too late":
			check(said != "", "too late: it says it will overshoot (%s)" % said.get_slice("   ", 0))
			check(not f.model.braking and f.model.speed() < 1.0 and f.phase == "cruise", "too late: it stops past the target")
		else:
			check(f.phase == "approach", "%s: the autopilot brings the run in (%.0f s, phase %s)" % [case[0], t, f.phase])
		if case[0] == "early":
			check("coasting" in states and "burning" in states, "early: it coasts first, then burns (%s)" % [states.keys()])
	# The way-finding markers.
	f.xfer.target = target0
	f.phase = "cruise"
	f.model.braking = false
	f.model.pos = target0 - to0 * 500000.0
	f.model.vel = to0 * 900.0
	f.model.basis = Basis.looking_at(-to0, Vector3.UP)   # facing away: the target is behind the camera
	f._process(0.05)
	check(f.reticle.target_edge != Vector2.INF and String(f.reticle.target_text).contains("km"), "with the target behind, an arrow points to it with its distance (%s)" % f.reticle.target_text)
	check(f.reticle.travel_edge == Vector2.INF, "travel toward that target needs no second arrow")
	f.model.basis = Basis.looking_at(-to0, Vector3.UP)
	f.model.vel = side * 300.0 + to0 * 50.0   # drifting off sideways
	f._process(0.05)
	check(f.reticle.travel_edge != Vector2.INF, "travel off screen in another direction gets its own arrow")
	check(String(f.hud.text).contains("off target"), "the readouts give the course error")
	f.model.basis = Basis.looking_at(to0, Vector3.UP)
	f.model.vel = to0 * 900.0
	f._process(0.05)
	check(f.reticle.target_edge == Vector2.INF and f.reticle.prograde != Vector2.INF, "facing the target: no arrow, the travel marker shows")
	check(String(f.hud.text).contains("COURSE  on target"), "and the course reads on target")
	f.queue_free()
	await process_frame
	print("DONE fails=%d" % fails)
	quit(1 if fails > 0 else 0)
