extends SceneTree
## Fitting salvaged parts (Builder, Salvage.fit_fee, ShipData.paid): parts in the hold show in the
## shipyard's palette; fitting one costs the fitting fee, keeps its wear and takes it out of the hold;
## undo puts it all back; unbolting returns it to the hold and the fee to you. Wear follows a part when
## others come off. A failed FTL drive doesn't jump until it's fixed, and jumps wear the drive.
## Run: godot --headless --path . --script res://tests/test_fit_salvage.gd
var fails := 0
func check(ok: bool, msg: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + msg)
	if not ok:
		fails += 1


func _initialize() -> void:
	SaveSlots.dir = "user://test_saves_fit_%d" % OS.get_process_id()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SaveSlots.dir))
	process_frame.connect(_run, CONNECT_ONE_SHOT)


## Somewhere on the outside of the ship that `id` fits.
func _spot(b: Node, id: StringName) -> Array:
	for x in range(-3, 4):
		for z in range(-3, 6):
			for r in 4:
				var c := Vector3i(x, 0, z)
				if b.ship.check_place(id, c, r) == "":
					return [c, r]
	return []


func _place(b: Node, id: StringName) -> String:
	var at := _spot(b, id)
	if at.is_empty():
		return "nowhere to put it"
	b.hover_active = true
	b.hover_cell = at[0]
	b.hover_rot = at[1]
	b.hover_error = ""
	b._on_click()
	return b.message


func _shift(on: bool) -> void:
	var k := InputEventKey.new()
	k.keycode = KEY_SHIFT
	k.physical_keycode = KEY_SHIFT
	k.pressed = on
	Input.parse_input_event(k)
	Input.flush_buffered_events()


func _run() -> void:
	Session.begin_new(1, "Tester", "human", "normal", "roosevelt_independent_yards")
	var lib := ModuleLibrary.new()
	print("the fee")
	var engine := {"kind": "part", "module": "engine", "tonnes": lib.get_def(&"engine").mass, "condition": 0.62, "failed": false}
	var drive := {"kind": "part", "module": "jump_drive", "tonnes": lib.get_def(&"jump_drive").mass, "condition": 0.08, "failed": true}
	check(Salvage.fit_fee(engine) == roundi(lib.get_def(&"engine").cost * 0.15) and Salvage.fit_fee(engine) < Salvage.part_value(engine), "fitting an engine costs %s cr (it'd sell for %s, and costs %s new)" % [ShipStats.commas(Salvage.fit_fee(engine)), ShipStats.commas(Salvage.part_value(engine)), ShipStats.commas(lib.get_def(&"engine").cost)])
	check(Salvage.wear_of(engine) > 0.37 and Salvage.wear_of(engine) < 0.39 and Salvage.wear_of(drive) == 1.0, "it keeps its wear; a failed one is failed")
	check(bool(Salvage.stow(engine).ok) and bool(Salvage.stow(drive).ok), "an engine and a dead drive in the hold")

	print("in the shipyard")
	Session.profile["location"] = "shipyard"
	Session.save_profile()
	var b: Node = load(Session.YARD_SCENE).instantiate()
	root.add_child(b)
	current_scene = b
	await process_frame
	await process_frame
	check(b._salvage_parts().size() == 2 and b.salvage_buttons.size() == 2, "the palette lists both: %s" % ", ".join(b.salvage_buttons.map(func(x): return x.text)))
	var credits0: int = b._credits()
	var hw0: float = b.manifest.total_of(Salvage.HARDWARE)
	var n0: int = b.ship.modules.size()
	b._select_salvage(0)
	check(b.salvage_pick == 0 and not b._picked_part().is_empty(), "pick the engine")
	var msg := _place(b, &"engine")
	var m: Dictionary = b.ship.modules.back()
	check(b.ship.modules.size() == n0 + 1 and m.id == &"engine" and int(m.get("paid", -1)) == Salvage.fit_fee(engine), "fitted: %s" % msg)
	check(b._credits() == credits0 - Salvage.fit_fee(engine), "it cost the fee, not the price (%s cr)" % ShipStats.commas(credits0 - b._credits()))
	check(absf(float(m.get("wear", 0.0)) - 0.38) < 0.01, "and it's as worn as it was")
	check(b._salvage_parts().size() == 1 and absf(b.manifest.total_of(Salvage.HARDWARE) - (hw0 - float(engine.tonnes))) < 0.01, "out of the hold")
	check(b.salvage_pick == -1, "the palette goes back to buying new")
	b._undo()
	check(b.ship.modules.size() == n0 and b._credits() == credits0 and b._salvage_parts().size() == 2 and absf(b.manifest.total_of(Salvage.HARDWARE) - hw0) < 0.01, "undo: back in the hold, fee back")
	b._redo()
	check(b.ship.modules.size() == n0 + 1 and b._salvage_parts().size() == 1 and int(b.ship.modules.back().get("paid", -1)) > 0, "redo: fitted again")

	print("unbolting it")
	var cell: Vector3i = b.ship.modules.back().cell
	b.hover_active = true
	b.hover_cell = cell
	_shift(true)
	check(Input.is_key_pressed(KEY_SHIFT), "(shift held)")
	b._on_click()
	_shift(false)
	check(b.ship.modules.size() == n0 and b._credits() == credits0, "unbolted, and the fitting fee comes back: %s" % b.message)
	var back: Array = b._salvage_parts().filter(func(p): return String(p.module) == "engine")
	check(back.size() == 1 and absf(float(back[0].condition) - 0.62) < 0.011, "back in the hold at %s" % Salvage.condition_text(back[0]) if not back.is_empty() else "back in the hold")

	print("a dead drive")
	b._select_salvage(b._salvage_parts().find(b._salvage_parts().filter(func(p): return String(p.module) == "jump_drive")[0]))
	msg = _place(b, &"jump_drive")
	check(b.ship.modules.back().id == &"jump_drive" and msg.contains("doesn't work yet"), "fitted: %s" % msg)
	check(not bool(Session.ship_stats(b.ship).ftl), "but the ship still can't jump")
	check(Session.ship_stats(b.ship).warnings.any(func(w): return String(w).contains("FTL drive failed")), "and says why")
	b._leave()
	await process_frame
	await process_frame
	var data := SaveSlots.read(Session.slot)
	var loaded := Session._load_ship(data)
	var di := -1
	for i in (loaded.ship as ShipData).modules.size():
		if (loaded.ship as ShipData).modules[i].id == &"jump_drive":
			di = i
	check(di >= 0 and int((loaded.ship as ShipData).modules[di].get("paid", -1)) == Salvage.fit_fee(drive), "the save remembers what it cost to fit")
	check(float(Session.wear().get(Wear.key(di, &"jump_drive"), 0.0)) >= 1.0, "and that it's failed")
	check(Session.ship_cost(loaded.ship, lib) < Session.ship_cost(loaded.ship, lib) + lib.get_def(&"jump_drive").cost - Salvage.fit_fee(drive) and \
			Session.ship_cost(loaded.ship, lib) == ShipStats.compute(loaded.ship).cost, "the ship's value counts the fee, not the price")
	SimWorld.sync(Session.sim, Session.profile, loaded.ship)
	check(not bool(SimWorld.player(Session.sim).ftl), "the economy agrees: no interstellar freight")
	var w := Session.wear().duplicate()
	w[Wear.key(di, &"jump_drive")] = Wear.eva_fixed(1.0)   # a spares kit on a space walk
	Session.profile["wear"] = w
	check(bool(Session.ship_stats(loaded.ship).ftl), "a spares kit later, it jumps")
	SimWorld.sync(Session.sim, Session.profile, loaded.ship)
	check(bool(SimWorld.player(Session.sim).ftl), "and the boards open up")
	var before := float(Session.wear()[Wear.key(di, &"jump_drive")])
	Session._autopilot_wear(loaded.ship, 0.03, 0.02, 0.02)
	check(float(Session.wear()[Wear.key(di, &"jump_drive")]) > before, "jumping wears the drive")
	check(Wear.parts(loaded.ship, Session.wear()).any(func(p): return String(p.kind) == "drive" and String(p.name) == "FTL drive"), "it's a working part like the others: serviced, overhauled, worn")

	print("wear follows the part")
	Session.profile["location"] = "shipyard"
	Session.save_profile()
	b = load(Session.YARD_SCENE).instantiate()
	root.add_child(b)
	current_scene = b
	await process_frame
	await process_frame
	var drive_wear := float(Session.wear()[Wear.key(di, &"jump_drive")])
	var idx := -1
	for i in b.ship.modules.size():
		if b.ship.modules[i].id == &"radiator" and i < di:
			idx = i
	if idx >= 0:
		b.hover_active = true
		b.hover_cell = b.ship.modules[idx].cell
		_shift(true)
		b._on_click()
		_shift(false)
		b._save()
		var nd := -1
		for i in b.ship.modules.size():
			if b.ship.modules[i].id == &"jump_drive":
				nd = i
		check(nd == di - 1 and absf(float(Session.wear().get(Wear.key(nd, &"jump_drive"), 0.0)) - drive_wear) < 0.001, "a radiator ahead of it came off; the drive is still %d%% (now part %d)" % [Wear.condition(drive_wear), nd])
	else:
		check(true, "(no radiator ahead of the drive to remove)")
	b.queue_free()
	print("DONE fails=", fails)
	quit(1 if fails > 0 else 0)
