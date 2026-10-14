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
var derelicts: Array = []     ## {ship, name, points: [{id, pos (body frame), normal, parts, taken, marker}]}
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
	_build_derelicts(port_id)


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
		var s := NpcShip.make(LAYOUTS[r.randi() % LAYOUTS.size()], "DERELICT  %s" % nm.trim_prefix("the ").trim_prefix("an ").to_upper(), true)
		var dist: Array = dc.get("distance_m", [1800.0, 5200.0])
		var dir := Vector3(r.randf_range(-1, 1), r.randf_range(-0.3, 0.3), r.randf_range(-1, 1)).normalized()
		s.position = dir * r.randf_range(float(dist[0]), float(dist[1]))
		if sc.planet != null and sc.planet.has_meta("radius"):   # not inside the planet
			var pc := sc.planet.position
			var pr := float(sc.planet.get_meta("radius")) + 400.0
			if s.position.distance_to(pc) < pr:
				s.position = pc + (s.position - pc).normalized() * pr if (s.position - pc).length() > 1.0 else -s.position
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
			var id := "%s|%d|%d|%d" % [port_id, Session.day(), w, k]
			var p := {"id": id, "pos": site_k.pos, "normal": site_k.normal, "parts": r.randi_range(int(ppp[0]), int(ppp[1])), "taken": id in taken}
			p["marker"] = _marker(s, site_k.pos, site_k.normal)
			(p.marker as Node3D).visible = not bool(p.taken)
			points.append(p)
		derelicts.append({"ship": s, "name": nm, "points": points})


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


## Every salvage point still there: [{id, world (position), parts, derelict, k}].
func salvage_points() -> Array:
	var out := []
	for d in derelicts:
		var s: NpcShip = d.ship
		if not s.is_inside_tree():
			continue
		for k in (d.points as Array).size():
			var p: Dictionary = d.points[k]
			if not bool(p.taken):
				out.append({"id": String(p.id), "world": s.body.global_transform * (p.pos as Vector3), "parts": int(p.parts), "point": p})
	return out


## Mark a point cut free.
func take(point: Dictionary) -> void:
	point["taken"] = true
	if point.has("marker") and is_instance_valid(point.marker):
		(point.marker as Node3D).visible = false


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
	_pass(dt)
	var eye: Vector3 = sc.model.pos
	var rng_m := float(cfg.get("label_range_m", 4000.0))
	for s in parked:
		s.show_tag(eye, rng_m)
	for m in movers:
		(m.ship as NpcShip).show_tag(eye, rng_m)
	for d in derelicts:
		(d.ship as NpcShip).show_tag(eye, 1.0e9)   # wrecks are worth finding: always tagged
	if passer != null:
		passer.show_tag(eye, rng_m * 2.0)


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
