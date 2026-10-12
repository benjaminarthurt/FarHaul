extends SceneTree
## Time compression on a run: , and . step the rate and the top right of the screen shows it. Every
## press answers on screen. When the game holds time at 1x (leaving the station, on the approach, near
## the target, at the brake point) it says so, why, and when it will work. The braking autopilot does
## not hold it. / goes straight back to 1x. The
## keys work on foot too.
## Run: godot --headless --path . --script res://tests/test_time_warp.gd
var fails := 0
func check(ok: bool, msg: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + msg)
	if not ok:
		fails += 1
func _initialize() -> void:
	SaveSlots.dir = "user://test_saves_time_warp"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SaveSlots.dir))
	process_frame.connect(_run, CONNECT_ONE_SHOT)
func _press(f: Node, k: int) -> void:
	var e := InputEventKey.new()
	e.keycode = k
	e.pressed = true
	f._unhandled_input(e)
func _frames(f: Node, n: int) -> void:
	for i in n:
		f._process(0.05)
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
	_frames(f, 1)
	check(not f.time_label.visible, "nothing shows at normal time")
	f.phase = "depart"   # still leaving the station: , and . can't work yet, and the readout says when they will
	_press(f, KEY_PERIOD)
	_frames(f, 1)
	check(f._warp() == 1 and String(f.time_label.text).contains("(x2 set)") and String(f.time_label.text).contains("km to go"),
			"pressing . while leaving the station says time compression starts further out (%s)" % f.time_label.text)
	_press(f, KEY_COMMA)
	_press(f, KEY_COMMA)
	_frames(f, 1)
	check(f.time_label.visible and String(f.time_label.text).contains("starts 1 km out"), ", at x1 still answers on screen (%s)" % f.time_label.text)
	f.phase = "approach"
	_press(f, KEY_PERIOD)
	_frames(f, 1)
	check(String(f.time_label.text).contains("approach"), "on the approach it says there is none there (%s)" % f.time_label.text)
	_press(f, KEY_SLASH)
	f.phase = "cruise"   # out on the run, far from the target and coasting
	var to: Vector3 = f.xfer.target - f.model.pos
	f.model.pos = f.xfer.target - to.normalized() * maxf(to.length(), 2.0e6)
	f.model.vel = Vector3.ZERO
	for i in 3:
		_press(f, KEY_PERIOD)
	_frames(f, 1)
	check(f._warp() == 10, "three presses of . make it x10 (%d)" % f._warp())
	check(f.time_label.visible and String(f.time_label.text).begins_with("TIME x10"), "the top of the screen says so (%s)" % f.time_label.text)
	f.model.vel = f.model.basis * Vector3(0, 0, -300.0)   # the braking autopilot far out: time still runs fast
	f.model.braking = true
	_frames(f, 1)
	check(f._warp() == 10, "the braking autopilot doesn't hold time at x1 far from the target (%d)" % f._warp())
	var near: Vector3 = f.xfer.target - (f.xfer.target - f.model.pos).normalized() * 20000.0
	var far_pos: Vector3 = f.model.pos
	var to_t: Vector3 = (f.xfer.target - f.model.pos).normalized()
	f.model.braking = false
	f.model.vel = to_t * 100.0   # closing slowly, so only the distance caps apply
	f.model.pos = near   # within 25 km of the target: reduced, not stopped, and it says why
	_frames(f, 1)
	check(f._warp() == 5, "within 25 km time comes down to x5 (%d)" % f._warp())
	check(String(f.time_label.text).begins_with("TIME x5") and String(f.time_label.text).contains("(x10 set)") and String(f.time_label.text).contains("within 25 km"),
			"and the readout says x5, x10 set, and why (%s)" % f.time_label.text)
	f.model.pos = f.xfer.target - to_t * 4000.0   # within 5 km: x2
	_frames(f, 1)
	check(f._warp() == 2, "within 5 km it comes down to x2 (%d)" % f._warp())
	f.model.pos = f.xfer.target - to_t * 600000.0   # fast, short of the brake point: capped by the time left
	f.model.vel = to_t * 1200.0
	f.set_warp(f.WARPS.size() - 1)   # x60 chosen
	_frames(f, 1)
	check(f._warp() == 25 and String(f.time_label.text).contains("away at this speed"),
			"closing fast, it is capped so the target stays at least 10 s away (x%d: %s)" % [f._warp(), f.time_label.text])
	f.set_warp(3)
	f.model.pos = far_pos
	f.model.vel = to_t * 0.0
	_frames(f, 1)
	check(f._warp() == 10, "out in the open again, the rate chosen comes back by itself (%d)" % f._warp())
	f.model.braking = false
	f.model.vel = Vector3.ZERO
	_press(f, KEY_COMMA)
	_frames(f, 1)
	check(f._warp() == 5, ", steps it down to x5 (%d)" % f._warp())
	f.phase = "depart"   # leaving the station: it unlocks 1 km out
	f.model.pos = f.model.pos.normalized() * 1500.0
	_frames(f, 1)
	check(f._warp() == 5, "leaving the station, past 1 km, time compression works (%d)" % f._warp())
	f.phase = "cruise"
	f.model.pos = far_pos
	_press(f, KEY_SLASH)
	_frames(f, 1)
	check(f.warp_index == 0 and f._warp() == 1, "/ goes straight back to x1")
	check(f.time_label.visible and String(f.time_label.text).begins_with("TIME x1"), "and shows TIME x1 for a moment (%s)" % f.time_label.text)
	for i in 50:
		f.hud_c._update_time()
		f.time_shown_s -= 0.05
	_frames(f, 1)
	check(not f.time_label.visible, "then the readout goes away")
	f.model.vel = Vector3.ZERO
	check(f.get_up(), "you get up from the helm")
	var e := InputEventKey.new()
	e.keycode = KEY_PERIOD
	e.pressed = true
	f._walk_input(e)
	_frames(f, 1)
	check(f._warp() == 2, ". works on foot too (%d)" % f._warp())
	f.queue_free()
	await process_frame
	print("DONE fails=%d" % fails)
	quit(1 if fails > 0 else 0)
