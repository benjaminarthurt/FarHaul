class_name HazardWatch
extends RefCounted
## Danger without combat, in a flight you're flying (Hazards): the system's solar storms (forecast at
## the start, the sensors' warning, and while one rages: radiators losing cooling and wearing, the hull
## taking a little) and, on a flown local run, the debris field across the route: a cloud of rock with a
## marker you can see coming and fly round. Inside it, hits come faster the faster you go and hurt more;
## with the autopilot flying (course hold or stop at the target) about a third as often.

var sc: FlightScene
var start_h := 0           ## the calendar hour the flight began (storms keep calendar time)
var field: Dictionary = {}  ## the debris field across this run, or {}
var centre := Vector3.ZERO
var radius := 0.0
var root: Node3D = null    ## the rock cloud and its marker
var hits := 0              ## debris hits this flight
var inside := false
var _rng := RandomNumberGenerator.new()
var _storm_told := false
var _sensor_told := false
var _near_told := false
var storm_now := {}        ## the storm raging right now, or {}


func _init(scene: FlightScene) -> void:
	sc = scene


## At the start of a flight: what the radio's weather says, and the run's debris field.
func setup() -> void:
	if Session.sim == null:
		return
	start_h = Session.sim.now_hour()
	var sys := Session.system_id()
	for s in Hazards.known(sys, start_h):
		sc.say("Space weather: solar storm here, %s. Radiators cook out there; in port you're shielded." % Hazards.describe(s, start_h), 7.0)
		_storm_told = int(s.start) <= start_h
	if sc.xfer == null or sc.job.is_empty():
		return
	field = Hazards.local_field(sys, String(sc.job.get("origin_kind", "port")), String(sc.job.get("dest_kind", "port")), Session.day())
	if field.is_empty():
		return
	_rng.seed = int(field.seed)
	radius = float(field.radius_m)
	var dir: Vector3 = sc.xfer.target.normalized()
	var side := dir.cross(Vector3.UP).normalized() if absf(dir.dot(Vector3.UP)) < 0.95 else Vector3.RIGHT
	centre = sc.xfer.target * float(field.along) + side * float(field.offset) * radius
	_build_cloud()
	sc.say("Debris field reported on this run: %.0f km out, %.0f km across. Go round it, slow down, or let the autopilot (V or X) thread it." % [centre.length() / 1000.0, radius * 2.0 / 1000.0], 8.0)


## The calendar hour now: the flight's own clock on top of where it started.
func hour_now() -> int:
	return start_h + int(sc.model.elapsed_s / 3600.0)


func autopilot() -> bool:
	return sc.model.braking or sc.model.course_hold


## Each step of game time: the weather, then the rocks.
func step(dt: float) -> void:
	if sc.model == null or Session.sim == null or dt <= 0.0 or sc._jumping():
		return
	_storm_step(dt)
	_debris_step(dt)


func _storm_step(dt: float) -> void:
	var c: Dictionary = Hazards.config().storms
	var h := hour_now()
	storm_now = Hazards.storm_at(Session.system_id(), h)
	if storm_now.is_empty():
		sc.model.storm_cooling = 0.0
		if not _sensor_told:   # the ship's own sensors pick up a front the forecasters missed
			for s in Hazards.storms(Session.system_id(), h, h + 12):
				if String(s.warn) == "sensors" and h >= int(s.warn_at) and h < int(s.start):
					_sensor_told = true
					sc.say("SENSORS: solar storm front building, about %d hours out. Somewhere with walls would be nice." % maxi(1, int(s.start) - h), 7.0)
		return
	var k := float(storm_now.intensity)
	sc.model.storm_cooling = float(c.cooling_loss) * k
	if sc.wear is Dictionary and sc.ship_data != null:
		Wear.add(sc.wear, sc.ship_data, "radiator", float(c.radiator_wear_per_hour) * k * dt / 3600.0)
	sc.model.hurt(float(c.hull_per_hour) * k * dt / 3600.0)
	if not _storm_told:
		_storm_told = true
		sc.say("SOLAR STORM. The radiators are cooking and shedding less heat. It lasts till day %d." % (int(storm_now.end) / 24), 7.0)


func _debris_step(dt: float) -> void:
	if field.is_empty():
		return
	var d := sc.model.pos.distance_to(centre)
	if not _near_told and d < radius * 3.0 and d > radius:
		_near_told = true
		sc.say("DEBRIS FIELD ahead, %.1f km. Slow down or go round." % ((d - radius) / 1000.0), 5.0)
	var was := inside
	inside = d < radius
	if inside and not was:
		sc.say("In the debris field.%s" % (" The autopilot's dodging what it can." if autopilot() else " Every metre a second counts."), 4.0)
	if not inside:
		return
	var speed := sc.model.speed()
	var mean := Hazards.hit_rate_per_km(field, autopilot()) * speed * dt / 1000.0
	var n := Hazards._poisson(mean, _rng)
	for i in n:
		hits += 1
		var dmg := Hazards.hit_damage(speed)
		sc.model.hurt(dmg)
		sc.say("Debris strike at %s m/s: %d%% of the hull." % [ShipStats.commas(roundi(speed)), maxi(1, roundi(dmg * 100.0))], 3.0)


## A flown star jump: storms at either end and debris on the lane, on the flight's own hull and wear.
func after_jump(hz: Dictionary) -> void:
	if hz.is_empty():
		return
	if float(hz.get("hull", 0.0)) > 0.0:
		sc.model.hurt(float(hz.hull))
	if float(hz.get("radiator", 0.0)) > 0.0 and sc.wear is Dictionary and sc.ship_data != null:
		Wear.add(sc.wear, sc.ship_data, "radiator", float(hz.radiator))
	var lines: Array = hz.get("lines", [])
	if not lines.is_empty():
		sc.say(" ".join(lines), 7.0)


func _build_cloud() -> void:
	root = Node3D.new()
	root.name = "DebrisField"
	sc.add_child(root)
	root.position = centre
	var rock := StandardMaterial3D.new()
	rock.albedo_color = Color(0.36, 0.34, 0.32)
	rock.roughness = 1.0
	var mesh := SphereMesh.new()
	mesh.radius = 1.0
	mesh.height = 1.6
	mesh.radial_segments = 6
	mesh.rings = 3
	mesh.material = rock
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = 600
	var g := RandomNumberGenerator.new()
	g.seed = int(field.seed)
	for i in mm.instance_count:
		var p := Vector3(g.randf_range(-1, 1), g.randf_range(-1, 1), g.randf_range(-1, 1))
		while p.length() > 1.0:
			p = Vector3(g.randf_range(-1, 1), g.randf_range(-1, 1), g.randf_range(-1, 1))
		var s := g.randf_range(4.0, 26.0) * (1.0 + float(field.density))
		var b := Basis(Vector3(g.randf(), g.randf(), g.randf()).normalized(), g.randf() * TAU).scaled(Vector3(s, s * g.randf_range(0.5, 1.0), s * g.randf_range(0.6, 1.2)))
		mm.set_instance_transform(i, Transform3D(b, p * radius))
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
	var haze := MeshInstance3D.new()   # the dust, so it shows from a long way off
	var hs := SphereMesh.new()
	hs.radius = radius
	hs.height = radius * 2.0
	var hm := StandardMaterial3D.new()
	hm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	hm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	hm.albedo_color = Color(0.6, 0.55, 0.45, 0.012 + 0.012 * float(field.density))
	hm.cull_mode = BaseMaterial3D.CULL_BACK   # a faint glow from outside; inside, the rocks speak for themselves
	hm.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	hs.material = hm
	haze.mesh = hs
	haze.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(haze)
	var tag := Label3D.new()
	tag.text = "DEBRIS FIELD"
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.fixed_size = true
	tag.pixel_size = 0.0012
	tag.font_size = 32
	tag.no_depth_test = true
	tag.modulate = Color(1.0, 0.62, 0.2)
	tag.outline_size = 6
	root.add_child(tag)
