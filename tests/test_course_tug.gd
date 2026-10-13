extends SceneTree
## Course hold (V) and the tug.
## - V only engages on a run with the nose within 5 degrees of the target, and says so otherwise.
## - Engaged and coasting, it trims sideways drift out with small burns of its own and leaves the
##   pilot's throttle closed; burning, it steers the burn so the travel swings onto the target.
## - A turn key or X lets it go (X hands over to the braking autopilot).
## - Out of fuel nearer the destination, Esc's tug takes you on and the run is delivered; nearer the
##   start, it tows you back. The prompt says which, and the fee.
## Run: godot --headless --path . --script res://tests/test_course_tug.gd
var fails := 0
func check(ok: bool, msg: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + msg)
	if not ok:
		fails += 1
func _initialize() -> void:
	SaveSlots.dir = "user://test_saves_course_tug"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SaveSlots.dir))
	process_frame.connect(_run, CONNECT_ONE_SHOT)
func _key(f: Node, k: int) -> void:
	var e := InputEventKey.new()
	e.keycode = k
	e.pressed = true
	f._unhandled_input(e)
func _drift(f: Node) -> float:
	var to: Vector3 = (f.xfer.target - f.model.pos).normalized()
	return (f.model.vel - to * maxf(f.model.vel.dot(to), 0.0)).length()
func _start() -> Node:
	Session.begin_new(2, "Pilot", "human", "normal", "roosevelt_independent_yards")
	var job: Dictionary = {}
	for o in Contracts.offers_from(Session.system_id()):
		if bool(o.get("local", false)) and not String(o.get("dest_kind", "port")) in LocalSpace.SURFACE:
			job = o
	if job.is_empty():
		for o in Contracts.offers_from(Session.system_id()):
			if bool(o.get("local", false)):
				job = o
	Session.accept_contract(job)
	Session.begin_local_flight()
	var f: Node = load(Session.FLIGHT_SCENE).instantiate()
	root.add_child(f)
	return f
func _run() -> void:
	var f := _start()
	await process_frame
	f.set_process(false)
	f.phase = "cruise"
	f.station.visible = false
	f.model.station_solid = false
	var to: Vector3 = (f.xfer.target - f.model.pos).normalized()
	var side := to.cross(Vector3.UP).normalized()
	f.model.pos = f.xfer.target - to * 600000.0
	f.model.vel = to * 600.0 + side * 30.0   # drifting 30 m/s sideways
	f.model.basis = Basis.looking_at((to + side * 0.2).normalized(), Vector3.UP)   # about 11 degrees off
	_key(f, KEY_V)
	check(not f.model.course_hold and String(f.notice).contains("within 5°"), "V refuses with the nose 11° off, and says why (%s)" % f.notice)
	f.model.basis = Basis.looking_at((to + side * 0.05).normalized(), Vector3.UP)   # about 3 degrees off
	_key(f, KEY_V)
	check(f.model.course_hold, "V engages with the nose within 5°")
	var fuel0: float = f.model.fuel_t
	var t := 0.0
	var trimmed := false
	while t < 120.0:
		f._process(0.05)
		t += 0.05
		trimmed = trimmed or f.model.trimming
	check(trimmed and _drift(f) < 0.6, "coasting, it trims the 30 m/s of drift out (%.2f m/s left)" % _drift(f))
	check(f.model.course_hold and f.model.throttle == 0.0, "and stays on, with the pilot's throttle still closed")
	check(fuel0 - f.model.fuel_t < 0.5, "trimming costs little fuel (%.3f t)" % (fuel0 - f.model.fuel_t))
	check(f.model.aim_error_deg(f.xfer.target) < 3.0, "then rests the nose on the target (%.1f° off)" % f.model.aim_error_deg(f.xfer.target))
	f.model.vel = to * 300.0 + side * 25.0   # burning with drift: the burn swings the travel onto the target
	var off0 := rad_to_deg(f.model.vel.angle_to(f.xfer.target - f.model.pos))
	f.model.throttle = 1.0
	for i in 400:
		f._process(0.05)
	var off1 := rad_to_deg(f.model.vel.angle_to(f.xfer.target - f.model.pos))
	check(off1 < 0.5 and off1 < off0, "burning, it steers the burn so the travel comes onto the target (%.1f° -> %.2f°)" % [off0, off1])
	f.model.throttle = 0.0
	var e := InputEventKey.new()   # a turn key lets it go
	e.keycode = KEY_LEFT
	e.physical_keycode = KEY_LEFT
	e.pressed = true
	Input.parse_input_event(e)
	Input.flush_buffered_events()
	f._process(0.05)
	e = e.duplicate()
	e.pressed = false
	Input.parse_input_event(e)
	Input.flush_buffered_events()
	check(not f.model.course_hold, "a turn key lets course hold go")
	f.model.basis = Basis.looking_at(to, Vector3.UP)
	_key(f, KEY_V)
	_key(f, KEY_X)
	check(not f.model.course_hold and f.model.braking, "X hands over from course hold to the braking autopilot")
	f.model.braking = false
	# The tug: out of fuel, nearer the start, it tows you back.
	f.model.fuel_t = 0.0
	f.model.pos = f.xfer.target - to * (f.xfer.target.length() * 0.8)
	f.model.vel = Vector3.ZERO
	f.notice_s = 0.0   # let the last notice ("Course hold on") go
	f._process(0.05)
	check(not f.tow_goes_on() and String(f.prompt.text).contains("back to the start"), "out of fuel nearer the start, the tug takes you back (%s)" % f.prompt.text)
	# Nearer the destination: it takes you on, and the run is delivered.
	f.model.pos = f.xfer.target - to * 20000.0
	f._process(0.05)
	check(f.tow_goes_on() and String(f.prompt.text).contains("tows you on") and String(f.prompt.text).contains("delivered"), "nearer the destination, it says the tug takes you on (%s)" % f.prompt.text)
	var dest := String(Session.active_contract().get("destination_port_id", ""))
	_key(f, KEY_T)
	check(String(Session.flash).contains("tug"), "the message says a tug towed you in (%s)" % Session.flash)
	await process_frame
	check(String(Session.profile.port_id) == dest and String(Session.active_contract().get("status", "")) == "arrived",
			"Esc: towed in, at %s, the run arrived (%s)" % [Session.profile.port_id, Session.active_contract().get("status", "")])
	print("DONE fails=%d" % fails)
	quit(1 if fails > 0 else 0)
