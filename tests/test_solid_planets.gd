extends SceneTree
## Worlds are solid (FlightModel.bodies, FlightScene.solid_bodies): flying into the planet beside the
## station stops the ship at its surface, bounces it off and costs hull for the speed of the hit; a gentle
## touch costs nothing; nothing is solid while the planet isn't there (a jump, the moon).
## Run: godot --headless --path . --script res://tests/test_solid_planets.gd
var fails := 0
func check(ok: bool, msg: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + msg)
	if not ok:
		fails += 1
func _initialize() -> void:
	SaveSlots.dir = "user://test_saves_planets_%d" % OS.get_process_id()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SaveSlots.dir))
	process_frame.connect(_run, CONNECT_ONE_SHOT)
func _run() -> void:
	Session.begin_new(2, "Tester", "human", "normal", "roosevelt_independent_yards")
	Session.profile["system_id"] = "sol"
	Session.profile["port_id"] = String(Worlds.primary_port("sol").id)
	Session.save_profile()
	Session.flight_job = {}
	var f: Node = load(Session.FLIGHT_SCENE).instantiate()
	root.add_child(f)
	current_scene = f
	await process_frame
	f.set_process(false)
	var b: Array = f.solid_bodies()
	check(b.size() >= 1 and float(b[0].radius) > 100.0, "the planet beside the station is solid (%s, %.0f m)" % [String(b[0].name) if not b.is_empty() else "none", float(b[0].radius) if not b.is_empty() else 0.0])
	var c: Vector3 = b[0].centre
	var r := float(b[0].radius)
	f.model.station_solid = false
	var dir: Vector3 = (f.model.pos - c).normalized()
	f.model.pos = c + dir * (r + 200.0)
	f.model.vel = -dir * 200.0
	f.model.throttle = 0.0
	f.model.damage = 0.0
	var inside := false
	for i in 60:
		f._process(0.05)
		if (f.model.pos - c).length() < r:
			inside = true
	check(not inside and f.model.vel.dot(dir) > 0.0, "flown into at 200 m/s, it stops at the surface and bounces off")
	check(f.model.damage > 0.5 and f.model.impacts > 0 and f.notice.contains("solid"), "and the hull pays for it (%d%% left): %s" % [roundi(f.model.hull() * 100.0), f.notice])
	f.model.damage = 0.0
	f.model.pos = c + dir * (r + 5.0)
	f.model.vel = -dir * 1.0
	for i in 40:
		f._process(0.05)
	check(f.model.damage == 0.0 and (f.model.pos - c).length() >= r, "a gentle touch: no harm, still outside")
	f.planet.visible = false
	check(f.solid_bodies().is_empty(), "with the planet out of sight (down on a moon), nothing to hit")
	f.planet.visible = true
	print("DONE fails=", fails)
	quit(1 if fails > 0 else 0)
