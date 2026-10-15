class_name Passengers
extends RefCounted
## Passengers: parties riding along with whatever else the ship is doing, each going where it's going.
## They are bookings (`profile.passengers`), not contracts, so a ship can carry freight and people at
## once. Two kinds:
##
## - **local:** asked for in person at the bar, the hab's dispatch desk or the camp foreman (People),
##   to another site in the same system.
## - **long haul:** at the freight office, to another star system the ship can reach.
##
## Beds come in tiers (`tiers`): a spare crew bunk at the basic fare, then cabins, quarters and
## staterooms (ModuleDef.cabins and cabin_tier) at a multiple of it. Each party is given the best free
## beds when it boards and pays for those, at the end of its trip. Some insist on a cabin or better
## (`wants`, the lowest tier they'll take). A rough ride (new hull damage) or a late arrival halves the
## fare. Rescued survivors (PortAuthority) take spare bunks first, then any free bed.
## Tuning: data/runtime/passengers.json. See docs/runtime/passengers.md.

const PATH := "res://data/runtime/passengers.json"

static var _cfg: Dictionary = {}


static func cfg() -> Dictionary:
	if _cfg.is_empty():
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		_cfg = parsed if typeof(parsed) == TYPE_DICTIONARY else {}
	return _cfg


static func tier(t: int) -> Dictionary:
	var ts: Array = cfg().get("tiers", [])
	return ts[clampi(t, 0, ts.size() - 1)] if not ts.is_empty() else {"id": "bunk", "name": "bunk", "mult": 1.0}


static func mult(t: int) -> float:
	return float(tier(t).get("mult", 1.0))


## "a cabin", "quarters", "the stateroom": what a party wants, for a line of text.
static func wants_text(t: int) -> String:
	return ["any bed", "a cabin or better", "quarters or better", "a stateroom"][clampi(t, 0, 3)]


## The parties aboard: [{id, person, seats, beds, fare, local, dest_port_id, dest_system_id, dest_name,
## booked_day, due_day, hull_at_accept, species, line}].
static func aboard() -> Array:
	return Session.profile.get("passengers", []) if Session.slot >= 0 else []


## How many people that is.
static func count() -> int:
	var n := 0
	for b in aboard():
		n += int(b.get("seats", 0))
	return n


## How passengers sit in `stats` (Session.ship_stats): beds by tier [spare bunks, cabin, quarters,
## stateroom], what's booked, what the rescued take, what's free, and `over`: survivors with no bed
## at all (the jump seat).
static func layout(stats: Dictionary, bookings: Array = []) -> Dictionary:
	var cb: Array = stats.get("cabin_beds", [0, 0, 0, 0])
	var beds := [maxi(0, int(stats.get("berths", 0)) - int(stats.get("crew_aboard", stats.get("crew_needed", 1)))), int(cb[1]), int(cb[2]), int(cb[3])]
	var used := [0, 0, 0, 0]
	for b in (bookings if not bookings.is_empty() else aboard()):
		for t in b.get("beds", []):
			used[clampi(int(t), 0, 3)] += 1
	var free := [0, 0, 0, 0]
	for t in 4:
		free[t] = beds[t] - used[t]
	var rescued := int(stats.get("rescued", 0))
	var in_beds := [0, 0, 0, 0]
	for t in 4:   # survivors: spare bunks first, then whatever's free, cheapest first
		var k := mini(rescued, maxi(free[t], 0))
		in_beds[t] = k
		free[t] -= k
		rescued -= k
	return {"beds": beds, "used": used, "rescued": in_beds, "free": free, "over": rescued}


## The beds a party of `seats` gets from `free` (best first), none below `wants`; [] if they don't fit.
static func assign(free: Array, seats: int, wants: int) -> Array:
	var out := []
	var left := free.duplicate()
	for t in [3, 2, 1, 0]:
		if t < wants:
			continue
		while out.size() < seats and int(left[t]) > 0:
			out.append(t)
			left[t] = int(left[t]) - 1
	return out if out.size() == seats else []


## What a party pays for `beds`, at `per_seat` a head.
static func fare_for(per_seat: int, beds: Array) -> int:
	var f := 0.0
	for t in beds:
		f += float(per_seat) * mult(int(t))
	return roundi(f / 10.0) * 10


## What the best beds free now would earn from offer `o`, or -1 if it can't board (see why_not).
static func fare_now(o: Dictionary, stats: Dictionary) -> int:
	var beds := assign(layout(stats).free, int(o.get("seats", 1)), int(o.get("wants", 0)))
	return fare_for(int(o.get("per_seat", 0)), beds) if not beds.is_empty() else -1


## Why offer `o` can't board this ship, or "".
static func why_not(o: Dictionary, stats: Dictionary) -> String:
	var lay := layout(stats)
	var n := int(o.get("seats", 1))
	var wants := int(o.get("wants", 0))
	if not bool(o.get("local", false)) and not bool(stats.get("ftl", false)):
		return "%s won't book a ship with no working FTL drive to %s. Fair." % [_who(o), String(o.get("dest_name", "there"))]
	if not assign(lay.free, n, wants).is_empty():
		return ""
	var any := 0
	var good := 0
	for t in 4:
		any += maxi(0, int(lay.free[t]))
		if t >= maxi(wants, 0):
			good += maxi(0, int(lay.free[t]))
	if wants > 0 and any >= n:
		return "%s want%s %s, and you have %d free. A spare bunk won't do." % [_who(o), "s" if n == 1 else "", wants_text(wants), good]
	return "%s need%s %d bed%s; you have %d free. Fit crew bunks or passenger cabins at a shipyard. Laps don't count." % [
			_who(o), "s" if n == 1 else "", n, "" if n == 1 else "s", any]


static func _who(o: Dictionary) -> String:
	var p := String(o.get("person", "They"))
	return p if int(o.get("seats", 1)) == 1 else p + "'s party"


## Take party `o` aboard (an offer from People.posted or long_haul): the best free beds, and the fare
## for them fixed now. Saves. {ok, message}.
static func book(o: Dictionary) -> Dictionary:
	if Session.slot < 0:
		return {"ok": false, "message": "Only in a saved game."}
	if o.has("locked"):
		return {"ok": false, "message": "%s won't deal with you yet. %s." % [String(o.get("person", "They")), String(o.locked)]}
	var loaded := Session._load_ship(SaveSlots.read(Session.slot))
	if loaded.is_empty():
		return {"ok": false, "message": "Couldn't load the ship from the save."}
	var stats := Session.ship_stats(loaded.ship)
	var why := why_not(o, stats)
	if why != "":
		return {"ok": false, "message": why}
	var n := int(o.get("seats", 1))
	var beds := assign(layout(stats).free, n, int(o.get("wants", 0)))
	var p := Session.profile
	var local := bool(o.get("local", false))
	var dest_port := String(o.get("destination_port_id", ""))
	var dest_sys := String(o.get("destination_system_id", Session.system_id()))
	var r := RandomNumberGenerator.new()
	r.seed = hash(String(o.get("id", "")))
	var b := {"id": String(o.get("id", "")), "person": String(o.get("person", "Someone")), "seats": n, "beds": beds,
			"fare": fare_for(int(o.get("per_seat", 0)), beds), "per_seat": int(o.get("per_seat", 0)), "local": local,
			"dest_port_id": dest_port, "dest_system_id": dest_sys, "dest_name": String(o.get("dest_name", "")),
			"booked_day": Session.day(), "due_day": Session.day() + int(o.get("due_days", 2)),
			"hull_at_accept": float(p.get("hull_damage", 0.0)), "species": _species(r), "wants": int(o.get("wants", 0))}
	var list: Array = (p.get("passengers", []) as Array).duplicate(true)
	list.append(b)
	p["passengers"] = list
	var key := "local_taken" if local else "pax_taken"
	var done: Array = (p.get(key, []) as Array).duplicate()
	done.append(String(o.get("id", "")))
	p[key] = done.slice(maxi(0, done.size() - 40))
	Session.save_profile()
	var where := beds_text(beds)
	return {"ok": true, "message": "%s %s aboard, in %s, for %s. %s cr when you set them down, if it's smooth and on time." % [
			_who(b), "is" if n == 1 else "are", where, String(b.dest_name), ShipStats.commas(int(b.fare))]}


## "the stateroom", "2 cabin beds and a spare bunk".
static func beds_text(beds: Array) -> String:
	var counts := {}
	for t in beds:
		counts[int(t)] = int(counts.get(int(t), 0)) + 1
	var bits := PackedStringArray()
	var one := ["a spare bunk", "a cabin bed", "a bed in the quarters", "the stateroom"]
	var many := ["%d spare bunks", "%d cabin beds", "%d beds in the quarters", "the stateroom"]
	for t in [3, 2, 1, 0]:
		if counts.has(t):
			var k := int(counts[t])
			bits.append(one[t] if k == 1 else (many[t] % k if many[t].contains("%d") else many[t]))
	if bits.size() <= 1:
		return bits[0] if not bits.is_empty() else "nowhere"
	return ", ".join(bits.slice(0, bits.size() - 1)) + " and " + bits[bits.size() - 1]


static func _species(r: RandomNumberGenerator) -> String:
	var pool: Array = cfg().get("species", [["human", 1]])
	var total := 0
	for s in pool:
		total += int(s[1])
	var roll := r.randi() % maxi(total, 1)
	for s in pool:
		roll -= int(s[1])
		if roll < 0:
			return String(s[0])
	return "human"


## Is booking `b` where it's going? Local parties get off at their site (or its moon base's pad);
## long-haul ones anywhere in their system.
static func here(b: Dictionary) -> bool:
	var port := String(Session.profile.get("port_id", ""))
	if not bool(b.get("local", false)):
		return Session.system_id() == String(b.get("dest_system_id", ""))
	if String(b.get("dest_port_id", "")) == port:
		return true
	return port == Session.system_id() + LocalSpace.SEP + "pad" and String(LocalSpace.node(String(b.get("dest_port_id", ""))).get("kind", "")) == "moon"


## Everyone whose stop this is gets off and pays. Call after the ship has arrived somewhere (and the
## arrival is saved). Returns a line for the arrival message, or "".
static func set_down() -> String:
	if Session.slot < 0:
		return ""
	var list: Array = aboard()
	var off := list.filter(func(b): return here(b))
	if off.is_empty():
		return ""
	var c := cfg()
	var roster := Session.crew()
	var hull := float(Session.profile.get("hull_damage", 0.0))
	var total := 0
	var tips := 0
	var rep := 0
	var notes := PackedStringArray()
	for b in off:
		var pay := int(b.fare)
		var note := ""
		var rough := hull > float(b.get("hull_at_accept", 0.0)) + 0.001
		var late := Session.day() > int(b.get("due_day", 1 << 30))
		if rough:
			pay = roundi(float(pay) * float(c.get("rough_pay", 0.5)))
			rep += int(c.get("rep_rough", -3))
			note = "a rough ride, so half"
		elif late:
			pay = roundi(float(pay) * float(c.get("late_pay", 0.5)))
			rep += int(c.get("rep_late", -2))
			note = "late, so half"
		else:
			rep += int(c.get("rep_ok", 2))
		if Crew.skill(roster, "steward") > 0:   # looked after: they pay more, and say so
			var before := pay
			pay = roundi(float(pay) * Crew.fare_mult(roster))
			tips += pay - before
			if not rough and not late and Crew.skill(roster, "steward") >= 3:
				rep += 1
		total += pay
		notes.append("%s %s cr%s" % [_who(b), ShipStats.commas(pay), " (%s)" % note if note != "" else ""])
	var keep := list.filter(func(b): return not here(b))
	Session.profile["passengers"] = keep
	var st: Dictionary = Session.profile.get("pax_stats", {})
	st["parties"] = int(st.get("parties", 0)) + off.size()
	st["fares_cr"] = int(st.get("fares_cr", 0)) + total
	Session.profile["pax_stats"] = st
	Session.save_profile()
	if total > 0:
		Session._book(float(total))
	var rep_note := Session._add_rep(rep)
	Session.save_profile()
	var care := " %s cr of that for %s's care." % [ShipStats.commas(tips), Crew.short(Crew.who(roster, "steward"))] if tips > 0 else ""
	return " Passengers off: %s.%s%s" % ["; ".join(notes), care, rep_note]


## Long-haul parties asking at the freight office here today, to systems this ship can reach:
## offers like People's ({id, person, seats, per_seat, wants, line, local: false, dest_name, ...}).
static func long_haul() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if Session.slot < 0 or Session.sim == null:
		return out
	var k: Dictionary = cfg().get("long_haul", {})
	var port := String(Session.profile.get("port_id", ""))
	var dests := SimWorld.destinations(Session.sim)
	if dests.is_empty():
		return out
	var taken: Array = Session.profile.get("pax_taken", [])
	var r := RandomNumberGenerator.new()
	r.seed = hash("%s|%d|pax" % [port, Session.day()])
	var per_day: Array = k.get("per_day", [2, 4])
	var n := r.randi_range(int(per_day[0]), int(per_day[1]))
	var lines: Dictionary = cfg().get("lines", {})
	var bonus := 1.0 + People.rep_bonus(int(Session.profile.get("rep", 0)))
	for i in n:
		var d: Dictionary = dests[r.randi() % mini(dests.size(), 5)]
		var id := "pax-%s-%d-%d" % [port, Session.day(), i]
		var seats := r.randi_range(int(k.seats[0]), int(k.seats[1]))
		var wants := 0
		var roll := r.randf()
		if roll < float(k.get("wants_stateroom", 0.1)):
			wants = 3
			seats = mini(seats, int(k.get("stateroom_max_seats", 2)))
		elif roll < float(k.get("wants_stateroom", 0.1)) + float(k.get("wants_cabin", 0.3)):
			wants = 1
		var sys := String(d.system_id)
		var name := String(Worlds.system(sys).get("name", sys))
		var person := "%s %s" % [People.FIRST[r.randi() % People.FIRST.size()], People.LAST[r.randi() % People.LAST.size()]]
		var said: Array = lines.get("stateroom" if wants == 3 else ("cabin" if wants == 1 else "long"), lines.get("long", ["Passage to %s."]))
		var line := String(said[r.randi() % said.size()])
		if line.contains("%s"):
			line = line % name
		var per_seat := roundi((float(k.get("fare_base_cr", 300)) + float(k.get("fare_per_ly_cr", 160)) * float(d.ly)) * bonus / 10.0) * 10
		var due := ceili(float(d.days) * float(k.get("due_days_x", 1.5))) + int(k.get("due_days_plus", 2))
		if taken.has(id):
			continue
		out.append({"id": id, "person": person, "person_kind": "passenger", "seats": seats, "per_seat": per_seat, "wants": wants,
				"line": line, "local": false, "destination_system_id": sys, "destination_port_id": sim_port(sys), "dest_name": name,
				"distance_ly": float(d.ly), "days": float(d.days), "due_days": due,
				"title": "%d passenger%s to %s" % [seats, "" if seats == 1 else "s", name]})
	return out


static func sim_port(sys: String) -> String:
	return Session.sim.net.primary_port(sys) if Session.sim != null else ""


## One line for an offer, for a desk button: who, how many, where, what they want and what it pays here.
static func offer_text(o: Dictionary, stats: Dictionary) -> String:
	var fare := fare_now(o, stats) if not stats.is_empty() else -1
	var wants := int(o.get("wants", 0))
	var base := roundi(float(o.per_seat) * float(o.seats) * mult(wants))
	var lowest: String = ["spare bunks", "cabins", "the quarters", "the stateroom"][clampi(wants, 0, 3)]
	var pays := "pays %s cr in the beds you have free" % ShipStats.commas(fare) if fare >= 0 else "%s cr in %s%s" % [ShipStats.commas(base), lowest, ", more in better beds" if wants < 3 else ""]
	var where := ("%d h" % int(o.get("hours", 0))) if bool(o.get("local", false)) else "%.2f ly, due in %d days" % [float(o.get("distance_ly", 0.0)), int(o.get("due_days", 0))]
	return "PASSENGER  %s: \"%s\"\n%s  ·  %s  ·  wants %s  ·  %s" % [String(o.person), String(o.line), String(o.title), where, wants_text(int(o.get("wants", 0))), pays]


## Old saves: a passenger run that was a contract becomes a booking, and the contract goes.
static func migrate(data: Dictionary) -> void:
	var c: Dictionary = data.get("active_contract", {})
	if String(c.get("person_kind", "")) != "passenger":
		return
	var p: Dictionary = data.get("profile", {})
	var list: Array = p.get("passengers", [])
	var n := int(c.get("seats", 1))
	var beds := []
	for i in n:
		beds.append(0)
	list.append({"id": String(c.get("id", "old")), "person": String(c.get("person", "Someone")), "seats": n, "beds": beds,
			"fare": int(c.get("pay_total", c.get("fare", 0))), "per_seat": int(c.get("fare", 0)) / maxi(n, 1), "local": true,
			"dest_port_id": String(c.get("destination_port_id", "")), "dest_system_id": String(p.get("system_id", "")),
			"dest_name": String(LocalSpace.node(String(c.get("destination_port_id", ""))).get("name", "their stop")),
			"booked_day": 0, "due_day": 1 << 30, "hull_at_accept": float(c.get("hull_at_accept", 0.0)), "species": "human", "wants": 0})
	p["passengers"] = list
	data["profile"] = p
	data.erase("active_contract")
