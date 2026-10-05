class_name JumpSequence
extends RefCounted
## A flown star jump: setting it up at the origin, what still blocks the drive, the spool, streak,
## flash and slowdown driven frame by frame, and arriving in the destination system. The jump's state
## (jump_t, the peaks tests read) stays on the scene.

var sc: FlightScene   ## the scene this works on


func _init(scene: FlightScene) -> void:
	sc = scene


## A flown jump: undock, fly clear of the station, then engage the FTL drive (J).
func _setup_jump() -> void:
	sc.phase = "depart"
	sc.model.station_solid = true
	sc.model.place_at_dock(Vector3(0.35, 0.15, 1.0))
	sc.fx = JumpFx.new()
	sc.fx.visible = false
	sc.add_child(sc.fx)
	sc.audio = JumpAudio.new()
	sc.add_child(sc.audio)
	sc.flash_rect = ColorRect.new()
	sc.flash_rect.color = Color(0.9, 0.95, 1.0, 0.0)
	sc.flash_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sc.hud.get_parent().add_child(sc.flash_rect)
	sc.flash_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _jumping() -> bool:
	return sc.phase == "spool" or sc.phase == "warp" or sc.phase == "decel"


func _tune(key: String, fallback: float) -> float:
	return float(sc.model.tune.get(key, fallback))


## Why the drive cannot be engaged right now, or "" when it can.
func _jump_blocker() -> String:
	if sc.phase != "depart" or String(sc.job.get("kind", "")) != "jump":
		return "no jump planned"
	var clear := sc._tune("jump_clear_m", 3000.0)
	if sc.model.pos.length() < clear:
		return "fly clear of the station: %.0f of %.0f m" % [sc.model.pos.length(), clear]
	if sc.model.overheated or sc.model.heat_fraction() > sc._tune("jump_max_heat_fraction", 0.9):
		return "let the ship cool before engaging the drive"
	if sc.model.speed() > sc._tune("jump_max_speed_m_s", 60.0):
		return "slow below %.0f m/s to engage (X brakes)" % sc._tune("jump_max_speed_m_s", 60.0)
	return ""


func _start_jump() -> void:
	sc.phase = "spool"
	sc.jump_t = 0.0
	sc._jump_committed = false
	sc._settle_played = false
	sc.model.braking = false
	sc.model.throttle = 0.0
	sc.fx.visible = true
	sc.fx.streak = 0.0
	sc.prompt.text = "FTL DRIVE SPOOLING"
	sc.audio.begin()
	sc.audio.cue("engage")


## The jump timeline: spool, accelerate into streaks, flash (the trip happens), decelerate out.
func _jump_step(delta: float) -> void:
	sc.jump_t += delta
	var spool := sc._tune("jump_spool_s", 5.0)
	var accel := sc._tune("jump_accel_s", 3.5)
	var flash := sc._tune("jump_flash_s", 0.5)
	var decel := sc._tune("jump_decel_s", 4.5)
	var t_flash := spool + accel
	var t_commit := t_flash + flash
	var t_end := t_commit + decel
	var streak := 0.0
	var speed := 0.0
	var fov := 70.0
	var white := 0.0
	var level := 0.0
	var duck := 1.0
	if sc.jump_t < spool:
		var u := sc.jump_t / spool
		streak = 0.12 * u
		speed = 30.0 + 250.0 * u
		fov = 70.0 + 4.0 * u
		level = 0.55 * u
		sc.prompt.text = "FTL DRIVE SPOOLING"
	elif sc.jump_t < t_flash:
		sc.phase = "warp"
		var u := (sc.jump_t - spool) / accel
		streak = 0.12 + 0.88 * u * u
		speed = 280.0 + 30000.0 * u * u
		fov = 74.0 + 44.0 * u * u
		level = 0.55 + 0.45 * u
		sc.prompt.text = ""
	elif sc.jump_t < t_commit:
		var u := (sc.jump_t - t_flash) / flash
		streak = 1.0
		speed = 30280.0
		fov = 118.0
		white = u
		level = 1.0
		if white >= 0.98 and not sc._jump_committed:
			sc._jump_committed = true
			sc._arrive_in_system()
			sc.audio.cue("boom")
	elif sc.jump_t < t_end:
		sc.phase = "decel"
		var u := (sc.jump_t - t_commit) / decel
		var inv := 1.0 - u
		streak = inv * inv
		speed = 30280.0 * inv * inv * inv + 20.0
		fov = 70.0 + 48.0 * inv * inv
		white = maxf(0.0, 1.0 - u * 4.0)
		level = inv
		duck = clampf((sc.jump_t - t_commit) / 1.2, 0.0, 1.0)   # silence under the boom, then everything comes back
		if not sc._settle_played and u > 0.8:
			sc._settle_played = true
			sc.audio.cue("settle")
		sc.prompt.text = ""
	else:
		sc.audio.end()
		sc.fx.visible = false
		sc.fx.streak = 0.0
		sc.camera.fov = 70.0
		sc.flash_rect.color = Color(0.9, 0.95, 1.0, 0.0)
		sc._begin_approach(3000.0)
		return
	sc.audio.mix(level, streak, duck)
	sc.fx.streak = streak
	sc.fx.advance(delta, speed)
	sc.camera.fov = fov
	sc.flash_rect.color = Color(0.9, 0.95, 1.0, white)
	sc.jump_peak_flash = maxf(sc.jump_peak_flash, white)
	sc.jump_peak_streak = maxf(sc.jump_peak_streak, streak)
	sc.jump_peak_fov = maxf(sc.jump_peak_fov, fov)


## At the height of the flash the sim runs the trip and the world changes: the destination's station is
## named, and the sun sits somewhere else.
func _arrive_in_system() -> void:
	sc._jump_result = Session.commit_jump()
	sc.station.visible = false
	sc.station_label.text = String(sc.job.destination).to_upper()
	var h := hash(String(sc.job.get("dest_system", "")))
	sc.sun.rotation_degrees = Vector3(-15.0 - float(h % 50), float((h / 50) % 360), 0.0)
	var warmth := float((h / 7) % 100) / 100.0
	sc.sun.light_color = Color(1.0, 0.82 + 0.16 * (1.0 - warmth), 0.65 + 0.3 * (1.0 - warmth))
	sc.model.vel = Vector3.ZERO
