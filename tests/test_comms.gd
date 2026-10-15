extends SceneTree
## Comms (scripts/comms/): radio voices, who's in range, clearance (and the hold, and the fine without it),
## fuel off a hauler, news, tows when you're dry, a distress call on a run, and the settling up at the end.
## Run: godot --headless --path . --script res://tests/test_comms.gd
var fails := 0
func check(ok: bool, msg: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + msg)
	if not ok:
		fails += 1


func _initialize() -> void:
	SaveSlots.dir = "user://test_saves_comms_%d" % OS.get_process_id()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SaveSlots.dir))
	process_frame.connect(_run, CONNECT_ONE_SHOT)


func _contact(f: Node, kind: String) -> Dictionary:
	for c in f.comms_c.contacts():
		if String(c.kind) == kind:
			return c
	return {}


func _opt(c: Dictionary, id: String) -> Dictionary:
	for o in c.get("options", []):
		if String(o.id) == id:
			return o
	return {}


## Let the radio say everything queued (the voices are made on a worker thread).
func _drain(f: Node) -> void:
	for i in 400:
		f.comms_c.step(0.05, 0.5)
		if f.comms_c.queue.is_empty() and f.comms_c.current.is_empty() and f.comms_c._task < 0:
			return
		await process_frame


func _flight() -> Node:
	var f: Node = load("res://scenes/flight.tscn").instantiate()
	root.add_child(f)
	current_scene = f
	await process_frame
	f.set_process(false)
	return f


func _run() -> void:
	print("voices")
	var kesh := RadioVoice.voice("kesh", 1)
	var ilyan := RadioVoice.voice("ilyan", 1)
	check(float(kesh.f0) < 110.0 and float(ilyan.f0) > 200.0 and float(kesh.rate) < float(ilyan.rate), "a Kesh speaks low and slow (%.0f Hz), an Ilyan high and quick (%.0f Hz)" % [float(kesh.f0), float(ilyan.f0)])
	check(RadioVoice.voice("vey", 42).f0 == RadioVoice.voice("vey", 42).f0, "the same speaker sounds the same every time")
	var t0 := Time.get_ticks_msec()
	var w := RadioVoice.speech("Freighter, you're cleared to berth four. Try to hit it.", kesh, 0.3)
	var ms := Time.get_ticks_msec() - t0
	check(w.get_length() > 1.0 and w.get_length() < 8.0, "a line said over the radio: %.1f s of babble, squelch and a roger beep (made in %d ms)" % [w.get_length(), ms])
	check(RadioVoice.chime().get_length() > 0.2 and RadioVoice.sos().get_length() > 1.5, "the hail chime and the SOS beacon")

	print("at the station")
	Session.begin_new(1, "Tester", "human", "normal", "roosevelt_independent_yards")
	Session.profile["ship_name"] = "Second Thoughts"
	Session.flight_job = {}
	var f := await _flight()
	f.model.pos = Vector3(0, 0, 1800)
	var cs: Array = f.comms_c.contacts()
	var ctl := _contact(f, "control")
	check(not ctl.is_empty() and String(ctl.name).contains("Traffic"), "traffic control is on the list: %s" % String(ctl.get("name", "")))
	var hauler := _contact(f, "hauler")
	check(not hauler.is_empty(), "and the haulers parked by the port: %s" % ", ".join(cs.map(func(c): return String(c.name))))
	Comms.cfg()["clearance"]["hold_chance"] = 1.0
	var r: Dictionary = f.comms_c.act("control", "clearance")
	check(bool(r.ok) and not f.comms_c.hold.is_empty(), "asked for clearance and told to hold: %s" % r.message)
	for i in 4000:
		f.traffic_c.step(0.25)
		f.comms_c.step(0.25, 0.0)
		if f.comms_c.hold.is_empty():
			break
	check(f.comms_c.clear_for != "" and f.comms_c.berth > 0, "the other ship comes out and you're cleared: berth %d" % f.comms_c.berth)
	check(f.station.get_node_or_null("ClearanceLamps") != null, "the collar's lamps are green")
	await _drain(f)
	print("    log: ", f.comms_c.log)
	check(f.comms_c.log.any(func(l): return String(l.who) == "YOU") and f.comms_c.log.any(func(l): return String(l.text).to_lower().contains("berth %d" % f.comms_c.berth)), "and the log has both sides of it")
	r = f.comms_c.act(String(hauler.id), "news")
	await _drain(f)
	check(bool(r.ok) and not bool(_opt(_contact(f, "hauler"), "news").get("enabled", true)) or String(hauler.id) != String(_contact(f, "hauler").id), "news from a hauler: \"%s\"" % String(f.comms_c.log.back().text))

	print("fuel off a hauler")
	f.model.fuel_t -= 6.0
	f.model.fuel_burned_t += 6.0
	var before: float = f.model.fuel_t
	hauler = _contact(f, "hauler")
	r = f.comms_c.act(String(hauler.id), "fuel")
	check(bool(r.ok), r.message)
	f.model.vel = Vector3.ZERO
	f.model.throttle = 0.0
	for i in 2000:
		f.comms_c.step(0.1, 0.0)
		if bool(f.comms_c.fuel_deal.get("done", false)) or String(f.comms_c.fuel_deal.get("stage", "")) == "leave":
			break
	var got: float = f.model.fuel_t - before
	var st: Dictionary = f.comms_c.settlement()
	check(got > 1.0 and absf(float(st.fuel_bought_t) - got) < 0.01 and int(st.fuel_bought_cr) == roundi(got * float(f.comms_c.fuel_deal.price)), "%.1f t came across for %s cr" % [got, ShipStats.commas(int(st.fuel_bought_cr))])
	check(absf(f.model.fuel_burned_t - (6.0 - got)) < 0.01, "and the port won't charge for it again")
	check(float(f.comms_c.fuel_deal.price) > Comms.port_fuel_price(), "dearer than the port (%s against %.0f cr/t)" % [ShipStats.commas(int(f.comms_c.fuel_deal.price)), Comms.port_fuel_price()])

	print("docking, cleared and not")
	var rep0 := int(Session.profile.get("rep", 0))
	f.comms_c.arrived(f.comms_c._station_id())
	check(int(f.comms_c.settle.fine_cr) == 0, "cleared: no fine")
	f.comms_c.clear_for = ""
	f.comms_c.arrived(f.comms_c._station_id())
	st = f.comms_c.settlement()
	check(int(st.fine_cr) > 0 and (st.notes as Array).size() > 0, "docked unannounced: %s cr and a lecture" % ShipStats.commas(int(st.fine_cr)))
	var cr0 := int(Session.profile.credits)
	Session.flight_extra = {"comms": st}
	var msg := Session.finish_flight(0.0, 60.0, 0.0)
	check(msg.contains("Fuel off a hauler") and msg.contains("Traffic") and int(Session.profile.get("rep", 0)) == maxi(0, rep0 - 1), "settled when the flight ends: %s" % msg.strip_edges())
	check(int(Session.profile.credits) < cr0, "and paid for")
	f.queue_free()
	await process_frame

	print("dry")
	f = await _flight()
	f.model.pos = Vector3(0, 0, 3000)
	f.model.fuel_burned_t += f.model.fuel_t
	f.model.fuel_t = 0.0
	var tug := _contact(f, "tug")
	check(not tug.is_empty(), "out of fuel: the port tug answers by relay")
	hauler = _contact(f, "hauler")
	check(not _opt(hauler, "tow").is_empty(), "and a hauler offers a tow: %s" % String(_opt(hauler, "tow").get("text", "")))
	f.queue_free()
	await process_frame

	print("a distress call")
	var job: Dictionary = {}
	for o in Contracts.offers_from(Session.system_id()):
		if bool(o.get("local", false)) and not bool(o.get("surface", false)) and String(LocalSpace.node(String(o.destination_port_id)).get("kind", "")) != "moon":
			job = o
			break
	var data := SaveSlots.read(Session.slot)   # a liner: beds for whoever needs one
	var liner := ShipData.new(ModuleLibrary.new())
	ShipPresets.build(liner, ShipPresets.STARTER_LINER)
	data["modules"] = (JSON.parse_string(liner.to_json()) as Dictionary)["modules"]
	data["cargo"] = CargoManifest.new(liner).to_dict()
	SaveSlots.write(Session.slot, data)
	Session.accept_contract(job)
	var bl := Session.begin_local_flight()
	check(bool(bl.ok), "a local run, in a liner: %s" % bl.message)
	Comms.cfg()["distress"]["chance"] = 1.0
	f = await _flight()
	f.model.pos = Vector3(0, 0, 4000)
	f._process(0.016)
	f.comms_c.step(0.1, 0.0)
	var dc := _contact(f, "distress")
	var mayday: Array = f.comms_c.queue.filter(func(l): return String(l.who).begins_with("DISTRESS"))
	check(not dc.is_empty() and not mayday.is_empty(), "a mayday on the route: %s" % (String(mayday[0].text) if not mayday.is_empty() else "none"))
	if not dc.is_empty():
		check(not bool(_opt(dc, "crew").enabled), "too far to help yet: %s" % String(_opt(dc, "crew").why))
		var s: NpcShip = f.comms_c.distress.ship
		f.model.vel = (s.global_position - f.model.pos).normalized() * 500.0   # cruising towards them
		var bt: Vector3 = f.traffic_c.brake_target(f.xfer.target)
		var wreck_first: bool = f.traffic_c.derelicts.any(func(d): return bool(d.deep) and (d.ship as NpcShip).global_position.distance_to(bt) < 200.0 and (d.ship as NpcShip).global_position.distance_to(f.model.pos) < s.global_position.distance_to(f.model.pos))
		check(f.traffic_c.stops.has(s) and (bt.distance_to(s.global_position) < 200.0 or wreck_first), "the braking autopilot stops you at them, or at a wreck that's nearer (%.0f m off them; they're %.0f km away, the target %.0f km)" % [bt.distance_to(s.global_position), s.global_position.distance_to(f.model.pos) / 1000.0, f.xfer.target.distance_to(f.model.pos) / 1000.0])
		f.model.pos = s.global_position + Vector3(0, 0, 80)
		f.model.vel = Vector3.ZERO
		dc = _contact(f, "distress")
		var n := int(f.comms_c.distress.crew)
		var res0 := (Session.profile.get("rescued", []) as Array).size()
		if bool(_opt(dc, "crew").enabled):
			r = f.comms_c.act("distress", "crew")
			check(bool(r.ok) and (Session.profile.get("rescued", []) as Array).size() == res0 + n, "%s" % r.message)
		else:
			check(false, "room for %d aboard a liner: %s" % [n, String(_opt(dc, "crew").why)])
		check(int(f.comms_c.settlement().rep) > 0, "and standing for it")
		f.comms_c.distress["helped"] = false
		check(int(f.comms_c.settlement().rep) < int(f.comms_c.settle.rep) + 1 and (f.comms_c.settlement().notes as Array).any(func(x): return String(x).contains("mayday")), "fly past instead and word gets round")
	f.queue_free()
	await process_frame
	print("DONE fails=", fails)
	quit(1 if fails > 0 else 0)
