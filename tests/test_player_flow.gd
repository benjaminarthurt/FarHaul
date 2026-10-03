extends SceneTree
## The player inside the living economy: board, accept, depart, deliver, wait, save and load.
## Run: godot --headless --path . --script res://tests/test_player_flow.gd
## Uses a throwaway save folder.

var fails := 0

func check(ok: bool, msg: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + msg)
	if not ok:
		fails += 1

func _initialize() -> void:
	SaveSlots.dir = "user://test_saves_flow"
	for f in DirAccess.get_files_at(SaveSlots.dir):
		DirAccess.remove_absolute(SaveSlots.dir + "/" + f)
	process_frame.connect(_run, CONNECT_ONE_SHOT)

## The new-game starter is sublight; interstellar freight needs a drive, so fit one the way a captain would.
func _fit_ftl() -> void:
	var data := SaveSlots.read(0)
	var ship := ShipData.new(ModuleLibrary.new())
	ShipPresets.build(ship, ShipPresets.STARTER_FTL)
	data["modules"] = (JSON.parse_string(ship.to_json()) as Dictionary)["modules"]
	data["cargo"] = CargoManifest.new(ship).to_dict()
	SaveSlots.write(0, data)
	SimWorld.sync(Session.sim, Session.profile, ship)


func _run() -> void:
	print("new game starts a living world")
	check(Session.begin_new(0, "Test Captain", "human", "hard", "roosevelt_independent_yards"), "begin a hard game at Roosevelt")
	check(Session.sim != null and Session.sim.hour >= 24 * SimWorld.WARMUP_DAYS, "the world has already been running (%d days)" % Session.day())
	check(Session.system_id() == "new_houston", "docked at New Houston")
	_fit_ftl()
	var credits0 := int(Session.profile.credits)
	check(SaveSlots.read(0).has("sim"), "the sim is saved with the game")

	print("board, accept, depart, deliver")
	var board := Contracts.offers_from("new_houston")
	check(not board.is_empty() and board[0].has("sim_contract"), "live freight is posted at the supplier's port (%d offers)" % board.size())
	if board.is_empty() or not board[0].has("sim_contract"):
		print("DONE fails=", fails)
		quit(1)
		return
	var offer: Dictionary = board[0]
	check(float(offer.rate) > 0.0 and float(offer.offer) > 0.0, "offer has tonnes and a rate (%.1f t at %d cr/t)" % [float(offer.offer), int(offer.rate)])
	var hour0 := Session.sim.hour
	var acc := Session.accept_contract(offer)
	check(bool(acc.ok), "accept and load: %s" % acc.message)
	var active := Session.active_contract()
	check(active.has("sim_taken") and float(active.accepted_tonnes) > 0.0, "the active contract is a real sim contract (%.1f t aboard)" % float(active.get("accepted_tonnes", 0)))
	check(Session.sim.carriers["player"]["state"] == "working", "the player's carrier is working it")
	var dep := Session.depart_active_contract()
	check(bool(dep.ok), "depart: %s" % dep.message)
	check(Session.sim.hour > hour0 + 12, "time passed on the trip (%.1f days)" % ((Session.sim.hour - hour0) / 24.0))
	check(Session.system_id() == String(active.destination_system_id), "arrived at the contract's destination")
	check(int(Session.profile.credits) < credits0, "the trip cost money before any pay (%d cr)" % (int(Session.profile.credits) - credits0))
	var before_pay := int(Session.profile.credits)
	var dl := Session.deliver_active_contract()
	check(bool(dl.ok) and Session.active_contract().is_empty(), "deliver: %s" % dl.message)
	check(int(Session.profile.credits) > before_pay, "delivery paid the captain")
	var lot_ok := false
	for k in Session.sim.contracts.values():
		if k["id"] == String(active.sim_taken):
			lot_ok = k["status"] == "delivered"
	check(lot_ok, "the sim records the contract delivered")

	print("waiting costs money, and the world moves")
	var c_before := int(Session.profile.credits)
	var h_before := Session.sim.hour
	var w := Session.wait_days(3)
	check(bool(w.ok) and Session.sim.hour == h_before + 72, "three days pass")
	check(int(Session.profile.credits) < c_before, "wages and ownership cost %d cr" % (c_before - int(Session.profile.credits)))

	print("dock helpers")
	check(SimWorld.daily_cost(Session.sim) > 0.0 and SimWorld.runway_days(Session.sim) > 0, "running costs %d cr/day, cash lasts %d days" % [roundi(SimWorld.daily_cost(Session.sim)), SimWorld.runway_days(Session.sim)])
	var dests := SimWorld.destinations(Session.sim)
	check(not dests.is_empty() and float(dests[0].cost) > 0.0, "fly-empty options listed (%d, nearest %s)" % [dests.size(), String(dests[0].system_id) if not dests.is_empty() else "-"])
	check(not bool(Session.travel_empty(Session.system_id()).ok), "cannot fly empty to where you already are")

	print("save and load keep the world")
	var hour_now := Session.sim.hour
	var cash_now := SimWorld.credits(Session.sim)
	var delivered_now := int(Session.sim.summary()["contracts"]["delivered"])
	Session.sim = null
	Session.slot = -1
	check(Session.load_slot(0) and Session.sim != null, "load restores the sim")
	check(Session.sim.hour == hour_now and SimWorld.credits(Session.sim) == cash_now and int(Session.profile.credits) == cash_now, "same day and same money after loading")
	check(int(Session.sim.summary()["contracts"]["delivered"]) == delivered_now, "deliveries so far carried over")
	Session.sim.run_days(5)
	check(Session.sim.violations.is_empty(), "the restored world keeps running cleanly")

	print("the builder spending money does not break the books")
	var data := SaveSlots.read(0)
	var ship := ShipData.new(ModuleLibrary.new())
	ship.from_json(JSON.stringify(data))
	Session.profile["credits"] = int(Session.profile.credits) - 12000
	SimWorld.sync(Session.sim, Session.profile, ship)
	check(SimWorld.credits(Session.sim) == int(Session.profile.credits), "sim cash follows the profile")
	check(absf(float(Session.sim.summary()["cash_error"])) < 0.01, "money is still conserved")

	print("insolvency")
	var saved_credits := int(Session.profile.credits)
	check(not Session.insolvent(), "a captain with cash is not insolvent")
	Session.profile["credits"] = -50
	check(Session.insolvent(), "a captain in debt with no contract is insolvent")
	var rep := Session.run_report()
	check(int(rep.days) > 0 and int(rep.jobs) >= 1 and float(rep.tonnes) > 0.0, "run report: %d days, %d jobs, %.0f t" % [int(rep.days), int(rep.jobs), float(rep.tonnes)])
	Session.profile["credits"] = saved_credits

	print("flights and the bank")
	var cr_before := int(Session.profile.credits)
	var hr_before := Session.sim.hour
	var msg := Session.finish_flight(0.5, 7300.0, 0.2)
	check(msg != "" and int(Session.profile.credits) < cr_before, "a flight costs fuel and repairs (%d cr): %s" % [cr_before - int(Session.profile.credits), msg])
	check(Session.sim.hour >= hr_before + 2, "and the clock moved on (%d h)" % (Session.sim.hour - hr_before))
	check(absf(float(Session.sim.summary()["cash_error"])) < 0.01 and Session.sim.violations.is_empty(), "the books still balance after a flight")
	Session.profile["credits"] = -5000
	check(Session.insolvent() and bool(Session.restructure().ok), "the bank steps in for a bankrupt captain")
	check(int(Session.profile.credits) > 0 and not Session.insolvent(), "debts cleared, cash %d cr" % int(Session.profile.credits))
	check(int(Session.profile.bankruptcies) == 1, "the failure is on the record")
	check(SaveSlots.read(Session.slot).modules.size() == 10, "the player flies the starter hauler again")
	check(absf(float(Session.sim.summary()["cash_error"])) < 0.01, "money is still conserved after the bailout")
	check(not bool(SimWorld.player(Session.sim)["ftl"]), "and it has no FTL drive")
	_fit_ftl()
	print("a captain working steadily for 60 days")
	var trips := 0
	var days_start := Session.day()
	var guard := 0
	while Session.day() - days_start < 60 and guard < 200:
		guard += 1
		var offers := Contracts.offers_from(Session.system_id())
		var live: Dictionary = {}
		for o in offers:
			if o.has("sim_contract"):
				live = o
				break
		if live.is_empty():
			var there := SimWorld.nearest_freight(Session.sim)
			if there != "" and bool(Session.travel_empty(there).ok):
				continue
			Session.wait_days(1)
			continue
		if not bool(Session.accept_contract(live).ok):
			Session.wait_days(1)
			continue
		if not bool(Session.depart_active_contract().ok):
			break
		Session.deliver_active_contract()
		trips += 1
	check(trips >= 3, "worked %d jobs in 60 days (credits now %s)" % [trips, ShipStats.commas(int(Session.profile.credits))])
	check(Session.sim.violations.is_empty(), "no ledger violations")
	check(absf(float(Session.sim.summary()["cash_error"])) < 0.01, "money conserved after a working stretch")
	print("DONE fails=", fails)
	quit(1 if fails > 0 else 0)
