class_name Wreckage
extends RefCounted
## What's inside a derelict when you go aboard (traffic.json "boarding"): who was aboard and what became
## of them, the log they left, and the things worth taking. The same wreck always holds the same, so it's
## rolled from the wreck's own id. Items are carried out like hold items (SpaceWalk.carry) and stowed by
## Salvage.stow:
##   crate:    {kind, commodity, tonnes}             a loose crate in a hold
##   supplies: {kind, patch_kits, spares_kits}       a locker
##   recorder: {kind, ship, bounty}                  the flight recorder, at the helm
##   body:     {kind, name, ship, tonnes}            one of the crew who didn't make it
##   survivor: {kind, name, species, role, skill, wage, line, ship}   one who did
## Each item says where it is: `at`, the index of the module it's in, and `slot`, which spot in it.

static func cfg() -> Dictionary:
	return Traffic.config().get("boarding", {})


static func _ri(c: Dictionary, key: String, fallback: Array, r: RandomNumberGenerator) -> int:
	var a: Array = c.get(key, fallback)
	return r.randi_range(int(a[0]), int(a[1]))


## Everything aboard the wreck `ship` called `ship_name`: {cause, log: [lines], crew: [names], items}.
## `deep`: stranded out on a route. `seed_key` makes it the same every time.
static func roll(ship: ShipData, ship_name: String, deep: bool, seed_key: String) -> Dictionary:
	var c := cfg()
	var r := RandomNumberGenerator.new()
	r.seed = hash("aboard|" + seed_key)
	var lib := ship.library
	var helm := -1
	var holds := []
	var bunks := []
	var service := []
	var walkable := []
	for i in ship.modules.size():
		var d := lib.get_def(ship.modules[i].id)
		if not d.pressurized:
			continue
		walkable.append(i)
		if d.helm and helm < 0:
			helm = i
		if d.cargo_slots > 0:
			holds.append(i)
		if d.berths > 0:
			bunks.append(i)
		if d.airlock or String(d.id) == "engineering":
			service.append(i)
	if walkable.is_empty():
		return {"cause": "", "log": [], "crew": [], "items": []}
	var anywhere := func(list: Array) -> int:
		return int(list[r.randi() % list.size()]) if not list.is_empty() else int(walkable[r.randi() % walkable.size()])
	var causes: Array = c.get("deep_causes" if deep else "near_causes", ["reactor"])
	var cause := String(causes[r.randi() % causes.size()])
	var items := []
	# The crew, and what became of them.
	var n := _ri(c, "crew", [1, 3], r)
	var dead := []
	var gone := []
	var survivor := {}
	var room := ""
	for k in n:
		var sp := Crew._species(r)
		var nm := Crew.make_name(sp, r)
		if survivor.is_empty() and r.randf() < float(c.get("deep_survivor_chance" if deep else "survivor_chance", 0.1)):
			var role: String = Crew.ROLES[r.randi() % Crew.ROLES.size()]
			var skill := Crew._skill(r)
			var lines: Array = (Crew.cfg().get("lines", {}) as Dictionary).get(role, [""])
			survivor = {"kind": "survivor", "name": nm, "species": sp, "role": role, "skill": skill, "wage": roundi(Crew.base_wage(role, skill)),
					"line": String(lines[r.randi() % lines.size()]) if not lines.is_empty() else "", "ship": ship_name,
					"at": anywhere.call(bunks), "slot": 0}
			items.append(survivor)
		elif r.randf() < float(c.get("dead_chance", 0.5)):
			var at: int = anywhere.call(bunks)
			room = lib.get_def(ship.modules[at].id).display_name.to_lower()
			dead.append(nm)
			items.append({"kind": "body", "name": nm, "ship": ship_name, "tonnes": float(c.get("remains_t", 0.2)), "at": at, "slot": dead.size()})
		else:
			gone.append(nm)
	# The log.
	var log := []
	for line in (c.get("causes", {}) as Dictionary).get(cause, []):
		log.append(String(line))
	if not gone.is_empty():
		log.append(String(c.get("evacuated_line", "{names} took the pod.")).format({"names": _and(gone)}))
	if not dead.is_empty():
		log.append(String(c.get("dead_line", "{names} didn't make it.")).format({"names": _and(dead), "room": room}))
	if not survivor.is_empty():
		log.append(String(c.get("survivor_line", "{name} is in the cold bunk.")).format({"name": String(survivor.name)}))
	log.append(String(c.get("last_line", "Last entry.")))
	# Things worth taking.
	var hc: Dictionary = Salvage.cfg()
	var coms: Array = hc.get("commodities", ["consumer_goods"])
	var ct: Array = c.get("crate_t", [0.4, 1.2])
	for k in _ri(c, "crates", [1, 3], r):
		items.append({"kind": "crate", "commodity": String(coms[r.randi() % coms.size()]), "tonnes": snappedf(r.randf_range(float(ct[0]), float(ct[1])), 0.1),
				"at": anywhere.call(holds), "slot": k + 1})
	for k in _ri(c, "lockers", [1, 2], r):
		var pk := r.randi_range(0, 2)
		items.append({"kind": "supplies", "patch_kits": pk, "spares_kits": 1 if pk == 0 or r.randf() < 0.3 else 0, "at": anywhere.call(service), "slot": k + 2})
	var bounty: Array = c.get("recorder_bounty", [3000, 8000])
	items.append({"kind": "recorder", "ship": ship_name, "bounty": roundi(r.randf_range(float(bounty[0]), float(bounty[1])) * (float(c.get("deep_recorder_mult", 1.5)) if deep else 1.0) / 100.0) * 100,
			"at": helm if helm >= 0 else int(walkable[0]), "slot": 3})
	var crew := []
	crew.append_array(dead)
	crew.append_array(gone)
	if not survivor.is_empty():
		crew.append(String(survivor.name))
	return {"cause": cause, "log": log, "crew": crew, "items": items, "helm": helm}


## "A", "A and B", "A, B and C".
static func _and(names: Array) -> String:
	if names.size() <= 1:
		return "".join(names)
	return ", ".join(names.slice(0, names.size() - 1)) + " and " + String(names.back())
