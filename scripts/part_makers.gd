class_name PartMakers
extends RefCounted
## Who makes the external parts, and what that changes (data/runtime/part_makers.json, makers from
## data/world/manufacturers.json). The parts the yards always had are Northstar Commercial's, sold
## everywhere at list price. Each maker's version of a part is its own module, id "<part>__<maker>",
## made from the part with the maker's multipliers: lighter, stronger, hotter, cheaper, slower to wear.
## Every yard sells every make; a maker's own system sells it cheaper, everywhere else adds duty.

const PATH := "res://data/runtime/part_makers.json"
const SEP := "__"

static var _cfg: Dictionary = {}
static var _makers: Dictionary = {}


static func cfg() -> Dictionary:
	if _cfg.is_empty():
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		_cfg = parsed if typeof(parsed) == TYPE_DICTIONARY else {}
	return _cfg


## The maker's canon record (data/world/manufacturers.json), or {}.
static func maker(id: String) -> Dictionary:
	if _makers.is_empty():
		var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://data/world/manufacturers.json"))
		if typeof(parsed) == TYPE_DICTIONARY:
			for m in parsed.get("manufacturers", []):
				_makers[String(m.id)] = m
	return _makers.get(id, {})


static func short(id: String) -> String:
	return String((cfg().get("short", {}) as Dictionary).get(id, maker(id).get("name", id)))


static func base_maker() -> String:
	return String(cfg().get("base_maker", "northstar_commercial"))


## Add every maker's version of each part to `lib`, each straight after its part in the palette order.
static func add_to(lib: ModuleLibrary) -> void:
	for e in cfg().get("parts", []):
		var base := lib.get_def(StringName(String(e.part)))
		if base == null:
			continue
		var mk := String(e.maker)
		var d := base.duplicate(true) as ModuleDef
		d.id = StringName(String(e.part) + SEP + mk)
		d.base = base.id
		d.maker = StringName(mk)
		d.pitch = String(e.get("pitch", ""))
		d.display_name = "%s (%s)" % [base.display_name, short(mk)]
		var mul: Dictionary = e.get("mul", {})
		d.mass = snappedf(base.mass * float(mul.get("mass", 1.0)), 0.01)
		d.cost = roundi(float(base.cost) * float(mul.get("cost", 1.0)) / 50.0) * 50
		d.thrust = base.thrust * float(mul.get("thrust", 1.0))
		d.fuel = base.fuel * float(mul.get("fuel", 1.0))
		d.lift = base.lift * float(mul.get("lift", 1.0))
		d.retro = base.retro * float(mul.get("retro", 1.0))
		d.rcs = base.rcs * float(mul.get("rcs", 1.0))
		d.power = base.power * float(mul.get("power", 1.0))
		d.heat = base.heat * float(mul.get("cooling" if base.heat < 0.0 else "heat", 1.0))
		if base.drive > 0.0:
			d.drive = base.drive + float(mul.get("drive", 0.0))
		d.wear_mult = float(mul.get("wear", 1.0))
		var col: Array = (cfg().get("colours", {}) as Dictionary).get(mk, [])
		if col.size() == 3:
			d.color = base.color.lerp(Color(float(col[0]), float(col[1]), float(col[2])), 0.6)
		var at := lib.order.find(base.id) + 1
		while at < lib.order.size() and lib.get_def(lib.order[at]).base == base.id:
			at += 1
		lib.defs[d.id] = d
		lib.order.insert(at, d.id)
	for id in lib.order:   # the parts the yards always had are Northstar's
		var d := lib.get_def(id)
		if d.base == &"" and has_versions(lib, id):
			d.maker = StringName(base_maker())


static func has_versions(lib: ModuleLibrary, id: StringName) -> bool:
	for k in lib.order:
		if lib.get_def(k).base == id:
			return true
	return false


## The maker's versions of `part` (not counting the part itself).
static func versions(lib: ModuleLibrary, part: StringName) -> Array:
	var out := []
	for k in lib.order:
		if lib.get_def(k).base == part:
			out.append(k)
	return out


## What `def` costs at a yard in `system_id`: list price for Northstar's (and anything unbranded); a
## maker's own system takes home_discount off, anywhere else adds import_duty. Rounded to 50 cr.
static func price(def: ModuleDef, system_id: String) -> int:
	if def.base == &"" or def.maker == &"":
		return def.cost
	var home := String(maker(String(def.maker)).get("origin_system_id", ""))
	var f := 1.0 - float(cfg().get("home_discount", 0.15)) if home == system_id else 1.0 + float(cfg().get("import_duty", 0.1))
	return roundi(float(def.cost) * f / 50.0) * 50


## Where `def`'s maker is: "Made in Ilos." or "".
static func home_name(def: ModuleDef) -> String:
	var home := String(maker(String(def.maker)).get("origin_system_id", ""))
	return String(Worlds.system(home).get("name", home)) if home != "" else ""


## The family `def` belongs to: its part, then every maker's version of it. [] for a part nobody else makes.
static func family(lib: ModuleLibrary, def: ModuleDef) -> Array:
	var part := def.base if def.base != &"" else def.id
	var vs := versions(lib, part)
	if vs.is_empty():
		return []
	return [part] + vs


## What a part does: its main number, by what kind of part it is. {label, value, unit}.
static func headline(def: ModuleDef) -> Dictionary:
	if def.thrust > 0.0:
		return {"label": "Thrust", "value": def.thrust, "unit": "kN"}
	if def.heat < 0.0:
		return {"label": "Cooling", "value": -def.heat, "unit": "kW"}
	if def.fuel > 0.0:
		return {"label": "Fuel", "value": def.fuel, "unit": "t"}
	if def.lift > 0.0:
		return {"label": "Lift", "value": def.lift, "unit": "kN"}
	if def.retro > 0.0:
		return {"label": "Braking", "value": def.retro, "unit": "kN"}
	if def.rcs > 0.0:
		return {"label": "Push", "value": def.rcs, "unit": "kN"}
	if def.drive > 0.0:
		return {"label": "Jump speed", "value": def.drive * 100.0, "unit": "%"}
	return {"label": "", "value": 0.0, "unit": ""}


## A few words on how a maker's version differs from the standard part: "+20% thrust · −20% mass · hot".
static func tags(lib: ModuleLibrary, def: ModuleDef) -> String:
	if def.base == &"":
		return ""
	var b := lib.get_def(def.base)
	var out := PackedStringArray()
	var pct := func(now: float, was: float) -> int: return roundi((now / was - 1.0) * 100.0) if absf(was) > 0.0001 else 0
	var h := headline(def)
	var hb := headline(b)
	if String(h.label) != "" and absf(float(h.value) - float(hb.value)) > 0.001:
		if String(h.label) == "Jump speed":
			out.append("+%d%% jump speed" % roundi(float(h.value) - float(hb.value)))
		else:
			out.append("%+d%% %s" % [pct.call(float(h.value), float(hb.value)), String(h.label).to_lower()])
	var dm: int = pct.call(def.mass, b.mass)
	if absf(dm) >= 5:
		out.append("%+d%% mass" % dm)
	if def.heat > 0.0 and b.heat > 0.0 and def.heat > b.heat * 1.15:
		out.append("hot")
	if def.wear_mult >= 1.25:
		out.append("wears fast")
	elif def.wear_mult <= 0.6:
		out.append("tough")
	if def.cost <= b.cost * 0.8:
		out.append("cheap")
	return "  ·  ".join(out).replace("-", "−")   # only the signs: none of these words has a hyphen


## A wreck's part, sometimes somebody else's make: `part` or one of its versions, picked with `r`.
static func on_a_wreck(lib: ModuleLibrary, part: String, r: RandomNumberGenerator) -> String:
	var vs := versions(lib, StringName(part))
	if vs.is_empty() or r.randf() < 0.4:
		return part
	return String(vs[r.randi() % vs.size()])
