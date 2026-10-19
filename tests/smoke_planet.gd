extends SceneTree
## A planet with air in the flight scene: a run from New Houston's orbital terminal down to its surface
## port on Roosevelt arrives at the top of the air; the autopilot (T) brings it down belly first onto the
## pad; outside the air is breathable; F unloads and the delivery pays. Back up: a run from the downport
## lifts off on the jets and burns for orbit, unless the tanks can't cover the climb. The downport's
## terminal and the field's shed are places to walk. Mars's air you can't breathe.
## Run: godot --headless --path . --script res://tests/smoke_planet.gd
var fails := 0


func check(ok: bool, msg: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + msg)
	if not ok:
		fails += 1


func _initialize() -> void:
	SaveSlots.dir = "user://test_saves_planet_%d" % OS.get_process_id()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SaveSlots.dir))
	process_frame.connect(_run, CONNECT_ONE_SHOT)


func _key(code: int) -> InputEventKey:
	var k := InputEventKey.new()
	k.keycode = code
	k.pressed = true
	return k


func _ship(preset: Array) -> void:
	var data := SaveSlots.read(2)
	var ship := ShipData.new(ModuleLibrary.new())
	ShipPresets.build(ship, preset)
	data["modules"] = (JSON.parse_string(ship.to_json()) as Dictionary)["modules"]
	data["cargo"] = CargoManifest.new(ship).to_dict()
	SaveSlots.write(2, data)
	SimWorld.sync(Session.sim, Session.profile, ship)


func _job(dest_kind: String) -> Dictionary:
	for tries in 12:
		for o in Contracts.offers_from(Session.system_id()):
			if bool(o.get("local", false)) and String(LocalSpace.node(String(o.destination_port_id)).get("kind", "")) == dest_kind and String(o.get("person_kind", "")) == "":
				return o
		Session.sim.run_hours(48)
	return {}


func _flight() -> Node:
	var f: Node = load(Session.FLIGHT_SCENE).instantiate()
	root.add_child(f)
	return f


func _run() -> void:
	Hazards.off = true
	Session.begin_new(2, "Pilot", "human", "normal", "roosevelt_independent_yards")
	Session.profile["hints_seen"] = ["welcome", "money", "crew", "holding", "arrived", "hab", "hut", "trade", "flight"]
	_ship(ShipPresets.STARTER_PLANET)
	print("down")
	var job := _job("world")
	check(not job.is_empty() and bool(job.get("planet", false)), "a planet run down to the surface is posted for a ship with heavy legs")
	check(bool(Session.accept_contract(job).ok) and bool(Session.begin_local_flight().ok), "accepted, loaded and the helm taken")
	var f := _flight()
	await process_frame
	f.phase = "cruise"
	f.model.station_solid = false
	f.model.pos = f.xfer.target
	f.model.vel = Vector3.ZERO
	await process_frame
	await process_frame
	check(f.phase == "entry" and f.world != null and f.model.altitude() > 30000.0 and not f.model.air.is_empty(), "arriving brings the top of the air (%.0f km up)" % (f.model.altitude() / 1000.0))
	check(f.hud.text.contains("ENTRY HEAT") and f.hud.text.contains("BELLY TO THE AIR"), "the entry readout: heat and how square the belly is")
	f._unhandled_input(_key(KEY_T))
	check(f.model.autoentry, "T hands the entry to the autopilot")
	var t := 0.0
	var saw_heat := 0.0
	var saw_descent := false
	while t < 900.0 and not f.model.landed:
		f._process(0.05)
		t += 0.05
		saw_heat = maxf(saw_heat, f.model.skin_heat)
		saw_descent = saw_descent or f.phase == "descent"
		if int(t * 20.0) % 400 == 0:
			await process_frame
	check(saw_descent, "low and slow, the entry becomes the landing")
	check(f.model.landed and f.model.on_pad() and f.model.damage < 0.01, "down on the downport's pad, unhurt (%.0f s)" % t)
	check(saw_heat > 0.3 and saw_heat < 1.0, "it ran warm on the way down, not over the limit (%d%%)" % roundi(saw_heat * 100.0))
	f.get_up()
	check(f.go_outside() and f.ops != null and f.ops.open_air, "out through the airlock into air you can breathe")
	var o2 := float(f.ops.o2)
	for i in 100:
		f._suit_step(0.05)
	check(is_equal_approx(float(f.ops.o2), o2) and f.ops.hud_lines()[0].contains("visor up"), "no tank to run down outside")
	f.suit.place(f.suit_hatch)
	check(f.come_aboard(), "back aboard")
	f.walk.stand_at_helm()
	f.sit_down()
	f._unhandled_input(_key(KEY_F))
	check(f.leaving and String(Session.profile.port_id) == "new_houston__world", "F unloads: the ship is at New Houston Surface Port")
	var r := Session.deliver_active_contract()
	check(bool(r.ok), "delivered: %s" % String(r.message))
	f.queue_free()
	await process_frame

	print("the downport")
	var place: Node = load(Session.PLACE_SCENE).instantiate()
	root.add_child(place)
	await process_frame
	check(place.kind == "concourse" and place.get_node_or_null("Outside") != null, "the downport's terminal, with the planet out of its window")
	check(place.info.text.contains("Downport terminal") if place.get("info") != null else true, "it says where you are")
	place.queue_free()
	await process_frame

	print("up")
	var up_job := _job("port")
	check(not up_job.is_empty(), "a run up to the orbital terminal is posted at the downport")
	check(float(up_job.dv_kms) > float(LocalSpace.hop("port", "world", "new_houston").dv_kms) * 2.0, "and the climb costs far more delta-v than the way down")
	check(bool(Session.accept_contract(up_job).ok) and bool(Session.begin_local_flight().ok), "accepted and the helm taken")
	f = _flight()
	await process_frame
	check(f.phase == "ascent" and f.model.landed and f.world != null, "sitting on the pad, ready to lift off")
	f._unhandled_input(_key(KEY_T))
	check(f.auto_ascent, "T: lift off on auto")
	var fuel_before := float(f.model.fuel_t)
	t = 0.0
	var clear_m := float(Planets.config().surface.ascent_clear_m)
	var need := 0.0
	while t < 400.0 and f.phase == "ascent":
		if f.model.altitude() > clear_m - 30.0 and need == 0.0:
			need = LocalSpace.burn_t(f.model.mass_t(), Planets.up_dv("new_houston", "world"))
		f._process(0.05)
		t += 0.05
		if int(t * 20.0) % 400 == 0:
			await process_frame
	check(f.phase == "approach" or f.phase == "cruise", "clear of the air, the main engine takes her up to orbit (%s)" % f.phase)
	check(fuel_before - f.model.fuel_t > need * 0.9, "the climb's fuel is burned (%.1f t)" % (fuel_before - f.model.fuel_t))
	check(f.world == null and f.model.air.is_empty() and f.model.gravity == 0.0, "the planet, its air and its gravity are left behind")
	f.queue_free()
	await process_frame
	# Not enough in the tanks for the climb.
	f = _flight()
	await process_frame
	f.model.fuel_t = 1.0
	f._unhandled_input(_key(KEY_T))
	t = 0.0
	while t < 200.0 and f.model.altitude() < clear_m + 50.0 and f.model.has_fuel():
		f._process(0.05)
		t += 0.05
	f.model.pos.y = f.model.terrain.height(f.model.pos.x, f.model.pos.z) + clear_m + 40.0
	f._process(0.05)
	check(f.phase == "ascent" and f.notice.contains("Not enough in the tanks"), "with the tanks nearly dry it won't try for orbit: %s" % f.notice)
	f.queue_free()
	await process_frame

	print("Mars")
	Session.profile["species"] = "human"
	check(not Planets.breathable("sol", "mars", "human") and Planets.breathable("keshar", "world", "kesh"), "nobody breathes Mars; the Kesh breathe Keshar")
	print("DONE fails=", fails)
	quit(1 if fails > 0 else 0)
