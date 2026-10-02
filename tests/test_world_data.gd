extends SceneTree
# The world data in data/world/ is read by the game, so check it hangs together:
# every id that something refers to must exist, and the new-game choices must work from it.

var ok := true

func check(cond: bool, label: String) -> void:
	print(("  ok    " if cond else "  FAIL  "), label)
	if not cond:
		ok = false

func _load(f: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("res://data/world/" + f))

func _initialize() -> void:
	var ks := _load("known_space.json")
	var systems: Array = _load("systems.json").systems
	var species: Array = _load("species.json").species
	var routes: Array = _load("routes.json").routes
	var corridors: Array = _load("corridors.json").corridors
	var sys_ids := {}
	for s in systems:
		sys_ids[s.id] = true

	print("references")
	check(systems.size() == ks.system_ids.size(), "manifest lists every system (%d)" % systems.size())
	var all_listed := true
	for id in ks.system_ids:
		if not sys_ids.has(id):
			all_listed = false
	check(all_listed, "every manifest system exists")
	var routes_ok := true
	for r in routes:
		if not sys_ids.has(r.a) or not sys_ids.has(r.b):
			routes_ok = false
	check(routes_ok and routes.size() == ks.route_ids.size(), "every route joins two real systems")
	var cor_ok := true
	for c in corridors:
		for id in c.system_ids:
			if not sys_ids.has(id):
				cor_ok = false
	check(cor_ok, "every corridor lists real systems")
	var sp_ok := true
	for s in species:
		if not sys_ids.has(s.home_system_id):
			sp_ok = false
	check(sp_ok, "every species has a real home system")

	print("new-game choices")
	var list := Worlds.species_list()
	check(list.size() == 5, "five playable species")
	for sp in list:
		var starts: Array = Worlds.start_ids(sp.id)
		check(starts[0] == sp.home_system_id and starts.size() == 4, "%s starts: home first, then the shared three" % sp.name)
		for id in starts:
			var w := Worlds.world(id)
			check(w.id == id and w.yard_name != "" and w.blurb != "", "%s has a yard and a description" % id)
	check(Worlds.world("no_such_place").id == "concord", "an unknown system falls back to Concord")
	check(Worlds.species("no_such_species").id == "human", "an unknown species falls back to the first")
	check(Worlds.world("concord").neighbours.size() > 0 and Worlds.world("concord").corridors.size() > 0, "systems report routes and corridors")
	check(Worlds.population_text(18400000000) == "18.4 billion", "population reads naturally")
	print("WORLD DATA ", "PASSED" if ok else "FAILED")
	quit(0 if ok else 1)
