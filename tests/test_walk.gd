extends SceneTree
## Walking inside the ship, headless: the starter can be walked from the airlock to the helm, the hold and
## engineering; walls, the hull and freight stop the walker; doors let it through; ladder shafts change deck.
## Run: godot --headless --path . --script res://tests/test_walk.gd

var fails := 0

func check(ok: bool, msg: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + msg)
	if not ok:
		fails += 1


func _initialize() -> void:
	process_frame.connect(_run, CONNECT_ONE_SHOT)


func _built(steps: Array) -> Dictionary:
	var ship := ShipData.new(ModuleLibrary.new())
	var err := ShipPresets.build(ship, steps)
	var view := ShipView.new()
	root.add_child(view)
	view.rebuild(ship)
	return {"ship": ship, "view": view, "walk": ShipWalk.build(ship, view), "err": err}


## Every point of a 0.1 m grid on one deck that can be reached from `start` without touching anything.
func reachable(w: ShipWalk, start: Vector3) -> Dictionary:
	var step := 0.1
	var seen := {}
	var y := start.y
	var key := Vector2i(roundi(start.x / step), roundi(start.z / step))
	var queue: Array[Vector2i] = [key]
	seen[key] = true
	while not queue.is_empty() and seen.size() < 200000:
		var k: Vector2i = queue.pop_back()
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = k + d
			if seen.has(n):
				continue
			if w.free_at(Vector3(n.x * step, y, n.y * step)):
				seen[n] = true
				queue.append(n)
	return seen


func can_reach(seen: Dictionary, x: float, z: float, within := 0.15) -> bool:
	var step := 0.1
	var c := Vector2i(roundi(x / step), roundi(z / step))
	var r := ceili(within / step)
	for dx in range(-r, r + 1):
		for dz in range(-r, r + 1):
			if seen.has(c + Vector2i(dx, dz)):
				return true
	return false


func _run() -> void:
	print("Starter ship")
	var b := _built(ShipPresets.STARTER)
	var w: ShipWalk = b.walk
	check(b.err == "", "starter builds")
	check(w.cells.size() == 6, "six walkable cells: cockpit, tee, airlock, two of hold, engineering (%d)" % w.cells.size())
	check(w.furniture.get(0, []).size() > 30, "furniture found on the deck (%d pieces)" % w.furniture.get(0, []).size())
	check(w.helm_seat != Vector3.INF and w.airlock != Vector3.INF, "helm seat and airlock located")

	check(w.stand_in_airlock(), "can stand in the airlock")
	var start := w.pos
	check(w.free_at(start) and w.room() == "Airlock", "airlock spawn is clear (%s, %s)" % [start, w.room()])
	var seen := reachable(w, start)
	var seat := w.helm_stand
	check(can_reach(seen, seat.x, seat.z), "from the airlock to behind the seats")
	check(can_reach(seen, 0.0, 6.0) and can_reach(seen, 0.0, 9.0), "down the hold's aisle")
	check(can_reach(seen, 0.0, 10.95), "into engineering, in front of the reactor")
	check(not can_reach(seen, 1.05, 6.0, 0.0), "not into a container")
	check(not can_reach(seen, -3.0, 6.0, 0.0), "not out into the fuel tank")
	check(not can_reach(seen, 0.0, 12.1, 0.0), "not into the reactor")
	check(not can_reach(seen, 0.0, -1.5, 0.0), "not through the windscreen")

	check(w.stand_at_helm(), "can stand at the helm")
	check(w.near_helm(), "standing at the helm is within reach of the seat")
	check(w.room() == "Cockpit", "the helm is in the cockpit (%s)" % w.room())

	# Walk from the tee into the side wall: stopped at the wall.
	w.pos = Vector3(0, ShipWalk.deck_y(0), 3.0)
	w.face(Vector3(-1, 0, 0))
	for i in 60:
		w.step(0.05, Vector2(0, 1))
	check(w.pos.x > -1.38 and w.pos.x < -0.5, "the tee's blank wall stops the walker (x %.2f)" % w.pos.x)
	# Walk from the tee forward through the door into the cockpit.
	w.pos = Vector3(0, ShipWalk.deck_y(0), 3.0)
	w.face(Vector3(0, 0, -1))
	for i in 40:
		w.step(0.05, Vector2(0, 1))
	check(w.pos.z < 1.4 and w.room() == "Cockpit", "through the door into the cockpit (z %.2f, %s)" % [w.pos.z, w.room()])
	# Into the airlock through its door, east from the tee.
	w.pos = Vector3(0, ShipWalk.deck_y(0), 3.0)
	w.face(Vector3(1, 0, 0))
	for i in 40:
		w.step(0.05, Vector2(0, 1))
	check(w.room() == "Airlock" and w.pos.x < 4.38, "east through the airlock door, stopped by its outer wall (x %.2f)" % w.pos.x)
	check(w.near_airlock(), "standing in the airlock")
	# Running covers more ground.
	w.pos = Vector3(0, ShipWalk.deck_y(0), 9.0)
	w.face(Vector3(0, 0, -1))
	w.step(0.5, Vector2(0, 1), true)
	check(absf(w.pos.z - 7.0) < 0.05, "running is 4 m/s (moved %.2f m in 0.5 s)" % (9.0 - w.pos.z))

	print("Two decks joined by ladder shafts")
	var b2 := _built([
		[&"cockpit", Vector3i(0, 0, 0), 0],
		[&"shaft", Vector3i(0, 0, 1), 0],
		[&"shaft", Vector3i(0, 1, 1), 0],
		[&"corridor", Vector3i(0, 1, 2), 0],
	])
	var w2: ShipWalk = b2.walk
	check(b2.err == "", "two-deck ship builds (%s)" % b2.err)
	check(w2.hatches.size() == 2, "both shafts have a hatch (%d)" % w2.hatches.size())
	w2.pos = Vector3(0, ShipWalk.deck_y(0), 3.0)
	w2.pitch = 0.3
	check(w2.climb() == 1 and w2.level() == 1, "up the ladder to deck 1")
	w2.pitch = -0.5
	check(w2.climb() == -1 and w2.level() == 0, "down again when looking down")
	w2.pos = Vector3(0, ShipWalk.deck_y(0), 1.0)
	check(w2.climb() == 0, "no climbing away from the hatch")
	w2.pos = Vector3(0, ShipWalk.deck_y(1), 3.0)
	w2.face(Vector3(0, 0, 1))
	for i in 40:
		w2.step(0.05, Vector2(0, 1))
	check(w2.cell() == Vector3i(0, 1, 2), "walk off the shaft into the upper corridor (%s)" % w2.cell())

	print("walk tests: %s" % ("FAIL (%d)" % fails if fails > 0 else "all passed"))
	quit(1 if fails > 0 else 0)
