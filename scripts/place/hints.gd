class_name Hints
extends RefCounted
## One-time pointers for a new captain, shown on arriving somewhere when they fit what is going on.
## Each is shown once per game (profile.hints_seen). Pure rules over the session, so they test easily.

const LIST := [
	{"id": "welcome", "where": "concourse", "text": "Welcome aboard the station. Walk to the FREIGHT OFFICE and press E to see the work posted here. People at the BAR have jobs of their own. T opens the station terminal."},
	{"id": "holding", "where": "", "text": "You have a load aboard. Go through the GATE and FLY THE RUN yourself, or DEPART ON AUTOPILOT at the freight office."},
	{"id": "arrived", "where": "", "text": "You've arrived. DELIVER THE LOAD at the freight office (or dispatch, or the foreman) to be paid."},
	{"id": "money", "where": "concourse", "text": "With some money put by, the SHIPYARD can fit LANDER LEGS (moons and surface work, which pays more) or crew bunks (passengers). An FTL drive opens the other stars."},
	{"id": "hab", "where": "hab", "text": "A moon base hab. DISPATCH posts timed surface missions, the SUIT STORE sells air tanks and kit, and the LAB pays well for rock samples. The airlock suits you up."},
	{"id": "hut", "where": "hut", "text": "The mining camp. The FOREMAN has work, the EXCHANGE pays well for ice. There's no crane here: unload your freight by hand to keep the whole fee."},
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
	return true


static func mark_seen(id: String) -> void:
	var seen: Array = (Session.profile.get("hints_seen", []) as Array).duplicate()
	if not id in seen:
		seen.append(id)
	Session.profile["hints_seen"] = seen
	Session.save_profile()
