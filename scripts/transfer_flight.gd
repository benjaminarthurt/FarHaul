class_name TransferFlight
extends RefCounted
## A flown local run: leave one site, burn toward the next and stop there. Pure code on top of
## FlightModel so it can be tested headless. The distance between sites is set so a clean burn-and-brake
## spends exactly the hop's delta-v (the figure the board prices fuel on); sloppy flying costs more
## fuel and a pilot who runs the tank dry is towed.

var target := Vector3.ZERO      # where the destination site is, metres from the start
var direction := Vector3(0, 0, -1)
var distance_m := 0.0           # start to target
var ideal_burn_t := 0.0         # fuel of the perfect burn-and-brake
var ideal_seconds := 0.0
var arrive_range_m := 1500.0
var arrive_speed_m_s := 8.0


## What a perfect run looks like for this ship and load: full burn to half the delta-v, flip, brake to
## a stop. Integrated with the real FlightModel mass and thrust so the numbers agree with the flight.
static func plan(stats: Dictionary, dv_kms: float, seed_key: String = "") -> TransferFlight:
	var t := TransferFlight.new()
	var m := FlightModel.from_stats(stats)
	t.arrive_range_m = float(m.tune.get("transfer_arrival_range_m", 1500.0))
	t.arrive_speed_m_s = float(m.tune.get("transfer_arrival_speed_m_s", 8.0))
	var half := dv_kms * 1000.0 * 0.5
	var v := 0.0
	var dist := 0.0
	var secs := 0.0
	var dt := 0.1
	var guard := 0
	# Accelerate until half the delta-v is spent, then mirror it: braking retraces the same speeds.
	var fuel0 := m.fuel_t
	while v < half and guard < 200000:
		guard += 1
		var burn := m._flow_kg_s(1.0) * dt / 1000.0
		var a := m.thrust_kn / m.mass_t()
		v += a * dt
		dist += v * dt
		m.fuel_t -= burn
		secs += dt
		if m.fuel_t <= 0.0:
			break
	var accel_burn := fuel0 - m.fuel_t
	# Braking: same delta-v from a lighter ship, so integrate it too.
	var vb := v
	var db := 0.0
	while vb > 0.0 and guard < 400000 and m.fuel_t > 0.0:
		guard += 1
		var burn2 := m._flow_kg_s(1.0) * dt / 1000.0
		var a2 := m.thrust_kn / m.mass_t()
		vb -= a2 * dt
		db += maxf(vb, 0.0) * dt
		m.fuel_t -= burn2
		secs += dt
	t.distance_m = dist + db
	t.ideal_burn_t = fuel0 - m.fuel_t
	t.ideal_seconds = secs
	var h := hash("transfer|" + seed_key)
	var ang := float(h % 3600) / 3600.0 * TAU
	t.direction = Vector3(cos(ang), 0.25 * sin(ang * 3.0), sin(ang)).normalized()
	t.target = t.direction * t.distance_m
	return t


## Point the run along `dir` (unit vector), keeping its distance.
func aim(dir: Vector3) -> void:
	direction = dir.normalized()
	target = direction * distance_m


func range_to(model: FlightModel) -> float:
	return (target - model.pos).length()


## Speed toward the target, m/s (negative when moving away).
func closing(model: FlightModel) -> float:
	var to := target - model.pos
	return model.vel.dot(to.normalized()) if to.length() > 0.01 else 0.0


## Distance a full-power stop needs from the current speed, with the ship getting lighter as it burns
## (rocket equation), ignoring the turn to retrograde.
func stopping_distance(model: FlightModel) -> float:
	var v := model.speed()
	if v < 0.01:
		return 0.0
	var scale := maxf(model.thrust_scale(), 0.01)
	var ve := float(model.tune.get("isp_s", 900.0)) * FlightModel.G0
	var mu := model.thrust_kn * scale / ve * 1.0            # kN / (m/s) = t/s of propellant
	var m0 := model.mass_t()
	var m_f := m0 * exp(-v / ve)
	if m0 - m_f > model.fuel_t:
		m_f = m0 - model.fuel_t                              # not enough propellant to stop: the best it can do
		v = ve * log(m0 / m_f)
	var burn_s := (m0 - m_f) / mu
	return v * burn_s - (ve / mu) * (m0 - m_f - m_f * v / ve)


## True once the pilot should flip and brake to stop at the target: the stopping distance plus what
## the ship covers while it turns round.
func brake_now(model: FlightModel) -> bool:
	var turn_s := 3.5
	return closing(model) > 1.0 and range_to(model) <= stopping_distance(model) + model.speed() * turn_s + arrive_range_m * 0.3


func arrived(model: FlightModel) -> bool:
	return range_to(model) <= arrive_range_m and model.speed() <= arrive_speed_m_s


## Seconds to the target at the current closing speed, or -1 when not closing.
func eta_s(model: FlightModel) -> float:
	var c := closing(model)
	return range_to(model) / c if c > 0.5 else -1.0
