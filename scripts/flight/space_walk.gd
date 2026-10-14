class_name SpaceWalk
extends RefCounted
## A tethered space walk: out of the airlock in the suit, drifting round the hull on the suit's jets,
## with the tether paid out from the hatch and the suit's air running down. The marks on the hull
## (ShipDamage) are the spots to fix: loose plating by hand, holes with a patch kit. A space walk can't
## take the hull above `eva_repair_cap` (50%): past that it's yard work.
##
## Everything is in the ship view's own frame (the ship's layout, the frame ShipWalk and ShipDamage use).
## A ship coasting at a steady speed carries the suit with it and the tether stays slack; a ship that
## burns, brakes or spins does not, and the suit is flung away from it (the pseudo-forces of the ship's
## frame). Taut, the tether takes the load; jerked hard enough, it snaps, and the suit is adrift.
## Tools: the wrench seats loose plating, the torch (with a patch kit) welds over holes.
## Tuning: flight_tuning.json "eva".

const RADIUS := 0.45            ## the suited body, for keeping out of the hull
const REACH := 2.3              ## how close to a mark to work on it
const HATCH_REACH := 2.2        ## how close to the hatch to come back in

var sc: FlightScene            ## the flight scene (null in plain tests)
var pos := Vector3.ZERO        ## the suit's eye, ship view frame
var vel := Vector3.ZERO
var yaw := 0.0
var pitch := 0.0
var anchor := Vector3.ZERO     ## where the tether is clipped on, just outside the hatch
var hatch := Vector3.ZERO      ## where to be to climb back in
var tether_m := 30.0
var o2 := 0.0
var o2_max := 0.0
var cfg := {}
var boxes: Array[AABB] = []    ## the ship's cells, grown by the hull's thickness and the suit: keep out
var work_t := 0.0              ## how long E has been held on the current mark
var work_on := -1              ## the mark being worked on, or -1
var message := ""              ## the last thing that happened, for the prompt
var message_t := 0.0
var repairs := 0               ## marks fixed this walk
var tether_line: MeshInstance3D
var tool := "wrench"           ## in hand: "wrench" (loose plating) or "torch" (holes, with a patch kit)
var strain := 0.0              ## 0..1+ of the tether's breaking load, as last felt (decays when slack)
var tension_n := 0.0           ## the load on the tether this step, newtons
var snapped := false           ## the tether broke: adrift
var com := Vector3.ZERO        ## the ship's centre of mass, ship view frame (what it spins about)
var last_ship_vel := Vector3.INF   ## for working out the ship's acceleration between steps (flight scene)
var spheres: Array = []        ## other hulls nearby (a derelict's), in this frame: {centre, radius}; set each step
var carrying := 0              ## salvage parts in hand, cut off a derelict and not yet stowed
var carrying_id := ""          ## which panel (or hold item) they came from
var carry := {}                ## a hold item in hand (Salvage: crate, supplies or part), or {} for a panel


static func tuning() -> Dictionary:
	return FlightModel.load_tuning().get("eva", {})


## Every cell of the ship as a solid box: hull cells out to the outer skin, external parts as they are,
## each grown by the suit's radius.
static func ship_boxes(ship: ShipData) -> Array[AABB]:
	var out: Array[AABB] = []
	for m in ship.modules:
		var def: ModuleDef = ship.library.get_def(m.id)
		if def.seal:
			continue   # a door cap is a plate under the hull, not a box in the way
		var grow := ShipSkin._outer() - ShipGrid.CELL * 0.5 if def.pressurized else -0.2
		for c in ship.world_cells(m.id, m.cell, m.rot):
			var h := ShipGrid.CELL * 0.5 + grow + RADIUS
			out.append(AABB(Vector3(c) * ShipGrid.CELL - Vector3.ONE * h, Vector3.ONE * h * 2.0))
	return out


## Set up outside `airlock` (deck-level centre of the airlock), facing out of `out_dir`.
static func make(ship: ShipData, airlock: Vector3, out_dir: Vector3, air_s: float) -> SpaceWalk:
	var w := SpaceWalk.new()
	w.cfg = tuning()
	w.tether_m = float(w.cfg.get("tether_m", 30.0))
	w.boxes = ship_boxes(ship)
	var mid := airlock + Vector3(0, 1.6, 0)   # eye height, standing in the airlock
	w.hatch = mid + out_dir * (ShipGrid.CELL * 0.5 + ShipSkin.GAP + ShipSkin.T + 0.8)
	w.anchor = mid + out_dir * (ShipGrid.CELL * 0.5 + ShipSkin.GAP + ShipSkin.T)
	w.pos = w.hatch
	w.o2_max = air_s
	w.o2 = air_s
	w.face(out_dir)
	return w


func look_basis() -> Basis:
	return Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, pitch)


func look(d_yaw: float, d_pitch: float) -> void:
	yaw = wrapf(yaw + d_yaw, -PI, PI)
	pitch = clampf(pitch + d_pitch, -1.5, 1.5)


func face(dir: Vector3) -> void:
	yaw = atan2(-dir.x, -dir.z)
	pitch = 0.0


## Drift on the suit jets: `move` is x right, y up, z forward, each -1..1, relative to where you look.
## With no input the suit's stabiliser bleeds the drift off. The hull is solid, and the tether stops you
## at its length.
## `ship_accel` and `spin` are the ship's acceleration and angular velocity in its own axes: the suit
## feels them backwards (and outwards from the spin).
func step(dt: float, move: Vector3, fast := false, ship_accel := Vector3.ZERO, spin := Vector3.ZERO) -> void:
	var accel := float(cfg.get("jet_accel_m_s2", 1.6)) * (1.6 if fast else 1.0)
	var top := float(cfg.get("max_speed_m_s", 2.5)) * (1.6 if fast else 1.0)
	var flung := -ship_accel - spin.cross(spin.cross(pos - com))   # what the ship's motion does to the suit
	vel += flung * dt
	if move.length() > 0.01:
		var dir := look_basis() * Vector3(move.x, move.y, -move.z)
		var jet := dir.normalized() * accel * dt
		if (vel + jet).length() < top or (vel + jet).length() < vel.length():
			vel += jet
	else:
		vel = vel.move_toward(Vector3.ZERO, float(cfg.get("stabilise_m_s2", 1.2)) * dt)
	pos += vel * dt
	_keep_out()
	tension_n = 0.0
	var off := pos - anchor
	if not snapped and off.length() > tether_m:   # the tether pulls taut: no further, and the outward drift stops
		var n := off.normalized()
		pos = anchor + n * tether_m
		var mass := float(cfg.get("suit_mass_kg", 150.0))
		var out := vel.dot(n)
		tension_n = mass * maxf(flung.dot(n), 0.0)   # holding the suit against the ship's pull
		if out > 0.0:
			tension_n += mass * out / float(cfg.get("tether_give_s", 0.25))   # and the jerk of stopping it
			vel -= n * out
	var snap := float(cfg.get("tether_snap_n", 2500.0))
	strain = maxf(tension_n / snap, strain - dt * 0.8)
	if tension_n > snap:
		snapped = true
	o2 = maxf(0.0, o2 - dt * (1.4 if fast and move.length() > 0.01 else 1.0))


## Out of any box (or other hull) the suit has drifted into, by the shortest way, and stop moving into it.
func _keep_out() -> void:
	for sp in spheres:
		var off: Vector3 = pos - (sp.centre as Vector3)
		var r := float(sp.radius) + RADIUS
		if off.length() < r and off.length() > 0.001:
			var n := off.normalized()
			pos = (sp.centre as Vector3) + n * r
			if vel.dot(n) < 0.0:
				vel -= n * vel.dot(n)
	for b in boxes:
		if not b.has_point(pos):
			continue
		var to_min := pos - b.position
		var to_max := b.end - pos
		var best := 0
		var dists := [to_min.x, to_max.x, to_min.y, to_max.y, to_min.z, to_max.z]
		for i in 6:
			if dists[i] < dists[best]:
				best = i
		var axis := best / 2
		var n := Vector3.ZERO
		n[axis] = -1.0 if best % 2 == 0 else 1.0
		pos[axis] = b.position[axis] - 0.001 if best % 2 == 0 else b.end[axis] + 0.001
		if vel.dot(n) < 0.0:
			vel -= n * vel.dot(n)


func tether_left() -> float:
	return maxf(0.0, tether_m - (pos - anchor).length())


## How far from the hatch: adrift, this is how lost you are.
func distance() -> float:
	return (pos - anchor).length()


func at_hatch() -> bool:
	return pos.distance_to(hatch) <= HATCH_REACH


## The nearest mark within reach among `marks` ({index: position}), or -1.
func mark_in_reach(marks: Dictionary) -> int:
	var best := -1
	var best_d := REACH
	for i in marks:
		var d := pos.distance_to(marks[i] as Vector3)
		if d <= best_d:
			best_d = d
			best = int(i)
	return best


## How long a mark takes to fix, seconds.
func work_s(i: int) -> float:
	return float(cfg.get("patch_s", 7.0)) if ShipDamage.needs_kit(i) else float(cfg.get("fix_s", 4.0))


## Which tool a mark wants.
static func tool_for(i: int) -> String:
	if i >= 1000:   # a working part (OnFoot.PART): machinery wants the wrench
		return "wrench"
	return "torch" if ShipDamage.needs_kit(i) else "wrench"


## Why mark `i` can't be fixed right now, or "": the hull is already at the space-walk limit, it's the
## wrong tool, or it needs a kit and there isn't one.
static func blocked(i: int, hull: float, kits: int, in_hand := "") -> String:
	var cap := float(tuning().get("repair_cap_hull", 0.5))
	if hull >= cap - 0.001:
		return "Hull at %d%%: that's as far as a wrench and a torch go. The rest is yard work." % roundi(cap * 100.0)
	if in_hand != "" and in_hand != tool_for(i):
		return "That's a hole: it wants the torch (2) and a patch kit. A wrench just makes it a louder hole." if ShipDamage.needs_kit(i) \
				else "That's loose plating: the wrench (1) seats it. The torch would only weld it on crooked."
	if ShipDamage.needs_kit(i) and kits <= 0:
		return "That's a hole, not a dent: it needs a patch kit, and you have none. The repair desk sells them."
	return ""


## What fixing one mark does to the damage: one mark's worth off, never past the cap.
static func repaired(damage: float) -> float:
	var cap := float(tuning().get("repair_cap_hull", 0.5))
	return maxf(minf(damage, 1.0 - cap), damage - 1.0 / float(ShipDamage.MAX_SCORCH))
