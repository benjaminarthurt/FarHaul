extends SceneTree
## Walking in the flight scene: get up from the helm, walk while the ship flies on, use the ladder-less
## starter's airlock at the berth to go back to the dock, and sit back down at the helm.
## Run: godot --headless --path . --script res://tests/smoke_walk.gd
var fails := 0
func check(ok: bool, msg: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + msg)
	if not ok:
		fails += 1
func _initialize() -> void:
	SaveSlots.dir = "user://test_saves_walksmoke"
	process_frame.connect(_run, CONNECT_ONE_SHOT)
func _key(code: int) -> InputEventKey:
	var k := InputEventKey.new()
	k.keycode = code
	k.pressed = true
	return k
func _run() -> void:
	Session.begin_new(2, "Pilot", "human", "normal", "roosevelt_independent_yards")
	Session.flight_job = {}
	var f: Node = load("res://scenes/flight.tscn").instantiate()
	root.add_child(f)
	await process_frame
	check(f.walk != null and f.walk.cells.size() >= 6, "the flight scene builds the walkable ship (%d cells)" % f.walk.cells.size())
	f._unhandled_input(_key(KEY_G))
	check(f.walking and f.walk.room() == "Cockpit", "G gets up in the cockpit (%s)" % f.walk.room())
	f._update_hud()
	check(f.prompt.text.contains("take the helm"), "the prompt offers the helm (%s)" % f.prompt.text)
	var cam_d: float = f.camera.global_position.distance_to(f.model.pos + f.model.basis * (f.view.position + f.walk.eye()))
	check(cam_d < 0.01, "the camera is at the walker's eyes")
	# The ship flies on with nobody at the helm: open the throttle, get up, it keeps burning.
	f._unhandled_input(_key(KEY_E))
	check(not f.walking, "E at the helm sits back down")
	f.model.throttle = 0.5
	f._unhandled_input(_key(KEY_G))
	var v0: float = f.model.speed()
	for i in 20:
		f._process(0.05)
	check(f.model.speed() > v0 + 0.05 and absf(f.model.throttle - 0.5) < 0.001, "the burn goes on while walking (%.2f -> %.2f m/s)" % [v0, f.model.speed()])
	# Holding W walks the walker; it does not touch the throttle.
	var p0: Vector3 = f.walk.pos
	Input.parse_input_event(_key(KEY_W))
	Input.flush_buffered_events()
	await process_frame
	for i in 10:
		f._process(0.05)
	var up := _key(KEY_W)
	up.pressed = false
	Input.parse_input_event(up)
	check(f.walk.pos.distance_to(p0) > 0.3 and absf(f.model.throttle - 0.5) < 0.001, "W walks (moved %.2f m) and leaves the throttle at 50%%" % f.walk.pos.distance_to(p0))
	# Walk to the airlock: aft through the door, then east.
	f.model.throttle = 0.0
	f.model.vel = Vector3.ZERO
	f.model.pos = f.model.pos.normalized() * 140.0
	f.walk.pos = Vector3(0, ShipWalk.deck_y(0), 3.0)
	f.walk.face(Vector3(1, 0, 0))
	for i in 40:
		f.walk.step(0.05, Vector2(0, 1))
	f._update_hud()
	check(f.walk.near_airlock() and f.prompt.text.contains("leave the ship"), "at the berth the airlock offers the way off (%s)" % f.prompt.text)
	f.model.vel = Vector3(0, 0, 20)
	f._update_hud()
	check(f.prompt.text.contains("stays shut"), "under way it does not (%s)" % f.prompt.text)
	check(f.use() == "", "and E does nothing")
	f.model.vel = Vector3.ZERO
	check(f.use() == "airlock" and f.leaving, "E at the berth leaves the ship")
	print("DONE fails=", fails)
	quit(1 if fails > 0 else 0)
