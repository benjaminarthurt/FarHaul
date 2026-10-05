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
	layer.add_child(sc.prompt)
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
		sc.reticle.queue_redraw()
		return
	sc.reticle.nose = sc._screen_dir(sc.model.forward())
	var v := sc.model.vel
	if sc.model.landed or v.length() < 0.3:
		pass
	else:
		sc.reticle.prograde = sc._screen_dir(v.normalized())
		sc.reticle.retrograde = sc._screen_dir(-v.normalized())
	sc.reticle.queue_redraw()


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


func _update_transfer_hud() -> void:
	var rng := sc.xfer.range_to(sc.model)
	var eta := sc.xfer.eta_s(sc.model)
	var lines := PackedStringArray([
		"RUN TO  %s    HOP  %.1f km/s" % [String(sc.job.destination).to_upper(), float(sc.job.dv_kms)],
		"TARGET  %.1f km    CLOSING  %+.0f m/s    ETA  %s" % [rng / 1000.0, sc.xfer.closing(sc.model), _eta_text(eta)],
		"SPEED  %.0f m/s    STOPS IN  %.1f km" % [sc.model.speed(), sc.xfer.stopping_distance(sc.model) / 1000.0],
		"THROTTLE  %d%%    THRUST  %d%%    TIME x%d" % [roundi(sc.model.throttle * 100.0), roundi(sc.model.thrust_scale() * 100.0), sc._warp()],
		"FUEL  %.2f t    ΔV %.0f m/s    PERFECT RUN %.2f t" % [sc.model.fuel_t, sc.model.delta_v(), sc.xfer.ideal_burn_t],
		"MASS  %.1f t    ACCEL %.2f m/s²" % [sc.model.mass_t(), sc.model.accel() if sc.model.throttle > 0.0 else sc.model.max_accel()],
		"HEAT  %d%%    HULL  %d%%" % [roundi(sc.model.heat_fraction() * 100.0), roundi((1.0 - sc.model.damage) * 100.0)],
		"ASSIST %s   %s" % ["ON" if sc.model.assist else "OFF", "AUTOPILOT BRAKING" if sc.model.braking else ""]])
	sc.hud.text = "\n".join(lines)
	sc.bar.value = sc.model.throttle
	var to := sc.xfer.target - sc.model.pos
	if not sc.camera.is_position_behind(sc.camera.global_position + to):
		sc.beacon.visible = true
		var sp := sc.camera.unproject_position(sc.camera.global_position + to.normalized() * 1000.0)
		sc.beacon.position = sp + Vector2(12, -12)
		sc.beacon.text = "◆ %s  %.1f km" % [String(sc.job.destination), rng / 1000.0]
	else:
		sc.beacon.visible = false
	var hint := ""
	if not sc.model.has_fuel() and not sc.xfer.arrived(sc.model):
		hint = "OUT OF FUEL. Press Esc to call a tug."
	elif sc.model.overheated:
		hint = "ENGINES OVERHEATED. Wait for them to cool."
	elif sc.model.braking:
		hint = "Braking. It stops the ship where it is: start it at the BRAKE NOW cue to stop at the target."
	elif sc.xfer.brake_now(sc.model):
		hint = "BRAKE NOW: press X to flip and stop."
	elif sc.xfer.closing(sc.model) < -1.0:
		hint = "You are moving away from the destination."
	elif sc.beacon != null and not sc.beacon.visible:
		hint = "The destination is behind you."
	elif sc.model.speed() < 5.0:
		hint = "Point at the diamond, open the throttle (W) and speed time up with period. Esc turns back."
	sc.prompt.text = hint


func _update_hud() -> void:
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
		"HEAT  %d%%    HULL  %d%%" % [roundi(sc.model.heat_fraction() * 100.0), roundi((1.0 - sc.model.damage) * 100.0)],
		"ASSIST %s   %s" % ["ON" if sc.model.assist else "OFF", "AUTOPILOT BRAKING" if sc.model.braking else ""]])
	if sc.phase == "approach":
		lines.insert(0, "APPROACH  %s    Esc: autopilot dock" % String(sc.job.destination).to_upper())
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
		sc.prompt.text = "ENGINES OVERHEATED. Wait for them to cool."
	elif sc.model.last_impact > float(sc.model.tune.get("soft_impact_m_s", 1.5)) and sc.model.elapsed_s - sc._impact_shown < 3.0:
		sc.prompt.text = "HULL IMPACT"
	if not sc.model.has_fuel() and sc.model.speed() > 1.0:
		sc.prompt.text = "OUT OF FUEL. You are drifting."
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
			hint = "E: step outside onto the surface" if sc.model.landed else "The outer hatch stays shut until the ship is down"
		else:
			hint = "E: leave the ship" if sc._berthed() else "The outer hatch stays shut away from a berth"
	var warn := ""
	if sc.model.overheated:
		warn = "ENGINES OVERHEATED"
	elif not sc.model.has_fuel() and sc.model.speed() > 1.0:
		warn = "OUT OF FUEL"
	elif sc.model.last_impact > float(sc.model.tune.get("soft_impact_m_s", 1.5)) and sc.model.elapsed_s - sc._impact_shown < 3.0:
		warn = "HULL IMPACT"
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
		head = "LIFT-OFF  %s    %s" % [String(body.get("name", "Moon")).to_upper(), "AUTO LIFT ON (Esc)" if sc.auto_ascent else "Esc: lift off on auto"]
	elif sc.job.is_empty():
		head = "%s  %s    %s" % [String(body.get("name", "Moon")).to_upper(), target, "HOVER HOLD (H)" if sc.hover_hold else "F on the pad: shut down"]
	else:
		head = "DESCENT  %s  %s    %s" % [String(sc.job.get("destination", "")).to_upper(), String(body.get("name", "")).to_upper(),
				"AUTOLAND ON (Esc)" if sc.model.autoland else ("no beacon: land by hand" if not sc._beacon else ("HOVER HOLD (H)" if sc.hover_hold else "Esc: autoland"))]
	var lines := PackedStringArray([head,
		"ALTITUDE  %.0f m    V/S  %+.1f m/s    DRIFT  %.1f m/s" % [alt, sc.model.vel.y, Vector2(sc.model.vel.x, sc.model.vel.z).length()],
		("CLIMB TO  %.0f m" % float(sc.model.land_cfg.get("ascent_clear_m", 1500.0))) if sc.phase == "ascent" else "%s  %.0f m    TILT  %.0f°" % [target, to_pad, sc.model.tilt_deg()],
		"LIFT  %d%%    %.2f m/s² available, gravity %.2f" % [roundi(sc.model.lift * 100.0), sc.model.lift_accel(), sc.model.gravity],
		"THROTTLE  %d%%    FUEL  %.2f t" % [roundi(sc.model.throttle * 100.0), sc.model.fuel_t],
		"HEAT  %d%%    HULL  %d%%" % [roundi(sc.model.heat_fraction() * 100.0), roundi((1.0 - sc.model.damage) * 100.0)]])
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
			hint = "Space: lift off (or Esc for auto).  F: stay and shut down.  G: get up and walk outside."
		elif not sc.model.has_fuel():
			hint = "OUT OF FUEL"
		else:
			hint = "Climb clear of the moon. W/S still runs the main engine."
	elif sc.model.landed and sc.model.on_pad():
		hint = ("Landed. F: shut down and unload.   G: get up and walk outside.") if not sc.job.is_empty() else "On the pad. F: shut down.   G: get up and walk outside."
	elif sc.model.landed:
		hint = "Down %.0f m from the %s. Lift off (Space) and set down within %d m%s." % [to_pad, "camp's pad" if sc._target_kind == "camp" else "pad",
				int(sc.model.zone_m if sc.model.zone_m > 0.0 else float(sc.model.land_cfg.get("landing_zone_m", 120.0))),
				"" if sc.model.has_fuel() else ". Out of fuel: F calls a crawler to tow you in"]
	elif not sc.model.has_fuel():
		hint = "OUT OF FUEL"
	elif sc.model.last_impact > float(sc.model.tune.get("soft_impact_m_s", 1.5)) and sc.model.elapsed_s - sc._impact_shown < 3.0:
		hint = "HARD LANDING"
	elif alt < 60.0 and sc.model.vel.y < -float(sc.model.land_cfg.get("touchdown_speed_m_s", 3.0)) * 1.5:
		hint = "SINKING FAST: hold Space"
	elif not sc.model.autoland:
		hint = "Space: lift jets.  H: hover.  Tilt to drift toward the pad.%s" % ("  Esc: let the autopilot land." if sc._beacon else "")
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
