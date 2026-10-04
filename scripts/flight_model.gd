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
var tune: Dictionary = {}
# Power and heat (flight_physics.json: loads must fit generation; heat_next = heat + generated - rejected).
var power_gen_kw := 0.0
var power_base_kw := 0.0         # everything except the engines
var engine_power_kw := 0.0       # engines at full throttle
var heat_base_kw := 0.0
var engine_heat_kw := 0.0
var cooling_kw := 0.0
var heat_mj := 0.0               # stored heat above ambient
var overheated := false
# Body and trouble
var radius_m := 6.0
var damage := 0.0                # 0..1 of the hull's integrity lost; repaired for money at the dock
var impacts := 0
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
var foot_m := 3.0                 # centre of mass down to the feet
var landed := false
var autoland := false             # autopilot: level out, null the drift, settle on the pad
var pad := Vector3.ZERO
var land_cfg: Dictionary = {}
var last_touchdown := 0.0         # vertical speed of the latest touchdown, m/s


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
	if overheated:
		return 0.0
	var demand := power_base_kw + engine_power_kw * throttle
	var power := 1.0 if demand <= power_gen_kw or demand <= 0.0 else power_gen_kw / demand
	return power * (1.0 - damage * float(tune.get("damage_thrust_loss", 0.5)))


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
func step(dt: float, turn: Vector3 = Vector3.ZERO, throttle_cmd: float = 0.0, lift_cmd: float = 0.0) -> void:
	throttle = clampf(throttle + throttle_cmd * float(tune.get("throttle_rate_per_s", 0.8)) * dt, 0.0, 1.0)
	var cmd := turn
	lift = clampf(lift_cmd, 0.0, 1.0)
	if braking:
		var auto := _brake(dt)
		cmd = auto["turn"]
		throttle = auto["throttle"]
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
			_heat(dt)
			elapsed_s += dt
			return
		landed = false
	# Rotation: move the angular rate toward what the pilot (or the assist) asks for.
	var want := cmd * _max_turn()
	var a := _turn_accel() * dt
	for i in 3:
		if cmd[i] != 0.0 or assist or braking or autoland:
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
	if lift > 0.0 and has_fuel() and lift_kn > 0.0 and scale > 0.0:
		var want_l := _lift_flow_kg_s(lift * scale) * dt / 1000.0
		var burn_l := minf(want_l, fuel_t)
		var eff_l := burn_l / want_l if want_l > 0.0 else 0.0
		vel += basis.y * (lift_kn / mass_t()) * lift * scale * eff_l * dt
		fuel_t -= burn_l
		fuel_burned_t += burn_l
	if gravity > 0.0:
		vel.y -= gravity * dt
	_heat(dt)
	pos += vel * dt
	if station_solid:
		_collide()
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
	if down <= ok_v and drift <= ok_h and tilt <= ok_t:
		landed = true
		autoland = false
		vel = Vector3.ZERO
		ang = Vector3.ZERO
		var heading := Vector3(basis.z.x, 0, basis.z.z)
		if heading.length() < 0.01:
			heading = Vector3(0, 0, 1)
		basis = Basis.looking_at(-heading.normalized(), Vector3.UP)   # settle level on the legs
		return
	impacts += 1
	last_impact = down
	damage = minf(1.0, damage + maxf(down - ok_v, 0.0) * float(land_cfg.get("hard_landing_damage_per_m_s", 0.04))
			+ maxf(drift - ok_h, 0.0) * float(land_cfg.get("hard_landing_damage_per_m_s", 0.04)) * 0.5
			+ maxf(tilt - ok_t, 0.0) * float(land_cfg.get("tilt_damage_per_deg", 0.004)))
	vel.y = maxf(down, 0.0) * 0.2
	vel.x *= 0.5
	vel.z *= 0.5


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


## Autopilot: point at the retrograde marker, then burn in proportion to the speed left.
func _brake(dt: float) -> Dictionary:
	var spd := vel.length()
	if spd < float(tune.get("stop_speed_m_s", 0.15)):
		vel = Vector3.ZERO
		braking = false
		return {"turn": Vector3.ZERO, "throttle": 0.0}
	var want := (-vel).normalized()
	var local := basis.inverse() * want                 # where retrograde is in ship axes (-Z is forward)
	var fwd := Vector3(0, 0, -1)
	var axis := fwd.cross(local)                       # rotation (ship axes) that takes forward onto retrograde
	var angle := fwd.angle_to(local)
	var turn := Vector3.ZERO
	if angle > 0.002:
		# Ease the turn so it settles instead of overshooting: command the rate the remaining angle allows.
		var stop_rate := sqrt(2.0 * _turn_accel() * angle) / _max_turn()
		var dir := axis.normalized() if axis.length() > 0.0001 else Vector3(1, 0, 0)
		turn = dir * clampf(stop_rate, 0.0, 1.0)
		# Our axes are pitch=X, yaw=Y, roll=Z in the ship's frame, so the rotation vector maps straight on.
	var thr := 0.0
	if angle < 0.12:
		var a_max := maxf(max_accel(), 0.001)
		thr = clampf(spd / (a_max * 1.5), 0.04, 1.0)
	return {"turn": turn, "throttle": thr}


## Where the ship starts when it leaves the dock: well clear, at rest, facing away from the station.
func place_at_dock(direction: Vector3 = Vector3(0, 0, 1)) -> void:
	var d := direction.normalized()
	pos = d * float(tune.get("start_distance_m", 140.0))
	vel = Vector3.ZERO
	ang = Vector3.ZERO
	throttle = 0.0
	braking = false
	basis = Basis.looking_at(d, Vector3.UP)    # forward (-Z) points along d, away from the station


## Heat builds when the ship makes more than its radiators shed. Past the limit the engines shut down
## until it has cooled to the restart level.
func _heat(dt: float) -> void:
	var made := heat_base_kw + engine_heat_kw * throttle
	heat_mj = maxf(0.0, heat_mj + (made - cooling_kw) * dt / 1000.0)   # kW x s = kJ -> MJ
	var cap := heat_capacity_mj()
	if heat_mj >= cap:
		overheated = true
		throttle = 0.0
	elif overheated and heat_mj <= cap * float(tune.get("restart_heat_fraction", 0.6)):
		overheated = false


## Station shapes in the station's own frame: a spine along Z and a ring in the XY plane.
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
	if d_spine < d_ring:
		return {"gap": d_spine, "normal": to_spine.normalized() if to_spine.length() > 0.001 else Vector3(0, 0, 1)}
	return {"gap": d_ring, "normal": to_ring.normalized() if to_ring.length() > 0.001 else Vector3(1, 0, 0)}


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
		damage = minf(1.0, damage + (into - soft) * float(tune.get("damage_per_m_s", 0.02)))


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
