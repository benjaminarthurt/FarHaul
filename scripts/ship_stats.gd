class_name ShipStats
extends RefCounted
## Engineering numbers for a ship, derived from ShipData. Pure functions, no 3D.
## Units: tonnes, credits, kW, kN, metres. Positions are in metres, ship front is -Z.

const G := 9.81  # m/s^2, for thrust-to-weight


static func compute(ship: ShipData) -> Dictionary:
	var lib := ship.library
	var cost := 0
	var dry := 0.0
	var fuel := 0.0
	var power_gen := 0.0
	var power_use := 0.0
	var heat_gen := 0.0
	var cooling := 0.0
	var thrust_total := 0.0
	var thrust_fwd := 0.0
	var mass_weighted := Vector3.ZERO
	var thrust_weighted := Vector3.ZERO
	var lo := Vector3(INF, INF, INF)
	var hi := Vector3(-INF, -INF, -INF)
	var has_helm := false

	for m in ship.modules:
		var d := lib.get_def(m.id)
		var cells := ship.world_cells(m.id, m.cell, m.rot)
		var centroid := Vector3.ZERO
		for c in cells:
			var p := ShipGrid.cell_to_world(c)
			centroid += p
			lo = Vector3(minf(lo.x, p.x), minf(lo.y, p.y), minf(lo.z, p.z))
			hi = Vector3(maxf(hi.x, p.x), maxf(hi.y, p.y), maxf(hi.z, p.z))
		centroid /= float(cells.size())

		dry += d.mass
		fuel += d.fuel
		cost += d.cost
		mass_weighted += centroid * (d.mass + d.fuel)  # balance is judged with tanks full
		if d.power > 0.0:
			power_gen += d.power
		else:
			power_use -= d.power
		if d.heat > 0.0:
			heat_gen += d.heat
		else:
			cooling -= d.heat
		if d.thrust > 0.0:
			var dir := ShipGrid.rotate_cell(Vector3i(0, 0, -1), m.rot)  # engines push along local -Z
			thrust_total += d.thrust
			thrust_fwd += d.thrust * float(-dir.z)
			thrust_weighted += centroid * d.thrust
		if d.helm:
			has_helm = true

	var wet := dry + fuel
	var com := Vector3.ZERO
	var centre := Vector3.ZERO
	if wet > 0.0:
		com = mass_weighted / wet
	if not ship.modules.is_empty():
		centre = (lo + hi) * 0.5
	var thrust_pos := com
	if thrust_total > 0.0:
		thrust_pos = thrust_weighted / thrust_total
	var thrust_offset := Vector2(thrust_pos.x - com.x, thrust_pos.y - com.y).length()

	var warnings: Array[String] = []
	if not ship.modules.is_empty():
		if not has_helm:
			warnings.append("No cockpit: nothing to fly this from")
		if power_use > power_gen:
			warnings.append("Power short by %.0f kW" % (power_use - power_gen))
		if heat_gen > cooling:
			warnings.append("Overheating: %.0f kW more heat than cooling" % (heat_gen - cooling))
		if thrust_total - thrust_fwd > 0.01:
			warnings.append("Some engines aren't pointing aft")
		if thrust_total > 0.0 and thrust_offset > 1.0:
			warnings.append("Thrust is %.1f m off the centre of mass: costs manoeuvring fuel" % thrust_offset)

	return {
		"modules": ship.modules.size(),
		"cost": cost,
		"dry": dry,
		"fuel": fuel,
		"wet": wet,
		"power_gen": power_gen,
		"power_use": power_use,
		"heat_gen": heat_gen,
		"cooling": cooling,
		"thrust": thrust_total,
		"thrust_fwd": thrust_fwd,
		"thrust_offset": thrust_offset,
		"com": com,  # absolute, in the ship's own coordinates (first module's cell is the origin)
		"centre": centre,  # middle of the occupied cells' bounding box
		"warnings": warnings,
	}


static func format(s: Dictionary) -> String:
	if s.modules == 0:
		return "SHIP STATS\nNo modules yet"
	var twr := 0.0
	if s.wet > 0.0:
		twr = s.thrust_fwd / (s.wet * G)
	var rel: Vector3 = s.com - s.centre
	var lines := PackedStringArray([
		"SHIP STATS",
		"Modules: %d" % s.modules,
		"Cost: %s cr" % _commas(s.cost),
		"Dry mass: %.1f t" % s.dry,
		"Fuel (full): %.1f t" % s.fuel,
		"Wet mass: %.1f t" % s.wet,
		"Forward thrust: %.0f kN" % s.thrust_fwd,
		"Thrust/weight: %.2f at 1 g" % twr,
		"Power use / gen: %.0f / %.0f kW" % [s.power_use, s.power_gen],
		"Heat gen / cooling: %.0f / %.0f kW" % [s.heat_gen, s.cooling],
		"Centre of mass (from hull centre):",
		"   x %+.1f   y %+.1f   z %+.1f m" % [rel.x, rel.y, rel.z],
	])
	return "\n".join(lines)


static func _commas(n: int) -> String:
	var digits := str(absi(n))
	var out := ""
	while digits.length() > 3:
		out = "," + digits.substr(digits.length() - 3) + out
		digits = digits.substr(0, digits.length() - 3)
	return ("-" if n < 0 else "") + digits + out
