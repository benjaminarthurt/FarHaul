extends SceneTree
# Save slots, new-game setup, resuming where you left off, and the ship builder inside a game.
# Uses a throwaway save folder so no real save is touched.

var ok := true

func check(cond: bool, label: String) -> void:
	print(("  ok    " if cond else "  FAIL  "), label)
	if not cond:
		ok = false

func _initialize() -> void:
	SaveSlots.dir = "user://test_saves_menus"
	for f in DirAccess.get_files_at(SaveSlots.dir):  # leftovers from earlier runs of this test only
		DirAccess.remove_absolute(SaveSlots.dir + "/" + f)
	process_frame.connect(_run, CONNECT_ONE_SHOT)

func _run() -> void:
	print("slots")
	check(SaveSlots.COUNT == 5, "five slots")
	check(SaveSlots.latest() == -1 and SaveSlots.first_empty() == 0, "all slots start empty")
	check(Worlds.species_list().size() == 5 and Worlds.start_ids("kesh").size() == 4 and Worlds.DIFFICULTIES.size() == 3, "species, starting systems and difficulties are defined")
	check(Worlds.starting_yards().size() >= 3 and Worlds.RACES.size() == 5, "yards and races are defined")
	check(Worlds.distance_ly("sol", "new_houston") > 0.0, "known systems have usable coordinates")
	check(not Worlds.market("talos").is_empty() and Worlds.commodity("grain").base_value > 0, "markets and commodities load from data")
	check(not Worlds.primary_port("new_houston").is_empty(), "ports load for known systems")
	check(Contracts.offers_from("new_houston").size() > 0, "market and route data generate freight offers")

	print("new game")
	check(Session.begin_new(2, "Mara Voss", "kesh", "hard", "new_houston"), "begin a new game in slot 3")
	check(SaveSlots.exists(2) and not SaveSlots.exists(0), "only slot 3 is filled")
	check(SaveSlots.latest() == 2 and SaveSlots.first_empty() == 0, "latest and first empty")
	var p := SaveSlots.profile(2)
	check(p.name == "Mara Voss" and (p.species == "kesh" or p.race == "kesh") and p.world == "new_houston" and p.difficulty == "hard", "profile saved")
	check(p.location == "dock" and Session.scene_path() == Session.PLACE_SCENE, "new games begin walking the port")
	check(Session.start_funds() == 110000, "hard starts with 110,000 credits")
	check(int(p.credits) < 110000 and int(p.credits) > 0, "credits are funds minus the starter ship")
	check(Worlds.world(p.world).yard_name in ["Roosevelt Orbital Yards", "Roosevelt Independent Yards"], "starting world decides the yard")

	print("overwrite keeps the old save")
	check(Session.begin_new(2, "Second", "human", "easy", "concord"), "start over in slot 3")
	var parked := 0
	for f in DirAccess.get_files_at(SaveSlots.dir):
		if f.contains("replaced"):
			parked += 1
	check(parked == 1, "the replaced save was moved aside, not deleted")

	print("load and resume")
	Session.slot = -1
	Session.profile = Session.default_profile()
	check(Session.load_slot(2) and Session.profile.name == "Second", "load slot 3")
	check(not Session.load_slot(4), "an empty slot does not load")
	Session.profile["location"] = "shipyard"
	check(Session.scene_path() == Session.YARD_SCENE, "saved in the shipyard resumes in the shipyard")
	check(LoadPanel.describe(0).contains("Empty") and LoadPanel.describe(2).contains("Second"), "load list describes slots")

	print("freight lifecycle")
	Session.load_slot(2)
	var offers := Contracts.offers_from(Session.system_id())
	check(not offers.is_empty(), "starting system has freight available")
	if not offers.is_empty():
		var accepted := Session.accept_contract(offers[0])
		check(bool(accepted.ok) and not Session.active_contract().is_empty(), "contract can be accepted and cargo loaded")
		var departed := Session.depart_active_contract()
		check(bool(departed.ok) and Session.system_id() == String(offers[0].destination_system_id), "ready ship travels to contract destination")
		var before := int(Session.profile.credits)
		var delivered := Session.deliver_active_contract()
		check(bool(delivered.ok) and Session.active_contract().is_empty() and int(Session.profile.credits) > before, "delivery unloads freight and pays the operator")

	print("builder in a game")
	Session.load_slot(2)
	var scene: Node3D = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	check(scene._credits() == int(Session.profile.credits) and scene._credits() == scene._start_funds() + scene.earned - scene._ship_cost(), "builder credits match the saved game")
	check(scene.yard_label.text.contains("Concord Open Docks") or scene.yard_label.text.contains("Concord Exchange Yards"), "builder shows which yard you are at")
	check(Session.profile.location == "shipyard", "entering the builder records the shipyard")
	scene.name_edit.text = "Dunlin"
	scene._on_ship_name("Dunlin")
	check(SaveSlots.profile(2).ship_name == "Dunlin", "ship name is saved to the slot")
	scene._select(scene.library.order.find(&"radiator"))
	scene._save()
	check(SaveSlots.profile(2).location == "shipyard", "saving in the builder records where you were")
	print("MENUS ", "PASSED" if ok else "FAILED")
	quit(0 if ok else 1)
