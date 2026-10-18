class_name Session
extends RefCounted
## The game being played right now: which slot, and the player's profile.
## Scenes read this instead of passing arguments, so any scene can be opened on its own.

const BOOT_SCENE := "res://scenes/boot.tscn"
const DOCK_SCENE := "res://scenes/dock.tscn"   ## the station terminal: every action as a menu
const PLACE_SCENE := "res://scenes/place.tscn"  ## walking the port, hab or camp: where a flight comes home to
const YARD_SCENE := "res://scenes/main.tscn"
const FLIGHT_SCENE := "res://scenes/flight.tscn"

static var slot := -1  ## -1 when a scene was opened on its own, outside a saved game
static var profile: Dictionary = default_profile()
static var skip_intro := false  ## set when returning to the title so the splash and video don't replay
static var flash := ""  ## one-shot message for the next dock screen
static var sim: EconomySim = null  ## the living economy for this game (see SimWorld); null outside a saved game


static func default_profile() -> Dictionary:
	return {
		"name": "Captain",
		"species": "human",
		"race": "human",
		"difficulty": "normal",
		"world": "concord",  # starting system id / yard id
		"system_id": "new_houston",
		"port_id": "roosevelt_orbital_freight",
		"ship_name": "",
		"location": "dock",  # "dock" or "shipyard"
		"seen_welcome": false,
		"credits": 150000,
		"saved_at": 0,
	}


static func start_funds() -> int:
	return int(Worlds.difficulty(profile.difficulty).funds)


static func yard() -> Dictionary:
	return Worlds.yard(String(profile.world))


static func world() -> Dictionary:
	return yard()


static func ship_label() -> String:
	return ship_label_for(profile)


static func ship_label_for(p: Dictionary) -> String:
	var n := String(p.get("ship_name", "")).strip_edges()
	return n if n != "" else "Unnamed ship"


static func ship_cost(ship: ShipData, library: ModuleLibrary) -> int:
	var total := 0
	for m in ship.modules:
		total += ShipData.paid(m, library)
	return total


## Starts a fresh game in `at_slot`: the starter ship, docked at the chosen world's yard.
## Any save already in that slot is parked, not deleted.
static func begin_new(at_slot: int, name: String, species_id: String, difficulty: String, world_id: String) -> bool:
	var p := default_profile()
	p["name"] = name.strip_edges() if name.strip_edges() != "" else "Captain"
	p["species"] = species_id
	p["difficulty"] = difficulty
	p["ftl_rules"] = 1   # FTL is a fitted drive, not a given
	p["crew"] = []       # hired at a bar (Crew); the captain flies alone until then
	p["world"] = world_id
	p["system_id"] = Worlds.yard_system(world_id)
	p["port_id"] = String(Worlds.primary_port(p.system_id).get("id", ""))
	var lib := ModuleLibrary.new()
	var ship := ShipData.new(lib)
	ShipPresets.build(ship)
	p["credits"] = int(Worlds.difficulty(difficulty).funds) - ship_cost(ship, lib)
	var data: Dictionary = JSON.parse_string(ship.to_json())
	data["cargo"] = CargoManifest.new(ship).to_dict()
	data["earned"] = 0
	data["profile"] = p
	sim = SimWorld.create(p, ship)
	if sim != null:
		data["sim"] = SimWorld.serialize(sim)
	SaveSlots.park(at_slot)
	if not SaveSlots.write(at_slot, data):
		return false
	slot = at_slot
	profile = p
	return true


static func load_slot(from_slot: int) -> bool:
	var data := SaveSlots.read(from_slot)
	if data.is_empty() or not data.has("modules"):
		return false
	slot = from_slot
	if String((data.get("active_contract", {}) as Dictionary).get("person_kind", "")) == "passenger":
		Passengers.migrate(data)   # saved when passengers were a contract: now they're a booking
		SaveSlots.write(slot, data)
	profile = SaveSlots.profile(from_slot)
	if not (data.get("profile", {}) as Dictionary).has("ftl_rules"):
		# Saved before FTL drives were a separate part: that ship keeps the jump capability it was flown with.
		profile["ftl_rules"] = 1
		profile["ftl_grandfathered"] = true
		data["profile"] = profile
		SaveSlots.write(slot, data)
	if not profile.has("crew"):   # saved before named crew: the hands the ship needed get names
		var old := ShipData.new(ModuleLibrary.new())
		if old.from_json(JSON.stringify(data)):
			_migrate_crew(old)
			data["profile"] = profile
			SaveSlots.write(slot, data)
	sim = SimWorld.restore(String(data["sim"])) if data.has("sim") else null
	if sim != null and sim.dev.is_empty():   # saved before frontier growth: everywhere starts at its canon size now
		Development.enable(sim)
	if sim == null:   # older save: the world starts now, around the player's current ship
		var ship := ShipData.new(ModuleLibrary.new())
		if ship.from_json(JSON.stringify(data)):
			sim = SimWorld.create(profile, ship)
	return true


static func system_id() -> String:
	var id := String(profile.get("system_id", ""))
	return id if id != "" else Worlds.yard_system(String(profile.world))


static func port() -> Dictionary:
	var id := String(profile.get("port_id", ""))
	if id == "":
		return Worlds.primary_port(system_id())
	var real := Worlds.port(id)
	return real if not real.is_empty() else LocalSpace.node(id)


## In-system jobs posted at the ship's current site, for the ship as it is now.
static func local_board() -> Array[Dictionary]:
	if slot < 0 or sim == null:
		return []
	var loaded := _load_ship(SaveSlots.read(slot))
	if loaded.is_empty():
		return []
	var st := ship_stats(loaded.ship)
	var id := String(profile.get("port_id", ""))
	if LocalSpace.node(id).is_empty():
		id = String(LocalSpace.nodes(system_id())[0]["id"])
	return LocalSpace.board(id, day(), st, SimShip.level(String(profile.get("difficulty", "normal"))), profile.get("local_taken", []))


## Propellant and berth fee for one local hop with `cargo_t` aboard, in credits.
static func local_trip_cost(stats: Dictionary, cargo_t: float, dv_kms: float) -> Dictionary:
	var burn := LocalSpace.burn_t(float(stats["wet"]) + cargo_t, dv_kms) * Crew.fuel_mult(crew())   # a pilot aboard burns less
	var lv := SimShip.level(String(profile.get("difficulty", "normal")))
	var units := burn * float(SimShip.config()["fuel"]["units_per_tonne"])
	var fuel_cost: float = units * float(sim.p["fuel_cr_per_unit"]) * float(sim.fuel_factor.get(system_id(), 1.0)) * float(lv.get("fuel_price_mult", 1.0)) * site_fuel_mult()
	var fee: float = float(LocalSpace.config()["board"]["dock_fee_cr"]) * float(lv.get("port_fee_mult", 1.0))
	return {"burn_t": burn, "fuel_cost": fuel_cost, "fee": fee, "total": fuel_cost + fee}


static func active_contract() -> Dictionary:
	if slot < 0:
		return {}
	return SaveSlots.read(slot).get("active_contract", {})


## Loads the saved ship and cargo for the current slot.
static func _load_ship(data: Dictionary) -> Dictionary:
	var ship := ShipData.new(ModuleLibrary.new())
	if not ship.from_json(JSON.stringify(data)):
		return {}
	var manifest := CargoManifest.new(ship)
	manifest.from_dict(data.get("cargo", {}))
	return {"ship": ship, "manifest": manifest}


## Puts the sim in step with the saved ship, money and position before it is used.
## Ship stats as the dock sees them, with the grandfathered FTL flag applied.
static func ship_stats(ship: ShipData, manifest: CargoManifest = null) -> Dictionary:
	var st := ShipStats.compute(ship, 1.0, manifest)
	if bool(profile.get("ftl_grandfathered", false)):
		st["ftl"] = true
	elif bool(st.get("ftl", false)) and not Wear.drive_ok(ship, wear()):
		st["ftl"] = false   # a drive that has failed doesn't jump, however much it cost
		(st["warnings"] as Array).append("FTL drive failed: a spares kit on a space walk, or an overhaul at a yard")
	st["crew_aboard"] = crew_aboard() if profile.has("crew") else int(st.get("crew_needed", 1))
	st["rescued"] = (profile.get("rescued", []) as Array).size()   # survivors off wrecks, in bunks (or the jump seat)
	return st


static func has_ftl(ship: ShipData) -> bool:
	return bool(ship_stats(ship).get("ftl", false))


static func _sync_sim(ship: ShipData) -> void:
	if sim != null:
		SimWorld.sync(sim, profile, ship)


## After the sim ran: take credits from it, record where the game has got to, and save.
static func _commit_sim(data: Dictionary, ship: ShipData) -> void:
	if sim == null:
		return
	profile["credits"] = SimWorld.credits(sim)
	data["earned"] = int(profile.credits) - start_funds() + ship_cost(ship, ship.library)
	data["sim"] = SimWorld.serialize(sim)


## Days the world has run since this game began its warm-up, for display.
static func day() -> int:
	return SimWorld.day(sim) if sim != null else 0


## Close out a flight: fuel burned and repairs are paid, and the clock moves on. Returns a line to show.
static func finish_flight(fuel_burned_t: float, seconds: float, damage: float) -> String:
	if slot < 0 or sim == null:
		return ""
	var data := SaveSlots.read(slot)
	var loaded := _load_ship(data)
	if loaded.is_empty():
		return ""
	_sync_sim(loaded.ship)
	var r := SimWorld.settle_flight(sim, fuel_burned_t, seconds, 0.0, float(ship_cost(loaded.ship, loaded.ship.library)), site_fuel_mult())
	profile["hull_damage"] = clampf(damage, 0.0, 1.0)   # carried until repaired at a fuel and repair desk
	var rescued := bool(flight_extra.get("rescue", false))
	var tow := 0.0
	if rescued:
		var lv := SimShip.level(String(profile.get("difficulty", "normal")))
		tow = float(LocalSpace.config()["board"]["tow_fee_cr"]) * float(lv.get("port_fee_mult", 1.0))
		sim._pay(SimWorld.PLAYER, "world", tow)
	var hull_note := _settle_hull(data, active_contract(), float(ship_cost(loaded.ship, loaded.ship.library)))
	_commit_sim(data, loaded.ship)
	data["profile"] = profile
	SaveSlots.write(slot, data)
	flash = "Flight over (%d min). Fuel %s cr%s.%s%s" % [roundi(seconds / 60.0), ShipStats.commas(int(r.fuel_cost)),
			", hull repairs %s cr" % ShipStats.commas(int(r.repair_cost)) if int(r.repair_cost) > 0 else "",
			" Hull breached: towed in for %s cr." % ShipStats.commas(roundi(tow)) if rescued else "", hull_note]
	return flash


## What the bank will do for a bankrupt captain: take the ship at half its price, clear what is still
## owed, and hand over a plain starter hauler with ten days of running costs in the till. The run
## goes on, but you start again from the bottom and the count of failures stays on the record.
static func restructure() -> Dictionary:
	if not insolvent():
		return {"ok": false, "message": "No debt, no bank. It only visits when you owe it."}
	var data := SaveSlots.read(slot)
	var loaded := _load_ship(data)
	if loaded.is_empty():
		return {"ok": false, "message": "Couldn't load the ship from the save."}
	var sale := roundi(float(ship_cost(loaded.ship, loaded.ship.library)) * 0.5)
	var left := maxi(0, int(profile.credits) + sale)
	var fresh := ShipData.new(ModuleLibrary.new())
	ShipPresets.build(fresh)
	var parsed: Dictionary = JSON.parse_string(fresh.to_json())
	data["modules"] = parsed["modules"]
	data["cargo"] = CargoManifest.new(fresh).to_dict()
	data.erase("active_contract")
	profile["bankruptcies"] = int(profile.get("bankruptcies", 0)) + 1
	profile["ftl_grandfathered"] = false   # the bank's hauler is the plain sublight starter
	profile["hull_damage"] = 0.0
	var room := maxi(0, int(ShipStats.compute(fresh).get("berths", 0)) - 1)
	if crew().size() > room:   # the bank's hauler has fewer bunks: the newest hands are let go, unpaid
		profile["crew"] = crew().slice(0, room)
	if LocalSpace.is_surface(String(profile.get("port_id", ""))):
		profile["port_id"] = system_id() + LocalSpace.SEP + "moon"   # it cannot lift off: the bank's tug brings it up to the base's station
	profile["credits"] = left
	_sync_sim(fresh)
	var grant := roundi(SimWorld.daily_cost(sim) * 10.0)
	profile["credits"] = left + grant
	_sync_sim(fresh)
	_commit_sim(data, fresh)
	data["profile"] = profile
	SaveSlots.write(slot, data)
	flash = "The bank took your ship for %s cr, cleared your debts and lent you a starter hauler with %s cr. Fresh start, same bank." % [ShipStats.commas(sale), ShipStats.commas(int(profile.credits))]
	return {"ok": true, "message": flash}


## How the captain's run went, for the bankruptcy screen and anything that wants a summary.
static func run_report() -> Dictionary:
	if sim == null:
		return {}
	var c := SimWorld.player(sim)
	var jobs := 0
	var tonnes := 0.0
	for k in sim.contracts.values():
		if k.get("carrier", "") == SimWorld.PLAYER and k["status"] == "delivered":
			jobs += 1
			tonnes += float(k["mass_kg"]) / 1000.0
	return {"days": day(), "jobs": jobs, "tonnes": tonnes, "revenue": float(c.get("revenue", 0.0)), "costs": float(c.get("costs", 0.0)),
			"credits": int(profile.get("credits", 0))}


## True once the captain is in debt with no contract in hand: the bank takes the ship and the run ends.
static func insolvent() -> bool:
	return sim != null and int(profile.get("credits", 0)) < 0 and active_contract().is_empty()


## Let the world run while the ship sits in port. Wages and ownership still cost money.
static func wait_days(days: int) -> Dictionary:
	if slot < 0 or sim == null or days < 1:
		return {"ok": false, "message": "No saved game, no clock. Load one first."}
	if not active_contract().is_empty():
		return {"ok": false, "message": "Finish the active contract first. The load is waiting."}
	var data := SaveSlots.read(slot)
	var loaded := _load_ship(data)
	if loaded.is_empty():
		return {"ok": false, "message": "Couldn't load the ship from the save."}
	_sync_sim(loaded.ship)
	var before := int(profile.credits)
	sim.run_hours(days * 24)
	var work := _crew_between(loaded.ship, days * 24.0).replace("On the way", "In port")
	_commit_sim(data, loaded.ship)
	data["profile"] = profile
	SaveSlots.write(slot, data)
	return {"ok": true, "message": "%d day%s in port. Running costs: %s cr.%s" % [days, "" if days == 1 else "s", ShipStats.commas(before - int(profile.credits)), work]}


## Fly empty to another system, the way out of a port with no freight. Time passes and costs money.
static func travel_empty(dest_system_id: String) -> Dictionary:
	if slot < 0 or sim == null:
		return {"ok": false, "message": "No saved game, nowhere to go. Load one first."}
	if not active_contract().is_empty():
		return {"ok": false, "message": "Finish the active contract first. The load is waiting."}
	if hull_block(false) != "":
		return {"ok": false, "message": hull_block(false)}
	var data := SaveSlots.read(slot)
	var loaded := _load_ship(data)
	if loaded.is_empty():
		return {"ok": false, "message": "Couldn't load the ship from the save."}
	_sync_sim(loaded.ship)
	var before := int(profile.credits)
	var r := sim.player_reposition(SimWorld.PLAYER, dest_system_id)
	if not bool(r.ok):
		return r
	var hours := sim.run_player_until(SimWorld.PLAYER, "done")
	_autopilot_wear(loaded.ship, float(Wear.cfg().get("jump_engine", 0.03)), float(Wear.cfg().get("jump_radiator", 0.02)), float(Wear.cfg().get("jump_drive", 0.02)))
	var work := _crew_between(loaded.ship, float(hours))
	profile["system_id"] = dest_system_id
	profile["port_id"] = sim.net.primary_port(dest_system_id)
	_commit_sim(data, loaded.ship)
	data["profile"] = profile
	SaveSlots.write(slot, data)
	var pax := Passengers.count() > 0
	var msg := "Flew %s to %s in %.1f days. Running costs: %s cr%s.%s" % ["with no freight" if pax else "empty", dest_system_id.replace("_", " ").capitalize(), hours / 24.0, ShipStats.commas(before - int(profile.credits)), "" if pax else ", for hauling air", work]
	return {"ok": true, "message": msg + Passengers.set_down()}


static func accept_contract(contract: Dictionary) -> Dictionary:
	if String(contract.get("person_kind", "")) == "passenger":
		return Passengers.book(contract)   # passengers ride along with whatever else the ship is doing
	if slot < 0 or contract.is_empty() or not active_contract().is_empty():
		return {"ok": false, "message": "One contract at a time, and only in a saved game."}
	var data := SaveSlots.read(slot)
	var loaded_ship := _load_ship(data)
	if loaded_ship.is_empty():
		return {"ok": false, "message": "Couldn't load the ship from the save."}
	var manifest: CargoManifest = loaded_ship.manifest
	var tonnes := float(contract.offer)
	var accepted := contract.duplicate(true)
	var live := sim != null and contract.has("sim_contract")
	var is_local := bool(contract.get("local", false))
	if is_local:
		var stats := ship_stats(loaded_ship.ship)
		var cap := LocalSpace.max_cargo_t(float(stats["wet"]), float(stats["fuel"]), float(contract["dv_kms"]))
		tonnes = minf(tonnes, maxf(cap, 0.0))
		if tonnes <= 0.0 and String(contract.get("person_kind", "")) != "passenger":
			return {"ok": false, "message": "Tanks can't haul a load that far. Optimism isn't fuel."}
	if live:
		_sync_sim(loaded_ship.ship)
		var taken := sim.player_accept(SimWorld.PLAYER, String(contract.sim_contract))
		if not bool(taken.ok):
			return {"ok": false, "message": String(taken.message)}
		var k: Dictionary = taken.contract
		tonnes = float(k.mass_kg) / 1000.0
		accepted["sim_taken"] = String(k.id)
		accepted["offer"] = tonnes
		accepted["pay_total"] = roundi(sim.pay_for(SimWorld.PLAYER, k))
		accepted["rate"] = float(accepted.pay_total) / maxf(tonnes, 0.001)
	var person := String(contract.get("person_kind", ""))
	if contract.has("locked"):
		return {"ok": false, "message": "%s won't deal with you yet. %s." % [String(contract.get("person", "They")), String(contract.locked)]}
	var loaded := 0.0
	if person == "passenger":
		var have := People.seats(ship_stats(loaded_ship.ship))
		if have < int(contract.seats):
			return {"ok": false, "message": "%s needs %d spare berth%s; you have %d. Fit crew bunks or quarters at a shipyard. Laps don't count." % [
					String(contract.person) if int(contract.seats) == 1 else String(contract.person) + "'s party", int(contract.seats), "" if int(contract.seats) == 1 else "s", have]}
	else:
		loaded = manifest.load(StringName(contract.commodity), tonnes)
		if loaded <= CargoManifest.EPS:
			return {"ok": false, "message": "No hold aboard can take this cargo type."}
	if person != "":
		accepted["hull_at_accept"] = float(profile.get("hull_damage", 0.0))
		if contract.has("due_in_hours") and sim != null:
			accepted["due_hour"] = sim.hour + int(contract.due_in_hours)
	if is_local:
		accepted["pay_total"] = int(contract.fare) if person == "passenger" else roundi(loaded * float(contract.rate))
		var done: Array = profile.get("local_taken", [])
		done.append(String(contract.id))
		profile["local_taken"] = done.slice(maxi(0, done.size() - 40))
	accepted["accepted_tonnes"] = loaded
	accepted["status"] = "loaded"
	data["cargo"] = manifest.to_dict()
	data["active_contract"] = accepted
	data["profile"] = profile
	if live:
		_commit_sim(data, loaded_ship.ship)
	if not SaveSlots.write(slot, data):
		return {"ok": false, "message": "Couldn't save the contract to the save file."}
	if person == "passenger":
		return {"ok": true, "message": ("%s is aboard." if int(contract.seats) == 1 else "%s's party is aboard.") % String(contract.person)}
	return {"ok": true, "message": "Loaded %.1f t of %s." % [loaded, Worlds.commodity(String(contract.commodity)).name]}


## Sites in this system the ship could fly to empty, with the hop's cost and the jobs posted there.
static func local_sites() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if slot < 0 or sim == null:
		return out
	var loaded := _load_ship(SaveSlots.read(slot))
	if loaded.is_empty():
		return out
	var st := ship_stats(loaded.ship)
	var here := LocalSpace.node(String(profile.get("port_id", "")))
	if here.is_empty():
		return out
	var lv := SimShip.level(String(profile.get("difficulty", "normal")))
	for n in LocalSpace.nodes(system_id()):
		if String(n["id"]) == String(here["id"]):
			continue
		if (bool(n.get("surface", false)) or bool(here.get("surface", false))) and not LocalSpace.can_land(st, system_id()):
			continue   # landing (or lifting off) needs lander legs with the lift for this moon
		var h := LocalSpace.hop(String(here["kind"]), String(n["kind"]))
		if LocalSpace.max_cargo_t(float(st["wet"]), float(st["fuel"]), float(h["dv_kms"])) < 0.0:
			continue   # out of reach of the tank even empty
		var cost := local_trip_cost(st, 0.0, float(h["dv_kms"]))
		var jobs := LocalSpace.board(String(n["id"]), day() + int(h["hours"]) / 24, st, lv, profile.get("local_taken", []))
		out.append({"id": n["id"], "name": n["name"], "dv_kms": h["dv_kms"], "hours": h["hours"], "cost": cost["total"], "jobs": jobs.size()})
	return out


## Fly empty to another site in this system.
static func local_reposition(dest_id: String) -> Dictionary:
	if slot < 0 or sim == null:
		return {"ok": false, "message": "No saved game, nowhere to go. Load one first."}
	if not active_contract().is_empty():
		return {"ok": false, "message": "Finish the active contract first. The load is waiting."}
	if hull_block(false) != "":
		return {"ok": false, "message": hull_block(false)}
	for site in local_sites():
		if String(site["id"]) != dest_id:
			continue
		var data := SaveSlots.read(slot)
		var loaded := _load_ship(data)
		if loaded.is_empty():
			return {"ok": false, "message": "Couldn't load the ship from the save."}
		_sync_sim(loaded.ship)
		var before := int(profile.credits)
		var hrs := maxi(1, ceili(float(site["hours"]) * Crew.time_mult(crew())))   # a pilot aboard flies it tighter
		sim._pay(SimWorld.PLAYER, "world", float(site["cost"]))
		sim.run_hours(hrs)
		_autopilot_wear(loaded.ship, float(Wear.cfg().get("reposition_engine", 0.01)), 0.0)
		var work := _crew_between(loaded.ship, float(hrs))
		profile["port_id"] = dest_id
		_commit_sim(data, loaded.ship)
		data["profile"] = profile
		SaveSlots.write(slot, data)
		return {"ok": true, "message": "Flew %s to %s in %d hours. Fuel and running costs: %s cr.%s" % ["with no freight" if Passengers.count() > 0 else "empty", String(site["name"]), hrs, ShipStats.commas(before - int(profile.credits)), work] + Passengers.set_down()}
	return {"ok": false, "message": "Your tanks can't reach that site."}


## Finds on this system's moon that are still there today (samples and salvage), with whether taken.
static func finds_here() -> Array[Dictionary]:
	var taken: Array = profile.get("finds_taken", [])
	var out: Array[Dictionary] = []
	for f in SurfaceFinds.list(system_id(), day()):
		var g := f.duplicate()
		g["taken"] = String(f.id) in taken
		out.append(g)
	return out


## Pick up a find on foot. It goes in the ship's locker until sold at a dock.
static func take_find(id: String) -> Dictionary:
	if slot < 0:
		return {"ok": false, "message": ""}
	for f in finds_here():
		if String(f.id) != id:
			continue
		if bool(f.taken):
			return {"ok": false, "message": "Already taken."}
		var taken: Array = profile.get("finds_taken", [])
		taken.append(id)
		while taken.size() > 200:
			taken.pop_front()
		profile["finds_taken"] = taken
		var kind := String(f.kind)
		var key: String = SurfaceFinds.KINDS.get(kind, "samples")
		var n := int(f.get("units", SurfaceFinds.units(kind)))
		profile[key] = int(profile.get(key, 0)) + n
		save_profile()
		if kind == "salvage":
			return {"ok": true, "message": "Stripped %d salvage parts from the %s." % [n, "wreck" if String(f.name).begins_with("Wreck") else String(f.name).to_lower()]}
		return {"ok": true, "message": "%s %s." % [String(f.name), "cut" if kind == "ice" else "bagged"]}
	return {"ok": false, "message": "Nothing here worth taking."}


## What is in the locker, by counter (samples, salvage, ice, rare), and what it would fetch.
static func finds_aboard() -> Dictionary:
	var out := {"value": 0}
	for k in SurfaceFinds.KINDS:
		var key: String = SurfaceFinds.KINDS[k]
		out[key] = int(profile.get(key, 0))
		out["value"] = int(out.value) + int(out[key]) * SurfaceFinds.value(k)
	return out


## Sell from the locker here. `rates` scales the standard price of each kind of find (a lab pays more for
## samples and crystals and takes no salvage or ice; the camp's exchange pays well for ice); a rate of 0
## keeps those aboard. Kinds not named sell at the standard price.
static func sell_finds(rates: Dictionary = {}) -> Dictionary:
	var held := finds_aboard()
	var sold := {}
	var value := 0.0
	for k in SurfaceFinds.KINDS:
		var key: String = SurfaceFinds.KINDS[k]
		var rate := float(rates.get(k, 1.0))
		sold[key] = int(held[key]) if rate > 0.0 else 0
		value += int(sold[key]) * SurfaceFinds.value(k) * rate
	if roundi(value) <= 0 or slot < 0 or sim == null:
		return {"ok": false, "message": "Nothing here they'll buy."}
	var data := SaveSlots.read(slot)
	var loaded := _load_ship(data)
	if loaded.is_empty():
		return {"ok": false, "message": "Couldn't load the ship from the save."}
	_sync_sim(loaded.ship)
	sim._pay("world", SimWorld.PLAYER, float(roundi(value)))
	SimStats.on_salvage(sim, float(roundi(value)))   # finds count with salvage in the trade report
	var pc: Dictionary = sim.carriers[SimWorld.PLAYER]
	pc["revenue"] = float(pc["revenue"]) + float(roundi(value))
	for key in sold:
		profile[key] = int(held[key]) - int(sold[key])
	_commit_sim(data, loaded.ship)
	data["profile"] = profile
	SaveSlots.write(slot, data)
	return {"ok": true, "message": "Sold %s for %s cr." % [SurfaceFinds.describe(sold), ShipStats.commas(roundi(value))], "value": roundi(value)}


## What the locker would fetch at these `rates` (as sell_finds).
static func finds_value(rates: Dictionary = {}) -> int:
	var held := finds_aboard()
	var value := 0.0
	for k in SurfaceFinds.KINDS:
		value += int(held[SurfaceFinds.KINDS[k]]) * SurfaceFinds.value(k) * float(rates.get(k, 1.0))
	return roundi(value)


## Money between the player and the world outside a run (gear, missions, fees). `amount` > 0 is paid
## to the player. Returns false when it could not be booked, or the player cannot pay.
static func _book(amount: float) -> bool:
	if slot < 0 or sim == null:
		return false
	var data := SaveSlots.read(slot)
	var loaded := _load_ship(data)
	if loaded.is_empty():
		return false
	_sync_sim(loaded.ship)
	if amount < 0.0 and int(profile.get("credits", 0)) < roundi(-amount):
		return false
	if amount >= 0.0:
		sim._pay("world", SimWorld.PLAYER, amount)
		var pc: Dictionary = sim.carriers[SimWorld.PLAYER]
		pc["revenue"] = float(pc["revenue"]) + amount
	else:
		sim._pay(SimWorld.PLAYER, "world", -amount)
	_commit_sim(data, loaded.ship)
	data["profile"] = profile
	SaveSlots.write(slot, data)
	return true


# --- The suit and surface work (SurfaceWork) ---------------------------------------------------------

static var suit_up := false   ## set by the airlock desk: the flight scene opens with you outside in the suit


static func gear_owned() -> Array:
	return profile.get("gear", [])


static func buy_gear(id: String) -> Dictionary:
	var g := SurfaceWork.gear(id)
	if g.is_empty():
		return {"ok": false, "message": "The store has no such thing."}
	var owned := gear_owned()
	if id in owned:
		return {"ok": false, "message": "You already have the %s." % String(g.name).to_lower()}
	if g.has("needs") and not String(g.needs) in owned:
		return {"ok": false, "message": "Needs the %s first." % String(SurfaceWork.gear(String(g.needs)).name).to_lower()}
	var price := int(g.price)
	if not _book(-float(price)):
		return {"ok": false, "message": "The %s costs %s cr; you have %s cr. No credit." % [String(g.name).to_lower(), ShipStats.commas(price), ShipStats.commas(int(profile.get("credits", 0)))]}
	owned = owned.duplicate()
	owned.append(id)
	profile["gear"] = owned
	save_profile()
	return {"ok": true, "message": "Bought the %s for %s cr." % [String(g.name).to_lower(), ShipStats.commas(price)]}


## The surface site the ship is at ("pad" or "camp"), or "".
static func surface_site() -> String:
	var k := String(LocalSpace.node(String(profile.get("port_id", ""))).get("kind", ""))
	return k if k in LocalSpace.SURFACE else ""


static func missions_here() -> Array[Dictionary]:
	var site := surface_site()
	if site == "" or sim == null:
		return []
	return SurfaceWork.offered(system_id(), site, day(), profile.get("missions_taken", []))


static func mission() -> Dictionary:
	return profile.get("mission", {})


static func take_mission(m: Dictionary) -> Dictionary:
	if not mission().is_empty():
		return {"ok": false, "message": "One mission at a time. Finish yours first."}
	if bool(m.get("taken", false)):
		return {"ok": false, "message": "Someone else has that one."}
	var held := m.duplicate(true)
	var done := []
	for p in held.points:
		done.append(false)
	held["done"] = done
	held["elapsed_s"] = 0.0
	held["hold_t"] = 0.0
	profile["mission"] = held
	var t: Array = profile.get("missions_taken", [])
	t = t.duplicate()
	t.append(String(m.id))
	profile["missions_taken"] = t.slice(maxi(0, t.size() - 40))
	save_profile()
	return {"ok": true, "message": "%s: %s outside. Suit up at the airlock; the clock runs while you're out and won't wait." % [String(m.title), SurfaceWork.clock(float(m.limit_s))]}


## Pay out a finished mission.
static func complete_mission() -> Dictionary:
	var m := mission()
	if m.is_empty():
		return {"ok": false, "message": ""}
	profile.erase("mission")
	_book(float(m.pay))
	var rep := _add_rep(int(m.get("rep", 2)))
	save_profile()
	return {"ok": true, "message": "%s: done. Paid %s cr.%s" % [String(m.title), ShipStats.commas(int(m.pay)), rep]}


static func fail_mission(why: String) -> Dictionary:
	var m := mission()
	if m.is_empty():
		return {"ok": false, "message": ""}
	profile.erase("mission")
	var rep := _add_rep(int(SurfaceWork.config().get("missions", {}).get("fail_rep", -2)))
	save_profile()
	return {"ok": true, "message": "%s: failed, %s.%s" % [String(m.title), why, rep]}


## Out of air: the base or camp crew drag you in. A fee, and any mission is lost.
static func suit_rescue() -> String:
	var fee := float(SurfaceWork.suit_cfg().get("rescue_fee_cr", 800))
	var paid := _book(-fee)
	var msg := "Out of air. The crew hauled you back aboard%s, grumbling." % (" and billed you %s cr" % ShipStats.commas(roundi(fee)) if paid else "")
	if not mission().is_empty():
		msg += " " + String(fail_mission("you ran out of air").message)
	return msg


## Carry the load off yourself at the camp (the crew's fee saved). Returns the crates to carry.
static func start_manual_unload() -> Dictionary:
	var c := active_contract()
	if c.is_empty() or String(c.get("status", "")) != "arrived" or surface_site() != "camp":
		return {"ok": false, "message": "Nothing to unload here."}
	if String(c.get("person_kind", "")) == "passenger":
		return {"ok": false, "message": "Passengers walk off on their own. Mostly."}
	var n := SurfaceWork.crates_for(float(c.get("accepted_tonnes", c.offer)))
	profile["unloading"] = {"crates": n, "done": 0}
	save_profile()
	suit_up = true
	return {"ok": true, "message": "%d crates to carry to the stack by the hut." % n}


static func unloading() -> Dictionary:
	return profile.get("unloading", {})


## One crate carried to the stack. The last one delivers the load.
static func crate_carried() -> Dictionary:
	var u := unloading()
	if u.is_empty():
		return {"ok": false, "message": ""}
	u["done"] = int(u.done) + 1
	if int(u.done) < int(u.crates):
		profile["unloading"] = u
		save_profile()
		return {"ok": true, "message": "Crate %d of %d on the stack." % [int(u.done), int(u.crates)], "finished": false}
	profile.erase("unloading")
	var r := deliver_active_contract(true)
	r["finished"] = true
	return r


## Fuel here against the system's price: depots are cheap, the surface dear (local_space.json).
static func site_fuel_mult(site_id: String = "") -> float:
	var id := site_id if site_id != "" else String(profile.get("port_id", ""))
	var kind := String(LocalSpace.node(id).get("kind", "port"))
	return float(LocalSpace.config().get("site_fuel_price", {}).get(kind, 1.0)) * Development.price_mult(sim, id)   # dearer on the edge, cheaper as it grows


static func site_repair_mult() -> float:
	var id := String(profile.get("port_id", ""))
	var kind := String(LocalSpace.node(id).get("kind", "port"))
	return float(LocalSpace.config().get("site_repair_rate", {}).get(kind, 1.0)) * Development.price_mult(sim, id)


## Whether the site you're at has a service at its size (frontier growth): freight, repairs,
## passengers, crew, yard.
static func site_has(service: String) -> bool:
	return Development.has(sim, String(profile.get("port_id", "")), service)


## Strip an abandoned site's fittings for salvage: a few parts, then nothing until it's been a while.
static func strip_fittings() -> Dictionary:
	var id := String(profile.get("port_id", ""))
	if not Development.abandoned(sim, id):
		return {"ok": false, "message": "People still work here. They'd notice."}
	var cfg: Dictionary = Development.config().get("abandoned_salvage", {})
	var every := int(cfg.get("every_days", 20))
	var done: Dictionary = profile.get("stripped", {})
	var last := int(done.get(id, -100000))
	if day() - last < every:
		return {"ok": false, "message": "You've had everything worth unbolting. Come back in %d days, when you've forgotten how little there was." % (every - (day() - last))}
	var n := int(cfg.get("parts", 3))
	profile["salvage"] = int(profile.get("salvage", 0)) + n
	done = done.duplicate()
	done[id] = day()
	profile["stripped"] = done
	save_profile()
	return {"ok": true, "message": "Stripped %d salvage parts from what they left behind. They left in a hurry." % n}


## What fixing the hull costs here: all of it, or `amount` of it (a fraction of the whole hull).
static func repair_cost(amount := -1.0) -> int:
	var dmg := float(profile.get("hull_damage", 0.0))
	var fix := dmg if amount < 0.0 else minf(amount, dmg)
	if fix <= 0.0 or slot < 0:
		return 0
	var loaded := _load_ship(SaveSlots.read(slot))
	if loaded.is_empty():
		return 0
	var lv := SimShip.level(String(profile.get("difficulty", "normal")))
	var frac := float(FlightModel.load_tuning().get("repair_cost_fraction_of_ship", 0.15))
	return roundi(fix * float(ship_cost(loaded.ship, loaded.ship.library)) * frac * float(lv.get("maintenance_mult", 1.0)) * site_repair_mult())


static func hull_faults_cfg() -> Dictionary:
	return FlightModel.load_tuning().get("hull_faults", {})


## Hull left, 0..1.
static func hull() -> float:
	return clampf(1.0 - float(profile.get("hull_damage", 0.0)), 0.0, 1.0)


## Why port control won't let the ship go, or "" when it will. A breached hull (0%) goes nowhere at
## all; below the unsafe line (25%) it may still fly empty (`with_load` false), at the captain's risk.
static func hull_block(with_load := true) -> String:
	if slot >= 0 and not engines_work():
		var loaded := _load_ship(SaveSlots.read(slot))
		if not loaded.is_empty() and float(ShipStats.compute(loaded.ship).thrust_fwd) <= 0.0:
			return "No engine pushing aft. The clamps stay shut until something can push: fit one at the shipyard, nozzle to the stern."
		return "Every engine has failed. The clamps stay shut until something can push: a space walk with a spares kit, or the yard's overhaul."
	var h := hull()
	if h <= 0.001:
		return "The hull is breached. Port control won't even open the clamps. The repair desk does patches, on account if it must."
	var unsafe := float(hull_faults_cfg().get("unsafe_hull", 0.25))
	if with_load and h < unsafe - 0.0001:
		return "Port control won't clear a ship at %d%% hull to carry freight. Patch it above %d%% at the repair desk. Flying empty is your own funeral." % [roundi(h * 100.0), roundi(unsafe * 100.0)]
	return ""


## The patches the repair desk offers short of a full repair: {afford: {to, cost}} for as much as the
## credits buy, in steps, and {account: {to, cost}} for a patch on account to just above the unsafe
## line when even that is out of reach. Either is {} when it doesn't apply.
static func patch_options() -> Dictionary:
	var out := {"afford": {}, "account": {}}
	var dmg := float(profile.get("hull_damage", 0.0))
	if dmg <= 0.0 or slot < 0:
		return out
	var cfg := hull_faults_cfg()
	var step := float(cfg.get("patch_step", 0.05))
	var credits := int(profile.get("credits", 0))
	var full := repair_cost()
	if credits < full:
		var steps := 0
		while (steps + 1) * step < dmg and repair_cost((steps + 1) * step) <= credits:
			steps += 1
		if steps > 0:
			out.afford = {"to": hull() + steps * step, "cost": repair_cost(steps * step)}
	var safe := float(cfg.get("unsafe_hull", 0.25)) + step
	if hull() < safe and repair_cost(safe - hull()) > credits:
		out.account = {"to": safe, "cost": repair_cost(safe - hull())}
	return out


## Patch the hull up to `to_hull` (0..1). `on_account`: the yard does it even if it puts you in debt,
## which only it offers for the patch that makes the ship fit to carry freight again.
static func patch_hull(to_hull: float, on_account := false) -> Dictionary:
	var fix := clampf(to_hull, 0.0, 1.0) - hull()
	if fix <= 0.0:
		return {"ok": false, "message": "The hull is already better than that."}
	var cost := repair_cost(fix)
	var data := SaveSlots.read(slot)
	var loaded := _load_ship(data)
	if loaded.is_empty() or sim == null:
		return {"ok": false, "message": "Couldn't load the ship from the save."}
	if not on_account and int(profile.get("credits", 0)) < cost:
		return {"ok": false, "message": "That patch costs %s cr; you have %s cr." % [ShipStats.commas(cost), ShipStats.commas(int(profile.credits))]}
	_sync_sim(loaded.ship)
	sim._pay(SimWorld.PLAYER, "world", float(cost))
	profile["hull_damage"] = clampf(float(profile.get("hull_damage", 0.0)) - fix, 0.0, 1.0)
	_commit_sim(data, loaded.ship)
	data["profile"] = profile
	SaveSlots.write(slot, data)
	if on_account:
		return {"ok": true, "message": "Patched to %d%% on account: %s cr, and you now owe the yard. Plates bolted over plates. It'll fly; don't ask it to enjoy it." % [roundi(hull() * 100.0), ShipStats.commas(cost)]}
	return {"ok": true, "message": "Patched to %d%% for %s cr. Not pretty, but it holds air." % [roundi(hull() * 100.0), ShipStats.commas(cost)]}


## What the rescue tug's salvage crew charges on top of the tow, for a ship that cost `cost` cr.
static func salvage_fee(cost: float) -> int:
	var lv := SimShip.level(String(profile.get("difficulty", "normal")))
	return roundi(cost * float(hull_faults_cfg().get("rescue_salvage_fraction_of_ship", 0.08)) * float(lv.get("maintenance_mult", 1.0)))


## What the flight scene reports beyond fuel, time and damage, set just before it calls a finish_*:
## {rescue: the hull was breached and the rescue tug came, cargo_hurt: 0..1 of the load spoiled by knocks}.
static var flight_extra: Dictionary = {}


## Settle the hull's toll on a flight: the salvage fee if the rescue tug came, and the share of the
## load that's spoiled (knocks, plus what goes over the side in a rescue) kept on the contract for the
## delivery. Returns a note for the flight's message.
static func _settle_hull(data: Dictionary, c: Dictionary, ship_price: float) -> String:
	var ex := flight_extra
	flight_extra = {}
	if ex.has("wear"):   # wear and tear from the flight, and any servicing on a space walk
		profile["wear"] = (ex.wear as Dictionary).duplicate()
	var rescue := bool(ex.get("rescue", false))
	var adrift_note := ""
	if bool(ex.get("adrift", false)):   # the captain drifted off on a space walk: a tug fished them out
		var lvd := SimShip.level(String(profile.get("difficulty", "normal")))
		var fish := float(LocalSpace.config()["board"]["tow_fee_cr"]) * float(lvd.get("port_fee_mult", 1.0))
		sim._pay(SimWorld.PLAYER, "world", fish)
		adrift_note = " A tug fished you out of the dark and towed the ship in: %s cr, and a story nobody believes." % ShipStats.commas(roundi(fish))
	var hurt := clampf(float(ex.get("cargo_hurt", 0.0)), 0.0, 1.0) * Crew.cargo_hurt_mult(crew())   # a loadmaster's lashings hold
	var salvage := salvage_fee(ship_price) if rescue else 0
	if salvage > 0:
		sim._pay(SimWorld.PLAYER, "world", float(salvage))
	var lost := 0.0
	var has_load := not c.is_empty() and String(c.get("person_kind", "")) != "passenger"
	if has_load:
		if rescue:
			hurt = 1.0 - (1.0 - hurt) * (1.0 - float(hull_faults_cfg().get("rescue_cargo_loss", 0.3)))
		if hurt > 0.0:
			var before := float(c.get("cargo_hurt", 0.0))
			c["cargo_hurt"] = 1.0 - (1.0 - before) * (1.0 - hurt)
			data["active_contract"] = c
			lost = float(c.cargo_hurt) - before
	var parts := PackedStringArray()
	if rescue:
		parts.append(" The salvage crew added %s cr for the privilege." % ShipStats.commas(salvage))
	parts.append(_settle_comms(ex.get("comms", {})))
	if lost > 0.005:
		parts.append(" About %d%% of the load is %s; the consignee will notice." % [roundi(lost * 100.0), "over the side or in pieces" if rescue else "dented"])
	return adrift_note + "".join(parts)


## What the radio came to on a flight (Comms.settlement): fuel bought from a hauler and sold to a ship in
## distress, a hauler's tow against the port tug's fee, fines for docking or landing unannounced, and
## the standing that went with it. Returns a note for the flight's message.
static func _settle_comms(c: Dictionary) -> String:
	if c.is_empty() or sim == null:
		return ""
	var bits := PackedStringArray()
	var bought := int(c.get("fuel_bought_cr", 0))
	if bought > 0:
		sim._pay(SimWorld.PLAYER, "world", float(bought))
		bits.append("Fuel off a hauler: %.1f t, %s cr." % [float(c.get("fuel_bought_t", 0.0)), ShipStats.commas(bought)])
	var sold := int(c.get("fuel_sold_cr", 0))
	if sold > 0:
		sim._pay("world", SimWorld.PLAYER, float(sold))
		var pc: Dictionary = sim.carriers[SimWorld.PLAYER]
		pc["revenue"] = float(pc["revenue"]) + float(sold)
		bits.append("Fuel sold to a ship in trouble: %.0f t, %s cr." % [float(c.get("fuel_sold_t", 0.0)), ShipStats.commas(sold)])
	var tow := int(c.get("tow_delta_cr", 0))
	if String(c.get("tow_by", "")) != "":
		if tow > 0:
			sim._pay(SimWorld.PLAYER, "world", float(tow))
		elif tow < 0:
			sim._pay("world", SimWorld.PLAYER, float(-tow))
		bits.append("The %s towed you, not the port tug: %s cr %s the tug's fee." % [String(c.tow_by), ShipStats.commas(absi(tow)), "on top of" if tow >= 0 else "off"])
	var fine := int(c.get("fine_cr", 0))
	if fine > 0:
		sim._pay(SimWorld.PLAYER, "world", float(fine))
	for n in c.get("notes", []):
		bits.append(String(n))
	var rep := int(c.get("rep", 0)) + int(c.get("fine_rep", 0))
	var note := (" " + " ".join(bits)) if not bits.is_empty() else ""
	return note + _add_rep(rep)


## Wear and tear (Wear) ------------------------------------------------------------------------------

static func wear() -> Dictionary:
	return profile.get("wear", {})


static func engines_work() -> bool:
	var loaded := _load_ship(SaveSlots.read(slot))
	if loaded.is_empty():
		return true
	return float(Wear.effective(loaded.ship, wear()).thrust_fwd) > 0.0


## Autopilot and sim trips wear the engines and radiators by the fuel they burn (or a flat amount).
static func _autopilot_wear(ship: ShipData, engine: float, radiator: float, drive := 0.0) -> void:
	var w := wear().duplicate()
	var wm := Crew.wear_mult(crew())   # an engineer aboard keeps it all running sweeter
	Wear.add(w, ship, "engine", engine * wm)
	Wear.add(w, ship, "radiator", radiator * wm)
	if drive > 0.0:
		Wear.add(w, ship, "drive", drive * wm)
	profile["wear"] = w


static func overhaul_cost() -> int:
	if slot < 0:
		return 0
	var loaded := _load_ship(SaveSlots.read(slot))
	if loaded.is_empty():
		return 0
	var lv := SimShip.level(String(profile.get("difficulty", "normal")))
	return Wear.overhaul_cost(loaded.ship, wear(), float(lv.get("maintenance_mult", 1.0)) * site_repair_mult())


## The yard overhauls every working part to new.
static func overhaul_parts() -> Dictionary:
	var cost := overhaul_cost()
	if cost <= 0:
		return {"ok": false, "message": "Nothing's worn. The yard's mechanic looks disappointed."}
	if int(profile.get("credits", 0)) < cost:
		return {"ok": false, "message": "An overhaul costs %s cr; you have %s cr." % [ShipStats.commas(cost), ShipStats.commas(int(profile.credits))]}
	var data := SaveSlots.read(slot)
	var loaded := _load_ship(data)
	if loaded.is_empty() or sim == null:
		return {"ok": false, "message": "Couldn't load the ship from the save."}
	_sync_sim(loaded.ship)
	sim._pay(SimWorld.PLAYER, "world", float(cost))
	profile["wear"] = {}
	_commit_sim(data, loaded.ship)
	data["profile"] = profile
	SaveSlots.write(slot, data)
	return {"ok": true, "message": "Every working part overhauled to new for %s cr. The engines sound younger." % ShipStats.commas(cost)}


static func spares_kits() -> int:
	return int(profile.get("spares_kits", 0))


static func spares_kit_price() -> int:
	var lv := SimShip.level(String(profile.get("difficulty", "normal")))
	return roundi(float(Wear.cfg().get("spares_kit_cr", 1500)) * float(lv.get("maintenance_mult", 1.0)) * site_repair_mult())


static func buy_spares_kit() -> Dictionary:
	if slot < 0 or sim == null:
		return {"ok": false, "message": "No saved game, no shop."}
	if spares_kits() >= int(Wear.cfg().get("spares_kit_max", 4)):
		return {"ok": false, "message": "The spares locker is full. Optimism has limits."}
	var price := spares_kit_price()
	if int(profile.get("credits", 0)) < price:
		return {"ok": false, "message": "A spares kit costs %s cr; you have %s cr." % [ShipStats.commas(price), ShipStats.commas(int(profile.credits))]}
	var data := SaveSlots.read(slot)
	var loaded := _load_ship(data)
	if loaded.is_empty():
		return {"ok": false, "message": "Couldn't load the ship from the save."}
	_sync_sim(loaded.ship)
	sim._pay(SimWorld.PLAYER, "world", float(price))
	profile["spares_kits"] = spares_kits() + 1
	_commit_sim(data, loaded.ship)
	data["profile"] = profile
	SaveSlots.write(slot, data)
	return {"ok": true, "message": "Bought a spares kit for %s cr: seals, valves, a pump, and a bag of mystery bolts. %d aboard." % [ShipStats.commas(price), spares_kits()]}


## Patch kits aboard, for space-walk repairs (SpaceWalk): what's carried, what one costs, how many fit.
static func patch_kits() -> int:
	return int(profile.get("patch_kits", 0))


static func patch_kit_price() -> int:
	var lv := SimShip.level(String(profile.get("difficulty", "normal")))
	return roundi(float(SpaceWalk.tuning().get("patch_kit_cr", 400)) * float(lv.get("maintenance_mult", 1.0)) * site_repair_mult())


static func patch_kit_max() -> int:
	return int(SpaceWalk.tuning().get("patch_kit_max", 8))


## Buy `n` patch kits here (as many as fit and the money covers).
static func buy_patch_kits(n: int) -> Dictionary:
	if slot < 0 or sim == null:
		return {"ok": false, "message": "No saved game, no shop."}
	var price := patch_kit_price()
	var room := patch_kit_max() - patch_kits()
	n = mini(n, room)
	if n <= 0:
		return {"ok": false, "message": "The kit locker is full: %d kits. Go and break something." % patch_kit_max()}
	n = mini(n, int(profile.get("credits", 0)) / maxi(price, 1))
	if n <= 0:
		return {"ok": false, "message": "A patch kit costs %s cr; you have %s cr." % [ShipStats.commas(price), ShipStats.commas(int(profile.credits))]}
	var data := SaveSlots.read(slot)
	var loaded := _load_ship(data)
	if loaded.is_empty():
		return {"ok": false, "message": "Couldn't load the ship from the save."}
	_sync_sim(loaded.ship)
	sim._pay(SimWorld.PLAYER, "world", float(price * n))
	profile["patch_kits"] = patch_kits() + n
	_commit_sim(data, loaded.ship)
	data["profile"] = profile
	SaveSlots.write(slot, data)
	return {"ok": true, "message": "Bought %d patch kit%s for %s cr. %d aboard. Plates, sealant, a welder with opinions." % [n, "" if n == 1 else "s", ShipStats.commas(price * n), patch_kits()]}


## Claim beacons (Rivals): fired at a wreck to stake it. Bought at the repair desk.
static func claim_beacon_price() -> int:
	var lv := SimShip.level(String(profile.get("difficulty", "normal")))
	return roundi(float(Rivals.cfg().get("beacon_price_cr", 150)) * float(lv.get("port_fee_mult", 1.0)))


static func buy_claim_beacons(n: int) -> Dictionary:
	if slot < 0 or sim == null:
		return {"ok": false, "message": "No saved game, no shop."}
	var price := claim_beacon_price()
	var cap := int(Rivals.cfg().get("beacon_max", 4))
	n = mini(n, cap - Rivals.beacons())
	if n <= 0:
		return {"ok": false, "message": "The beacon rack holds %d. Go and claim something." % cap}
	n = mini(n, int(profile.get("credits", 0)) / maxi(price, 1))
	if n <= 0:
		return {"ok": false, "message": "A claim beacon costs %s cr; you have %s cr." % [ShipStats.commas(price), ShipStats.commas(int(profile.credits))]}
	var have := Rivals.beacons()
	if not _book(-float(price * n)):
		return {"ok": false, "message": "The desk's card reader is sulking. Try again."}
	profile["claim_beacons"] = have + n
	save_profile()
	return {"ok": true, "message": "Bought %d claim beacon%s for %s cr. %d aboard. Fire one at a wreck and it's yours, legally speaking." % [n, "" if n == 1 else "s", ShipStats.commas(price * n), Rivals.beacons()]}


## Pay the yard here to make the hull good again (it also restores the thrust damage takes away).
static func repair_hull() -> Dictionary:
	var cost := repair_cost()
	if cost <= 0:
		return {"ok": false, "message": "The hull needs no work."}
	var data := SaveSlots.read(slot)
	var loaded := _load_ship(data)
	if loaded.is_empty() or sim == null:
		return {"ok": false, "message": "Couldn't load the ship from the save."}
	if int(profile.get("credits", 0)) < cost:
		return {"ok": false, "message": "Repairs here cost %s cr; you have %s cr. Cash only." % [ShipStats.commas(cost), ShipStats.commas(int(profile.credits))]}
	_sync_sim(loaded.ship)
	sim._pay(SimWorld.PLAYER, "world", float(cost))
	profile["hull_damage"] = 0.0
	profile["hull_patches"] = []   # the yard replaces the welded-on patches with proper plating
	_commit_sim(data, loaded.ship)
	data["profile"] = profile
	SaveSlots.write(slot, data)
	return {"ok": true, "message": "Hull repaired for %s cr." % ShipStats.commas(cost)}


## What fitting a first FTL drive and its radiator costs: the gap between the starter and the FTL starter.
static func drive_price() -> int:
	var lib := ModuleLibrary.new()
	var a := ShipData.new(lib)
	var b := ShipData.new(lib)
	ShipPresets.build(a)
	ShipPresets.build(b, ShipPresets.STARTER_FTL)
	return ship_cost(b, lib) - ship_cost(a, lib)


## The run being flown in the flight scene ({} when the helm is just practice).
static var flight_job: Dictionary = {}
static var walk_aboard := false   ## set by the berth gate: the flight scene opens with you on your feet aboard


## Check the ship is ready and hand the active local contract to the flight scene.
static func begin_local_flight() -> Dictionary:
	var c := active_contract()
	if c.is_empty() or not bool(c.get("local", false)):
		return {"ok": false, "message": "There is no local run to fly."}
	if String(c.origin_port_id) != String(profile.get("port_id", "")) or String(c.get("status", "")) == "arrived":
		return {"ok": false, "message": "This run starts somewhere else."}
	var loaded_ship := _load_ship(SaveSlots.read(slot))
	if loaded_ship.is_empty():
		return {"ok": false, "message": "Couldn't load the ship from the save."}
	var stats := ship_stats(loaded_ship.ship, loaded_ship.manifest)
	var unfit := Contracts.why_not(Contracts.check(stats, loaded_ship.manifest, c))
	if unfit != "":
		return {"ok": false, "message": unfit}
	if hull_block() != "":
		return {"ok": false, "message": hull_block()}
	var dest := LocalSpace.node(String(c.destination_port_id))
	flight_job = {"kind": "run", "contract_id": String(c.id), "dv_kms": float(c.dv_kms), "hours": int(c.hours),
			"destination": String(dest.get("name", "the destination")), "key": String(c.id),
			"dest_kind": String(dest.get("kind", "port")), "dest_id": String(c.destination_port_id),
			"origin_kind": String(LocalSpace.node(String(c.origin_port_id)).get("kind", "port")), "origin_id": String(c.origin_port_id),
			"system_id": system_id()}
	return {"ok": true, "message": "Take the helm."}


## Hand an active interstellar contract to the flight scene as a flown jump: undock, fly clear, engage the
## FTL drive, arrive in the destination system and dock there.
static func begin_jump_flight() -> Dictionary:
	var c := active_contract()
	if c.is_empty() or bool(c.get("local", false)) or not c.has("sim_taken"):
		return {"ok": false, "message": "There is no interstellar contract to fly."}
	if String(c.origin_system_id) != system_id() or String(c.get("status", "")) == "arrived":
		return {"ok": false, "message": "This contract departs from somewhere else."}
	var loaded_ship := _load_ship(SaveSlots.read(slot))
	if loaded_ship.is_empty():
		return {"ok": false, "message": "Couldn't load the ship from the save."}
	var stats := ship_stats(loaded_ship.ship, loaded_ship.manifest)
	var unfit := Contracts.why_not(Contracts.check(stats, loaded_ship.manifest, c))
	if unfit != "":
		return {"ok": false, "message": unfit}
	if hull_block() != "":
		return {"ok": false, "message": hull_block()}
	flight_job = {"kind": "jump", "contract_id": String(c.id), "destination": String(Worlds.port(String(c.destination_port_id)).get("name", "the destination")),
			"dest_system": String(c.destination_system_id), "ly": float(c.distance_ly), "key": String(c.id), "jumped": false}
	return {"ok": true, "message": "Take the helm."}


## The moment of the jump: the sim runs the trip (fuel, fees, crew and the days it takes) and the ship
## is now in the destination system. Returns {ok, days, message}.
static func commit_jump() -> Dictionary:
	var c := active_contract()
	if flight_job.is_empty() or c.is_empty() or not c.has("sim_taken"):
		return {"ok": false, "days": 0.0, "message": "No jump to make."}
	var data := SaveSlots.read(slot)
	var loaded_ship := _load_ship(data)
	if loaded_ship.is_empty():
		return {"ok": false, "days": 0.0, "message": "Couldn't load the ship from the save."}
	_sync_sim(loaded_ship.ship)
	var hours := sim.run_player_until(SimWorld.PLAYER, "arrival")
	# The jump's wear and the crew's work on the way go on the flight's own copies (CrewWork.after_jump):
	# the flight saves its wear and hull when it ends.
	profile["system_id"] = String(c.destination_system_id)
	profile["port_id"] = String(c.destination_port_id)
	c["status"] = "arrived"
	data["active_contract"] = c
	data["profile"] = profile
	_commit_sim(data, loaded_ship.ship)
	SaveSlots.write(slot, data)
	flight_job["jumped"] = true
	return {"ok": true, "days": hours / 24.0, "hours": float(hours), "message": "Jumped %.2f ly in %.1f days." % [float(c.distance_ly), hours / 24.0]}


## Close out a flown jump. Before the jump (`jumped` false) the ship just came home; after it, it has
## docked at the destination (or been towed in) and the load is ready to deliver.
static func finish_jump_flight(fuel_burned_t: float, seconds: float, damage: float, stranded: bool) -> String:
	var job := flight_job
	flight_job = {}
	var c := active_contract()
	if slot < 0 or sim == null or c.is_empty() or job.is_empty():
		return ""
	var data := SaveSlots.read(slot)
	var loaded := _load_ship(data)
	if loaded.is_empty():
		return ""
	_sync_sim(loaded.ship)
	var lv := SimShip.level(String(profile.get("difficulty", "normal")))
	var r := SimWorld.settle_flight(sim, fuel_burned_t, seconds, 0.0, float(ship_cost(loaded.ship, loaded.ship.library)), site_fuel_mult())
	profile["hull_damage"] = clampf(damage, 0.0, 1.0)   # carried until repaired at a fuel and repair desk
	var tow := 0.0
	if stranded:
		tow = float(LocalSpace.config()["board"]["tow_fee_cr"]) * float(lv.get("port_fee_mult", 1.0))
		sim._pay(SimWorld.PLAYER, "world", tow)
	var hull_note := _settle_hull(data, c, float(ship_cost(loaded.ship, loaded.ship.library)))
	var msg := ""
	if bool(job.get("jumped", false)):
		msg = "Docked at %s. Manoeuvring fuel %s cr%s.%s" % [job.destination, ShipStats.commas(int(r.fuel_cost)),
				", hull repairs %s cr" % ShipStats.commas(int(r.repair_cost)) if int(r.repair_cost) > 0 else "", " A tug towed you in (%s cr), smugly." % ShipStats.commas(roundi(tow)) if stranded else ""]
	else:
		msg = "Turned back before the jump. Fuel %s cr. The load is still aboard.%s" % [ShipStats.commas(int(r.fuel_cost)), " A tug brought you in (%s cr)." % ShipStats.commas(roundi(tow)) if stranded else ""]
	msg += hull_note
	_commit_sim(data, loaded.ship)
	data["profile"] = profile
	SaveSlots.write(slot, data)
	if bool(job.get("jumped", false)):
		msg += Passengers.set_down()
	flash = msg
	return msg


## Close out a flown local run. `arrived`: the ship stopped at the destination. Otherwise it came home
## (Esc) or ran dry and was towed; either way the contract stays loaded at the origin.
## `surface`: the ship landed on the destination's pad (a moon base) instead of docking in orbit, which
## earns the surface bonus when the load is delivered.
static func finish_local_flight(fuel_burned_t: float, seconds: float, damage: float, arrived: bool, stranded: bool = false, surface: bool = false) -> String:
	var job := flight_job
	flight_job = {}
	var c := active_contract()
	var ferry := bool(job.get("ferry", false))   # flown with no contract: passengers, or nobody
	if slot < 0 or sim == null or (c.is_empty() and not ferry) or job.is_empty():
		return ""
	var data := SaveSlots.read(slot)
	var loaded := _load_ship(data)
	if loaded.is_empty():
		return ""
	_sync_sim(loaded.ship)
	var lv := SimShip.level(String(profile.get("difficulty", "normal")))
	var cfg: Dictionary = LocalSpace.config()["board"]
	var clock := float(int(job.hours)) * 3600.0 if arrived else seconds
	if arrived and String(c.get("person_kind", "")) == "rush":
		clock = ceilf(float(int(job.hours)) * float(People.hard_burn().time)) * 3600.0   # flown by hand, flat out
	var r := SimWorld.settle_flight(sim, fuel_burned_t, clock, 0.0, float(ship_cost(loaded.ship, loaded.ship.library)), site_fuel_mult())
	profile["hull_damage"] = clampf(damage, 0.0, 1.0)   # carried until repaired at a fuel and repair desk
	var berth := float(cfg["dock_fee_cr"]) * float(lv.get("port_fee_mult", 1.0)) if arrived else 0.0
	var tow := float(cfg["tow_fee_cr"]) * float(lv.get("port_fee_mult", 1.0)) if stranded else 0.0
	var extra := berth + tow
	sim._pay(SimWorld.PLAYER, "world", extra)
	var rescued := bool(flight_extra.get("rescue", false))
	var hull_note := _settle_hull(data, c, float(ship_cost(loaded.ship, loaded.ship.library)))
	var dry := "Hull breached" if rescued else "Out of fuel"
	var msg := ""
	if arrived:
		var dest_id := String(job.get("dest_id", "")) if ferry else String(c.destination_port_id)
		profile["port_id"] = dest_id
		if surface and String(LocalSpace.node(dest_id).get("kind", "")) == "moon":
			profile["port_id"] = system_id() + LocalSpace.SEP + "pad"   # landed on the base's pad, not docked in orbit
		if not ferry:
			c["status"] = "arrived"
			if surface:
				c["surface"] = true
			data["active_contract"] = c
		msg = (("Landed on the pad at %s." if surface else "Docked at %s.") + " Fuel %s cr, berth fee %s cr%s.%s") % [job.destination, ShipStats.commas(int(r.fuel_cost)), ShipStats.commas(roundi(berth)),
				", hull repairs %s cr" % ShipStats.commas(int(r.repair_cost)) if int(r.repair_cost) > 0 else "", (" %s: a tug towed you in for %s cr." % [dry, ShipStats.commas(roundi(tow))]) if stranded else ""]
	elif stranded:
		msg = "%s. A tug brought you back for %s cr plus %s cr of fuel. The load is still aboard." % [dry, ShipStats.commas(roundi(extra)), ShipStats.commas(int(r.fuel_cost))]
	else:
		msg = "Turned back to the start. Fuel %s cr. The load is still aboard." % ShipStats.commas(int(r.fuel_cost))
	msg += hull_note
	_commit_sim(data, loaded.ship)
	data["profile"] = profile
	SaveSlots.write(slot, data)
	if arrived:
		msg += Passengers.set_down()
	flash = msg
	return msg


## Fly a local hop by hand with no contract: to set passengers down, or just to get there. The flight
## scene treats it as a run (flight_job kind "run", `ferry` true); finish_local_flight closes it out.
static func begin_ferry_flight(dest_id: String) -> Dictionary:
	if slot < 0 or sim == null:
		return {"ok": false, "message": "No saved game, nowhere to go. Load one first."}
	if not active_contract().is_empty():
		return {"ok": false, "message": "Fly the contract: the passengers ride along with it."}
	if hull_block(false) != "":
		return {"ok": false, "message": hull_block(false)}
	for site in local_sites():
		if String(site["id"]) != dest_id:
			continue
		var here := String(profile.get("port_id", ""))
		var dest := LocalSpace.node(dest_id)
		flight_job = {"kind": "run", "ferry": true, "contract_id": "", "dv_kms": float(site.dv_kms), "hours": int(site.hours),
				"destination": String(dest.get("name", "the destination")), "key": "ferry-%s-%d" % [dest_id, day()],
				"dest_kind": String(dest.get("kind", "port")), "dest_id": dest_id,
				"origin_kind": String(LocalSpace.node(here).get("kind", "port")), "origin_id": here, "system_id": system_id()}
		return {"ok": true, "message": "Take the helm."}
	return {"ok": false, "message": "Your tanks can't reach that site."}


## `hard`: a hard burn for a rush job, sooner and dearer (People.hard_burn).
static func _depart_local(c: Dictionary, hard := false) -> Dictionary:
	if String(c.origin_port_id) != String(profile.get("port_id", "")):
		return {"ok": false, "message": "This run starts somewhere else."}
	var data := SaveSlots.read(slot)
	var loaded_ship := _load_ship(data)
	if loaded_ship.is_empty():
		return {"ok": false, "message": "Couldn't load the ship from the save."}
	var manifest: CargoManifest = loaded_ship.manifest
	var stats := ship_stats(loaded_ship.ship, manifest)
	var unfit := Contracts.why_not(Contracts.check(stats, manifest, c))
	if unfit != "":
		return {"ok": false, "message": unfit}
	var cargo := float(c.get("accepted_tonnes", c.offer))
	var cost := local_trip_cost(stats, cargo, float(c.dv_kms))
	var hours := maxi(1, ceili(float(c.hours) * Crew.time_mult(crew())))
	if hard:
		var hb := People.hard_burn()
		cost["burn_t"] = float(cost.burn_t) * float(hb.fuel)
		cost["total"] = float(cost.fuel_cost) * float(hb.fuel) + float(cost.fee)
		hours = maxi(1, ceili(float(c.hours) * float(hb.time) * Crew.time_mult(crew())))
	if float(cost.burn_t) > float(stats["fuel"]):
		return {"ok": false, "message": "The tanks cannot cover that burn."}
	_sync_sim(loaded_ship.ship)
	sim._pay(SimWorld.PLAYER, "world", float(cost.total))
	sim.run_hours(hours)
	var wc := Wear.cfg()
	_autopilot_wear(loaded_ship.ship, float(cost.burn_t) * float(wc.get("autopilot_engine_per_t", 0.006)), float(cost.burn_t) * float(wc.get("autopilot_radiator_per_t", 0.003)))
	var work := _crew_between(loaded_ship.ship, float(hours))
	profile["port_id"] = String(c.destination_port_id)
	c["status"] = "arrived"
	data["active_contract"] = c
	data["profile"] = profile
	_commit_sim(data, loaded_ship.ship)
	SaveSlots.write(slot, data)
	return {"ok": true, "message": "Burned %.1f t of fuel (%s cr) and reached %s in %d hours%s." % [float(cost.burn_t), ShipStats.commas(roundi(float(cost.total))), String(LocalSpace.node(String(c.destination_port_id)).get("name", "the site")), hours, (" on a hard burn" if hard else "") + ("." + work.trim_suffix(".") if work != "" else "")] + Passengers.set_down()}


static func _deliver_local(c: Dictionary, manual := false) -> Dictionary:
	var here := String(profile.get("port_id", ""))
	var landed_for_it := bool(c.get("surface", false)) and here == system_id() + LocalSpace.SEP + "pad" \
			and String(LocalSpace.node(String(c.destination_port_id)).get("kind", "")) == "moon"   # landed on the base's pad
	if String(c.destination_port_id) != here and not landed_for_it:
		return {"ok": false, "message": "Nothing to deliver here. Check the destination."}
	var data := SaveSlots.read(slot)
	var loaded_ship := _load_ship(data)
	if loaded_ship.is_empty():
		return {"ok": false, "message": "Couldn't load the ship from the save."}
	var manifest: CargoManifest = loaded_ship.manifest
	var passengers := String(c.get("person_kind", "")) == "passenger"
	var delivered := 0.0 if passengers else manifest.unload(StringName(c.commodity), float(c.get("accepted_tonnes", c.offer)))
	var payment := int(c.get("pay_total", roundi(delivered * float(c.rate))))
	_sync_sim(loaded_ship.ship)
	var deal := People.settle(c, payment, sim.hour, float(profile.get("hull_damage", 0.0)))
	payment = int(deal.payment)
	var spoiled := roundi(float(payment) * clampf(float(c.get("cargo_hurt", 0.0)), 0.0, 1.0))
	payment -= spoiled
	var bonus := 0
	if bool(c.get("surface", false)):   # landed straight on the moon base's pad: no lighter up from orbit
		bonus = roundi(float(payment) * float(SurfaceTerrain.config().get("surface_bonus", 0.25)))
		payment += bonus
	var rep_note := _add_rep(int(deal.rep) + (1 if passengers and Crew.skill(crew(), "steward") >= 3 else 0))   # a good steward's passengers speak well of you
	var uc := SurfaceWork.unload_cfg()
	var roster := crew()
	var hours := int(LocalSpace.config()["board"]["unload_hours"])
	var camp_fee := 0
	var own_crew := ""
	var at_camp := String(LocalSpace.node(here).get("kind", "")) == "camp" and not passengers
	if at_camp and not manual and Crew.skill(roster, "loadmaster") > 0:   # your loadmaster runs the unloading: no camp crew to pay
		hours = int(uc.get("camp_crew_hours", 8))
		own_crew = Crew.short(Crew.who(roster, "loadmaster"))
	elif at_camp and not manual:   # no crane at the camp: its crew carry it off, for a fee and most of a day
		hours = int(uc.get("camp_crew_hours", 8))
		camp_fee = roundi(float(payment) * float(uc.get("camp_crew_share", 0.15)))
		payment -= camp_fee
	elif manual or passengers:
		hours = 0
	if hours > 0:
		hours = maxi(1, ceili(float(hours) * Crew.unload_mult(roster)))
	var tip := 0
	if passengers and Crew.skill(roster, "steward") > 0:   # looked after: they pay more, and say so
		tip = roundi(float(payment) * (Crew.fare_mult(roster) - 1.0))
		payment += tip
	if hours > 0:
		sim.run_hours(hours)
	sim._pay("world", SimWorld.PLAYER, float(payment))
	SimStats.on_local(sim, system_id(), delivered, float(payment))
	var moved_t := float(int(c.get("seats", 0))) * float(Development.config().get("passenger_t", 0.1)) if passengers else delivered
	Development.moved(sim, String(c.destination_port_id), moved_t)   # frontier growth: supply here, trade where it came from
	Development.moved(sim, String(c.get("origin_port_id", "")), moved_t, true)
	var pc: Dictionary = sim.carriers[SimWorld.PLAYER]
	pc["revenue"] = float(pc["revenue"]) + float(payment)
	pc["trips"] = int(pc["trips"]) + 1
	_commit_sim(data, loaded_ship.ship)
	data["cargo"] = manifest.to_dict()
	data.erase("active_contract")
	data["profile"] = profile
	SaveSlots.write(slot, data)
	var note := " (includes %s cr for landing it on the surface)" % ShipStats.commas(bonus) if bonus > 0 else ""
	if tip > 0:
		note += ", %s cr of it for %s's care" % [ShipStats.commas(tip), Crew.short(Crew.who(roster, "steward"))]
	if own_crew != "":
		note += ", unloaded by %s and the crew in %d hours, no camp crew to pay" % [own_crew, hours]
	elif camp_fee > 0:
		note += ", less %s cr to the camp crew for %d hours' unloading" % [ShipStats.commas(camp_fee), hours]
	elif manual:
		note += ", carried off by your own two hands"
	elif hours > 0:
		note += ", after %d hours' unloading" % hours
	if spoiled > 0:
		note += ", less %s cr for the %d%% that arrived broken" % [ShipStats.commas(spoiled), roundi(float(c.cargo_hurt) * 100.0)]
	var dn := String(deal.note)
	var deal_note := (" " + dn.substr(0, 1).to_upper() + dn.substr(1) + ".") if dn != "" else ""
	if passengers:
		return {"ok": true, "message": "Passengers set down. Fare paid: %s cr%s.%s%s" % [ShipStats.commas(payment), note, deal_note, rep_note], "payment": payment}
	return {"ok": true, "message": "Delivered %.1f t. Freight paid: %s cr%s.%s%s" % [delivered, ShipStats.commas(payment), note, deal_note, rep_note], "payment": payment}


## Standing: what people think of you (People). Returns a note for the delivery message.
static func _add_rep(delta: int) -> String:
	if delta == 0:
		return ""
	var before := int(profile.get("rep", 0))
	var after := maxi(0, before + delta)
	profile["rep"] = after
	var note := " Standing %+d." % delta
	if People.standing(after) != People.standing(before):
		note += " You are now %s." % People.standing(after)
	return note


## People asking for work in person here today (People.posted).
static func people_here() -> Array[Dictionary]:
	if slot < 0 or sim == null:
		return []
	var loaded := _load_ship(SaveSlots.read(slot))
	if loaded.is_empty():
		return []
	var id := String(profile.get("port_id", ""))
	if LocalSpace.node(id).is_empty():
		return []
	if Development.abandoned(sim, id):
		return []
	var st := ship_stats(loaded.ship)
	var out := People.posted(id, day(), st, SimShip.level(String(profile.get("difficulty", "normal"))), profile.get("local_taken", []), int(profile.get("rep", 0)),
			func(cargo_t: float, dv: float) -> float: return float(local_trip_cost(st, cargo_t, dv).total))
	if site_has("passengers"):
		return out
	var kept: Array[Dictionary] = []   # too small a place for anyone to be travelling from
	for j in out:
		if String(j.get("person_kind", "")) != "passenger":
			kept.append(j)
	return kept


static func depart_active_contract(hard := false) -> Dictionary:
	var c := active_contract()
	if c.is_empty():
		return {"ok": false, "message": "Accept a freight contract first."}
	if hull_block() != "":
		return {"ok": false, "message": hull_block()}
	if bool(c.get("local", false)):
		return _depart_local(c, hard)
	if String(c.origin_system_id) != system_id():
		return {"ok": false, "message": "This contract leaves from another system."}
	var data := SaveSlots.read(slot)
	var loaded_ship := _load_ship(data)
	if loaded_ship.is_empty():
		return {"ok": false, "message": "Couldn't load the ship from the save."}
	var manifest: CargoManifest = loaded_ship.manifest
	var stats := ship_stats(loaded_ship.ship, manifest)
	var unfit := Contracts.why_not(Contracts.check(stats, manifest, c))
	if unfit != "":
		return {"ok": false, "message": unfit}
	var days_text := ""
	var live := sim != null and c.has("sim_taken")
	if live:
		_sync_sim(loaded_ship.ship)
		var hours := sim.run_player_until(SimWorld.PLAYER, "arrival")
		days_text = " The trip took %.1f days." % (hours / 24.0)
		_autopilot_wear(loaded_ship.ship, float(Wear.cfg().get("jump_engine", 0.03)), float(Wear.cfg().get("jump_radiator", 0.02)), float(Wear.cfg().get("jump_drive", 0.02)))
		days_text += _crew_between(loaded_ship.ship, float(hours))
	profile["system_id"] = String(c.destination_system_id)
	profile["port_id"] = String(c.destination_port_id)
	c["status"] = "arrived"
	data["active_contract"] = c
	data["profile"] = profile
	if live:
		_commit_sim(data, loaded_ship.ship)
	SaveSlots.write(slot, data)
	return {"ok": true, "message": "Arrived at %s after %.2f ly.%s" % [Worlds.port(profile.port_id).name, float(c.distance_ly), days_text] + Passengers.set_down()}


## Why the active contract can't set off from here right now, or "" when it can: the hull, then every
## fitness check the ship fails for this load (Contracts.why_not).
static func depart_block() -> String:
	var c := active_contract()
	if c.is_empty():
		return "No contract to fly."
	if hull_block() != "":
		return hull_block()
	var loaded := _load_ship(SaveSlots.read(slot))
	if loaded.is_empty():
		return "Couldn't load the ship from the save."
	return Contracts.why_not(Contracts.check(ship_stats(loaded.ship, loaded.manifest), loaded.manifest, c))


## Whether the active contract can be cancelled here, and why not: "" when it can. Only before
## setting off: at the origin, not yet arrived.
static func cancel_block() -> String:
	var c := active_contract()
	if c.is_empty():
		return "No contract to cancel."
	if String(c.get("status", "")) == "arrived":
		return "You're already there. Deliver it; it's less paperwork."
	var at_start := String(c.get("origin_port_id", "")) == String(profile.get("port_id", "")) if bool(c.get("local", false)) \
			else String(c.get("origin_system_id", "")) == system_id()
	if not at_start:
		return "The load comes off where it came on. Go back to %s first." % (String(LocalSpace.node(String(c.get("origin_port_id", ""))).get("name", "the origin"))
				if bool(c.get("local", false)) else String(Worlds.system(String(c.get("origin_system_id", ""))).get("name", "the origin")))
	return ""


## What backing out costs: a share of the pay (People config "cancel_fee_share", 10%), no more than
## the captain has.
static func cancel_fee() -> int:
	var c := active_contract()
	var pay := float(c.get("pay_total", roundi(float(c.get("accepted_tonnes", c.get("offer", 0.0))) * float(c.get("rate", 0.0)))))
	return mini(roundi(pay * float(People.config().get("cancel_fee_share", 0.1))), maxi(0, int(profile.get("credits", 0))))


## Back out of the active contract before setting off: the load goes back to the shipper's dock (the
## economy puts the freight back on the board), a fee for the trouble, and people you let down remember.
static func cancel_contract() -> Dictionary:
	var why := cancel_block()
	if why != "":
		return {"ok": false, "message": why}
	var c := active_contract()
	var data := SaveSlots.read(slot)
	var loaded := _load_ship(data)
	if loaded.is_empty():
		return {"ok": false, "message": "Couldn't load the ship from the save."}
	var fee := cancel_fee()
	var manifest: CargoManifest = loaded.manifest
	var pax := String(c.get("person_kind", "")) == "passenger"
	if not pax and c.has("commodity"):
		manifest.unload(StringName(c.commodity), float(c.get("accepted_tonnes", c.get("offer", 0.0))))
	if sim != null:
		_sync_sim(loaded.ship)
		if c.has("sim_taken"):
			var r := sim.player_cancel(SimWorld.PLAYER)
			if not bool(r.ok):
				return r
		if fee > 0:
			sim._pay(SimWorld.PLAYER, "world", float(fee))
	var rep := ""
	if String(c.get("person_kind", "")) != "":
		rep = _add_rep(-int(People.config().get("cancel_rep", 2)))
	flight_job = {}
	data.erase("active_contract")
	data["cargo"] = manifest.to_dict()
	if sim != null:
		_commit_sim(data, loaded.ship)
	data["profile"] = profile
	SaveSlots.write(slot, data)
	var what := ("%s stays ashore" % String(c.get("person", "Your passenger"))) if pax else "The load goes back on the dock"
	return {"ok": true, "message": "Contract cancelled. %s%s.%s" % [what, (", and the shipper keeps %s cr for the trouble" % ShipStats.commas(fee)) if fee > 0 else "", rep]}


## `manual`: at the camp, carried off by hand instead of paying the camp crew.
static func deliver_active_contract(manual := false) -> Dictionary:
	var c := active_contract()
	if not c.is_empty() and bool(c.get("local", false)):
		return _deliver_local(c, manual)
	if c.is_empty() or String(c.destination_system_id) != system_id():
		return {"ok": false, "message": "Nothing to deliver here. Check the destination."}
	var data := SaveSlots.read(slot)
	var loaded_ship := _load_ship(data)
	if loaded_ship.is_empty():
		return {"ok": false, "message": "Couldn't load the ship from the save."}
	var manifest: CargoManifest = loaded_ship.manifest
	var delivered := manifest.unload(StringName(c.commodity), float(c.get("accepted_tonnes", c.offer)))
	var payment := roundi(delivered * float(c.rate))
	var hurt := clampf(float(c.get("cargo_hurt", 0.0)), 0.0, 1.0)
	var spoiled := 0
	if sim != null and c.has("sim_taken"):
		_sync_sim(loaded_ship.ship)
		sim.run_player_until(SimWorld.PLAYER, "done")   # unloading takes hours; the consignee pays the moment it is done
		payment = int(c.get("pay_total", payment))
		spoiled = roundi(float(payment) * hurt)
		if spoiled > 0:   # the consignee docks the broken share: paid back out of what the sim paid in
			sim._pay(SimWorld.PLAYER, "world", float(spoiled))
			var pc: Dictionary = sim.carriers[SimWorld.PLAYER]
			pc["revenue"] = float(pc["revenue"]) - float(spoiled)
			payment -= spoiled
		_commit_sim(data, loaded_ship.ship)
	else:
		spoiled = roundi(float(payment) * hurt)
		payment -= spoiled
		profile["credits"] = int(profile.credits) + payment
		data["earned"] = int(data.get("earned", 0)) + payment
	data["cargo"] = manifest.to_dict()
	data.erase("active_contract")
	data["profile"] = profile
	SaveSlots.write(slot, data)
	var rep_note := _add_rep(int(People.config().get("rep_freight", 1)))
	data["profile"] = profile
	SaveSlots.write(slot, data)
	var broke := ", less %s cr for the %d%% that arrived broken" % [ShipStats.commas(spoiled), roundi(hurt * 100.0)] if spoiled > 0 else ""
	return {"ok": true, "message": "Delivered %.1f t. Freight paid: %s cr%s.%s" % [delivered, ShipStats.commas(payment), broke, rep_note], "payment": payment}


## The crew (Crew) -----------------------------------------------------------------------------------

## The hired crew, captain not included: [{id, name, species, role, skill, wage, line, hired_day}].
static func crew() -> Array:
	return profile.get("crew", [])


## People aboard who work the ship, the captain included.
static func crew_aboard() -> int:
	return 1 + crew().size()


## Berths not taken by the captain, the crew, passengers or rescued survivors aboard right now. It goes to
## -1 when a survivor has the jump seat (Salvage.room_for): nobody's hired into that.
static func free_berths(stats: Dictionary) -> int:
	var lay := Passengers.layout(stats)   # passengers in spare bunks, survivors in whatever's free
	return int(lay.free[0]) - int(lay.over)


## Who is looking for work in this port today (not anyone already hired or let go here).
static func crew_candidates() -> Array[Dictionary]:
	if slot < 0 or sim == null:
		return []
	return Crew.candidates(String(profile.get("port_id", "")), day(), SimShip.wage_index(system_id()), profile.get("crew_seen", []))


static func _seen(id: String) -> void:
	var seen: Array = (profile.get("crew_seen", []) as Array).duplicate()
	if not seen.has(id):
		seen.append(id)
	profile["crew_seen"] = seen.slice(maxi(0, seen.size() - 60))


## Hire candidate `id` here: a day's pay up front to sign on, and a free berth.
static func hire(id: String) -> Dictionary:
	var who := {}
	for p in crew_candidates():
		if String(p.id) == id:
			who = p
	if who.is_empty():
		return {"ok": false, "message": "They've already gone. People at bars do that."}
	var loaded := _load_ship(SaveSlots.read(slot))
	if loaded.is_empty():
		return {"ok": false, "message": "Couldn't load the ship from the save."}
	if free_berths(ship_stats(loaded.ship)) <= 0:
		return {"ok": false, "message": "No bunk for %s. Fit crew bunks or quarters at a shipyard; nobody signs on to sleep in the hold." % Crew.short(who)}
	var fee := roundi(float(who.wage) * float(Crew.cfg().get("hire_fee_days", 1)) * float(SimShip.level(String(profile.get("difficulty", "normal"))).get("wage_mult", 1.0)))
	if not _book(-float(fee)):
		return {"ok": false, "message": "Signing %s on costs %s cr up front; you have %s cr." % [Crew.short(who), ShipStats.commas(fee), ShipStats.commas(int(profile.get("credits", 0)))]}
	var p := who.duplicate()
	p["hired_day"] = day()
	var roster := crew().duplicate()
	roster.append(p)
	profile["crew"] = roster
	_seen(id)
	_resync()
	return {"ok": true, "message": "%s signs on as %s for %s cr a day, and %s cr up front. \"%s\"" % [String(p.name), Crew.role_name(String(p.role)).to_lower(),
			ShipStats.commas(int(p.wage)), ShipStats.commas(fee), String(p.line)]}


## Let crew member `id` go: two days' pay to see them off.
static func fire(id: String) -> Dictionary:
	var roster := crew().duplicate()
	var who := {}
	for p in roster:
		if String(p.id) == id:
			who = p
	if who.is_empty():
		return {"ok": false, "message": "Nobody aboard by that name."}
	var pay := roundi(float(who.wage) * float(Crew.cfg().get("severance_days", 2)) * float(SimShip.level(String(profile.get("difficulty", "normal"))).get("wage_mult", 1.0)))
	_book(-float(mini(pay, maxi(0, int(profile.get("credits", 0))))))   # what you can pay of it, anyway
	roster.erase(who)
	profile["crew"] = roster
	_seen(id)
	_resync()
	return {"ok": true, "message": "%s collects %s cr severance and their kit, and goes. %s" % [String(who.name), ShipStats.commas(pay),
			"They don't look back." if int(who.skill) < 4 else "The ship already feels a little worse at its job."]}


## Put the sim's payroll in step with the roster and save.
static func _resync() -> void:
	var data := SaveSlots.read(slot)
	var loaded := _load_ship(data)
	if loaded.is_empty():
		save_profile()
		return
	_sync_sim(loaded.ship)
	_commit_sim(data, loaded.ship)
	data["profile"] = profile
	SaveSlots.write(slot, data)


## A save from before named crew: the hands its ship needed get names and jobs, at the old pay.
static func _migrate_crew(ship: ShipData, need := -1) -> void:
	if profile.has("crew"):
		return
	if need < 0:
		need = SimShip.crew_for(float(ShipStats.compute(ship).cargo_capacity)) - 1
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(String(profile.get("name", "")) + "|old crew")
	var roster := []
	var order := ["engineer", "deck_tech", "loadmaster", "pilot", "steward"]
	for k in maxi(0, need):
		var r: String = order[k % order.size()]
		var sp := Crew._species(rng)
		var lines: Array = (Crew.cfg().get("lines", {}) as Dictionary).get(r, [""])
		roster.append({"id": "old-%d" % k, "name": Crew.make_name(sp, rng), "species": sp, "role": r, "skill": 2,
				"wage": roundi(Crew.base_wage(r, 2) * SimShip.wage_index(system_id())), "line": String(lines[k % lines.size()]), "hired_day": 0})
	profile["crew"] = roster


## The crew's work while the ship flies itself or sits in port for `hours`. Returns a note.
static func _crew_between(ship: ShipData, hours: float) -> String:
	var roster := crew()
	if roster.is_empty() or hours <= 0.0:
		return ""
	var done := Crew.work_between(profile, ship, Crew.jobs_in(roster, "deck_tech", "fixes_per_trip_hour", hours),
			Crew.jobs_in(roster, "engineer", "services_per_trip_hour", hours))
	return Crew.work_note(roster, done)


static func scene_path() -> String:
	return YARD_SCENE if profile.location == "shipyard" else PLACE_SCENE


## Writes the profile into the current slot without touching the ship. Returns false if not in a saved game.
static func save_profile() -> bool:
	if slot < 0:
		return false
	var data := SaveSlots.read(slot)
	if data.is_empty():
		return false
	data["profile"] = profile
	return SaveSlots.write(slot, data)
