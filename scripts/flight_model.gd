class_name FlightModel
extends RefCounted
## Newtonian flight for a built ship, with no 3D in it so it can be tested headless.
## Follows data/runtime/flight_physics.json: a = available thrust / current mass, and
## current mass = dry + fuel + cargo. Thrust pushes along the ship's local -Z (forward).
## Units: metres, seconds, tonnes, kN. Tunables live in data/runtime/flight_tuning.json.

const TUNING_PATH := "res://data/runtime/flight_tuning.json"
const G0 := 9.80665

var pos := Vector3.ZERO
var vel := Vector3.ZERO
var basis := Basis.IDENTITY
var ang := Vector3.ZERO          # angular velocity in the ship's own axes (pitch, yaw, roll), rad/s
var throttle := 0.0              # 0..1 of full forward thrust
var fuel_t := 0.0
var dry_t := 0.0                 # dry mass, tonnes
var cargo_t := 0.0
var thrust_kn := 0.0             # forward thrust at full throttle
var offset_m := 0.0              # thrust line off the centre of mass: less manoeuvring authority
var assist := true               # damp rotation when the pilot lets go
var braking := false             # autopilot: turn retrograde and burn to a stop
## Where the braking autopilot should stop (a run's target), or INF to stop where the ship is. With a
## target it coasts tail-first until it has to burn, then flies down a stopping curve that ends at the
## target, taking out sideways drift on the way.
var brake_to := Vector3.INF
var brake_state := ""            # what the autopilot is doing: turning, coasting, burning or stopping
var brake_burn_in_s := -1.0      # seconds until the stopping burn starts, while coasting
const BRAKE_USE := 0.8           # plan the stop on this fraction of full thrust, to keep some in hand
## Course hold: keeps the direction of travel on `course_to` (a run's target). It steers the nose;
## the pilot keeps the throttle. Burning, it angles the burn to take out sideways drift as well;
## coasting, it makes small trim burns of its own, then points the nose back at the target.
var course_hold := false
var course_to := Vector3.INF
var trimming := false            # course hold is making a trim burn (the pilot's throttle is 0)
const TRIM_MAX := 0.2            # the most throttle a trim burn uses
const DRIFT_OK_M_S := 0.3        # sideways drift below this is left alone
const COURSE_TAU_S := 4.0        # burning, take sideways drift out over about this long
var tune: Dictionary = {}
# Power and heat (flight_physics.json: loads must fit generation; heat_next = heat + generated - rejected).
var power_gen_kw := 0.0
var power_base_kw := 0.0         # everything except the engines
var engine_power_kw := 0.0       # engines at full throttle
var heat_base_kw := 0.0
var engine_heat_kw := 0.0
var cooling_kw := 0.0
var heat_mj := 0.0               # stored heat above ambient
var storm_cooling := 0.0         # share of the radiators' cooling a solar storm is taking away (HazardWatch)
var overheated := false
# Body and trouble
var radius_m := 6.0
var damage := 0.0                # 0..1 of the hull's integrity lost; repaired for money at the dock
## Hull trouble before it's gone (flight_tuning.json "hull_faults"): radiators lose cooling from 75% hull,
## the tanks leak from 50%, and below 25% every knock reaches the cargo. At 0% the ship is disabled:
## no thrust, no lift, no autopilots, nothing but a call to the rescue tug.
var cargo_hurt := 0.0            # 0..1 of the cargo's value spoiled by knocks
var leaked_t := 0.0              # fuel lost through the leak, tonnes (also counted in fuel_burned_t)
var impacts := 0
var bodies: Array = []           # worlds in this frame that the ship can't fly through: [{centre: Vector3, radius: float}]
var crashed_into := ""           # name of the last world (or ship) the ship hit, for the cockpit
var crashed_ship := false        # and whether it was a ship
var last_impact := 0.0           # speed of the latest hit, m/s
var fuel_burned_t := 0.0
var elapsed_s := 0.0
var station_solid := true         # false on a transfer between sites: nothing to hit
# Landing (see data/runtime/landing.json). With `terrain` set the ship flies over a moon: gravity pulls
# it down, the lift jets under the hull push along the ship's +Y, and the feet meet the ground.
var gravity := 0.0                # m/s^2 down (-Y); 0 in space
var terrain: SurfaceTerrain = null
var lift_kn := 0.0                # lift jets at full power
var lift := 0.0                   # 0..1, set every step
var retro_kn := 0.0               # braking thrusters at full power, pushing the ship backward (along +Z)
var retro := 0.0                  # 0..1, set every step: the pilot's B, or the braking autopilot
var rcs_x_kn := 0.0               # manoeuvring thrusters, each way: sideways (ship X)
var rcs_y_kn := 0.0               # and up and down (ship Y)
var strafe := Vector2.ZERO        # -1..1 each, set every step: x right, y up (Ctrl + arrows)
const RETRO_STOP_S := 40.0        # the braking autopilot uses the thrusters, nose on, when they stop the ship within this
var foot_m := 3.0                 # centre of mass down to the feet
var landed := false
var autoland := false             # autopilot: level out, null the drift, settle on the pad
var pad := Vector3.ZERO
var land_cfg: Dictionary = {}
var last_touchdown := 0.0         # vertical speed of the latest touchdown, m/s
var rocks: Array[Vector3] = []     # boulders on the ground (x, z, radius): setting down on one damages the ship
var hazard := ""                   # what went wrong at the latest touchdown on rough ground, or ""
var hazards_seen := 0
# Air (planets with air, Planets): empty in space and over the moon. {density (kg/m³ at y = 0), scale_m,
# cd_flat, cd_nose, heat_k, nose_mult, shed, damage_per_s, shield_cut}. The air presses on the ship's
# three faces (its outline from below, the front and the side, `area`), so belly first it brakes hard and
# nose first it barely slows; and it heats the ship by its density and the cube of the speed.
var air: Dictionary = {}
var wind := Vector3.ZERO           # the air's own movement, m/s (Planets.wind_at, set by the scene)
var area := Vector3(60.0, 100.0, 40.0)   # m²: side (X), belly (Y), front (Z)
var shield := 0.0                  # 0..1 of the belly a heat shield covers
var skin_heat := 0.0               # entry heat, 0 cold .. 1 at the limit; past 1 the hull burns
var skin_peak := 0.0
var burn_s := 0.0                  # seconds spent over the limit
var drag_g := 0.0                  # the air's braking just now, in g (the HUD)
var heat_rate := 0.0               # the heat going into the skin just now (per second): the entry glow
var autoentry := false             # autopilot: belly into the air, glide toward the pad, landing burn, then autoland
var entry_state := ""              # what it's doing: "belly", "glide", "burn"
var entry_burn := false            # the landing burn has started: it carries on until the landing autopilot has her
var sea := false                   # the latest touchdown was in water (PlanetTerrain)


static func load_tuning() -> Dictionary:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(TUNING_PATH))
	return parsed if typeof(parsed) == TYPE_DICTIONARY else {}


## `stats` is ShipStats.compute output; the ship starts with full tanks and whatever cargo `stats` carries.
static func from_stats(stats: Dictionary) -> FlightModel:
	var m := FlightModel.new()
	m.tune = load_tuning()
	m.dry_t = float(stats["dry"])
	m.fuel_t = float(stats["fuel"])
	m.cargo_t = float(stats.get("cargo_mass", 0.0))
	m.thrust_kn = float(stats["thrust_fwd"])
	m.offset_m = float(stats.get("thrust_offset", 0.0))
	m.power_gen_kw = float(stats.get("power_gen", 0.0))
	m.engine_power_kw = float(stats.get("engine_power", 0.0))
	m.power_base_kw = float(stats.get("power_use", 0.0)) - m.engine_power_kw
	m.engine_heat_kw = float(stats.get("engine_heat", 0.0))
	m.heat_base_kw = float(stats.get("heat_gen", 0.0)) - m.engine_heat_kw
	m.cooling_kw = float(stats.get("cooling", 0.0))
	m.radius_m = float(stats.get("radius", 6.0))
	m.lift_kn = float(stats.get("lift", 0.0))
	m.retro_kn = float(stats.get("retro", 0.0))
	m.rcs_x_kn = float(stats.get("rcs_x", 0.0))
	m.rcs_y_kn = float(stats.get("rcs_y", 0.0))
	if stats.has("belly_m2"):
		m.area = Vector3(float(stats.side_m2), float(stats.belly_m2), float(stats.front_m2))
	m.shield = float(stats.get("shield", 0.0))
	if stats.has("foot_y") and stats.has("com"):
		m.foot_m = float((stats["com"] as Vector3).y) - float(stats["foot_y"])
	return m


func mass_t() -> float:
	return dry_t + fuel_t + cargo_t


func has_fuel() -> bool:
	return fuel_t > 0.0001


## How much of the commanded thrust the ship can actually deliver: 1.0 normally, less when the power
## plant cannot feed the engines (brownout), none while overheated, and less with a damaged hull.
func thrust_scale() -> float:
	if overheated or disabled():
		return 0.0
	var demand := power_base_kw + engine_power_kw * throttle
	var power := 1.0 if demand <= power_gen_kw or demand <= 0.0 else power_gen_kw / demand
	return power * (1.0 - damage * float(tune.get("damage_thrust_loss", 0.5)))


## The hull is gone: 0% integrity. Nothing on board answers the helm.
func disabled() -> bool:
	return damage >= 0.999


func _fault(key: String, default: float) -> float:
	return float((tune.get("hull_faults", {}) as Dictionary).get(key, default))


## Hull left, 0..1.
func hull() -> float:
	return clampf(1.0 - damage, 0.0, 1.0)


## How far a fault has got: 0 at the hull level it starts, 1 at 0% hull.
func _fault_level(starts_at_hull: float) -> float:
	return clampf((starts_at_hull - hull()) / maxf(starts_at_hull, 0.001), 0.0, 1.0)


## The radiators still working: cracked panels shed less heat from 75% hull down.
func cooling_now_kw() -> float:
	return cooling_kw * (1.0 - _fault_level(_fault("cooling_from_hull", 0.75)) * _fault("cooling_loss_at_zero", 0.5)) * (1.0 - storm_cooling)


## Tonnes an hour leaking from the tanks: nothing above 50% hull, rising to the full rate at 0%.
func leak_t_per_h() -> float:
	return _fault_level(_fault("leak_from_hull", 0.5)) * _fault("leak_t_per_h_at_zero", 1.5)


## Which faults are live now, for the HUD and the remote.
func faults() -> Array[String]:
	var out: Array[String] = []
	if disabled():
		out.append("disabled")
		return out
	if hull() < _fault("cooling_from_hull", 0.75):
		out.append("cooling")
	if hull() < _fault("leak_from_hull", 0.5):
		out.append("leak")
	if hull() < _fault("cargo_from_hull", 0.25):
		out.append("cargo")
	return out


## Take `amount` of hull. Below 25% hull the cargo takes its share; at 0% the ship is disabled.
func hurt(amount: float) -> void:
	if amount <= 0.0:
		return
	if hull() < _fault("cargo_from_hull", 0.25) and cargo_t > 0.0:
		cargo_hurt = minf(_fault("cargo_hurt_max", 0.6), cargo_hurt + amount * _fault("cargo_hurt_per_damage", 2.0))
	damage = minf(1.0, damage + amount)
	if disabled():
		_shut_down()


func _shut_down() -> void:
	throttle = 0.0
	lift = 0.0
	retro = 0.0
	strafe = Vector2.ZERO
	braking = false
	brake_state = ""
	course_hold = false
	trimming = false
	autoland = false


func heat_capacity_mj() -> float:
	return float(tune.get("heat_capacity_mj_per_t", 60.0)) * mass_t()


## 0 cold .. 1 at the limit.
func heat_fraction() -> float:
	return heat_mj / heat_capacity_mj()


## Forward acceleration at the current throttle, m/s^2.
func accel() -> float:
	return thrust_kn * 1000.0 * throttle * thrust_scale() / (mass_t() * 1000.0) if has_fuel() else 0.0


func max_accel() -> float:
	return thrust_kn / mass_t() if mass_t() > 0.0 else 0.0   # kN / t = m/s^2


func forward() -> Vector3:
	return -basis.z


func speed() -> float:
	return vel.length()


## What the tanks can still change the ship's speed by, from the rocket equation, m/s.
func delta_v() -> float:
	var dry := dry_t + cargo_t
	return float(tune.get("isp_s", 900.0)) * G0 * log(mass_t() / dry) if fuel_t > 0.0 and dry > 0.0 else 0.0


## Seconds of full burn left.
func burn_seconds() -> float:
	var flow := _flow_kg_s(1.0)
	return fuel_t * 1000.0 / flow if flow > 0.0 else 0.0


func _flow_kg_s(thr: float) -> float:
	return thrust_kn * 1000.0 * thr / (float(tune.get("isp_s", 900.0)) * G0)


func _lift_flow_kg_s(l: float) -> float:
	return lift_kn * 1000.0 * l / (float(tune.get("isp_s", 900.0)) * G0)


## m/s^2 the lift jets can give at full power, now.
func lift_accel() -> float:
	return lift_kn / mass_t() if mass_t() > 0.0 else 0.0


## True when the lift jets can hold this ship up here with the margin landing.json asks for.
func can_hover() -> bool:
	return gravity <= 0.0 or lift_accel() >= gravity * float(land_cfg.get("min_lift_margin", 1.15))


## Height of the feet above the ground below, metres (INF away from a surface).
func altitude() -> float:
	if terrain == null:
		return INF
	return pos.y - foot_m - terrain.height(pos.x, pos.z)


func tilt_deg() -> float:
	return rad_to_deg(basis.y.angle_to(Vector3.UP))


var zone_m := 0.0                 # how close to `pad` counts as on it (0: landing.json's landing_zone_m)


func on_pad() -> bool:
	var zone := zone_m if zone_m > 0.0 else float(land_cfg.get("landing_zone_m", 120.0))
	return landed and Vector2(pos.x - pad.x, pos.z - pad.z).length() <= zone


func _turn_accel() -> float:
	var ref := float(tune.get("reference_mass_t", 20.0))
	var scale := pow(ref / maxf(mass_t(), 0.1), float(tune.get("turn_mass_exponent", 0.5)))
	var authority := 1.0 / (1.0 + float(tune.get("offset_penalty_per_m", 0.12)) * offset_m)
	return float(tune.get("turn_accel_rad_s2", 0.9)) * scale * authority


func _max_turn() -> float:
	return float(tune.get("max_turn_rate_rad_s", 1.1))


## Advance by `dt` seconds. `turn` is the pilot's pitch/yaw/roll command, each -1..1; `throttle_cmd` is
## -1 (ease off), 0 (hold) or +1 (open up), applied at throttle_rate_per_s.
func step(dt: float, turn: Vector3 = Vector3.ZERO, throttle_cmd: float = 0.0, lift_cmd: float = 0.0, retro_cmd: float = 0.0, strafe_cmd := Vector2.ZERO) -> void:
	if trimming:
		throttle = 0.0   # a trim burn was course hold's, not the pilot's: back to their closed throttle
		trimming = false
	throttle = clampf(throttle + throttle_cmd * float(tune.get("throttle_rate_per_s", 0.8)) * dt, 0.0, 1.0)
	var cmd := turn
	lift = clampf(lift_cmd, 0.0, 1.0)
	retro = clampf(retro_cmd, 0.0, 1.0) if retro_kn > 0.0 else 0.0
	strafe = Vector2(clampf(strafe_cmd.x, -1.0, 1.0) if rcs_x_kn > 0.0 else 0.0, clampf(strafe_cmd.y, -1.0, 1.0) if rcs_y_kn > 0.0 else 0.0)
	if disabled():
		_shut_down()
		cmd = Vector3.ZERO
	_leak(dt)
	if braking:
		var auto := _brake(dt)
		cmd = auto["turn"]
		throttle = auto["throttle"]
		retro = float(auto.get("retro", 0.0))
		if auto.has("strafe"):
			strafe = auto["strafe"]
	if course_hold and not braking and course_to != Vector3.INF:
		var ch := _course()
		cmd = ch["turn"]
		if ch.has("throttle"):
			throttle = ch["throttle"]
			trimming = true
	if autoentry and terrain != null and not air.is_empty():
		var ae := _autoentry()
		cmd = ae["turn"]
		lift = ae["lift"]
		throttle = 0.0
	if autoland and terrain != null:
		var al := _autoland()
		cmd = al["turn"]
		lift = al["lift"]
		throttle = 0.0
	if landed:
		# Standing on the legs: nothing moves until the jets can lift the ship off.
		var up := lift * lift_accel() * thrust_scale() if has_fuel() else 0.0
		if up <= gravity * 1.02 and throttle <= 0.0:
			vel = Vector3.ZERO
			ang = Vector3.ZERO
			lift = 0.0
			_leak(0.0)
			_heat(dt)
			elapsed_s += dt
			return
		landed = false
	# Rotation: move the angular rate toward what the pilot (or the assist) asks for.
	var want := cmd * _max_turn()
	var a := _turn_accel() * dt
	for i in 3:
		if not disabled() and (cmd[i] != 0.0 or assist or braking or autoland or course_hold):
			ang[i] = move_toward(ang[i], want[i], a)
	if ang.length() > 0.0:
		basis = (basis * Basis(ang.normalized(), ang.length() * dt)).orthonormalized()
	# Thrust: burns fuel, and the ship gets lighter as it goes. A brownout, overheating or a battered
	# hull cuts the push (and the burn with it).
	var scale := thrust_scale()
	if has_fuel() and throttle > 0.0 and scale > 0.0:
		var want_burn := _flow_kg_s(throttle * scale) * dt / 1000.0
		var burn := minf(want_burn, fuel_t)
		var effective := burn / want_burn if want_burn > 0.0 else 0.0
		vel += forward() * (thrust_kn / mass_t()) * throttle * scale * effective * dt
		fuel_t -= burn
		fuel_burned_t += burn
	else:
		if not has_fuel():
			fuel_t = 0.0
			throttle = 0.0
	if retro > 0.0 and has_fuel() and scale > 0.0:   # braking thrusters: push backward, burn like the rest
		var want_r := retro_kn * 1000.0 * retro * scale / (float(tune.get("isp_s", 900.0)) * G0) * dt / 1000.0
		var burn_r := minf(want_r, fuel_t)
		var eff_r := burn_r / want_r if want_r > 0.0 else 0.0
		vel -= forward() * (retro_kn / mass_t()) * retro * scale * eff_r * dt
		fuel_t -= burn_r
		fuel_burned_t += burn_r
	if strafe != Vector2.ZERO and has_fuel() and scale > 0.0 and not landed:   # manoeuvring thrusters
		var kn := absf(strafe.x) * rcs_x_kn + absf(strafe.y) * rcs_y_kn
		var want_s := kn * 1000.0 * scale / (float(tune.get("isp_s", 900.0)) * G0) * dt / 1000.0
		var burn_s := minf(want_s, fuel_t)
		var eff_s := burn_s / want_s if want_s > 0.0 else 0.0
		vel += (basis.x * strafe.x * rcs_x_kn + basis.y * strafe.y * rcs_y_kn) / mass_t() * scale * eff_s * dt
		fuel_t -= burn_s
		fuel_burned_t += burn_s
	if lift > 0.0 and has_fuel() and lift_kn > 0.0 and scale > 0.0:
		var want_l := _lift_flow_kg_s(lift * scale) * dt / 1000.0
		var burn_l := minf(want_l, fuel_t)
		var eff_l := burn_l / want_l if want_l > 0.0 else 0.0
		vel += basis.y * (lift_kn / mass_t()) * lift * scale * eff_l * dt
		fuel_t -= burn_l
		fuel_burned_t += burn_l
	if not air.is_empty():
		_aero(dt)
	if gravity > 0.0:
		vel.y -= gravity * dt
	_heat(dt)
	pos += vel * dt
	if station_solid:
		_collide()
	if not bodies.is_empty():
		_collide_bodies()
	if terrain != null:
		_ground()
	elapsed_s += dt


## The feet meet the ground. Slow, level and not drifting is a landing; anything else is a hard landing
## that costs hull and bounces.
func _ground() -> void:
	var g := terrain.height(pos.x, pos.z)
	if pos.y - foot_m > g:
		return
	var down := -vel.y
	var drift := Vector2(vel.x, vel.z).length()
	var tilt := tilt_deg()
	pos.y = g + foot_m
	if down <= 0.0 and drift < 0.2:
		return
	var ok_v := float(land_cfg.get("touchdown_speed_m_s", 3.0))
	var ok_h := float(land_cfg.get("touchdown_drift_m_s", 2.0))
	var ok_t := float(land_cfg.get("touchdown_tilt_deg", 15.0))
	last_touchdown = maxf(down, 0.0)
	sea = terrain.has_method("is_water") and terrain.call("is_water", pos.x, pos.z)
	if sea:   # down in the water: it floats, more or less, and the sea gets in
		landed = true
		autoland = false
		autoentry = false
		last_touchdown = maxf(down, 0.0)
		impacts += 1
		last_impact = down
		hurt(float(land_cfg.get("sea_damage", 0.25)) + maxf(down - ok_v, 0.0) * float(land_cfg.get("hard_landing_damage_per_m_s", 0.04)))
		hazard = "Down in the sea. It floats, for now. The crawler's a boat today, and charges like one"
		hazards_seen += 1
		vel = Vector3.ZERO
		ang = Vector3.ZERO
		return
	if down <= ok_v and drift <= ok_h and tilt <= ok_t:
		landed = true
		autoentry = false
		autoland = false
		vel = Vector3.ZERO
		ang = Vector3.ZERO
		var heading := Vector3(basis.z.x, 0, basis.z.z)
		if heading.length() < 0.01:
			heading = Vector3(0, 0, 1)
		basis = Basis.looking_at(-heading.normalized(), Vector3.UP)   # settle level on the legs
		_rough_ground()
		return
	impacts += 1
	last_impact = down
	hurt(maxf(down - ok_v, 0.0) * float(land_cfg.get("hard_landing_damage_per_m_s", 0.04))
			+ maxf(drift - ok_h, 0.0) * float(land_cfg.get("hard_landing_damage_per_m_s", 0.04)) * 0.5
			+ maxf(tilt - ok_t, 0.0) * float(land_cfg.get("tilt_damage_per_deg", 0.004)))
	vel.y = maxf(down, 0.0) * 0.2
	vel.x *= 0.5
	vel.z *= 0.5


## A clean touchdown can still go wrong off the pads: on a boulder, or on a slope the legs cannot hold.
func _rough_ground() -> void:
	var sc: Dictionary = land_cfg.get("sites", {})
	var foot := float(sc.get("ship_footprint_m", 3.0))
	for r in rocks:
		if Vector2(pos.x - r.x, pos.z - r.y).length() < r.z + foot:
			hurt(float(sc.get("boulder_damage", 0.12)))
			hazard = "Set down on a boulder. The legs took it personally"
			hazards_seen += 1
			impacts += 1
			return
	var slope := SurfaceSites.slope_deg(terrain, pos.x, pos.z)
	var lim := float(sc.get("land_slope_deg", 10.0))
	if slope > lim:
		hurt((slope - lim) * float(sc.get("slope_damage_per_deg", 0.012)))
		hazard = "Landed on a %d° slope: slid and scraped. Pick flatter rock" % roundi(slope)
		hazards_seen += 1
		impacts += 1


## Autopilot landing: hold altitude while flying over the pad, then come straight down, slowing as the
## ground nears. It steers by tilting the ship so the lift jets push it sideways, like a helicopter.
func _autoland() -> Dictionary:
	var g := gravity
	var to_pad := Vector2(pad.x - pos.x, pad.z - pos.z)
	var v_h := Vector2(vel.x, vel.z)
	var cruise := float(land_cfg.get("autoland_cruise_m_s", 15.0))
	var want_vh := to_pad * 0.06
	if want_vh.length() > cruise:
		want_vh = want_vh.normalized() * cruise
	var a_h := (want_vh - v_h) * 0.6
	if a_h.length() > 2.0:
		a_h = a_h.normalized() * 2.0
	var alt := altitude()
	var want_vy := 0.0
	if to_pad.length() > 40.0:
		var a_net0 := maxf(lift_accel() * 0.85 - g, 0.05)
		want_vy = clampf((150.0 - alt) * 0.15, -minf(12.0, sqrt(2.0 * a_net0 * maxf(alt - 150.0, 0.0)) * 0.7 + 1.0), 4.0)   # cruise over at about 150 m
	else:
		# Then down, never faster than the lift jets can stop from at this height, gently at the end.
		var a_net := maxf(lift_accel() * 0.85 - g, 0.05)
		want_vy = -clampf(minf(alt * 0.12, sqrt(2.0 * a_net * maxf(alt - 1.0, 0.0)) * 0.7), 0.8, 20.0)
	var a_v := (want_vy - vel.y) * 0.9
	var t := Vector3(a_h.x, a_v + g, a_h.y)
	var max_tilt := deg_to_rad(float(land_cfg.get("autoland_max_tilt_deg", 25.0)))
	if t.y < 0.1:
		t.y = 0.1
	var up_want := t.normalized()
	if up_want.angle_to(Vector3.UP) > max_tilt:
		var horiz := Vector3(up_want.x, 0, up_want.z).normalized()
		up_want = (Vector3.UP * cos(max_tilt) + horiz * sin(max_tilt)).normalized()
	if alt < 3.0:
		up_want = Vector3.UP        # last few metres: level for the legs
	var turn := Vector3.ZERO
	var up_now := basis.y
	var angle := up_now.angle_to(up_want)
	if angle > 0.002:
		var axis_local := basis.inverse() * up_now.cross(up_want)
		if axis_local.length() > 0.0001:
			var rate := sqrt(2.0 * _turn_accel() * angle) / _max_turn()
			turn = axis_local.normalized() * clampf(rate, 0.0, 1.0)
	# Damp any yaw spin; heading does not matter.
	turn.y = -clampf(ang.y, -1.0, 1.0)
	var need := t.dot(up_now) * mass_t() / maxf(lift_kn, 0.001)
	return {"turn": turn, "lift": clampf(need, 0.0, 1.0)}


## Air density where the ship is, kg/m³ (0 with no air).
func air_density() -> float:
	if air.is_empty():
		return 0.0
	return float(air.density) * exp(-maxf(pos.y, 0.0) / float(air.get("scale_m", 8500.0)))


## How fast the ship moves through the air (not over the ground), m/s.
func airspeed() -> float:
	return (vel - wind).length()


## How square the belly is to the air: 1 flat on, belly first; 0 edge on; negative with the top into it.
func belly_to_air() -> float:
	var va := vel - wind
	if va.length() < 0.5:
		return 1.0
	return -(basis.inverse() * va.normalized()).y


## The air pressing on the ship's faces, and the heat it puts into the skin.
func _aero(dt: float) -> void:
	var va := vel - wind
	var v := va.length()
	var rho := air_density()
	if v < 0.01 or rho <= 0.0:
		drag_g = 0.0
		heat_rate = 0.0
		skin_heat = maxf(0.0, skin_heat - float(air.get("shed", 0.012)) * skin_heat * dt)
		return
	var loc := basis.inverse() * va
	var cf := float(air.get("cd_flat", 1.15))
	var cn := float(air.get("cd_nose", 0.45))
	var f := -0.5 * rho * Vector3(cf * area.x * loc.x * absf(loc.x), cf * area.y * loc.y * absf(loc.y), cn * area.z * loc.z * absf(loc.z))
	var acc := basis * f / (mass_t() * 1000.0)
	var dv := acc * dt
	if dv.length() > v:   # never push it past standing still in the air
		dv = dv.normalized() * v
	vel += dv
	drag_g = acc.length() / G0
	if landed:
		return
	var s := loc / v
	var belly := maxf(0.0, -s.y)
	var q := float(air.get("heat_k", 5.3e-11)) * sqrt(rho) * v * v * v * (1.0 + (float(air.get("nose_mult", 1.7)) - 1.0) * s.z * s.z)
	q *= 1.0 - float(air.get("shield_cut", 0.55)) * shield * belly * belly
	heat_rate = q
	skin_heat = maxf(0.0, skin_heat + (q - float(air.get("shed", 0.012)) * skin_heat) * dt)
	skin_peak = maxf(skin_peak, skin_heat)
	if skin_heat > 1.0:
		burn_s += dt
		hurt(float(air.get("damage_per_s", 0.02)) * (skin_heat - 1.0) * dt)


## Coming down through air on autopilot: belly into the airflow to brake on the air, then, falling slowly
## enough, tilt toward the pad so the air pushes the ship over to it; light the lift jets in time to stop
## (belly first they push against the fall), and hand over to the landing autopilot low and slow.
func _autoentry() -> Dictionary:
	var va := vel - wind
	var v := va.length()
	var alt := altitude()
	var to := Vector3(pad.x - pos.x, 0, pad.z - pos.z)
	var want_up := -va.normalized() if v > 1.0 else Vector3.UP
	entry_state = "belly"
	var a_lift := lift_accel() * 0.85
	var down := maxf(-vel.y, 0.0)
	var a_net := a_lift - gravity
	if v < 320.0 and to.length() > 60.0:   # slow enough to steer: lean the belly toward the pad
		entry_state = "glide"
		var tilt := deg_to_rad(28.0) * clampf(to.length() / 2500.0, 0.0, 1.0)
		want_up = (want_up * cos(tilt) + to.normalized() * sin(tilt)).normalized()
	var lift_cmd := 0.0
	# The landing burn: the jets have to take the fall out by about 250 m up. The air helps: half of what
	# it's braking by now is counted on (in thick air that is plenty, and the burn waits; in thin air it
	# isn't, and the burn starts high). Burning, the ship leans to kill its drift toward the pad as well.
	var v_h0 := Vector2(vel.x, vel.z).length()
	var thin := float(air.get("density", 1.0)) < 0.2   # air too thin to brake on (Mars)
	if not entry_burn and (burn_due(alt, down) or (thin and v > 320.0 and to.length() <= v_h0 * v_h0 / maxf(lift_accel(), 0.5) * 1.1 + 800.0)):
		entry_burn = true   # thin air: the jets have to take the speed off over the ground too
	if entry_burn:
		entry_state = "burn"
		var a_full := maxf(lift_accel(), 0.01)
		var want_dn := gravity + down * down / (2.0 * maxf(alt - 200.0, 30.0))
		var v_h := Vector3(vel.x, 0, vel.z)
		var reach_v := to.normalized() * minf(sqrt(2.0 * 3.0 * to.length()) * 0.8, 120.0) if to.length() > 20.0 else Vector3.ZERO
		var a_h := (reach_v - v_h) * 0.35
		var room := sqrt(maxf(a_full * a_full * 0.85 * 0.85 - want_dn * want_dn, 0.0))
		if a_h.length() > room:
			a_h = a_h.normalized() * room
		var a_want := Vector3(a_h.x, maxf(want_dn, 0.1), a_h.z)
		want_up = a_want.normalized()
		if want_up.angle_to(Vector3.UP) > deg_to_rad(50.0):
			var hz := Vector3(want_up.x, 0, want_up.z).normalized()
			want_up = (Vector3.UP * cos(deg_to_rad(50.0)) + hz * sin(deg_to_rad(50.0))).normalized()
		lift_cmd = clampf(a_want.length() / a_full, 0.0, 1.0) if a_net > 0.2 else 1.0
	if (alt < 450.0 and down < 22.0 and Vector2(vel.x, vel.z).length() < 40.0) or alt < 120.0:
		autoentry = false
		entry_burn = false
		autoland = true   # low and slow: the landing autopilot has it from here
		entry_state = ""
	var turn := Vector3.ZERO
	var up_now := basis.y
	var angle := up_now.angle_to(want_up)
	if angle > 0.002:
		var axis_local := basis.inverse() * up_now.cross(want_up)
		if axis_local.length() > 0.0001:
			var rate := sqrt(2.0 * _turn_accel() * angle) / _max_turn()
			turn = axis_local.normalized() * clampf(rate, 0.0, 1.0)
	turn.y = -clampf(ang.y, -1.0, 1.0)
	return {"turn": turn, "lift": lift_cmd}


## Whether the landing burn has to start now, falling `down` m/s at `alt` m: the jets (and half the air's
## braking) must stop the fall by about 250 m up. A ship whose jets can't hold it up burns from 2 km
## anyway, for what that's worth.
func burn_due(alt: float, down: float) -> bool:
	if not air.is_empty() and float(air.get("density", 1.0)) >= 0.2 and alt > 6000.0:
		return false   # thick air brakes the fall far better than the jets up here: wait for it
	var a_net := lift_accel() * 0.85 - gravity
	if a_net <= 0.2:
		return alt < 2000.0
	return alt <= down * down / (2.0 * (a_net + 0.5 * drag_g * G0) * 0.8) + 250.0


## Autopilot. Without a target: point at the retrograde marker and burn in proportion to the speed
## left. With one (brake_to) and closing on it: hold tail-first, coast while there is room, then burn
## to follow the stopping curve v = sqrt(2 a d) down to the target, steering out any sideways drift.
func _brake(dt: float) -> Dictionary:
	var spd := vel.length()
	brake_burn_in_s = -1.0
	var want := Vector3.ZERO     # the velocity change the autopilot wants
	var a_max := maxf(max_accel(), 0.001)
	var to := brake_to - pos if brake_to != Vector3.INF else Vector3.ZERO
	var closing := vel.dot(to.normalized()) if to.length() > 1.0 else 0.0
	if brake_to != Vector3.INF and closing > 1.0:
		var dist := maxf(to.length() - 300.0, 1.0)          # aim a little short of the mark
		var a_plan := a_max * BRAKE_USE
		var v_curve := sqrt(2.0 * a_plan * dist)            # fastest speed that can still stop in time
		var desired := to.normalized() * minf(v_curve, closing)   # never speed up: only slow and straighten
		want = desired - vel
		if want.length() < 0.5:
			brake_state = "coasting"
			brake_burn_in_s = maxf(0.0, (to.length() - closing * closing / (2.0 * a_plan)) / closing)
			want = -vel       # stay tail-first, ready
			return _brake_steer(want, 0.0, "coasting")
		return _brake_steer(want, clampf(want.length() / (a_max * 1.0), 0.04, 1.0), "burning")
	if spd < float(tune.get("stop_speed_m_s", 0.15)):
		vel = Vector3.ZERO
		braking = false
		brake_state = ""
		return {"turn": Vector3.ZERO, "throttle": 0.0}
	# Moving roughly nose-first and slow enough for the braking thrusters: stop on them, nose on, rather
	# than turning tail-first (a docking approach stays lined up).
	var a_retro := retro_kn / mass_t() if mass_t() > 0.0 else 0.0
	if a_retro > 0.0 and vel.dot(forward()) > 0.0 and rad_to_deg(forward().angle_to(vel)) < 30.0 and spd / a_retro < RETRO_STOP_S:
		brake_state = "retro"
		# Manoeuvring thrusters, if fitted, take out the sideways drift at the same time.
		var side := Vector2(vel.dot(basis.x), vel.dot(basis.y))
		var st := Vector2.ZERO
		if rcs_x_kn > 0.0 and absf(side.x) > 0.05:
			st.x = -clampf(side.x / (rcs_x_kn / mass_t() * 1.5), -1.0, 1.0)
		if rcs_y_kn > 0.0 and absf(side.y) > 0.05:
			st.y = -clampf(side.y / (rcs_y_kn / mass_t() * 1.5), -1.0, 1.0)
		return {"turn": Vector3.ZERO, "throttle": 0.0, "retro": clampf(spd / (a_retro * 1.5), 0.05, 1.0), "strafe": st}
	return _brake_steer(-vel, clampf(spd / (a_max * 1.5), 0.04, 1.0), "stopping")


## Turn to burn along `want` and give `thr` once lined up (within about 7 degrees).
func _brake_steer(want: Vector3, thr: float, state: String) -> Dictionary:
	var p := _point(want)
	brake_state = state if p.angle < 0.12 else "turning"
	return {"turn": p.turn, "throttle": thr if p.angle < 0.12 else 0.0}


## The turn command that brings the nose round onto `want`, easing in so it settles rather than
## overshooting, and the angle still to go: {turn, angle}.
func _point(want: Vector3) -> Dictionary:
	var local := basis.inverse() * want.normalized()   # where to point in ship axes (-Z is forward)
	var fwd := Vector3(0, 0, -1)
	var axis := fwd.cross(local)                       # rotation (ship axes) that takes forward onto it
	var angle := fwd.angle_to(local)
	var turn := Vector3.ZERO
	if angle > 0.002:
		var stop_rate := sqrt(2.0 * _turn_accel() * angle) / _max_turn()
		var dir := axis.normalized() if axis.length() > 0.0001 else Vector3(1, 0, 0)
		turn = dir * clampf(stop_rate, 0.0, 1.0)
		# Our axes are pitch=X, yaw=Y, roll=Z in the ship's frame, so the rotation vector maps straight on.
	return {"turn": turn, "angle": angle}


## Course hold. Burning (the pilot's throttle open): point where the burn both speeds the ship toward
## the target and cancels its sideways drift. Coasting: if it is drifting, turn across the drift and
## trim it out with a small burn; otherwise rest the nose on the target. {turn, throttle?}
func _course() -> Dictionary:
	var to := course_to - pos
	if to.length() < 1.0:
		return {"turn": Vector3.ZERO}
	var dir := to.normalized()
	var closing := vel.dot(dir)
	var drift := vel - dir * maxf(closing, 0.0)          # everything that isn't heading for the target
	if throttle > 0.0:
		# Spend the push on the drift first (taking it out over about COURSE_TAU_S), the rest toward
		# the target: the burn swings the travel onto the target as it speeds the ship up.
		var a_max := maxf(max_accel() * throttle, 0.001)
		var side := -drift / COURSE_TAU_S
		if side.length() > a_max:
			side = side.normalized() * a_max
		var ahead := sqrt(maxf(a_max * a_max - side.length_squared(), 0.0))
		return {"turn": _point(side + dir * maxf(ahead, a_max * 0.05))["turn"]}
	if drift.length() > DRIFT_OK_M_S:
		var p := _point(-drift)
		var thr := clampf(drift.length() / (maxf(max_accel(), 0.001) * 2.0), 0.02, TRIM_MAX) if p.angle < 0.12 else 0.0
		return {"turn": p.turn, "throttle": thr}
	return {"turn": _point(dir)["turn"]}


## The angle in degrees between where the nose points and the direction to `at`.
func aim_error_deg(at: Vector3) -> float:
	var to := at - pos
	return rad_to_deg(forward().angle_to(to)) if to.length() > 1.0 else 0.0


## Where the ship starts when it leaves the dock: well clear, at rest, facing away from the station.
func place_at_dock(direction: Vector3 = Vector3(0, 0, 1)) -> void:
	var d := direction.normalized()
	pos = d * float(tune.get("start_distance_m", 140.0))
	vel = Vector3.ZERO
	ang = Vector3.ZERO
	throttle = 0.0
	braking = false
	basis = Basis.looking_at(d, Vector3.UP)    # forward (-Z) points along d, away from the station


## Fuel lost through a cracked tank. Counted as burned: it was paid for, and now it's space's.
func _leak(dt: float) -> void:
	var rate := leak_t_per_h()
	if rate <= 0.0 or fuel_t <= 0.0 or dt <= 0.0:
		return
	var lost := minf(fuel_t, rate * dt / 3600.0)
	fuel_t -= lost
	fuel_burned_t += lost
	leaked_t += lost


## Heat builds when the ship makes more than its radiators shed. Past the limit the engines shut down
## until it has cooled to the restart level.
func _heat(dt: float) -> void:
	var made := heat_base_kw + engine_heat_kw * throttle
	heat_mj = maxf(0.0, heat_mj + (made - cooling_now_kw()) * dt / 1000.0)   # kW x s = kJ -> MJ
	var cap := heat_capacity_mj()
	if heat_mj >= cap:
		overheated = true
		throttle = 0.0
	elif overheated and heat_mj <= cap * float(tune.get("restart_heat_fraction", 0.6)):
		overheated = false


## Extra solid parts of the station (axis-aligned boxes in its frame), set by the flight scene.
var station_boxes: Array[AABB] = []


## Station shapes in the station's own frame: a spine along Z, a ring in the XY plane, and boxes.
func station_clearance(p: Vector3) -> Dictionary:
	var half := float(tune.get("station_half_length_m", 30.0))
	var spine_r := float(tune.get("station_spine_radius_m", 5.0))
	var on_axis := Vector3(0, 0, clampf(p.z, -half, half))
	var to_spine := p - on_axis
	var d_spine := to_spine.length() - spine_r
	var ring_r := float(tune.get("station_ring_radius_m", 24.5))
	var ring_tube := float(tune.get("station_ring_tube_m", 1.8))
	var in_plane := Vector3(p.x, p.y, 0)
	var nearest := in_plane.normalized() * ring_r if in_plane.length() > 0.001 else Vector3(ring_r, 0, 0)
	var to_ring := p - nearest
	var d_ring := to_ring.length() - ring_tube
	var best := {"gap": d_spine, "normal": to_spine.normalized() if to_spine.length() > 0.001 else Vector3(0, 0, 1)}
	if d_ring < d_spine:
		best = {"gap": d_ring, "normal": to_ring.normalized() if to_ring.length() > 0.001 else Vector3(1, 0, 0)}
	for box in station_boxes:   # the station's other modules: cargo stacks, solar wings, berthed ships
		var q := p.clamp(box.position, box.end)
		var off := p - q
		var gap := off.length()
		if gap == 0.0:   # inside: out through the nearest face
			var to_min := p - box.position
			var to_max := box.end - p
			var faces := [to_min.x, to_max.x, to_min.y, to_max.y, to_min.z, to_max.z]
			var k := 0
			for i in 6:
				if faces[i] < faces[k]:
					k = i
			gap = -float(faces[k])
			off = [Vector3.LEFT, Vector3.RIGHT, Vector3.DOWN, Vector3.UP, Vector3.FORWARD, Vector3.BACK][k]
		if gap < float(best.gap):
			best = {"gap": gap, "normal": off.normalized()}
	return best


## Hitting the station: bounce off, lose some hull in proportion to the impact.
func _collide() -> void:
	var body := radius_m * float(tune.get("collision_radius_fraction", 0.5))
	var c := station_clearance(pos)
	if float(c.gap) >= body:
		return
	var n: Vector3 = c.normal
	var into := -vel.dot(n)
	pos += n * (body - float(c.gap))                     # back out of the structure
	if into <= 0.0:
		return
	vel += n * into * (1.0 + float(tune.get("restitution", 0.25)))
	last_impact = into
	var soft := float(tune.get("soft_impact_m_s", 1.5))
	if into > soft:
		impacts += 1
		hurt((into - soft) * float(tune.get("damage_per_m_s", 0.02)))


## Worlds are solid: a ship that reaches one's surface is pushed back out, bounces off it the way it
## would off the station, and takes the same damage for the speed it hit at. At orbital speeds that's
## the hull, all of it.
func _collide_bodies() -> void:
	var body := radius_m * float(tune.get("collision_radius_fraction", 0.5))
	for b in bodies:
		var off: Vector3 = pos - (b.centre as Vector3)
		var r := float(b.radius) + body
		if off.length() >= r or off.length() < 0.001:
			continue
		var n := off.normalized()
		pos = (b.centre as Vector3) + n * r
		var into := -vel.dot(n)
		if into <= 0.0:
			continue
		vel += n * into * (1.0 + float(tune.get("restitution", 0.25)))
		last_impact = into
		crashed_into = String(b.get("name", "the planet"))
		crashed_ship = bool(b.get("ship", false))
		var soft := float(tune.get("soft_impact_m_s", 1.5))
		if into > soft:
			impacts += 1
			hurt((into - soft) * float(tune.get("damage_per_m_s", 0.02)))


## The mooring point in front of the station's docking collar.
func port_pos() -> Vector3:
	return Vector3(0, 0, float(tune.get("port_z_m", 38.0)))


## Docking: nose toward the collar along the station's axis, slow, and close enough.
func dock_alignment() -> Dictionary:
	var rel := pos - port_pos()
	var lateral := Vector2(rel.x, rel.y).length()
	var nose := forward().angle_to(Vector3(0, 0, -1))
	return {"distance": rel.length(), "lateral": lateral, "nose_deg": rad_to_deg(nose)}


func can_dock() -> bool:
	var a := dock_alignment()
	return a.distance <= float(tune.get("dock_range_m", 30.0)) and a.lateral <= float(tune.get("dock_lateral_m", 8.0)) \
			and a.nose_deg <= float(tune.get("dock_nose_deg", 25.0)) and vel.length() <= float(tune.get("dock_speed_m_s", 3.0))
