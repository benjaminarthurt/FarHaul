extends SceneTree
## Rival salvage crews and claim beacons (scripts/comms/rivals.gd): beaconing a wreck, a rival turning up
## and stripping it, warning them off, splitting it, claim jumping, and buying beacons.
## Run: godot --headless --path . --script res://tests/test_rivals.gd
var fails := 0
func check(ok: bool, msg: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + msg)
	if not ok:
		fails += 1


func _initialize() -> void:
	SaveSlots.dir = "user://test_saves_rivals_%d" % OS.get_process_id()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SaveSlots.dir))
	process_frame.connect(_run, CONNECT_ONE_SHOT)


func _contact(f: Node, kind: String) -> Dictionary:
	for c in f.comms_c.contacts():
		if String(c.kind) == kind:
			return c
	return {}


func _steps(f: Node, n: int, dt: float) -> void:
	for i in n:
		f.comms_c.step(dt, 0.0)


func _taken(d: Dictionary) -> int:
	return (d.points as Array).filter(func(p): return bool(p.taken)).size()


func _run() -> void:
	Session.begin_new(1, "Tester", "human", "normal", "roosevelt_independent_yards")
	Session.flight_job = {}
	var f: Node = load("res://scenes/flight.tscn").instantiate()
	root.add_child(f)
	current_scene = f
	await process_frame
	f.set_process(false)
	var t: Traffic = f.traffic_c
	t.cfg["derelicts"]["chance"] = 1.0
	t.rebuild(String(Session.profile.port_id))
	var rc := Rivals.cfg()
	rc["chance"] = 1.0
	rc["there_first"] = 0.0
	rc["warn_first"] = 1.0
	rc["warn_second"] = 0.0
	f.comms_c.rivals = Rivals.new(f.comms_c)   # forget what the first frame rolled, before the wrecks were forced
	var d: Dictionary = t.derelicts[0]
	var w: NpcShip = d.ship
	print("a claim beacon")
	f.model.pos = w.global_position + Vector3(0, 0, 900)
	f.model.vel = Vector3.ZERO
	_steps(f, 2, 0.1)
	var r: Dictionary = f.comms_c.rivals._rival_for(d)
	check(not r.is_empty() and String(r.state) == "coming", "this wreck draws a rival, not here yet")
	var wc := _contact(f, "wreck")
	check(not wc.is_empty() and bool(wc.options[0].enabled), "the wreck is on the radio: %s" % String(wc.options[0].text) if not wc.is_empty() else "no wreck contact")
	var n0 := Rivals.beacons()
	var res: Dictionary = f.comms_c.act(String(wc.id), "beacon")
	check(bool(res.ok) and Rivals.beacons() == n0 - 1 and Rivals.claim_of(String(d.id_base)) == "you", "beacon away: %s" % res.message)
	check(w.get_node_or_null("ClaimBeacon") != null and w.title.contains("YOUR CLAIM"), "a green light on the wreck, and the tag says so")

	print("they turn up")
	for i in 400:
		f.comms_c.step(2.0, 0.0)
		if String(r.state) == "working":
			break
	check(String(r.state) == "working" and r.ship != null, "the salvage tug arrives and parks alongside")
	check(f.comms_c.queue.any(func(l): return String(l.who).begins_with("Salvage tug")) or f.comms_c.log.any(func(l): return String(l.who).begins_with("Salvage tug")), "and calls in about your beacon")
	var before := _taken(d)
	_steps(f, 24, 5.0)
	var cut := _taken(d) - before
	check(cut >= 2, "and starts cutting: %d pieces gone" % cut)
	var tk: Array = Session.profile.get("salvage_taken", [])
	check((d.points as Array).filter(func(p): return bool(p.taken)).all(func(p): return tk.has(String(p.id))), "and they stay gone")
	var rv := _contact(f, "rival")
	check(not rv.is_empty(), "the rival's on the radio: %s" % String(rv.get("name", "")))
	res = f.comms_c.act(String(rv.id), "warn")
	check(bool(res.ok) and String(r.state) == "leaving", "your beacon was first: told to clear off, they go (%s)" % res.message)
	before = _taken(d)
	_steps(f, 30, 5.0)
	check(_taken(d) == before, "and stop cutting")

	print("theirs first")
	f.comms_c.rivals = Rivals.new(f.comms_c)
	f.comms_c.rivals._seen.clear()
	rc["there_first"] = 1.0
	var d2: Dictionary = t.derelicts[1] if t.derelicts.size() > 1 else t.derelicts[0]
	if d2 == d:
		var cl: Dictionary = Session.profile.get("claims", {})
		cl.erase(String(d.id_base))
	f.model.pos = (d2.ship as NpcShip).global_position + Vector3(0, 0, 900)
	_steps(f, 2, 0.1)
	var r2: Dictionary = f.comms_c.rivals._rival_for(d2)
	check(not r2.is_empty() and String(r2.state) == "working" and Rivals.claim_of(String(d2.id_base)) == "them", "a tug already there, beacon on it")
	check(_contact(f, "wreck").is_empty() or String(_contact(f, "wreck").id) != "wreck:" + String(d2.id_base), "no beaconing a claimed wreck")
	res = f.comms_c.act("rival:" + String(d2.id_base), "warn")
	check(bool(res.ok) and String(r2.state) == "working", "told to clear off, they don't: %s" % res.message)
	var p: Dictionary = (d2.points as Array).filter(func(x): return not bool(x.taken) and String(x.kind) == "panel")[0]
	t.take(p)
	var st: Dictionary = f.comms_c.settlement()
	check(int(st.rep) <= -2 and (st.notes as Array).any(func(x): return String(x).contains("claim-jumping")), "cut a panel off their wreck anyway: %s" % String((st.notes as Array).back()))

	print("half each")
	f.comms_c.rivals = Rivals.new(f.comms_c)
	(Session.profile.get("claims", {}) as Dictionary).erase(String(d2.id_base))
	f.comms_c.rivals._seen.clear()
	_steps(f, 2, 0.1)
	var r3: Dictionary = f.comms_c.rivals._rival_for(d2)
	res = f.comms_c.act("rival:" + String(d2.id_base), "split")
	var share: Array = r3.share
	check(bool(res.ok) and not share.is_empty(), "split: %s" % res.message)
	var mine := (d2.points as Array).filter(func(x): return not bool(x.taken) and String(x.kind) in ["panel", "item"] and not share.has(String(x.id)))
	_steps(f, 80, 5.0)
	check(mine.all(func(x): return not bool(x.taken)), "they leave your half alone (%d pieces)" % mine.size())
	check((d2.points as Array).filter(func(x): return share.has(String(x.id))).any(func(x): return bool(x.taken)), "and take theirs")
	var jumped0: int = f.comms_c.rivals.jumped
	if not mine.is_empty():
		t.take(mine[0])
	check(f.comms_c.rivals.jumped == jumped0, "taking from your own half is fine")

	print("the shop")
	f.queue_free()
	await process_frame
	var have := Rivals.beacons()
	var cr0 := int(Session.profile.credits)
	res = Session.buy_claim_beacons(1)
	check(bool(res.ok) and Rivals.beacons() == have + 1 and int(Session.profile.credits) == cr0 - Session.claim_beacon_price(), res.message)
	res = Session.buy_claim_beacons(10)
	check(Rivals.beacons() == int(rc.get("beacon_max", 4)), "the rack holds %d" % Rivals.beacons())
	print("DONE fails=", fails)
	quit(1 if fails > 0 else 0)
