extends SceneTree
## Headless checks for the ship data rules and stats. Run from the project folder:
##   godot --headless --script res://tests/test_ship.gd

var failures := 0


func check(cond: bool, label: String) -> void:
	if cond:
		print("  ok    ", label)
	else:
		print("  FAIL  ", label)
		failures += 1


func has_warning(st: Dictionary, prefix: String) -> bool:
	return st.warnings.any(func(w: String) -> bool: return w.begins_with(prefix))


func _init() -> void:
	var lib := ModuleLibrary.new()

	print("rotation")
	check(ShipGrid.rotate_cell(Vector3i(1, 0, 0), 1) == Vector3i(0, 0, -1), "+X turns to -Z")
	check(ShipGrid.rotate_cell(Vector3i(1, 0, 2), 4) == Vector3i(1, 0, 2), "four turns is identity")
	check(ShipGrid.rotate_cell(Vector3i(0, 1, 0), 3) == Vector3i(0, 1, 0), "up is unchanged")

	print("door placement rules")
	var ship := ShipData.new(lib)
	check(ship.add(&"cockpit", Vector3i(0, 0, 0), 0) == "", "first module goes anywhere")
	check(ship.add(&"corridor", Vector3i(0, 0, 0), 0) != "", "overlap rejected")
	check(ship.add(&"corridor", Vector3i(5, 0, 5), 0) != "", "floating module rejected")
	check(ship.add(&"corridor", Vector3i(0, 0, 1), 1) != "", "wrongly rotated corridor rejected")
	check(ship.add(&"corridor", Vector3i(0, 0, 1), 0) == "", "corridor snaps behind cockpit")
	check(ship.add(&"engineering", Vector3i(0, 0, 2), 0) == "", "engineering snaps onto corridor end")

	print("external mounts")
	check(ship.add(&"engine", Vector3i(0, 0, 3), 0) == "", "engine bolts onto bare rear hull face")
	var doorway_test := ShipData.new(lib)
	doorway_test.add(&"cockpit", Vector3i(0, 0, 0), 0)
	check(doorway_test.add(&"engine", Vector3i(0, 0, 1), 0) != "", "engine can't bolt over a doorway")
	check(ship.add(&"frame", Vector3i(1, 0, 1), 0) == "", "frame bolts onto a corridor's side")
	check(ship.add(&"tank", Vector3i(2, 0, 1), 0) == "", "tank bolts onto the frame")
	check(ship.add(&"radiator", Vector3i(1, 0, 0), 0) == "", "radiator bolts onto cockpit side")
	check(ship.add(&"frame", Vector3i(6, 0, 6), 0) != "", "floating frame rejected")
	check(ship.add(&"corner", Vector3i(0, 1, 1), 0) != "", "pressurised module can't float on a door-less hull face")
	check(ship.modules.size() == 7, "seven modules placed")

	print("removal")
	check(ship.remove_at(Vector3i(0, 0, 1)) != "", "removing the middle is refused")
	check(ship.modules.size() == 7, "ship unchanged after refusal")
	check(ship.remove_at(Vector3i(2, 0, 1)) == "", "removing the tank works")
	check(ship.modules.size() == 6, "six modules left")

	print("multi-cell and vertical")
	var s2 := ShipData.new(lib)
	check(s2.add(&"room_2x2", Vector3i(0, 0, 0), 1) == "", "room placed rotated")
	check(s2.occupied.size() == 4, "room occupies four cells")
	check(s2.occupied.has(Vector3i(1, 0, -1)), "rotated cell offset is right")
	var s3 := ShipData.new(lib)
	s3.add(&"shaft", Vector3i(0, 0, 0), 0)
	check(s3.add(&"shaft", Vector3i(0, 1, 0), 0) == "", "shaft stacks on shaft")
	check(s3.add(&"corridor", Vector3i(0, 2, 0), 0) != "", "corridor can't connect to shaft top")

	print("stats")
	var s4 := ShipData.new(lib)
	s4.add(&"cockpit", Vector3i(0, 0, 0), 0)
	s4.add(&"corridor", Vector3i(0, 0, 1), 0)
	var st := ShipStats.compute(s4)
	var m0 := lib.get_def(&"cockpit").mass
	var m1 := lib.get_def(&"corridor").mass
	check(is_equal_approx(st.dry, m0 + m1), "dry mass adds up")
	check(st.cost == lib.get_def(&"cockpit").cost + lib.get_def(&"corridor").cost, "cost adds up")
	var rel: Vector3 = st.com - st.centre
	check(is_equal_approx(rel.z, (m1 * 3.0) / (m0 + m1) - 1.5), "centre of mass sits toward the heavier end")
	check(is_equal_approx(rel.x, 0.0) and is_equal_approx(rel.y, 0.0), "centre of mass on the centreline")
	check(not has_warning(st, "No cockpit"), "cockpit satisfies the helm check")
	check(has_warning(ShipStats.compute(s3), "No cockpit"), "no cockpit is flagged")

	var full := ShipStats.compute(ship)  # cockpit, corridor, engineering, engine, frame, radiator
	check(full.thrust_fwd == 80.0, "engine thrust points forward")
	check(full.power_gen == 100.0 and full.power_use == 18.0, "power balance")
	check(full.cooling == 60.0 and full.heat_gen == 148.0, "heat balance")
	check(has_warning(full, "Overheating"), "overheating flagged")
	check(not has_warning(full, "Power short"), "power is fine")

	var s5 := ShipData.new(lib)  # engine mounted well off the centre of mass
	s5.add(&"engineering", Vector3i(0, 0, 0), 0)
	s5.add(&"frame", Vector3i(1, 0, 0), 0)
	s5.add(&"engine", Vector3i(1, 0, 1), 0)
	check(has_warning(ShipStats.compute(s5), "Thrust is"), "off-axis thrust flagged")
	var s6 := ShipData.new(lib)  # engine straight behind: no offset warning
	s6.add(&"engineering", Vector3i(0, 0, 0), 0)
	s6.add(&"engine", Vector3i(0, 0, 1), 0)
	check(not has_warning(ShipStats.compute(s6), "Thrust is"), "on-axis thrust is fine")
	var s7 := ShipData.new(lib)  # engine bolted on sideways, pushing the ship west
	s7.add(&"engineering", Vector3i(0, 0, 0), 0)
	s7.add(&"frame", Vector3i(1, 0, 0), 0)
	check(s7.add(&"engine", Vector3i(2, 0, 0), 1) == "", "engine mounts sideways on the frame")
	check(has_warning(ShipStats.compute(s7), "Some engines"), "misaligned engine flagged")

	print("save and load")
	var json := ship.to_json()
	var s8 := ShipData.new(lib)
	check(s8.from_json(json), "json loads (mounts count as connections)")
	check(s8.modules.size() == ship.modules.size(), "same module count")
	check(s8.occupied.keys().size() == ship.occupied.keys().size(), "same occupied cells")
	check(not s8.from_json("not json"), "garbage rejected")
	check(not s8.from_json('{"modules":[{"id":"nope","cell":[0,0,0]}]}'), "unknown module rejected")
	check(s8.modules.size() == ship.modules.size(), "failed load leaves ship untouched")

	print("")
	print("FAILED: %d" % failures if failures > 0 else "all passed")
	quit(1 if failures > 0 else 0)
