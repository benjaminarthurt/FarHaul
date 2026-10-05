extends SceneTree
## The everyday sounds load and play where they should: port room tone and footsteps, desk clicks,
## the engine following the throttle, the suit's breathing outside, and a cue for a job done.
## Run: godot --headless --path . --script res://tests/test_world_audio.gd
var fails := 0
func check(ok: bool, msg: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + msg)
	if not ok:
		fails += 1
func _initialize() -> void:
	SaveSlots.dir = "user://test_saves_world_audio"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SaveSlots.dir))
	process_frame.connect(_run, CONNECT_ONE_SHOT)
func _run() -> void:
	var names := ["port_hum", "hab_hum", "ship_hum", "engine", "lift", "breath", "low_air", "ui", "done", "thud"]
	for k in 3:
		names.append("step_metal_%d" % k)
		names.append("step_dust_%d" % k)
	var missing := []
	for n in names:
		if not ResourceLoader.exists(WorldAudio.DIR + n + ".wav"):
			missing.append(n)
	check(missing.is_empty(), "all %d sounds are there %s" % [names.size(), missing])
	var wa := WorldAudio.new()
	root.add_child(wa)
	wa.loop("port_hum")
	var s: AudioStreamWAV = wa.loops["port_hum"].stream
	check(s.loop_mode == AudioStreamWAV.LOOP_FORWARD and s.loop_end > int(s.mix_rate * 7.5), "room tone loops over its whole 8 s (%d samples)" % s.loop_end)
	wa.queue_free()
	Session.begin_new(2, "Pilot", "human", "normal", "roosevelt_independent_yards")
	var p: Node = load(Session.PLACE_SCENE).instantiate()
	root.add_child(p)
	await process_frame
	check(p.audio.loops.has("port_hum") and float(p.audio._levels["port_hum"]) > 0.0, "the concourse has its room tone")
	Input.parse_input_event(_key(KEY_W, true))
	Input.flush_buffered_events()
	for i in 120:
		p._process(0.05)
	Input.parse_input_event(_key(KEY_W, false))
	var steps := 0
	for n in p.audio.played:
		if String(n).begins_with("step_metal"):
			steps += 1
	check(steps >= 4, "walking makes footsteps (%d)" % steps)
	p.use_desk("bar")
	check("ui" in p.audio.played, "opening a desk clicks")
	p.queue_free()
	await process_frame
	Session.flight_job = {}
	var f: Node = load(Session.FLIGHT_SCENE).instantiate()
	root.add_child(f)
	await process_frame
	f.model.throttle = 1.0
	f._mix_audio(0.1)
	check(float(f.sounds._levels["engine"]) > 0.9, "the engine is heard at full throttle")
	f.model.throttle = 0.0
	f._mix_audio(0.1)
	check(float(f.sounds._levels["engine"]) == 0.0, "and goes quiet when cut")
	f.queue_free()
	await process_frame
	print("DONE fails=", fails)
	quit(1 if fails > 0 else 0)
func _key(code: int, down: bool) -> InputEventKey:
	var k := InputEventKey.new()
	k.keycode = code
	k.physical_keycode = code
	k.pressed = down
	return k
