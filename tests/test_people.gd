extends SceneTree
## People with work: who asks, the rules for each kind of job, and standing.
## Run: godot --headless --path . --script res://tests/test_people.gd
var fails := 0
func check(ok: bool, msg: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + msg)
	if not ok:
		fails += 1
func _initialize() -> void:
	SaveSlots.dir = "user://test_saves_people"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SaveSlots.dir))
	process_frame.connect(_run, CONNECT_ONE_SHOT)
func _fit(preset: Array) -> String:
	var data := SaveSlots.read(Session.slot)
	var ship := ShipData.new(ModuleLibrary.new())
	var err := ShipPresets.build(ship, preset)
	data["modules"] = (JSON.parse_string(ship.to_json()) as Dictionary)["modules"]
	data["cargo"] = CargoManifest.new(ship).to_dict()
	SaveSlots.write(Session.slot, data)
	SimWorld.sync(Session.sim, Session.profile, ship)
	return err
func _clear() -> void:
	var data := SaveSlots.read(Session.slot)
	data.erase("active_contract")
	SaveSlots.write(Session.slot, data)
## Find a job of `kind` in the next days here, waiting a day at a time.
func _find(kind: String, unlocked := true) -> Dictionary:
	for i in 30:
		for j in Session.people_here():
			if String(j.person_kind) == kind and (not unlocked or not j.has("locked")):
				return j
		Session.wait_days(1)
	return {}
func _run() -> void:
	Session.begin_new(2, "Pilot", "human", "normal", "roosevelt_independent_yards")
	check(People.standing(0) == "Unknown" and People.standing(12) == "Known" and People.standing(60) == "Respected", "standings by points")
	check(is_equal_approx(People.rep_bonus(100), 0.15), "standing's pay bonus is capped at 15%")
	var a := Session.people_here()
	var b := Session.people_here()
	check(not a.is_empty(), "people are asking at the home port (%d)" % a.size())
	check(a.size() == b.size() and (a.is_empty() or String(a[0].person) == String(b[0].person)), "who asks is fixed for the day")
	var posted_ids := []
	for o in Contracts.offers_from(Session.system_id()):
		posted_ids.append(String(o.id))
	var overlap := false
	for j in a:
		if String(j.id) in posted_ids:
			overlap = true
	check(not overlap, "their work is not on the posted board")
	# Sealed work wants standing.
	var sealed := _find("sealed", false)
	check(not sealed.is_empty() and sealed.has("locked"), "a sealed crate is refused to an unknown captain")
	if not sealed.is_empty():
		check(not bool(Session.accept_contract(sealed).ok), "and cannot be taken")
	# Rush: on time, then late.
	var rush := _find("rush")
	check(not rush.is_empty(), "a rush job turns up")
	if not rush.is_empty():
		var std := float(rush.rate)
		var r := Session.accept_contract(rush)
		check(bool(r.ok), "the rush job is taken: %s" % r.message)
		var c := Session.active_contract()
		check(c.has("due_hour") and int(c.due_hour) == Session.sim.hour + int(rush.due_in_hours), "it is due %d hours from now" % int(rush.due_in_hours))
		var cr0 := int(Session.profile.credits)
		r = Session.depart_active_contract(true)
		check(bool(r.ok) and "hard burn" in String(r.message), "sent on a hard burn: %s" % r.message)
		if not bool(r.ok):
			print("DONE fails=", fails + 1)
			quit(1)
			return
		var rep0 := int(Session.profile.get("rep", 0))
		r = Session.deliver_active_contract()
		check(bool(r.ok) and "on time" in String(r.message).to_lower(), "delivered on time: %s" % r.message)
		check(int(r.payment) == int(c.pay_total), "full pay on time (%d)" % int(r.payment))
		check(int(Session.profile.credits) > cr0, "a rush on a hard burn still makes money (%+d cr)" % (int(Session.profile.credits) - cr0))
		check(int(Session.profile.rep) == rep0 + 3, "standing +3 for a rush on time")
		var late := _find("rush")
		if not late.is_empty():
			Session.accept_contract(late)
			var lc := Session.active_contract()
			Session.depart_active_contract()   # the usual burn: too slow for a rush
			var rep1 := int(Session.profile.rep)
			r = Session.deliver_active_contract()
			check("late" in String(r.message).to_lower() and int(r.payment) == roundi(int(lc.pay_total) * 0.5), "the usual burn arrives late, at half pay: %s" % r.message)
			check(int(Session.profile.rep) == maxi(0, rep1 - 4), "and costs standing")
		_clear()
	# Passengers need spare berths.
	var fare := _find("passenger")
	check(not fare.is_empty(), "passengers ask for passage")
	if not fare.is_empty():
		var r := Session.accept_contract(fare)
		check(not bool(r.ok) and "spare berth" in String(r.message), "the starter has no spare berth: %s" % r.message)
		check(_fit(ShipPresets.STARTER_CABIN) == "", "the cabin starter builds")
		fare = _find("passenger")
		if int(fare.seats) > 2:
			for i in 10:
				Session.wait_days(1)
				fare = _find("passenger")
				if int(fare.seats) <= 2:
					break
		r = Session.accept_contract(fare)
		check(bool(r.ok), "with two bunks they come aboard: %s" % r.message)
		var c := Session.active_contract()
		check(Contracts.ready(Contracts.check(Session.ship_stats(Session._load_ship(SaveSlots.read(Session.slot)).ship), Session._load_ship(SaveSlots.read(Session.slot)).manifest, c)), "a passenger run is ready to fly with no cargo")
		Session.depart_active_contract()
		Session.profile["hull_damage"] = 0.2   # a hard landing on the way
		r = Session.deliver_active_contract()
		check("rough" in String(r.message) and int(r.payment) == roundi(int(c.pay_total) * 0.5), "a hard landing halves the fare: %s" % r.message)
		Session.profile["hull_damage"] = 0.0
		_clear()
	# Sealed, with standing.
	Session.profile["rep"] = 12
	Session.save_profile()
	sealed = _find("sealed")
	check(not sealed.is_empty() and not sealed.has("locked"), "a known captain is offered sealed crates")
	if not sealed.is_empty():
		var r := Session.accept_contract(sealed)
		check(bool(r.ok), "the crate is loaded: %s" % r.message)
		var c := Session.active_contract()
		Session.depart_active_contract()
		r = Session.deliver_active_contract()
		check("seal intact" in String(r.message).to_lower() and int(r.payment) == int(c.pay_total), "delivered sealed and paid in full")
		check(int(Session.profile.rep) == 16, "standing +4")
	# Freight builds standing too.
	var rep2 := int(Session.profile.rep)
	var job: Dictionary = Contracts.offers_from(Session.system_id())[0]
	Session.accept_contract(job)
	Session.depart_active_contract()
	var r2 := Session.deliver_active_contract()
	check(int(Session.profile.rep) == rep2 + 1 and "Standing +1" in String(r2.message), "ordinary freight: standing +1")
	print("DONE fails=", fails)
	quit(1 if fails > 0 else 0)
