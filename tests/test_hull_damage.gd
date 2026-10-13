extends SceneTree
## A battered hull: faults as it goes (radiators from 75%, a fuel leak from 50%, cargo knocks below
## 25%), warnings as it passes each mark, ports that won't clear an unsafe ship for freight, patches
## at the repair desk (on account if need be), and at 0% a disabled ship and the rescue tug, with its
## salvage fee and the share of the load that goes over the side, docked from the pay at delivery.
## Run: godot --headless --path . --script res://tests/test_hull_damage.gd
var fails := 0
func check(ok: bool, msg: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + msg)
	if not ok:
		fails += 1
func _initialize() -> void:
	SaveSlots.dir = "user://test_saves_hull_damage_%d" % OS.get_process_id()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SaveSlots.dir))
	process_frame.connect(_run, CONNECT_ONE_SHOT)


func _model() -> FlightModel:
	var ship := ShipData.new(ModuleLibrary.new())
	ShipPresets.build(ship)
	var m := FlightModel.from_stats(ShipStats.compute(ship, 0.0))
	m.station_solid = false
	m.pos = Vector3(0, 0, 5000)
	return m


func _run() -> void:
	print("the flight model")
	var m := _model()
	check(m.faults().is_empty() and is_equal_approx(m.cooling_now_kw(), m.cooling_kw) and m.leak_t_per_h() == 0.0, "a sound hull has no faults")
	m.hurt(0.3)
	check(m.faults() == ["cooling"] and m.cooling_now_kw() < m.cooling_kw and m.leak_t_per_h() == 0.0, "at 70%% the radiators crack (%d%% left)" % roundi(m.cooling_now_kw() / m.cooling_kw * 100.0))
	m.hurt(0.3)
	check("leak" in m.faults() and m.leak_t_per_h() > 0.0, "at 40%% the tanks weep (%.2f t/h)" % m.leak_t_per_h())
	var f0 := m.fuel_t
	var b0 := m.fuel_burned_t
	for i in 360:
		m.step(10.0)
	var lost := f0 - m.fuel_t
	check(absf(lost - m.leak_t_per_h()) < 0.02 and absf((m.fuel_burned_t - b0) - lost) < 0.0001 and absf(m.leaked_t - lost) < 0.0001,
			"an hour coasting loses %.2f t, counted as burned (it was paid for)" % lost)
	m.cargo_t = 5.0
	m.hurt(0.05)
	check(m.cargo_hurt == 0.0, "above 25%, knocks don't reach the cargo")
	m.damage = 0.8
	m.hurt(0.05)
	check(is_equal_approx(m.cargo_hurt, 0.1) and "cargo" in m.faults(), "below 25%%, they do (%.0f%% of the load)" % (m.cargo_hurt * 100.0))
	m.braking = true
	m.course_hold = true
	m.throttle = 0.8
	m.hurt(0.5)
	check(m.disabled() and m.faults() == ["disabled"] and m.throttle == 0.0 and not m.braking and not m.course_hold and m.thrust_scale() == 0.0,
			"at 0% the ship is disabled: no thrust, autopilots off")
	var v0 := m.vel
	var b := m.basis
	m.step(1.0, Vector3(1, 1, 0), 1.0, 1.0)
	check(m.vel == v0 and m.basis.is_equal_approx(b) and m.throttle == 0.0, "and nothing answers the helm")
	var hit := _model()
	hit.station_solid = true
	hit.pos = Vector3(0, 0, 40)
	hit.vel = Vector3(0, 0, -20)
	for i in 200:
		hit.step(0.02)
	check(hit.damage > 0.2 and hit.impacts > 0, "hitting the station still dents it (%d%%)" % roundi(hit.damage * 100.0))

	print("ports and the repair desk")
	check(Session.begin_new(3, "Test Captain", "human", "normal", "roosevelt_independent_yards"), "new game")
	check(Session.hull_block() == "" and Session.hull_block(false) == "", "a sound ship goes anywhere")
	Session.profile["hull_damage"] = 0.8
	check(Session.hull_block() != "" and Session.hull_block(false) == "", "at 20%% no freight, but it may fly empty: %s" % Session.hull_block())
	Session.profile["hull_damage"] = 1.0
	check(Session.hull_block() != "" and Session.hull_block(false) != "", "breached, it goes nowhere: %s" % Session.hull_block(false))
	var sites := Session.local_sites()
	check(not sites.is_empty() and not bool(Session.local_reposition(String(sites[0].id)).ok), "not even empty to the next site")
	var job: Dictionary = {}
	for o in Contracts.offers_from(String(Session.profile.port_id)):
		if bool(o.get("local", false)) and String(o.get("person_kind", "")) == "":
			job = o
			break
	check(not job.is_empty() and bool(Session.accept_contract(job).ok), "take a local run")
	Session.profile["hull_damage"] = 0.8
	check(not bool(Session.begin_local_flight().ok) and not bool(Session.depart_active_contract().ok), "port control won't clear it at 20%, flown or on autopilot")
	var cost := float(Session.ship_cost(Session._load_ship(SaveSlots.read(3)).ship, ModuleLibrary.new()))
	var sal := Session.salvage_fee(cost)
	check(sal > 0 and absf(float(sal) / cost - 0.08) < 0.03, "salvage is about 8%% of the ship (%d cr of %d)" % [sal, roundi(cost)])
	Session.profile["credits"] = 100000
	var po := Session.patch_options()
	check((po.afford as Dictionary).is_empty() and (po.account as Dictionary).is_empty(), "with the money, the desk just repairs it all")
	Session.profile["credits"] = Session.repair_cost(0.12)
	po = Session.patch_options()
	check(not (po.afford as Dictionary).is_empty() and absf(float(po.afford.to) - 0.30) < 0.001, "short of it, a patch as far as the money goes (to %d%%)" % roundi(float(po.afford.get("to", 0)) * 100.0))
	Session.profile["credits"] = 0
	Session.save_profile()
	po = Session.patch_options()
	check((po.afford as Dictionary).is_empty() and absf(float(po.account.get("to", 0)) - 0.30) < 0.001, "broke and unsafe, a patch on account to 30%")
	var pr := Session.patch_hull(float(po.account.to), true)
	check(bool(pr.ok) and absf(Session.hull() - 0.30) < 0.001 and int(Session.profile.credits) < 0, "patched on account: %s" % pr.message)
	check(Session.hull_block() == "", "and port control clears it for freight again")
	Session.profile["credits"] = 100000
	Session.save_profile()

	print("the rescue tug")
	check(bool(Session.begin_local_flight().ok), "hand the run to the helm")
	var cr_tow := int(Session.profile.credits)
	Session.finish_local_flight(0.4, 600.0, 0.7, false, true)
	var plain := cr_tow - int(Session.profile.credits)
	check(bool(Session.begin_local_flight().ok), "fly it again")
	var cr := int(Session.profile.credits)
	Session.flight_extra = {"rescue": true, "cargo_hurt": 0.1}
	var msg := Session.finish_local_flight(0.4, 600.0, 1.0, false, true)
	var paid := cr - int(Session.profile.credits)
	check(absf(float(paid - plain - sal)) < 2.0, "the rescue costs the tow plus %d cr salvage (%d vs %d)" % [sal, paid, plain])
	check(Session.flight_extra.is_empty() and msg.contains("salvage crew") and msg.contains("over the side"), "and says so: %s" % msg)
	var hurt := float(Session.active_contract().get("cargo_hurt", 0.0))
	check(absf(hurt - (1.0 - 0.9 * 0.7)) < 0.001, "10%% knocked plus 30%% over the side spoils %d%% of the load" % roundi(hurt * 100.0))
	check(Session.hull() == 0.0 and not bool(Session.begin_local_flight().ok), "it came home breached, and stays grounded")
	check(bool(Session.repair_hull().ok) and Session.hull() == 1.0, "until the yard fixes it")
	var pay := int(Session.active_contract().get("pay_total", roundi(float(job.offer) * float(job.rate))))
	check(bool(Session.depart_active_contract().ok), "then autopilot to the destination")
	var dl := Session.deliver_active_contract()
	check(bool(dl.ok) and String(dl.message).contains("arrived broken") and int(dl.payment) <= roundi(float(pay) * (1.0 - hurt)) + 1,
			"the consignee docks the broken share: %s" % dl.message)
	check(absf(float(Session.sim.summary()["cash_error"])) < 0.01 and Session.sim.violations.is_empty(), "money conserved")

	print("in the cockpit")
	Session.profile["hull_damage"] = 0.95
	Session.save_profile()
	Session.flight_job = {}
	var f: Node = load(Session.FLIGHT_SCENE).instantiate()
	root.add_child(f)
	current_scene = f
	await process_frame
	await process_frame
	check(f.alerts.is_empty() and f._hull_warned == 4, "old damage is shown, not announced again")
	check(f.hud.text.contains("HULL  5%") and f.hud.text.contains("LEAK"), "the HUD shows the hull and its faults")
	check(f.view._damage != null and f.view._damage.sites.size() > 4, "the skin has places to show it (%d)" % f.view._damage.sites.size())
	var shown := 0
	for d in f.view._damage._scorches:
		shown += 1 if d.visible else 0
	check(shown >= 12 and f.view._damage._vents[0].emitting and f.view._damage._vents[1].emitting, "scorched and venting at 5%% (%d marks)" % shown)
	f.model.hurt(0.2)
	await process_frame
	await process_frame
	check(f.model.disabled() and f.alerts.size() == 1 and String(f.alerts[0].level) == "breach", "the breach is announced, once")
	check(f.prompt.text.begins_with("HULL BREACHED") and f.prompt.text.contains("Esc"), "the cockpit says what to do: %s" % f.prompt.text)
	var st: Dictionary = f.remote_state()
	check(bool(st.disabled) and bool(st.can_tug) and (st.alerts as Array).size() == 1, "the remote hears about it")
	check(not bool(f.pilot("throttle", 1.0).ok) and not bool(f.pilot("brake").ok), "the controls are dead")
	check(f._jump_blocker() != "", "and no jump")
	var r: Dictionary = f.pilot("tug")
	check(bool(r.ok) and f.leaving, "the rescue tug comes")
	check(Session.flash.contains("salvage crew") and Session.hull() == 0.0, "and bills for it: %s" % Session.flash)
	print("DONE fails=", fails)
	quit(1 if fails > 0 else 0)
