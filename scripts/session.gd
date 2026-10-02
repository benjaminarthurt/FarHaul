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


static func accept_contract(contract: Dictionary) -> Dictionary:
	if slot < 0 or contract.is_empty() or not active_contract().is_empty():
		return {"ok": false, "message": "A contract is already active or this is not a saved game."}
	var data := SaveSlots.read(slot)
	var lib := ModuleLibrary.new()
	var ship := ShipData.new(lib)
	if not ship.from_json(JSON.stringify(data)):
		return {"ok": false, "message": "Could not load the current ship."}
	var manifest := CargoManifest.new(ship)
	manifest.from_dict(data.get("cargo", {}))
	var loaded := manifest.load(StringName(contract.commodity), float(contract.offer))
	if loaded <= CargoManifest.EPS:
		return {"ok": false, "message": "No compatible cargo capacity is available."}
	var accepted := contract.duplicate(true)
	accepted["accepted_tonnes"] = loaded
	accepted["status"] = "loaded"
	data["cargo"] = manifest.to_dict()
	data["active_contract"] = accepted
	data["profile"] = profile
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
	var lib := ModuleLibrary.new()
	var ship := ShipData.new(lib)
	if not ship.from_json(JSON.stringify(data)):
		return {"ok": false, "message": "Could not load the current ship."}
	var manifest := CargoManifest.new(ship)
	manifest.from_dict(data.get("cargo", {}))
	var stats := ShipStats.compute(ship, 1.0, manifest)
	var checks := Contracts.check(stats, manifest, c)
	if not Contracts.ready(checks):
		return {"ok": false, "message": "The ship is not ready to depart with this load."}
	profile["system_id"] = String(c.destination_system_id)
	profile["port_id"] = String(c.destination_port_id)
	c["status"] = "arrived"
	data["active_contract"] = c
	data["profile"] = profile
	SaveSlots.write(slot, data)
	return {"ok": true, "message": "Arrived at %s after %.2f ly." % [Worlds.port(profile.port_id).name, float(c.distance_ly)]}


static func deliver_active_contract() -> Dictionary:
	var c := active_contract()
	if c.is_empty() or String(c.destination_system_id) != system_id():
		return {"ok": false, "message": "There is no contract to deliver here."}
	var data := SaveSlots.read(slot)
	var lib := ModuleLibrary.new()
	var ship := ShipData.new(lib)
	ship.from_json(JSON.stringify(data))
	var manifest := CargoManifest.new(ship)
	manifest.from_dict(data.get("cargo", {}))
	var delivered := manifest.unload(StringName(c.commodity), float(c.get("accepted_tonnes", c.offer)))
	var payment := roundi(delivered * float(c.rate))
	profile["credits"] = int(profile.credits) + payment
	data["earned"] = int(data.get("earned", 0)) + payment
	data["cargo"] = manifest.to_dict()
	data.erase("active_contract")
	data["profile"] = profile
	SaveSlots.write(slot, data)
	return {"ok": true, "message": "Delivered %.1f t. Payment: %s cr." % [delivered, ShipStats.commas(payment)], "payment": payment}


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
