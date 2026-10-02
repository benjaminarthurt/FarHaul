extends SceneTree
# Boots the real builder scene and plays a full loop through the same calls the UI makes.

var ok := true

func check(cond: bool, label: String) -> void:
	print(("  ok    " if cond else "  FAIL  "), label)
	if not cond:
		ok = false

func _initialize() -> void:
	var scene: Node3D = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	process_frame.connect(_run.bind(scene), CONNECT_ONE_SHOT)

func _run(scene: Node3D) -> void:
	print("start state")
	check(scene.ship.modules.size() == 10, "starter ship is loaded on a fresh start")
	check(scene.welcome_panel.visible, "welcome panel shows on first run")
	check(scene.last_stats.warnings.size() == 0, "starter has no warnings")

	print("placement")
	var before_n: int = scene.ship.modules.size()
	scene._select(scene.library.order.find(&"radiator"))
	scene.hover_active = true
	scene.hover_cell = Vector3i(-1, 0, 0)
	scene.hover_rot = scene._fit_rotation(&"radiator", scene.hover_cell)
	scene.hover_error = scene.ship.check_place(&"radiator", scene.hover_cell, scene.hover_rot)
	check(scene.hover_error == "", "radiator fits on the cockpit's west side (auto-rotated from rot %d to %d)" % [scene.rot, scene.hover_rot])
	check(scene.hover_rot == 2, "auto-rotation picked a turn that fits")
	scene._on_click()
	check(scene.ship.modules.size() == before_n + 1, "click places the module")
	check(scene.history.can_undo(), "placing is undoable")
	scene._undo()
	check(scene.ship.modules.size() == before_n, "undo removes it")
	scene._redo()
	check(scene.ship.modules.size() == before_n + 1, "redo puts it back")
	scene._undo()

	print("cargo preview")
	scene.commodity_pick.select(0)
	scene.amount_box.value = 20
	scene._load_cargo()
	check(scene.manifest.total() > 0.0, "loading cargo puts freight aboard")
	scene._unload_cargo()
	scene._load_cargo()
	scene._unload_all()
	check(is_equal_approx(scene.manifest.total(), 0.0), "unload all empties the hold")
	scene._load_cargo()

	print("save and resume")
	scene.autosave_enabled = false
	scene._save()
	scene._clear()
	check(scene.ship.modules.is_empty(), "cleared")
	scene._load()
	check(scene.ship.modules.size() == before_n and scene.manifest.total() > 0.0, "loaded ship and cargo")

	print(scene.stats_label.text)
	print("SMOKE ", "PASSED" if ok else "FAILED")
	quit(0 if ok else 1)
