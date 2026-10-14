class_name Salvage
extends RefCounted
## What's behind a derelict's cargo hatch once it's torched open (traffic.json "hold"), getting it home,
## and selling it. Items are one of:
##   crate:    {kind, commodity, tonnes}: freight; rides in the hold, sold to a buyer at a port
##   supplies: {kind, patch_kits, spares_kits}: straight into the lockers
##   part:     {kind, module, tonnes, condition}: a working part off the wreck; rides in the hold as
##             HARDWARE, sold at a shipyard
## The profile keeps a ledger of what in the hold is salvage (salvage_cargo: commodity -> tonnes,
## salvage_parts: [part items]) so contract freight and salvage never get mixed up.

const HARDWARE := &"salvage_hardware"
const REMAINS := &"recovered_remains"   ## the crew of a wreck, carried home (Wreckage body, PortAuthority)
const EPS := 0.001


static var _lib: CommodityLibrary


## The commodity catalogue, read once.
static func clib() -> CommodityLibrary:
	if _lib == null:
		_lib = CommodityLibrary.new()
	return _lib


static func cfg() -> Dictionary:
	return Traffic.config().get("hold", {})


static func _rr(c: Dictionary, key: String, fallback: Array, r: RandomNumberGenerator) -> int:
	var a: Array = c.get(key, fallback)
	return r.randi_range(int(a[0]), int(a[1]))


static func _rf(c: Dictionary, key: String, fallback: Array, r: RandomNumberGenerator) -> float:
	var a: Array = c.get(key, fallback)
	return r.randf_range(float(a[0]), float(a[1]))


## The hold of a wreck built from `layout`. `deep`: it died of a failed jump, so it carries a little more
## and its jump drive (if it had one) is what failed.
static func roll(layout: Array, r: RandomNumberGenerator, deep: bool) -> Array:
	var c := cfg()
	var out := []
	var coms: Array = c.get("commodities", ["consumer_goods"])
	var n := _rr(c, "crates", [1, 3], r) + (int(c.get("deep_extra_crates", 1)) if deep else 0)
	for k in n:
		out.append({"kind": "crate", "commodity": String(coms[r.randi() % coms.size()]), "tonnes": snappedf(_rf(c, "crate_t", [0.5, 2.0], r), 0.1)})
	var pk := _rr(c, "patch_kits", [0, 3], r)
	var sk := _rr(c, "spares_kits", [0, 1], r)
	if pk + sk > 0:
		out.append({"kind": "supplies", "patch_kits": pk, "spares_kits": sk})
	var lib := ModuleLibrary.new()
	var cands: Array = []
	for m in layout:
		var d := lib.get_def(m[0])
		if d != null and not d.pressurized and not d.seal and not cands.has(String(m[0])):
			cands.append(String(m[0]))
	var want := mini(_rr(c, "parts", [1, 2], r), cands.size())
	var picked: Array = []
	if deep and cands.has("jump_drive"):
		picked.append("jump_drive")
	while picked.size() < want:
		var id: String = cands[r.randi() % cands.size()]
		if not picked.has(id):
			picked.append(id)
	for base_id in picked:
		var id := PartMakers.on_a_wreck(lib, String(base_id), r)   # whoever made the part they fitted
		var failed: bool = deep and lib.get_def(StringName(id)).drive > 0.0
		var cond := _rf(c, "failed_drive_condition" if failed else "part_condition", [0.05, 0.15] if failed else [0.3, 0.85], r)
		out.append({"kind": "part", "module": id, "tonnes": lib.get_def(StringName(id)).mass, "condition": snappedf(cond, 0.01), "failed": failed})
	return out


## "1.4 t of electronics", "a supplies locker: 2 patch kits", "an engine (62%), 3.0 t".
static func describe(item: Dictionary) -> String:
	match String(item.get("kind", "part" if item.has("module") else "")):
		"crate":
			return "a crate: %.1f t of %s" % [float(item.tonnes), clib().label(StringName(String(item.commodity))).to_lower()]
		"supplies":
			var bits := PackedStringArray()
			if int(item.patch_kits) > 0:
				bits.append("%d patch kit%s" % [int(item.patch_kits), "" if int(item.patch_kits) == 1 else "s"])
			if int(item.spares_kits) > 0:
				bits.append("%d spares kit%s" % [int(item.spares_kits), "" if int(item.spares_kits) == 1 else "s"])
			return "a supplies locker: %s" % " and ".join(bits)
		"part":
			return "%s, %s, %.1f t" % [part_name(item), condition_text(item), float(item.tonnes)]
		"recorder":
			return "the %s's flight recorder" % String(item.ship)
		"body":
			return "%s, of the %s" % [String(item.name), String(item.ship)]
		"survivor":
			return "%s, alive" % String(item.name)
	return "something"


## `text` with its first letter upper case (String.capitalize would do every word, and the units too).
static func sentence(text: String) -> String:
	return text.left(1).to_upper() + text.substr(1)


static func _kits(n: int, what: String) -> String:
	return "%d %s%s" % [n, what, "" if n == 1 else "s"]


## `name` in a sentence: lower case, except an acronym (FTL drive) stays as it is.
static func lower(name: String) -> String:
	var w := name.get_slice(" ", 0)
	return name if w.length() > 1 and w == w.to_upper() else name.to_lower()


static func part_name(item: Dictionary) -> String:
	var d := ModuleLibrary.new().get_def(StringName(String(item.module)))
	return d.display_name if d != null else String(item.module)


## Whether it needs room in the hold (crates and parts do).
static func needs_hold(item: Dictionary) -> bool:
	return String(item.get("kind", "")) in ["crate", "part", "body"]


static func _com(item: Dictionary) -> StringName:
	match String(item.kind):
		"part":
			return HARDWARE
		"body":
			return REMAINS
	return StringName(String(item.commodity))


## "" if the ship can take it aboard now, otherwise why not.
static func room_for(item: Dictionary) -> String:
	if String(item.get("kind", "")) == "survivor" and Session.slot >= 0:
		var ld := Session._load_ship(SaveSlots.read(Session.slot))
		if not ld.is_empty() and Session.free_berths(Session.ship_stats(ld.ship)) < 0:
			return "No bunk and the jump seat's taken. Report them: the port will send its own boat."
		return ""
	if not needs_hold(item) or Session.slot < 0:
		return ""
	var loaded := Session._load_ship(SaveSlots.read(Session.slot))
	if loaded.is_empty():
		return ""
	var m: CargoManifest = loaded.manifest
	var free := m.free_space_for(_com(item))
	if free + EPS < float(item.tonnes):
		if m.capacity() <= EPS:
			return "There's no hold aboard to put %.1f t in. Salvage is for ships with somewhere to keep it." % float(item.tonnes)
		return "No room: that's %.1f t and the hold has %.1f t free for it. Sell something first." % [float(item.tonnes), free]
	return ""


## Into the ship: crates and parts into the hold (and the ledger), supplies into the lockers. Saves.
## Returns {ok, message, tonnes: added to the hold}.
static func stow(item: Dictionary) -> Dictionary:
	var kind := String(item.get("kind", ""))
	var p := Session.profile
	if kind == "supplies":
		var pk_room := Session.patch_kit_max() - Session.patch_kits()
		var sk_room := int(Wear.cfg().get("spares_kit_max", 4)) - Session.spares_kits()
		var pk := mini(int(item.patch_kits), maxi(pk_room, 0))
		var sk := mini(int(item.spares_kits), maxi(sk_room, 0))
		p["patch_kits"] = Session.patch_kits() + pk
		p["spares_kits"] = Session.spares_kits() + sk
		Session.save_profile()
		var left := int(item.patch_kits) - pk + int(item.spares_kits) - sk
		return {"ok": true, "tonnes": 0.0, "message": "Supplies stowed. Aboard now: %s and %s.%s" % [_kits(Session.patch_kits(), "patch kit"), _kits(Session.spares_kits(), "spares kit"),
				" The lockers were full, so %d kit%s went back out the hatch." % [left, "" if left == 1 else "s"] if left > 0 else ""]}
	if kind == "recorder":
		var recs: Array = (p.get("recorders", []) as Array).duplicate()
		recs.append({"ship": String(item.ship), "bounty": int(item.bounty)})
		p["recorders"] = recs
		Session.save_profile()
		return {"ok": true, "tonnes": 0.0, "message": "The %s's flight recorder is aboard. Any port's freight office will pass it to the insurer, who pays about %s cr to know what happened." % [String(item.ship), ShipStats.commas(int(item.bounty))]}
	if kind == "survivor":
		var why_s := room_for(item)
		if why_s != "":
			return {"ok": false, "tonnes": 0.0, "message": why_s}
		var res: Array = (p.get("rescued", []) as Array).duplicate()
		var who := item.duplicate()
		for k in ["at", "slot", "kind"]:
			who.erase(k)
		who["handed"] = false
		res.append(who)
		p["rescued"] = res
		Session.save_profile()
		var ld2 := Session._load_ship(SaveSlots.read(Session.slot)) if Session.slot >= 0 else {}
		var seat := not ld2.is_empty() and Session.free_berths(Session.ship_stats(ld2.ship)) < 0
		var how := "No bunk free, so it's the jump seat, a blanket and a hot drink. Cramped, and nobody's complaining." if seat else "A bunk, a blanket and a hot drink, still shaking."
		return {"ok": true, "tonnes": 0.0, "message": "%s is aboard. %s The freight office at the next port will take it from there." % [String(item.name), how]}
	if not needs_hold(item):
		return {"ok": false, "tonnes": 0.0, "message": "Nothing to stow."}
	var why := room_for(item)
	if why != "":
		return {"ok": false, "tonnes": 0.0, "message": why}
	var t := float(item.tonnes)
	var data := SaveSlots.read(Session.slot) if Session.slot >= 0 else {}
	if not data.is_empty():
		var loaded := Session._load_ship(data)
		if not loaded.is_empty():
			var m: CargoManifest = loaded.manifest
			var put := m.load(_com(item), t)
			if put + EPS < t:
				return {"ok": false, "tonnes": 0.0, "message": "It won't go in: the hold's fuller than it looked."}
			data["cargo"] = m.to_dict()
	if kind == "crate":
		var led: Dictionary = (p.get("salvage_cargo", {}) as Dictionary).duplicate()
		led[String(item.commodity)] = snappedf(float(led.get(String(item.commodity), 0.0)) + t, 0.001)
		p["salvage_cargo"] = led
	elif kind == "body":
		var dead: Array = (p.get("remains", []) as Array).duplicate()
		dead.append({"name": String(item.name), "ship": String(item.ship), "tonnes": t})
		p["remains"] = dead
	else:
		var parts: Array = (p.get("salvage_parts", []) as Array).duplicate()
		parts.append({"kind": "part", "module": String(item.module), "tonnes": t, "condition": float(item.condition), "failed": bool(item.get("failed", false))})
		p["salvage_parts"] = parts
	if not data.is_empty():
		data["profile"] = p
		SaveSlots.write(Session.slot, data)
	if kind == "body":
		return {"ok": true, "tonnes": t, "message": "%s is in the hold, wrapped and secured. The port authority at the next port will see them home." % String(item.name)}
	var what := "%.1f t of %s" % [t, clib().label(_com(item)).to_lower()] if kind == "crate" else lower(part_name(item))
	return {"ok": true, "tonnes": t, "message": "Stowed %s in the hold. Sell it at a port: %s." % [what, "the freight office finds a buyer" if kind == "crate" else "the shipyard takes parts"]}


# --- What's aboard, and selling it ------------------------------------------------------------

## Salvaged freight in the hold: [{commodity, tonnes}], the ledger capped by what's really there.
static func cargo_aboard(manifest: CargoManifest = null) -> Array:
	if manifest == null and Session.slot >= 0:
		var loaded := Session._load_ship(SaveSlots.read(Session.slot))
		manifest = loaded.get("manifest", null)
	var out := []
	var led: Dictionary = Session.profile.get("salvage_cargo", {})
	for com in led:
		var t := minf(float(led[com]), manifest.total_of(StringName(String(com))) if manifest != null else float(led[com]))
		if t > EPS:
			out.append({"commodity": String(com), "tonnes": snappedf(t, 0.001)})
	return out


## Salvaged parts in the hold (the ledger, dropping any the hold no longer has the tonnes for).
static func parts_aboard(manifest: CargoManifest = null) -> Array:
	if manifest == null and Session.slot >= 0:
		var loaded := Session._load_ship(SaveSlots.read(Session.slot))
		manifest = loaded.get("manifest", null)
	var room := manifest.total_of(HARDWARE) if manifest != null else INF
	var out := []
	for pt in Session.profile.get("salvage_parts", []):
		if float(pt.tonnes) <= room + EPS:
			out.append(pt)
			room -= float(pt.tonnes)
	return out


## Who here buys `tonnes` of `com` and for how much: {buyer: facility id or "", name, value}. A facility
## at this port that deals in it pays its going rate (less buyer_rate: no paperwork, no questions);
## otherwise the scrap dealer pays scrap_rate of the base value.
static func cargo_offer(com: String, tonnes: float) -> Dictionary:
	var c := cfg()
	var lib := clib()
	var tpu := lib.tonnes_per_unit(StringName(com))
	var units := tonnes / tpu if tpu > 0.0 else 0.0
	var best := {"buyer": "", "name": "the scrap dealer", "value": roundi(units * float(lib.record(StringName(com)).get("base_value", 0)) * float(c.get("scrap_rate", 0.35)))}
	var sim := Session.sim
	if sim == null:
		return best
	var port_id := String(Session.profile.get("port_id", ""))
	for fid in sim.facilities:
		var f: Dictionary = sim.facilities[fid]
		if String(f.port_id) != port_id or not (f["items"] as Dictionary).has(com):
			continue
		var v := roundi(units * sim.quote(fid, com) * float(c.get("buyer_rate", 0.85)))
		if v > int(best.value):
			best = {"buyer": String(fid), "name": String(f.get("name", fid)).replace(" (assumed)", ""), "value": v}
	return best


## What fitting salvaged part `pt` costs at the shipyard: a share of its price new, for the fitter's time.
static func fit_fee(pt: Dictionary) -> int:
	var d := ModuleLibrary.new().get_def(StringName(String(pt.get("module", ""))))
	if d == null:
		return 0
	return maxi(int(cfg().get("fit_min_cr", 250)), roundi(float(d.cost) * float(cfg().get("fit_rate", 0.15))))


## The wear a salvaged part starts with once fitted (Wear: 0 new, 1 failed).
static func wear_of(pt: Dictionary) -> float:
	if bool(pt.get("failed", false)):
		return 1.0
	return clampf(1.0 - float(pt.get("condition", 1.0)), 0.0, 1.0)


## "62%" or "failed".
static func condition_text(pt: Dictionary) -> String:
	return "failed" if bool(pt.get("failed", false)) or float(pt.get("condition", 1.0)) <= 0.0 else "%d%%" % roundi(float(pt.condition) * 100.0)


## What the shipyard pays for a salvaged part.
static func part_value(pt: Dictionary) -> int:
	var d := ModuleLibrary.new().get_def(StringName(String(pt.module)))
	if d == null:
		return 0
	return roundi(float(d.cost) * float(pt.condition) * float(cfg().get("part_rate", 0.5)))


static func cargo_value() -> int:
	var v := 0
	for l in cargo_aboard():
		v += int(cargo_offer(String(l.commodity), float(l.tonnes)).value)
	return v


static func parts_value() -> int:
	var v := 0
	for pt in parts_aboard():
		v += part_value(pt)
	return v


## Sell `what` ("cargo" or "parts") here: paid, off the hold, out of the ledger, saved.
static func sell(what: String) -> Dictionary:
	if Session.slot < 0 or Session.sim == null:
		return {"ok": false, "message": "No saved game, no sale."}
	var data := SaveSlots.read(Session.slot)
	var loaded := Session._load_ship(data)
	if loaded.is_empty():
		return {"ok": false, "message": "Couldn't load the ship from the save."}
	var m: CargoManifest = loaded.manifest
	var sim := Session.sim
	Session._sync_sim(loaded.ship)
	var total := 0
	var lines := PackedStringArray()
	if what == "cargo":
		var lib := clib()
		for l in cargo_aboard(m):
			var com := String(l.commodity)
			var t := float(l.tonnes)
			var o := cargo_offer(com, t)
			if int(o.value) <= 0:
				continue
			if String(o.buyer) != "":
				sim._pay(String(o.buyer), SimWorld.PLAYER, float(o.value))
				var tpu := lib.tonnes_per_unit(StringName(com))
				sim.ledger.receive(String(o.buyer), com, t / tpu if tpu > 0.0 else 0.0)
				SimStats.on_salvage(sim, float(o.value), String(o.buyer), t)
			else:
				sim._pay("world", SimWorld.PLAYER, float(o.value))
				SimStats.on_salvage(sim, float(o.value))
			m.unload(StringName(com), t)
			total += int(o.value)
			lines.append("%.1f t of %s to %s" % [t, lib.label(StringName(com)).to_lower(), String(o.name)])
		Session.profile["salvage_cargo"] = {}
	else:
		for pt in parts_aboard(m):
			var v := part_value(pt)
			sim._pay("world", SimWorld.PLAYER, float(v))
			SimStats.on_salvage(sim, float(v))
			m.unload(HARDWARE, float(pt.tonnes))
			total += v
			lines.append(lower(part_name(pt)))
		Session.profile["salvage_parts"] = []
	if lines.is_empty():
		return {"ok": false, "message": "No salvage aboard to sell."}
	var pc: Dictionary = sim.carriers[SimWorld.PLAYER]
	pc["revenue"] = float(pc["revenue"]) + float(total)
	var sold: int = int(Session.profile.get("salvage_sold_cr", 0))
	Session.profile["salvage_sold_cr"] = int(sold) + total
	Session._commit_sim(data, loaded.ship)
	data["cargo"] = m.to_dict()
	data["profile"] = Session.profile
	SaveSlots.write(Session.slot, data)
	return {"ok": true, "value": total, "message": "Sold %s for %s cr. Finders keepers." % [", ".join(lines), ShipStats.commas(total)]}
