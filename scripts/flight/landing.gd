class_name Landing
extends RefCounted
## Coming down and going up: whether a run lands or docks, arriving above a moon's pad or at the top of
## a planet's air, the entry and the descent, lift-off and the climb back to orbit, the lift-jet command,
## and bringing the right ground, gravity, air and scenery in (the moon's or a planet's) and taking them
## away again.

var sc: FlightScene   ## the scene this works on
var _moon_cfg: Dictionary = {}   ## landing.json, kept while a planet's own settings are in force


func _init(scene: FlightScene) -> void:
	sc = scene


## Which ground a surface site kind is on: "moon" (pad, camp), "world" (downport, field) or "mars".
static func body_key(kind: String) -> String:
	if kind == "field":
		return "world"
	return kind if Planets.is_planet_kind(kind) else "moon"


func on_planet() -> bool:
	return Planets.is_planet_kind(sc._target_kind)


## Where a surface site's pad is on the ground (y is the ground there).
func _pad_pos(kind: String) -> Vector3:
	if Planets.is_planet_kind(kind):
		var pt := sc.model.terrain as PlanetTerrain
		if pt == null or body_key(kind) != sc._scenery_key:
			pt = sc._make_terrain_for(kind) as PlanetTerrain
		if kind == "field":
			return Vector3(pt.field_xz.x, pt.field_h, pt.field_xz.y)
		return Vector3(0, pt.port_h, 0)
	if kind == "camp":
		var c := SurfaceFinds.camp_xz()
		var t := sc.model.terrain if sc.model.terrain != null and sc._scenery_key == "moon" else sc._make_terrain_for("pad")
		return Vector3(c.x, t.height(c.x, c.y), c.y)
	return Vector3.ZERO


## A run to a moon base lands on its pad when the ship has lander legs with enough lift for the load and
## fuel to come down on; otherwise it docks at the base's orbital station. Surface sites must be landed
## on, and a planet's are come down to through its air whatever the lift says (the HUD warns).
func _can_land() -> bool:
	var dk := String(sc.job.get("dest_kind", ""))
	if Planets.is_planet_kind(dk):
		return true
	if not (dk == "moon" or dk in LocalSpace.SURFACE) or sc.model.lift_kn <= 0.0:
		return false
	if dk == "moon" and sc.model.fuel_t < float(sc.model.land_cfg.get("landing_reserve_t", 1.5)):
		return false   # not enough left in the tanks to come down on the jets: dock in orbit instead
	return sc.model.lift_accel() >= float(LocalSpace.body_at(sc._system_id(), "pad").get("gravity_m_s2", 1.62)) * float(sc.model.land_cfg.get("min_lift_margin", 1.15))


func _stranded() -> bool:
	var helpless := not sc.model.has_fuel() or sc.model.disabled()
	if sc._on_surface():
		return helpless and not sc.model.on_pad()
	return helpless and (sc.phase != "approach" or not sc.model.can_dock())


## The settings for landing on this ground: landing.json, with a planet's own on top.
func _cfg_for(key: String) -> Dictionary:
	if _moon_cfg.is_empty():
		_moon_cfg = sc.model.land_cfg
	if key == "moon":
		return _moon_cfg
	var c := _moon_cfg.duplicate()
	var e: Dictionary = Planets.config().entry
	for k in ["autoland_cruise_m_s", "touchdown_speed_m_s", "landing_zone_m", "sea_damage"]:
		c[k] = e[k]
	c["camp_zone_m"] = float(e.field_zone_m)
	c["ascent_clear_m"] = float(Planets.config().surface.ascent_clear_m)
	return c


## The air a planet site's ship flies through, in FlightModel's terms.
func air_for(kind: String) -> Dictionary:
	var p := Planets.planet(sc._system_id(), kind)
	var e: Dictionary = Planets.config().entry
	return {"density": Planets.density(sc._system_id(), kind), "scale_m": float(p.get("air", {}).get("scale_km", 8.5)) * 1000.0,
			"cd_flat": float(e.cd_flat), "cd_nose": float(e.cd_nose), "heat_k": float(e.heat_k), "nose_mult": float(e.heat_nose_mult),
			"shed": float(e.heat_shed_per_s), "damage_per_s": float(e.heat_damage_per_s), "shield_cut": 1.0 - 1.0 / float(e.shield_tolerance)}


## Gravity, ground, air and the right scenery on; space markers and the station off.
func _ensure_moon() -> void:
	var key := body_key(sc._target_kind)
	var body := sc._body()
	sc.model.gravity = float(body.get("gravity_m_s2", 1.62))
	if sc._ground_task >= 0:
		WorkerThreadPool.wait_for_task_completion(sc._ground_task)
		sc._ground_task = -1
	if sc._scenery_key != key:
		_drop_scenery()
		sc.model.terrain = null
	if sc.model.terrain == null:
		sc.model.terrain = sc._ground_terrain if (sc._ground_terrain != null and sc._ground_key == key) else sc._make_terrain_for(sc._target_kind)
	sc.model.land_cfg = _cfg_for(key)
	if key == "moon":
		sc.model.air = {}
		sc.model.wind = Vector3.ZERO
		sc.model.rocks = SurfaceSites.boulders(sc._system_id())
	else:
		sc.model.air = air_for(sc._target_kind)
		sc.model.rocks = []
		sc.weather = Planets.weather(sc._system_id(), sc._target_kind, Session.sim.now_hour() if Session.sim != null else 0)
	sc.model.station_solid = false
	sc.station.visible = false
	if sc.planet != null:
		sc.planet.visible = false
	for m in sc.sparks:
		m.visible = false
	if sc.beacon != null:
		sc.beacon.visible = false
	sc.warp_index = 0
	sc.help.text = sc.LAND_HELP
	if key == "moon":
		var sun_deg: Array = body.get("sky_sun_deg", [-28, 35])
		sc.sun.rotation_degrees = Vector3(float(sun_deg[0]), float(sun_deg[1]), 0)
		sc.sun.light_color = Color(1.0, 0.97, 0.92)
		sc.sun.light_energy = 1.05             # bare rock in hard sunlight: keep it from burning out to white
		sc.world_env.ambient_light_energy = 0.18
		if sc.moon == null:
			sc._build_moon(body)
			GameSettings.apply_scene(sc, 400.0)
		sc.moon.visible = true
	else:
		if sc._space_sky == null:
			sc._space_sky = sc.world_env.sky
		var p := Planets.planet(sc._system_id(), sc._target_kind)
		sc.world_env.sky = PlanetScenery.make_sky(p)
		sc.camera.far = 400000.0
		if sc.world == null:
			sc._build_world_ground()
			GameSettings.apply_scene(sc, 400.0)
		sc.world.visible = true
		update_planet(0.0)
	sc._scenery_key = key


## Take away whichever ground is built (going from a moon to a planet, or back).
func _drop_scenery() -> void:
	if sc.moon != null:
		sc.moon.queue_free()
		sc.moon = null
		sc.find_nodes = {}
		sc.ops = null
	if sc.world != null:
		sc.world.queue_free()
		sc.world = null
	sc.pad_label = null
	sc._scenery_key = ""


## Each frame over a planet: the wind on the ship, the sky and haze by height and hour, the city's lights
## and the fine ground following the ship. Hot from the entry, the radiators and the legs wear.
func update_planet(dt: float) -> void:
	if sc.world == null or not on_planet():
		return
	var alt := sc.model.pos.y
	sc.model.wind = Planets.wind_at(sc.weather, sc.model.elapsed_s, maxf(sc.model.altitude(), 0.0)) * clampf(1.0 - alt / 15000.0, 0.0, 1.0)
	var hour := Session.sim.now_hour() if Session.sim != null else 12
	var hod := PlanetScenery.local_hour(sc._system_id(), hour, sc.model.elapsed_s / 60.0)
	var k := sc.model.air_density() / maxf(float(sc.model.air.get("density", 1.0)), 0.0001)
	PlanetScenery.update_sky(sc.world_env, sc.sun, Planets.planet(sc._system_id(), sc._target_kind), hod, k, float(sc.weather.get("fog", 0.0)))
	sc.world.follow(sc.model.pos, PlanetScenery.night_at(hod))
	var low := sc.model.altitude() < 4000.0 or sc.outside
	sc.world.set_weather(String(sc.weather.get("kind", "calm")) if low else "", sc.model.wind)
	sc.world.weather_at(sc.camera.global_position)
	if sc.model.skin_heat > 1.0 and dt > 0.0 and sc.wear is Dictionary and sc.ship_data != null:
		var w := float(Planets.config().entry.heat_wear_per_s) * (sc.model.skin_heat - 1.0) * dt
		for part in ["radiator", "legs"]:
			Wear.add(sc.wear, sc.ship_data, part, w)


## Standing on a surface site's pad, landed, level.
func _begin_surface(kind: String) -> void:
	sc._target_kind = kind
	sc._ensure_moon()
	var p := sc._pad_pos(kind)
	sc.model.pos = p + Vector3(0, sc.model.foot_m, 0)
	sc.model.vel = Vector3.ZERO
	sc.model.ang = Vector3.ZERO
	sc.model.throttle = 0.0
	sc.model.braking = false
	sc.model.autoland = false
	sc.model.autoentry = false
	sc.model.basis = Basis.looking_at(Vector3(0, 0, -1), Vector3.UP)
	sc.model.landed = true
	sc.model.pad = p
	sc.model.zone_m = float(sc.model.land_cfg.get("camp_zone_m", 60.0)) if kind in ["camp", "field"] else 0.0
	sc._target_kind = kind
	sc._apply_pose()


## Point the descent at a surface site: its pad becomes the target, and only the base and the downports
## have a beacon.
func _aim_descent_at(kind: String) -> void:
	sc._target_kind = kind
	sc.model.pad = sc._pad_pos(kind)
	sc.model.zone_m = float(sc.model.land_cfg.get("camp_zone_m", 60.0)) if kind in ["camp", "field"] else 0.0
	sc._beacon = not kind in ["camp", "field"]


## Arrived over the moon: high above the target pad, drifting toward it, level. Gravity on. At a planet,
## the entry instead.
func _begin_descent() -> void:
	var dk := String(sc.job.get("dest_kind", "moon"))
	if Planets.is_planet_kind(dk):
		_begin_entry(dk)
		return
	sc.phase = "descent"
	var cfg := sc.model.land_cfg
	sc._target_kind = dk if dk in LocalSpace.SURFACE else "pad"
	sc._ensure_moon()
	cfg = sc.model.land_cfg
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


## The top of a planet's air, a long way out from the downport and coming in fast and shallow, belly to
## the air. Where it starts is worked out so the drag alone would bring the ship down a little short of
## the pad: the glide and the jets do the rest.
func _begin_entry(kind: String) -> void:
	sc.phase = "entry"
	sc._target_kind = kind
	sc._ensure_moon()
	sc._aim_descent_at(kind)
	var e: Dictionary = Planets.config().entry
	var p := Planets.planet(sc._system_id(), kind)
	var thin := clampf(sqrt(float(p.get("air", {}).get("density", 1.0))), 0.35, 1.0)   # thin air brakes less: arrive slower
	var v0 := float(e.start_speed_m_s) * thin
	var gamma := deg_to_rad(float(e.start_angle_deg))
	var alt0 := float(e.start_altitude_m) * clampf(float(p.get("air", {}).get("scale_km", 8.5)) / 8.5, 0.7, 1.2)
	var a := float(absi(hash(String(sc.job.get("dest_id", "")) + "|entry")) % 360) * PI / 180.0
	var dir := Vector3(cos(a), 0, sin(a))
	var vel := dir * v0 * cos(gamma) + Vector3.DOWN * v0 * sin(gamma)
	var reach := entry_range(sc.model, alt0, vel)
	sc.model.pos = sc.model.pad - dir * (reach + float(e.aim_short_m)) + Vector3(0, alt0, 0)
	sc.model.pos.y = alt0
	sc.model.vel = vel
	sc.model.basis = belly_basis(vel, dir)
	sc.model.ang = Vector3.ZERO
	sc.model.throttle = 0.0
	sc.model.braking = false
	sc.model.course_hold = false
	sc.model.autoland = false
	sc.model.autoentry = false
	sc.model.landed = false
	sc.model.skin_heat = 0.0
	sc.model.skin_peak = 0.0
	sc.warp_index = 0
	sc._apply_pose()
	var shield := sc.model.shield
	sc.say("Entry interface, %s. Belly to the air and keep it there: nose first, you cook. T for the autopilot.%s" % [String(p.get("name", "")),
			"" if shield > 0.0 else " No heat shield: the hull takes it all."], 8.0)


## The ship's attitude with its belly square to the airflow, nose along the way it's heading.
static func belly_basis(vel: Vector3, heading: Vector3) -> Basis:
	var up := -vel.normalized()
	var fwd := (heading - up * heading.dot(up)).normalized()
	if fwd.length() < 0.1:
		fwd = Vector3.FORWARD
	return Basis.looking_at(fwd, up)


## How far over the ground a ship flies from the top of the air, belly first with no help, until it's low
## and slow enough to steer (planets.json descent_below_m and _m_s). Runs the flight model's own air.
static func entry_range(m: FlightModel, alt0: float, vel0: Vector3) -> float:
	var t := FlightModel.new()
	t.tune = m.tune
	t.dry_t = m.dry_t
	t.fuel_t = m.fuel_t
	t.cargo_t = m.cargo_t
	t.area = m.area
	t.shield = m.shield
	t.air = m.air
	t.gravity = m.gravity
	t.pos = Vector3(0, alt0, 0)
	t.vel = vel0
	t.lift_kn = m.lift_kn
	var e: Dictionary = Planets.config().entry
	var dt := 0.25
	for i in 12000:
		t.basis = belly_basis(t.vel, Vector3(t.vel.x, 0, t.vel.z).normalized() if Vector2(t.vel.x, t.vel.z).length() > 1.0 else Vector3.FORWARD)
		t._aero(dt)
		t.vel.y -= t.gravity * dt
		t.pos += t.vel * dt
		if t.pos.y < float(e.descent_below_m) and t.airspeed() < float(e.descent_below_m_s):
			break   # thick air: low and slow, the glide does the rest
		var v_h0 := Vector2(t.vel.x, t.vel.z).length()
		if t.burn_due(t.pos.y, maxf(-t.vel.y, 0.0)) or t.pos.y <= 0.0 or (float(t.air.get("density", 1.0)) < 0.2 and t.airspeed() > 320.0 and t.pos.y < 30000.0):
			# thin air: the burn starts high, still moving; it carries on about half its drift while it stops
			var a_brake := maxf(t.lift_accel() * 0.85 - t.gravity, 0.5)
			var v_h := Vector2(t.vel.x, t.vel.z).length()
			return Vector2(t.pos.x, t.pos.z).length() + v_h * (maxf(-t.vel.y, 0.0) / a_brake) * 0.45
	return Vector2(t.pos.x, t.pos.z).length()


## Lifted clear of the moon: on to the base's station (a run to orbit) or out into space for the cruise.
## From a planet, the climb to orbit is burned now, all of it; if the tanks can't cover it, the ship stays
## in the air and says so.
func _reach_orbit() -> bool:
	if on_planet():
		var up := Planets.up_dv(sc._system_id(), sc._target_kind)
		var need := LocalSpace.burn_t(sc.model.mass_t(), up)
		if sc.model.fuel_t < need:
			sc.auto_ascent = false
			sc.say("Not enough in the tanks to make orbit: %.1f t short. Set back down and buy fuel, or lighten the load." % (need - sc.model.fuel_t), 6.0)
			return false
		sc.model.fuel_t -= need
		sc.model.fuel_burned_t += need
		sc.say("Main engine to orbit: %.1f t of fuel for %.1f km/s. The air lets go about half way up." % [need, up], 6.0)
	sc.auto_ascent = false
	sc.hover_hold = false
	sc.model.terrain = null
	sc.model.gravity = 0.0
	sc.model.landed = false
	sc.model.lift = 0.0
	sc.model.air = {}
	sc.model.wind = Vector3.ZERO
	sc.model.autoentry = false
	if sc.moon != null:
		sc.moon.visible = false
	if sc.world != null:
		sc.world.visible = false
		_drop_scenery()
	if sc._space_sky != null:
		sc.world_env.sky = sc._space_sky
		sc.world_env.fog_enabled = false
		sc.world_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		sc.camera.far = 16000.0
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
		return true
	sc.phase = "cruise"
	var start := Vector3(0.35, 0.15, 1.0).normalized() * (sc.CLEAR_M + 50.0)
	sc.model.pos = start
	sc.model.vel = Vector3.ZERO
	sc.model.ang = Vector3.ZERO
	sc.model.station_solid = false
	sc.model.basis = Basis.looking_at((sc.xfer.target - start).normalized(), Vector3.UP)
	sc._apply_pose()
	if String(sc.job.get("dest_kind", "")) == "port" and sc._dv_space <= 0.3:
		sc._begin_approach()   # a downport's own station is right overhead
	return true


## Free flight from a surface site (the helm taken at a pad, the camp, a downport or a field): sitting on
## its pad.
func _begin_surface_free() -> void:
	var kind := String(LocalSpace.node(String(Session.profile.get("port_id", ""))).get("kind", "pad"))
	sc._begin_surface(kind)
	sc.phase = "descent"
	sc._beacon = not kind in ["camp", "field"]


## Space fires the lift jets; with hover hold on they cancel the fall instead; lifting off on auto, full lift.
func _lift_command() -> float:
	if not sc._on_surface() or sc.model.autoland or sc.model.autoentry:
		return 0.0
	if sc.auto_ascent:
		return 1.0
	if not sc.walking and not sc.outside and Input.is_key_pressed(KEY_SPACE):
		return 1.0
	if sc.hover_hold and sc.model.lift_accel() > 0.0:
		var up := maxf(sc.model.basis.y.dot(Vector3.UP), 0.2)
		return clampf((sc.model.gravity - sc.model.vel.y * 1.2) / (sc.model.lift_accel() * up), 0.0, 1.0)
	return 0.0
