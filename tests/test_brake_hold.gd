extends SceneTree
## The braking autopilot keeps braking while you get up, walk about, change view and sit back down,
## even if you are still holding E (sit down, also roll) or W (walked to the seat) as you take the
## helm. A key pressed fresh at the helm still takes the controls back. On foot, the HUD says the
## autopilot is braking rather than telling you to brake.
## Run: godot --headless --path . --script res://tests/test_brake_hold.gd
var fails := 0
func check(ok: bool, msg: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + msg)
	if not ok:
		fails += 1
func _initialize() -> void:
	SaveSlots.dir = "user://test_saves_brake_hold"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SaveSlots.dir))
	process_frame.connect(_run, CONNECT_ONE_SHOT)
func _key(k: int, down: bool) -> void:
	var e := InputEventKey.new()
	e.keycode = k
	e.physical_keycode = k
	e.pressed = down
	Input.parse_input_event(e)
	Input.flush_buffered_events()
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
	f.phase = "cruise"
	f.model.pos = f.model.pos.normalized() * 3000.0
	f.model.vel = f.model.basis * Vector3(0, 0, -400.0)   # flying fast, forward
	f.model.braking = true
	_frames(f, 2)
	check(f.model.braking, "the braking autopilot is on")
	check(f.get_up(), "you get up from the helm")
	_frames(f, 4)
	check(f.model.braking, "it keeps braking while you are on your feet")
	check(not String(f.prompt.text).contains("BRAKE NOW") and String(f.prompt.text).contains("AUTOPILOT BRAKING"),
			"on foot the HUD says the autopilot is braking (%s)" % f.prompt.text)
	_key(KEY_W, true)   # still holding W from walking to the seat
	_key(KEY_E, true)   # E sits you down (at the helm, E is roll), and is still held as you take the helm
	if f.walking:
		f.sit_down()
	_frames(f, 6)
	check(f.model.braking, "sitting down while still holding E and W doesn't cancel it")
	_key(KEY_E, false)
	_key(KEY_W, false)
	_frames(f, 2)
	check(f.model.braking, "letting go of them doesn't either")
	for i in 2:   # change view twice: chase, cockpit, chase
		var c := InputEventKey.new()
		c.keycode = KEY_C
		c.pressed = true
		f._unhandled_input(c)
		_frames(f, 3)
	check(f.model.braking, "changing the camera doesn't cancel it")
	_key(KEY_W, true)   # a fresh press at the helm is the pilot taking over
	_frames(f, 2)
	_key(KEY_W, false)
	check(not f.model.braking, "a fresh throttle press at the helm takes the controls back")
	f.queue_free()
	await process_frame
	print("DONE fails=%d" % fails)
	quit(1 if fails > 0 else 0)
