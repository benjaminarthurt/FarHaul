extends SceneTree
## Manufacturers (PartMakers): each maker's version of a part, its numbers, where it's cheaper, how fast
## it wears; buying one at a yard; makers' parts turning up on wrecks.
## Run: godot --headless --path . --script res://tests/test_part_makers.gd
var fails := 0
func check(ok: bool, msg: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + msg)
	if not ok:
		fails += 1


func _initialize() -> void:
	SaveSlots.dir = "user://test_saves_makers_%d" % OS.get_process_id()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SaveSlots.dir))
	process_frame.connect(_run, CONNECT_ONE_SHOT)


func _run() -> void:
	print("the catalogue")
	var lib := ModuleLibrary.new()
	var vs := PartMakers.versions(lib, &"engine")
	check(vs.size() == 4, "four other makers' engines: %s" % ", ".join(vs.map(func(v): return lib.get_def(v).display_name)))
	var at := lib.order.find(&"engine")
	check(lib.order[at + 1] == vs[0] and lib.get_def(lib.order[at + 1]).base == &"engine", "listed right under the engine")
	check(lib.order.slice(0, 10).all(func(id): return lib.get_def(id).base == &""), "the number keys still pick the same parts")
	check(lib.get_def(&"engine").maker == &"northstar_commercial" and lib.get_def(&"corridor").maker == &"", "the yards' own parts are Northstar's; hull isn't branded")
	var vw := lib.get_def(&"engine__ilyan_vector_works")
	check(is_equal_approx(vw.thrust, 96.0) and is_equal_approx(vw.mass, 2.4) and is_equal_approx(vw.heat, 32.5) and vw.cost == 32000 and is_equal_approx(vw.wear_mult, 1.4),
			"Vector Works: %.0f kN, %.1f t, %.1f kW of heat, %d cr, wears %.1fx" % [vw.thrust, vw.mass, vw.heat, vw.cost, vw.wear_mult])
	check(is_equal_approx(lib.get_def(&"radiator__orun_thermal_collective").heat, -84.0), "Orun Thermal's radiator sheds 84 kW (60 standard)")
	check(is_equal_approx(lib.get_def(&"jump_drive__ilyan_vector_works").drive, 0.40), "Vector Works' drive is faster")
	check(is_equal_approx(lib.get_def(&"tank__roosevelt_modular").fuel, 12.0), "Roosevelt's tank holds 12 t")
	check(lib.get_def(&"engine__kesh_heavy_systems").sockets.size() == lib.get_def(&"engine").sockets.size(), "and they mount like the part they're a version of")

	print("prices")
	check(PartMakers.price(vw, "ilos") == 27200 and PartMakers.price(vw, "sol") == 35200, "cheaper at home in Ilos (27,200), duty elsewhere (35,200)")
	check(PartMakers.price(lib.get_def(&"engine"), "keshar") == 20000, "Northstar's at list price everywhere")

	print("wear")
	var ship := ShipData.new(lib)
	ShipPresets.build(ship)
	var ei := -1
	for i in ship.modules.size():
		if ship.modules[i].id == &"engine":
			ei = i
	ship.modules[ei].id = &"engine__kesh_heavy_systems"
	var w := {}
	Wear.add(w, ship, "engine", 0.1)
	check(absf(float(w.get(Wear.key(ei, &"engine__kesh_heavy_systems"), 0.0)) - 0.04) < 0.0001, "a Kesh Heavy engine wears at 40%% of the rate (%.3f for 0.1)" % float(w.get(Wear.key(ei, &"engine__kesh_heavy_systems"), 0.0)))
	check(Wear.parts(ship, w).any(func(p): return String(p.kind) == "engine"), "and it's still an engine to the crew and the space walk")

	print("buying one")
	Session.begin_new(1, "Tester", "human", "normal", "roosevelt_independent_yards")
	Session.profile["location"] = "shipyard"
	Session.save_profile()
	var b: Node = load(Session.YARD_SCENE).instantiate()
	root.add_child(b)
	current_scene = b
	await process_frame
	await process_frame
	check(Session.system_id() == "new_houston", "at the New Houston yards, home of Roosevelt Modular")
	var tank_id := &"tank__roosevelt_modular"
	var price := PartMakers.price(lib.get_def(tank_id), "new_houston")
	check(price < lib.get_def(tank_id).cost, "their tank's cheaper here: %s cr against %s list" % [ShipStats.commas(price), ShipStats.commas(lib.get_def(tank_id).cost)])
	var credits: int = b._credits()
	b._select(b.library.order.find(tank_id))
	var placed := false
	for x in range(-3, 4):
		for z in range(-3, 6):
			for r in 4:
				if not placed and b.ship.check_place(tank_id, Vector3i(x, 0, z), r) == "":
					b.hover_active = true
					b.hover_cell = Vector3i(x, 0, z)
					b.hover_rot = r
					b.hover_error = ""
					b._on_click()
					placed = true
	var m: Dictionary = b.ship.modules.back()
	check(placed and m.id == tank_id and int(m.get("paid", -1)) == price and String(m.get("src", "")) == "yard", "bought for %s cr" % ShipStats.commas(int(m.get("paid", -1))))
	check(b._credits() == credits - price, "and that's what it cost")
	check(b._room_to_unbolt(m) == "" and String(m.src) != "salvage", "it's not salvage")
	b._save()
	var loaded := Session._load_ship(SaveSlots.read(Session.slot))
	var back: Dictionary = (loaded.ship as ShipData).modules.back()
	check(back.id == tank_id and int(back.paid) == price and String(back.src) == "yard", "saved as bought")
	check(is_equal_approx(float(ShipStats.compute(loaded.ship).fuel), 10.0 + 12.0), "and it holds 12 t more fuel")
	b._undo()
	check(b._credits() == credits, "undo: the money's back")
	b.queue_free()

	print("legacy saves and wrecks")
	var starter := ShipData.new(lib)
	ShipPresets.build(starter)
	var js: Dictionary = JSON.parse_string(starter.to_json())
	var ek := -1
	for i in (js.modules as Array).size():
		if String(js.modules[i].id) == "engine":
			ek = i
			js.modules[i]["paid"] = 3000   # how 0.12 saved a fitted salvage engine: no "src"
	var old := ShipData.new(lib)
	check(old.from_json(JSON.stringify(js)), "a 0.12 save with a fitted salvage engine loads")
	check(ek >= 0 and String(old.modules[ek].get("src", "")) == "salvage", "and its engine is still salvage")
	var makes := {}
	for k in 60:
		var r := RandomNumberGenerator.new()
		r.seed = k
		for it in Salvage.roll(ShipPresets.NPC_HAULER, r, k % 3 == 0):
			if String(it.kind) == "part":
				makes[String(lib.get_def(StringName(String(it.module))).maker)] = true
	check(makes.size() >= 3, "wrecks carry several makers' parts: %s" % ", ".join(makes.keys()))
	print("telling them apart")
	var tg := PartMakers.tags(lib, vw)
	check(tg.contains("+20% thrust") and tg.contains("−20% mass") and tg.contains("hot") and tg.contains("wears fast"), "a make's row says how it differs: %s" % tg)
	check(PartMakers.tags(lib, lib.get_def(&"engine")) == "" and not PartMakers.tags(lib, lib.get_def(&"radiator__orun_thermal_collective")).contains("-"), "nothing on the standard part; real minus signs on the rest")
	check(lib.order.all(func(id): return lib.get_def(id).base == &"" or PartMakers.tags(lib, lib.get_def(id)) != ""), "every make has something to say for itself")
	var fam := PartMakers.family(lib, vw)
	check(fam.size() >= 3 and fam[0] == &"engine" and fam.has(vw.id) and PartMakers.family(lib, lib.get_def(&"engine")) == fam, "the engine's family: %s" % ", ".join(fam))
	var list := func(d: ModuleDef) -> int: return d.cost
	var rs := PartCompare.rows(lib, vw, list)
	var bs := PartCompare.best(rs)
	var top: Dictionary = rs.reduce(func(a, r): return r if float(r.head) > float(a.head) else a)
	var light: Dictionary = rs.reduce(func(a, r): return r if float(r.mass) < float(a.mass) else a)
	check(is_equal_approx(float(bs.head), float(top.head)) and is_equal_approx(float(bs.mass), float(light.mass)), "best thrust %s (%.0f kN), lightest %s (%.1f t)" % [top.make, top.head, light.make, light.mass])
	check(rs.all(func(r): return String(r.home) != ""), "and each says where it's cheapest: %s" % ", ".join(rs.map(func(r): return "%s %s" % [r.make, r.home])))
	var sh := ShipData.new(lib)
	ShipPresets.build(sh)
	var st := ShipStats.compute(sh, 1.0)
	var fx := PartCompare.effect(st, vw)
	var tw: Array = fx.filter(func(e): return String(e.label) == "T/W")
	var want := (float(st.thrust_fwd) + vw.thrust) / ((float(st.wet) + vw.mass) * ShipStats.G)
	check(tw.size() == 1 and String(tw[0].now) == "%.2f" % want and bool(tw[0].good), "another engine: T/W %s → %s" % [tw[0].was if not tw.is_empty() else "?", tw[0].now if not tw.is_empty() else "?"])
	var hot := lib.get_def(&"engine__gateworks")
	var cool: Dictionary = st.duplicate()
	cool["cooling"] = float(st.heat_gen) + 1.0
	var hx: Array = PartCompare.effect(cool, hot).filter(func(e): return String(e.label) == "Heat")
	check(hx.size() == 1 and bool(hx[0].bad), "and one that would overheat it says so: heat %s → %s" % [hx[0].was if not hx.is_empty() else "?", hx[0].now if not hx.is_empty() else "?"])
	var rad: Array = PartCompare.effect(st, lib.get_def(&"radiator")).filter(func(e): return String(e.label) == "Heat")
	check(rad.size() == 1 and String(rad[0].now).begins_with("%.0f/%.0f" % [float(st.heat_gen), float(st.cooling) - lib.get_def(&"radiator").heat]), "a radiator adds cooling: %s" % (rad[0].now if not rad.is_empty() else "?"))
	var card := PartCompare.card(lib, vw, st, list)
	check(card.contains("[table=") and card.contains("Fit one") and card.contains(PartCompare.BEST), "the card: a table, the best picked out, and what fitting one does")
	check(not PartCompare.card(lib, lib.get_def(&"corridor"), st, list).contains("[table="), "a part only one yard makes gets no table")

	print("DONE fails=", fails)
	quit(1 if fails > 0 else 0)
