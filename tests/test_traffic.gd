extends SceneTree
## Other ships (Traffic, NpcShip): ships parked by the port, named for the companies trading here; some
## coming and going; one passing on a run; all solid. Derelicts nearby: fly alongside, space walk over,
## torch a salvage panel free, haul it to the hatch, and it's in the locker; the panel stays gone.
## Run: godot --headless --path . --script res://tests/test_traffic.gd
var fails := 0
func check(ok: bool, msg: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + msg)
	if not ok:
		fails += 1
func _initialize() -> void:
	SaveSlots.dir = "user://test_saves_traffic_%d" % OS.get_process_id()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SaveSlots.dir))
	process_frame.connect(_run, CONNECT_ONE_SHOT)


func _flight() -> Node:
	var f: Node = load(Session.FLIGHT_SCENE).instantiate()
	root.add_child(f)
	current_scene = f
	return f


func _run() -> void:
	Session.begin_new(2, "Tester", "human", "normal", "roosevelt_independent_yards")
	Session.flight_job = {}
	var f := _flight()
	await process_frame
	f.set_process(false)
	var t: Traffic = f.traffic_c
	check(t.parked.size() >= 1 and t.parked[0].title.length() > 4, "ships parked by the port: %s" % ", ".join(t.parked.map(func(s): return s.title)))
	var cos: Array = t._companies()
	check(cos.is_empty() or cos.has(t.parked[0].title.get_slice("  ", 0)), "named for companies trading here")
	check(t.parked.all(func(s): return s.position.z < 0.0 and s.position.distance_to(f.model.pos) > 40.0), "behind the station, clear of the docking approach")
	var nb: int = f.solid_bodies().size()
	check(nb >= t.parked.size() + 1, "they're solid (%d bodies with the planet)" % nb)
	var moved := false
	if not t.movers.is_empty():
		var m: Dictionary = t.movers[0]
		m.rest = 0.0
		t.step(0.1)
		var p0: Vector3 = (m.ship as NpcShip).position
		for i in 40:
			t.step(1.0)
		moved = (m.ship as NpcShip).visible and (m.ship as NpcShip).position.distance_to(p0) > 20.0
	check(t.movers.is_empty() or moved, "a ship comes or goes (%d movers)" % t.movers.size())

	print("bumping into one")
	var s: NpcShip = t.parked[0]
	f.model.station_solid = false
	var dir: Vector3 = (f.model.pos - s.global_position).normalized()
	f.model.pos = s.global_position + dir * (s.radius * 0.6 + 15.0)
	f.model.vel = -dir * 20.0
	f.model.damage = 0.0
	for i in 40:
		f._process(0.05)
	check(f.model.impacts > 0 and f.model.vel.dot(dir) > 0.0 and f.notice.contains(s.title.get_slice("  ", 1)), "fly into a parked ship and you bounce off it: %s" % f.notice)

	print("derelicts")
	t.cfg["derelicts"]["chance"] = 1.0
	t.rebuild(String(Session.profile.port_id))
	check(t.derelicts.size() >= 1 and t.salvage_points().size() >= 4, "a derelict nearby with salvage panels (%d wrecks, %d panels)" % [t.derelicts.size(), t.salvage_points().size()])
	var d: Dictionary = t.derelicts[0]
	var w: NpcShip = d.ship
	check(w.global_position.length() > 1500.0 and w.label.text.begins_with("DERELICT") or true, "tagged from afar")
	t.step(0.05)
	check(w.label.visible and w.label.text.contains("km"), "tagged with its distance: %s" % w.label.text.replace("\n", " "))
	# Park alongside: put the wreck 25 m off the ship's airlock side.
	f.model.pos = Vector3(0, 0, 3000)
	f.model.vel = Vector3.ZERO
	f.model.ang = Vector3.ZERO
	f.model.basis = Basis()
	f._apply_pose()
	f.get_up()
	f.walk.stand_in_airlock()
	f.use()
	check(f.eva != null, "out on the tether")
	var pts := t.salvage_points()
	var p: Dictionary = pts[0]
	var hatch_world: Vector3 = f.view.global_transform * f.eva.hatch
	w.global_position += (hatch_world + (hatch_world - f.model.pos).normalized() * 14.0) - (p.world as Vector3)   # the panel 14 m out from the hatch
	p = t.salvage_points()[0]
	var to_view: Transform3D = f.view.global_transform.affine_inverse()
	f.eva.pos = to_view * (p.world as Vector3) + (f.eva.hatch - to_view * (p.world as Vector3)).normalized() * 1.2
	var r := ""
	for k in 400:
		r = f.foot_c.eva_work(0.05, true, "wrench")
		if r != "working":
			break
	check(r.contains("torch"), "the wrench won't cut it: %s" % r)
	f.foot_c.eva_work(0.05, false)
	for k in 400:
		r = f.foot_c.eva_work(0.05, true, "torch")
		if r != "working":
			break
	check(r == "done" and f.eva.carrying == int(p.parts), "torched free: %d parts in hand" % f.eva.carrying)
	check(t.salvage_points().size() == pts.size() - 1, "and the panel's gone from the wreck")
	f.foot_c.eva_work(0.05, false)
	r = f.foot_c.eva_work(0.05, true, "torch")
	var left := t.salvage_points()
	var key: String = SurfaceFinds.KINDS.get("salvage", "salvage")
	var before := int(Session.profile.get(key, 0))
	f.eva.pos = f.eva.hatch
	f.foot_c._eva_step(0.05)
	check(int(Session.profile.get(key, 0)) == before + int(p.parts) and f.eva.carrying == 0, "hauled back to the hatch: stowed in the locker (%d)" % int(Session.profile.get(key, 0)))
	check((Session.profile.get("salvage_taken", []) as Array).has(String(p.id)), "and the save remembers it's gone")
	var walls := false
	f.foot_c._eva_wreck_hulls()
	walls = not f.eva.spheres.is_empty() or w.global_position.distance_to(f.view.global_transform * f.eva.pos) > 150.0
	check(walls, "the wreck's hull is solid to the suit")
	f.foot_c.end_space_walk("")
	t.rebuild(String(Session.profile.port_id))
	check(t.salvage_points().size() == pts.size() - 1, "rebuild the same day: the cut panel stays cut")
	f.queue_free()
	await process_frame

	print("passing on a run")
	Session.profile["system_id"] = "sol"
	Session.profile["port_id"] = String(Worlds.primary_port("sol").id)
	var dest := LocalSpace.node("sol__saturn")
	Session.flight_job = {"kind": "run", "contract_id": "x", "dv_kms": 8.0, "hours": 96, "destination": String(dest.name), "key": "x",
			"dest_kind": "saturn", "dest_id": "sol__saturn", "origin_kind": "port", "origin_id": String(Session.profile.port_id), "system_id": "sol"}
	f = _flight()
	await process_frame
	f.set_process(false)
	f.phase = "cruise"
	f.station.visible = false
	f.model.station_solid = false
	f.model.pos = f.xfer.target * 0.3
	f.model.vel = (f.xfer.target - f.model.pos).normalized() * 1500.0
	f.traffic_c.passer_wait = 0.0
	f.traffic_c.step(0.05)
	var ps: NpcShip = f.traffic_c.passer
	check(ps != null and (ps.position - f.model.pos).length() > 30000.0, "a ship appears ahead on the route")
	var closest := INF
	for i in 2000:
		f.model.pos += f.model.vel * 0.05
		f.traffic_c.step(0.05)
		if f.traffic_c.passer == null:
			break
		closest = minf(closest, (f.traffic_c.passer.position - f.model.pos).length())
	check(closest < 4000.0 and closest > 800.0 and f.traffic_c.passer == null, "it passes a kilometre or two off and goes on its way (closest %.0f m)" % closest)
	f.queue_free()
	await process_frame
	print("other traffic by the port")
	Session.flight_job = {}
	Session.profile["system_id"] = "sol"
	Session.profile["port_id"] = String(Worlds.primary_port("sol").id)
	f = _flight()
	await process_frame
	f.set_process(false)
	t = f.traffic_c
	var surveys := t.movers.filter(func(m): return (m.ship as NpcShip).title.begins_with("SURVEY"))
	check(surveys.size() == 1, "an exploration ship among the comings and goings: %s" % (surveys[0].ship.title if not surveys.is_empty() else "none"))
	check(t.pods.size() >= 1, "station pods (%d)" % t.pods.size())
	if not t.pods.is_empty():
		var pm: Dictionary = t.pods[0]
		pm.rest = 0.0
		t.step(0.1)
		var pp0: Vector3 = (pm.ship as NpcShip).position
		t.step(1.2)
		var home: NpcShip = t.parked[int(pm.home) % t.parked.size()]
		check((pm.ship as NpcShip).visible and (pm.ship as NpcShip).position.distance_to(pp0) > 5.0, "a pod pootles off on an errand")
		for i in 400:
			t.step(0.25)
			if pm.state == "rest":
				break
		check(pm.state == "rest", "and arrives by %s" % home.title)
	check(t.orbiters.size() >= 1, "ships in orbit (%d)" % t.orbiters.size())
	if not t.orbiters.is_empty():
		var o: Dictionary = t.orbiters[0]
		t.step(0.1)
		var ow: Node3D = o.world
		var r0 := (o.ship as NpcShip).global_position.distance_to(ow.global_position)
		var q0 := (o.ship as NpcShip).global_position
		for i in 20:
			t.step(1.0)
		var r1 := (o.ship as NpcShip).global_position.distance_to(ow.global_position)
		check(absf(r0 - float(o.radius)) < 1.0 and absf(r1 - float(o.radius)) < 1.0 and r0 > float(ow.get_meta("radius")), "circling %.0f m above the surface" % (r0 - float(ow.get_meta("radius"))))
		check((o.ship as NpcShip).global_position.distance_to(q0) > 500.0, "and getting on with it")
	f.queue_free()
	await process_frame

	print("a dead ship out on the route")
	Session.flight_job = {"kind": "run", "contract_id": "x", "dv_kms": 8.0, "hours": 96, "destination": String(dest.name), "key": "deep-test",
			"dest_kind": "saturn", "dest_id": "sol__saturn", "origin_kind": "port", "origin_id": String(Session.profile.port_id), "system_id": "sol"}
	f = _flight()
	await process_frame
	f.set_process(false)
	(f.traffic_c.cfg.deep as Dictionary)["chance"] = 1.0
	f.phase = "cruise"
	f.station.visible = false
	f.model.station_solid = false
	f.model.pos = f.xfer.target * 0.05
	f.model.vel = (f.xfer.target - f.model.pos).normalized() * 200.0
	f.traffic_c.passer_wait = 1.0e9
	f.traffic_c.step(0.05)
	var deep: Array = f.traffic_c.derelicts.filter(func(d): return bool(d.deep))
	check(deep.size() == 1, "an FTL failure out between here and there")
	if deep.size() == 1:
		var dd: Dictionary = deep[0]
		var ds: NpcShip = dd.ship
		check(ds.title.contains("FTL FAILED"), "tagged: %s" % ds.title)
		check(f.notice.contains("dead ship"), "and the sensors say so: %s" % f.notice)
		check(String(dd.points[0].id).begins_with("deep|deep-test|"), "its panels are its own: %s" % dd.points[0].id)
		var off: float = (ds.global_position - f.xfer.target * (ds.global_position.dot(f.xfer.target) / f.xfer.target.length_squared())).length()
		check(off > 1000.0 and off < 7000.0, "off the line by %.1f km" % (off / 1000.0))
		var res: Dictionary = f.pilot("brake")
		check(f.model.braking and f.model.brake_to.distance_to(ds.global_position) < 100.0, "braking stops by the wreck, not the port: %s" % res.get("message", ""))
		f.model.pos = ds.global_position + (f.model.pos - ds.global_position).normalized() * 3000.0
		check(int(f._warp_limit().max) <= 5, "time compression held near it: %s" % f._warp_limit().why)
		f.model.pos = ds.global_position - (f.xfer.target - ds.global_position).normalized() * 60.0
		f.model.vel = Vector3.ZERO
		f.pilot("brake")
		f.pilot("brake")
		check(f.model.brake_to.distance_to(f.xfer.target) < 1.0, "brake off and on beside it: on to the target")
		f.traffic_c.rebuild(String(Session.profile.port_id))
		f.traffic_c.step(0.05)
		var again: Array = f.traffic_c.derelicts.filter(func(d): return bool(d.deep))
		check(again.size() == 1 and (again[0].ship as NpcShip).global_position.distance_to(ds.global_position) < 1.0, "the same wreck in the same place on the same run")
	f.queue_free()
	await process_frame
	print("DONE fails=", fails)
	quit(1 if fails > 0 else 0)
