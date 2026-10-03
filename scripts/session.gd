class_name Session
extends RefCounted
## The game being played right now: which slot, and the player's profile.
## Scenes read this instead of passing arguments, so any scene can be opened on its own.

const BOOT_SCENE := "res://scenes/boot.tscn"
const DOCK_SCENE := "res://scenes/dock.tscn"
const YARD_SCENE := "res://scenes/main.tscn"

static var slot := -1  ## -1 when a scene was opened on its own, outside a saved game
static var profile: Dictionary = default_profile()
static var skip_intro := false  ## set when returning to the title so the splash and video don't replay
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
	return Worlds.port(id) if id != "" else Worlds.primary_port(system_id())


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


static func depart_active_contract() -> Dictionary:
	var c := active_contract()
	if c.is_empty():
		return {"ok": false, "message": "Accept a freight contract first."}
	if String(c.origin_system_id) != system_id():
		return {"ok": false, "message": "This contract does not depart from the current system."}
	var data := SaveSlots.read(slot)
	var loaded_ship := _load_ship(data)
	if loaded_ship.is_empty():
		return {"ok": false, "message": "Could not load the current ship."}
	var manifest: CargoManifest = loaded_ship.manifest
	var stats := ShipStats.compute(loaded_ship.ship, 1.0, manifest)
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
	return YARD_SCENE if profile.location == "shipyard" else DOCK_SCENE


## Writes the profile into the current slot without touching the ship. Returns false if not in a saved game.
static func save_profile() -> bool:
	if slot < 0:
		return false
	var data := SaveSlots.read(slot)
	if data.is_empty():
		return false
	data["profile"] = profile
	return SaveSlots.write(slot, data)
