extends SceneTree
## The dock's freight board and fly-empty list open on screen (they used to be pushed below the window by
## the menu). Run: godot --headless --path . --script res://tests/smoke_dock.gd
var fails := 0
func check(ok: bool, msg: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + msg)
	if not ok:
		fails += 1
func _initialize() -> void:
	SaveSlots.dir = "user://test_saves_dock"
	process_frame.connect(_run, CONNECT_ONE_SHOT)
func _run() -> void:
	Session.begin_new(3, "Ren", "human", "normal", "roosevelt_independent_yards")
	var d: Node = load("res://scenes/dock.tscn").instantiate()
	root.add_child(d)
	await process_frame
	await process_frame
	var vp := root.get_viewport().get_visible_rect()
	d._show_contracts()
	await process_frame
	await process_frame
	var jobs := 0
	for c in d.contract_list.get_children():
		if c is Button:
			jobs += 1
	check(d.side.visible and d.contract_panel.visible and jobs > 0, "the board opens with %d jobs" % jobs)
	check(vp.encloses(d.side.get_global_rect()), "the board is on screen (%s in %s)" % [d.side.get_global_rect(), vp])
	check(not d.card.visible, "the system card steps aside")
	var first: Control = d.contract_list.get_child(d.contract_list.get_child_count() - jobs)
	check(vp.has_point(first.get_global_rect().get_center()), "the first job can be clicked (%s)" % first.get_global_rect())
	d._show_destinations()
	await process_frame
	check(d.fly_panel.visible and not d.contract_panel.visible and vp.encloses(d.side.get_global_rect()), "fly empty replaces the board, on screen")
	d._show_destinations()
	await process_frame
	check(not d.side.visible and d.card.visible, "closing it brings the card back")
	print("DONE fails=", fails)
	quit(1 if fails > 0 else 0)
