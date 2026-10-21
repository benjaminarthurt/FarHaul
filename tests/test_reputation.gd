extends SceneTree
## Reputation (scripts/reputation.gd): places, species and authorities remember you; word travels along
## the routes; bad marks fade; what it does to pay, fees, the board, people, crew and traffic control;
## settling your record; a save from before 0.20.0.
## Run: godot --headless --path . --script res://tests/test_reputation.gd
var fails := 0
func check(ok: bool, msg: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + msg)
	if not ok:
		fails += 1


func _initialize() -> void:
	SaveSlots.dir = "user://test_saves_rep_%d" % OS.get_process_id()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SaveSlots.dir))
	process_frame.connect(_run, CONNECT_ONE_SHOT)


func _blank() -> Dictionary:
	return {"places": {}, "species": {}, "auth": {}, "log": [], "faded_h": -1}


## Your standing at the home port set to about `points`, all of it the port's own opinion.
func _set_here(points: float) -> void:
	var st := Reputation.state(Session.profile)
	st.places = {String(Session.profile.port_id): points}
	st.species = {}
	st.auth = {}
	st.log = []
	Session.save_profile()


func _run() -> void:
	Hazards.off = true
	print("tiers")
	check(Reputation.tier(0) == "Unknown" and Reputation.tier(-9) == "Unknown" and Reputation.tier(9) == "Unknown", "Unknown from -9 to 9")
	check(Reputation.tier(-10) == "Doubtful" and Reputation.tier(-25) == "Unwelcome" and Reputation.tier(-50) == "Barred" and Reputation.tier(-100) == "Barred", "Doubtful at -10, Unwelcome at -25, Barred at -50")
	check(Reputation.tier(10) == "Known" and Reputation.tier(25) == "Trusted" and Reputation.tier(50) == "Respected" and Reputation.tier(100) == "Respected", "Known at 10, Trusted at 25, Respected at 50")
	check(String(Reputation.next_tier(0).name) == "Known" and String(Reputation.next_tier(-30).name) == "Doubtful" and Reputation.next_tier(60).is_empty(), "the next tier up")
	check(is_equal_approx(Reputation.pay_mult(0), 1.0) and is_equal_approx(Reputation.pay_mult(50), 1.25) and is_equal_approx(Reputation.pay_mult(-50), 0.7), "pay: 0.7 Barred, 1.0 Unknown, 1.25 Respected")
	check(is_equal_approx(Reputation.fee_mult(0), 1.0) and is_equal_approx(Reputation.fee_mult(50), 0.88) and is_equal_approx(Reputation.fee_mult(-50), 1.6), "fees: 1.6 Barred, 1.0 Unknown, 0.88 Respected")
	check(Reputation.pay_mult(17.5) > 1.05 and Reputation.pay_mult(17.5) < 1.12, "and in between, smoothly (%.3f at 17.5)" % Reputation.pay_mult(17.5))
	check(Reputation.peoples("keshar") == ["kesh"] and Reputation.peoples("new_houston").has("human"), "the Kesh live at Keshar; New Houston is %s" % ", ".join(PackedStringArray(Reputation.peoples("new_houston"))))

	print("three kinds of memory")
	var st := _blank()
	var port := "roosevelt_orbital_freight"
	var keshp := String(LocalSpace.nodes("keshar")[0].id)
	Reputation.record(st, 0, "new_houston", port, 10.0, "work")
	var p := Reputation.parts(st, port, 0)
	check(is_equal_approx(float(p.place), 10.0), "work counts with the place: %+.1f" % float(p.place))
	check(float(p.species) > 0.0 and is_equal_approx(float(p.authority), 0.0), "and its people (%+.1f), not the authorities" % float(p.species))
	var other := String(LocalSpace.nodes("new_houston")[1].id)
	check(is_equal_approx(float(Reputation.parts(st, other, 0).place), 0.0) and float(Reputation.parts(st, other, 0).species) > 0.0, "another site in the system doesn't know the work, but its people do")
	var lag := Reputation.lag_hours("new_houston", "keshar")
	check(lag > 24, "word takes %d h to get from New Houston to Keshar" % lag)
	Reputation.record(st, 0, "keshar", keshp, -20.0, "record")   # a fine at Keshar
	check(is_equal_approx(Reputation.authority_view(st, "keshar", 0), -20.0), "Keshar's authorities write their own fine down at once")
	check(is_equal_approx(Reputation.authority_view(st, "new_houston", 0), 0.0), "New Houston hasn't heard yet")
	var ln := Reputation.lag_hours("keshar", "new_houston")
	check(is_equal_approx(Reputation.authority_view(st, "new_houston", ln), -15.0), "after %d h it has: three quarters of it (%+.1f)" % [ln, Reputation.authority_view(st, "new_houston", ln)])
	Reputation.record(st, 0, "keshar", keshp, 8.0, "rescue", ["kesh"])
	check(is_equal_approx(Reputation.species_view(st, "kesh", "keshar", 0), 4.0) and is_equal_approx(Reputation.species_view(st, "kesh", "new_houston", 0), 0.0), "a rescue: the Kesh at Keshar know, the Kesh at New Houston will")
	var far := 0
	for s in Worlds.system_ids():
		far = maxi(far, Reputation.lag_hours("keshar", s))
	var before_kesh := Reputation.species_view(st, "kesh", "new_houston", far + 1)
	Reputation.tick(st, far + 24 * 40)
	check((st.log as Array).is_empty(), "once everyone has heard, the news is folded in")
	check(absf(Reputation.species_view(st, "kesh", "new_houston", far + 24 * 40) - before_kesh) < 0.01 or before_kesh > 0.0, "and it still counts (Kesh %+.1f)" % Reputation.species_view(st, "kesh", "new_houston", far + 24 * 40))

	print("fading")
	var fs := _blank()
	Reputation.record(fs, 0, "new_houston", port, -40.0, "work")
	Reputation.record(fs, 0, "new_houston", other, 30.0, "work")
	Reputation.tick(fs, 24 * 7)
	check(absf(float(fs.places[port]) - (-36.0)) < 0.2, "a bad mark fades a tenth a week (%.1f after one)" % float(fs.places[port]))
	check(is_equal_approx(float(fs.places[other]), 30.0), "a good one doesn't")
	Reputation.tick(fs, 24 * 7 * 20)
	check(float(fs.places[port]) > -6.0, "in twenty weeks it's nearly gone (%.1f)" % float(fs.places[port]))

	print("settling your record")
	var rs := _blank()
	Reputation.record(rs, 0, "new_houston", port, -6.0, "record")
	check(Reputation.settle_cost(rs, "new_houston", 0) == 6 * int(Reputation.cfg().settle_cr_per_point), "six points on the record: %d cr to settle" % Reputation.settle_cost(rs, "new_houston", 0))
	Reputation.settle(rs, "new_houston", 0)
	check(Reputation.settle_cost(rs, "new_houston", 0) == 0 and absf(Reputation.authority_view(rs, "new_houston", 0)) < 0.01, "settled: the record is clean")
	check(is_equal_approx(Reputation.authority_view(rs, "keshar", 24 * 60), 0.0), "and the word that hadn't left yet never does")
	var hs := _blank()
	var kh := Reputation.lag_hours("new_houston", "keshar")
	Reputation.record(hs, 0, "new_houston", port, -8.0, "record")
	Reputation.settle(hs, "new_houston", kh + 10)   # settled after Keshar had heard
	check(absf(Reputation.authority_view(hs, "new_houston", kh + 20)) < 0.01 and absf(Reputation.authority_view(hs, "keshar", kh + 20) + 6.0) < 0.01, "settled late: clean at home, but Keshar already heard (%+.1f)" % Reputation.authority_view(hs, "keshar", kh + 20))
	Reputation.tick(hs, 24 * 400)
	check(absf(float(hs.auth.get("keshar", 0.0)) + 6.0) < 0.6 or float(hs.auth.get("keshar", 0.0)) < 0.0, "and it stays there once folded in (%+.1f, faded)" % float(hs.auth.get("keshar", 0.0)))
	check(absf(float(hs.auth.get("new_houston", 0.0))) < 0.01, "while home stays clean")

	print("in a game")
	Session.begin_new(1, "Tester", "human", "normal", "roosevelt_independent_yards")
	check(Session.tier_here() == "Unknown" and is_equal_approx(Session.rep_fee_mult(), 1.0), "a new captain is Unknown everywhere")
	var board0 := Contracts.offers_from(Session.system_id())
	check(not board0.is_empty(), "the board has %d offers" % board0.size())
	var stats := Session.ship_stats(Session._load_ship(SaveSlots.read(Session.slot)).ship)
	var fee0 := float(Session.local_trip_cost(stats, 0.0, 1.0).fee)
	var fuel0 := Session.site_fuel_mult()
	_set_here(60.0)
	var board1 := Contracts.offers_from(Session.system_id())
	check(board1.size() == board0.size() and int(board1[0].rate) == roundi(float(board0[0].rate) * 1.25), "Respected: the same offers at a quarter more (%d against %d cr/t)" % [int(board1[0].rate), int(board0[0].rate)])
	check(float(Session.local_trip_cost(stats, 0.0, 1.0).fee) < fee0 and Session.site_fuel_mult() < fuel0, "and the berth fee and fuel are cheaper")
	var people := Session.people_here()
	var kinds := {}
	for d in 6:
		for j in Session.people_here():
			kinds[String(j.person_kind)] = true
		Session.wait_days(1)
	check(kinds.has("private"), "private contracts turn up for the Respected: %s" % ", ".join(PackedStringArray(kinds.keys())))
	_set_here(-15.0)
	var board2 := Contracts.offers_from(Session.system_id())
	check(board2.size() < Contracts._offers(Session.system_id()).size(), "Doubtful: fewer offers (%d of %d)" % [board2.size(), Contracts._offers(Session.system_id()).size()])
	check(Session.people_here().size() <= 2, "and fewer people ask (%d)" % Session.people_here().size())
	_set_here(-30.0)
	check(Session.people_here().is_empty() and Passengers.long_haul().is_empty(), "Unwelcome: nobody asks in person, nobody wants passage")
	check(not Contracts.offers_from(Session.system_id()).is_empty(), "but the board still has freight")
	var cands := Session.crew_candidates()
	check(not cands.is_empty() and cands.all(func(c): return c.has("refuses")), "and nobody at the bar will sign on")
	var r := Session.hire(String(cands[0].id)) if not cands.is_empty() else {"ok": true}
	check(not bool(r.ok), "hiring is refused: %s" % String(r.get("message", "")))
	_set_here(-60.0)
	check(Session.tier_here() == "Barred" and Contracts.offers_from(Session.system_id()).is_empty(), "Barred: no work at all")
	check(Session.rep_fee_mult() > 1.5, "and everything costs %.0f%% more" % ((Session.rep_fee_mult() - 1.0) * 100.0))

	print("species and crew")
	_set_here(0.0)
	var stx := Reputation.state(Session.profile)
	stx.species = {"human": -20.0}
	var c2 := Session.crew_candidates()
	var humans := c2.filter(func(c): return String(c.species) == "human")
	var others := c2.filter(func(c): return String(c.species) != "human")
	check(humans.all(func(c): return c.has("refuses")) and others.all(func(c): return not c.has("refuses")), "with humans thinking badly of you, humans won't sign on (%d), others will (%d)" % [humans.size(), others.size()])
	stx.species = {}

	print("deeds")
	_set_here(0.0)
	var note := Session._add_rep(3)
	check(is_equal_approx(float(Reputation.state(Session.profile).places[String(Session.profile.port_id)]), 3.0) and "Standing +3" in note, "a deed here: %s" % note)
	note = Session._add_rep(12)
	check("You are now Known here" in note, "crossing a tier says so: %s" % note)
	_set_here(0.0)
	note = Session._settle_comms({"fine_rep": -5, "fine_cr": 300, "rep": 0, "notes": []})
	check(Session.standing_parts().authority < -4.9 and is_equal_approx(float(Session.standing_parts().place), 0.0), "a fine goes on the authorities' record, not the port's (%+.1f)" % float(Session.standing_parts().authority))
	var cost := Session.settle_record_cost()
	var cr := int(Session.profile.credits)
	var sr := Session.settle_record()
	check(bool(sr.ok) and int(Session.profile.credits) == cr - cost and Session.settle_record_cost() == 0, "settled for %d cr: %s" % [cost, sr.message])

	print("old saves")
	var old := {"rep": 14, "port_id": "roosevelt_orbital_freight", "system_id": "new_houston"}
	var ost := Reputation.state(old)
	check(is_equal_approx(float(ost.places.roosevelt_orbital_freight), 14.0) and old.has("reputation"), "a save from before 0.20.0 brings its standing home: Known at %s" % Reputation.tier(Reputation.standing(ost, "roosevelt_orbital_freight", 0)))

	print("traffic control")
	_set_here(-60.0)
	Session.flight_job = {}
	var f: Node = load("res://scenes/flight.tscn").instantiate()
	root.add_child(f)
	current_scene = f
	await process_frame
	f.set_process(false)
	f.model.pos = Vector3(0, 0, 1800)
	var rr: Dictionary = f.comms_c.act("control", "clearance")
	check(not bool(rr.ok) and f.comms_c.clear_for == "", "Barred: clearance refused: %s" % rr.message)
	check(f.comms_c.queue.any(func(q): return String(q.text).to_lower().contains("refused") or String(q.text).to_lower().contains("not cleared")), "and control says so: \"%s\"" % String(f.comms_c.queue.back().text if not f.comms_c.queue.is_empty() else ""))
	f.comms_c.queue.clear()
	_set_here(60.0)
	Comms.cfg()["clearance"]["hold_chance"] = 1.0
	rr = f.comms_c.act("control", "clearance")
	check(bool(rr.ok) and f.comms_c.hold.is_empty() and f.comms_c.clear_for != "", "Respected: a priority berth, no holding: %s" % rr.message)
	check(f.comms_c.queue.any(func(q): return (q.get("refs", []) as Array).any(func(x): return String(x.key).begins_with("comms:standing_warm"))), "and a warm word")
	f.queue_free()
	await process_frame
	print("DONE fails=", fails)
	quit(1 if fails > 0 else 0)
