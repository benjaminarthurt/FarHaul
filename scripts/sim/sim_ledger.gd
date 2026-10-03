class_name SimLedger
extends RefCounted
## Inventory ledger. Material quantities change ONLY through the event
## methods below, so every unit can be audited.
## Invariant: on_hand >= reserved >= 0; available = on_hand - reserved.

var entries: Dictionary = {}   # "entity|commodity" -> entry dict
var produced_total: Dictionary = {}   # commodity -> units created by production
var consumed_total: Dictionary = {}   # commodity -> units destroyed by consumption
var initial_total: Dictionary = {}

static func key(entity: String, com: String) -> String:
	return entity + "|" + com

func entry(entity: String, com: String) -> Dictionary:
	var k := key(entity, com)
	if not entries.has(k):
		entries[k] = {"entity": entity, "commodity": com, "on_hand": 0.0, "reserved": 0.0,
				"initial": 0.0, "audit": 0.0}
	return entries[k]

func seed_stock(entity: String, com: String, units: float) -> void:
	var e := entry(entity, com)
	e["on_hand"] += units
	e["initial"] += units
	initial_total[com] = initial_total.get(com, 0.0) + units

func on_hand(entity: String, com: String) -> float:
	return entries.get(key(entity, com), {}).get("on_hand", 0.0)

func reserved(entity: String, com: String) -> float:
	return entries.get(key(entity, com), {}).get("reserved", 0.0)

func available(entity: String, com: String) -> float:
	return on_hand(entity, com) - reserved(entity, com)

func produce(entity: String, com: String, units: float) -> void:
	var e := entry(entity, com)
	e["on_hand"] += units
	e["audit"] += units
	produced_total[com] = produced_total.get(com, 0.0) + units

## Consume up to `units` of available stock. Returns the amount actually consumed.
func consume(entity: String, com: String, units: float) -> float:
	var e := entry(entity, com)
	var take: float = minf(units, e["on_hand"] - e["reserved"])
	take = maxf(take, 0.0)
	e["on_hand"] -= take
	e["audit"] -= take
	consumed_total[com] = consumed_total.get(com, 0.0) + take
	return take

func reserve(entity: String, com: String, units: float) -> bool:
	var e := entry(entity, com)
	if e["on_hand"] - e["reserved"] + 1e-9 < units:
		return false
	e["reserved"] += units
	return true

func release(entity: String, com: String, units: float) -> void:
	var e := entry(entity, com)
	e["reserved"] = maxf(0.0, e["reserved"] - units)

## Remove reserved goods from a holder (they are now on a carrier).
func ship_out(entity: String, com: String, units: float) -> bool:
	var e := entry(entity, com)
	if e["reserved"] + 1e-9 < units or e["on_hand"] + 1e-9 < units:
		return false
	e["reserved"] -= units
	e["on_hand"] -= units
	e["audit"] -= units
	return true

func receive(entity: String, com: String, units: float) -> void:
	var e := entry(entity, com)
	e["on_hand"] += units
	e["audit"] += units

func total_on_hand(com: String) -> float:
	var t := 0.0
	for e in entries.values():
		if e["commodity"] == com:
			t += e["on_hand"]
	return t

## Returns a list of violation strings (empty when sound).
func check() -> Array:
	var bad: Array = []
	for e in entries.values():
		if e["reserved"] < -1e-6 or e["on_hand"] < e["reserved"] - 1e-6:
			bad.append("%s/%s on_hand %.3f reserved %.3f" % [e["entity"], e["commodity"], e["on_hand"], e["reserved"]])
		if absf(e["on_hand"] - (e["initial"] + e["audit"])) > 1e-6:
			bad.append("%s/%s on_hand does not match audit trail" % [e["entity"], e["commodity"]])
	for com in initial_total:
		var expect: float = initial_total[com] + produced_total.get(com, 0.0) - consumed_total.get(com, 0.0)
		if absf(total_on_hand(com) - expect) > 1e-4:
			bad.append("%s not conserved: have %.3f expect %.3f" % [com, total_on_hand(com), expect])
	return bad
