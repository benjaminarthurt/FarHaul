extends SceneTree
## Landing in the flight scene: a run to a moon base with lander legs ends in a descent, the autopilot
## sets the ship on the pad, you walk out of the airlock onto the surface and back, unload, and the
## delivery pays the surface bonus. Run: godot --headless --path . --script res://tests/smoke_land.gd
var fails := 0
func check(ok: bool, msg: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + msg)
	if not ok:
		fails += 1
func _initialize() -> void:
	SaveSlots.dir = "user://test_saves_landsmoke"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SaveSlots.dir))
	process_frame.connect(_run, CONNECT_ONE_SHOT)
func _key(code: int) -> InputEventKey:
	var k := InputEventKey.new()
	k.keycode = code
	k.pressed = true
	return k
func _run() -> void:
	Session.begin_new(2, "Pilot", "human", "normal", "roosevelt_independent_yards")
	var data := SaveSlots.read(2)
	var ship := ShipData.new(ModuleLibrary.new())
	ShipPresets.build(ship, ShipPresets.STARTER_LANDER)
	data["modules"] = (JSON.parse_string(ship.to_json()) as Dictionary)["modules"]
	data["cargo"] = CargoManifest.new(ship).to_dict()
	SaveSlots.write(2, data)
	SimWorld.sync(Session.sim, Session.profile, ship)
	var job: Dictionary = {}
	for o in Contracts.offers_from(Session.system_id()):
		if bool(o.get("local", false)) and String(LocalSpace.node(String(o.destination_port_id)).get("kind", "")) == "moon":
			job = o
			break
	check(not job.is_empty(), "a run to the moon base is posted")
	check(bool(Session.accept_contract(job).ok), "accepted and loaded")
	check(bool(Session.begin_local_flight().ok) and String(Session.flight_job.get("dest_kind", "")) == "moon", "the helm is handed a moon run")
	var f: Node = load("res://scenes/flight.tscn").instantiate()
	root.add_child(f)
	await process_frame
	check(f._can_land(), "the lander can land with this load")
	# Skip the cruise: arrive at the marker.
	f.phase = "cruise"
	f.model.station_solid = false
	f.model.pos = f.xfer.target
	f.model.vel = Vector3.ZERO
	await process_frame
	await process_frame
	check(f.phase == "descent" and f.moon != null and f.model.gravity > 1.0, "arriving brings the descent over the moon")
	check(f.model.altitude() > 1000.0 and f.hud.text.contains("ALTITUDE"), "high above the pad (%.0f m)" % f.model.altitude())
	f._unhandled_input(_key(KEY_ESCAPE))
	check(f.model.autoland, "Esc hands it to the autopilot")
	var t := 0.0
	while t < 400.0 and not f.model.landed:
		f._process(0.05)
		t += 0.05
	check(f.model.landed and f.model.on_pad() and f.model.damage == 0.0, "landed on the pad in %.0f s, undamaged" % t)
	f._update_hud()
	check(f.prompt.text.contains("unload"), "the prompt offers unloading (%s)" % f.prompt.text)
	# Walk out onto the surface.
	check(f.get_up(), "get up from the helm")
	f.walk.pos = Vector3(0, ShipWalk.deck_y(0), 3.0)
	f.walk.face(Vector3(1, 0, 0))
	for i in 40:
		f.walk.step(0.05, Vector2(0, 1))
	f._update_hud()
	check(f.walk.near_airlock() and f.prompt.text.contains("step outside"), "the airlock offers the surface (%s)" % f.prompt.text)
	check(f.use() == "outside" and f.outside, "E steps outside")
	var g0: float = f.model.terrain.height(f.suit.pos.x, f.suit.pos.z)
	check(absf(f.suit.pos.y - g0) < 0.01, "standing on the ground")
	# Walk straight at the ship: the hull stops you.
	var to_ship: Vector3 = (f.model.pos - f.suit.pos)
	f.suit.face(Vector3(to_ship.x, 0, to_ship.z).normalized())
	for i in 100:
		f.suit.step(0.05, Vector2(0, 1))
	check(f.suit.distance_to(f.model.pos) > 1.0, "the ship is solid (%.1f m from its centre)" % f.suit.distance_to(f.model.pos))
	# Jump: low gravity, slow.
	f.suit.place(f.suit_hatch + Vector3(8, 0, 8))
	f.suit.step(0.05, Vector2.ZERO, false, true)
	var peak := 0.0
	for i in 80:
		f.suit.step(0.05, Vector2.ZERO)
		peak = maxf(peak, f.suit.pos.y - f.model.terrain.height(f.suit.pos.x, f.suit.pos.z))
	check(peak > 1.2 and f.suit.on_ground, "a jump goes %.1f m up and comes down" % peak)
	f.suit.place(f.suit_hatch)
	check(f.come_aboard() and f.walking and not f.outside, "back aboard through the airlock")
	f.walk.stand_at_helm()
	f.sit_down()
	var cr0 := int(Session.profile.credits)
	f._unhandled_input(_key(KEY_F))
	check(f.leaving and Session.flight_job.is_empty(), "F unloads and ends the flight")
	var c := Session.active_contract()
	check(bool(c.get("surface", false)) and String(c.get("status", "")) == "arrived", "the run is marked delivered to the surface")
	var r := Session.deliver_active_contract()
	check(bool(r.ok) and String(r.message).contains("landing it on the surface"), "the delivery pays the surface bonus (%s)" % r.message)
	print("DONE fails=", fails)
	quit(1 if fails > 0 else 0)
