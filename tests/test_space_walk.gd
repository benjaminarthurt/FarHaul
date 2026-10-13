extends SceneTree
## Tethered space walks (SpaceWalk): out of the airlock in space, drifting on the suit's jets, kept out of
## the hull and held by the tether; fixing the hull's marks, loose plating for free and holes with a patch
## kit, never past 50%; patched spots staying welded until a yard repair; air running out; patch kits at
## the repair desk.
## Run: godot --headless --path . --script res://tests/test_space_walk.gd
var fails := 0
func check(ok: bool, msg: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + msg)
	if not ok:
		fails += 1
func _initialize() -> void:
	SaveSlots.dir = "user://test_saves_space_walk_%d" % OS.get_process_id()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SaveSlots.dir))
	process_frame.connect(_run, CONNECT_ONE_SHOT)


func _inside(e: SpaceWalk) -> bool:
	for b in e.boxes:
		var shrunk := b.grow(-0.05)
		if shrunk.has_point(e.pos):
			return true
	return false


## Fix mark `i` from right next to it; returns the last result.
func _fix(f: Node, i: int) -> String:
	var site: Dictionary = f.view._damage.sites[i]
	f.eva.pos = (site.pos as Vector3) + (site.normal as Vector3) * 1.2
	f.eva.vel = Vector3.ZERO
	var r := ""
	for k in 400:
		r = f.foot_c.eva_work(0.05, true, SpaceWalk.tool_for(i))
		if r != "working":
			break
	f.foot_c.eva_work(0.05, false)
	return r


func _run() -> void:
	print("the suit")
	var ship := ShipData.new(ModuleLibrary.new())
	ShipPresets.build(ship)
	var walk := ShipWalk.build(ship, null)
	var e := SpaceWalk.make(ship, walk.airlock, -walk.airlock_face, 600.0)
	check(not _inside(e) and e.at_hatch(), "it starts just outside the hatch, clear of the hull")
	e.face(walk.airlock_face)   # turn round and jet straight at the ship
	for i in 200:
		e.step(0.05, Vector3(0, 0, 1))
	check(not _inside(e), "jetting into the hull stops at the hull")
	e.face(-walk.airlock_face)
	for i in 1200:
		e.step(0.05, Vector3(0, 0, 1), true)
	check((e.pos - e.anchor).length() <= e.tether_m + 0.01 and e.tether_left() < 0.5, "the tether stops you at %.0f m" % e.tether_m)
	var v := e.vel.length()
	for i in 200:
		e.step(0.05, Vector3.ZERO)
	check(e.vel.length() < 0.05 and v > 0.0, "let go of the jets and the suit stops drifting")
	check(e.o2 < 600.0, "and the air runs down (%.0f s left)" % e.o2)
	check(is_equal_approx(SpaceWalk.repaired(0.8), 0.8 - 1.0 / 16.0), "each spot fixed is worth a sixteenth of the hull")
	check(is_equal_approx(SpaceWalk.repaired(0.52), 0.5), "but never past 50%")
	check(SpaceWalk.blocked(2, 0.4, 5, "torch").contains("wrench") and SpaceWalk.blocked(3, 0.4, 5, "wrench").contains("torch"), "each job wants its own tool")
	check(SpaceWalk.blocked(2, 0.5, 5) != "" and SpaceWalk.blocked(2, 0.4, 0) == "" and SpaceWalk.blocked(3, 0.4, 0) != "" and SpaceWalk.blocked(3, 0.4, 1) == "",
			"loose plating is free, holes need a kit, and nothing above 50%")

	print("the tether")
	var t := SpaceWalk.make(ship, walk.airlock, -walk.airlock_face, 600.0)
	t.com = Vector3(0, 0, 6)
	for i in 400:   # coasting at any speed: nothing pulls
		t.step(0.05, Vector3.ZERO, false, Vector3.ZERO, Vector3.ZERO)
	check(t.strain < 0.01 and t.distance() < 1.5, "a coasting ship doesn't pull on the tether")
	t.pos = t.anchor + Vector3(0, 0, 1).normalized() * t.tether_m
	t.vel = Vector3.ZERO
	for i in 40:   # taut and the ship braking at 2 m/s² (more than the suit's stabiliser takes out): held, some strain
		t.step(0.05, Vector3.ZERO, false, Vector3(0, 0, -2.0))
	check(not t.snapped and t.strain > 0.03 and t.strain < 0.5, "taut while the ship brakes gently: it holds (%d%% strain)" % roundi(t.strain * 100.0))
	var s := SpaceWalk.make(ship, walk.airlock, -walk.airlock_face, 600.0)
	for i in 400:   # slack, and the ship burns away at 2.6 m/s²: the suit is flung to the end and it snaps
		s.step(0.05, Vector3.ZERO, false, Vector3(0, 0, -2.6))
		if s.snapped:
			break
	check(s.snapped, "flung to the end of a slack tether by a burning ship, it snaps")

	print("on a flight")
	Session.begin_new(2, "Test Captain", "human", "normal", "roosevelt_independent_yards")
	Session.profile["hull_damage"] = 0.8
	Session.profile["patch_kits"] = 1
	Session.save_profile()
	Session.flight_job = {}
	var f: Node = load(Session.FLIGHT_SCENE).instantiate()
	root.add_child(f)
	current_scene = f
	await process_frame
	f.model.pos = Vector3(0, 0, 3000)   # well clear of the berth, coasting
	f.model.vel = Vector3(0, 0, 40)
	f.model.throttle = 0.6
	f.get_up()
	f.walk.stand_in_airlock()
	f._walk_prompt()
	check(f.prompt.text.contains("tether"), "at the airlock, away from a berth, the hatch offers a space walk: %s" % f.prompt.text)
	f.use()
	check(f.eva != null and not f.walking and is_equal_approx(f.model.throttle, 0.6) and f._warp() == 1, "out on the tether: the ship carries on as it was, time at x1")
	f.model.throttle = 0.0
	f._update_hud()
	check(f.hud.text.contains("TETHER") and f.hud.text.contains("PATCH KITS  1"), "the HUD shows tether, air and kits")
	var marks: Dictionary = f.foot_c._eva_marks()
	check(marks.size() == 13, "a hull at 20%% shows 13 marks to fix (%d)" % marks.size())
	var free_i := -1
	var kit_i := -1
	var kit_j := -1
	for i in marks:
		if ShipDamage.needs_kit(i):
			if kit_i < 0:
				kit_i = i
			elif kit_j < 0:
				kit_j = i
		elif free_i < 0:
			free_i = i
	var d0: float = f.model.damage
	var wrong: OnFoot = f.foot_c
	f.eva.pos = (f.view._damage.sites[kit_i].pos as Vector3) + (f.view._damage.sites[kit_i].normal as Vector3) * 1.2
	check(wrong.eva_work(0.05, true, "wrench").contains("torch"), "the wrench won't close a hole")
	wrong.eva_work(0.05, false)
	check(_fix(f, free_i) == "done" and is_equal_approx(f.model.damage, d0 - 1.0 / 16.0) and Session.patch_kits() == 1, "loose plating: fixed by hand, no kit used")
	check(not f.foot_c._eva_marks().has(free_i) and not f.view._damage._plates[free_i].visible, "the mark is gone: seated plating just looks like plating again")
	check(_fix(f, kit_i) == "done" and Session.patch_kits() == 0 and f.view._damage._plates[kit_i].visible, "a hole takes the patch kit, and shows a welded plate")
	var r := _fix(f, kit_j)
	check(r.contains("patch kit") and f.foot_c._eva_marks().has(kit_j), "with no kits left, the next hole stays a hole: %s" % r)
	f.model.damage = 0.52
	f.view.set_damage(0.52)
	var free2 := -1
	for i in f.foot_c._eva_marks():
		if not ShipDamage.needs_kit(i):
			free2 = i
			break
	check(_fix(f, free2) == "done" and is_equal_approx(f.model.hull(), 0.5), "from 48% one fix gets you to 50%")
	var free3 := -1
	for i in f.foot_c._eva_marks():
		if not ShipDamage.needs_kit(i):
			free3 = i
			break
	r = _fix(f, free3) if free3 >= 0 else "no mark"
	check(r.contains("yard work") and is_equal_approx(f.model.hull(), 0.5), "and no further: %s" % r)

	print("a breached hull")
	f.model.damage = 1.0
	f.view.set_damage(1.0)
	check(f.model.disabled(), "breached and dead in space")
	var any_free := -1
	for i in f.foot_c._eva_marks():
		if not ShipDamage.needs_kit(i):
			any_free = i
			break
	check(_fix(f, any_free) == "done" and not f.model.disabled() and f.model.thrust_scale() > 0.0, "one fix on a space walk and the helm answers again")

	print("coming back in")
	f.eva.pos = f.eva.hatch
	var ev := InputEventKey.new()
	ev.keycode = KEY_Q
	ev.pressed = true
	f._unhandled_input(ev)
	check(f.eva == null and f.walking and f.walk.near_airlock(), "Q at the hatch: back in the airlock")
	f.walk.stand_in_airlock()
	f.use()
	f.eva.o2 = 0.01
	f.foot_c._eva_step(0.1)
	check(f.eva == null and f.walking and f.notice.contains("AIR"), "out of air, the winch reels you in")
	f.walk.stand_in_airlock()
	f.use()
	f.foot_c._eva_step(0.05)
	check(f.foot_c._eva_ui != null and f.foot_c._air_bar.value > 0.9 and f.foot_c._tools != null, "the air, tether and strain gauges show, and a tool's in hand")
	var ev2 := InputEventKey.new()
	ev2.keycode = KEY_2
	ev2.pressed = true
	f._unhandled_input(ev2)
	check(f.eva.tool == "torch", "2 picks up the torch")
	f.eva.pos = f.eva.hatch
	f._unhandled_input(ev)
	print("adrift")
	f.walk.stand_in_airlock()
	f.use()
	f.model.throttle = 1.0   # somebody left the engine on
	var cr := int(Session.profile.credits)
	var dmg_kept: float = f.model.damage
	for k in 4000:
		f.foot_c._eva_step(0.05)
		f.model.step(0.05, Vector3.ZERO, 0.0)
		if f.leaving or f.eva == null:
			break
		if f.eva.snapped and k % 20 == 0:
			pass
	check(f.leaving and Session.flash.contains("fished"), "the engine's burning: the tether snaps, the ship leaves, and a tug fishes you out: %s" % Session.flash)
	check(int(Session.profile.credits) < cr, "for a fee")
	check(absf(float(Session.profile.hull_damage) - dmg_kept) < 0.001 and (Session.profile.get("hull_patches", []) as Array).size() >= 4, "the space-walk repairs are kept when the flight ends")
	f.queue_free()
	await process_frame
	Session.profile["hull_damage"] = 0.8
	Session.save_profile()
	Session.flight_job = {}
	f = load(Session.FLIGHT_SCENE).instantiate()
	root.add_child(f)
	current_scene = f
	await process_frame
	f.model.pos = Vector3(0, 0, 3000)
	check(f.view._damage.patched.size() >= 4, "the welded patches are still there next flight")
	f._return_to_dock()
	await process_frame

	print("the repair desk")
	Session.profile["credits"] = 100000
	Session.save_profile()
	var price := Session.patch_kit_price()
	var b := Session.buy_patch_kits(3)
	check(bool(b.ok) and Session.patch_kits() == 3 and price > 0, "patch kits are %d cr each: %s" % [price, b.message])
	b = Session.buy_patch_kits(99)
	check(Session.patch_kits() == Session.patch_kit_max() and not bool(Session.buy_patch_kits(1).ok), "the locker holds %d" % Session.patch_kit_max())
	check(bool(Session.repair_hull().ok) and (Session.profile.get("hull_patches", []) as Array).is_empty(), "a yard repair replaces the patches with proper plating")
	check(absf(float(Session.sim.summary()["cash_error"])) < 0.01, "money conserved")
	print("DONE fails=", fails)
	quit(1 if fails > 0 else 0)
