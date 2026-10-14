class_name PartCompare
extends RefCounted
## The shipyard's comparison card (builder, I to hide it): every make of the selected part side by side,
## the best in each column picked out, where each is cheapest, and what fitting one does to the ship
## as it stands (from ShipStats.compute). Plain functions so the tests can read the same numbers.

const BEST := "#8fe08f"
const PICK := "#ffe680"
const BAD := "#ff8a80"
const DIM := "#9aa6b8"


## One row per make: {id, make, head, mass, heat, power, wear, price, home, tags}. `price` is a
## Callable(ModuleDef) -> int, what the part costs at this yard.
static func rows(lib: ModuleLibrary, def: ModuleDef, price: Callable) -> Array:
	var out := []
	for id in PartMakers.family(lib, def):
		var d := lib.get_def(id)
		var home := PartMakers.home_name(d) if d.base != &"" else ""
		out.append({
			"id": id,
			"make": PartMakers.short(String(d.maker)) if d.maker != &"" else d.display_name,
			"head": float(PartMakers.headline(d).value),
			"mass": d.mass,
			"heat": maxf(d.heat, 0.0),
			"power": d.power,
			"wear": d.wear_mult,
			"price": int(price.call(d)),
			"home": home if home != "" else "anywhere",
			"tags": PartMakers.tags(lib, d),
		})
	return out


## The best value in each column: {column: value}, left out where they're all the same. Higher is
## better for the headline and power (generation is positive, draw negative); lower for mass, heat,
## wear and price.
static func best(rs: Array) -> Dictionary:
	var out := {}
	for col in ["head", "mass", "heat", "power", "wear", "price"]:
		var hi: bool = col in ["head", "power"]
		var at := -1
		for i in rs.size():
			var v := float(rs[i][col])
			if at < 0 or (v > float(rs[at][col]) + 0.0001 if hi else v < float(rs[at][col]) - 0.0001):
				at = i
		var tie: bool = rs.all(func(r): return absf(float(r[col]) - float(rs[at][col])) < 0.0001)
		if at >= 0 and not tie:   # nothing to pick out when they're all the same
			out[col] = float(rs[at][col])
	return out


## What fitting one `def` does to the ship: a list of {label, was, now, bad, good}, as text.
static func effect(st: Dictionary, def: ModuleDef) -> Array:
	var out := []
	if st.is_empty():
		return out
	var wet := float(st.get("wet", 0.0))
	var loaded := wet + float(st.get("cargo_mass", 0.0))
	var add := def.mass + def.fuel
	var thrust := float(st.get("thrust_fwd", 0.0))
	if def.thrust > 0.0 or (thrust > 0.0 and add > 0.0):
		var was := thrust / (wet * ShipStats.G) if wet > 0.0 else 0.0
		var now := (thrust + def.thrust) / ((wet + add) * ShipStats.G) if wet + add > 0.0 else 0.0
		out.append({"label": "T/W", "was": "%.2f" % was, "now": "%.2f" % now, "good": now > was + 0.005, "bad": now < was - 0.005})
	if def.heat != 0.0:
		var hg := float(st.get("heat_gen", 0.0))
		var co := float(st.get("cooling", 0.0))
		var hg2 := hg + maxf(def.heat, 0.0)
		var co2 := co - minf(def.heat, 0.0)
		out.append({"label": "Heat", "was": "%.0f/%.0f" % [hg, co], "now": "%.0f/%.0f kW" % [hg2, co2], "good": def.heat < 0.0 and hg > co, "bad": hg2 > co2})
	if def.power != 0.0:
		var pu := float(st.get("power_use", 0.0))
		var pg := float(st.get("power_gen", 0.0))
		var pu2 := pu - minf(def.power, 0.0)
		var pg2 := pg + maxf(def.power, 0.0)
		out.append({"label": "Power", "was": "%.0f/%.0f" % [pu, pg], "now": "%.0f/%.0f kW" % [pu2, pg2], "good": def.power > 0.0 and pu > pg, "bad": pu2 > pg2})
	if def.fuel > 0.0:
		var f := float(st.get("fuel", 0.0))
		out.append({"label": "Fuel", "was": "%.0f" % f, "now": "%.0f t" % (f + def.fuel), "good": true, "bad": false})
	if def.lift > 0.0 or float(st.get("lift", 0.0)) > 0.0 and add > 0.0:
		var l := float(st.get("lift", 0.0))
		var was := l / maxf(loaded, 0.001)
		var now := (l + def.lift) / maxf(loaded + add, 0.001)
		out.append({"label": "Lift", "was": "%.1f" % was, "now": "%.1f m/s²" % now, "good": now > was + 0.05, "bad": now < was - 0.05})
	if def.retro > 0.0:
		var r := float(st.get("retro", 0.0))
		out.append({"label": "Braking", "was": "%.2f" % (r / maxf(loaded, 0.001)), "now": "%.2f m/s²" % ((r + def.retro) / maxf(loaded + add, 0.001)), "good": true, "bad": false})
	if def.rcs > 0.0:
		var x := float(st.get("rcs_y", 0.0))
		out.append({"label": "Push", "was": "%.0f" % x, "now": "%.0f kN" % (x + def.rcs), "good": true, "bad": false})
	if def.drive > 0.0:
		var n := int(st.get("drive_count", 0))
		out.append({"label": "Jumps", "was": "none" if n == 0 else "%d%%" % roundi(float(st.get("drive", 0.0)) * 100.0),
				"now": "%d%%" % roundi((float(st.get("drive", 0.0)) + def.drive) * 100.0), "good": n == 0, "bad": false})
	if def.cargo_slots > 0:
		out.append({"label": "Hold", "was": "%d" % int(st.get("cargo_slots", 0)), "now": "%d containers" % (int(st.get("cargo_slots", 0)) + def.cargo_slots), "good": true, "bad": false})
	return out.filter(func(e): return not String(e.now).begins_with(String(e.was) + " ") and String(e.now) != String(e.was))   # only what moves


## The card, as BBCode for a RichTextLabel. `pick` is the id being fitted (a row in the table if it's one
## of a family); `st` the ship as it stands.
static func card(lib: ModuleLibrary, def: ModuleDef, st: Dictionary, price: Callable) -> String:
	var t := ""
	var rs := rows(lib, def, price)
	if not rs.is_empty():
		var h := PartMakers.headline(lib.get_def(rs[0].id))
		var part := lib.get_def(rs[0].id).display_name
		var b := best(rs)
		var show_heat: bool = String(h.label) != "Cooling" and rs.any(func(r): return float(r.heat) > 0.0)
		var show_power: bool = rs.any(func(r): return absf(float(r.power)) > 0.001)
		var cols := ["Make"]
		if String(h.label) != "":
			cols.append("%s %s" % [h.label, h.unit])
		cols.append("Mass t")
		if show_heat:
			cols.append("Heat kW")
		if show_power:
			cols.append("Power kW")
		cols.append_array(["Wear", "Price", "Home"])
		t += "[b]%s[/b]  [color=%s]%d makes, same job, different compromises. Prices are this yard's.[/color]\n" % [part.to_upper(), DIM, rs.size()]
		t += "[table=%d]" % cols.size()
		for c in cols:
			t += "[cell expand=%d][color=%s]%s  [/color][/cell]" % [3 if c == "Make" else (2 if c == "Home" else 1), DIM, c]
		for i in rs.size():
			var r: Dictionary = rs[i]
			var mine: bool = StringName(r.id) == def.id
			t += "[cell]%s  [/cell]" % (("[color=%s][b]%s[/b][/color]" % [PICK, r.make]) if mine else String(r.make))
			if String(h.label) != "":
				t += _cell("%.0f" % float(r.head), _is(b, "head", r))
			t += _cell("%.1f" % float(r.mass), _is(b, "mass", r))
			if show_heat:
				t += _cell("%.0f" % float(r.heat), _is(b, "heat", r))
			if show_power:
				t += _cell("%+.0f" % float(r.power), _is(b, "power", r))
			t += _cell("×%.1f" % float(r.wear), _is(b, "wear", r))
			t += _cell(ShipStats.commas(int(r.price)), _is(b, "price", r))
			t += "[cell][color=%s]%s[/color][/cell]" % [DIM, r.home]
		t += "[/table]\n"
		t += "[color=%s]Green: best in its column. Wear ×2 wears out twice as fast. 15%% off in a make's home system, 10%% duty anywhere else.[/color]\n" % DIM
	else:
		t += "[b]%s[/b]\n" % def.display_name.to_upper()
	var fx := effect(st, def)
	if not fx.is_empty():
		var bits := PackedStringArray()
		for e in fx:
			var col := BAD if bool(e.bad) else (BEST if bool(e.good) else "")
			var now := String(e.now) if col == "" else "[color=%s]%s%s[/color]" % [col, e.now, "  over!" if bool(e.bad) and String(e.label) in ["Heat", "Power"] else ""]
			bits.append("%s %s → %s" % [e.label, e.was, now])
		t += "Fit one%s:  %s" % [" (the highlighted make)" if not rs.is_empty() else "", "    ".join(bits)]
	return t


static func _is(b: Dictionary, col: String, r: Dictionary) -> bool:
	return b.has(col) and absf(float(r[col]) - float(b[col])) < 0.0001


static func _cell(text: String, best_here: bool) -> String:
	return "[cell]%s  [/cell]" % (("[color=%s]%s[/color]" % [BEST, text]) if best_here else text)
