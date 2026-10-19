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
	var cabin_beds := [0, 0, 0, 0]   # passenger beds by tier (Passengers.tiers): [unused, cabin, quarters, stateroom]
	var engine_power := 0.0
	var engine_heat := 0.0
	var drive := 0.0
	var drive_count := 0
	var cargo_capacity := 0.0
	var cargo_carried := 0.0
	var lift := 0.0
	var legs := 0
	var retro := 0.0
	var retro_total := 0.0
	var rcs_x := 0.0   # kN each way, sideways
	var rcs_y := 0.0   # kN each way, up and down
	var rcs_sideways := 0
	var shield_cells := 0.0
	var plan := {}    # the ship's outline seen from below (x, z), from the front (x, y) and from the side (y, z)
	var front := {}
	var side_out := {}
	var hull_plan := {}   # the pressure hull's outline from below: what a heat shield protects

	for mi in ship.modules.size():
		var m: Dictionary = ship.modules[mi]
		var d := lib.get_def(m.id)
		var cells := ship.world_cells(m.id, m.cell, m.rot)
		var centroid := Vector3.ZERO
		if cells.is_empty():   # a cap: a plate on the doorway it covers, as near as matters at its cell
			cells = [m.cell]
		for c in cells:
			var p := ShipGrid.cell_to_world(c)
			centroid += p
			if not d.seal and d.shield <= 0.0:
				plan[Vector2i(c.x, c.z)] = true
				front[Vector2i(c.x, c.y)] = true
				side_out[Vector2i(c.y, c.z)] = true
				if d.pressurized:
					hull_plan[Vector2i(c.x, c.z)] = true
			if not d.seal:   # a cap doesn't make the ship any bigger
				lo = Vector3(minf(lo.x, p.x), minf(lo.y, p.y), minf(lo.z, p.z))
				hi = Vector3(maxf(hi.x, p.x), maxf(hi.y, p.y), maxf(hi.z, p.z))
		centroid /= float(cells.size())

		dry += d.mass
		fuel += d.fuel
		cost += ShipData.paid(m, ship.library)
		cargo_slots += d.cargo_slots
		berths += d.berths
		if d.cabins > 0:
			cabin_beds[clampi(d.cabin_tier, 1, 3)] += d.cabins
		drive += d.drive
		if d.drive > 0.0:
			drive_count += 1
		cargo_capacity += d.cargo_capacity
		lift += d.lift
		if d.lift > 0.0:
			legs += 1
		shield_cells += d.shield
		if d.rcs > 0.0:   # side nozzles push along the module's X (which turns with it); top and bottom along Y
			var side := absf(float(ShipGrid.rotate_cell(Vector3i(1, 0, 0), m.rot).x))
			rcs_x += d.rcs * side
			rcs_y += d.rcs
			if side < 0.5:
				rcs_sideways += 1
		if d.retro > 0.0:   # braking thrusters fire along the module's local -Z, pushing the ship toward +Z
			retro_total += d.retro
			retro += d.retro * maxf(float(ShipGrid.rotate_cell(Vector3i(0, 0, 1), m.rot).z), 0.0)
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
			warnings.append("No cockpit: nothing to fly it from but hope")
		if open_doors > 0:
			warnings.append("Hull open: %d doorway%s onto space. Join a room to it or fit a door cap" % [open_doors, "" if open_doors == 1 else "s"])
		if airlocks == 0:
			warnings.append("No airlock: no way in or out, captain included")
		if power_use > power_gen:
			warnings.append("Power short by %.0f kW" % (power_use - power_gen))
		if heat_gen > cooling:
			warnings.append("Overheating: %.0f kW over cooling. Physics has noticed" % (heat_gen - cooling))
		if thrust_total - thrust_fwd > 0.01:
			warnings.append("Some engines aren't pointing aft")
		if thrust_total > 0.0 and thrust_offset > 1.0:
			warnings.append("Thrust is %.1f m off the centre of mass: you pay for it in manoeuvring fuel" % thrust_offset)
		if berths < crew_needed:
			warnings.append("Crew: %d berths needed, %d fitted. Add crew bunks or quarters; cargo makes a poor pillow" % [crew_needed, berths])
		if cargo_capacity <= 0.0:
			warnings.append("No cargo capacity: add a hold or rack. Without one it's a yacht")
		if retro_total - retro > 0.01:
			warnings.append("Some braking thrusters aren't facing the bow: they'll brake sideways, which is called steering, badly")
		if rcs_sideways > 0:
			warnings.append("Manoeuvring thrusters turned a quarter round push fore and aft, not sideways. Square them up (R)")
		if drive_count == 0:
			warnings.append("No FTL drive: this ship stays inside one system. The stars can wait")

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
		"cabin_beds": cabin_beds,
		"cabins": int(cabin_beds[1]) + int(cabin_beds[2]) + int(cabin_beds[3]),
		"engine_power": engine_power,   # kW the engines draw at full throttle (part of power_use)
		"engine_heat": engine_heat,     # kW of waste heat the engines make at full throttle (part of heat_gen)
		"radius": (hi - lo).length() * 0.5 + 1.5 if not ship.modules.is_empty() else 0.0,
		"crew_needed": crew_needed,
		"drive": drive,  # summed drive rating; the first FTL drive is the baseline, extras add speed
		"drive_count": drive_count,
		"ftl": drive_count > 0,
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
		"lift": lift,      # kN of lift jets (along +Y)
		"legs": legs,      # lander leg modules fitted
		"retro": retro,    # kN of braking thrust pushing the ship backward
		"retro_a": retro / maxf(loaded, 0.001),   # m/s² they slow the loaded ship by
		"rcs_x": rcs_x,    # kN each way of manoeuvring thrust, sideways
		"rcs_y": rcs_y,    # and up and down
		"foot_y": lo.y - ShipGrid.CELL * 0.5 if not ship.modules.is_empty() else 0.0,   # lowest point, ship coordinates
		"lift_g": lift / maxf(loaded, 0.001),
		# Coming down through air (FlightModel.air): the areas the air presses on, and how much of the belly
		# a heat shield covers.
		"belly_m2": float(plan.size()) * ShipGrid.CELL * ShipGrid.CELL,
		"front_m2": float(front.size()) * ShipGrid.CELL * ShipGrid.CELL,
		"side_m2": float(side_out.size()) * ShipGrid.CELL * ShipGrid.CELL,
		"shield": clampf(shield_cells / maxf(1.0, float(hull_plan.size())), 0.0, 1.0),   # m/s² the lift jets can hold up at this load: must beat a world's gravity to land
		"warnings": warnings,
	}


static func format(s: Dictionary) -> String:
	if s.modules == 0:
		return "SHIP STATS\nNo modules yet. Light, at least"
	var rel: Vector3 = s.com - s.centre
	var hull := "sealed" if s.open_doors == 0 else "OPEN (%d doorways)" % s.open_doors
	var lines := PackedStringArray([
		"SHIP STATS",
		"%d modules   %s cr" % [s.modules, _commas(s.cost)],
		"Mass  dry %.1f   wet %.1f   loaded %.1f t" % [s.dry, s.wet, s.loaded],
		"Fuel  %.1f t full" % s.fuel,
		"Hull  %s   airlocks %d" % [hull, s.airlocks],
		"Crew  %d needed, %d berths%s" % [s.crew_needed, s.berths, ("   FTL drive x%d" % s.drive_count) if s.drive_count > 0 else "   no FTL"],
		"Thrust  %.0f kN   T/W %.2f empty, %.2f loaded" % [s.thrust_fwd, s.twr, s.twr_loaded],
	])
	if int(s.get("cabins", 0)) > 0:
		var cb: Array = s.cabin_beds
		var bits := PackedStringArray()
		for t in [3, 2, 1]:
			if int(cb[t]) > 0:
				bits.append("%d %s" % [int(cb[t]), ["", "cabin", "quarters", "stateroom"][t]])
		lines.append("Passengers  %d beds: %s" % [int(s.cabins), ", ".join(bits)])
	if float(s.get("lift", 0.0)) > 0.0:
		lines.append("Lift  %.0f kN   lands where gravity is under %.2f g loaded" % [s.lift, float(s.lift_g) / G])
	if float(s.get("shield", 0.0)) > 0.0:
		lines.append("Heat shield  %d%% of the hull's belly covered" % roundi(float(s.shield) * 100.0))
	if float(s.get("retro", 0.0)) > 0.0:
		lines.append("Braking  %.0f kN   slows %.2f m/s² loaded, without turning round" % [s.retro, float(s.retro_a)])
	if float(s.get("rcs_y", 0.0)) > 0.0:
		lines.append("Manoeuvring  %.0f kN sideways, %.0f kN up/down   %.2f m/s² loaded" % [s.rcs_x, s.rcs_y, float(s.rcs_y) / maxf(float(s.loaded), 0.001)])
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
