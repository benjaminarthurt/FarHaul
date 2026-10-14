extends SceneTree
## Cancelling a contract (Session.cancel_contract): before setting off, the load goes back, a fee is
## paid, people you let down remember, and the economy puts the freight back on the board; not once the
## ship has arrived or left the origin. Also the case that asked for it: an interstellar load and no
## FTL drive any more.
## Run: godot --headless --path . --script res://tests/test_cancel_contract.gd
var fails := 0
func check(ok: bool, msg: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + msg)
	if not ok:
		fails += 1
func _initialize() -> void:
	SaveSlots.dir = "user://test_saves_cancel_%d" % OS.get_process_id()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SaveSlots.dir))
	process_frame.connect(_run, CONNECT_ONE_SHOT)


func _ship(preset: Array) -> void:
	var data := SaveSlots.read(Session.slot)
	var ship := ShipData.new(ModuleLibrary.new())
	ShipPresets.build(ship, preset)
	data["modules"] = (JSON.parse_string(ship.to_json()) as Dictionary)["modules"]
	SaveSlots.write(Session.slot, data)


func _aboard() -> float:
	var l := Session._load_ship(SaveSlots.read(Session.slot))
	var t := 0.0
	for s in (l.manifest as CargoManifest).to_dict().get("slots", []):
		t += float(s.get("tonnes", 0.0)) if s is Dictionary else 0.0
	return float(l.manifest.total_mass()) if l.manifest.has_method("total_mass") else t


func _run() -> void:
	Session.begin_new(2, "Tester", "human", "normal", "roosevelt_independent_yards")
	check(Session.cancel_block() != "", "nothing to cancel with no contract")
	print("a local run")
	var job := {}
	for o in Contracts.offers_from(Session.system_id()):
		if bool(o.get("local", false)):
			job = o
			break
	var r := Session.accept_contract(job)
	var c := Session.active_contract()
	var cr := int(Session.profile.credits)
	var fee := Session.cancel_fee()
	check(bool(r.ok) and Session.cancel_block() == "" and fee > 0, "loaded at the origin: it can be cancelled, for %d cr" % fee)
	r = Session.cancel_contract()
	var manifest: CargoManifest = Session._load_ship(SaveSlots.read(Session.slot)).manifest
	check(bool(r.ok) and Session.active_contract().is_empty() and manifest.total_of(StringName(c.commodity)) <= 0.001, "cancelled: the load comes off: %s" % r.message)
	check(int(Session.profile.credits) == cr - fee and absf(float(Session.sim.summary()["cash_error"])) < 0.01, "and the fee's paid, money conserved")

	print("once there")
	for o in Contracts.offers_from(Session.system_id()):
		if bool(o.get("local", false)):
			job = o
			break
	Session.accept_contract(job)
	Session.depart_active_contract()
	check(Session.cancel_block().contains("Deliver"), "arrived: deliver it, no cancelling: %s" % Session.cancel_block())
	Session.deliver_active_contract()

	print("an interstellar load, and the drive's been sold")
	Session.begin_new(2, "Tester", "human", "normal", "roosevelt_independent_yards")
	_ship(ShipPresets.STARTER_FTL)
	Session.profile["credits"] = 500000
	Session.save_profile()
	var far := {}
	for o in Contracts.offers_from(Session.system_id()):
		if not bool(o.get("local", false)) and o.has("sim_contract"):
			far = o
			break
	if far.is_empty():
		for i in 10:
			Session.wait_days(1)
			for o in Contracts.offers_from(Session.system_id()):
				if not bool(o.get("local", false)) and o.has("sim_contract"):
					far = o
					break
			if not far.is_empty():
				break
	r = Session.accept_contract(far)
	check(bool(r.ok), "took an interstellar load: %s" % r.message)
	var kid := String(Session.active_contract().get("sim_taken", ""))
	_ship(ShipPresets.STARTER)   # sold the drive in the shipyard
	r = Session.depart_active_contract()
	check(not bool(r.ok) and String(r.message).contains("FTL drive") and Session.depart_block().contains("FTL drive"), "no drive: it can't leave, and it says why (%s)" % r.message)
	var origin := String(SimWorld.player(Session.sim).sys)
	for h in 48:   # time passes in port until the freight is aboard in the economy's books, but not gone
		if String(Session.sim.contracts[kid].status) == "in_transit":
			break
		Session.sim.step_hour()
	check(String(Session.sim.contracts[kid].status) == "in_transit" and String(SimWorld.player(Session.sim).sys) == origin, "the economy has the freight aboard, still in port")
	print("  (economy status before cancelling: ", Session.sim.contracts[kid].status, ", player at ", SimWorld.player(Session.sim).sys, ")")
	r = Session.cancel_contract()
	check(bool(r.ok) and Session.active_contract().is_empty(), "cancelled: %s" % r.message)
	var k: Dictionary = Session.sim.contracts.get(kid, {})
	check(not k.is_empty() and String(k.status) == "offered" and String(SimWorld.player(Session.sim).state) == "idle", "the freight's back on the board and the ship is free (%s)" % String(k.get("status", "?")))
	check(Session.sim.ledger.check().is_empty() and absf(float(Session.sim.summary()["cash_error"])) < 0.01, "goods and money all accounted for")
	r = Session.wait_days(1)
	check(bool(r.ok), "and life goes on: %s" % r.message)
	print("DONE fails=", fails)
	quit(1 if fails > 0 else 0)
