extends SceneTree
## Bigger holds and passengers (scripts/passengers.gd): the 2x2 hold and 2x3 bay, cabins in three sizes,
## beds given best first and paid for at their tier, parties who insist on a cabin, long-haul passengers
## at the freight office riding along with freight, local ones from the bar, setting down on arrival,
## rough and late rides, survivors in spare beds, and old saves' passenger runs.
## Run: godot --headless --path . --script res://tests/test_passengers.gd
var fails := 0
func check(ok: bool, msg: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + msg)
	if not ok:
		fails += 1


func _initialize() -> void:
	SaveSlots.dir = "user://test_saves_pax_%d" % OS.get_process_id()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SaveSlots.dir))
	process_frame.connect(_run, CONNECT_ONE_SHOT)


func _liner(at_slot: int) -> ShipData:
	var data := SaveSlots.read(at_slot)
	var ship := ShipData.new(ModuleLibrary.new())
	var err := ShipPresets.build(ship, ShipPresets.STARTER_LINER)
	check(err == "", "the liner builds: %s" % (err if err != "" else "ok"))
	data["modules"] = (JSON.parse_string(ship.to_json()) as Dictionary)["modules"]
	data["cargo"] = CargoManifest.new(ship).to_dict()
	SaveSlots.write(at_slot, data)
	SimWorld.sync(Session.sim, Session.profile, ship)
	return ship


func _run() -> void:
	print("holds and cabins")
	var lib := ModuleLibrary.new()
	var small := lib.get_def(&"cargo_hold")
	var big := lib.get_def(&"cargo_hold_2x2")
	var bay := lib.get_def(&"cargo_bay_2x3")
	check(big.cargo_slots == 8 and bay.cargo_slots == 12, "a 2x2 hold takes 8 containers, the 2x3 bay 12")
	check(float(big.cost) / big.cargo_capacity < float(small.cost) / small.cargo_capacity and bay.mass / bay.cargo_capacity < small.mass / small.cargo_capacity,
			"bigger is cheaper and lighter a tonne: %.0f, %.0f, %.0f cr/t" % [float(small.cost) / small.cargo_capacity, float(big.cost) / big.cargo_capacity, float(bay.cost) / bay.cargo_capacity])
	var crates := 0
	var v := bay.build_visual()
	for c in v.get_children():
		if c.has_meta("slot"):
			crates += 1
	check(crates == 12, "and shows 12 containers, two high along the walls")
	v.free()
	for id in [&"pax_cabin", &"pax_quarters", &"pax_stateroom"]:
		var d := lib.get_def(id)
		check(d.cabins > 0 and d.berths == 0 and d.group == &"cabins", "%s: %d passenger beds at %.1f×, no crew berths" % [d.display_name, d.cabins, Passengers.mult(d.cabin_tier)])
	check(lib.order.find(&"cargo_hold") == 9, "the number keys still pick the same hull parts")
	var liner := ShipData.new(lib)
	check(ShipPresets.build(liner, ShipPresets.STARTER_LINER) == "", "a liner: quarters, a cabin and a stateroom")
	var ls := ShipStats.compute(liner, 1.0)
	check(int(ls.cabins) == 8 and (ls.cabin_beds as Array) == [0, 2, 4, 2] and int(ls.open_doors) == 0, "8 passenger beds, sealed: %s" % str(ls.cabin_beds))
	check(ShipStats.format(ls).contains("Passengers  8 beds"), "the builder's stats say so")

	print("beds")
	var st := {"berths": 3, "crew_aboard": 1, "cabin_beds": [0, 2, 4, 2], "rescued": 0, "ftl": true}
	var lay := Passengers.layout(st, [{"beds": []}])
	check(lay.free == [2, 2, 4, 2], "2 spare bunks and 8 passenger beds free")
	check(Passengers.assign(lay.free, 3, 0) == [3, 3, 2], "a party of three gets the best: stateroom, stateroom, quarters")
	check(Passengers.assign([2, 0, 0, 0], 2, 1).is_empty(), "a party wanting cabins won't take bunks")
	check(Passengers.fare_for(1000, [3, 0]) == 3500, "and pays for the beds it gets: 2.5× and 1×")
	var sv := st.duplicate()
	sv["rescued"] = 3
	var lr := Passengers.layout(sv, [{"beds": [1, 1]}])
	check(lr.free == [0, 0, 3, 2] and int(lr.over) == 0, "survivors take the spare bunks, then the cheapest beds left: %s" % str(lr.free))

	print("long haul, alongside freight")
	Session.begin_new(1, "Tester", "human", "normal", "roosevelt_independent_yards")
	var ship := _liner(1)
	var stats := Session.ship_stats(ship)
	var offers := Passengers.long_haul()
	check(not offers.is_empty(), "parties asking at the freight office: %s" % ", ".join(offers.map(func(o): return String(o.title))))
	var freight: Dictionary = {}
	for o in Contracts.offers_from(Session.system_id()):
		if o.has("sim_contract") and String(o.destination_system_id) != Session.system_id():
			freight = o
			break
	check(not freight.is_empty(), "and freight between stars")
	var to_sys := String(freight.destination_system_id)
	var pax: Dictionary = {}
	for o in offers:
		if String(o.destination_system_id) == to_sys and int(o.wants) == 0:
			pax = o
	if pax.is_empty():   # nobody going that way today: make one, as the office would
		pax = (offers[0] as Dictionary).duplicate()
		pax["id"] = "pax-test"
		pax["destination_system_id"] = to_sys
		pax["dest_name"] = String(Worlds.system(to_sys).get("name", to_sys))
		pax["wants"] = 0
	pax["seats"] = 2
	var r := Session.accept_contract(freight)
	check(bool(r.ok), "freight loaded: %s" % r.message)
	var expect := Passengers.fare_now(pax, Session.ship_stats(ship))
	r = Session.accept_contract(pax)
	check(bool(r.ok) and Passengers.count() == 2, "and a party of two aboard with it: %s" % r.message)
	var b: Dictionary = Passengers.aboard()[0]
	check(b.beds == [3, 3] and int(b.fare) == expect and int(b.fare) == Passengers.fare_for(int(pax.per_seat), [3, 3]), "in the stateroom, %s cr (%s a head in a bunk)" % [ShipStats.commas(int(b.fare)), ShipStats.commas(int(pax.per_seat))])
	check(not Passengers.long_haul().any(func(o): return String(o.id) == String(pax.id)), "and off the board")
	var picky := (offers[0] as Dictionary).duplicate()
	picky["id"] = "pax-picky"
	picky["wants"] = 3
	picky["seats"] = 1
	check(Passengers.why_not(picky, Session.ship_stats(ship)).contains("stateroom"), "someone who wants the stateroom can't have it now: %s" % Passengers.why_not(picky, Session.ship_stats(ship)))
	var fares0 := int((Session.profile.get("pax_stats", {}) as Dictionary).get("fares_cr", 0))
	r = Session.depart_active_contract()
	check(bool(r.ok) and Session.system_id() == to_sys, "flew the freight: %s" % r.message)
	check(Passengers.count() == 0 and String(r.message).contains("Passengers off"), "and the passengers got off there")
	var got := int((Session.profile.get("pax_stats", {}) as Dictionary).get("fares_cr", 0)) - fares0
	check(got == int(b.fare), "they paid the fare in full: %s cr" % ShipStats.commas(got))
	check(bool(Session.deliver_active_contract().ok), "and the freight's delivered as usual")
	check(int(Session.profile.get("rep", 0)) >= 2, "a smooth ride: standing %d" % int(Session.profile.get("rep", 0)))

	print("rough and late")
	Passengers.migrate({})   # nothing to do
	var o2 := (Passengers.long_haul()[0] as Dictionary).duplicate() if not Passengers.long_haul().is_empty() else {}
	check(not o2.is_empty(), "more passengers here")
	if not o2.is_empty():
		o2["seats"] = 1
		o2["wants"] = 0
		Session.accept_contract(o2)
		var bk: Dictionary = Passengers.aboard()[0]
		Session.profile["hull_damage"] = float(bk.hull_at_accept) + 0.2
		var fares := int((Session.profile.get("pax_stats", {}) as Dictionary).get("fares_cr", 0))
		r = Session.travel_empty(String(o2.destination_system_id))
		check(bool(r.ok) and String(r.message).contains("rough ride"), "a hull full of dents: %s" % r.message)
		var paid := int((Session.profile.get("pax_stats", {}) as Dictionary).get("fares_cr", 0)) - fares
		check(paid == roundi(float(bk.fare) * 0.5), "and they paid half: %s of %s cr" % [ShipStats.commas(paid), ShipStats.commas(int(bk.fare))])
		Session.profile["hull_damage"] = 0.0
	var o3 := (Passengers.long_haul()[0] as Dictionary).duplicate() if not Passengers.long_haul().is_empty() else {}
	if not o3.is_empty():
		o3["seats"] = 1
		o3["wants"] = 0
		o3["due_days"] = 0
		Session.accept_contract(o3)
		Session.wait_days(2)
		r = Session.travel_empty(String(o3.destination_system_id))
		check(String(r.message).contains("late"), "two days in port first: %s" % r.message)

	print("local, from the bar")
	Session.begin_new(2, "Tester", "human", "normal", "roosevelt_independent_yards")
	ship = _liner(2)
	var local: Dictionary = {}
	var cargo: Dictionary = {}
	for k in 12:
		for j in Session.people_here():
			if String(j.person_kind) == "passenger" and local.is_empty():
				local = j
		if not local.is_empty():
			break
		Session.wait_days(1)
	check(not local.is_empty() and int(local.per_seat) > 0 and local.has("wants"), "someone at the bar wants passage: %s" % String(local.get("line", "")))
	for o in Contracts.offers_from(Session.system_id()):
		if bool(o.get("local", false)) and String(o.destination_port_id) == String(local.get("destination_port_id", "")) and not o.has("person_kind"):
			cargo = o
	if not cargo.is_empty():
		check(bool(Session.accept_contract(cargo).ok), "a load for the same site")
	r = Session.accept_contract(local)
	check(bool(r.ok), "they come along with it: %s" % r.message)
	check(not Session.people_here().any(func(j): return String(j.id) == String(local.id)), "and leave the bar")
	if not cargo.is_empty():
		r = Session.depart_active_contract()
	else:
		r = Session.local_reposition(String(local.destination_port_id))
	check(bool(r.ok) and String(r.message).contains("Passengers off"), "set down at %s: %s" % [String(local.dest_name), r.message])
	var back := String(Session.local_sites()[0].id) if not Session.local_sites().is_empty() else ""
	check(Session.begin_ferry_flight(back).ok if back != "" and Session.active_contract().is_empty() else true, "a hop with no contract can be flown by hand")
	Session.flight_job = {}

	print("survivors, crew and old saves")
	var data := SaveSlots.read(2)
	data["active_contract"] = {"id": "old-pax", "person_kind": "passenger", "person": "Ade Okafor", "seats": 2, "pay_total": 1500, "fare": 1500,
			"destination_port_id": "new_houston__moon", "local": true, "hull_at_accept": 0.0}
	SaveSlots.write(2, data)
	Session.load_slot(2)
	check(Session.active_contract().is_empty() and Passengers.aboard().any(func(x): return String(x.id) == "old-pax" and int(x.fare) == 1500), "a 0.14 passenger run loads as a booking")
	stats = Session.ship_stats(ship)
	check(Session.free_berths(stats) == int(Passengers.layout(stats).free[0]), "free crew berths count the passengers in spare bunks: %d" % Session.free_berths(stats))
	var f := Figure.make(Color(0.86, 0.8, 0.66), 7, false, "human", "passenger")
	var c := Figure.make(Color(0.85, 0.55, 0.15), 7, false, "human")
	check(f.outfit == "passenger" and _meshes(f) != _meshes(c), "passengers dress for travel, not work (%d pieces against %d)" % [_meshes(f), _meshes(c)])
	f.free()
	c.free()
	var ppl := PassengersAboard.people()
	check(ppl.size() == 2 and PassengersAboard.line_for(ppl[0].booking, 0, 0).contains("PASSENGER TO"), "aboard, they say so: %s" % PassengersAboard.line_for(ppl[0].booking, 0, 0))
	print("DONE fails=", fails)
	quit(1 if fails > 0 else 0)


func _meshes(n: Node) -> int:
	var k := 0
	for ch in n.get_children():
		k += (1 if ch is MeshInstance3D else 0) + _meshes(ch)
	return k
