class_name ShipPresets
extends RefCounted
## Ready-made ships. Built through the normal placement rules, so a preset can never be a ship
## the builder couldn't have made.

## Name, then [module, cell, rotation] steps in an order where each piece attaches to the last.
const STARTER := [
	[&"cockpit", Vector3i(0, 0, 0), 0],
	[&"tee", Vector3i(0, 0, 1), 0],
	[&"airlock", Vector3i(1, 0, 1), 0],
	[&"cargo_hold", Vector3i(0, 0, 2), 0],
	[&"engineering", Vector3i(0, 0, 4), 0],
	[&"engine", Vector3i(0, 0, 5), 0],
	[&"radiator", Vector3i(1, 0, 4), 0],
	[&"radiator", Vector3i(-1, 0, 4), 2],
	[&"radiator", Vector3i(1, 0, 3), 0],
	[&"tank", Vector3i(-1, 0, 2), 0],
]

## The starter plus an FTL drive and the radiator it needs: what a captain flies once they can
## afford to go between stars. The plain STARTER is sublight only.
const STARTER_FTL := [
	[&"cockpit", Vector3i(0, 0, 0), 0],
	[&"tee", Vector3i(0, 0, 1), 0],
	[&"airlock", Vector3i(1, 0, 1), 0],
	[&"cargo_hold", Vector3i(0, 0, 2), 0],
	[&"engineering", Vector3i(0, 0, 4), 0],
	[&"engine", Vector3i(0, 0, 5), 0],
	[&"radiator", Vector3i(1, 0, 4), 0],
	[&"radiator", Vector3i(-1, 0, 4), 2],
	[&"radiator", Vector3i(1, 0, 3), 0],
	[&"tank", Vector3i(-1, 0, 2), 0],
	[&"jump_drive", Vector3i(1, 0, 2), 0],
	[&"radiator", Vector3i(1, 0, 0), 0],
]


## The starter with two lander legs under it (hold and engineering) and a second fuel tank for the
## descent: what a captain flies to land freight on a moon base. Used by the landing tests.
const STARTER_LANDER := [
	[&"cockpit", Vector3i(0, 0, 0), 0],
	[&"tank", Vector3i(-1, 0, 0), 0],
	[&"tee", Vector3i(0, 0, 1), 0],
	[&"airlock", Vector3i(1, 0, 1), 0],
	[&"cargo_hold", Vector3i(0, 0, 2), 0],
	[&"engineering", Vector3i(0, 0, 4), 0],
	[&"engine", Vector3i(0, 0, 5), 0],
	[&"radiator", Vector3i(1, 0, 4), 0],
	[&"radiator", Vector3i(-1, 0, 4), 2],
	[&"radiator", Vector3i(1, 0, 3), 0],
	[&"tank", Vector3i(-1, 0, 2), 0],
	[&"lander_legs", Vector3i(0, -1, 2), 0],
	[&"lander_legs", Vector3i(0, -1, 4), 0],
]


## The starter with two crew bunks behind the cockpit: two spare berths for passengers (People).
const STARTER_CABIN := [
	[&"cockpit", Vector3i(0, 0, 0), 0],
	[&"bunk", Vector3i(0, 0, 1), 0],
	[&"bunk", Vector3i(0, 0, 2), 0],
	[&"tee", Vector3i(0, 0, 3), 0],
	[&"airlock", Vector3i(1, 0, 3), 0],
	[&"cargo_hold", Vector3i(0, 0, 4), 0],
	[&"engineering", Vector3i(0, 0, 6), 0],
	[&"engine", Vector3i(0, 0, 7), 0],
	[&"radiator", Vector3i(1, 0, 6), 0],
	[&"radiator", Vector3i(-1, 0, 6), 2],
	[&"radiator", Vector3i(1, 0, 5), 0],
	[&"tank", Vector3i(-1, 0, 4), 0],
]


## Replaces whatever is on `ship`. Returns the first error, or "" if everything placed.
static func build(ship: ShipData, steps: Array = STARTER) -> String:
	ship.clear()
	for step in steps:
		var err := ship.add(step[0], step[1], step[2])
		if err != "":
			return "%s at %s: %s" % [step[0], step[1], err]
	return ""
