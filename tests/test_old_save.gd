extends SceneTree
## A game saved before ports, people, the suit and surface work (no standing, kit, missions, finds
## counters, hull damage or hints in its profile) still loads and plays: the port, every desk, the
## hints, the helm, the moon and the suit all work from defaults.
## Run: godot --headless --path . --script res://tests/test_old_save.gd
var fails := 0
func check(ok: bool, msg: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + msg)
	if not ok:
		fails += 1
func _initialize() -> void:
	SaveSlots.dir = "user://test_saves_old"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SaveSlots.dir))
	process_frame.connect(_run, CONNECT_ONE_SHOT)
func _run() -> void:
	Session.begin_new(1, "Old Hand", "human", "normal", "roosevelt_independent_yards")
	var data := SaveSlots.read(1)
	var p: Dictionary = data["profile"]
	for k in ["rep", "gear", "mission", "missions_taken", "unloading", "hull_damage", "samples", "salvage", "ice", "rare",
			"finds_taken", "hints_seen", "local_taken"]:
		p.erase(k)
	data["profile"] = p
	data.erase("active_contract")
	SaveSlots.write(1, data)
	check(Session.load_slot(1), "the old save loads")
	check(not Session.profile.has("rep") and not Session.profile.has("gear"), "with none of the new fields")
	var place: Node = load(Session.PLACE_SCENE).instantiate()
	root.add_child(place)
	await process_frame
	check(place.kind == "concourse" and place.desks.size() >= 6, "the concourse opens")
	check(place.hint_box != null, "a new hint welcomes the returning captain")
	for d in ["freight", "fuel", "yard", "bar", "gate"]:
		place.use_desk(d)
		await process_frame
		check(place.panel.visible, "the %s desk opens" % d)
		place.close_desk()
	place.queue_free()
	await process_frame
	check(Session.repair_cost() == 0 and Session.gear_owned().is_empty() and int(Session.finds_aboard().value) == 0, "repairs, kit and finds read as none")
	check(People.standing(int(Session.profile.get("rep", 0))) == "Unknown", "standing starts at Unknown")
	# The moon, in the suit.
	var d2 := SaveSlots.read(1)
	var ship := ShipData.new(ModuleLibrary.new())
	ShipPresets.build(ship, ShipPresets.STARTER_LANDER)
	d2["modules"] = (JSON.parse_string(ship.to_json()) as Dictionary)["modules"]
	d2["cargo"] = CargoManifest.new(ship).to_dict()
	SaveSlots.write(1, d2)
	Session.profile["port_id"] = Session.system_id() + LocalSpace.SEP + "pad"
	Session.save_profile()
	place = load(Session.PLACE_SCENE).instantiate()
	root.add_child(place)
	await process_frame
	for d in ["dispatch", "lab", "store", "fuel", "gate"]:
		place.use_desk(d)
		await process_frame
		check(place.panel.visible, "the hab's %s desk opens" % d)
		place.close_desk()
	place.queue_free()
	await process_frame
	Session.flight_job = {}
	Session.suit_up = true
	var f: Node = load(Session.FLIGHT_SCENE).instantiate()
	root.add_child(f)
	await process_frame
	await process_frame
	check(f.outside and f.ops != null and f.ops.o2_max == 900.0, "outside in a plain suit")
	f._process(0.05)
	f.queue_free()
	await process_frame
	print("DONE fails=", fails)
	quit(1 if fails > 0 else 0)
