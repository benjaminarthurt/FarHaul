extends SceneTree
# Boots the start-up flow: assets exist, the title screen builds, buttons behave, and START
# hands over to the builder. Uses a throwaway user dir via FARHAUL_NOSAVE so no real save is touched.

var ok := true

func check(cond: bool, label: String) -> void:
	print(("  ok    " if cond else "  FAIL  "), label)
	if not cond:
		ok = false

func _initialize() -> void:
	print("assets")
	for p in [Brand.LOGO, Brand.WORDMARK, Brand.SPLASH, Brand.INTRO_VIDEO, "res://assets/brand/icon.png"]:
		check(ResourceLoader.exists(p), p)
	check(load(Brand.INTRO_VIDEO) is VideoStream, "intro video loads as a VideoStream")
	check(ProjectSettings.get_setting("application/config/name") == "Far Haul", "project is named Far Haul")
	check(Brand.container_code(5) == Brand.container_code(5), "container codes are stable")
	check(Brand.container_code(5).begins_with("FHCU "), "container code prefix")
	var boot: Node = load("res://scenes/boot.tscn").instantiate()
	root.add_child(boot)
	process_frame.connect(_run.bind(boot), CONNECT_ONE_SHOT)

func _run(boot: Node) -> void:
	print("flow")
	check(boot.stage == 0, "starts on the splash")
	boot._enter_intro()
	check(boot.stage == 1 and boot.player.is_playing(), "intro video plays")
	boot._unhandled_input(_key())
	check(boot.stage == 2 and not boot.player.is_playing(), "any key skips the intro to the title screen")
	check(boot.title_layer.visible and boot.world.visible, "title screen is showing")
	check(boot.continue_btn.disabled == not FileAccess.file_exists(boot.AUTOSAVE), "continue only enabled with a save")
	boot._start_game()
	await create_timer(0.8).timeout
	check(current_scene != null and current_scene.name != "Boot", "START hands over to the game scene")
	print("OK" if ok else "FAILED")
	quit(0 if ok else 1)

func _key() -> InputEventKey:
	var e := InputEventKey.new()
	e.pressed = true
	e.keycode = KEY_SPACE
	return e
