class_name PlaceDesks
extends RefCounted
## What each desk shows when you use it: the freight office, dispatch and foreman (posted work,
## people asking, surface missions), fuel and repairs, the bar, the survey lab and exchange, the suit
## store and the gate aboard. It fills the scene's panel with notes and action buttons.

var sc: PlaceScene   ## the scene this works on


func _init(scene: PlaceScene) -> void:
	sc = scene


func _fill(id: String) -> void:
	match id:
		"freight", "dispatch", "foreman":
			_desk_freight(id)
		"fuel":
			_desk_fuel()
		"yard":
			sc._clear_panel("Shipyard", "Build, refit and fit parts to your ship. The yard can change anything, at a price.")
			sc._action("ENTER THE SHIPYARD", func() -> void:
				Session.profile["location"] = "shipyard"
				Session.save_profile()
				sc._go(Session.YARD_SCENE), not Session.insolvent())
		"bar":
			_desk_bar()
		"lab":
			_desk_sell("Survey lab", "The lab pays well for rock samples and glass crystals. It has no use for salvage or ice.", {"sample": 1.4, "rare": 1.4, "salvage": 0.0, "ice": 0.0})
		"exchange":
			_desk_sell("Ore and parts exchange", "The camp buys anything, cheaply, except ice: the drills need water, and it pays well for that.", {"sample": 0.8, "salvage": 0.9, "ice": 1.3, "rare": 0.8})
		"store":
			_desk_store()
		"gate":
			_desk_gate()


func _desk_freight(id: String) -> void:
	var title: String = {"freight": "Freight office", "dispatch": "Dispatch", "foreman": "Foreman"}[id]
	sc._clear_panel(title)
	if Session.insolvent():
		sc.panel_list.add_child(Brand.note("No one will give a bankrupt captain freight. The bank will take the ship at half price, clear the debt and lend you a starter hauler.", 15))
		sc._action("LET THE BANK STEP IN", func() -> void:
			var r := Session.restructure()
			Session.flash = String(r.message)
			if bool(r.ok):
				sc.get_tree().reload_current_scene())
		return
	var c := Session.active_contract()
	var here := String(Session.profile.get("port_id", ""))
	if not c.is_empty():
		if id != "freight":
			_missions_section()
		var local := bool(c.get("local", false))
		var arrived := String(c.get("status", "")) == "arrived"
		var load_text := "%d passengers aboard" % int(c.seats) if String(c.get("person_kind", "")) == "passenger" else "%.1f t aboard" % float(c.get("accepted_tonnes", c.get("offer", 0.0)))
		sc.panel_list.add_child(Brand.note("ACTIVE: %s, %s." % [String(c.title), load_text], 15))
		var at_start := String(c.get("origin_port_id", "")) == here if local else String(c.get("origin_system_id", "")) == Session.system_id()
		var at_end := (String(c.get("destination_port_id", "")) == here or (bool(c.get("surface", false)) and LocalSpace.is_surface(here))) if local else String(c.get("destination_system_id", "")) == Session.system_id()
		if arrived and at_end and Session.surface_site() == "camp" and String(c.get("person_kind", "")) != "passenger":
			var t := float(c.get("accepted_tonnes", c.get("offer", 0.0)))
			var uc := SurfaceWork.unload_cfg()
			sc._action("PAY THE CAMP CREW TO UNLOAD  %d%% of the pay, %d hours" % [roundi(float(uc.get("camp_crew_share", 0.15)) * 100.0), int(uc.get("camp_crew_hours", 8))], func() -> void:
				var r := Session.deliver_active_contract()
				sc._say(String(r.message))
				sc._refill())
			sc._action("UNLOAD IT YOURSELF  %d crates, in the suit" % SurfaceWork.crates_for(t), func() -> void:
				var r := Session.start_manual_unload()
				if bool(r.ok):
					Session.flight_job = {}
					sc._go(Session.FLIGHT_SCENE)
				else:
					sc._say(String(r.message)))
		elif arrived and at_end:
			sc._action("DELIVER THE LOAD", func() -> void:
				var r := Session.deliver_active_contract()
				sc._say(String(r.message))
				sc._refill())
		elif at_start and not arrived:
			sc._action("FLY THE RUN YOURSELF" if local else "FLY THE JUMP YOURSELF", func() -> void:
				var r := Session.begin_local_flight() if local else Session.begin_jump_flight()
				if bool(r.ok):
					sc._go(Session.FLIGHT_SCENE)
				else:
					sc._say(String(r.message)))
			sc._action("DEPART ON AUTOPILOT", func() -> void:
				var r := Session.depart_active_contract()
				sc._say(String(r.message))
				sc._refill())
			if c.has("due_hour"):
				var hb := People.hard_burn()
				sc._action("HARD BURN ON AUTOPILOT  (%d%% of the time, %d%% of the fuel)" % [roundi(float(hb.time) * 100.0), roundi(float(hb.fuel) * 100.0)], func() -> void:
					var r := Session.depart_active_contract(true)
					sc._say(String(r.message))
					sc._refill())
		return
	if id != "freight":
		_missions_section()
		_people_section()
		sc.panel_list.add_child(Brand.heading("POSTED WORK", 15))
	var offers := Contracts.offers_from(Session.system_id())
	if offers.is_empty():
		sc.panel_list.add_child(Brand.note("Nothing posted here right now. Wait a day at the bunks, or fly empty somewhere busier.", 15))
	var stats := {}
	var loaded := Session._load_ship(SaveSlots.read(Session.slot)) if Session.slot >= 0 else {}
	if not loaded.is_empty():
		stats = Session.ship_stats(loaded.ship)
	for o in offers:
		var job: Dictionary = o
		sc._action(_offer_text(job, stats), func() -> void:
			var r := Session.accept_contract(job)
			sc._say(String(r.message))
			sc._refill())
	sc.panel_list.add_child(Brand.heading("FLY EMPTY", 15))
	if Session.sim != null and not bool(SimWorld.player(Session.sim).get("ftl", true)):
		for s in Session.local_sites():
			var sid := String(s.id)
			sc._action("%s  ·  %.1f km/s  ·  %d h  ·  about %s cr  ·  %d jobs there" % [String(s.name), float(s.dv_kms), int(s.hours), ShipStats.commas(roundi(float(s.cost))), int(s.jobs)], func() -> void:
				var r := Session.local_reposition(sid)
				Session.flash = String(r.message)
				if bool(r.ok):
					sc.get_tree().reload_current_scene()
				else:
					sc._say(String(r.message)))
	elif Session.sim != null:
		for o in SimWorld.destinations(Session.sim).slice(0, 6):
			var sys := String(o.system_id)
			sc._action("%s  ·  %.2f ly  ·  %.1f days  ·  about %s cr" % [String(Worlds.system(sys).get("name", sys)), float(o.ly), float(o.days), ShipStats.commas(roundi(float(o.cost)))], func() -> void:
				var r := Session.travel_empty(sys)
				Session.flash = String(r.message)
				if bool(r.ok):
					sc.get_tree().reload_current_scene()
				else:
					sc._say(String(r.message)))


func _offer_text(c: Dictionary, stats: Dictionary) -> String:
	var goods := Worlds.commodity(String(c.commodity))
	if bool(c.get("local", false)):
		var tag := "SURFACE" if bool(c.get("surface", false)) else "LOCAL"
		var dest := String(LocalSpace.node(String(c.destination_port_id)).get("name", c.destination_port_id))
		var fuel := ""
		if not stats.is_empty():
			fuel = ", fuel about %s cr" % ShipStats.commas(roundi(float(Session.local_trip_cost(stats, float(c.offer), float(c.dv_kms)).total)))
		return "%s  %s  →  %s\n%.1f t  ·  %.1f km/s  ·  %d h  ·  %s cr/t  ·  up to %s cr%s" % [tag, goods.get("name", c.commodity), dest, float(c.offer), float(c.dv_kms), int(c.hours),
				ShipStats.commas(int(c.rate)), ShipStats.commas(roundi(float(c.offer) * float(c.rate))), fuel]
	var port := Worlds.port(String(c.destination_port_id))
	return "%s  →  %s\n%.1f t  ·  %.2f ly  ·  %s cr/t  ·  up to %s cr" % [goods.get("name", c.commodity), port.get("name", c.destination_system_id), float(c.offer), float(c.distance_ly),
			ShipStats.commas(int(c.rate)), ShipStats.commas(roundi(float(c.offer) * float(c.rate)))]


## People asking in person (People): rush jobs, passengers and sealed crates.
func _people_section() -> void:
	var rep := int(Session.profile.get("rep", 0))
	var nxt := People.next_standing(rep)
	sc.panel_list.add_child(Brand.heading("PEOPLE WITH WORK", 15))
	sc.panel_list.add_child(Brand.note("Your standing: %s (%d%s). Standing raises what people offer, up to +15%%." % [People.standing(rep), rep,
			", %s at %d" % [People.standing(nxt), nxt] if nxt > 0 else ""], 13))
	var busy := not Session.active_contract().is_empty()
	var people := Session.people_here()
	if people.is_empty():
		sc.panel_list.add_child(Brand.note("No one is asking today.", 14))
	for j in people:
		var job: Dictionary = j
		var tag := String(job.person_kind).to_upper()
		var pay := int(job.fare) if job.person_kind == "passenger" else roundi(float(job.offer) * float(job.rate))
		var size := "%d seat%s" % [int(job.seats), "" if int(job.seats) == 1 else "s"] if job.person_kind == "passenger" else "%.1f t" % float(job.offer)
		var txt := "%s  %s: \"%s\"\n%s  ·  %s  ·  %d h  ·  pays %s cr  ·  %s" % [tag, String(job.person), String(job.line), String(job.title), size, int(job.hours),
				ShipStats.commas(pay), String(job.get("locked", job.blurb))]
		sc._action(txt, func() -> void:
			var r := Session.accept_contract(job)
			sc._say(String(r.message))
			sc._refill(), not busy and not job.has("locked"))


func _desk_fuel() -> void:
	var mult := Session.site_fuel_mult()
	sc._clear_panel("Fuel and repairs", "Fuel here costs %d%% of the system price (%s). You are charged for what you burn when you leave or land." % [roundi(mult * 100.0),
			"cheap: a fuel depot" if mult < 0.95 else ("dear: it has to come up from the surface or down from orbit" if mult > 1.2 else "the usual")])
	var dmg := float(Session.profile.get("hull_damage", 0.0))
	sc.panel_list.add_child(Brand.note("Hull: %d%%%s" % [roundi((1.0 - dmg) * 100.0), "" if dmg <= 0.0 else ". A damaged hull loses thrust until it is fixed."], 15))
	var cost := Session.repair_cost()
	sc._action("REPAIR THE HULL  %s cr" % ShipStats.commas(cost) if cost > 0 else "THE HULL NEEDS NO WORK", func() -> void:
		var r := Session.repair_hull()
		sc._say(String(r.message))
		sc._refill(), cost > 0)
	var f := Session.finds_aboard()
	if int(f.value) > 0:
		sc._action("SELL YOUR FINDS  %s cr  (%s)" % [ShipStats.commas(int(f.value)), SurfaceFinds.describe(f)], func() -> void:
			var r := Session.sell_finds()
			sc._say(String(r.message))
			sc._refill())


func _desk_bar() -> void:
	sc._clear_panel("Bar and bunks", "Captains and crews pass through here between jobs, and some of them have work that never reaches the board.")
	_people_section()
	sc.panel_list.add_child(Brand.heading("BUNKS", 15))
	var idle := Session.active_contract().is_empty() and Session.sim != null and not Session.insolvent()
	sc._action("RENT A BUNK AND WAIT A DAY", func() -> void:
		var r := Session.wait_days(1)
		Session.flash = String(r.message)
		if bool(r.ok):
			sc.get_tree().reload_current_scene()
		else:
			sc._say(String(r.message)), idle)


func _desk_sell(title: String, note: String, rates: Dictionary) -> void:
	sc._clear_panel(title, note)
	var f := Session.finds_aboard()
	var value := Session.finds_value(rates)
	sc.panel_list.add_child(Brand.note("In your locker: %s." % SurfaceFinds.describe(f), 15))
	sc._action("SELL  %s cr" % ShipStats.commas(value) if value > 0 else "NOTHING THEY WANT", func() -> void:
		var r := Session.sell_finds(rates)
		sc._say(String(r.message))
		sc._refill(), value > 0)


func _desk_store() -> void:
	var owned := Session.gear_owned()
	sc._clear_panel("Suit store", "Kit for working outside. Your suit holds %s of air." % SurfaceWork.clock(SurfaceWork.o2_capacity(owned)))
	for gid in SurfaceWork.GEAR_ORDER:
		var g := SurfaceWork.gear(gid)
		var have: bool = gid in owned
		var blocked: bool = g.has("needs") and not String(g.needs) in owned
		var txt := "%s  ·  %s\n%s" % [String(g.name).to_upper(), "OWNED" if have else "%s cr" % ShipStats.commas(int(g.price)), String(g.blurb)]
		if blocked:
			txt += "  (needs the %s)" % String(SurfaceWork.gear(String(g.needs)).name).to_lower()
		var id: String = gid
		sc._action(txt, func() -> void:
			var r := Session.buy_gear(id)
			sc._say(String(r.message))
			sc._refill(), not have and not blocked)


## Timed jobs on foot around this site (SurfaceWork), and the one you hold.
func _missions_section() -> void:
	if Session.surface_site() == "":
		return
	sc.panel_list.add_child(Brand.heading("SURFACE WORK", 15))
	var held := Session.mission()
	if not held.is_empty():
		var left := 0
		for d in held.done:
			if not bool(d):
				left += 1
		sc.panel_list.add_child(Brand.note("HELD: %s, %d of %d left, %s on the clock (it runs while you are outside). Pays %s cr. Suit up at the %s." % [
				String(held.title), left, held.done.size(), SurfaceWork.clock(float(held.limit_s) - float(held.get("elapsed_s", 0.0))),
				ShipStats.commas(int(held.pay)), "airlock"], 14))
		sc._action("GIVE IT UP  (standing −2)", func() -> void:
			var r := Session.fail_mission("given up")
			sc._say(String(r.message))
			sc._refill())
		return
	for mm in Session.missions_here():
		var m: Dictionary = mm
		sc._action("%s  ·  %d m on foot  ·  %s on the clock  ·  pays %s cr\n%s" % [String(m.title).to_upper(), int(m.walk_m), SurfaceWork.clock(float(m.limit_s)),
				ShipStats.commas(int(m.pay)), "Taken." if bool(m.taken) else String(m.blurb)], func() -> void:
			var r := Session.take_mission(m)
			sc._say(String(r.message))
			sc._refill(), not bool(m.taken))


func _desk_gate() -> void:
	sc._clear_panel("Your ship: %s" % Session.ship_label(), "Through the gate and aboard.")
	var c := Session.active_contract()
	var here := String(Session.profile.get("port_id", ""))
	if not c.is_empty() and String(c.get("status", "")) != "arrived":
		var local := bool(c.get("local", false))
		var at_start := String(c.get("origin_port_id", "")) == here if local else String(c.get("origin_system_id", "")) == Session.system_id()
		if at_start:
			sc._action("FLY THE RUN" if local else "FLY THE JUMP", func() -> void:
				var r := Session.begin_local_flight() if local else Session.begin_jump_flight()
				if bool(r.ok):
					sc._go(Session.FLIGHT_SCENE)
				else:
					sc._say(String(r.message)))
	sc._action("TAKE THE HELM", func() -> void:
		Session.flight_job = {}
		sc._go(Session.FLIGHT_SCENE), not Session.insolvent())
	sc._action("GO ABOARD AND WALK THE SHIP", func() -> void:
		Session.flight_job = {}
		Session.walk_aboard = true
		sc._go(Session.FLIGHT_SCENE), not Session.insolvent())
	if Session.surface_site() != "":
		sc._action("SUIT UP AND GO OUTSIDE  (%s of air)" % SurfaceWork.clock(SurfaceWork.o2_capacity(Session.gear_owned())), func() -> void:
			Session.flight_job = {}
			Session.suit_up = true
			sc._go(Session.FLIGHT_SCENE), not Session.insolvent())
