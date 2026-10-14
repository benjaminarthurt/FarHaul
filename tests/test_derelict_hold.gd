extends SceneTree
## Derelict holds (scripts/salvage.gd, Traffic hatch and items, OnFoot): the cargo hatch is torched open,
## the hold's crates, supplies and parts drift out, each is hauled to your hatch: crates and parts into
## your hold (they take room, and the ledger keeps them apart from contract freight), supplies into the
## lockers. Then they sell at a port: cargo at the freight office to whoever deals in it, parts at the yard.
## Run: godot --headless --path . --script res://tests/test_derelict_hold.gd
var fails := 0
func check(ok: bool, msg: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + msg)
	if not ok:
		fails += 1


func _initialize() -> void:
	SaveSlots.dir = "user://test_saves_hold_%d" % OS.get_process_id()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SaveSlots.dir))
	process_frame.connect(_run, CONNECT_ONE_SHOT)


var f: Node
var t: Traffic


## Bring salvage point `id` 14 m out from the hatch and the suit up to it; work it with `tool` until done.
func _work(id: String, tool: String) -> String:
	var p := _point(id)
	if p.is_empty():
		return "gone"
	var w: NpcShip = null
	for d in t.derelicts:
		if (d.points as Array).has(p.point):
			w = d.ship
	var hatch_world: Vector3 = f.view.global_transform * f.eva.hatch
	w.global_position += (hatch_world + (hatch_world - f.model.pos).normalized() * 14.0) - (p.world as Vector3)
	p = _point(id)
	var to_view: Transform3D = f.view.global_transform.affine_inverse()
	f.eva.pos = to_view * (p.world as Vector3) + (f.eva.hatch - to_view * (p.world as Vector3)).normalized() * 1.0
	f.foot_c.eva_work(0.05, false)
	var r := ""
	for k in 600:
		r = f.foot_c.eva_work(0.05, true, tool)
		if r != "working":
			break
	f.foot_c.eva_work(0.05, false)
	return r


func _point(id: String) -> Dictionary:
	for p in t.salvage_points():
		if String(p.id) == id:
			return p
	return {}


func _home() -> void:
	f.eva.pos = f.eva.hatch
	f.foot_c._eva_step(0.05)


func _manifest() -> CargoManifest:
	return Session._load_ship(SaveSlots.read(Session.slot)).manifest


func _run() -> void:
	print("what's in a hold")
	var lib := CommodityLibrary.new()
	var all_ok := true
	for c in Salvage.cfg().get("commodities", []):
		all_ok = all_ok and lib.has(StringName(String(c))) and lib.tonnes_per_unit(StringName(String(c))) > 0.0
	check(all_ok, "every commodity a hold can carry is real freight")
	var r := RandomNumberGenerator.new()
	r.seed = 7
	var deep := Salvage.roll(ShipPresets.STARTER_FTL, r, true)
	var drive := deep.filter(func(i): return String(i.kind) == "part" and String(i.module) == "jump_drive")
	check(drive.size() == 1 and bool(drive[0].failed) and float(drive[0].condition) < 0.2, "a ship lost between systems: its jump drive is what failed (%s)" % (Salvage.describe(drive[0]) if not drive.is_empty() else "none"))
	check(deep.any(func(i): return String(i.kind) == "crate"), "and it was carrying something: %s" % ", ".join(deep.map(func(i): return Salvage.describe(i))))
	check(lib.has(Salvage.HARDWARE) and not lib.order.has(Salvage.HARDWARE), "salvaged parts ride in the hold, but aren't freight anyone posts")

	Session.begin_new(2, "Tester", "human", "normal", "roosevelt_independent_yards")
	Session.flight_job = {}
	f = load(Session.FLIGHT_SCENE).instantiate()
	root.add_child(f)
	current_scene = f
	await process_frame
	f.set_process(false)
	t = f.traffic_c
	t.cfg["derelicts"]["chance"] = 1.0
	t.rebuild(String(Session.profile.port_id))
	var d: Dictionary = t.derelicts[0]
	var hatch: Dictionary = {}
	var items: Array = []
	for p in d.points:
		if String(p.kind) == "hatch":
			hatch = p
		elif String(p.kind) == "item":
			items.append(p)
	check(not hatch.is_empty() and not items.is_empty(), "the derelict has a cargo hatch, and %d things behind it" % items.size())
	check(t.salvage_points().all(func(p): return String(p.kind) != "item"), "sealed: nothing to take until it's open")
	check((hatch.marker as Node3D).visible and not items.any(func(p): return (p.marker as Node3D).visible), "the hatch is marked; the hold's contents out of sight")

	print("cutting in")
	f.model.pos = Vector3(0, 0, 3000)
	f.model.vel = Vector3.ZERO
	f.model.ang = Vector3.ZERO
	f.model.basis = Basis()
	f._apply_pose()
	f.get_up()
	f.walk.stand_in_airlock()
	f.use()
	check(f.eva != null, "out on the tether")
	var res := _work(String(hatch.id), "wrench")
	check(res.contains("torch"), "the wrench won't open it: %s" % res)
	res = _work(String(hatch.id), "torch")
	check(res == "done" and bool(hatch.taken), "torched open")
	check((Session.profile.get("salvage_taken", []) as Array).has(String(hatch.id)), "and the save knows it's open")
	check(items.all(func(p): return (p.marker as Node3D).visible) and not (hatch.marker as Node3D).visible and (hatch.open_mark as Node3D).visible, "a hole where the hatch was; the hold's contents in view")
	check(f.eva.message.contains("out of the hold"), "%s" % f.eva.message)
	var reachable := t.salvage_points().filter(func(p): return String(p.kind) == "item")
	check(reachable.size() == items.size(), "all %d of them to take" % reachable.size())

	print("hauling it home")
	var crate: Dictionary = {}
	var part: Dictionary = {}
	for p in items:
		if String(p.item.kind) == "crate" and crate.is_empty():
			crate = p
		if String(p.item.kind) == "part" and part.is_empty():
			part = p
	check(not crate.is_empty() and not part.is_empty(), "a crate and a part among them")
	var cargo_before := float(f.model.cargo_t)
	res = _work(String(crate.id), "torch")
	check(res == "done" and f.eva.carrying > 0 and String(f.eva.carry.get("kind", "")) == "crate", "grabbed the crate (any tool will do)")
	var other: Dictionary = items[1] if items[0] == crate else items[0]
	res = _work(String(other.id), "wrench")
	check(res.contains("hands are full"), "one thing at a time: %s" % res)
	f.foot_c._eva_hud()
	check(f.hud.text.contains("CARRYING  A CRATE"), "the suit says what's in hand")
	_home()
	var com := String(crate.item.commodity)
	var m := _manifest()
	check(f.eva.carrying == 0 and absf(m.total_of(StringName(com)) - float(crate.item.tonnes)) < 0.01, "stowed: %.1f t of %s in the hold" % [m.total_of(StringName(com)), com])
	check(absf(float((Session.profile.get("salvage_cargo", {}) as Dictionary).get(com, 0.0)) - float(crate.item.tonnes)) < 0.01, "and the ledger knows it's salvage")
	check(absf(float(f.model.cargo_t) - cargo_before - float(crate.item.tonnes)) < 0.01, "the ship's heavier for it")
	check(f.eva.message.contains("freight office"), "%s" % f.eva.message)
	res = _work(String(part.id), "wrench")
	_home()
	m = _manifest()
	check(absf(m.total_of(Salvage.HARDWARE) - float(part.item.tonnes)) < 0.01 and (Session.profile.get("salvage_parts", []) as Array).size() == 1, "a %s in the hold: %.1f t of it" % [Salvage.part_name(part.item).to_lower(), m.total_of(Salvage.HARDWARE)])
	var sup: Array = items.filter(func(p): return String(p.item.kind) == "supplies")
	if not sup.is_empty():
		var kits := Session.patch_kits() + Session.spares_kits()
		_work(String(sup[0].id), "wrench")
		_home()
		check(Session.patch_kits() + Session.spares_kits() > kits and _manifest().total() <= m.total() + 0.001, "supplies go in the lockers, not the hold: %s" % f.eva.message)

	print("no room")
	var rest: Array = items.filter(func(p): return not bool(p.taken) and Salvage.needs_hold(p.item))
	var data := SaveSlots.read(Session.slot)
	var full := Session._load_ship(data)
	var fm: CargoManifest = full.manifest
	fm.load(&"grain", fm.capacity())
	data["cargo"] = fm.to_dict()
	SaveSlots.write(Session.slot, data)
	if not rest.is_empty():
		res = _work(String(rest[0].id), "wrench")
		check(res.contains("No room"), "a full hold takes nothing more: %s" % res)
	else:
		check(Salvage.room_for({"kind": "crate", "commodity": "fasteners", "tonnes": 1.0}).contains("No room"), "a full hold takes nothing more")
	data = SaveSlots.read(Session.slot)
	full = Session._load_ship(data)
	fm = full.manifest
	fm.unload(&"grain", 1000.0)
	data["cargo"] = fm.to_dict()
	SaveSlots.write(Session.slot, data)
	f.foot_c.end_space_walk("")

	print("the same day")
	t.rebuild(String(Session.profile.port_id))
	var d2: Dictionary = t.derelicts[0]
	var h2: Array = (d2.points as Array).filter(func(p): return String(p.kind) == "hatch")
	check(not h2.is_empty() and bool(h2[0].taken) and (h2[0].open_mark as Node3D).visible, "the hatch stays open")
	check(_point(String(crate.id)).is_empty() and _point(String(part.id)).is_empty(), "what you took stays taken")
	f.queue_free()
	await process_frame

	print("selling it")
	check(Salvage.cargo_aboard().size() == 1, "salvaged cargo aboard: %s" % str(Salvage.cargo_aboard()))
	data = SaveSlots.read(Session.slot)
	full = Session._load_ship(data)
	(full.manifest as CargoManifest).load(StringName(com), 1.0)   # someone's contract freight, same goods
	data["cargo"] = (full.manifest as CargoManifest).to_dict()
	SaveSlots.write(Session.slot, data)
	var ps: Dictionary = ShipRemote.port_state()
	check((ps.salvage.cargo as Array).size() == 1 and int(ps.salvage.cargo_value) > 0 and (ps.salvage.parts as Array).size() == 1, "the phone sees it too: %s" % str(ps.salvage))
	var o := Salvage.cargo_offer(com, float(crate.item.tonnes))
	check(int(o.value) > 0, "an offer for the %s: %s cr from %s" % [com, ShipStats.commas(int(o.value)), o.name])
	var credits := int(Session.profile.credits)
	var stock_before := Session.sim.ledger.on_hand(String(o.buyer), com) if String(o.buyer) != "" else 0.0
	var sr := Salvage.sell("cargo")
	check(bool(sr.ok) and int(Session.profile.credits) == credits + int(o.value), "sold: %s" % sr.message)
	check(absf(_manifest().total_of(StringName(com)) - 1.0) < 0.01, "the contract's tonne of it stays aboard")
	check(Salvage.cargo_aboard().is_empty() and int(Session.profile.get("salvage_sold_cr", 0)) >= int(o.value), "and the ledger's clear")
	if String(o.buyer) != "":
		check(Session.sim.ledger.on_hand(String(o.buyer), com) > stock_before, "the buyer's shelf has it now")
	var pv := Salvage.parts_value()
	check(pv > 0 and pv == Salvage.part_value(Session.profile.salvage_parts[0]), "the yard's price for the part: %s cr" % ShipStats.commas(pv))
	credits = int(Session.profile.credits)
	sr = Salvage.sell("parts")
	check(bool(sr.ok) and int(Session.profile.credits) == credits + pv and _manifest().total_of(Salvage.HARDWARE) < 0.001, "sold at the yard: %s" % sr.message)
	check(not bool(Salvage.sell("parts").ok), "nothing left to sell")
	check(Salvage.cargo_offer("electronics", 1.0).value > 0 and Salvage.cargo_offer("mining_equipment", 1.0).value > 0, "somebody always buys: the scrap dealer if nobody else")
	print("DONE fails=", fails)
	quit(1 if fails > 0 else 0)
