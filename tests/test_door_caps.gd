extends SceneTree
## Door caps (ModuleLibrary door_cap, porthole_cap): bolted over a doorway nobody uses, the hull counts as
## sealed; they only fit facing a doorway; they're cheap; the porthole shows through the outer hull; a
## space walker isn't walled out of the cap's cell.
## Run: godot --headless --path . --script res://tests/test_door_caps.gd
var fails := 0
func check(ok: bool, msg: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + msg)
	if not ok:
		fails += 1


func _initialize() -> void:
	var lib := ModuleLibrary.new()
	var ship := ShipData.new(lib)
	ship.add(&"cockpit", Vector3i(0, 0, 0), 0)
	ship.add(&"bunk", Vector3i(0, 0, 1), 0)
	check(ship.open_doors().size() == 1, "a bunk behind the cockpit leaves its back door open to space")
	check(ship.check_place(&"door_cap", Vector3i(0, 0, 2), 2) != "", "a cap turned away from the doorway doesn't fit")
	check(ship.add(&"door_cap", Vector3i(0, 0, 2), 0) == "", "facing the doorway, it bolts on")
	check(ship.open_doors().is_empty() and int(ShipStats.compute(ship).open_doors) == 0, "and the hull is sealed")
	check(lib.get_def(&"door_cap").cost <= 300 and lib.get_def(&"porthole_cap").cost <= 800 and lib.get_def(&"door_cap").mass < 0.2, "caps are cheap and light (%d and %d cr)" % [lib.get_def(&"door_cap").cost, lib.get_def(&"porthole_cap").cost])
	check(ship.remove_at(Vector3i(0, 0, 2)) == "" and ship.open_doors().size() == 1, "take it off and the doorway's open again")

	print("a cap only seals the doorway it faces")
	var two := ShipData.new(lib)
	two.add(&"cockpit", Vector3i(0, 0, 0), 0)
	two.add(&"tee", Vector3i(0, 0, 1), 0)          # doors N, S, E
	two.add(&"door_cap", Vector3i(0, 0, 2), 0)     # over the tee's back door
	check(two.open_doors().size() == 1 and two.open_doors()[0].dir == Vector3i(1, 0, 0), "the side door is still open")
	two.add(&"porthole_cap", Vector3i(1, 0, 1), 1)  # turned to face west, onto the tee's side door
	check(two.open_doors().is_empty(), "a porthole cap closes it too")

	print("on the outside")
	var press := ShipSkin.pressurised_cells(two)
	var info := {"def": lib.get_def(&"tee"), "rot": 0, "origin": Vector3i(0, 0, 1)}
	var holes := ShipSkin._holes(two, Vector3i(0, 0, 1), Vector3i(1, 0, 0), info)
	check(holes.size() == 1 and holes[0].has_point(ModuleDef.PORTHOLE.get_center()), "the hull has a hole for the porthole")
	check(ShipSkin._holes(two, Vector3i(0, 0, 1), Vector3i(0, 0, 1), info).is_empty(), "and none for a solid cap: the hull plates over it")
	check(ShipSkin.mount_offset(two, two.modules[2], press) == Vector3.ZERO, "caps stay on the pressure wall, under the hull")
	var boxes := SpaceWalk.ship_boxes(two)
	var in_cap := false
	for b in boxes:
		if b.has_point(Vector3(0, 0, 2) * ShipGrid.CELL + Vector3(0, 0, 1.0)):
			in_cap = true
	check(not in_cap, "a space walker can drift through the cap's cell")
	var view_node := lib.get_def(&"porthole_cap").build_visual()
	check(view_node.get_child_count() > 6, "the porthole cap has a plate, a frame and glass")
	view_node.free()

	print("parts bolt on over a cap")
	var three := ShipData.new(lib)
	three.add(&"cockpit", Vector3i(0, 0, 0), 0)
	three.add(&"tee", Vector3i(0, 0, 1), 0)          # side door east, at (1, 0, 1)
	check(three.check_place(&"radiator", Vector3i(1, 0, 1), 0) != "", "a radiator can't bolt over an open doorway")
	check(three.add(&"door_cap", Vector3i(1, 0, 1), 1) == "" and three.open_doors().size() == 1, "cap the side door")
	check(not three.occupied.has(Vector3i(1, 0, 1)), "the cap fills no cell")
	check(three.add(&"radiator", Vector3i(1, 0, 1), 0) == "", "so a radiator goes in that cell, bolted to the capped face: %s" % three.check_place(&"radiator", Vector3i(1, 0, 1), 0))
	check(three.check_place(&"porthole_cap", Vector3i(1, 0, 1), 1) != "", "and one cap to a doorway")
	check(three.remove_at(Vector3i(1, 0, 1)) == "" and three.modules.size() == 3 and lib.get_def(three.modules[2].id).seal, "shift-click takes the radiator first")
	check(three.remove_at(Vector3i(1, 0, 1)) == "" and three.modules.size() == 2, "then the cap")
	var st := ShipStats.compute(two)
	check(is_finite((st.com as Vector3).x) and float(st.wet) > 0.0 and float(st.radius) < 30.0, "stats stay sane with caps aboard")

	print("hatch caps")
	var four := ShipData.new(lib)
	four.add(&"cockpit", Vector3i(0, 0, 0), 0)
	four.add(&"shaft", Vector3i(0, 0, 1), 0)         # doors N, S, up, down
	four.add(&"door_cap", Vector3i(0, 0, 2), 0)
	check(four.open_doors().size() == 2, "a ladder shaft on its own: top and bottom open")
	check(four.add(&"hatch_cap_top", Vector3i(0, 1, 1), 0) == "" and four.add(&"hatch_cap_bottom", Vector3i(0, -1, 1), 0) == "", "hatch caps fit over both")
	check(four.open_doors().is_empty(), "and the hull is sealed")
	check(four.check_place(&"hatch_cap_top", Vector3i(0, -1, 1), 0) != "", "a top cap won't go underneath")

	print("saving")
	var copy := ShipData.new(lib)
	check(copy.from_json(two.to_json()) and copy.open_doors().is_empty(), "a capped ship saves and loads sealed")
	print("DONE fails=", fails)
	quit(1 if fails > 0 else 0)
