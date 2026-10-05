class_name Landing
extends RefCounted
## Over a moon: whether a run lands or docks, arriving above the pad, the descent and lift-off, the
## lift-jet command, bringing the moon's gravity, ground and scenery in and taking them away again on
## the climb back to orbit.

var sc: FlightScene   ## the scene this works on


func _init(scene: FlightScene) -> void:
	sc = scene


## Where a surface site's pad is on the ground (y is the ground there).
func _pad_pos(kind: String) -> Vector3:
	if kind == "camp":
		var c := SurfaceFinds.camp_xz()
		var t := sc.model.terrain if sc.model.terrain != null else sc._make_terrain()
		return Vector3(c.x, t.height(c.x, c.y), c.y)
	return Vector3.ZERO


## A run to a moon base lands on its pad when the ship has lander legs with enough lift for the load and
## fuel to come down on; otherwise it docks at the base's orbital station. Surface sites must be landed on.
func _can_land() -> bool:
	var dk := String(sc.job.get("dest_kind", ""))
	if not (dk == "moon" or dk in LocalSpace.SURFACE) or sc.model.lift_kn <= 0.0:
		return false
	if dk == "moon" and sc.model.fuel_t < float(sc.model.land_cfg.get("landing_reserve_t", 1.5)):
		return false   # not enough left in the tanks to come down on the jets: dock in orbit instead
	return sc.model.lift_accel() >= float(sc._body().get("gravity_m_s2", 1.62)) * float(sc.model.land_cfg.get("min_lift_margin", 1.15))


func _stranded() -> bool:
	if sc._on_surface():
		return not sc.model.has_fuel() and not sc.model.on_pad()
	return not sc.model.has_fuel() and (sc.phase != "approach" or not sc.model.can_dock())


## Gravity, ground and the moon's scenery on; space markers and the station off.
func _ensure_moon() -> void:
	var body := sc._body()
	sc.model.gravity = float(body.get("gravity_m_s2", 1.62))
	if sc._ground_task >= 0:
		WorkerThreadPool.wait_for_task_completion(sc._ground_task)
		sc._ground_task = -1
	if sc.model.terrain == null:
		sc.model.terrain = sc._ground_terrain if sc._ground_terrain != null else sc._make_terrain()
	sc.model.rocks = SurfaceSites.boulders(sc._system_id())
	sc.model.station_solid = false
	sc.station.visible = false
	if sc.planet != null:
		sc.planet.visible = false
	for m in sc.sparks:
		m.visible = false
	if sc.beacon != null:
		sc.beacon.visible = false
	sc.warp_index = 0
	var sun_deg: Array = body.get("sky_sun_deg", [-28, 35])
	sc.sun.rotation_degrees = Vector3(float(sun_deg[0]), float(sun_deg[1]), 0)
	sc.sun.light_color = Color(1.0, 0.97, 0.92)
	sc.sun.light_energy = 1.05             # bare rock in hard sunlight: keep it from burning out to white
	sc.world_env.ambient_light_energy = 0.18
	sc.help.text = sc.LAND_HELP
	if sc.moon == null:
		sc._build_moon(body)
		GameSettings.apply_scene(sc, 400.0)
	sc.moon.visible = true


## Standing on a surface site's pad, landed, level.
func _begin_surface(kind: String) -> void:
	sc._ensure_moon()
	var p := sc._pad_pos(kind)
	sc.model.pos = p + Vector3(0, sc.model.foot_m, 0)
	sc.model.vel = Vector3.ZERO
	sc.model.ang = Vector3.ZERO
	sc.model.throttle = 0.0
	sc.model.braking = false
	sc.model.autoland = false
	sc.model.basis = Basis.looking_at(Vector3(0, 0, -1), Vector3.UP)
	sc.model.landed = true
	sc.model.pad = p
	sc.model.zone_m = float(sc.model.land_cfg.get("camp_zone_m", 60.0)) if kind == "camp" else 0.0
	sc._target_kind = kind
	sc._apply_pose()


## Point the descent at a surface site: its pad becomes the target, and only the base has a beacon.
func _aim_descent_at(kind: String) -> void:
	sc._target_kind = kind
	sc.model.pad = sc._pad_pos(kind)
	sc.model.zone_m = float(sc.model.land_cfg.get("camp_zone_m", 60.0)) if kind == "camp" else 0.0
	sc._beacon = kind != "camp"


## Arrived over the moon: high above the target pad, drifting toward it, level. Gravity on.
func _begin_descent() -> void:
	sc.phase = "descent"
	var cfg := sc.model.land_cfg
	sc._ensure_moon()
	var dk := String(sc.job.get("dest_kind", "moon"))
	sc._aim_descent_at(dk if dk in LocalSpace.SURFACE else "pad")
	sc.model.braking = false
	sc.model.autoland = false
	sc.model.throttle = 0.0
	sc.model.ang = Vector3.ZERO
	sc.model.landed = false
	var a := float(absi(hash(String(sc.job.get("dest_id", "")))) % 360) * PI / 180.0
	var dir := Vector3(cos(a), 0, sin(a))
	sc.model.pos = sc.model.pad + dir * float(cfg.get("start_offset_m", 900.0)) + Vector3(0, float(cfg.get("start_altitude_m", 1200.0)), 0)
	sc.model.vel = -dir * float(cfg.get("start_speed_m_s", 25.0))
	sc.model.basis = Basis.looking_at(-dir, Vector3.UP)
	sc._apply_pose()


## Lifted clear of the moon: on to the base's station (a run to orbit) or out into space for the cruise.
func _reach_orbit() -> void:
	sc.auto_ascent = false
	sc.hover_hold = false
	sc.model.terrain = null
	sc.model.gravity = 0.0
	sc.model.landed = false
	sc.model.lift = 0.0
	if sc.moon != null:
		sc.moon.visible = false
	for m in sc.sparks:
		m.visible = true
	if sc.planet != null:
		sc.planet.visible = true
	sc.sun.rotation_degrees = Vector3(-30, 40, 0)
	sc.sun.light_color = Color(1.0, 0.94, 0.85)
	sc.sun.light_energy = 1.4
	sc.world_env.ambient_light_energy = 0.55
	sc.help.text = sc.FLY_HELP
	if String(sc.job.get("dest_kind", "")) == "moon":
		sc.station_label.text = String(sc.job.get("destination", "")).to_upper()
		sc._begin_approach(3000.0)
		return
	sc.phase = "cruise"
	var start := Vector3(0.35, 0.15, 1.0).normalized() * (sc.CLEAR_M + 50.0)
	sc.model.pos = start
	sc.model.vel = Vector3.ZERO
	sc.model.ang = Vector3.ZERO
	sc.model.station_solid = false
	sc.model.basis = Basis.looking_at((sc.xfer.target - start).normalized(), Vector3.UP)
	sc._apply_pose()


## Free flight from a surface site (the helm taken at a pad or the camp): sitting on its pad.
func _begin_surface_free() -> void:
	var kind := String(LocalSpace.node(String(Session.profile.get("port_id", ""))).get("kind", "pad"))
	sc._begin_surface(kind)
	sc.phase = "descent"
	sc._beacon = kind != "camp"


## Space fires the lift jets; with hover hold on they cancel the fall instead; lifting off on auto, full lift.
func _lift_command() -> float:
	if not sc._on_surface() or sc.model.autoland:
		return 0.0
	if sc.auto_ascent:
		return 1.0
	if not sc.walking and not sc.outside and Input.is_key_pressed(KEY_SPACE):
		return 1.0
	if sc.hover_hold and sc.model.lift_accel() > 0.0:
		var up := maxf(sc.model.basis.y.dot(Vector3.UP), 0.2)
		return clampf((sc.model.gravity - sc.model.vel.y * 1.2) / (sc.model.lift_accel() * up), 0.0, 1.0)
	return 0.0
