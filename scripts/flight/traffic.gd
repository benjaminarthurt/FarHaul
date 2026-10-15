class_name Traffic
extends RefCounted
## Other ships, so known space isn't just you (data/runtime/traffic.json):
## - parked: ships holding station near the port, behind it, away from the docking approach. As many as
##   the economy has carriers in this system, up to a cap, named for their companies.
## - movers: a ship or two coming and going from the station, out to a few kilometres and back.
## - passers: on a run, now and then a ship coming the other way along the route.
## - derelicts: dead ships drifting a few kilometres from a station, different each day. Fly alongside,
##   go out on the tether and cut salvage panels off with the torch (OnFoot, SALVAGE), then haul them
##   back to the hatch. Each panel can be taken once (profile.salvage_taken).
## - pods: station pods ferrying between the station and the parked ships.
## - survey craft: other people's exploration ships, coming and going with the movers.
## - orbiters: tugs, patrols and tenders circling the planet and its neighbour.
## - deep derelicts: on a run, sometimes a dead ship out along the route, one whose FTL failed partway:
##   braking with X stops you at it when it's ahead and nearer than the destination (brake_target()).
## Everything sits in the flight scene's frame; the ships are solid (bodies()).

const PATH := "res://data/runtime/traffic.json"
const LAYOUTS := [ShipPresets.STARTER, ShipPresets.STARTER_FTL, ShipPresets.STARTER_CABIN, ShipPresets.NPC_HAULER, ShipPresets.STARTER_LANDER]

var sc: FlightScene
var cfg := {}
var root: Node3D
var parked: Array[NpcShip] = []
var movers: Array = []        ## {ship, state: rest|out|in, t, dur, a, b, rest}
var passer: NpcShip = null
var passer_vel := Vector3.ZERO
var passer_wait := 0.0
var derelicts: Array = []     ## {ship, name, deep, points: [{id, pos (body frame), normal, parts, taken, marker}]}
var pods: Array = []          ## {ship, state, t, dur, a, b, rest, home}
var orbiters: Array = []      ## {ship, world: Node3D it circles, radius, speed, angle, tilt: Basis}
var deep_key := ""            ## the run the deep derelict (if any) was placed for
var stops: Array = []         ## other things out on the route the braking autopilot stops at (a ship in distress: Comms)
var _announce := ""           ## the sensors' line about it, said once the cockpit isn't saying something else
var site := ""
var rng := RandomNumberGenerator.new()


static func config() -> Dictionary:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	return parsed if typeof(parsed) == TYPE_DICTIONARY else {}


func _init(scene: FlightScene) -> void:
	sc = scene
	cfg = config()


func _range(key: String, fallback: Array, r: RandomNumberGenerator = rng) -> float:
	var v: Array = cfg.get(key, fallback)
	return r.randf_range(float(v[0]), float(v[1]))


## Company names of the economy's carriers in this system (who's around), most first.
func _companies() -> Array:
	var out := []
	if Session.sim == null:
		return out
	var sys := Session.system_id()
	for c in Session.sim.carriers.values():
		if String(c.get("sys", "")) == sys and not bool(c.get("manual", false)):
			out.append(String(c.get("company", "")).replace("_", " ").to_upper())
	return out


func _ship_name(r: RandomNumberGenerator) -> String:
	var names: Array = cfg.get("names", ["Unnamed"])
	return String(names[r.randi() % names.size()])


func clear() -> void:
	if root != null:
		root.queue_free()
	root = null
	parked.clear()
	movers.clear()
	derelicts.clear()
	stops.clear()
	pods.clear()
	orbiters.clear()
	deep_key = ""
	_announce = ""
	passer = null


## Everything for the station at `port_id` (start of a flight, a run's destination, a jump's arrival).
func rebuild(port_id: String) -> void:
	clear()
	site = port_id
	root = Node3D.new()
	root.name = "Traffic"
	sc.add_child(root)
	if LocalSpace.is_surface(port_id):
		return
	rng.seed = hash("%s|%d|traffic" % [port_id, Session.day()])
	var companies := _companies()
	var busy: bool = String(LocalSpace.node(port_id).get("kind", "port")) == "port"   # out-sites are quieter
	var n := clampi(companies.size() + 1, 2, int(cfg.get("parked_max", 4))) if busy else 1
	for k in n:
		var co: String = companies[k % companies.size()] if not companies.is_empty() else "INDEPENDENT"
		var s := NpcShip.make(LAYOUTS[rng.randi() % LAYOUTS.size()], "%s  %s" % [co, _ship_name(rng)])
		var a := -PI * 0.75 + rng.randf() * PI * 1.5 + PI * 0.5   # round the back and sides, clear of the approach
		var r := _range("parked_ring_m", [75.0, 120.0])
		s.position = Vector3(cos(a) * r, sin(a) * r * 0.5, -25.0 - rng.randf() * 50.0)
		s.rotation.y = rng.randf_range(-0.4, 0.4)
		root.add_child(s)
		parked.append(s)
	for k in (int(cfg.get("movers_max", 2)) if busy else 1):
		var co: String = companies[(k + n) % companies.size()] if not companies.is_empty() else "INDEPENDENT"
		var s := NpcShip.make(LAYOUTS[rng.randi() % LAYOUTS.size()], "%s  %s" % [co, _ship_name(rng)])
		s.visible = false
		root.add_child(s)
		movers.append({"ship": s, "state": "rest", "t": 0.0, "rest": rng.randf_range(2.0, 25.0), "out": k % 2 == 0})
	if busy:   # someone else's exploration ship, coming or going
		var sv: Dictionary = cfg.get("survey", {})
		var sn: Array = sv.get("names", ["Far Look"])
		var s := NpcShip.make(ShipPresets.NPC_SURVEYOR, "%s  %s" % [String(sv.get("label", "SURVEY")), String(sn[rng.randi() % sn.size()])])
		s.visible = false
		root.add_child(s)
		movers.append({"ship": s, "state": "rest", "t": 0.0, "rest": rng.randf_range(10.0, 60.0), "out": rng.randf() < 0.5})
	var pc: Dictionary = cfg.get("pods", {})
	for k in (int(pc.get("count", 2)) if busy and not parked.is_empty() else 0):
		var s := NpcShip.make(ShipPresets.NPC_POD, "%s  %d" % [String(pc.get("label", "POD")), rng.randi_range(2, 39)])
		s.visible = false
		root.add_child(s)
		pods.append({"ship": s, "state": "rest", "t": 0.0, "rest": rng.randf_range(1.0, 12.0), "home": k % parked.size(), "out": true})
	_build_orbiters()
	_build_derelicts(port_id)


## Ships working round the planet (and its small neighbour): in circular orbits a few hundred metres up.
func _build_orbiters() -> void:
	var oc: Dictionary = cfg.get("orbiters", {})
	if sc.planet == null or not sc.planet.has_meta("radius"):
		return
	var worlds: Array = [sc.planet]
	for c in sc.planet.get_children():
		if c is Node3D and (c as Node3D).has_meta("radius"):
			worlds.append(c)
	var roles: Array = oc.get("roles", ["TENDER"])
	for k in int(oc.get("count", 3)):
		var w: Node3D = worlds[0] if k < int(oc.get("count", 3)) - 1 or worlds.size() < 2 else worlds[1]
		var alt: Array = oc.get("altitude_m", [250.0, 900.0])
		var spd: Array = oc.get("speed_m_s", [60.0, 160.0])
		var layout: Array = [ShipPresets.NPC_POD, ShipPresets.NPC_SURVEYOR, ShipPresets.STARTER][k % 3]
		var s := NpcShip.make(layout, "%s  %s" % [String(roles[rng.randi() % roles.size()]), _ship_name(rng)])
		root.add_child(s)
		var tilt := Basis(Vector3.RIGHT, rng.randf_range(-0.5, 0.5)) * Basis(Vector3.FORWARD, rng.randf_range(-0.4, 0.4))
		orbiters.append({"ship": s, "world": w, "radius": float(w.get_meta("radius")) + rng.randf_range(float(alt[0]), float(alt[1])),
				"speed": rng.randf_range(float(spd[0]), float(spd[1])), "angle": rng.randf() * TAU, "tilt": tilt})


func _build_derelicts(port_id: String) -> void:
	var dc: Dictionary = cfg.get("derelicts", {})
	var r := RandomNumberGenerator.new()
	r.seed = hash("%s|%d|wrecks" % [port_id, Session.day()])
	var taken: Array = Session.profile.get("salvage_taken", []) if Session.slot >= 0 else []
	for w in int(dc.get("max", 2)):
		if r.randf() > float(dc.get("chance", 0.75)) / float(w + 1):
			continue
		var names: Array = dc.get("names", ["a wreck"])
		var nm := String(names[r.randi() % names.size()])
		var dist: Array = dc.get("distance_m", [1800.0, 5200.0])
		var dir := Vector3(r.randf_range(-1, 1), r.randf_range(-0.3, 0.3), r.randf_range(-1, 1)).normalized()
		var at := dir * r.randf_range(float(dist[0]), float(dist[1]))
		if sc.planet != null and sc.planet.has_meta("radius"):   # not inside the planet
			var pc := sc.planet.position
			var pr := float(sc.planet.get_meta("radius")) + 400.0
			if at.distance_to(pc) < pr:
				at = pc + (at - pc).normalized() * pr if (at - pc).length() > 1.0 else -at
		_add_derelict(LAYOUTS[r.randi() % LAYOUTS.size()], nm, "DERELICT", at, "%s|%d|%d" % [port_id, Session.day(), w], r, taken, false)


## One dead ship at `at` with its salvage panels; panel ids are `id_base`|k.
func _add_derelict(layout: Array, nm: String, tag: String, at: Vector3, id_base: String, r: RandomNumberGenerator, taken: Array, deep: bool) -> Dictionary:
	var dc: Dictionary = cfg.get("derelicts", {})
	var s := NpcShip.make(layout, "%s  %s" % [tag, nm.trim_prefix("the ").trim_prefix("an ").trim_prefix("a ").to_upper()], true)
	s.position = at
	s.rotation = Vector3(r.randf_range(-0.5, 0.5), r.randf() * TAU, r.randf_range(-0.6, 0.6))
	root.add_child(s)
	var sites := ShipDamage.skin_sites(s.ship)
	var pts: Array = dc.get("points", [4, 7])
	var ppp: Array = dc.get("parts_per_point", [2, 5])
	var points := []
	var usable := range(mini(ShipDamage.MAX_SCORCH, sites.size()), maxi(0, sites.size() - 3))   # clear of the scorch marks and the venting plates
	if usable.size() < int(pts[0]):
		usable = range(0, maxi(0, sites.size() - 3))
	for k in mini(usable.size(), r.randi_range(int(pts[0]), int(pts[1]))):
		var site_k: Dictionary = sites[usable[k]]
		var id := "%s|%d" % [id_base, k]
		var p := {"id": id, "kind": "panel", "pos": site_k.pos, "normal": site_k.normal, "parts": r.randi_range(int(ppp[0]), int(ppp[1])), "taken": id in taken}
		p["marker"] = _marker(s, site_k.pos, site_k.normal)
		(p.marker as Node3D).visible = not bool(p.taken)
		points.append(p)
	# The cargo hatch: torch it open and the hold's contents drift out to be hauled home (Salvage).
	var hk: int = usable[mini(usable.size() - 1, points.size())] if not usable.is_empty() else 0
	if not sites.is_empty():
		var hs: Dictionary = sites[hk]
		var hid := "%s|h" % id_base
		var hatch := {"id": hid, "kind": "hatch", "pos": hs.pos, "normal": hs.normal, "parts": 0, "taken": hid in taken}
		hatch["marker"] = _hatch_marker(s, hs.pos, hs.normal)
		hatch["open_mark"] = _hatch_hole(s, hs.pos, hs.normal)
		(hatch.marker as Node3D).visible = not bool(hatch.taken)
		(hatch.open_mark as Node3D).visible = bool(hatch.taken)
		points.append(hatch)
		var items := Salvage.roll(layout, r, deep)
		var face := ShipDamage._facing(hs.normal)
		for k in items.size():
			var iid := "%s|h|%d" % [id_base, k]
			var side := face * Vector3((k % 3 - 1) * 1.6, 0.0, ((k / 3) % 2) * 1.4 - 0.7)
			var at_k: Vector3 = (hs.pos as Vector3) + (hs.normal as Vector3) * (2.2 + 1.1 * (k % 2)) + side
			var it := {"id": iid, "kind": "item", "item": items[k], "pos": at_k, "normal": hs.normal, "parts": 0, "taken": iid in taken, "hatch": hatch}
			it["marker"] = _item_marker(s, at_k, items[k], r)
			(it.marker as Node3D).visible = bool(hatch.taken) and not bool(it.taken)
			points.append(it)
	# The airlock's outer door: torch it open and you can go aboard (Boarding).
	var wk := ShipWalk.build(s.ship)
	if wk.airlock != Vector3.INF:
		var out := -wk.airlock_face
		var dpos := wk.airlock + Vector3(0, 1.1, 0) + out * (ShipGrid.CELL * 0.5 + ShipSkin.GAP + ShipSkin.T)
		var did := "%s|door" % id_base
		var door := {"id": did, "kind": "door", "pos": dpos, "normal": out, "parts": 0, "taken": did in taken}
		door["marker"] = _door_marker(s, dpos, out, false)
		door["open_mark"] = _door_marker(s, dpos, out, true)
		(door.marker as Node3D).visible = not bool(door.taken)
		(door.open_mark as Node3D).visible = bool(door.taken)
		points.append(door)
	var d := {"ship": s, "name": nm, "points": points, "deep": deep, "id_base": id_base}
	derelicts.append(d)
	return d


## On a run: sometimes a ship that dropped out of a failed jump, dead, out along the route.
func _deep_derelict() -> void:
	var key := String(sc.job.get("key", ""))
	if key == "" or key == deep_key or sc.xfer == null:
		return
	deep_key = key
	var dest := String(sc.job.get("dest_id", ""))
	if String(sc.job.get("dest_kind", "")) == "moon" or LocalSpace.is_surface(dest):
		return   # a run down to the ground: the dead stay out in the deep
	var dp: Dictionary = cfg.get("deep", {})
	var r := RandomNumberGenerator.new()
	r.seed = hash("deep|" + key)
	if r.randf() > float(dp.get("chance", 0.55)):
		return
	var along: Array = dp.get("along", [0.3, 0.7])
	var side_m: Array = dp.get("side_m", [1500.0, 6000.0])
	var route := sc.xfer.target.normalized()
	var side := route.cross(Vector3.UP)
	side = (side if side.length() > 0.1 else route.cross(Vector3.RIGHT)).normalized().rotated(route, r.randf() * TAU)
	var at := sc.xfer.target * r.randf_range(float(along[0]), float(along[1])) + side * r.randf_range(float(side_m[0]), float(side_m[1]))
	var names: Array = dp.get("names", ["a ship"])
	var taken: Array = Session.profile.get("salvage_taken", []) if Session.slot >= 0 else []
	var d := _add_derelict([ShipPresets.STARTER_FTL, ShipPresets.NPC_HAULER, ShipPresets.NPC_SURVEYOR][r.randi() % 3], String(names[r.randi() % names.size()]),
			"DERELICT · FTL FAILED", at, "deep|%s" % key, r, taken, true)
	(d.ship as NpcShip).label.modulate = Color(1.0, 0.5, 0.3)
	_announce = "Sensors: a dead ship out on the route, %s. No transponder, no drive signature. Brake (X) to stop by it." % String(d.name)


## Metres to the nearest dead ship out on a route, INF if none.
func deep_range(pos: Vector3) -> float:
	var best := INF
	for d in derelicts:
		if bool(d.deep):
			best = minf(best, (d.ship as NpcShip).global_position.distance_to(pos))
	for s in stops:
		if is_instance_valid(s):
			best = minf(best, (s as Node3D).global_position.distance_to(pos))
	return best


## Where the braking autopilot should stop: at a derelict out on the route when it's ahead of you and
## nearer than `fallback` (the destination), a little short of it; otherwise `fallback`.
func brake_target(fallback: Vector3) -> Vector3:
	var best := fallback
	var best_d := sc.model.pos.distance_to(fallback)
	var stop := float((cfg.get("deep", {}) as Dictionary).get("stop_m", 60.0))
	var all: Array = derelicts.map(func(d): return d.ship) + stops.filter(func(s): return is_instance_valid(s))
	for n in all:
		var p: Vector3 = (n as Node3D).global_position
		var to := p - sc.model.pos
		if to.length() < stop * 2.0 or to.length() >= best_d:
			continue
		if sc.model.vel.length() > 1.0 and sc.model.vel.normalized().dot(to.normalized()) < 0.5:
			continue   # not ahead
		best = p - to.normalized() * stop
		best_d = to.length()
	return best


## A salvageable panel: an orange frame of cut lines on the hull, glowing faintly so you can find it.
func _marker(s: NpcShip, pos: Vector3, normal: Vector3) -> Node3D:
	var m := Node3D.new()
	m.position = pos + normal * 0.04
	m.basis = ShipDamage._facing(normal)
	var mat := Interiors.glow(Color(1.0, 0.55, 0.15), 0.5)
	for e in [[Vector3(0, 0, 0.6), Vector3(1.3, 0.03, 0.06)], [Vector3(0, 0, -0.6), Vector3(1.3, 0.03, 0.06)],
			[Vector3(0.62, 0, 0), Vector3(0.06, 0.03, 1.2)], [Vector3(-0.62, 0, 0), Vector3(0.06, 0.03, 1.2)]]:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = e[1]
		bm.material = mat
		mi.mesh = bm
		mi.position = e[0]
		m.add_child(mi)
	s.body.add_child(m)
	return m


## Every salvage point still there: [{id, kind (panel, hatch, item), world (position), parts, item, point}].
## A hold's items only once its hatch is open.
func salvage_points() -> Array:
	var out := []
	for d in derelicts:
		var s: NpcShip = d.ship
		if not s.is_inside_tree():
			continue
		for k in (d.points as Array).size():
			var p: Dictionary = d.points[k]
			var kind := String(p.get("kind", "panel"))
			if kind == "door" and bool(p.taken):
				kind = "enter"   # cut open: the way in
			elif bool(p.taken) or (p.has("hatch") and not bool(p.hatch.taken)):
				continue
			var world: Vector3 = s.body.global_transform * (p.pos as Vector3)
			if p.has("marker") and is_instance_valid(p.marker) and String(p.get("kind", "")) == "item":
				world = (p.marker as Node3D).global_position   # drifting a little
			out.append({"id": String(p.id), "kind": kind, "world": world, "parts": int(p.parts), "item": p.get("item", {}), "point": p, "derelict": d})
	return out


## Mark a point cut free (a panel), cut open (a hatch: the hold's items come into view) or taken (an item).
func take(point: Dictionary) -> void:
	point["taken"] = true
	if point.has("marker") and is_instance_valid(point.marker):
		(point.marker as Node3D).visible = false
	if String(point.get("kind", "")) == "door":
		if point.has("open_mark") and is_instance_valid(point.open_mark):
			(point.open_mark as Node3D).visible = true
		return
	if String(point.get("kind", "")) != "hatch":
		return
	if point.has("open_mark") and is_instance_valid(point.open_mark):
		(point.open_mark as Node3D).visible = true
	for d in derelicts:
		for p in d.points:
			if p.has("hatch") and p.hatch == point and not bool(p.taken) and is_instance_valid(p.marker):
				(p.marker as Node3D).visible = true


## The cargo hatch, sealed: a broad yellow frame with a bar across, so it reads as a door, not a panel.
func _hatch_marker(s: NpcShip, pos: Vector3, normal: Vector3) -> Node3D:
	var m := Node3D.new()
	m.position = pos + normal * 0.05
	m.basis = ShipDamage._facing(normal)
	var mat := Interiors.glow(Color(1.0, 0.85, 0.3), 0.6)
	for e in [[Vector3(0, 0, 0.8), Vector3(2.0, 0.04, 0.08)], [Vector3(0, 0, -0.8), Vector3(2.0, 0.04, 0.08)],
			[Vector3(0.96, 0, 0), Vector3(0.08, 0.04, 1.6)], [Vector3(-0.96, 0, 0), Vector3(0.08, 0.04, 1.6)],
			[Vector3(0, 0, 0), Vector3(1.9, 0.04, 0.06)]]:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = e[1]
		bm.material = mat
		mi.mesh = bm
		mi.position = e[0]
		m.add_child(mi)
	s.body.add_child(m)
	return m


## A derelict's airlock door, standing upright on the hull: sealed, a white frame with amber corner
## marks; cut open, a dark doorway with a glowing rim.
func _door_marker(s: NpcShip, pos: Vector3, normal: Vector3, open: bool) -> Node3D:
	var m := Node3D.new()
	m.position = pos + normal * 0.04
	m.basis = ShipDamage._facing(normal)   # local x runs up the hull, z across it
	if open:
		var hole := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(2.0, 0.03, 1.2)
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.02, 0.02, 0.025)
		mat.roughness = 1.0
		bm.material = mat
		hole.mesh = bm
		m.add_child(hole)
		var rim := MeshInstance3D.new()
		var rm := BoxMesh.new()
		rm.size = Vector3(2.16, 0.02, 1.36)
		rm.material = Interiors.glow(Color(0.9, 0.35, 0.1), 0.25)
		rim.mesh = rm
		rim.position = Vector3(0, -0.01, 0)
		m.add_child(rim)
	else:
		var mat := Interiors.glow(Color(0.9, 0.92, 0.95), 0.5)
		for e in [[Vector3(1.0, 0, 0), Vector3(0.08, 0.04, 1.2)], [Vector3(-1.0, 0, 0), Vector3(0.08, 0.04, 1.2)],
				[Vector3(0, 0, 0.6), Vector3(2.0, 0.04, 0.08)], [Vector3(0, 0, -0.6), Vector3(2.0, 0.04, 0.08)]]:
			var mi := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = e[1]
			bm.material = mat
			mi.mesh = bm
			mi.position = e[0]
			m.add_child(mi)
		var amber := Interiors.glow(Color(1.0, 0.7, 0.2), 0.6)
		for c in [Vector3(0.9, 0, 0.5), Vector3(0.9, 0, -0.5), Vector3(-0.9, 0, 0.5), Vector3(-0.9, 0, -0.5)]:
			var mi := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3(0.22, 0.05, 0.22)
			bm.material = amber
			mi.mesh = bm
			mi.position = c
			m.add_child(mi)
	s.body.add_child(m)
	return m


## The hatch once it's been cut away: a dark hole with a scorched rim.
func _hatch_hole(s: NpcShip, pos: Vector3, normal: Vector3) -> Node3D:
	var m := Node3D.new()
	m.position = pos + normal * 0.03
	m.basis = ShipDamage._facing(normal)
	var hole := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(1.85, 0.03, 1.5)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.02, 0.02, 0.025)
	mat.roughness = 1.0
	bm.material = mat
	hole.mesh = bm
	m.add_child(hole)
	var rim := MeshInstance3D.new()
	var rm := BoxMesh.new()
	rm.size = Vector3(2.05, 0.02, 1.7)
	rm.material = Interiors.glow(Color(0.9, 0.35, 0.1), 0.25)
	rim.mesh = rm
	rim.position = Vector3(0, -0.01, 0)
	m.add_child(rim)
	s.body.add_child(m)
	return m


## Something out of the hold, drifting by the hatch: a crate in its goods' colour, a green supplies case,
## or a grey machine part with a hazard band. A faint glow so it can be found in shadow.
func _item_marker(s: NpcShip, pos: Vector3, item: Dictionary, r: RandomNumberGenerator) -> Node3D:
	var m := Node3D.new()
	m.position = pos
	m.rotation = Vector3(r.randf_range(-0.6, 0.6), r.randf() * TAU, r.randf_range(-0.6, 0.6))
	var mi := MeshInstance3D.new()
	var mat := StandardMaterial3D.new()
	mat.roughness = 0.7
	match String(item.get("kind", "")):
		"crate":
			var bm := BoxMesh.new()
			bm.size = Vector3(1.3, 0.9, 0.9)
			mi.mesh = bm
			mat.albedo_color = Salvage.clib().color(StringName(String(item.commodity))).darkened(0.1)
		"supplies":
			var bm := BoxMesh.new()
			bm.size = Vector3(0.8, 0.5, 0.5)
			mi.mesh = bm
			mat.albedo_color = Color(0.3, 0.6, 0.35)
		_:
			var cm := CylinderMesh.new()
			cm.top_radius = 0.45
			cm.bottom_radius = 0.55
			cm.height = 1.3
			mi.mesh = cm
			mat.albedo_color = Color(0.5, 0.52, 0.56)
			mat.metallic = 0.6
	mat.emission_enabled = true
	mat.emission = mat.albedo_color
	mat.emission_energy_multiplier = 0.15
	mi.material_override = mat
	m.add_child(mi)
	var band := MeshInstance3D.new()
	var bb := BoxMesh.new()
	bb.size = Vector3(0.12, 1.0, 1.0) if String(item.get("kind", "")) != "part" else Vector3(1.15, 0.14, 1.15)
	bb.material = Interiors.glow(Color(1.0, 0.75, 0.2), 0.35)
	band.mesh = bb
	m.add_child(band)
	m.set_meta("spin", Vector3(r.randf_range(-0.15, 0.15), r.randf_range(-0.2, 0.2), r.randf_range(-0.1, 0.1)))
	m.set_meta("home", pos)
	m.set_meta("phase", r.randf() * TAU)
	s.body.add_child(m)
	return m


## The wrecks' hulls near `world`, as spheres in the world frame: {centre, radius} per compartment.
func wreck_spheres(world: Vector3, within := 120.0) -> Array:
	var out := []
	for d in derelicts:
		var s: NpcShip = d.ship
		if not s.is_inside_tree() or s.global_position.distance_to(world) > within + s.radius:
			continue
		for c in ShipSkin.pressurised_cells(s.ship):
			out.append({"centre": s.body.global_transform * (Vector3(c) * ShipGrid.CELL), "radius": ShipGrid.CELL * 0.5 + ShipSkin.GAP + ShipSkin.T})
	return out


## The ships as things to hit (FlightModel.bodies).
func bodies() -> Array:
	var out := []
	if root == null or not root.visible:
		return out
	for s in parked:
		out.append({"centre": s.global_position, "radius": s.radius * 0.6, "name": "the " + s.title.get_slice("  ", 1), "ship": true})
	for m in movers:
		if (m.ship as NpcShip).visible:
			out.append({"centre": (m.ship as NpcShip).global_position, "radius": (m.ship as NpcShip).radius * 0.6, "name": "the " + (m.ship as NpcShip).title.get_slice("  ", 1), "ship": true})
	for d in derelicts:
		out.append({"centre": (d.ship as NpcShip).global_position, "radius": (d.ship as NpcShip).radius * 0.6, "name": "the wreck of " + String(d.name), "ship": true, "wreck": true})
	if passer != null:
		out.append({"centre": passer.global_position, "radius": passer.radius * 0.6, "name": "the " + passer.title.get_slice("  ", 1), "ship": true})
	for m in pods:
		if (m.ship as NpcShip).visible:
			out.append({"centre": (m.ship as NpcShip).global_position, "radius": (m.ship as NpcShip).radius * 0.6, "name": "a station pod", "ship": true})
	for o in orbiters:
		out.append({"centre": (o.ship as NpcShip).global_position, "radius": (o.ship as NpcShip).radius * 0.6, "name": "the " + (o.ship as NpcShip).title.get_slice("  ", 1), "ship": true})
	return out


## Move the traffic on by `dt` game seconds; `real_dt` keeps the name tags fresh.
func step(dt: float) -> void:
	if root == null:
		return
	root.visible = not sc._jumping() and not sc._on_surface() and (sc.planet == null or sc.planet.visible)
	if not root.visible:
		return
	for m in movers:
		_move(m, dt)
	for m in pods:
		_pod(m, dt)
	for o in orbiters:
		_orbit(o, dt)
	if sc.xfer != null and (sc.phase == "cruise" or sc.phase == "depart"):
		_deep_derelict()
	if _announce != "" and sc.notice_s <= 0.0:
		sc.say(_announce, 8.0)
		_announce = ""
	_pass(dt)
	var eye: Vector3 = sc.model.pos
	var rng_m := float(cfg.get("label_range_m", 4000.0))
	for s in parked:
		s.show_tag(eye, rng_m)
	for m in movers:
		(m.ship as NpcShip).show_tag(eye, rng_m)
	for m in pods:
		(m.ship as NpcShip).show_tag(eye, rng_m * 0.25)
	for o in orbiters:
		(o.ship as NpcShip).show_tag(eye, rng_m)
	for d in derelicts:
		(d.ship as NpcShip).show_tag(eye, 1.0e9)   # wrecks are worth finding: always tagged
		for p in d.points:
			if String(p.get("kind", "")) == "item" and is_instance_valid(p.marker) and (p.marker as Node3D).visible:
				(p.marker as Node3D).rotation += (p.marker as Node3D).get_meta("spin", Vector3.ZERO) * dt   # tumbling slowly
	if passer != null:
		passer.show_tag(eye, rng_m * 2.0)
	for s in stops:   # somebody calling for help: always tagged
		if is_instance_valid(s):
			(s as NpcShip).show_tag(eye, 1.0e9)


## A ship coming or going: rest out of sight, then fly from a slot by the station out to far away (or
## back in), easing up to speed and down again.
func _move(m: Dictionary, dt: float) -> void:
	var s: NpcShip = m.ship
	m.t = float(m.t) + dt
	if m.state == "rest":
		s.visible = false
		if float(m.t) < float(m.rest):
			return
		var a := rng.randf() * TAU
		var near := Vector3(cos(a) * 140.0, sin(a) * 60.0, -40.0)
		var far := (near.normalized() + Vector3(0, 0, -1.5)).normalized() * float(cfg.get("mover_far_m", 5000.0))
		var out := bool(m.out)
		m.a = near if out else far
		m.b = far if out else near
		m.dur = (m.a as Vector3).distance_to(m.b) / float(cfg.get("mover_speed_m_s", 90.0))
		m.state = "fly"
		m.t = 0.0
		s.visible = true
	var u := clampf(float(m.t) / float(m.dur), 0.0, 1.0)
	var e := u * u * (3.0 - 2.0 * u)
	var p0: Vector3 = m.a
	var p1: Vector3 = m.b
	s.position = p0.lerp(p1, e)
	var dir := (p1 - p0).normalized()
	if dir.length() > 0.5:
		s.basis = Basis.looking_at(dir, Vector3.UP)
	s.set_flames(bool(m.out) and u < 0.5)   # burning away from the station
	if u >= 1.0:
		m.state = "rest"
		m.t = 0.0
		m.rest = _range("mover_rest_s", [20.0, 70.0])
		m.out = not bool(m.out)
		s.visible = false
		s.set_flames(false)


## A pod's errand: from the station out to one of the parked ships, a pause, and back.
func _pod(m: Dictionary, dt: float) -> void:
	var s: NpcShip = m.ship
	m.t = float(m.t) + dt
	if m.state == "rest":
		s.visible = false
		if float(m.t) < float(m.rest) or parked.is_empty():
			return
		var dock := Vector3(rng.randf_range(-6.0, 6.0), rng.randf_range(-6.0, 6.0), -48.0)   # the rear module
		var ship_p: Vector3 = parked[int(m.home) % parked.size()].position
		var by := ship_p + (dock - ship_p).normalized() * (parked[int(m.home) % parked.size()].radius + 6.0)
		m.a = dock if bool(m.out) else by
		m.b = by if bool(m.out) else dock
		m.dur = (m.a as Vector3).distance_to(m.b) / float((cfg.get("pods", {}) as Dictionary).get("speed_m_s", 25.0))
		m.state = "fly"
		m.t = 0.0
		s.visible = true
	var u := clampf(float(m.t) / maxf(float(m.dur), 0.1), 0.0, 1.0)
	var e := u * u * (3.0 - 2.0 * u)
	var p0: Vector3 = m.a
	var p1: Vector3 = m.b
	s.position = p0.lerp(p1, e)
	if (p1 - p0).length() > 0.5:
		s.basis = Basis.looking_at((p1 - p0).normalized(), Vector3.UP)
	s.set_flames(u < 0.3)
	if u >= 1.0:
		m.state = "rest"
		m.t = 0.0
		var pr: Array = (cfg.get("pods", {}) as Dictionary).get("rest_s", [8.0, 30.0])
		m.rest = rng.randf_range(float(pr[0]), float(pr[1]))
		m.out = not bool(m.out)
		if bool(m.out):
			m.home = rng.randi() % maxi(1, parked.size())
		s.visible = false
		s.set_flames(false)


## Round and round the world it works.
func _orbit(o: Dictionary, dt: float) -> void:
	var w: Node3D = o.world
	if not is_instance_valid(w):
		return
	o.angle = float(o.angle) + float(o.speed) / float(o.radius) * dt
	var a := float(o.angle)
	var tilt: Basis = o.tilt
	var s: NpcShip = o.ship
	s.global_position = w.global_position + tilt * Vector3(cos(a), 0, sin(a)) * float(o.radius)
	var along := tilt * Vector3(-sin(a), 0, cos(a))
	s.global_basis = Basis.looking_at(along, tilt * Vector3.UP)


## On a run, now and then a ship comes the other way along the route, a kilometre or two off.
func _pass(dt: float) -> void:
	var on_run: bool = sc.xfer != null and sc.phase == "cruise"
	if passer != null:
		passer.position += passer_vel * dt
		var dir := passer_vel.normalized()
		if not on_run or (passer.position - sc.model.pos).dot(-dir) < -25000.0:
			passer.queue_free()
			passer = null
		return
	if not on_run:
		return
	passer_wait -= dt
	if passer_wait > 0.0:
		return
	passer_wait = _range("passer_every_s", [50.0, 140.0])
	var to := sc.xfer.target - sc.model.pos
	if to.length() < float(cfg.get("passer_ahead_m", 40000.0)) * 1.5:
		return   # too near the end of the run for anyone to pass
	var route := to.normalized()
	var side := route.cross(Vector3.UP)
	if side.length() < 0.1:
		side = route.cross(Vector3.RIGHT)
	side = side.normalized().rotated(route, rng.randf() * TAU)
	var companies := _companies()
	var co: String = companies[rng.randi() % companies.size()] if not companies.is_empty() else "INDEPENDENT"
	passer = NpcShip.make(LAYOUTS[rng.randi() % LAYOUTS.size()], "%s  %s" % [co, _ship_name(rng)])
	passer.position = sc.model.pos + route * float(cfg.get("passer_ahead_m", 40000.0)) + side * _range("passer_side_m", [1200.0, 3000.0])
	passer_vel = -route * float(cfg.get("passer_speed_m_s", 600.0))
	passer.basis = Basis.looking_at(-route, Vector3.UP)
	root.add_child(passer)
