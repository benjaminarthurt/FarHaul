class_name PortAuthority
extends RefCounted
## What you bring back from boarding a derelict that isn't for sale, handed in at any port's freight
## office (traffic.json "boarding"):
##   flight recorders (profile.recorders): the insurer pays a bounty for each;
##   remains (profile.remains, in the hold as Salvage.REMAINS): the port authority sees them home to
##     their next of kin and pays a recovery fee for each;
##   survivors (profile.rescued): handed over for a rescue bounty and standing; after that each will
##     sign on with no hiring fee, or go their own way.

static func cfg() -> Dictionary:
	return Wreckage.cfg()


static func recorders() -> Array:
	return Session.profile.get("recorders", [])


static func remains() -> Array:
	return Session.profile.get("remains", [])


static func rescued() -> Array:
	return Session.profile.get("rescued", [])


## Survivors you found but had no room for: the port sent its own boat (profile.reported).
static func reported() -> Array:
	return Session.profile.get("reported", [])


## Anything to hand in here at all.
static func any() -> bool:
	return not recorders().is_empty() or not remains().is_empty() or not rescued().is_empty() or not reported().is_empty()


static func finder_fee() -> int:
	return roundi(float(cfg().get("rescue_bounty", 6000)) * float(cfg().get("finder_share", 0.4)))


## Report survivor `item` (no room aboard): the port's rescue boat fetches them; a finder's fee later.
static func report(item: Dictionary) -> String:
	var rep: Array = reported().duplicate()
	rep.append({"name": String(item.name), "ship": String(item.ship)})
	Session.profile["reported"] = rep
	Session.save_profile()
	return "You call it in: survivor aboard the %s, %s, alive. The port's rescue boat is on its way with a bunk to spare. Leave the lamp on for them." % [String(item.ship), String(item.name)]


## Finder's fees for survivors you reported.
static func collect_finders() -> Dictionary:
	var rep := reported()
	if rep.is_empty():
		return {"ok": false, "message": "Nobody reported."}
	var fee := finder_fee() * rep.size()
	Session._book(float(fee))
	var note := Session._add_rep(int(cfg().get("finder_rep", 1)) * rep.size(), "record")   # the authorities like a captain who reports wrecks
	Session.profile["reported"] = []
	_count("reported", rep.size())
	Session.save_profile()
	return {"ok": true, "message": "The rescue boat brought %s in. Finder's fee: %s cr.%s Somebody's buying you a drink, if you're ever back." % [
			", ".join(PackedStringArray(rep.map(func(r: Dictionary) -> String: return String(r.name)))), ShipStats.commas(fee), note]}


static func recorder_total() -> int:
	var t := 0
	for r in recorders():
		t += int(r.bounty)
	return t


static func recovery_total() -> int:
	return remains().size() * int(cfg().get("recovery_fee", 2500))


## The insurers' bounties for every recorder aboard.
static func hand_in_recorders() -> Dictionary:
	var recs := recorders()
	if recs.is_empty():
		return {"ok": false, "message": "No flight recorders aboard."}
	var total := recorder_total()
	if not Session._book(float(total)):
		return {"ok": false, "message": "The insurer's office is shut. Try again in a minute."}
	Session.profile["recorders"] = []
	_count("recorders_cr", total)
	Session.save_profile()
	var ships := PackedStringArray(recs.map(func(r: Dictionary) -> String: return "the " + String(r.ship)))
	return {"ok": true, "message": "Handed in %s. The insurer pays %s cr to find out what happened%s." % [
			"the flight recorder from " + ships[0] if recs.size() == 1 else "%d flight recorders (%s)" % [recs.size(), ", ".join(ships)],
			ShipStats.commas(total), ", and to make sure it wasn't their fault" if recs.size() > 1 else ""]}


## The remains in the hold go to the port authority; a recovery fee for each.
static func hand_over_remains() -> Dictionary:
	var dead := remains()
	if dead.is_empty():
		return {"ok": false, "message": "Nobody in the hold."}
	var data := SaveSlots.read(Session.slot)
	var loaded := Session._load_ship(data)
	if loaded.is_empty():
		return {"ok": false, "message": "Couldn't load the ship from the save."}
	var fee := recovery_total()
	var m: CargoManifest = loaded.manifest
	var t := 0.0
	for d in dead:
		t += float(d.get("tonnes", 0.0))
	m.unload(Salvage.REMAINS, t + 0.001)
	data["cargo"] = m.to_dict()
	SaveSlots.write(Session.slot, data)
	Session._book(float(fee))
	Session.profile["remains"] = []
	_count("recovered", dead.size())
	Session.save_profile()
	var names := PackedStringArray(dead.map(func(d: Dictionary) -> String: return String(d.name)))
	return {"ok": true, "message": "The port authority takes %s home from here, to whoever's waiting. They pay a recovery fee of %s cr, and nobody makes a joke about it." % [
			names[0] if names.size() == 1 else "%s and %s" % [", ".join(names.slice(0, names.size() - 1)), names[names.size() - 1]], ShipStats.commas(fee)]}


## Survivor `i` handed over: the rescue bounty and standing. They stay aboard until they sign on or go.
static func hand_over(i: int) -> Dictionary:
	var res := rescued().duplicate(true)
	if i < 0 or i >= res.size() or bool(res[i].get("handed", false)):
		return {"ok": false, "message": "Nobody to hand over."}
	var bounty := int(cfg().get("rescue_bounty", 6000))
	Session._book(float(bounty))
	var rep := Session._add_rep(int(cfg().get("rescue_rep", 2)), "rescue", [String(res[i].get("species", "human"))])   # their own people hear who brought them home
	res[i]["handed"] = true
	Session.profile["rescued"] = res
	_count("rescued", 1)
	Session.save_profile()
	return {"ok": true, "message": "The port records %s off the %s as rescued. The bounty's %s cr.%s %s says they could use a berth, and a job." % [
			String(res[i].name), String(res[i].ship), ShipStats.commas(bounty), rep, String(res[i].name).get_slice(" ", 0)]}


## A handed-over survivor signs on: no hiring fee, their usual wage.
static func sign_on(i: int) -> Dictionary:
	var res := rescued().duplicate(true)
	if i < 0 or i >= res.size() or not bool(res[i].get("handed", false)):
		return {"ok": false, "message": "Hand them over to the port first: there's paperwork."}
	var who: Dictionary = res[i]
	var p := {"id": "rescued-%d-%d" % [absi(hash(String(who.name))) % 100000, Session.day()], "name": String(who.name), "species": String(who.species),
			"role": String(who.role), "skill": int(who.skill), "wage": roundi(float(who.wage) * SimShip.wage_index(Session.system_id())),
			"line": "Owes you one. Says so, often.", "hired_day": Session.day()}
	var roster := Session.crew().duplicate()
	roster.append(p)
	Session.profile["crew"] = roster
	res.remove_at(i)
	Session.profile["rescued"] = res
	Session._resync()
	return {"ok": true, "message": "%s signs on as %s for %s cr a day, no fee. \"You came aboard. Nobody else did.\"" % [String(p.name), Crew.role_name(String(p.role)).to_lower(), ShipStats.commas(int(p.wage))]}


## A handed-over survivor goes their own way.
static func see_off(i: int) -> Dictionary:
	var res := rescued().duplicate(true)
	if i < 0 or i >= res.size():
		return {"ok": false, "message": "Nobody to see off."}
	var who: Dictionary = res[i]
	res.remove_at(i)
	Session.profile["rescued"] = res
	Session.save_profile()
	return {"ok": true, "message": "%s shakes your hand at the gate and goes to find a ship that isn't dead. Fair enough." % String(who.name)}


static func _count(key: String, n: int) -> void:
	var life: Dictionary = (Session.profile.get("aboard_record", {}) as Dictionary).duplicate()
	life[key] = int(life.get(key, 0)) + n
	Session.profile["aboard_record"] = life
