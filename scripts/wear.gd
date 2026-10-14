class_name Wear
extends RefCounted
## Wear and tear on the ship's working parts: engines, radiators, braking and manoeuvring thrusters,
## and lander legs. Each fitted part has a wear level, 0 new .. 1 failed, kept in the save
## (profile.wear, keyed "<module index>:<module id>", so a part rebuilt in the yard starts new).
##
## - A worn part works less well (each kind loses up to `loss` of its output at 1.0); a failed part
##   (wear >= 1) does nothing at all.
## - Parts wear with use (engines burning, hotter when the ship is hot; radiators running hot; thrusters
##   firing; legs landing) and with knocks to the hull. Autopilot trips wear the engines and radiators
##   by the fuel they burn.
## - On a space walk the wrench services a worn part (free, never better than `eva_floor`), and a failed
##   one comes back with a spares kit. The repair desk overhauls everything to new, for money.
## Tuning: data/runtime/flight_tuning.json "wear".

const KINDS := ["engine", "radiator", "retro", "rcs", "legs", "drive"]
const NAMES := {"engine": "Engine", "radiator": "Radiator", "retro": "Braking thrusters", "rcs": "Manoeuvring thrusters", "legs": "Lander legs", "drive": "FTL drive"}


static func cfg() -> Dictionary:
	return FlightModel.load_tuning().get("wear", {})


## Which kind of wearing part a module is, or "" if it doesn't wear.
static func kind_of(def: ModuleDef) -> String:
	if def.thrust > 0.0:
		return "engine"
	if def.heat < 0.0 and not def.pressurized:
		return "radiator"
	if def.retro > 0.0:
		return "retro"
	if def.rcs > 0.0:
		return "rcs"
	if def.lift > 0.0:
		return "legs"
	if def.drive > 0.0:
		return "drive"
	return ""


static func key(i: int, id: StringName) -> String:
	return "%d:%s" % [i, String(id)]


## Whether the ship can still jump: it has an FTL drive that hasn't failed (or no drive at all, which
## is a different problem). A drive only works or doesn't; wear just brings failure closer.
static func drive_ok(ship: ShipData, wear: Dictionary) -> bool:
	var any := false
	for p in parts(ship, wear):
		if String(p.kind) == "drive":
			any = true
			if float(p.wear) < 1.0:
				return true
	return not any


## How much of its output a part of `kind` still gives at wear `w`.
static func factor(kind: String, w: float) -> float:
	if w >= 1.0:
		return 0.0
	var loss := float((cfg().get("loss", {}) as Dictionary).get(kind, 0.4))
	return 1.0 - loss * clampf(w, 0.0, 1.0)


## Every wearing part on `ship`: [{i, key, kind, name, wear}], in module order.
static func parts(ship: ShipData, wear: Dictionary) -> Array:
	var out := []
	for i in ship.modules.size():
		var m: Dictionary = ship.modules[i]
		var k := kind_of(ship.library.get_def(m.id))
		if k == "":
			continue
		var kk := key(i, m.id)
		out.append({"i": i, "key": kk, "kind": k, "name": String(NAMES[k]), "wear": clampf(float(wear.get(kk, 0.0)), 0.0, 1.0)})
	return out


## The ship's working outputs with wear taken into account, the same sums ShipStats makes:
## {thrust_fwd, cooling, retro, rcs_x, rcs_y, lift}.
static func effective(ship: ShipData, wear: Dictionary) -> Dictionary:
	var out := {"thrust_fwd": 0.0, "cooling": 0.0, "retro": 0.0, "rcs_x": 0.0, "rcs_y": 0.0, "lift": 0.0}
	for i in ship.modules.size():
		var m: Dictionary = ship.modules[i]
		var d: ModuleDef = ship.library.get_def(m.id)
		var k := kind_of(d)
		var f := factor(k, float(wear.get(key(i, m.id), 0.0))) if k != "" else 1.0
		if d.heat < 0.0:
			out.cooling += -d.heat * f
		if d.thrust > 0.0:
			out.thrust_fwd += d.thrust * float(-ShipGrid.rotate_cell(Vector3i(0, 0, -1), m.rot).z) * f
		if d.retro > 0.0:
			out.retro += d.retro * maxf(float(ShipGrid.rotate_cell(Vector3i(0, 0, 1), m.rot).z), 0.0) * f
		if d.rcs > 0.0:
			out.rcs_x += d.rcs * absf(float(ShipGrid.rotate_cell(Vector3i(1, 0, 0), m.rot).x)) * f
			out.rcs_y += d.rcs * f
		if d.lift > 0.0:
			out.lift += d.lift * f
	return out


## Put the worn outputs into a flight model.
static func apply(model: FlightModel, ship: ShipData, wear: Dictionary) -> void:
	var e := effective(ship, wear)
	model.thrust_kn = float(e.thrust_fwd)
	model.cooling_kw = float(e.cooling)
	model.retro_kn = float(e.retro)
	model.rcs_x_kn = float(e.rcs_x)
	model.rcs_y_kn = float(e.rcs_y)
	model.lift_kn = float(e.lift)


## Wear the parts of `kind` by `amount` each. Returns the keys that crossed a warning line
## ({key: "worn" | "failed"}) so the cockpit can say so.
static func add(wear: Dictionary, ship: ShipData, kind: String, amount: float) -> Dictionary:
	var crossed := {}
	if amount <= 0.0:
		return crossed
	for p in parts(ship, wear):
		if String(p.kind) != kind:
			continue
		crossed.merge(_bump(wear, String(p.key), amount))
	return crossed


## Wear one part.
static func _bump(wear: Dictionary, k: String, amount: float) -> Dictionary:
	var before := float(wear.get(k, 0.0))
	var after := minf(1.0, before + amount)
	wear[k] = after
	var worn := float(cfg().get("worn_at", 0.75))
	if before < 1.0 and after >= 1.0:
		return {k: "failed"}
	if before < worn and after >= worn:
		return {k: "worn"}
	return {}


## A knock to the hull: `amount` of hull damage shakes one part loose, picked by `pick` (0..1).
static func knock(wear: Dictionary, ship: ShipData, amount: float, pick: float) -> Dictionary:
	var ps := parts(ship, wear)
	if ps.is_empty() or amount <= 0.0:
		return {}
	var p: Dictionary = ps[mini(int(pick * ps.size()), ps.size() - 1)]
	return _bump(wear, String(p.key), amount * float(cfg().get("knock_per_damage", 1.5)))


## Condition for people: 100% new, 0% failed.
static func condition(w: float) -> int:
	return roundi((1.0 - clampf(w, 0.0, 1.0)) * 100.0)


## The parts worth mentioning (worn past the warning line, or failed), worst first: [{name, wear, key}].
static func troubles(ship: ShipData, wear: Dictionary) -> Array:
	var worn := float(cfg().get("worn_at", 0.75))
	var out := []
	for p in parts(ship, wear):
		if float(p.wear) >= worn:
			out.append(p)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.wear) > float(b.wear))
	return out


## One line for the HUD or a desk: "Engine failed, Radiator 18%".
static func summary(ship: ShipData, wear: Dictionary) -> String:
	var bits := PackedStringArray()
	for p in troubles(ship, wear):
		bits.append("%s %s" % [String(p.name), "FAILED" if float(p.wear) >= 1.0 else "%d%%" % condition(float(p.wear))])
	return ", ".join(bits)


## What overhauling everything to new costs, for a ship worth `ship_cost` built from these parts.
static func overhaul_cost(ship: ShipData, wear: Dictionary, mult: float) -> int:
	var total := 0.0
	for p in parts(ship, wear):
		var d: ModuleDef = ship.library.get_def(ship.modules[int(p.i)].id)
		total += float(d.cost) * float(p.wear) * float(cfg().get("overhaul_fraction_of_part", 0.45))
	return roundi(total * mult)


## On a space walk: what servicing part `p` does to its wear. Worn: the wrench takes `eva_service`
## off, never below `eva_floor`. Failed: a spares kit brings it back to `eva_replace_to`.
static func eva_fixed(w: float) -> float:
	var c := cfg()
	if w >= 1.0:
		return float(c.get("eva_replace_to", 0.6))
	return maxf(minf(w, float(c.get("eva_floor", 0.5))), w - float(c.get("eva_service", 0.3)))
