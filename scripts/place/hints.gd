class_name Hints
extends RefCounted
## One-time pointers for a new captain, shown on arriving somewhere when they fit what is going on.
## Each is shown once per game (profile.hints_seen). Pure rules over the session, so they test easily.

const LIST := [
	{"id": "welcome", "where": "concourse", "text": "Welcome to the station, Captain. Walk to the FREIGHT OFFICE and press E to see what needs hauling. People at the BAR have jobs of their own, and opinions to go with them. T opens the station terminal."},
	{"id": "holding", "where": "", "text": "You have a load aboard, and it won't deliver itself. Go through the GATE and FLY THE RUN yourself, or DEPART ON AUTOPILOT at the freight office."},
	{"id": "arrived", "where": "", "text": "You made it. DELIVER THE LOAD at the freight office (or dispatch, or the foreman) and get paid before anyone asks questions."},
	{"id": "money", "where": "concourse", "text": "With some money put by, the SHIPYARD can fit LANDER LEGS (moons and surface work, which pays more) or crew bunks (passengers, and hands from the bar). An FTL drive opens the other stars, at a price that's also astronomical."},
	{"id": "hab", "where": "hab", "text": "A moon base hab: all the comforts of a tin can. DISPATCH posts timed surface missions, the SUIT STORE sells air tanks and kit, and the LAB pays well for rock samples. The airlock suits you up."},
	{"id": "hut", "where": "hut", "text": "The mining camp. The FOREMAN has work, and the EXCHANGE pays well for ice. There's no crane here, only you and the low gravity: unload your freight by hand to keep the whole fee."},
	{"id": "trade", "where": "concourse", "text": "Your first delivery is on the books. Press N for the TRADE REPORT: where the freight's going across known space, who's running short of what, who's earning, and the dent you're making in it all."},
	{"id": "crew", "where": "concourse", "text": "A spare bunk and nobody in it. The BAR has people looking for a berth: an engineer slows the wear and fixes parts, a deck tech patches the hull, a pilot flies leaner and minds the helm. They want paying every day, and they earn it. Mostly."},
]


## The hint to show now in a place of `kind` ("concourse", "hab" or "hut"), or {}.
static func next(kind: String) -> Dictionary:
	var seen: Array = Session.profile.get("hints_seen", [])
	var c := Session.active_contract() if Session.slot >= 0 else {}
	for h in LIST:
		if String(h.id) in seen:
			continue
		if String(h.where) != "" and String(h.where) != kind:
			continue
		if _fits(String(h.id), c):
			return h
	return {}


static func _fits(id: String, c: Dictionary) -> bool:
	match id:
		"welcome":
			return c.is_empty()
		"holding":
			return not c.is_empty() and String(c.get("status", "")) != "arrived"
		"arrived":
			return not c.is_empty() and String(c.get("status", "")) == "arrived"
		"money":
			return int(Session.profile.get("credits", 0)) >= 70000 and "welcome" in Session.profile.get("hints_seen", [])
		"trade":
			if Session.sim == null or not "welcome" in Session.profile.get("hints_seen", []):
				return false
			var life := SimStats.lifetime(Session.sim)
			return int(life.get("deliveries", 0)) + int(life.get("local_runs", 0)) > 0
		"crew":
			if Session.slot < 0 or not Session.crew().is_empty() or not "welcome" in Session.profile.get("hints_seen", []):
				return false
			var loaded := Session._load_ship(SaveSlots.read(Session.slot))
			return not loaded.is_empty() and Session.free_berths(Session.ship_stats(loaded.ship)) > 0
	return true


static func mark_seen(id: String) -> void:
	var seen: Array = (Session.profile.get("hints_seen", []) as Array).duplicate()
	if not id in seen:
		seen.append(id)
	Session.profile["hints_seen"] = seen
	Session.save_profile()
