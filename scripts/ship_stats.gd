class_name ShipStats
extends RefCounted
## Engineering numbers for a ship, derived from ShipData. Pure functions, no 3D.
## Units: tonnes, credits, kW, kN, metres. Positions are in metres, ship front is -Z.

const G := 9.81  # m/s^2, for thrust-to-weight


## Cargo comes from `manifest` when given (what is really aboard, where). Otherwise every cargo
## space is assumed `cargo_load` full (0.0 to 1.0), which is handy for what-if checks.
## Balance is judged with tanks full.
static func compute(ship: ShipData, cargo_load := 1.0, manifest: CargoManifest = null) -> Dictionary:
	cargo_load = clampf(cargo_load, 0.0, 1.0)
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
	var airlocks := 0
	var cargo_slots := 0
	var berths := 0
	var engine_power := 0.0
	var engine_heat := 0.0
	var drive := 0.0
	var cargo_capacity := 0.0
	var cargo_carried := 0.0

	for mi in ship.modules.size():
		var m: Dictionary = ship.modules[mi]
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
		cargo_slots += d.cargo_slots
		berths += d.berths
		drive += d.drive
		cargo_capacity += d.cargo_capacity
		var carried := d.cargo_capacity * cargo_load
		if manifest != null:
			carried = manifest.mass_at(mi)
		cargo_carried += carried
		mass_weighted += centroid * (d.mass + d.fuel + carried)
		if d.power > 0.0:
			power_gen += d.power
		else:
			power_use -= d.power
		if d.heat > 0.0:
			heat_gen += d.heat
		else:
			cooling -= d.heat
		if d.thrust > 0.0:
			engine_power += maxf(-d.power, 0.0)
			engine_heat += maxf(d.heat, 0.0)
			var dir := ShipGrid.rotate_cell(Vector3i(0, 0, -1), m.rot)  # engines push along local -Z
			thrust_total += d.thrust
			thrust_fwd += d.thrust * float(-dir.z)
			thrust_weighted += centroid * d.thrust
		if d.helm:
			has_helm = true
		if d.airlock:
			airlocks += 1

	var wet := dry + fuel  # no cargo
	var cargo_mass := cargo_carried
	var used_slots := -1
	var cargo_value := 0.0
	if manifest != null:
		used_slots = manifest.slots_in_use()
		cargo_value = manifest.value()
	var load_frac := cargo_mass / cargo_capacity if cargo_capacity > 0.0 else 0.0
	var loaded := wet + cargo_mass
	var com := Vector3.ZERO
	var centre := Vector3.ZERO
	if loaded > 0.0:
		com = mass_weighted / loaded
	if not ship.modules.is_empty():
		centre = (lo + hi) * 0.5
	var thrust_pos := com
	if thrust_total > 0.0:
		thrust_pos = thrust_weighted / thrust_total
	var thrust_offset := Vector2(thrust_pos.x - com.x, thrust_pos.y - com.y).length()

	var crew_needed := SimShip.crew_for(cargo_capacity)
	var open_doors := ship.open_doors().size()
	var warnings: Array[String] = []
	if not ship.modules.is_empty():
		if not has_helm:
			warnings.append("No cockpit: nothing to fly this from")
		if open_doors > 0:
			warnings.append("Hull open: %d doorway%s onto space. Cap with a module" % [open_doors, "" if open_doors == 1 else "s"])
		if airlocks == 0:
			warnings.append("No airlock: nobody can get in or out")
		if power_use > power_gen:
			warnings.append("Power short by %.0f kW" % (power_use - power_gen))
		if heat_gen > cooling:
			warnings.append("Overheating: %.0f kW more heat than cooling" % (heat_gen - cooling))
		if thrust_total - thrust_fwd > 0.01:
			warnings.append("Some engines aren't pointing aft")
		if thrust_total > 0.0 and thrust_offset > 1.0:
			warnings.append("Thrust is %.1f m off the centre of mass: costs manoeuvring fuel" % thrust_offset)
		if berths < crew_needed:
			warnings.append("Crew: this hold needs %d berths, you have %d. Add crew bunks or quarters" % [crew_needed, berths])
		if cargo_capacity <= 0.0:
			warnings.append("No cargo capacity: add a hold or rack to haul freight")

	return {
		"modules": ship.modules.size(),
		"open_doors": open_doors,
		"airlocks": airlocks,
		"has_helm": has_helm,
		"twr": thrust_fwd / (wet * G) if wet > 0.0 else 0.0,
		"twr_loaded": thrust_fwd / (loaded * G) if loaded > 0.0 else 0.0,
		"cost": cost,
		"dry": dry,
		"fuel": fuel,
		"wet": wet,  # dry plus full tanks, no cargo
		"berths": berths,
		"engine_power": engine_power,   # kW the engines draw at full throttle (part of power_use)
		"engine_heat": engine_heat,     # kW of waste heat the engines make at full throttle (part of heat_gen)
		"radius": (hi - lo).length() * 0.5 + 1.5 if not ship.modules.is_empty() else 0.0,
		"crew_needed": crew_needed,
		"drive": drive,
		"cargo_slots": cargo_slots,
		"cargo_capacity": cargo_capacity,  # tonnes when full
		"cargo_load": load_frac,
		"cargo_used_slots": used_slots,  # -1 when no manifest was given
		"cargo_value": cargo_value,
		"cargo_mass": cargo_mass,  # tonnes at the current load
		"loaded": loaded,  # wet plus cargo at the current load
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
	var rel: Vector3 = s.com - s.centre
	var hull := "sealed" if s.open_doors == 0 else "OPEN (%d doorways)" % s.open_doors
	var lines := PackedStringArray([
		"SHIP STATS",
		"%d modules   %s cr" % [s.modules, _commas(s.cost)],
		"Mass  dry %.1f   wet %.1f   loaded %.1f t" % [s.dry, s.wet, s.loaded],
		"Fuel  %.1f t full" % s.fuel,
		"Hull  %s   airlocks %d" % [hull, s.airlocks],
		"Crew  %d needed, %d berths%s" % [s.crew_needed, s.berths, "   Jump drive +%d%%" % roundi(s.drive * 100.0) if s.drive > 0.0 else ""],
		"Thrust  %.0f kN   T/W %.2f empty, %.2f loaded" % [s.thrust_fwd, s.twr, s.twr_loaded],
	])
	if s.cargo_used_slots >= 0:
		lines.append("Cargo  %.1f t   worth %s cr" % [s.cargo_mass, _commas(roundi(s.cargo_value))])
	lines.append("Centre of mass  x %+.1f  y %+.1f  z %+.1f m" % [rel.x, rel.y, rel.z])
	return "\n".join(lines)


static func commas(n: int) -> String:
	return _commas(n)


static func _commas(n: int) -> String:
	var digits := str(absi(n))
	var out := ""
	while digits.length() > 3:
		out = "," + digits.substr(digits.length() - 3) + out
		digits = digits.substr(0, digits.length() - 3)
	return ("-" if n < 0 else "") + digits + out
