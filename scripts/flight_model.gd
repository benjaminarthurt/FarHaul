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
	return m


func mass_t() -> float:
	return dry_t + fuel_t + cargo_t


func has_fuel() -> bool:
	return fuel_t > 0.0001


## Forward acceleration at the current throttle, m/s^2.
func accel() -> float:
	return thrust_kn * 1000.0 * throttle / (mass_t() * 1000.0) if has_fuel() else 0.0


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


func _turn_accel() -> float:
	var ref := float(tune.get("reference_mass_t", 20.0))
	var scale := pow(ref / maxf(mass_t(), 0.1), float(tune.get("turn_mass_exponent", 0.5)))
	var authority := 1.0 / (1.0 + float(tune.get("offset_penalty_per_m", 0.12)) * offset_m)
	return float(tune.get("turn_accel_rad_s2", 0.9)) * scale * authority


func _max_turn() -> float:
	return float(tune.get("max_turn_rate_rad_s", 1.1))


## Advance by `dt` seconds. `turn` is the pilot's pitch/yaw/roll command, each -1..1; `throttle_cmd` is
## -1 (ease off), 0 (hold) or +1 (open up), applied at throttle_rate_per_s.
func step(dt: float, turn: Vector3 = Vector3.ZERO, throttle_cmd: float = 0.0) -> void:
	throttle = clampf(throttle + throttle_cmd * float(tune.get("throttle_rate_per_s", 0.8)) * dt, 0.0, 1.0)
	var cmd := turn
	if braking:
		var auto := _brake(dt)
		cmd = auto["turn"]
		throttle = auto["throttle"]
	# Rotation: move the angular rate toward what the pilot (or the assist) asks for.
	var want := cmd * _max_turn()
	var a := _turn_accel() * dt
	for i in 3:
		if cmd[i] != 0.0 or assist or braking:
			ang[i] = move_toward(ang[i], want[i], a)
	if ang.length() > 0.0:
		basis = (basis * Basis(ang.normalized(), ang.length() * dt)).orthonormalized()
	# Thrust: burns fuel, and the ship gets lighter as it goes.
	if has_fuel() and throttle > 0.0:
		var burn := minf(_flow_kg_s(throttle) * dt / 1000.0, fuel_t)
		var effective := burn / (_flow_kg_s(throttle) * dt / 1000.0) if burn > 0.0 else 0.0
		vel += forward() * (thrust_kn / mass_t()) * throttle * effective * dt
		fuel_t -= burn
	else:
		if not has_fuel():
			fuel_t = 0.0
			throttle = 0.0
	pos += vel * dt


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


## True when the ship is close and slow enough to dock with the station at the origin.
func can_dock(station_pos: Vector3 = Vector3.ZERO) -> bool:
	return pos.distance_to(station_pos) <= float(tune.get("dock_range_m", 70.0)) and vel.length() <= float(tune.get("dock_speed_m_s", 4.0))


## Where the ship starts when it leaves the dock: well clear, at rest, facing away from the station.
func place_at_dock(direction: Vector3 = Vector3(0, 0, 1)) -> void:
	var d := direction.normalized()
	pos = d * float(tune.get("start_distance_m", 140.0))
	vel = Vector3.ZERO
	ang = Vector3.ZERO
	throttle = 0.0
	braking = false
	basis = Basis.looking_at(d, Vector3.UP)    # forward (-Z) points along d, away from the station
