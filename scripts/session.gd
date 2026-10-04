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
		total += library.get_def(m.id).cost
	return total


## Starts a fresh game in `at_slot`: the starter ship, docked at the chosen world's yard.
## Any save already in that slot is parked, not deleted.
static func begin_new(at_slot: int, name: String, species_id: String, difficulty: String, world_id: String) -> bool:
	var p := default_profile()
	p["name"] = name.strip_edges() if name.strip_edges() != "" else "Captain"
	p["species"] = species_id
	p["difficulty"] = difficulty
	p["ftl_rules"] = 1   # FTL is a fitted drive, not a given
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
	profile = SaveSlots.profile(from_slot)
	if not (data.get("profile", {}) as Dictionary).has("ftl_rules"):
		# Saved before FTL drives were a separate part: that ship keeps the jump capability it was flown with.
		profile["ftl_rules"] = 1
		profile["ftl_grandfathered"] = true
		data["profile"] = profile
		SaveSlots.write(slot, data)
	sim = SimWorld.restore(String(data["sim"])) if data.has("sim") else null
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
	var burn := LocalSpace.burn_t(float(stats["wet"]) + cargo_t, dv_kms)
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
	_commit_sim(data, loaded.ship)
	data["profile"] = profile
	SaveSlots.write(slot, data)
	flash = "Flight over (%d min). Fuel %s cr%s." % [roundi(seconds / 60.0), ShipStats.commas(int(r.fuel_cost)),
			", hull repairs %s cr" % ShipStats.commas(int(r.repair_cost)) if int(r.repair_cost) > 0 else ""]
	return flash


## What the bank will do for a bankrupt captain: take the ship at half its price, clear what is still
## owed, and hand over a plain starter hauler with ten days of running costs in the till. The run
## goes on, but you start again from the bottom and the count of failures stays on the record.
static func restructure() -> Dictionary:
	if not insolvent():
		return {"ok": false, "message": "The bank only steps in when you are in debt."}
	var data := SaveSlots.read(slot)
	var loaded := _load_ship(data)
	if loaded.is_empty():
		return {"ok": false, "message": "Could not load the current ship."}
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
	flash = "The bank took your ship for %s cr, cleared your debts and lent you a starter hauler with %s cr." % [ShipStats.commas(sale), ShipStats.commas(int(profile.credits))]
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
		return {"ok": false, "message": "Time only passes in a saved game."}
	if not active_contract().is_empty():
		return {"ok": false, "message": "Deliver or finish the active contract first."}
	var data := SaveSlots.read(slot)
	var loaded := _load_ship(data)
	if loaded.is_empty():
		return {"ok": false, "message": "Could not load the current ship."}
	_sync_sim(loaded.ship)
	var before := int(profile.credits)
	sim.run_hours(days * 24)
	_commit_sim(data, loaded.ship)
	data["profile"] = profile
	SaveSlots.write(slot, data)
	return {"ok": true, "message": "%d day%s pass. Running costs: %s cr." % [days, "" if days == 1 else "s", ShipStats.commas(before - int(profile.credits))]}


## Fly empty to another system, the way out of a port with no freight. Time passes and costs money.
static func travel_empty(dest_system_id: String) -> Dictionary:
	if slot < 0 or sim == null:
		return {"ok": false, "message": "Travel only happens in a saved game."}
	if not active_contract().is_empty():
		return {"ok": false, "message": "Deliver or finish the active contract first."}
	var data := SaveSlots.read(slot)
	var loaded := _load_ship(data)
	if loaded.is_empty():
		return {"ok": false, "message": "Could not load the current ship."}
	_sync_sim(loaded.ship)
	var before := int(profile.credits)
	var r := sim.player_reposition(SimWorld.PLAYER, dest_system_id)
	if not bool(r.ok):
		return r
	var hours := sim.run_player_until(SimWorld.PLAYER, "done")
	profile["system_id"] = dest_system_id
	profile["port_id"] = sim.net.primary_port(dest_system_id)
	_commit_sim(data, loaded.ship)
	data["profile"] = profile
	SaveSlots.write(slot, data)
	return {"ok": true, "message": "Flew empty to %s in %.1f days. Running costs: %s cr." % [dest_system_id.replace("_", " ").capitalize(), hours / 24.0, ShipStats.commas(before - int(profile.credits))]}


static func accept_contract(contract: Dictionary) -> Dictionary:
	if slot < 0 or contract.is_empty() or not active_contract().is_empty():
		return {"ok": false, "message": "A contract is already active or this is not a saved game."}
	var data := SaveSlots.read(slot)
	var loaded_ship := _load_ship(data)
	if loaded_ship.is_empty():
		return {"ok": false, "message": "Could not load the current ship."}
	var manifest: CargoManifest = loaded_ship.manifest
	var tonnes := float(contract.offer)
	var accepted := contract.duplicate(true)
	var live := sim != null and contract.has("sim_contract")
	var is_local := bool(contract.get("local", false))
	if is_local:
		var stats := ship_stats(loaded_ship.ship)
		var cap := LocalSpace.max_cargo_t(float(stats["wet"]), float(stats["fuel"]), float(contract["dv_kms"]))
		tonnes = minf(tonnes, maxf(cap, 0.0))
		if tonnes <= 0.0:
			return {"ok": false, "message": "The tanks cannot lift a load that far."}
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
	var loaded := manifest.load(StringName(contract.commodity), tonnes)
	if loaded <= CargoManifest.EPS:
		return {"ok": false, "message": "No compatible cargo capacity is available."}
	if is_local:
		accepted["pay_total"] = roundi(loaded * float(contract.rate))
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
		return {"ok": false, "message": "Could not save the accepted contract."}
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
		return {"ok": false, "message": "Travel only happens in a saved game."}
	if not active_contract().is_empty():
		return {"ok": false, "message": "Deliver or finish the active contract first."}
	for site in local_sites():
		if String(site["id"]) != dest_id:
			continue
		var data := SaveSlots.read(slot)
		var loaded := _load_ship(data)
		if loaded.is_empty():
			return {"ok": false, "message": "Could not load the current ship."}
		_sync_sim(loaded.ship)
		var before := int(profile.credits)
		sim._pay(SimWorld.PLAYER, "world", float(site["cost"]))
		sim.run_hours(int(site["hours"]))
		profile["port_id"] = dest_id
		_commit_sim(data, loaded.ship)
		data["profile"] = profile
		SaveSlots.write(slot, data)
		return {"ok": true, "message": "Flew empty to %s in %d hours. Fuel and running costs: %s cr." % [String(site["name"]), int(site["hours"]), ShipStats.commas(before - int(profile.credits))]}
	return {"ok": false, "message": "That site is out of reach."}


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
		var key := "samples" if String(f.kind) == "sample" else "salvage"
		var n := SurfaceFinds.units(String(f.kind))
		profile[key] = int(profile.get(key, 0)) + n
		save_profile()
		return {"ok": true, "message": ("%s bagged." % String(f.name)) if key == "samples" else "Stripped %d salvage parts from the wreck." % n}
	return {"ok": false, "message": "Nothing to take here."}


## Samples and salvage in the locker, and what they would fetch.
static func finds_aboard() -> Dictionary:
	var s := int(profile.get("samples", 0))
	var w := int(profile.get("salvage", 0))
	return {"samples": s, "salvage": w, "value": s * SurfaceFinds.value("sample") + w * SurfaceFinds.value("salvage")}


## Sell from the locker here. `sample_rate` and `salvage_rate` scale the standard prices (a lab pays more
## for samples and takes no salvage, a camp's exchange pays less); a rate of 0 keeps those aboard.
static func sell_finds(sample_rate: float = 1.0, salvage_rate: float = 1.0) -> Dictionary:
	var held := finds_aboard()
	var ns := int(held.samples) if sample_rate > 0.0 else 0
	var nw := int(held.salvage) if salvage_rate > 0.0 else 0
	var f := {"samples": ns, "salvage": nw,
			"value": roundi(ns * SurfaceFinds.value("sample") * sample_rate + nw * SurfaceFinds.value("salvage") * salvage_rate)}
	if int(f.value) <= 0 or slot < 0 or sim == null:
		return {"ok": false, "message": "Nothing to sell here."}
	var data := SaveSlots.read(slot)
	var loaded := _load_ship(data)
	if loaded.is_empty():
		return {"ok": false, "message": "Could not load the current ship."}
	_sync_sim(loaded.ship)
	sim._pay("world", SimWorld.PLAYER, float(f.value))
	var pc: Dictionary = sim.carriers[SimWorld.PLAYER]
	pc["revenue"] = float(pc["revenue"]) + float(f.value)
	profile["samples"] = int(held.samples) - ns
	profile["salvage"] = int(held.salvage) - nw
	_commit_sim(data, loaded.ship)
	data["profile"] = profile
	SaveSlots.write(slot, data)
	return {"ok": true, "message": "Sold %d samples and %d salvage parts for %s cr." % [int(f.samples), int(f.salvage), ShipStats.commas(int(f.value))]}


## Fuel here against the system's price: depots are cheap, the surface dear (local_space.json).
static func site_fuel_mult(site_id: String = "") -> float:
	var id := site_id if site_id != "" else String(profile.get("port_id", ""))
	var kind := String(LocalSpace.node(id).get("kind", "port"))
	return float(LocalSpace.config().get("site_fuel_price", {}).get(kind, 1.0))


static func site_repair_mult() -> float:
	var kind := String(LocalSpace.node(String(profile.get("port_id", ""))).get("kind", "port"))
	return float(LocalSpace.config().get("site_repair_rate", {}).get(kind, 1.0))


## What fixing the hull costs here.
static func repair_cost() -> int:
	var dmg := float(profile.get("hull_damage", 0.0))
	if dmg <= 0.0 or slot < 0:
		return 0
	var loaded := _load_ship(SaveSlots.read(slot))
	if loaded.is_empty():
		return 0
	var lv := SimShip.level(String(profile.get("difficulty", "normal")))
	var frac := float(FlightModel.load_tuning().get("repair_cost_fraction_of_ship", 0.15))
	return roundi(dmg * float(ship_cost(loaded.ship, loaded.ship.library)) * frac * float(lv.get("maintenance_mult", 1.0)) * site_repair_mult())


## Pay the yard here to make the hull good again (it also restores the thrust damage takes away).
static func repair_hull() -> Dictionary:
	var cost := repair_cost()
	if cost <= 0:
		return {"ok": false, "message": "The hull needs no work."}
	var data := SaveSlots.read(slot)
	var loaded := _load_ship(data)
	if loaded.is_empty() or sim == null:
		return {"ok": false, "message": "Could not load the current ship."}
	if int(profile.get("credits", 0)) < cost:
		return {"ok": false, "message": "Repairs here cost %s cr; you have %s cr." % [ShipStats.commas(cost), ShipStats.commas(int(profile.credits))]}
	_sync_sim(loaded.ship)
	sim._pay(SimWorld.PLAYER, "world", float(cost))
	profile["hull_damage"] = 0.0
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
		return {"ok": false, "message": "This run does not start from here."}
	var loaded_ship := _load_ship(SaveSlots.read(slot))
	if loaded_ship.is_empty():
		return {"ok": false, "message": "Could not load the current ship."}
	var stats := ship_stats(loaded_ship.ship, loaded_ship.manifest)
	if not Contracts.ready(Contracts.check(stats, loaded_ship.manifest, c)):
		return {"ok": false, "message": "The ship is not ready to depart with this load."}
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
		return {"ok": false, "message": "This contract does not depart from here."}
	var loaded_ship := _load_ship(SaveSlots.read(slot))
	if loaded_ship.is_empty():
		return {"ok": false, "message": "Could not load the current ship."}
	var stats := ship_stats(loaded_ship.ship, loaded_ship.manifest)
	if not Contracts.ready(Contracts.check(stats, loaded_ship.manifest, c)):
		return {"ok": false, "message": "The ship is not ready to depart with this load."}
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
		return {"ok": false, "days": 0.0, "message": "Could not load the current ship."}
	_sync_sim(loaded_ship.ship)
	var hours := sim.run_player_until(SimWorld.PLAYER, "arrival")
	profile["system_id"] = String(c.destination_system_id)
	profile["port_id"] = String(c.destination_port_id)
	c["status"] = "arrived"
	data["active_contract"] = c
	data["profile"] = profile
	_commit_sim(data, loaded_ship.ship)
	SaveSlots.write(slot, data)
	flight_job["jumped"] = true
	return {"ok": true, "days": hours / 24.0, "message": "Jumped %.2f ly in %.1f days." % [float(c.distance_ly), hours / 24.0]}


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
	var msg := ""
	if bool(job.get("jumped", false)):
		msg = "Docked at %s. Manoeuvring fuel %s cr%s.%s" % [job.destination, ShipStats.commas(int(r.fuel_cost)),
				", hull repairs %s cr" % ShipStats.commas(int(r.repair_cost)) if int(r.repair_cost) > 0 else "", " A tug towed you in (%s cr)." % ShipStats.commas(roundi(tow)) if stranded else ""]
	else:
		msg = "Turned back before the jump. Fuel %s cr. The load is still aboard.%s" % [ShipStats.commas(int(r.fuel_cost)), " A tug brought you in (%s cr)." % ShipStats.commas(roundi(tow)) if stranded else ""]
	_commit_sim(data, loaded.ship)
	data["profile"] = profile
	SaveSlots.write(slot, data)
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
	if slot < 0 or sim == null or c.is_empty() or job.is_empty():
		return ""
	var data := SaveSlots.read(slot)
	var loaded := _load_ship(data)
	if loaded.is_empty():
		return ""
	_sync_sim(loaded.ship)
	var lv := SimShip.level(String(profile.get("difficulty", "normal")))
	var cfg: Dictionary = LocalSpace.config()["board"]
	var clock := float(int(job.hours)) * 3600.0 if arrived else seconds
	var r := SimWorld.settle_flight(sim, fuel_burned_t, clock, 0.0, float(ship_cost(loaded.ship, loaded.ship.library)), site_fuel_mult())
	profile["hull_damage"] = clampf(damage, 0.0, 1.0)   # carried until repaired at a fuel and repair desk
	var extra := 0.0
	if arrived:
		extra = float(cfg["dock_fee_cr"]) * float(lv.get("port_fee_mult", 1.0))
	if stranded:
		extra += float(cfg["tow_fee_cr"]) * float(lv.get("port_fee_mult", 1.0))
	sim._pay(SimWorld.PLAYER, "world", extra)
	var msg := ""
	if arrived:
		profile["port_id"] = String(c.destination_port_id)
		if surface and String(LocalSpace.node(String(c.destination_port_id)).get("kind", "")) == "moon":
			profile["port_id"] = system_id() + LocalSpace.SEP + "pad"   # landed on the base's pad, not docked in orbit
		c["status"] = "arrived"
		if surface:
			c["surface"] = true
		data["active_contract"] = c
		msg = (("Landed on the pad at %s." if surface else "Docked at %s.") + " Fuel %s cr, berth fee %s cr%s.%s") % [job.destination, ShipStats.commas(int(r.fuel_cost)), ShipStats.commas(roundi(extra)),
				", hull repairs %s cr" % ShipStats.commas(int(r.repair_cost)) if int(r.repair_cost) > 0 else "", " A tug towed you in." if stranded else ""]
	elif stranded:
		msg = "Out of fuel. A tug brought you back for %s cr plus %s cr of fuel. The load is still aboard." % [ShipStats.commas(roundi(extra)), ShipStats.commas(int(r.fuel_cost))]
	else:
		msg = "Turned back to the start. Fuel %s cr. The load is still aboard." % ShipStats.commas(int(r.fuel_cost))
	_commit_sim(data, loaded.ship)
	data["profile"] = profile
	SaveSlots.write(slot, data)
	flash = msg
	return msg


static func _depart_local(c: Dictionary) -> Dictionary:
	if String(c.origin_port_id) != String(profile.get("port_id", "")):
		return {"ok": false, "message": "This run does not start from here."}
	var data := SaveSlots.read(slot)
	var loaded_ship := _load_ship(data)
	if loaded_ship.is_empty():
		return {"ok": false, "message": "Could not load the current ship."}
	var manifest: CargoManifest = loaded_ship.manifest
	var stats := ship_stats(loaded_ship.ship, manifest)
	if not Contracts.ready(Contracts.check(stats, manifest, c)):
		return {"ok": false, "message": "The ship is not ready to depart with this load."}
	var cargo := float(c.get("accepted_tonnes", c.offer))
	var cost := local_trip_cost(stats, cargo, float(c.dv_kms))
	if float(cost.burn_t) > float(stats["fuel"]):
		return {"ok": false, "message": "The tanks cannot cover that burn."}
	_sync_sim(loaded_ship.ship)
	sim._pay(SimWorld.PLAYER, "world", float(cost.total))
	sim.run_hours(int(c.hours))
	profile["port_id"] = String(c.destination_port_id)
	c["status"] = "arrived"
	data["active_contract"] = c
	data["profile"] = profile
	_commit_sim(data, loaded_ship.ship)
	SaveSlots.write(slot, data)
	return {"ok": true, "message": "Burned %.1f t of fuel (%s cr) and reached %s in %d hours." % [float(cost.burn_t), ShipStats.commas(roundi(float(cost.total))), String(LocalSpace.node(String(c.destination_port_id)).get("name", "the site")), int(c.hours)]}


static func _deliver_local(c: Dictionary) -> Dictionary:
	var here := String(profile.get("port_id", ""))
	var landed_for_it := bool(c.get("surface", false)) and here == system_id() + LocalSpace.SEP + "pad" \
			and String(LocalSpace.node(String(c.destination_port_id)).get("kind", "")) == "moon"   # landed on the base's pad
	if String(c.destination_port_id) != here and not landed_for_it:
		return {"ok": false, "message": "There is no contract to deliver here."}
	var data := SaveSlots.read(slot)
	var loaded_ship := _load_ship(data)
	if loaded_ship.is_empty():
		return {"ok": false, "message": "Could not load the current ship."}
	var manifest: CargoManifest = loaded_ship.manifest
	var delivered := manifest.unload(StringName(c.commodity), float(c.get("accepted_tonnes", c.offer)))
	var payment := int(c.get("pay_total", roundi(delivered * float(c.rate))))
	var bonus := 0
	if bool(c.get("surface", false)):   # landed straight on the moon base's pad: no lighter up from orbit
		bonus = roundi(float(payment) * float(SurfaceTerrain.config().get("surface_bonus", 0.25)))
		payment += bonus
	_sync_sim(loaded_ship.ship)
	sim.run_hours(int(LocalSpace.config()["board"]["unload_hours"]))
	sim._pay("world", SimWorld.PLAYER, float(payment))
	var pc: Dictionary = sim.carriers[SimWorld.PLAYER]
	pc["revenue"] = float(pc["revenue"]) + float(payment)
	pc["trips"] = int(pc["trips"]) + 1
	_commit_sim(data, loaded_ship.ship)
	data["cargo"] = manifest.to_dict()
	data.erase("active_contract")
	data["profile"] = profile
	SaveSlots.write(slot, data)
	var note := " (includes %s cr for landing it on the surface)" % ShipStats.commas(bonus) if bonus > 0 else ""
	return {"ok": true, "message": "Delivered %.1f t. Freight paid: %s cr%s." % [delivered, ShipStats.commas(payment), note], "payment": payment}


static func depart_active_contract() -> Dictionary:
	var c := active_contract()
	if c.is_empty():
		return {"ok": false, "message": "Accept a freight contract first."}
	if bool(c.get("local", false)):
		return _depart_local(c)
	if String(c.origin_system_id) != system_id():
		return {"ok": false, "message": "This contract does not depart from the current system."}
	var data := SaveSlots.read(slot)
	var loaded_ship := _load_ship(data)
	if loaded_ship.is_empty():
		return {"ok": false, "message": "Could not load the current ship."}
	var manifest: CargoManifest = loaded_ship.manifest
	var stats := ship_stats(loaded_ship.ship, manifest)
	var checks := Contracts.check(stats, manifest, c)
	if not Contracts.ready(checks):
		return {"ok": false, "message": "The ship is not ready to depart with this load."}
	var days_text := ""
	var live := sim != null and c.has("sim_taken")
	if live:
		_sync_sim(loaded_ship.ship)
		var hours := sim.run_player_until(SimWorld.PLAYER, "arrival")
		days_text = " The trip took %.1f days." % (hours / 24.0)
	profile["system_id"] = String(c.destination_system_id)
	profile["port_id"] = String(c.destination_port_id)
	c["status"] = "arrived"
	data["active_contract"] = c
	data["profile"] = profile
	if live:
		_commit_sim(data, loaded_ship.ship)
	SaveSlots.write(slot, data)
	return {"ok": true, "message": "Arrived at %s after %.2f ly.%s" % [Worlds.port(profile.port_id).name, float(c.distance_ly), days_text]}


static func deliver_active_contract() -> Dictionary:
	var c := active_contract()
	if not c.is_empty() and bool(c.get("local", false)):
		return _deliver_local(c)
	if c.is_empty() or String(c.destination_system_id) != system_id():
		return {"ok": false, "message": "There is no contract to deliver here."}
	var data := SaveSlots.read(slot)
	var loaded_ship := _load_ship(data)
	if loaded_ship.is_empty():
		return {"ok": false, "message": "Could not load the current ship."}
	var manifest: CargoManifest = loaded_ship.manifest
	var delivered := manifest.unload(StringName(c.commodity), float(c.get("accepted_tonnes", c.offer)))
	var payment := roundi(delivered * float(c.rate))
	if sim != null and c.has("sim_taken"):
		_sync_sim(loaded_ship.ship)
		sim.run_player_until(SimWorld.PLAYER, "done")   # unloading takes hours; the consignee pays the moment it is done
		payment = int(c.get("pay_total", payment))
		_commit_sim(data, loaded_ship.ship)
	else:
		profile["credits"] = int(profile.credits) + payment
		data["earned"] = int(data.get("earned", 0)) + payment
	data["cargo"] = manifest.to_dict()
	data.erase("active_contract")
	data["profile"] = profile
	SaveSlots.write(slot, data)
	return {"ok": true, "message": "Delivered %.1f t. Freight paid: %s cr." % [delivered, ShipStats.commas(payment)], "payment": payment}


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
