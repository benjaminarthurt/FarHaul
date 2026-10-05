extends SceneTree
## The in-game menu (F10, or Esc in a port) pauses and resumes, saves, opens settings; F3 shows the
## frame-rate readout; the title screen has no menu. One-time hints show once each, when they fit.
## Run: godot --headless --path . --script res://tests/test_game_menu.gd
var fails := 0
func check(ok: bool, msg: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + msg)
	if not ok:
		fails += 1
func _initialize() -> void:
	SaveSlots.dir = "user://test_saves_menu"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SaveSlots.dir))
	process_frame.connect(_run, CONNECT_ONE_SHOT)
func _key(code: int) -> InputEventKey:
	var k := InputEventKey.new()
	k.keycode = code
	k.pressed = true
	return k
func _run() -> void:
	Session.begin_new(2, "Pilot", "human", "normal", "roosevelt_independent_yards")
	var p: Node = load(Session.PLACE_SCENE).instantiate()
	root.add_child(p)
	await process_frame
	var m: GameMenu = p.get_node_or_null("GameMenu")
	check(m != null, "the port has the menu")
	check(p.hint_box != null and "FREIGHT OFFICE" in (p.hint_box.get_child(0) as Label).text, "a first hint points to the freight office")
	p._unhandled_input(_key(KEY_ESCAPE))
	check(m.is_open() and paused, "Esc in the port opens the menu and pauses")
	m._unhandled_input(_key(KEY_ESCAPE))
	check(not m.is_open() and not paused, "Esc again resumes")
	m._unhandled_input(_key(GameMenu.KEY))
	check(m.is_open() and paused, "F10 opens it too")
	m._save()
	check("Saved" in m.note.text, "save from the menu: %s" % m.note.text)
	m._settings()
	check(m.settings.visible and not m.panel.visible, "settings open from the menu")
	m.settings.back.emit()
	check(m.panel.visible, "and come back to it")
	m.close()
	check(not paused, "closed and running")
	m._unhandled_input(_key(GameMenu.PERF_KEY))
	await process_frame
	m._process(1.0)
	check(m.perf.visible and "FPS" in m.perf.text, "F3 shows the frame rate: %s" % m.perf.text.split("\n")[0])
	m._unhandled_input(_key(GameMenu.PERF_KEY))
	check(not m.perf.visible, "and F3 hides it")
	p.queue_free()
	await process_frame
	# Hints: once each, when they fit.
	p = load(Session.PLACE_SCENE).instantiate()
	root.add_child(p)
	await process_frame
	check(p.hint_box == null, "the welcome is not shown twice")
	p.queue_free()
	await process_frame
	Session.accept_contract(Contracts.offers_from(Session.system_id())[0])
	p = load(Session.PLACE_SCENE).instantiate()
	root.add_child(p)
	await process_frame
	check(p.hint_box != null and "load aboard" in (p.hint_box.get_child(0) as Label).text, "holding a job, the next hint says how to fly it")
	p.queue_free()
	await process_frame
	# Flight has the menu; the title has none.
	Session.flight_job = {}
	var f: Node = load(Session.FLIGHT_SCENE).instantiate()
	root.add_child(f)
	await process_frame
	var fm: GameMenu = f.get_node_or_null("GameMenu")
	check(fm != null and fm.in_flight, "flight has the menu")
	fm.open()
	check("not saved" in fm.note.text, "and says a flight in progress is not saved")
	fm.close()
	f.queue_free()
	await process_frame
	var b: Node = load(Session.BOOT_SCENE).instantiate()
	root.add_child(b)
	await process_frame
	check(b.get_node_or_null("GameMenu") == null, "the title screen has no in-game menu")
	b.queue_free()
	await process_frame
	print("DONE fails=", fails)
	quit(1 if fails > 0 else 0)
