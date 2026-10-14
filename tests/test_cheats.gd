extends SceneTree
## Debug cheats (Cheats): off by default; when on, the pause menu offers a million credits and a full
## repair and resupply in any scene of a saved game; the money stays on the economy's books; using one
## marks the save.
## Run: godot --headless --path . --script res://tests/test_cheats.gd
var fails := 0
func check(ok: bool, msg: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + msg)
	if not ok:
		fails += 1
func _initialize() -> void:
	SaveSlots.dir = "user://test_saves_cheats_%d" % OS.get_process_id()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SaveSlots.dir))
	process_frame.connect(_run, CONNECT_ONE_SHOT)


func _menu_cheats(scene: Node) -> int:
	var m: GameMenu = scene.get_node("GameMenu")
	m.open()
	var n := 0
	for c in m.extra.get_children():
		if c is Button and (String(c.text).begins_with("+") or String(c.text).begins_with("REPAIR")):
			n += 1
	m.close()
	return n


func _run() -> void:
	check(GameSettings.DEFAULTS.cheats == false, "cheats are off by default")
	Session.begin_new(2, "Tester", "human", "normal", "roosevelt_independent_yards")
	Session.flight_job = {}
	var f: Node = load(Session.FLIGHT_SCENE).instantiate()
	root.add_child(f)
	current_scene = f
	GameMenu.attach(f)
	await process_frame
	check(_menu_cheats(f) == 0, "switched off, the pause menu has none")
	GameSettings.set_value("cheats", true)
	check(_menu_cheats(f) == 2, "switched on, it offers money and repairs")
	f.model.damage = 0.7
	f.model.fuel_t = 0.5
	f.model.overheated = true
	f.wear["5:engine"] = 1.0
	var msg := Cheats.run(f, "fix")
	check(f.model.damage == 0.0 and f.model.fuel_t > 5.0 and not f.model.overheated and f.wear.is_empty() and f.model.thrust_kn > 0.0, "in flight: hull, parts, tanks and heat put right: %s" % msg)
	check(Session.patch_kits() == Session.patch_kit_max() and bool(Session.profile.get("cheated", false)), "kit lockers full, and the save is marked")
	var cr := int(Session.profile.credits)
	msg = Cheats.run(f, "credits")
	check(int(Session.profile.credits) == cr + Cheats.MONEY, "a million credits: %s" % msg)
	check(absf(float(Session.sim.summary()["cash_error"])) < 0.01 and float(Session.sim.carriers[SimWorld.PLAYER].revenue) == 0.0, "on the economy's books, not counted as freight pay")
	f.queue_free()
	await process_frame
	Session.profile["location"] = "shipyard"
	Session.save_profile()
	var y: Node = load(Session.YARD_SCENE).instantiate()
	root.add_child(y)
	current_scene = y
	await process_frame
	await process_frame
	var before: int = y._credits()
	msg = Cheats.run(y, "credits")
	check(y._credits() == before + Cheats.MONEY, "in the shipyard the builder can spend it at once: %s" % msg)
	y.queue_free()
	await process_frame
	check(int(SaveSlots.read(Session.slot).profile.credits) == before + Cheats.MONEY, "and it's saved")
	GameSettings.set_value("cheats", false)
	print("DONE fails=", fails)
	quit(1 if fails > 0 else 0)
