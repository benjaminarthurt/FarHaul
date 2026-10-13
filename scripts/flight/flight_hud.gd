class_name FlightHud
extends RefCounted
## The flight scene's on-screen readouts: the HUD text for free flight, local runs, the descent and
## lift-off, the prompts when walking the ship or out in the suit, and the flight markers. It builds
## the labels in _build_hud() and refreshes them in _update_hud(); the labels themselves stay on the
## scene (hud, prompt, bar, help, crosshair, beacon, reticle) where other code reads them.

var sc: FlightScene   ## the scene this works on


func _init(scene: FlightScene) -> void:
	sc = scene


func _build_hud() -> void:
	var layer := CanvasLayer.new()
	sc.add_child(layer)
	sc.hud = Label.new()
	sc.hud.position = Vector2(28, 24)
	sc.hud.add_theme_font_size_override("font_size", 18)
	sc.hud.add_theme_color_override("font_color", Brand.OFFWHITE)
	layer.add_child(sc.hud)
	sc.prompt = Label.new()
	sc.prompt.add_theme_font_size_override("font_size", 22)
	sc.prompt.add_theme_color_override("font_color", Brand.AMBER)
	sc.prompt.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM, Control.PRESET_MODE_MINSIZE, 60)
	sc.prompt.grow_horizontal = Control.GROW_DIRECTION_BOTH
	sc.prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sc.prompt.grow_vertical = Control.GROW_DIRECTION_BEGIN   # a second line goes up, not over the key strip
	layer.add_child(sc.prompt)
	sc.time_label = Label.new()   # time compression, big enough to notice
	sc.time_label.add_theme_font_size_override("font_size", 26)
	sc.time_label.add_theme_color_override("font_color", Brand.AMBER)
	sc.time_label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	sc.time_label.add_theme_constant_override("outline_size", 6)
	sc.time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT   # top right, clear of the readouts and below F3's
	sc.time_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE, 28)
	sc.time_label.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	sc.time_label.position.y = 96
	sc.time_label.visible = false
	layer.add_child(sc.time_label)
	sc.bar = ProgressBar.new()
	sc.bar.custom_minimum_size = Vector2(26, 160)
	sc.bar.fill_mode = ProgressBar.FILL_BOTTOM_TO_TOP
	sc.bar.max_value = 1.0
	sc.bar.show_percentage = false
	sc.bar.position = Vector2(28, 230)
	layer.add_child(sc.bar)
	sc.help = Brand.note(sc.FLY_HELP, 13)
	sc.help.autowrap_mode = TextServer.AUTOWRAP_OFF
	sc.help.custom_minimum_size = Vector2(1000, 0)
	sc.help.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT, Control.PRESET_MODE_MINSIZE, 20)
	layer.add_child(sc.help)
	sc.crosshair = Label.new()
	sc.crosshair.text = "+"
	sc.crosshair.add_theme_font_size_override("font_size", 22)
	sc.crosshair.add_theme_color_override("font_color", Color(Brand.OFFWHITE, 0.7))
	sc.crosshair.set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_MINSIZE)
	sc.crosshair.grow_horizontal = Control.GROW_DIRECTION_BOTH
	sc.crosshair.grow_vertical = Control.GROW_DIRECTION_BOTH
	sc.crosshair.visible = false
	layer.add_child(sc.crosshair)
	sc.reticle = FlightReticle.new()
	layer.add_child(sc.reticle)
	layer.move_child(sc.reticle, 0)


## Nose, prograde and retrograde markers, at the helm in either camera (not on foot or mid-jump).
func _update_reticle() -> void:
	if sc.reticle == null:
		return
	sc.reticle.nose = Vector2.INF
	sc.reticle.prograde = Vector2.INF
	sc.reticle.retrograde = Vector2.INF
	if sc.walking or sc.outside or sc._jumping():
		sc.reticle.target_edge = Vector2.INF   # no stale arrow to a station that's light years behind
		sc.reticle.travel_edge = Vector2.INF
		sc.reticle.queue_redraw()
		return
	sc.reticle.nose = sc._screen_dir(sc.model.forward())
	sc.reticle.target_edge = Vector2.INF
	sc.reticle.travel_edge = Vector2.INF
	var v := sc.model.vel
	if sc.model.landed or v.length() < 0.3:
		pass
	else:
		sc.reticle.prograde = sc._screen_dir(v.normalized())
		sc.reticle.retrograde = sc._screen_dir(-v.normalized())
	var goal := _goal()   # where you are flying to: an arrow round the edge when it is off screen
	var to_goal := Vector3.ZERO
	if not goal.is_empty():
		to_goal = goal.at - sc.model.pos
		if to_goal.length() > 1.0 and sc._screen_dir(to_goal.normalized()) == Vector2.INF:
			var e := _edge(to_goal.normalized())
			sc.reticle.target_edge = e.pos
			sc.reticle.target_edge_dir = e.dir
			sc.reticle.target_text = "%s  %s" % [goal.name, _distance(to_goal.length())]
	if sc.reticle.prograde != Vector2.INF or sc._on_surface() or sc.model.landed or v.length() < 0.3:
		pass
	elif sc.reticle.target_edge != Vector2.INF and v.angle_to(to_goal) < deg_to_rad(10.0):
		pass   # travelling toward an off-screen target: its arrow already says which way
	else:
		var e := _edge(v.normalized())   # travel off screen: its own arrow
		sc.reticle.travel_edge = e.pos
		sc.reticle.travel_edge_dir = e.dir
	sc.reticle.queue_redraw()


## The place being flown to, {at, name}: a run's target, else the station; {} on a moon.
func _goal() -> Dictionary:
	if sc._on_surface():
		return {}
	if sc.xfer != null and sc.phase in ["depart", "cruise"]:
		return {"at": sc.xfer.target, "name": "◆ " + String(sc.job.destination)}
	return {"at": Vector3.ZERO, "name": String(sc.station_label.text) if sc.station_label != null else "STATION"}


## Where to put an arrow toward an off-screen direction, round an oval inside the screen's edges, and
## which way it points: {pos, dir}. Directions behind the camera get the arrow on the side to turn toward.
func _edge(dir: Vector3) -> Dictionary:
	var local := sc.camera.global_basis.inverse() * dir
	var d2 := Vector2(local.x, -local.y)
	if d2.length() < 0.0001:
		d2 = Vector2(0, 1)   # straight behind: point down, turn either way
	d2 = d2.normalized()
	var size := sc.get_viewport().get_visible_rect().size
	# On an oval inside the edges, clear of the readouts top left and the prompt at the bottom.
	return {"pos": size * 0.5 + Vector2(d2.x * size.x * 0.4, d2.y * size.y * 0.34), "dir": d2}


static func _distance(m: float) -> String:
	return "%.0f m" % m if m < 1000.0 else ("%.1f km" % (m / 1000.0) if m < 1.0e6 else "%.0f km" % (m / 1000.0))


## Where a direction from the ship lands on screen, or INF if it is behind the camera.
func _screen_dir(dir: Vector3) -> Vector2:
	var far := sc.model.pos + dir * 2000.0
	if sc.camera.is_position_behind(far):
		return Vector2.INF
	var p := sc.camera.unproject_position(far)
	var size := sc.get_viewport().get_visible_rect().size
	if p.x < 0.0 or p.y < 0.0 or p.x > size.x or p.y > size.y:
		return Vector2.INF
	return p


## The time readout, top right. Running at the rate chosen: the rate and the keys. Chosen faster than
## the limit here: the rate actually running, the rate chosen, and why it is capped (it comes back on
## its own as the cap lifts). Back at x1: shown for a moment after any , . or / press, with the reason
## if time compression can't be used here. Hidden otherwise.
func _update_time() -> void:
	if sc.time_label == null:
		return
	var chosen: int = sc.WARPS[sc.warp_index]
	var running: int = sc._warp()
	var lim: Dictionary = sc._warp_limit()
	sc.time_shown_s = maxf(0.0, sc.time_shown_s - sc.get_process_delta_time())
	if chosen > 1 and running == chosen:
		sc.time_label.text = "TIME x%d\n, . change   / back to x1" % chosen
	elif chosen > 1:
		sc.time_label.text = "TIME x%d   (x%d set)\n%s\n/ back to x1" % [running, chosen, lim.why]
	elif sc.time_shown_s > 0.0:
		sc.time_label.text = "TIME x1" + ("\n" + String(lim.why) if int(lim.max) <= 1 else "")
	else:
		sc.time_label.text = ""
	sc.time_label.visible = sc.time_label.text != ""


## How far the direction of travel is off the target: on course, a few degrees off, or moving away.
func _course_line() -> String:
	if sc.model.speed() < 5.0:
		return "COURSE  not moving: point at the diamond and burn"
	var to := sc.xfer.target - sc.model.pos
	var off := rad_to_deg(sc.model.vel.angle_to(to))
	if off < 0.5:
		return "COURSE  on target"
	if off > 90.0:
		return "COURSE  moving away from the target (%.0f° off)" % off
	return "COURSE  %.1f° off target: burn toward the diamond to correct" % off


func _update_transfer_hud() -> void:
	var rng := sc.xfer.range_to(sc.model)
	var eta := sc.xfer.eta_s(sc.model)
	var lines := PackedStringArray([
		"RUN TO  %s    HOP  %.1f km/s" % [String(sc.job.destination).to_upper(), float(sc.job.dv_kms)],
		"TARGET  %.1f km    CLOSING  %+.0f m/s    ETA  %s" % [rng / 1000.0, sc.xfer.closing(sc.model), _eta_text(eta)],
		_course_line(),
		"SPEED  %.0f m/s    STOPS IN  %.1f km" % [sc.model.speed(), sc.xfer.stopping_distance(sc.model) / 1000.0],
		"THROTTLE  %d%%    THRUST  %d%%    TIME x%d" % [roundi(sc.model.throttle * 100.0), roundi(sc.model.thrust_scale() * 100.0), sc._warp()],
		"FUEL  %.2f t    ΔV %.0f m/s    PERFECT RUN %.2f t" % [sc.model.fuel_t, sc.model.delta_v(), sc.xfer.ideal_burn_t],
		"MASS  %.1f t    ACCEL %.2f m/s²" % [sc.model.mass_t(), sc.model.accel() if sc.model.throttle > 0.0 else sc.model.max_accel()],
		_hull_line(),
		"ASSIST %s   %s" % ["ON" if sc.model.assist else "OFF", "AUTOPILOT BRAKING" if sc.model.braking else ("COURSE HOLD" if sc.model.course_hold else "")]])
	sc.hud.text = "\n".join(lines)
	sc.bar.value = sc.model.throttle
	var to := sc.xfer.target - sc.model.pos
	if sc.reticle.target_edge == Vector2.INF and not sc.camera.is_position_behind(sc.camera.global_position + to):
		sc.beacon.visible = true
		var sp := sc.camera.unproject_position(sc.camera.global_position + to.normalized() * 1000.0)
		sc.beacon.position = sp + Vector2(12, -12)
		sc.beacon.text = "◆ %s  %.1f km" % [String(sc.job.destination), rng / 1000.0]
	else:
		sc.beacon.visible = false
	var hint := ""
	if sc.notice_s > 0.0:
		hint = sc.notice
	elif not sc.model.has_fuel() and not sc.xfer.arrived(sc.model):
		var fee := ShipStats.commas(sc.tow_fee())
		if sc.tow_goes_on():
			hint = "OUT OF FUEL. T: a tug tows you on to %s, the nearer (%s), and the run is delivered. Tow %s cr, sympathy extra." % [String(sc.job.destination), _distance(sc.xfer.range_to(sc.model)), fee]
		elif String(sc.job.get("dest_kind", "")) in LocalSpace.SURFACE:
			hint = "OUT OF FUEL. T: a tug tows you back to the start. It's a tug: it can't land you. Tow %s cr." % fee
		else:
			hint = "OUT OF FUEL. T: a tug tows you back to the start, the nearer (%s). Tow %s cr, payable in advance." % [_distance(sc.model.pos.length()), fee]
	elif sc.model.overheated:
		hint = "ENGINES OVERHEATED. Wait while they cool and sulk."
	elif sc.model.braking:
		hint = sc.brake_status()
	elif sc.model.course_hold and not sc.xfer.brake_now(sc.model):
		hint = sc.course_status()
	elif sc.xfer.brake_now(sc.model):
		hint = "BRAKE NOW: press X and the autopilot stops you at the target."
	elif sc.xfer.closing(sc.model) < -1.0:
		hint = "Moving away from the destination. It won't follow."
	elif sc.beacon != null and not sc.beacon.visible:
		hint = "The destination is off screen. Turn toward the orange arrow; it knows."
	elif sc.model.speed() < 5.0:
		hint = "Point at the diamond, throttle up (W), period speeds time up. Esc for the menu to turn back. The cargo won't haul itself."
	sc.prompt.text = hint


## Heat and hull, with whatever the hull's faults are doing.
func _hull_line() -> String:
	var m := sc.model
	var line := "HEAT  %d%%    HULL  %d%%" % [roundi(m.heat_fraction() * 100.0), roundi(m.hull() * 100.0)]
	for f in m.faults():
		match f:
			"disabled":
				line += "    BREACHED"
			"cooling":
				line += "    RADIATORS %d%%" % roundi(m.cooling_now_kw() / maxf(m.cooling_kw, 0.001) * 100.0)
			"leak":
				line += "    LEAK %.1f t/h" % m.leak_t_per_h()
			"cargo":
				line += "    CARGO AT RISK" if m.cargo_t > 0.0 else ""
	return line


func _update_hud() -> void:
	_update_hud_body()
	# A breached hull wins the prompt at the helm: there's only one thing left to do.
	var at_helm := not sc.walking and not sc.outside and sc.eva == null and not sc._jumping()
	if sc.model.disabled() and at_helm:
		sc.prompt.text = sc.rescue_hint()
	elif at_helm and sc.notice_s > 0.0:
		sc.prompt.text = sc.notice   # a fresh message wins the prompt everywhere, not just on a run
	if sc.model.strafe != Vector2.ZERO and at_helm:
		var dirs := PackedStringArray()
		if sc.model.strafe.x < 0.0: dirs.append("LEFT")
		if sc.model.strafe.x > 0.0: dirs.append("RIGHT")
		if sc.model.strafe.y > 0.0: dirs.append("UP")
		if sc.model.strafe.y < 0.0: dirs.append("DOWN")
		sc.hud.text += "\nMANOEUVRING  %s" % " ".join(dirs)
	if sc.model.retro > 0.02 and at_helm and not sc._on_surface():
		sc.hud.text += "\nBRAKING THRUSTERS  %d%%    -%.2f m/s²" % [roundi(sc.model.retro * 100.0), sc.model.retro_kn * sc.model.retro * sc.model.thrust_scale() / maxf(sc.model.mass_t(), 0.001)]
	sc.prompt.add_theme_color_override("font_color", Brand.ALARM if sc.model.disabled() or (sc.notice_s > 0.0 and sc.notice.begins_with("HULL")) else Brand.AMBER)


func _update_hud_body() -> void:
	_update_time()
	if sc.eva != null:
		sc.notice_s = maxf(0.0, sc.notice_s - sc.get_process_delta_time())
		sc.foot_c._eva_hud()
		return
	sc.notice_s = maxf(0.0, sc.notice_s - sc.get_process_delta_time())
	if sc._on_surface():
		sc._update_descent_hud()
		if sc.outside:
			sc._suit_prompt()
		elif sc.walking:
			sc._walk_prompt()
		return
	if sc.xfer != null and sc.phase != "approach":
		sc._update_transfer_hud()
		if sc.walking:
			sc._walk_prompt()
		return
	var dist := sc.model.pos.length()
	var closing := -sc.model.vel.dot(sc.model.pos.normalized()) if dist > 0.01 else 0.0
	var al := sc.model.dock_alignment()
	var lines := PackedStringArray([
		"SPEED  %.1f m/s    CLOSING  %+.1f m/s" % [sc.model.speed(), closing],
		"STATION  %.0f m    PORT  %.0f m" % [dist, al.distance],
		"THROTTLE  %d%%    THRUST  %d%%" % [roundi(sc.model.throttle * 100.0), roundi(sc.model.thrust_scale() * 100.0)],
		"FUEL  %.2f t    ΔV %.0f m/s" % [sc.model.fuel_t, sc.model.delta_v()],
		"MASS  %.1f t    ACCEL %.2f m/s²" % [sc.model.mass_t(), sc.model.accel() if sc.model.throttle > 0.0 else sc.model.max_accel()],
		_hull_line(),
		"ASSIST %s   %s" % ["ON" if sc.model.assist else "OFF", "AUTOPILOT BRAKING" if sc.model.braking else ""]])
	if sc.phase == "approach":
		lines.insert(0, "APPROACH  %s    T: traffic control brings you in" % String(sc.job.destination).to_upper())
	sc.hud.text = "\n".join(lines)
	sc.bar.value = sc.model.throttle
	if sc.model.can_dock():
		sc.prompt.text = "Press F to dock"
	elif al.distance < 60.0:
		var hints := PackedStringArray()
		if al.nose_deg > float(sc.model.tune.get("dock_nose_deg", 25.0)):
			hints.append("point the nose at the collar (%d° off)" % roundi(al.nose_deg))
		if al.lateral > float(sc.model.tune.get("dock_lateral_m", 8.0)):
			hints.append("line up on the axis (%.0f m off)" % al.lateral)
		if sc.model.speed() > float(sc.model.tune.get("dock_speed_m_s", 3.0)):
			hints.append("slow below %.0f m/s" % float(sc.model.tune.get("dock_speed_m_s", 3.0)))
		if al.distance > float(sc.model.tune.get("dock_range_m", 18.0)):
			hints.append("close in")
		sc.prompt.text = "To dock: " + ", ".join(hints)
	else:
		sc.prompt.text = ""
	if sc.model.overheated:
		sc.prompt.text = "ENGINES OVERHEATED. Wait while they cool and sulk."
	elif sc.model.last_impact > float(sc.model.tune.get("soft_impact_m_s", 1.5)) and sc.model.elapsed_s - sc._impact_shown < 3.0:
		sc.prompt.text = "HULL IMPACT"
	if not sc.model.has_fuel() and sc.model.speed() > 1.0:
		sc.prompt.text = "OUT OF FUEL. Drifting, free of charge."
	if String(sc.job.get("kind", "")) == "jump" and sc.phase == "depart" and not sc.model.overheated:
		var why := sc._jump_blocker()
		sc.prompt.text = "J: engage the FTL drive for %s (%.1f ly)" % [String(sc.job.destination), float(sc.job.ly)] if why == "" else "Jump to %s: %s" % [String(sc.job.destination), why]
	elif sc._jumping():
		sc.prompt.text = "FTL DRIVE SPOOLING" if sc.phase == "spool" else ""
	if sc.walking:
		sc._walk_prompt()


func _walk_prompt() -> void:
	var where := sc.walk.room()
	var hint := ""
	if sc.walk.near_helm():
		hint = "E: take the helm"
	elif not sc.walk.hatch_here().is_empty():
		var hx := sc.walk.hatch_here()
		hint = "E: climb %s (look up or down)" % ("up or down" if bool(hx.up) and bool(hx.down) else ("up" if bool(hx.up) else "down"))
	elif sc.walk.near_airlock():
		if sc._on_surface():
			hint = "E: step outside onto the surface" if sc.model.landed else "Outer hatch stays shut until the ship is down. Wise policy."
		else:
			hint = "E: leave the ship" if sc._berthed() else ("E: suit up and go out on the tether" if sc.foot_c.space_walk_blocker() == "" else "Outer hatch stays shut. Outside is mostly vacuum.")
	var warn := ""
	if sc.model.disabled():
		warn = "HULL BREACHED: back to the helm and call the tug (T)"
	elif sc.model.overheated:
		warn = "ENGINES OVERHEATED"
	elif not sc.model.has_fuel() and sc.model.speed() > 1.0:
		warn = "OUT OF FUEL"
	elif sc.model.last_impact > float(sc.model.tune.get("soft_impact_m_s", 1.5)) and sc.model.elapsed_s - sc._impact_shown < 3.0:
		warn = "HULL IMPACT"
	elif sc.model.braking:
		warn = sc.brake_status().get_slice("   ", 0)
	elif sc.xfer != null and sc.phase == "cruise" and sc.xfer.brake_now(sc.model):
		warn = "BRAKE NOW: get back to the helm"
	var parts := PackedStringArray()
	for t in [warn, where.to_upper() if where != "" else "", hint]:
		if t != "":
			parts.append(t)
	sc.prompt.text = "   ".join(parts)


func _update_descent_hud() -> void:
	var to_pad := Vector2(sc.model.pos.x - sc.model.pad.x, sc.model.pos.z - sc.model.pad.z).length()
	var alt := sc.model.altitude()
	var body := sc._body()
	var target := "MINING CAMP" if sc._target_kind == "camp" else "BASE PAD"
	var head := ""
	if sc.phase == "ascent":
		head = "LIFT-OFF  %s    %s" % [String(body.get("name", "Moon")).to_upper(), "AUTO LIFT ON (T)" if sc.auto_ascent else "T: lift off on auto"]
	elif sc.job.is_empty():
		head = "%s  %s    %s" % [String(body.get("name", "Moon")).to_upper(), target, "HOVER HOLD (H)" if sc.hover_hold else "F on the pad: shut down"]
	else:
		head = "DESCENT  %s  %s    %s" % [String(sc.job.get("destination", "")).to_upper(), String(body.get("name", "")).to_upper(),
				"AUTOLAND ON (T)" if sc.model.autoland else ("no beacon: land by hand" if not sc._beacon else ("HOVER HOLD (H)" if sc.hover_hold else "T: autoland"))]
	var lines := PackedStringArray([head,
		"ALTITUDE  %.0f m    V/S  %+.1f m/s    DRIFT  %.1f m/s" % [alt, sc.model.vel.y, Vector2(sc.model.vel.x, sc.model.vel.z).length()],
		("CLIMB TO  %.0f m" % float(sc.model.land_cfg.get("ascent_clear_m", 1500.0))) if sc.phase == "ascent" else "%s  %.0f m    TILT  %.0f°" % [target, to_pad, sc.model.tilt_deg()],
		"LIFT  %d%%    %.2f m/s² available, gravity %.2f" % [roundi(sc.model.lift * 100.0), sc.model.lift_accel(), sc.model.gravity],
		"THROTTLE  %d%%    FUEL  %.2f t" % [roundi(sc.model.throttle * 100.0), sc.model.fuel_t],
		_hull_line()])
	sc.hud.text = "\n".join(lines)
	sc.bar.value = sc.model.lift
	if sc.pad_label != null:
		sc.pad_label.visible = alt > 80.0 and not sc.outside   # a sc.beacon from above, not a wall of text up close
	if sc.job.is_empty() and sc.phase == "descent":
		var near := PackedStringArray()
		for st in SurfaceSites.sites(sc._system_id()):
			near.append("%s %.1f km" % [String(st.name), Vector2(sc.model.pos.x - float(st.x), sc.model.pos.z - float(st.z)).length() / 1000.0])
		var c := SurfaceFinds.camp_xz()
		near.append("Camp %.1f km" % (Vector2(sc.model.pos.x - c.x, sc.model.pos.z - c.y).length() / 1000.0))
		sc.hud.text += "\nSITES  " + "   ".join(near)
	if sc.model.hazards_seen != sc._hazards_shown:
		sc._hazards_shown = sc.model.hazards_seen
		sc._hazard_t = sc.model.elapsed_s
	var hint := ""
	if sc.model.elapsed_s - sc._hazard_t < 5.0 and sc.model.hazard != "":
		sc.prompt.text = sc.model.hazard.to_upper()
		return
	if sc.phase == "ascent":
		if sc.model.landed:
			hint = "Space: lift off (or T for auto).  F: stay and shut down.  G: get up and walk outside."
		elif not sc.model.has_fuel():
			hint = "OUT OF FUEL"
		else:
			hint = "Climb clear of the moon; it wants you back. W/S runs the main engine."
	elif sc.model.landed and sc.model.on_pad():
		hint = ("Landed, in one piece. F: shut down and unload.   G: get up and walk outside.") if not sc.job.is_empty() else "On the pad. F: shut down.   G: get up and walk outside."
	elif sc.model.landed:
		hint = "Down %.0f m from the %s. Close isn't landed. Lift off (Space) and set down within %d m%s." % [to_pad, "camp's pad" if sc._target_kind == "camp" else "pad",
				int(sc.model.zone_m if sc.model.zone_m > 0.0 else float(sc.model.land_cfg.get("landing_zone_m", 120.0))),
				"" if sc.model.has_fuel() else ". Out of fuel: F calls a crawler to tow you in"]
	elif not sc.model.has_fuel():
		hint = "OUT OF FUEL"
	elif sc.model.last_impact > float(sc.model.tune.get("soft_impact_m_s", 1.5)) and sc.model.elapsed_s - sc._impact_shown < 3.0:
		hint = "HARD LANDING"
	elif alt < 60.0 and sc.model.vel.y < -float(sc.model.land_cfg.get("touchdown_speed_m_s", 3.0)) * 1.5:
		hint = "SINKING FAST: hold Space"
	elif not sc.model.autoland:
		hint = "Space: lift jets.  H: hover.  Tilt to drift toward the pad.%s" % ("  T: let the autopilot land." if sc._beacon else "")
	sc.prompt.text = hint


func _suit_prompt() -> void:
	var d := sc.suit.distance_to(sc.suit_hatch)
	var parts := PackedStringArray(["%s SURFACE" % String(sc._body().get("name", "MOON")).to_upper()])
	if sc.ops != null:
		sc.hud.text = "\n".join(sc.ops.hud_lines())
	sc.bar.visible = false
	var f := sc.find_in_reach()
	var job_prompt := sc.ops.prompt() if sc.ops != null else ""
	if job_prompt != "":
		parts.append(job_prompt)
	elif not f.is_empty():
		parts.append("E: take the sample (%s)" % String(f.name) if String(f.kind) == "sample" else "E: strip salvage from the wreck")
	elif sc.model.elapsed_s - sc._find_message_t < 4.0:
		parts.append(sc._find_message)
	else:
		parts.append("E: back aboard" if d <= 2.5 else "Airlock hatch %.0f m" % d)
	var held := Session.finds_aboard() if Session.slot >= 0 else {}
	if int(held.get("value", 0)) > 0:
		parts.append("Locker: %s" % SurfaceFinds.describe(held))
	sc.prompt.text = "   ".join(parts)


## A time to arrival that reads at a glance: "45 s", "12 min", "3 h 20 min", or a dash when the ship
## is not closing fast enough for it to mean anything.
static func _eta_text(eta: float) -> String:
	if eta < 0.0 or eta > 86400.0 * 3.0:
		return "-"
	if eta < 90.0:
		return "%d s" % roundi(eta)
	if eta < 3600.0:
		return "%d min" % roundi(eta / 60.0)
	return "%d h %02d min" % [int(eta / 3600.0), int(fmod(eta, 3600.0) / 60.0)]
