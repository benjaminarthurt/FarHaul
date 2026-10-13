extends SceneTree
## Wear and tear (Wear): parts weaken as they wear and stop when they fail; flying, overheating, firing
## thrusters, landing and knocks wear them; autopilot trips too; the cockpit warns; a space walk services
## worn parts (free, up to 50%) and brings failed ones back with a spares kit; the yard overhauls.
## Run: godot --headless --path . --script res://tests/test_wear.gd
var fails := 0
func check(ok: bool, msg: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + msg)
	if not ok:
		fails += 1
func _initialize() -> void:
	SaveSlots.dir = "user://test_saves_wear_%d" % OS.get_process_id()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SaveSlots.dir))
	process_frame.connect(_run, CONNECT_ONE_SHOT)


func _engine_key(ship: ShipData) -> String:
	for p in Wear.parts(ship, {}):
		if String(p.kind) == "engine":
			return String(p.key)
	return ""


func _run() -> void:
	var ship := ShipData.new(ModuleLibrary.new())
	ShipPresets.build(ship)
	var st := ShipStats.compute(ship, 0.0)
	var parts := Wear.parts(ship, {})
	var kinds := {}
	for p in parts:
		kinds[String(p.kind)] = true
	check(kinds.has("engine") and kinds.has("radiator") and parts.size() == 4, "the starter's working parts: an engine and three radiators (%d)" % parts.size())
	var e0 := Wear.effective(ship, {})
	check(is_equal_approx(float(e0.thrust_fwd), float(st.thrust_fwd)) and is_equal_approx(float(e0.cooling), float(st.cooling)), "new parts give exactly what the stats say")
	var ek := _engine_key(ship)
	var half := Wear.effective(ship, {ek: 0.5})
	check(absf(float(half.thrust_fwd) - float(st.thrust_fwd) * 0.8) < 0.01, "a half-worn engine pushes 80%")
	check(float(Wear.effective(ship, {ek: 1.0}).thrust_fwd) == 0.0, "a failed one doesn't push at all")
	var w := {}
	var crossed := Wear.add(w, ship, "engine", 0.8)
	check(crossed.get(ek, "") == "worn", "past 75% worn it says so")
	crossed = Wear.add(w, ship, "engine", 0.3)
	check(crossed.get(ek, "") == "failed" and float(w[ek]) == 1.0, "and when it fails")
	check(Wear.summary(ship, w).contains("Engine FAILED"), "the summary names it: %s" % Wear.summary(ship, w))
	check(is_equal_approx(Wear.eva_fixed(0.9), 0.6) and is_equal_approx(Wear.eva_fixed(0.6), 0.5) and is_equal_approx(Wear.eva_fixed(0.5), 0.5) and is_equal_approx(Wear.eva_fixed(1.0), 0.6),
			"a space walk services down to 50% at best, and a spares kit brings a failed part back to 40%")

	print("in flight")
	Session.begin_new(2, "Test Captain", "human", "normal", "roosevelt_independent_yards")
	Session.profile["wear"] = {ek: 0.749}
	Session.save_profile()
	Session.flight_job = {}
	var f: Node = load(Session.FLIGHT_SCENE).instantiate()
	root.add_child(f)
	current_scene = f
	await process_frame
	check(absf(f.model.thrust_kn - float(st.thrust_fwd) * (1.0 - 0.4 * 0.749)) < 0.01, "the flight starts with the worn engine's thrust (%.1f kN)" % f.model.thrust_kn)
	f.model.pos = Vector3(0, 0, 5000)
	f.model.station_solid = false
	f.model.throttle = 1.0
	for i in 400:   # 20 s of full burn
		f.model.step(0.05)
		f._wear_step(0.05)
	check(float(f.wear[ek]) > 0.749 and f.notice.contains("ENGINE WORN"), "burning wears it, and the cockpit warns: %s" % f.notice)
	var before := float(f.wear[ek])
	f.model.hurt(0.2)
	f._wear_step(0.05)
	var moved := false
	for k in f.wear:
		if String(k) != ek and float(f.wear[k]) > 0.0:
			moved = true
	check(moved or float(f.wear[ek]) > before + 0.2, "a knock to the hull shakes a part loose")
	f.wear[ek] = 0.9999
	f._wear_step(5.0)
	check(f.model.thrust_kn == 0.0 and f.notice.contains("FAILED"), "the engine fails: no thrust, and an alarm: %s" % f.notice)
	f._update_hud()
	check(f.hud.text.contains("PARTS") and f.hud.text.contains("ENGINE FAILED"), "the HUD lists the parts in trouble")
	check(String(f.remote_state().get("parts", "")).contains("Engine FAILED"), "and so does the remote")

	print("a space walk")
	f.model.throttle = 0.0
	f.get_up()
	f.walk.stand_in_airlock()
	f.use()
	var targets: Dictionary = f.foot_c._eva_targets()
	var eng_t := -1
	for t in targets:
		if int(t) >= OnFoot.PART:
			var p: Dictionary = f.foot_c._part(int(t))
			if String(p.kind) == "engine":
				eng_t = int(t)
	check(eng_t >= OnFoot.PART, "the failed engine is a job outside")
	f.eva.pos = (targets[eng_t] as Vector3) + Vector3(0, 2.0, 0)
	var r: String = f.foot_c.eva_work(0.05, true, "wrench")
	check(r.contains("spares kit"), "without a spares kit it stays dead: %s" % r)
	f.foot_c.eva_work(0.05, false)
	Session.profile["spares_kits"] = 1
	r = f.foot_c.eva_work(0.05, true, "torch")
	check(r.contains("wrench"), "machinery wants the wrench: %s" % r)
	f.foot_c.eva_work(0.05, false)
	for k in 400:
		r = f.foot_c.eva_work(0.05, true, "wrench")
		if r != "working":
			break
	f.foot_c.eva_work(0.05, false)
	check(r == "done" and is_equal_approx(float(f.wear[ek]), 0.6) and Session.spares_kits() == 0 and f.model.thrust_kn > 0.0, "the spares kit brings it back to 40%, and it pushes again")
	for k in 400:
		r = f.foot_c.eva_work(0.05, true, "wrench")
		if r != "working":
			break
	f.foot_c.eva_work(0.05, false)
	check(r == "done" and is_equal_approx(float(f.wear[ek]), 0.5), "a wrench service takes it to 50%, free")
	check(not f.foot_c._eva_targets().has(eng_t), "and that's as far as a space walk goes: the rest is yard work")
	f.foot_c.end_space_walk()
	f.sit_down()
	f._return_to_dock()
	await process_frame
	check(is_equal_approx(float((Session.profile.get("wear", {}) as Dictionary).get(ek, 0.0)), 0.5), "the wear is kept when the flight ends")

	print("autopilot and the yard")
	var job: Dictionary = {}
	for o in Contracts.offers_from(String(Session.profile.port_id)):
		if bool(o.get("local", false)) and String(o.get("person_kind", "")) == "":
			job = o
			break
	Session.accept_contract(job)
	var wb := float(Session.wear()[ek])
	check(bool(Session.depart_active_contract().ok) and float(Session.wear()[ek]) > wb, "an autopilot run wears the engine too (%.3f to %.3f)" % [wb, float(Session.wear()[ek])])
	Session.deliver_active_contract()
	var all_dead := {}
	for p in Wear.parts(ship, {}):
		if String(p.kind) == "engine":
			all_dead[String(p.key)] = 1.0
	Session.profile["wear"] = all_dead
	check(Session.hull_block(false).contains("engine"), "with every engine failed, nothing leaves: %s" % Session.hull_block(false))
	Session.profile["credits"] = 200000
	Session.save_profile()
	var cost := Session.overhaul_cost()
	check(cost > 0 and bool(Session.overhaul_parts().ok) and Session.wear().is_empty() and Session.hull_block(false) == "", "the yard overhauls everything to new for %d cr" % cost)
	check(bool(Session.buy_spares_kit().ok) and Session.spares_kits() == 1, "spares kits are sold at the desk (%d cr)" % Session.spares_kit_price())
	check(absf(float(Session.sim.summary()["cash_error"])) < 0.01, "money conserved")
	print("DONE fails=", fails)
	quit(1 if fails > 0 else 0)
