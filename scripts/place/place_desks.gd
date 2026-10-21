class_name PlaceDesks
extends RefCounted
## What each desk shows when you use it: the freight office, dispatch and foreman (posted work,
## people asking, surface missions), fuel and repairs, the bar, the survey lab and exchange, the suit
## store and the gate aboard. It fills the scene's panel with notes and action buttons.

var sc: PlaceScene   ## the scene this works on
var _letting_go := ""  ## crew id asked to be let go once: a second click does it
var _cancel_asked := false   ## cancelling the contract asked once: a second click does it
var _standing_open := false  ## the standing section shows who thinks what


func _init(scene: PlaceScene) -> void:
	sc = scene


func _fill(id: String) -> void:
	match id:
		"freight", "dispatch", "foreman":
			_desk_freight(id)
			if id == "freight":
				_authority_section()
				_salvage_section("cargo")
				sc._action("READ THE TRADE REPORT  (N anywhere)", func() -> void:
					var r := TradeReport.find(sc.get_tree())
					if r != null:
						r.open())
			_standing_section(id == "freight")
		"fuel":
			_desk_fuel()
		"yard":
			sc._clear_panel("Shipyard", "Build, refit and fit parts to your ship. The yard can change anything except the price.")
			sc._action("ENTER THE SHIPYARD", func() -> void:
				Session.profile["location"] = "shipyard"
				Session.save_profile()
				sc._go(Session.YARD_SCENE), not Session.insolvent())
			_salvage_section("parts")
		"bar":
			_desk_bar()
		"lab":
			_desk_sell("Survey lab", "The lab pays well for rock samples and glass crystals. Salvage and ice? Science has standards.", {"sample": 1.4, "rare": 1.4, "salvage": 0.0, "ice": 0.0})
		"exchange":
			_desk_sell("Ore and parts exchange", "The camp buys anything, cheaply. Ice is the exception: the drills drink water, so it pays well.", {"sample": 0.8, "salvage": 0.9, "ice": 1.3, "rare": 0.8})
		"store":
			_desk_store()
		"gate":
			_desk_gate()
		"strip":
			_desk_strip()


func _desk_freight(id: String) -> void:
	var title: String = {"freight": "Freight office", "dispatch": "Dispatch", "foreman": "Foreman"}[id]
	sc._clear_panel(title)
	if Session.insolvent():
		sc.panel_list.add_child(Brand.note("No one gives freight to a bankrupt captain. The bank will take the ship at half price, clear the debt and lend you a starter hauler. It's very generous with your ship.", 15))
		sc._action("LET THE BANK STEP IN", func() -> void:
			var r := Session.restructure()
			Session.flash = String(r.message)
			if bool(r.ok):
				sc.get_tree().reload_current_scene())
		return
	if Session.sim != null:
		for st in Hazards.known(Session.system_id(), Session.sim.now_hour()):
			sc.panel_list.add_child(Brand.note("Space weather: a solar storm here, %s. In port you're shielded; out there the radiators cook. The other haulers will be sitting it out." % Hazards.describe(st, Session.sim.now_hour()), 14))
		var here_kind := String(LocalSpace.node(String(Session.profile.get("port_id", ""))).get("kind", ""))
		if Planets.is_planet_kind(here_kind):
			var wx := Planets.weather(Session.system_id(), here_kind, Session.sim.now_hour())
			if float(wx.speed) >= 17.0:
				sc.panel_list.add_child(Brand.note("Weather: %s. The pads stay open. Coming in or lifting off, the gusts will push you about, and landing fuel goes on fighting them." % Planets.describe_weather(wx), 14))
	if id == "freight" and Session.site_has("passengers"):
		_passengers_section(true)
	var c := Session.active_contract()
	var here := String(Session.profile.get("port_id", ""))
	if not c.is_empty():
		if id != "freight":
			_missions_section()
			_people_section()   # passengers can still ride along
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
			var unfit := Session.depart_block()
			if unfit != "":   # say what's wrong before offering buttons that won't work
				var warn := Brand.note(unfit, 14)
				warn.add_theme_color_override("font_color", Color(0.95, 0.55, 0.4))
				warn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
				sc.panel_list.add_child(warn)
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
			sc._action(("SURE? CANCEL IT: the load goes back, %s cr fee%s" % [ShipStats.commas(Session.cancel_fee()), ", and they'll remember" if String(c.get("person_kind", "")) != "" else ""]) if _cancel_asked
					else "CANCEL THIS CONTRACT  (%s cr fee)" % ShipStats.commas(Session.cancel_fee()), func() -> void:
				if not _cancel_asked:
					_cancel_asked = true
					sc._refill()
					return
				_cancel_asked = false
				var r := Session.cancel_contract()
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
	if offers.is_empty() and Session.tier_here() == "Barred":
		sc.panel_list.add_child(Brand.note("Nothing for you. The clerk is very busy not looking up. You're Barred here: settle your record with the authorities, let it fade, or take your custom somewhere that hasn't heard yet.", 15))
	elif offers.is_empty():
		sc.panel_list.add_child(Brand.note("Nothing posted right now. Wait a day at the bunks, or fly empty somewhere less sleepy.", 15))
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
		var tag := "FRESH" if bool(c.get("fresh", false)) else "PLANET" if bool(c.get("planet", false)) else "SURFACE" if bool(c.get("surface", false)) else "LOCAL"
		var dest := String(LocalSpace.node(String(c.destination_port_id)).get("name", c.destination_port_id))
		var fuel := ""
		if not stats.is_empty():
			fuel = ", fuel about %s cr" % ShipStats.commas(roundi(float(Session.local_trip_cost(stats, float(c.offer), float(c.dv_kms), String(c.destination_port_id)).total)))
		return "%s  %s  →  %s\n%.1f t  ·  %.1f km/s  ·  %d h  ·  %s cr/t  ·  up to %s cr%s" % [tag, goods.get("name", c.commodity), dest, float(c.offer), float(c.dv_kms), int(c.hours),
				ShipStats.commas(int(c.rate)), ShipStats.commas(roundi(float(c.offer) * float(c.rate))), fuel]
	var port := Worlds.port(String(c.destination_port_id))
	return "%s  →  %s\n%.1f t  ·  %.2f ly  ·  %s cr/t  ·  up to %s cr" % [goods.get("name", c.commodity), port.get("name", c.destination_system_id), float(c.offer), float(c.distance_ly),
			ShipStats.commas(int(c.rate)), ShipStats.commas(roundi(float(c.offer) * float(c.rate)))]


## People asking in person (People): rush jobs, passengers and sealed crates.
func _people_section() -> void:
	var rep := Session.standing_here()
	sc.panel_list.add_child(Brand.heading("PEOPLE WITH WORK", 15))
	sc.panel_list.add_child(Brand.note(_standing_line(rep), 13))
	var busy := not Session.active_contract().is_empty()
	var people := Session.people_here()
	var st := {}
	var ld := Session._load_ship(SaveSlots.read(Session.slot)) if Session.slot >= 0 else {}
	if not ld.is_empty():
		st = Session.ship_stats(ld.ship)
	if people.is_empty() and not Reputation.at_least(rep, "Doubtful"):
		sc.panel_list.add_child(Brand.note("Nobody asks. A few people look at you, then at each other. Word has got around.", 14))
	elif people.is_empty():
		sc.panel_list.add_child(Brand.note("No one is asking today.", 14))
	for j in people:
		var job: Dictionary = j
		if String(job.person_kind) == "passenger":   # they ride along: a contract on doesn't stop them
			var why := Passengers.why_not(job, st) if not st.is_empty() else ""
			sc._action(Passengers.offer_text(job, st) + ("\n" + why if why != "" else ""), func() -> void:
				var r := Session.accept_contract(job)
				sc._say(String(r.message))
				sc._refill(), not job.has("locked"))
			continue
		var tag := String(job.person_kind).to_upper()
		var pay := int(job.fare) if job.person_kind == "passenger" else roundi(float(job.offer) * float(job.rate))
		var size := "%d seat%s" % [int(job.seats), "" if int(job.seats) == 1 else "s"] if job.person_kind == "passenger" else "%.1f t" % float(job.offer)
		var txt := "%s  %s: \"%s\"\n%s  ·  %s  ·  %d h  ·  pays %s cr  ·  %s" % [tag, String(job.person), String(job.line), String(job.title), size, int(job.hours),
				ShipStats.commas(pay), String(job.get("locked", job.blurb))]
		sc._action(txt, func() -> void:
			var r := Session.accept_contract(job)
			sc._say(String(r.message))
			sc._refill(), not busy and not job.has("locked"))


## Who thinks what of you (Reputation), and, at a port's freight office, settling your record with the
## system's authorities.
func _standing_section(authority_desk: bool) -> void:
	if Session.slot < 0:
		return
	var p := Session.standing_parts()
	var tier := Reputation.tier(float(p.total))
	sc.panel_list.add_child(Brand.heading("YOUR STANDING", 15))
	sc.panel_list.add_child(Brand.note("%s here (%d). %s Fees and fuel %s." % [tier, roundi(float(p.total)), Reputation.tier_note(tier),
			_pct(Reputation.fee_mult(float(p.total)))], 14))
	sc._action(("HIDE WHO THINKS WHAT" if _standing_open else "SEE WHO THINKS WHAT"), func() -> void:
		_standing_open = not _standing_open
		sc._refill())
	if _standing_open:
		var sys := Session.system_id()
		var st := Reputation.state(Session.profile)
		var now := Session._now_h()
		var who := PackedStringArray()
		for sp in Reputation.peoples(sys):
			who.append(Session._species_plural(String(sp)))
		var lines := PackedStringArray([
			"This place: %+d, for the work you've done here." % roundi(float(p.place)),
			"Its people (%s): %+d, as word has reached them." % [", ".join(who), roundi(float(p.species))],
			"The %s authorities: %+d, fines and rescues on the record." % [String(Worlds.system(sys).get("name", sys)), roundi(float(p.authority))]])
		var views := PackedStringArray()
		for sp in ["human", "kesh", "ilyan", "vey", "orun"]:
			views.append("%s %+d" % [String(Worlds.species(sp).get("name", sp)), roundi(Reputation.species_view(st, sp, sys, now, Session.sim))])
		lines.append("What each people thinks, as heard here: %s." % ", ".join(views))
		var travelling: int = (st.log as Array).size()   # deeds not yet heard everywhere
		if travelling > 0:
			lines.append("%d thing%s you did %s still on the way to other systems." % [travelling, "" if travelling == 1 else "s", "is" if travelling == 1 else "are"])
		var known := []
		for site in (st.places as Dictionary).keys():
			if String(site) != String(Session.profile.get("port_id", "")) and absf(float(st.places[site])) >= 1.0:
				known.append(String(site))
		known.sort_custom(func(a: String, b: String) -> bool: return absf(float(st.places[a])) > absf(float(st.places[b])))
		var elsewhere := PackedStringArray()
		for site in known.slice(0, 6):
			elsewhere.append("%s: %s" % [String(LocalSpace.node(site).get("name", site)), Session.tier_here(site)])
		if not elsewhere.is_empty():
			lines.append("Elsewhere: %s." % "; ".join(elsewhere))
		sc.panel_list.add_child(Brand.note("\n".join(lines), 13))
	var cost := Session.settle_record_cost()
	if cost > 0:
		if authority_desk:
			sc._action("SETTLE YOUR RECORD WITH THE AUTHORITIES  %s cr" % ShipStats.commas(cost), func() -> void:
				var r := Session.settle_record()
				sc._say(String(r.message))
				sc._refill(), int(Session.profile.get("credits", 0)) >= cost)
		else:
			sc.panel_list.add_child(Brand.note("The authorities have you on record. Settling it is done at the port's freight office, for %s cr." % ShipStats.commas(cost), 13))


static func _pct(mult: float) -> String:
	var d := roundi((mult - 1.0) * 100.0)
	return "at the usual price" if d == 0 else "%+d%%" % d


## One line on where you stand here and what it does to the pay.
static func _standing_line(rep: float) -> String:
	var nxt := Reputation.next_tier(rep)
	var pay := roundi((Reputation.pay_mult(rep) - 1.0) * 100.0)
	return "Your standing here: %s (%d%s). %s" % [Reputation.tier(rep), roundi(rep),
			", %s at %d" % [String(nxt.name), ceili(float(nxt.points))] if not nxt.is_empty() else "",
			"Pay is the usual." if pay == 0 else ("Pay %+d%% for it." % pay)]


## Passengers (Passengers): who's aboard and where they're going, the way to take them there when
## there's no contract to fly, and (`offers`, at the freight office) long-haul parties asking for passage.
func _passengers_section(offers: bool) -> void:
	var st := {}
	var ld := Session._load_ship(SaveSlots.read(Session.slot)) if Session.slot >= 0 else {}
	if not ld.is_empty():
		st = Session.ship_stats(ld.ship)
	var aboard := Passengers.aboard()
	var free_contract := Session.active_contract().is_empty() and not Session.insolvent()
	if not aboard.is_empty():
		sc.panel_list.add_child(Brand.heading("PASSENGERS ABOARD", 15))
		var shown := {}
		for b in aboard:
			var late := Session.day() > int(b.get("due_day", 1 << 30))
			sc.panel_list.add_child(Brand.note("%s, %d aboard, to %s, in %s. %s cr%s." % [String(b.person), int(b.seats), String(b.dest_name), Passengers.beds_text(b.beds),
					ShipStats.commas(int(b.fare)), ", and late: half that now" if late else ", due by day %d" % int(b.due_day) if int(b.get("due_day", 1 << 30)) < (1 << 29) else ""], 14))
			if not free_contract or shown.has(String(b.dest_port_id) + String(b.dest_system_id)):
				continue
			shown[String(b.dest_port_id) + String(b.dest_system_id)] = true
			if bool(b.local):
				var dest := String(b.dest_port_id)
				if dest == String(Session.profile.get("port_id", "")):
					continue
				sc._action("FLY THEM TO %s YOURSELF" % String(b.dest_name).to_upper(), func() -> void:
					var r := Session.begin_ferry_flight(dest)
					if bool(r.ok):
						sc._go(Session.FLIGHT_SCENE)
					else:
						sc._say(String(r.message)))
				sc._action("TAKE THEM TO %s ON AUTOPILOT" % String(b.dest_name).to_upper(), func() -> void:
					var r := Session.local_reposition(dest)
					Session.flash = String(r.message)
					if bool(r.ok):
						sc.get_tree().reload_current_scene()
					else:
						sc._say(String(r.message)))
			else:
				var sys := String(b.dest_system_id)
				sc._action("TAKE THEM TO %s ON AUTOPILOT, no freight" % String(b.dest_name).to_upper(), func() -> void:
					var r := Session.travel_empty(sys)
					Session.flash = String(r.message)
					if bool(r.ok):
						sc.get_tree().reload_current_scene()
					else:
						sc._say(String(r.message)))
	if not offers or Session.insolvent():
		return
	var lay := Passengers.layout(st) if not st.is_empty() else {}
	sc.panel_list.add_child(Brand.heading("PASSENGERS FOR OTHER SYSTEMS", 15))
	if not lay.is_empty():
		var f: Array = lay.free
		sc.panel_list.add_child(Brand.note("Free beds: %d spare bunk%s, %d cabin, %d quarters, %d stateroom. They ride with your freight; best beds first." % [
				maxi(0, int(f[0])), "" if int(f[0]) == 1 else "s", maxi(0, int(f[1])), maxi(0, int(f[2])), maxi(0, int(f[3]))], 13))
	var list := Passengers.long_haul()
	if list.is_empty():
		sc.panel_list.add_child(Brand.note("Nobody asking for passage. They want a ship with a working FTL drive, or a better day." if not bool(st.get("ftl", false)) else "Nobody asking for passage today.", 14))
	for o in list:
		var job: Dictionary = o
		var why := Passengers.why_not(job, st) if not st.is_empty() else ""
		sc._action(Passengers.offer_text(job, st) + ("\n" + why if why != "" else ""), func() -> void:
			var r := Session.accept_contract(job)
			sc._say(String(r.message))
			sc._refill())


## Your crew (Crew), with a button to let each go, and who is looking for a berth here today.
func _crew_section() -> void:
	if Session.slot < 0 or Session.sim == null:
		return
	var loaded := Session._load_ship(SaveSlots.read(Session.slot))
	if loaded.is_empty():
		return
	var st := Session.ship_stats(loaded.ship)
	var free := Session.free_berths(st)
	var mult := float(SimShip.level(String(Session.profile.get("difficulty", "normal"))).get("wage_mult", 1.0))
	var roster := Session.crew()
	sc.panel_list.add_child(Brand.heading("YOUR CREW", 15))
	var need := int(st.get("crew_needed", 1))
	sc.panel_list.add_child(Brand.note("%d aboard counting you, %d berth%s, %d free. %s" % [Session.crew_aboard(), int(st.get("berths", 0)), "" if int(st.get("berths", 0)) == 1 else "s", maxi(0, free),
			("This ship needs %d aboard to take freight: hire %d more." % [need, need - Session.crew_aboard()]) if Session.crew_aboard() < need else "Wages are paid daily, in port or out."], 14))
	if roster.is_empty():
		sc.panel_list.add_child(Brand.note("Just you. Every repair is yours, every brake point, every crate.", 14))
	for p in roster:
		var who: Dictionary = p
		var sev := roundi(float(who.wage) * float(Crew.cfg().get("severance_days", 2)) * mult)
		var asked := _letting_go == String(who.id)
		var txt := "%s  ·  %s, skill %d  ·  %s cr/day\n%s  %s" % [String(who.name), Crew.role_name(String(who.role)), int(who.skill),
				ShipStats.commas(roundi(float(who.wage) * mult)), String(Crew.role(String(who.role)).get("does", "")),
				("LET %s GO? Click again: %s cr severance." % [Crew.short(who).to_upper(), ShipStats.commas(sev)]) if asked else "Click to let go (%s cr severance)." % ShipStats.commas(sev)]
		sc._action(txt, func() -> void:
			if _letting_go != String(who.id):
				_letting_go = String(who.id)
				sc._refill()
				return
			_letting_go = ""
			var r := Session.fire(String(who.id))
			sc._say(String(r.message))
			sc._refill())
	sc.panel_list.add_child(Brand.heading("LOOKING FOR A BERTH", 15))
	var cands := Session.crew_candidates()
	if cands.is_empty():
		sc.panel_list.add_child(Brand.note("Nobody's looking today. Try tomorrow, or a busier port.", 14))
	if free <= 0 and not cands.is_empty():
		sc.panel_list.add_child(Brand.note("No free berth to offer. Fit crew bunks or quarters at a shipyard first.", 14))
	for p in cands:
		var cand: Dictionary = p
		var fee := roundi(float(cand.wage) * float(Crew.cfg().get("hire_fee_days", 1)) * mult)
		var txt := "%s  ·  %s, skill %d  ·  %s, %s cr/day, %s cr to sign\n\"%s\" %s" % [String(cand.name), Crew.role_name(String(cand.role)), int(cand.skill),
				Worlds.species(String(cand.species)).name, ShipStats.commas(roundi(float(cand.wage) * mult)), ShipStats.commas(fee), String(cand.line),
				String(cand.refuses) + "." if cand.has("refuses") else String(Crew.role(String(cand.role)).get("does", ""))]
		sc._action(txt, func() -> void:
			var r := Session.hire(String(cand.id))
			sc._say(String(r.message))
			sc._refill(), free > 0 and int(Session.profile.get("credits", 0)) >= fee and not cand.has("refuses"))


func _desk_fuel() -> void:
	var mult := Session.site_fuel_mult()
	if Development.abandoned(Session.sim, String(Session.profile.get("port_id", ""))):
		sc._clear_panel("Fuel pump", "Everyone left. The pump didn't. It charges %d%% of the system price, because nobody's here to argue with it." % roundi(mult * 100.0))
		sc.panel_list.add_child(Brand.note("Hull: %d%%. No repairs out here; the yard went with the people." % roundi(Session.hull() * 100.0), 15))
		return
	sc._clear_panel("Fuel and repairs", "Fuel here costs %d%% of the system price (%s). You pay for every drop you burn when you leave or land." % [roundi(mult * 100.0),
			"cheap: a fuel depot" if mult < 0.95 else ("dear: it has to come up from the surface or down from orbit" if mult > 1.2 else "the usual")])
	sc.panel_list.add_child(Brand.note("Hull: %d%%. %s" % [roundi(Session.hull() * 100.0), _hull_words(Session.hull())], 15))
	var cost := Session.repair_cost()
	sc._action("REPAIR THE HULL  %s cr" % ShipStats.commas(cost) if cost > 0 else "THE HULL NEEDS NO WORK", func() -> void:
		var r := Session.repair_hull()
		sc._say(String(r.message))
		sc._refill(), cost > 0 and int(Session.profile.get("credits", 0)) >= cost)
	var po := Session.patch_options()
	if not (po.afford as Dictionary).is_empty():
		var to := float(po.afford.to)
		sc._action("PATCH IT TO %d%%  %s cr, what you can afford" % [roundi(to * 100.0), ShipStats.commas(int(po.afford.cost))], func() -> void:
			var r := Session.patch_hull(to)
			sc._say(String(r.message))
			sc._refill())
	if not (po.account as Dictionary).is_empty():
		var to2 := float(po.account.to)
		sc._action("EMERGENCY PATCH TO %d%% ON ACCOUNT  %s cr you'll owe the yard" % [roundi(to2 * 100.0), ShipStats.commas(int(po.account.cost))], func() -> void:
			var r := Session.patch_hull(to2, true)
			sc._say(String(r.message))
			sc._refill())
	var parts_line := ""
	var loaded_p := Session._load_ship(SaveSlots.read(Session.slot)) if Session.slot >= 0 else {}
	if not loaded_p.is_empty():
		parts_line = Wear.summary(loaded_p.ship, Session.wear())
	sc.panel_list.add_child(Brand.note("Working parts: %s" % (parts_line if parts_line != "" else "all in decent shape. Wear shows up as you fly."), 15))
	var oc := Session.overhaul_cost()
	sc._action("OVERHAUL THE WORKING PARTS  %s cr" % ShipStats.commas(oc) if oc > 0 else "THE PARTS NEED NO OVERHAUL", func() -> void:
		var r := Session.overhaul_parts()
		sc._say(String(r.message))
		sc._refill(), oc > 0 and int(Session.profile.get("credits", 0)) >= oc)
	sc._action("BUY A SPARES KIT  %s cr  (%d aboard, for bringing a failed part back on a space walk)" % [ShipStats.commas(Session.spares_kit_price()), Session.spares_kits()], func() -> void:
		var r := Session.buy_spares_kit()
		sc._say(String(r.message))
		sc._refill(), Session.spares_kits() < int(Wear.cfg().get("spares_kit_max", 4)))
	var kits := Session.patch_kits()
	var kit_cr := Session.patch_kit_price()
	sc.panel_list.add_child(Brand.note("Patch kits aboard: %d of %d. For fixing the hull yourself on a space walk, up to 50%%: loose plating needs only hands, holes need a kit." % [kits, Session.patch_kit_max()], 14))
	sc._action("BUY A PATCH KIT  %s cr" % ShipStats.commas(kit_cr), func() -> void:
		var r := Session.buy_patch_kits(1)
		sc._say(String(r.message))
		sc._refill(), kits < Session.patch_kit_max())
	if Session.patch_kit_max() - kits > 1:
		sc._action("FILL THE KIT LOCKER  %d for %s cr" % [Session.patch_kit_max() - kits, ShipStats.commas(kit_cr * (Session.patch_kit_max() - kits))], func() -> void:
			var r := Session.buy_patch_kits(Session.patch_kit_max())
			sc._say(String(r.message))
			sc._refill())
	var bc := Rivals.beacons()
	var bmax := int(Rivals.cfg().get("beacon_max", 4))
	sc.panel_list.add_child(Brand.note("Claim beacons aboard: %d of %d. Fire one at a wreck from the radio (Y) and it's yours: rival salvage crews have to deal with you, not the other way round." % [bc, bmax], 14))
	sc._action("BUY A CLAIM BEACON  %s cr" % ShipStats.commas(Session.claim_beacon_price()), func() -> void:
		var r := Session.buy_claim_beacons(1)
		sc._say(String(r.message))
		sc._refill(), bc < bmax)
	var f := Session.finds_aboard()
	if int(f.value) > 0:
		sc._action("SELL YOUR FINDS  %s cr  (%s)" % [ShipStats.commas(int(f.value)), SurfaceFinds.describe(f)], func() -> void:
			var r := Session.sell_finds()
			sc._say(String(r.message))
			sc._refill())


## What came back from going aboard a derelict: flight recorders for the insurer, the remains of the
## crew for the port authority, and survivors (PortAuthority).
func _authority_section() -> void:
	if not PortAuthority.any():
		return
	sc.panel_list.add_child(Brand.heading("PORT AUTHORITY", 15))
	var recs := PortAuthority.recorders()
	if not recs.is_empty():
		sc._action("HAND IN %s  %s cr from the insurer" % ["THE FLIGHT RECORDER" if recs.size() == 1 else "%d FLIGHT RECORDERS" % recs.size(), ShipStats.commas(PortAuthority.recorder_total())], func() -> void:
			var r := PortAuthority.hand_in_recorders()
			sc._say(String(r.message))
			sc._refill())
	var dead := PortAuthority.remains()
	if not dead.is_empty():
		sc.panel_list.add_child(Brand.note("In the hold: %s. They'll be seen home to their families from here." % ", ".join(PackedStringArray(dead.map(func(d: Dictionary) -> String: return "%s of the %s" % [String(d.name), String(d.ship)]))), 14))
		sc._action("HAND OVER THE REMAINS  %s cr recovery fee" % ShipStats.commas(PortAuthority.recovery_total()), func() -> void:
			var r := PortAuthority.hand_over_remains()
			sc._say(String(r.message))
			sc._refill())
	var rep := PortAuthority.reported()
	if not rep.is_empty():
		sc._action("COLLECT THE FINDER'S FEE  %s cr for %d reported" % [ShipStats.commas(PortAuthority.finder_fee() * rep.size()), rep.size()], func() -> void:
			var r := PortAuthority.collect_finders()
			sc._say(String(r.message))
			sc._refill())
	var res := PortAuthority.rescued()
	for i in res.size():
		var who: Dictionary = res[i]
		var k := i
		if not bool(who.get("handed", false)):
			sc._action("HAND OVER %s, RESCUED  %s cr bounty" % [String(who.name).to_upper(), ShipStats.commas(int(PortAuthority.cfg().get("rescue_bounty", 6000)))], func() -> void:
				var r := PortAuthority.hand_over(k)
				sc._say(String(r.message))
				sc._refill())
		else:
			sc.panel_list.add_child(Brand.note("%s, off the %s: %s, skill %d, would work for %s cr a day." % [String(who.name), String(who.ship), Crew.role_name(String(who.role)).to_lower(), int(who.skill), ShipStats.commas(roundi(float(who.wage) * SimShip.wage_index(Session.system_id())))], 14))
			sc._action("SIGN %s ON  no fee" % String(who.name).get_slice(" ", 0).to_upper(), func() -> void:
				var r := PortAuthority.sign_on(k)
				sc._say(String(r.message))
				sc._refill())
			sc._action("SEE %s OFF" % String(who.name).get_slice(" ", 0).to_upper(), func() -> void:
				var r := PortAuthority.see_off(k)
				sc._say(String(r.message))
				sc._refill())


## Salvage in the hold off derelicts: freight ("cargo", at the freight office, to whoever here deals
## in it) or working parts ("parts", at the shipyard). Nothing shows when there's none aboard.
func _salvage_section(what: String) -> void:
	var lines := Salvage.cargo_aboard() if what == "cargo" else Salvage.parts_aboard()
	if lines.is_empty():
		return
	sc.panel_list.add_child(Brand.heading("SALVAGE IN THE HOLD", 15))
	var total := 0
	for l in lines:
		if what == "cargo":
			var o := Salvage.cargo_offer(String(l.commodity), float(l.tonnes))
			total += int(o.value)
			sc.panel_list.add_child(Brand.note("%.1f t of %s: %s cr from %s." % [float(l.tonnes), Salvage.clib().label(StringName(String(l.commodity))).to_lower(),
					ShipStats.commas(int(o.value)), String(o.name)], 14))
		else:
			var v := Salvage.part_value(l)
			total += v
			sc.panel_list.add_child(Brand.note("%s: %s cr." % [Salvage.sentence(Salvage.describe(l)), ShipStats.commas(v)], 14))
	if what == "parts":
		sc.panel_list.add_child(Brand.note("Or keep them: in the shipyard they're under FROM YOUR HOLD, and fitting one costs %d%% of its price new. It comes as worn as you found it." % roundi(float(Salvage.cfg().get("fit_rate", 0.15)) * 100.0), 13))
	sc._action("SELL THE SALVAGED %s  %s cr" % ["CARGO" if what == "cargo" else "PARTS", ShipStats.commas(total)], func() -> void:
		var r := Salvage.sell(what)
		sc._say(String(r.message))
		sc._refill(), total > 0)


## What the hull's state means, in a sentence.
static func _hull_words(h: float) -> String:
	if h <= 0.001:
		return "Breached. It goes nowhere until it's patched, not even empty."
	if h < 0.25:
		return "Below 25%: port control won't clear it to carry freight, every knock reaches the cargo, the tanks leak and the radiators are cracked."
	if h < 0.5:
		return "Below 50%: the tanks leak fuel in flight and the radiators are cracked. Thrust is down too."
	if h < 0.75:
		return "Cracked radiator panels: it runs hotter. Thrust is down a little."
	if h < 1.0:
		return "Dents. A damaged hull loses some thrust until it's fixed."
	return "Sound."


func _desk_bar() -> void:
	sc._clear_panel("Bar and bunks", "Captains and crews drift through between jobs. Some have work that never reaches the board, for reasons they'd rather not discuss.")
	if Session.site_has("crew"):
		_crew_section()
	else:
		sc.panel_list.add_child(Brand.note("Nobody here is looking for a berth: too few people to spare one. Crew sign on where there's a crowd to sign from.", 14))
	_people_section()
	if Session.site_has("passengers"):
		_passengers_section(false)
	sc.panel_list.add_child(Brand.heading("BUNKS", 15))
	var idle := Session.active_contract().is_empty() and Session.sim != null and not Session.insolvent()
	sc._action("RENT A BUNK AND WAIT A DAY", func() -> void:
		var r := Session.wait_days(1)
		Session.flash = String(r.message)
		if bool(r.ok):
			sc.get_tree().reload_current_scene()
		else:
			sc._say(String(r.message)), idle)


## An abandoned site (frontier growth): strip what's left for salvage, and read how it got this way.
func _desk_strip() -> void:
	var id := String(Session.profile.get("port_id", ""))
	var s := Development.site(Session.sim, id)
	var since := Session.day() - int(s.get("since", Session.day()))
	sc._clear_panel("Strip the fittings", "Abandoned %s. Nobody kept it supplied, so nobody stayed. The lights are on a timer and the timer is optimistic." % ("today" if since <= 0 else ("%d day%s ago" % [since, "" if since == 1 else "s"])))
	sc._action("STRIP WHAT'S WORTH TAKING", func() -> void:
		var r := Session.strip_fittings()
		sc._say(String(r.message))
		sc._refill())
	sc.panel_list.add_child(Brand.note("Salvage parts aboard: %d. Any freight office or yard will buy them." % int(Session.profile.get("salvage", 0)), 14))


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
	sc._clear_panel("Suit store", "Kit for the great airless outdoors. Your suit holds %s of air." % SurfaceWork.clock(SurfaceWork.o2_capacity(owned)))
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
	sc._action("TAKE THE HELM" if Session.hull() > 0.001 else "TAKE THE HELM  (the hull is breached: patch it first)", func() -> void:
		Session.flight_job = {}
		sc._go(Session.FLIGHT_SCENE), not Session.insolvent() and Session.hull() > 0.001)
	sc._action("GO ABOARD AND WALK THE SHIP", func() -> void:
		Session.flight_job = {}
		Session.walk_aboard = true
		sc._go(Session.FLIGHT_SCENE), not Session.insolvent())
	if Session.surface_site() != "":
		sc._action("SUIT UP AND GO OUTSIDE  (%s of air)" % SurfaceWork.clock(SurfaceWork.o2_capacity(Session.gear_owned())), func() -> void:
			Session.flight_job = {}
			Session.suit_up = true
			sc._go(Session.FLIGHT_SCENE), not Session.insolvent())
