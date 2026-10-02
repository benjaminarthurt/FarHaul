extends SceneTree
# Boots the start-up flow: assets exist, the title screen builds, buttons behave, and START
# hands over to the builder. Uses a throwaway user dir via FARHAUL_NOSAVE so no real save is touched.

var ok := true

func check(cond: bool, label: String) -> void:
	print(("  ok    " if cond else "  FAIL  "), label)
	if not cond:
		ok = false

func _initialize() -> void:
	SaveSlots.dir = "user://test_saves_boot"
	for f in DirAccess.get_files_at(SaveSlots.dir):
		DirAccess.remove_absolute(SaveSlots.dir + "/" + f)
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
	check(boot.continue_btn.disabled == (SaveSlots.latest() < 0), "continue only enabled with a save")
	boot._on_new()
	check(boot.new_panel.visible and not boot.load_panel.visible, "NEW GAME opens the new game panel")
	boot._on_load()
	check(boot.load_panel.visible and not boot.new_panel.visible, "LOAD GAME opens the load panel")
	boot._on_settings()
	check(boot.settings_panel.visible, "SETTINGS opens the settings panel")
	boot._show_menu()
	check(not boot.settings_panel.visible and boot.menu_box.visible, "back returns to the menu")
	check(Session.begin_new(4, "Test Pilot", "belter", "hard", "marrow"), "new game writes slot 5")
	check(Session.scene_path() == Session.DOCK_SCENE, "a new game starts at the dock")
	boot._enter_game()
	await create_timer(0.9).timeout
	check(current_scene != null and current_scene.name == "Dock", "starting a game opens the dock")
	print("OK" if ok else "FAILED")
	quit(0 if ok else 1)

func _key() -> InputEventKey:
	var e := InputEventKey.new()
	e.pressed = true
	e.keycode = KEY_SPACE
	return e
