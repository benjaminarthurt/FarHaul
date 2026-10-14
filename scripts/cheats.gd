class_name Cheats
extends RefCounted
## Debug cheats, for testing ships and flying without earning the money first. Off unless Settings >
## Debug cheats is on; then the pause menu (Esc) lists them in any scene of a saved game. Using one marks
## the save (profile.cheated), and the pause menu says so from then on.
##
## - Money: a million credits, paid in from outside the economy (not counted as freight revenue).
## - Repair and resupply: hull to 100% with the patches gone, every working part new, patch and spares
##   kits full; in flight also full tanks, the heat dumped, and the hull's breach undone.
## In the shipyard the money goes on the builder's own books (its `earned`), which it saves with the ship.

const MONEY := 1000000


static func actions(scene: Node) -> Array:
	var out := [{"text": "+%s CR" % ShipStats.commas(MONEY), "kind": "credits"},
			{"text": "REPAIR AND RESUPPLY" + ("  (AND REFUEL)" if scene is FlightScene else ""), "kind": "fix"}]
	return out


## Do one; returns what happened, for the menu's note.
static func run(scene: Node, kind: String) -> String:
	var msg := ""
	if scene != null and scene.has_method("cheat"):
		msg = String(scene.cheat(kind))
	if msg == "":
		var r := money() if kind == "credits" else fix()
		msg = String(r.message)
	if scene != null and scene.has_method("_refill"):
		scene._refill()
	return msg


static func money(amount := MONEY) -> Dictionary:
	if Session.slot < 0 or Session.sim == null:
		return {"ok": false, "message": "No saved game to cheat in."}
	var data := SaveSlots.read(Session.slot)
	var loaded := Session._load_ship(data)
	if loaded.is_empty():
		return {"ok": false, "message": "Couldn't load the ship from the save."}
	Session._sync_sim(loaded.ship)
	Session.sim._pay("world", SimWorld.PLAYER, float(amount))
	Session.profile["cheated"] = true
	Session._commit_sim(data, loaded.ship)
	data["profile"] = Session.profile
	SaveSlots.write(Session.slot, data)
	return {"ok": true, "message": "+%s cr. Nobody asks where it came from." % ShipStats.commas(amount)}


static func fix() -> Dictionary:
	if Session.slot < 0:
		return {"ok": false, "message": "No saved game to cheat in."}
	Session.profile["hull_damage"] = 0.0
	Session.profile["hull_patches"] = []
	Session.profile["wear"] = {}
	Session.profile["patch_kits"] = Session.patch_kit_max()
	Session.profile["spares_kits"] = int(Wear.cfg().get("spares_kit_max", 4))
	Session.profile["cheated"] = true
	Session.save_profile()
	return {"ok": true, "message": "Hull at 100%, every part new, kit lockers full. Free, apart from your conscience."}
