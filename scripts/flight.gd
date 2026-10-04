extends Node3D
## Flying the ship. Leaves the dock, burns, turns, brakes and comes back in. Free flight for now:
## no sim time passes and jumps between stars are not here yet (see docs/runtime/economy-sim.md).
##
## Costs: fuel burned and hull repairs are charged and the clock advances when the flight ends.
## Controls: W/S throttle up/down, Z cut throttle, arrow keys pitch and yaw, Q/E roll, X braking
## autopilot, R toggle rotation assist, C camera, F dock when close and slow, Esc back to the dock.
## G gets up from the helm to walk the ship (see ShipWalk): WASD walk, mouse or arrows look, Shift run,
## E uses the helm, a ladder or the airlock. The ship carries on as it was while nobody is at the helm.

const STATION_RADIUS := 26.0

var model: FlightModel
var stats: Dictionary
var ship_root: Node3D
var camera: Camera3D
var station: Node3D
var hud: Label
var prompt: Label
var bar: ProgressBar
var chase := true
var cockpit_pos := Vector3.ZERO
var com := Vector3.ZERO
var view: ShipView
var leaving := false
var sparks: Array[MeshInstance3D] = []
var xfer: TransferFlight = null   ## set when a local run is being flown; null for free flight at the dock
var job: Dictionary = {}
var warp_index := 0
var beacon: Label
var _arrived := false
var phase := "free"   ## free flight, or for a flown run: depart (leaving the origin site), cruise, approach (docking at the destination)
var station_label: Label3D
var sun: DirectionalLight3D
var fx: JumpFx
var audio: JumpAudio
var flash_rect: ColorRect
var jump_t := 0.0
var _jump_committed := false
var _settle_played := false
var _jump_result := {}
var jump_peak_flash := 0.0   # for tests: the brightest the flash got
var jump_peak_streak := 0.0
var jump_peak_fov := 0.0
const CLEAR_M := 3000.0
const WARPS := [1, 2, 5, 10, 25, 60]
var _impact_shown := -10.0
var _impacts_seen := 0
var walk: ShipWalk
var walking := false
var help: Label
var crosshair: Label
const MOUSE_TURN := 0.0025     ## radians per pixel of mouse movement, times the mouse sensitivity setting
const KEY_TURN := 1.8          ## radians per second with the arrow keys
const FLY_HELP := "W/S throttle   Z cut   arrows pitch+yaw   Q/E roll   X brake autopilot   R assist   C camera   F dock   J jump (when clear)   , . time   G get up   Esc back to the dock"
const WALK_HELP := "WASD walk   mouse or arrows look   Shift run   E use (helm, ladder, airlock)   , . time   Esc frees the mouse, click to look again"
const LAND_HELP := "Space lift jets   H hover hold   W/S main engine   arrows pitch+yaw   Q/E roll   Esc autoland   F unload (landed on the pad)   G get up   C camera"
const SUIT_HELP := "WASD walk   Shift run   Space jump (hold for suit jets)   mouse or arrows look   E use   Q back aboard (at the hatch)   Esc frees the mouse"
var ship_data: ShipData
var moon: Node3D
var hover_hold := false
var _surface := false          ## landed on the destination's pad: the run earns the surface bonus
var outside := false           ## on foot on the moon, in a suit
var suit: SurfaceWalker
var suit_hatch := Vector3.ZERO
var pad_label: Label3D
var reticle: FlightReticle
var world_env: Environment
var auto_ascent := false       ## Esc while lifting off: full lift until clear of the surface
var _beacon := true            ## the target pad has a landing beacon (the base does, the mining camp does not)
var _target_kind := "pad"      ## which surface site the descent is for
var _dv_space := 0.0           ## the part of a run's delta-v spent in space (the rest is landing or lifting off)
var _ground_task := -1         ## the moon's ground mesh, built on a worker thread during the cruise
var _ground_mesh: MeshInstance3D
var _ground_terrain: SurfaceTerrain
var ops: SurfaceOps            ## the suit's air, jets and scanner, mission points and crates (on the moon)


func _ready() -> void:
	_build_world()
	_build_ship()
	_build_hud()
	GameSettings.apply_scene(self, 150.0)
	if not Session.flight_job.is_empty():
		job = Session.flight_job
		if String(job.get("kind", "run")) == "jump":
			_setup_jump()
		else:
			_setup_transfer()
	elif LocalSpace.is_surface(String(Session.profile.get("port_id", ""))):
		_begin_surface_free()   # the helm taken on the moon: sitting on the pad
	if Session.walk_aboard:
		Session.walk_aboard = false
		get_up.call_deferred()
		walk_from_airlock.call_deferred()
	if Session.suit_up:
		Session.suit_up = false
		_suit_up.call_deferred()


func _build_world() -> void:
	var env := Environment.new()
	world_env = env
	env.background_mode = Environment.BG_SKY
	env.sky = SpaceSky.make()
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.glow_intensity = 0.8
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.4, 0.45, 0.58)
	env.ambient_light_energy = 0.55
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-30, 40, 0)
	sun.light_color = Color(1.0, 0.94, 0.85)
	sun.light_energy = 1.4
	add_child(sun)
	station = _make_station()
	add_child(station)
	# Drifting markers give the eye something to measure speed against.
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.7, 0.8, 1.0)
	for i in 160:
		var m := MeshInstance3D.new()
		var s := SphereMesh.new()
		s.radius = 0.35
		s.height = 0.7
		s.radial_segments = 6
		s.rings = 3
		s.material = mat
		m.mesh = s
		m.position = Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)).normalized() * rng.randf_range(60.0, 700.0)
		add_child(m)
		sparks.append(m)


## A blocky orbital dock at the origin: a spine, a spinning ring and a lit docking collar.
func _make_station() -> Node3D:
	var root := Node3D.new()
	var steel := Interiors.flat(Color(0.42, 0.46, 0.52), 0.7, 0.3)
	var dark := Interiors.flat(Color(0.34, 0.38, 0.44), 0.7, 0.3)
	var spine := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 5.0
	cyl.bottom_radius = 5.0
	cyl.height = 60.0
	cyl.material = steel
	spine.mesh = cyl
	spine.rotation_degrees.x = 90.0
	root.add_child(spine)
	var ring := Node3D.new()                       # spins about the spine (Z); everything on it is in the XY plane
	root.add_child(ring)
	var band := MeshInstance3D.new()
	var tor := TorusMesh.new()                     # a torus lies flat by default: stand it up to face along Z
	tor.inner_radius = STATION_RADIUS - 3.0
	tor.outer_radius = STATION_RADIUS
	tor.material = dark
	band.mesh = tor
	band.rotation_degrees.x = 90.0
	ring.add_child(band)
	ring.set_meta("spin", true)
	for k in 4:
		var spoke := MeshInstance3D.new()
		var b := BoxMesh.new()
		b.size = Vector3(1.4, STATION_RADIUS, 1.4)
		b.material = steel
		spoke.mesh = b
		spoke.rotation.z = k * PI / 2.0
		spoke.position = Vector3(sin(k * PI / 2.0), -cos(k * PI / 2.0), 0) * STATION_RADIUS * 0.5
		ring.add_child(spoke)
	for k in 16:      # lit windows around the ring
		var win := MeshInstance3D.new()
		var wb := BoxMesh.new()
		wb.size = Vector3(2.4, 1.2, 3.2)
		wb.material = Interiors.glow(Color(1.0, 0.85, 0.5), 1.4)
		win.mesh = wb
		var a := k * TAU / 16.0
		win.position = Vector3(cos(a), sin(a), 0) * (STATION_RADIUS - 1.5)
		win.rotation.z = a
		ring.add_child(win)
	var collar := MeshInstance3D.new()
	var ct := TorusMesh.new()
	ct.inner_radius = 6.2
	ct.outer_radius = 7.2
	ct.material = Interiors.glow(Color(0.35, 0.85, 1.0), 1.6)
	collar.mesh = ct
	collar.rotation_degrees.x = 90.0
	collar.position = Vector3(0, 0, 32)
	root.add_child(collar)
	var label := Label3D.new()
	label.text = String(Session.port().get("name", "DOCK")).to_upper()
	label.font_size = 96
	label.pixel_size = 0.05
	label.position = Vector3(0, STATION_RADIUS + 10.0, 0)
	label.modulate = Color(1.0, 0.8, 0.4)
	root.add_child(label)
	station_label = label
	return root


## A flown local run: undock from the origin site, fly clear, cruise to the destination (the clock can be
## sped up), then dock there.
func _setup_transfer() -> void:
	var o_s := String(job.get("origin_kind", "")) in LocalSpace.SURFACE
	var d_s := String(job.get("dest_kind", "")) in LocalSpace.SURFACE
	var sdv := float(LocalSpace.config().get("surface_dv_kms", 1.8))
	_dv_space = float(job.dv_kms) - (sdv if o_s else 0.0) - (sdv if d_s else 0.0)
	xfer = TransferFlight.plan(stats, maxf(_dv_space, 0.3), String(job.key))
	if (String(job.get("dest_kind", "")) == "moon" or d_s) and model.lift_kn > 0.0 and not o_s:
		_ground_task = WorkerThreadPool.add_task(_prebuild_ground, false, "moon ground")
	phase = "depart"
	var dock_dir := Vector3(0.35, 0.15, 1.0).normalized()
	# The destination lies about 35 degrees off the way the ship leaves the dock.
	xfer.aim(Basis(Vector3.UP, deg_to_rad(35.0)) * dock_dir)
	model.station_solid = true
	model.place_at_dock(Vector3(0.35, 0.15, 1.0))
	beacon = Label.new()
	beacon.add_theme_font_size_override("font_size", 18)
	beacon.add_theme_color_override("font_color", Brand.AMBER)
	hud.get_parent().add_child(beacon)
	if o_s:
		# Starting on the moon: sitting on the origin pad, lift off first.
		_begin_surface(String(job.get("origin_kind", "pad")))
		if d_s:
			_aim_descent_at(String(job.get("dest_kind", "pad")))   # a hop across the surface
			phase = "descent"
		else:
			phase = "ascent"
		help.text = LAND_HELP


## A flown jump: undock, fly clear of the station, then engage the FTL drive (J).
func _setup_jump() -> void:
	phase = "depart"
	model.station_solid = true
	model.place_at_dock(Vector3(0.35, 0.15, 1.0))
	fx = JumpFx.new()
	fx.visible = false
	add_child(fx)
	audio = JumpAudio.new()
	add_child(audio)
	flash_rect = ColorRect.new()
	flash_rect.color = Color(0.9, 0.95, 1.0, 0.0)
	flash_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.get_parent().add_child(flash_rect)
	flash_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _jumping() -> bool:
	return phase == "spool" or phase == "warp" or phase == "decel"


func _tune(key: String, fallback: float) -> float:
	return float(model.tune.get(key, fallback))


## Why the drive cannot be engaged right now, or "" when it can.
func _jump_blocker() -> String:
	if phase != "depart" or String(job.get("kind", "")) != "jump":
		return "no jump planned"
	var clear := _tune("jump_clear_m", 3000.0)
	if model.pos.length() < clear:
		return "fly clear of the station: %.0f of %.0f m" % [model.pos.length(), clear]
	if model.overheated or model.heat_fraction() > _tune("jump_max_heat_fraction", 0.9):
		return "let the ship cool before engaging the drive"
	if model.speed() > _tune("jump_max_speed_m_s", 60.0):
		return "slow below %.0f m/s to engage (X brakes)" % _tune("jump_max_speed_m_s", 60.0)
	return ""


func _start_jump() -> void:
	phase = "spool"
	jump_t = 0.0
	_jump_committed = false
	_settle_played = false
	model.braking = false
	model.throttle = 0.0
	fx.visible = true
	fx.streak = 0.0
	prompt.text = "FTL DRIVE SPOOLING"
	audio.begin()
	audio.cue("engage")


## The jump timeline: spool, accelerate into streaks, flash (the trip happens), decelerate out.
func _jump_step(delta: float) -> void:
	jump_t += delta
	var spool := _tune("jump_spool_s", 5.0)
	var accel := _tune("jump_accel_s", 3.5)
	var flash := _tune("jump_flash_s", 0.5)
	var decel := _tune("jump_decel_s", 4.5)
	var t_flash := spool + accel
	var t_commit := t_flash + flash
	var t_end := t_commit + decel
	var streak := 0.0
	var speed := 0.0
	var fov := 70.0
	var white := 0.0
	var level := 0.0
	var duck := 1.0
	if jump_t < spool:
		var u := jump_t / spool
		streak = 0.12 * u
		speed = 30.0 + 250.0 * u
		fov = 70.0 + 4.0 * u
		level = 0.55 * u
		prompt.text = "FTL DRIVE SPOOLING"
	elif jump_t < t_flash:
		phase = "warp"
		var u := (jump_t - spool) / accel
		streak = 0.12 + 0.88 * u * u
		speed = 280.0 + 30000.0 * u * u
		fov = 74.0 + 44.0 * u * u
		level = 0.55 + 0.45 * u
		prompt.text = ""
	elif jump_t < t_commit:
		var u := (jump_t - t_flash) / flash
		streak = 1.0
		speed = 30280.0
		fov = 118.0
		white = u
		level = 1.0
		if white >= 0.98 and not _jump_committed:
			_jump_committed = true
			_arrive_in_system()
			audio.cue("boom")
	elif jump_t < t_end:
		phase = "decel"
		var u := (jump_t - t_commit) / decel
		var inv := 1.0 - u
		streak = inv * inv
		speed = 30280.0 * inv * inv * inv + 20.0
		fov = 70.0 + 48.0 * inv * inv
		white = maxf(0.0, 1.0 - u * 4.0)
		level = inv
		duck = clampf((jump_t - t_commit) / 1.2, 0.0, 1.0)   # silence under the boom, then everything comes back
		if not _settle_played and u > 0.8:
			_settle_played = true
			audio.cue("settle")
		prompt.text = ""
	else:
		audio.end()
		fx.visible = false
		fx.streak = 0.0
		camera.fov = 70.0
		flash_rect.color = Color(0.9, 0.95, 1.0, 0.0)
		_begin_approach(3000.0)
		return
	audio.mix(level, streak, duck)
	fx.streak = streak
	fx.advance(delta, speed)
	camera.fov = fov
	flash_rect.color = Color(0.9, 0.95, 1.0, white)
	jump_peak_flash = maxf(jump_peak_flash, white)
	jump_peak_streak = maxf(jump_peak_streak, streak)
	jump_peak_fov = maxf(jump_peak_fov, fov)


## At the height of the flash the sim runs the trip and the world changes: the destination's station is
## named, and the sun sits somewhere else.
func _arrive_in_system() -> void:
	_jump_result = Session.commit_jump()
	station.visible = false
	station_label.text = String(job.destination).to_upper()
	var h := hash(String(job.get("dest_system", "")))
	sun.rotation_degrees = Vector3(-15.0 - float(h % 50), float((h / 50) % 360), 0.0)
	var warmth := float((h / 7) % 100) / 100.0
	sun.light_color = Color(1.0, 0.82 + 0.16 * (1.0 - warmth), 0.65 + 0.3 * (1.0 - warmth))
	model.vel = Vector3.ZERO


## Arrived at the marker: the destination's station comes up and the ship is brought to rest 1.5 km
## off its docking collar.
func _begin_approach(distance_m: float = 1500.0) -> void:
	phase = "approach"
	station.visible = true
	station_label.text = String(job.destination).to_upper()
	model.station_solid = true
	model.pos = Vector3(0.35, 0.15, 1.0).normalized() * distance_m
	model.vel = Vector3.ZERO
	model.braking = false
	model.throttle = 0.0
	if beacon != null:
		beacon.visible = false
	warp_index = 0


func _build_ship() -> void:
	var ship := ShipData.new(ModuleLibrary.new())
	var manifest: CargoManifest = null
	if Session.slot >= 0 and SaveSlots.exists(Session.slot):
		var loaded := Session._load_ship(SaveSlots.read(Session.slot))
		if not loaded.is_empty():
			ship = loaded.ship
			manifest = loaded.manifest
	if ship.modules.is_empty():
		ShipPresets.build(ship)
	stats = ShipStats.compute(ship, 0.0, manifest)
	ship_data = ship
	model = FlightModel.from_stats(stats)
	model.land_cfg = SurfaceTerrain.config()
	if Session.slot >= 0:
		model.damage = clampf(float(Session.profile.get("hull_damage", 0.0)), 0.0, 1.0)   # dents stay until repaired
	model.place_at_dock(Vector3(0.35, 0.15, 1.0))
	com = stats.com
	ship_root = Node3D.new()
	add_child(ship_root)
	view = ShipView.new()
	ship_root.add_child(view)
	view.position = -com                       # turn about the centre of mass
	view.rebuild(ship, manifest)
	walk = ShipWalk.build(ship, view)
	for m in ship.modules:
		if ship.library.get_def(m.id).helm:
			cockpit_pos = ShipGrid.cell_to_world(m.cell) - com + Vector3(0, 0.5, 0)
	camera = Camera3D.new()
	camera.fov = 70.0
	camera.far = 4000.0
	add_child(camera)
	camera.current = true
	_apply_pose()


func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	hud = Label.new()
	hud.position = Vector2(28, 24)
	hud.add_theme_font_size_override("font_size", 18)
	hud.add_theme_color_override("font_color", Brand.OFFWHITE)
	layer.add_child(hud)
	prompt = Label.new()
	prompt.add_theme_font_size_override("font_size", 22)
	prompt.add_theme_color_override("font_color", Brand.AMBER)
	prompt.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM, Control.PRESET_MODE_MINSIZE, 60)
	prompt.grow_horizontal = Control.GROW_DIRECTION_BOTH
	layer.add_child(prompt)
	bar = ProgressBar.new()
	bar.custom_minimum_size = Vector2(26, 160)
	bar.fill_mode = ProgressBar.FILL_BOTTOM_TO_TOP
	bar.max_value = 1.0
	bar.show_percentage = false
	bar.position = Vector2(28, 230)
	layer.add_child(bar)
	help = Brand.note(FLY_HELP, 13)
	help.autowrap_mode = TextServer.AUTOWRAP_OFF
	help.custom_minimum_size = Vector2(1000, 0)
	help.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT, Control.PRESET_MODE_MINSIZE, 20)
	layer.add_child(help)
	crosshair = Label.new()
	crosshair.text = "+"
	crosshair.add_theme_font_size_override("font_size", 22)
	crosshair.add_theme_color_override("font_color", Color(Brand.OFFWHITE, 0.7))
	crosshair.set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_MINSIZE)
	crosshair.grow_horizontal = Control.GROW_DIRECTION_BOTH
	crosshair.grow_vertical = Control.GROW_DIRECTION_BOTH
	crosshair.visible = false
	layer.add_child(crosshair)
	reticle = FlightReticle.new()
	layer.add_child(reticle)
	layer.move_child(reticle, 0)


func _process(delta: float) -> void:
	if leaving or model == null:
		return
	if fx != null:
		fx.global_position = model.pos
		fx.global_basis = model.basis
	if _jumping():
		_jump_step(delta)
		_apply_pose()
		_update_hud()
		return
	var turn := Vector3.ZERO
	var thr := 0.0
	var lift_cmd := _lift_command()
	if outside:
		_suit_step(delta)
	elif walking:
		_walk_step(delta)    # nobody at the helm: the ship carries on as it was
	else:
		if Input.is_key_pressed(KEY_UP): turn.x += 1.0
		if Input.is_key_pressed(KEY_DOWN): turn.x -= 1.0
		if Input.is_key_pressed(KEY_LEFT): turn.y += 1.0
		if Input.is_key_pressed(KEY_RIGHT): turn.y -= 1.0
		if Input.is_key_pressed(KEY_Q): turn.z += 1.0
		if Input.is_key_pressed(KEY_E): turn.z -= 1.0
		if Input.is_key_pressed(KEY_W): thr += 1.0
		if Input.is_key_pressed(KEY_S): thr -= 1.0
		if Input.is_key_pressed(KEY_Z):
			model.throttle = 0.0
	if turn != Vector3.ZERO or thr != 0.0:
		model.braking = false          # any pilot input takes the controls back
	if xfer == null:
		model.step(minf(delta, 0.05), turn, thr, lift_cmd)
	else:
		var total := minf(delta, 0.05) * float(_warp())
		var n := maxi(1, ceili(total / 0.05))
		for i in n:
			model.step(total / float(n), turn, thr, lift_cmd)
			if phase == "cruise" and xfer.arrived(model):
				if _can_land():
					_begin_descent()
				else:
					_begin_approach()
				break
		if phase == "depart" and xfer != null and model.pos.length() > CLEAR_M:
			if _dv_space <= 0.3 and String(job.get("dest_kind", "")) in LocalSpace.SURFACE:
				_begin_descent()   # from the base's station straight down to the surface
			else:
				phase = "cruise"
				station.visible = false
				model.station_solid = false
		if phase == "ascent" and model.altitude() > float(model.land_cfg.get("ascent_clear_m", 1500.0)):
			_reach_orbit()
		if phase == "cruise" or phase == "depart":
			_wrap_markers()
	if model.impacts != _impacts_seen:
		_impacts_seen = model.impacts
		_impact_shown = model.elapsed_s
	_apply_pose()
	_update_hud()
	view.set_flames(model.throttle > 0.02 and model.has_fuel())
	view.set_lift_flames(model.lift > 0.03 and model.has_fuel())
	for ring in station.get_children():
		if ring.has_meta("spin"):
			ring.rotate_z(delta * 0.05)


## Time compression, held to 1x when the target is close or the ship is closing fast on it.
func _warp() -> int:
	var w: int = WARPS[warp_index]
	if xfer == null or w == 1 or phase != "cruise":
		return 1
	var eta := xfer.eta_s(model)
	if xfer.range_to(model) < 25000.0 or (eta >= 0.0 and eta < 60.0) or xfer.brake_now(model) or model.braking:
		return 1
	return w


## Keep the speed markers around the ship however far it has come.
func _wrap_markers() -> void:
	for m in sparks:
		var rel := m.position - model.pos
		rel = Vector3(fposmod(rel.x + 700.0, 1400.0) - 700.0, fposmod(rel.y + 700.0, 1400.0) - 700.0, fposmod(rel.z + 700.0, 1400.0) - 700.0)
		m.position = model.pos + rel


func _apply_pose() -> void:
	ship_root.position = model.pos
	ship_root.basis = model.basis
	# Everything else is placed relative to the ship so the numbers stay small near the origin.
	if outside:
		camera.global_position = suit.eye()
		camera.global_basis = suit.look_basis()
	elif walking:
		camera.global_position = model.pos + model.basis * (view.position + walk.eye())
		camera.global_basis = model.basis * walk.look_basis()
	elif chase:
		var back := model.basis * Vector3(0, 6.0, 26.0)
		camera.global_position = model.pos + back
		camera.look_at(model.pos + model.basis * Vector3(0, 1.5, -10.0), model.basis.y)
	else:
		camera.global_position = model.pos + model.basis * cockpit_pos
		camera.global_basis = model.basis
	_update_reticle()


## Nose, prograde and retrograde markers, at the helm in either camera (not on foot or mid-jump).
func _update_reticle() -> void:
	if reticle == null:
		return
	reticle.nose = Vector2.INF
	reticle.prograde = Vector2.INF
	reticle.retrograde = Vector2.INF
	if walking or outside or _jumping():
		reticle.queue_redraw()
		return
	reticle.nose = _screen_dir(model.forward())
	var v := model.vel
	if model.landed or v.length() < 0.3:
		pass
	else:
		reticle.prograde = _screen_dir(v.normalized())
		reticle.retrograde = _screen_dir(-v.normalized())
	reticle.queue_redraw()


## Where a direction from the ship lands on screen, or INF if it is behind the camera.
func _screen_dir(dir: Vector3) -> Vector2:
	var far := model.pos + dir * 2000.0
	if camera.is_position_behind(far):
		return Vector2.INF
	var p := camera.unproject_position(far)
	var size := get_viewport().get_visible_rect().size
	if p.x < 0.0 or p.y < 0.0 or p.x > size.x or p.y > size.y:
		return Vector2.INF
	return p


func _update_transfer_hud() -> void:
	var rng := xfer.range_to(model)
	var eta := xfer.eta_s(model)
	var lines := PackedStringArray([
		"RUN TO  %s    HOP  %.1f km/s" % [String(job.destination).to_upper(), float(job.dv_kms)],
		"TARGET  %.1f km    CLOSING  %+.0f m/s    ETA  %s" % [rng / 1000.0, xfer.closing(model), "%d s" % roundi(eta) if eta >= 0.0 else "-"],
		"SPEED  %.0f m/s    STOPS IN  %.1f km" % [model.speed(), xfer.stopping_distance(model) / 1000.0],
		"THROTTLE  %d%%    THRUST  %d%%    TIME x%d" % [roundi(model.throttle * 100.0), roundi(model.thrust_scale() * 100.0), _warp()],
		"FUEL  %.2f t    ΔV %.0f m/s    PERFECT RUN %.2f t" % [model.fuel_t, model.delta_v(), xfer.ideal_burn_t],
		"MASS  %.1f t    ACCEL %.2f m/s²" % [model.mass_t(), model.accel() if model.throttle > 0.0 else model.max_accel()],
		"HEAT  %d%%    HULL  %d%%" % [roundi(model.heat_fraction() * 100.0), roundi((1.0 - model.damage) * 100.0)],
		"ASSIST %s   %s" % ["ON" if model.assist else "OFF", "AUTOPILOT BRAKING" if model.braking else ""]])
	hud.text = "\n".join(lines)
	bar.value = model.throttle
	var to := xfer.target - model.pos
	if not camera.is_position_behind(camera.global_position + to):
		beacon.visible = true
		var sp := camera.unproject_position(camera.global_position + to.normalized() * 1000.0)
		beacon.position = sp + Vector2(12, -12)
		beacon.text = "◆ %s  %.1f km" % [String(job.destination), rng / 1000.0]
	else:
		beacon.visible = false
	var hint := ""
	if not model.has_fuel() and not xfer.arrived(model):
		hint = "OUT OF FUEL. Press Esc to call a tug."
	elif model.overheated:
		hint = "ENGINES OVERHEATED. Wait for them to cool."
	elif model.braking:
		hint = "Braking. It stops the ship where it is: start it at the BRAKE NOW cue to stop at the target."
	elif xfer.brake_now(model):
		hint = "BRAKE NOW: press X to flip and stop."
	elif xfer.closing(model) < -1.0:
		hint = "You are moving away from the destination."
	elif beacon != null and not beacon.visible:
		hint = "The destination is behind you."
	elif model.speed() < 5.0:
		hint = "Point at the diamond, open the throttle (W) and speed time up with period. Esc turns back."
	prompt.text = hint


func _update_hud() -> void:
	if _on_surface():
		_update_descent_hud()
		if outside:
			_suit_prompt()
		elif walking:
			_walk_prompt()
		return
	if xfer != null and phase != "approach":
		_update_transfer_hud()
		if walking:
			_walk_prompt()
		return
	var dist := model.pos.length()
	var closing := -model.vel.dot(model.pos.normalized()) if dist > 0.01 else 0.0
	var al := model.dock_alignment()
	var lines := PackedStringArray([
		"SPEED  %.1f m/s    CLOSING  %+.1f m/s" % [model.speed(), closing],
		"STATION  %.0f m    PORT  %.0f m" % [dist, al.distance],
		"THROTTLE  %d%%    THRUST  %d%%" % [roundi(model.throttle * 100.0), roundi(model.thrust_scale() * 100.0)],
		"FUEL  %.2f t    ΔV %.0f m/s" % [model.fuel_t, model.delta_v()],
		"MASS  %.1f t    ACCEL %.2f m/s²" % [model.mass_t(), model.accel() if model.throttle > 0.0 else model.max_accel()],
		"HEAT  %d%%    HULL  %d%%" % [roundi(model.heat_fraction() * 100.0), roundi((1.0 - model.damage) * 100.0)],
		"ASSIST %s   %s" % ["ON" if model.assist else "OFF", "AUTOPILOT BRAKING" if model.braking else ""]])
	if phase == "approach":
		lines.insert(0, "APPROACH  %s    Esc: autopilot dock" % String(job.destination).to_upper())
	hud.text = "\n".join(lines)
	bar.value = model.throttle
	if model.can_dock():
		prompt.text = "Press F to dock"
	elif al.distance < 60.0:
		var hints := PackedStringArray()
		if al.nose_deg > float(model.tune.get("dock_nose_deg", 25.0)):
			hints.append("point the nose at the collar (%d° off)" % roundi(al.nose_deg))
		if al.lateral > float(model.tune.get("dock_lateral_m", 8.0)):
			hints.append("line up on the axis (%.0f m off)" % al.lateral)
		if model.speed() > float(model.tune.get("dock_speed_m_s", 3.0)):
			hints.append("slow below %.0f m/s" % float(model.tune.get("dock_speed_m_s", 3.0)))
		if al.distance > float(model.tune.get("dock_range_m", 18.0)):
			hints.append("close in")
		prompt.text = "To dock: " + ", ".join(hints)
	else:
		prompt.text = ""
	if model.overheated:
		prompt.text = "ENGINES OVERHEATED. Wait for them to cool."
	elif model.last_impact > float(model.tune.get("soft_impact_m_s", 1.5)) and model.elapsed_s - _impact_shown < 3.0:
		prompt.text = "HULL IMPACT"
	if not model.has_fuel() and model.speed() > 1.0:
		prompt.text = "OUT OF FUEL. You are drifting."
	if String(job.get("kind", "")) == "jump" and phase == "depart" and not model.overheated:
		var why := _jump_blocker()
		prompt.text = "J: engage the FTL drive for %s (%.1f ly)" % [String(job.destination), float(job.ly)] if why == "" else "Jump to %s: %s" % [String(job.destination), why]
	elif _jumping():
		prompt.text = "FTL DRIVE SPOOLING" if phase == "spool" else ""
	if walking:
		_walk_prompt()


func _unhandled_input(event: InputEvent) -> void:
	if _jumping():
		return
	if outside and not leaving:
		_suit_input(event)
		return
	if walking and not leaving:
		_walk_input(event)
		return
	if _on_surface() and not leaving and event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_ESCAPE:
				if phase == "ascent":
					auto_ascent = not auto_ascent and model.can_hover()
				else:
					model.autoland = not model.autoland and model.can_hover() and _beacon
				hover_hold = false
				return
			KEY_H:
				hover_hold = not hover_hold
				model.autoland = false
				auto_ascent = false
				return
			KEY_F:
				if not model.landed:
					return
				if job.is_empty() or phase == "ascent":
					if model.on_pad():
						_return_to_dock()   # shut down where the flight started
					return
				if model.on_pad() or not model.has_fuel():
					_arrived = true
					_surface = model.on_pad() and String(job.get("dest_kind", "")) == "moon"
					_return_to_dock()
				return
			KEY_X:
				return   # the braking autopilot is for space
	if leaving or not (event is InputEventKey) or not event.pressed or event.echo:
		return
	match event.keycode:
		KEY_G:
			get_up()
		KEY_X:
			model.braking = not model.braking
		KEY_R:
			model.assist = not model.assist
		KEY_C:
			chase = not chase
			_apply_pose()
		KEY_J:
			if String(job.get("kind", "")) == "jump" and phase == "depart" and _jump_blocker() == "":
				_start_jump()
		KEY_PERIOD:
			if xfer != null:
				warp_index = mini(warp_index + 1, WARPS.size() - 1)
		KEY_COMMA:
			warp_index = maxi(warp_index - 1, 0)
		KEY_F:
			if model.can_dock():
				if phase == "approach":
					_arrived = true   # docked at the destination
				_return_to_dock()
		KEY_ESCAPE:
			if phase == "approach":
				_arrived = true   # the station's traffic control brings the ship in
			_return_to_dock()


func _return_to_dock() -> void:
	if leaving:
		return
	leaving = true
	if String(job.get("kind", "")) == "jump":
		Session.finish_jump_flight(model.fuel_burned_t, model.elapsed_s, model.damage, not model.has_fuel() and (phase != "approach" or not model.can_dock()))
	elif xfer != null:
		Session.finish_local_flight(model.fuel_burned_t, model.elapsed_s, model.damage, _arrived, _stranded(), _surface)
	else:
		Session.finish_flight(model.fuel_burned_t, model.elapsed_s, model.damage)
	get_tree().change_scene_to_file(Session.PLACE_SCENE)


# --- Walking the ship -------------------------------------------------------------------------------

## Leave the pilot's seat. Whatever the ship was doing it keeps doing: throttle, braking autopilot, assist.
func get_up() -> bool:
	if walking or _jumping() or walk == null or not walk.stand_at_helm():
		return false
	walking = true
	view.set_interior(true)
	help.text = WALK_HELP
	crosshair.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_apply_pose()
	return true


## Back in the seat, at the controls as they were left.
func sit_down() -> void:
	if not walking:
		return
	walking = false
	view.set_interior(false)
	help.text = LAND_HELP if _on_surface() else FLY_HELP
	crosshair.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_apply_pose()


## Docked, or still at the berth the flight started from: the airlock lets you off.
func _berthed() -> bool:
	if _on_surface():
		return model.landed
	if model.can_dock():
		return true
	return phase != "approach" and phase != "cruise" and model.pos.length() < 400.0 and model.speed() < 1.0


func _walk_step(delta: float) -> void:
	var dir := Vector2.ZERO
	if Input.is_key_pressed(KEY_W): dir.y += 1.0
	if Input.is_key_pressed(KEY_S): dir.y -= 1.0
	if Input.is_key_pressed(KEY_D): dir.x += 1.0
	if Input.is_key_pressed(KEY_A): dir.x -= 1.0
	var yaw := 0.0
	var pitch := 0.0
	if Input.is_key_pressed(KEY_LEFT): yaw += 1.0
	if Input.is_key_pressed(KEY_RIGHT): yaw -= 1.0
	if Input.is_key_pressed(KEY_UP): pitch += 1.0
	if Input.is_key_pressed(KEY_DOWN): pitch -= 1.0
	walk.look(yaw * KEY_TURN * delta, pitch * KEY_TURN * delta)
	walk.step(minf(delta, 0.05), dir, Input.is_key_pressed(KEY_SHIFT))


func _walk_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		walk.look(-event.relative.x * MOUSE_TURN * GameSettings.mouse_sensitivity(), -event.relative.y * MOUSE_TURN * GameSettings.mouse_sensitivity())
		return
	if event is InputEventMouseButton and event.pressed:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		return
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	match event.keycode:
		KEY_E:
			use()
		KEY_ESCAPE:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		KEY_PERIOD:
			if xfer != null:
				warp_index = mini(warp_index + 1, WARPS.size() - 1)
		KEY_COMMA:
			warp_index = maxi(warp_index - 1, 0)


## E: sit at the helm, climb a ladder, or leave by the airlock when the ship is at a berth.
func use() -> String:
	if walk.near_helm():
		sit_down()
		return "helm"
	if walk.climb() != 0:
		return "ladder"
	if walk.near_airlock() and _on_surface() and model.landed:
		go_outside()
		return "outside"
	if walk.near_airlock() and _berthed():
		if phase == "approach":
			_arrived = true
		sit_down()
		_return_to_dock()
		return "airlock"
	return ""


func _walk_prompt() -> void:
	var where := walk.room()
	var hint := ""
	if walk.near_helm():
		hint = "E: take the helm"
	elif not walk.hatch_here().is_empty():
		var hx := walk.hatch_here()
		hint = "E: climb %s (look up or down)" % ("up or down" if bool(hx.up) and bool(hx.down) else ("up" if bool(hx.up) else "down"))
	elif walk.near_airlock():
		if _on_surface():
			hint = "E: step outside onto the surface" if model.landed else "The outer hatch stays shut until the ship is down"
		else:
			hint = "E: leave the ship" if _berthed() else "The outer hatch stays shut away from a berth"
	var warn := ""
	if model.overheated:
		warn = "ENGINES OVERHEATED"
	elif not model.has_fuel() and model.speed() > 1.0:
		warn = "OUT OF FUEL"
	elif model.last_impact > float(model.tune.get("soft_impact_m_s", 1.5)) and model.elapsed_s - _impact_shown < 3.0:
		warn = "HULL IMPACT"
	elif xfer != null and phase == "cruise" and xfer.brake_now(model):
		warn = "BRAKE NOW: get back to the helm"
	var parts := PackedStringArray()
	for t in [warn, where.to_upper() if where != "" else "", hint]:
		if t != "":
			parts.append(t)
	prompt.text = "   ".join(parts)


# --- Landing on a moon ------------------------------------------------------------------------------
# The moon of the run's system: its base pad at the origin of the ground frame and a mining camp some
# kilometres off (LocalSpace "pad" and "camp"). Descending, lifting off and hopping between them all
# happen over the same ground.

func _on_surface() -> bool:
	return phase == "descent" or phase == "ascent"


func _system_id() -> String:
	return String(job.get("system_id", Session.system_id()))


func _body() -> Dictionary:
	return LocalSpace.body(_system_id())


func _make_terrain() -> SurfaceTerrain:
	return SurfaceTerrain.make(_system_id() + LocalSpace.SEP + "moon", [SurfaceFinds.camp_xz()])


## Where a surface site's pad is on the ground (y is the ground there).
func _pad_pos(kind: String) -> Vector3:
	if kind == "camp":
		var c := SurfaceFinds.camp_xz()
		var t := model.terrain if model.terrain != null else _make_terrain()
		return Vector3(c.x, t.height(c.x, c.y), c.y)
	return Vector3.ZERO


## A run to a moon base lands on its pad when the ship has lander legs with enough lift for the load and
## fuel to come down on; otherwise it docks at the base's orbital station. Surface sites must be landed on.
func _can_land() -> bool:
	var dk := String(job.get("dest_kind", ""))
	if not (dk == "moon" or dk in LocalSpace.SURFACE) or model.lift_kn <= 0.0:
		return false
	if dk == "moon" and model.fuel_t < float(model.land_cfg.get("landing_reserve_t", 1.5)):
		return false   # not enough left in the tanks to come down on the jets: dock in orbit instead
	return model.lift_accel() >= float(_body().get("gravity_m_s2", 1.62)) * float(model.land_cfg.get("min_lift_margin", 1.15))


func _stranded() -> bool:
	if _on_surface():
		return not model.has_fuel() and not model.on_pad()
	return not model.has_fuel() and (phase != "approach" or not model.can_dock())


## Gravity, ground and the moon's scenery on; space markers and the station off.
func _ensure_moon() -> void:
	var body := _body()
	model.gravity = float(body.get("gravity_m_s2", 1.62))
	if _ground_task >= 0:
		WorkerThreadPool.wait_for_task_completion(_ground_task)
		_ground_task = -1
	if model.terrain == null:
		model.terrain = _ground_terrain if _ground_terrain != null else _make_terrain()
	model.station_solid = false
	station.visible = false
	for m in sparks:
		m.visible = false
	if beacon != null:
		beacon.visible = false
	warp_index = 0
	var sun_deg: Array = body.get("sky_sun_deg", [-28, 35])
	sun.rotation_degrees = Vector3(float(sun_deg[0]), float(sun_deg[1]), 0)
	sun.light_color = Color(1.0, 0.97, 0.92)
	sun.light_energy = 1.05             # bare rock in hard sunlight: keep it from burning out to white
	world_env.ambient_light_energy = 0.18
	help.text = LAND_HELP
	if moon == null:
		_build_moon(body)
		GameSettings.apply_scene(self, 400.0)
	moon.visible = true


## Standing on a surface site's pad, landed, level.
func _begin_surface(kind: String) -> void:
	_ensure_moon()
	var p := _pad_pos(kind)
	model.pos = p + Vector3(0, model.foot_m, 0)
	model.vel = Vector3.ZERO
	model.ang = Vector3.ZERO
	model.throttle = 0.0
	model.braking = false
	model.autoland = false
	model.basis = Basis.looking_at(Vector3(0, 0, -1), Vector3.UP)
	model.landed = true
	model.pad = p
	model.zone_m = float(model.land_cfg.get("camp_zone_m", 60.0)) if kind == "camp" else 0.0
	_target_kind = kind
	_apply_pose()


## Point the descent at a surface site: its pad becomes the target, and only the base has a beacon.
func _aim_descent_at(kind: String) -> void:
	_target_kind = kind
	model.pad = _pad_pos(kind)
	model.zone_m = float(model.land_cfg.get("camp_zone_m", 60.0)) if kind == "camp" else 0.0
	_beacon = kind != "camp"


## Arrived over the moon: high above the target pad, drifting toward it, level. Gravity on.
func _begin_descent() -> void:
	phase = "descent"
	var cfg := model.land_cfg
	_ensure_moon()
	var dk := String(job.get("dest_kind", "moon"))
	_aim_descent_at(dk if dk in LocalSpace.SURFACE else "pad")
	model.braking = false
	model.autoland = false
	model.throttle = 0.0
	model.ang = Vector3.ZERO
	model.landed = false
	var a := float(absi(hash(String(job.get("dest_id", "")))) % 360) * PI / 180.0
	var dir := Vector3(cos(a), 0, sin(a))
	model.pos = model.pad + dir * float(cfg.get("start_offset_m", 900.0)) + Vector3(0, float(cfg.get("start_altitude_m", 1200.0)), 0)
	model.vel = -dir * float(cfg.get("start_speed_m_s", 25.0))
	model.basis = Basis.looking_at(-dir, Vector3.UP)
	_apply_pose()


## Lifted clear of the moon: on to the base's station (a run to orbit) or out into space for the cruise.
func _reach_orbit() -> void:
	auto_ascent = false
	hover_hold = false
	model.terrain = null
	model.gravity = 0.0
	model.landed = false
	model.lift = 0.0
	if moon != null:
		moon.visible = false
	for m in sparks:
		m.visible = true
	sun.rotation_degrees = Vector3(-30, 40, 0)
	sun.light_color = Color(1.0, 0.94, 0.85)
	sun.light_energy = 1.4
	world_env.ambient_light_energy = 0.55
	help.text = FLY_HELP
	if String(job.get("dest_kind", "")) == "moon":
		station_label.text = String(job.get("destination", "")).to_upper()
		_begin_approach(3000.0)
		return
	phase = "cruise"
	var start := Vector3(0.35, 0.15, 1.0).normalized() * (CLEAR_M + 50.0)
	model.pos = start
	model.vel = Vector3.ZERO
	model.ang = Vector3.ZERO
	model.station_solid = false
	model.basis = Basis.looking_at((xfer.target - start).normalized(), Vector3.UP)
	_apply_pose()


## Free flight from a surface site (the helm taken at a pad or the camp): sitting on its pad.
func _begin_surface_free() -> void:
	var kind := String(LocalSpace.node(String(Session.profile.get("port_id", ""))).get("kind", "pad"))
	_begin_surface(kind)
	phase = "descent"
	_beacon = kind != "camp"


func _build_moon(body: Dictionary) -> void:
	moon = Node3D.new()
	add_child(moon)
	var ground := _ground_mesh if _ground_mesh != null else _ground_for(model.terrain)
	ground.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF   # receives shadows; casting onto itself only made acne
	moon.add_child(ground)
	_build_base_pad()
	_build_camp()
	_build_wreck()
	_build_finds()


func _build_base_pad() -> void:
	var pad_r := float(model.land_cfg.get("pad_radius_m", 25.0))
	var pad := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = pad_r
	disc.bottom_radius = pad_r + 1.0
	disc.height = 0.4
	disc.material = Interiors.flat(Color(0.33, 0.34, 0.36), 0.9)
	pad.mesh = disc
	pad.position = Vector3(0, 0.05, 0)
	moon.add_child(pad)
	var ring := MeshInstance3D.new()
	var tor := TorusMesh.new()
	tor.inner_radius = pad_r - 1.4
	tor.outer_radius = pad_r - 0.6
	tor.material = SurfaceTextures.hazard_material()
	ring.mesh = tor
	ring.position = Vector3(0, 0.26, 0)
	ring.scale = Vector3(1, 0.05, 1)
	moon.add_child(ring)
	for k in 12:   # edge lights, easy to find from above
		var lamp := MeshInstance3D.new()
		var b := BoxMesh.new()
		b.size = Vector3(0.6, 0.4, 0.6)
		b.material = Interiors.glow(Color(1.0, 0.75, 0.3) if k % 2 == 0 else Color(0.4, 0.9, 1.0), 2.0)
		lamp.mesh = b
		var ang := k * TAU / 12.0
		lamp.position = Vector3(cos(ang), 0, sin(ang)) * (pad_r + 1.5) + Vector3(0, 0.4, 0)
		moon.add_child(lamp)
	var sys_name := String(Worlds.system(_system_id()).get("name", _system_id().capitalize()))
	var label := Label3D.new()
	label.text = "%s MOON BASE  PAD 1" % sys_name.to_upper()
	label.font_size = 40
	label.fixed_size = true
	label.pixel_size = 0.0012
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.modulate = Color(1.0, 0.8, 0.4)
	label.position = Vector3(0, 14, 0)
	moon.add_child(label)
	pad_label = label
	# The base itself: a few domes and boxes off to the side of the pad.
	var hab := Interiors.flat(Color(0.78, 0.77, 0.72), 0.7)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(_system_id())
	for i in 6:
		var at := Vector3(rng.randf_range(45, 80), 0, rng.randf_range(-40, 40)).rotated(Vector3.UP, rng.randf() * TAU)
		var mi := MeshInstance3D.new()
		if i % 2 == 0:
			var dome := SphereMesh.new()
			dome.radius = rng.randf_range(5, 9)
			dome.height = dome.radius
			dome.is_hemisphere = true
			dome.material = hab
			mi.mesh = dome
		else:
			var box := BoxMesh.new()
			box.size = Vector3(rng.randf_range(6, 14), rng.randf_range(3, 6), rng.randf_range(6, 12))
			box.material = hab
			mi.mesh = box
			at.y = box.size.y * 0.5
		mi.position = at
		moon.add_child(mi)
		var light := MeshInstance3D.new()
		var lb := BoxMesh.new()
		lb.size = Vector3(1.2, 0.5, 0.2)
		lb.material = Interiors.glow(Color(1.0, 0.85, 0.5), 1.5)
		light.mesh = lb
		light.position = at + Vector3(0, 2.0, 0)
		moon.add_child(light)


## The mining camp: a rough pad marked with four flares, a drill rig, ore skips and a pressurised hut.
func _build_camp() -> void:
	var c := _pad_pos("camp")
	var root := Node3D.new()
	root.position = c
	moon.add_child(root)
	var rough := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = 16.0
	disc.bottom_radius = 17.0
	disc.height = 0.2
	disc.material = Interiors.flat(Color(0.3, 0.27, 0.22), 1.0)
	rough.mesh = disc
	root.add_child(rough)
	for k in 4:
		var flare := MeshInstance3D.new()
		var b := BoxMesh.new()
		b.size = Vector3(0.4, 0.8, 0.4)
		b.material = Interiors.glow(Color(1.0, 0.35, 0.2), 2.2)
		flare.mesh = b
		var ang := k * TAU / 4.0 + PI * 0.25
		flare.position = Vector3(cos(ang), 0, sin(ang)) * 17.5 + Vector3(0, 0.4, 0)
		root.add_child(flare)
	var steel := Interiors.flat(Color(0.5, 0.45, 0.32), 0.6, 0.3)
	var rig := MeshInstance3D.new()   # drill derrick
	var tower := BoxMesh.new()
	tower.size = Vector3(3, 18, 3)
	tower.material = steel
	rig.mesh = tower
	rig.position = Vector3(40, 9, 12)
	root.add_child(rig)
	var hut := MeshInstance3D.new()
	var hb := BoxMesh.new()
	hb.size = Vector3(10, 4, 6)
	hb.material = Interiors.flat(Color(0.7, 0.62, 0.42), 0.8)
	hut.mesh = hb
	hut.position = Vector3(-35, 2, -18)
	root.add_child(hut)
	for i in 5:   # ore skips
		var skip := MeshInstance3D.new()
		var sb := BoxMesh.new()
		sb.size = Vector3(3, 2, 5)
		sb.material = Interiors.flat(Color(0.45, 0.3, 0.2), 0.9)
		skip.mesh = sb
		skip.position = Vector3(30 + i * 4.0, 1, -25)
		root.add_child(skip)
	var label := Label3D.new()
	label.text = "MINING CAMP  (no beacon: land by hand)"
	label.font_size = 36
	label.fixed_size = true
	label.pixel_size = 0.0012
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.modulate = Color(1.0, 0.55, 0.35)
	label.position = Vector3(0, 12, 0)
	root.add_child(label)


## A lander that came down hard near the camp: a broken hull on its side and scattered parts.
func _build_wreck() -> void:
	var w := SurfaceFinds.wreck_xz()
	var root := Node3D.new()
	root.position = Vector3(w.x, model.terrain.height(w.x, w.y), w.y)
	moon.add_child(root)
	var hull := Interiors.flat(Color(0.35, 0.38, 0.42), 0.7, 0.4)
	var burnt := Interiors.flat(Color(0.12, 0.11, 0.1), 0.9)
	var body := MeshInstance3D.new()
	var bb := BoxMesh.new()
	bb.size = Vector3(6, 3, 9)
	bb.material = hull
	body.mesh = bb
	body.position = Vector3(0, 1.0, 0)
	body.rotation_degrees = Vector3(8, 25, 62)
	root.add_child(body)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(_system_id() + "wreck")
	for i in 9:
		var part := MeshInstance3D.new()
		var pb := BoxMesh.new()
		pb.size = Vector3(rng.randf_range(0.6, 2.4), rng.randf_range(0.3, 1.2), rng.randf_range(0.6, 3.0))
		pb.material = hull if i % 3 else burnt
		part.mesh = pb
		part.position = Vector3(rng.randf_range(-14, 14), 0.3, rng.randf_range(-14, 14))
		part.rotation_degrees = Vector3(rng.randf_range(-30, 30), rng.randf() * 360.0, rng.randf_range(-30, 30))
		root.add_child(part)
	var label := Label3D.new()
	label.text = "WRECK"
	label.font_size = 32
	label.fixed_size = true
	label.pixel_size = 0.0012
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.modulate = Color(0.85, 0.85, 0.9)
	label.position = Vector3(0, 7, 0)
	root.add_child(label)


var find_nodes := {}   ## find id -> its node on the ground


## Rock samples: glowing crystals with a small tag, skipped once taken.
func _build_finds() -> void:
	find_nodes.clear()
	for f in (Session.finds_here() if Session.slot >= 0 else SurfaceFinds.list(_system_id(), 0)):
		if String(f.kind) != "sample" or bool(f.get("taken", false)):
			continue
		var x := float(f.x)
		var z := float(f.z)
		var node := Node3D.new()
		node.position = Vector3(x, model.terrain.height(x, z), z)
		var crystal := MeshInstance3D.new()
		var prism := PrismMesh.new()
		prism.size = Vector3(0.5, 0.9, 0.5)
		prism.material = Interiors.glow(Color(0.35, 0.95, 0.85), 1.6)
		crystal.mesh = prism
		crystal.position = Vector3(0, 0.45, 0)
		node.add_child(crystal)
		var tag := Label3D.new()
		tag.text = "SAMPLE"
		tag.font_size = 28
		tag.fixed_size = true
		tag.pixel_size = 0.0012
		tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		tag.modulate = Color(0.5, 1.0, 0.9)
		tag.position = Vector3(0, 1.6, 0)
		node.add_child(tag)
		moon.add_child(node)
		find_nodes[String(f.id)] = node


## The find within reach of the suit, or {}.
func find_in_reach() -> Dictionary:
	if suit == null or Session.slot < 0:
		return {}
	var reach := float(SurfaceFinds.config().get("reach_m", 2.5))
	for f in Session.finds_here():
		if bool(f.taken):
			continue
		var d := suit.distance_to(Vector3(float(f.x), 0, float(f.z)))
		if d <= (reach if String(f.kind) == "sample" else 9.0):
			return f
	return {}


## E on foot next to a find: bag the sample or strip the wreck.
func take_find() -> String:
	var f := find_in_reach()
	if f.is_empty():
		return ""
	var r := Session.take_find(String(f.id))
	if bool(r.ok) and find_nodes.has(String(f.id)):
		(find_nodes[String(f.id)] as Node3D).visible = false
	_find_message = String(r.message)
	_find_message_t = model.elapsed_s
	return String(r.message)


var _find_message := ""
var _find_message_t := -100.0


## Space fires the lift jets; with hover hold on they cancel the fall instead; lifting off on auto, full lift.
func _lift_command() -> float:
	if not _on_surface() or model.autoland:
		return 0.0
	if auto_ascent:
		return 1.0
	if not walking and not outside and Input.is_key_pressed(KEY_SPACE):
		return 1.0
	if hover_hold and model.lift_accel() > 0.0:
		var up := maxf(model.basis.y.dot(Vector3.UP), 0.2)
		return clampf((model.gravity - model.vel.y * 1.2) / (model.lift_accel() * up), 0.0, 1.0)
	return 0.0


func _update_descent_hud() -> void:
	var to_pad := Vector2(model.pos.x - model.pad.x, model.pos.z - model.pad.z).length()
	var alt := model.altitude()
	var body := _body()
	var target := "MINING CAMP" if _target_kind == "camp" else "BASE PAD"
	var head := ""
	if phase == "ascent":
		head = "LIFT-OFF  %s    %s" % [String(body.get("name", "Moon")).to_upper(), "AUTO LIFT ON (Esc)" if auto_ascent else "Esc: lift off on auto"]
	elif job.is_empty():
		head = "%s  %s    %s" % [String(body.get("name", "Moon")).to_upper(), target, "HOVER HOLD (H)" if hover_hold else "F on the pad: shut down"]
	else:
		head = "DESCENT  %s  %s    %s" % [String(job.get("destination", "")).to_upper(), String(body.get("name", "")).to_upper(),
				"AUTOLAND ON (Esc)" if model.autoland else ("no beacon: land by hand" if not _beacon else ("HOVER HOLD (H)" if hover_hold else "Esc: autoland"))]
	var lines := PackedStringArray([head,
		"ALTITUDE  %.0f m    V/S  %+.1f m/s    DRIFT  %.1f m/s" % [alt, model.vel.y, Vector2(model.vel.x, model.vel.z).length()],
		("CLIMB TO  %.0f m" % float(model.land_cfg.get("ascent_clear_m", 1500.0))) if phase == "ascent" else "%s  %.0f m    TILT  %.0f°" % [target, to_pad, model.tilt_deg()],
		"LIFT  %d%%    %.2f m/s² available, gravity %.2f" % [roundi(model.lift * 100.0), model.lift_accel(), model.gravity],
		"THROTTLE  %d%%    FUEL  %.2f t" % [roundi(model.throttle * 100.0), model.fuel_t],
		"HEAT  %d%%    HULL  %d%%" % [roundi(model.heat_fraction() * 100.0), roundi((1.0 - model.damage) * 100.0)]])
	hud.text = "\n".join(lines)
	bar.value = model.lift
	if pad_label != null:
		pad_label.visible = alt > 80.0 and not outside   # a beacon from above, not a wall of text up close
	var hint := ""
	if phase == "ascent":
		if model.landed:
			hint = "Space: lift off (or Esc for auto).  F: stay and shut down.  G: get up and walk outside."
		elif not model.has_fuel():
			hint = "OUT OF FUEL"
		else:
			hint = "Climb clear of the moon. W/S still runs the main engine."
	elif model.landed and model.on_pad():
		hint = ("Landed. F: shut down and unload.   G: get up and walk outside.") if not job.is_empty() else "On the pad. F: shut down.   G: get up and walk outside."
	elif model.landed:
		hint = "Down %.0f m from the %s. Lift off (Space) and set down within %d m%s." % [to_pad, "camp's pad" if _target_kind == "camp" else "pad",
				int(model.zone_m if model.zone_m > 0.0 else float(model.land_cfg.get("landing_zone_m", 120.0))),
				"" if model.has_fuel() else ". Out of fuel: F calls a crawler to tow you in"]
	elif not model.has_fuel():
		hint = "OUT OF FUEL"
	elif model.last_impact > float(model.tune.get("soft_impact_m_s", 1.5)) and model.elapsed_s - _impact_shown < 3.0:
		hint = "HARD LANDING"
	elif alt < 60.0 and model.vel.y < -float(model.land_cfg.get("touchdown_speed_m_s", 3.0)) * 1.5:
		hint = "SINKING FAST: hold Space"
	elif not model.autoland:
		hint = "Space: lift jets.  H: hover.  Tilt to drift toward the pad.%s" % ("  Esc: let the autopilot land." if _beacon else "")
	prompt.text = hint


# --- On foot outside --------------------------------------------------------------------------------

## Out through the airlock onto the surface (the ship must be down).
func go_outside() -> bool:
	if phase != "descent" or not model.landed or walk.airlock == Vector3.INF:
		return false
	var cells: Array[Vector3i] = []
	for m in ship_data.modules:
		for c in ship_data.world_cells(m.id, m.cell, m.rot):
			cells.append(c)
	var origin := model.pos + model.basis * view.position
	var out_dir := -walk.airlock_face
	var hatch_local := Vector3(walk.airlock.x, 0, walk.airlock.z) + out_dir * 2.6
	suit_hatch = origin + model.basis * hatch_local
	suit = SurfaceWalker.make(model.terrain, model.gravity, cells, origin, model.basis)
	suit.place(suit_hatch)
	suit.face(model.basis * out_dir)
	if ops == null:
		ops = SurfaceOps.new()
		moon.add_child(ops)
		ops.setup(self, _site_here())
	outside = true
	ops.begin_outing()
	walking = false
	view.set_interior(false)
	help.text = SUIT_HELP
	crosshair.visible = true
	_apply_pose()
	return true


## Back in through the airlock.
func come_aboard() -> bool:
	if not outside or suit.distance_to(suit_hatch) > 2.5:
		return false
	if ops != null:
		ops.end_outing()
	bar.visible = true
	outside = false
	walking = true
	walk.stand_in_airlock()
	view.set_interior(true)
	help.text = WALK_HELP
	_apply_pose()
	return true


func _suit_step(delta: float) -> void:
	var dir := Vector2.ZERO
	if Input.is_key_pressed(KEY_W): dir.y += 1.0
	if Input.is_key_pressed(KEY_S): dir.y -= 1.0
	if Input.is_key_pressed(KEY_D): dir.x += 1.0
	if Input.is_key_pressed(KEY_A): dir.x -= 1.0
	var yaw := 0.0
	var pitch := 0.0
	if Input.is_key_pressed(KEY_LEFT): yaw += 1.0
	if Input.is_key_pressed(KEY_RIGHT): yaw -= 1.0
	if Input.is_key_pressed(KEY_UP): pitch += 1.0
	if Input.is_key_pressed(KEY_DOWN): pitch -= 1.0
	suit.look(yaw * KEY_TURN * delta, pitch * KEY_TURN * delta)
	suit.step(minf(delta, 0.05), dir, Input.is_key_pressed(KEY_SHIFT), Input.is_key_pressed(KEY_SPACE), Input.is_key_pressed(KEY_SPACE))
	if ops != null:
		ops.step(minf(delta, 0.05), Input.is_key_pressed(KEY_SHIFT) and dir != Vector2.ZERO)


func _suit_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		suit.look(-event.relative.x * MOUSE_TURN * GameSettings.mouse_sensitivity(), -event.relative.y * MOUSE_TURN * GameSettings.mouse_sensitivity())
		return
	if event is InputEventMouseButton and event.pressed:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		return
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	match event.keycode:
		KEY_E:
			if ops != null and ops.use() != "":
				return
			if take_find() == "":
				come_aboard()
		KEY_Q:
			come_aboard()
		KEY_ESCAPE:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _suit_prompt() -> void:
	var d := suit.distance_to(suit_hatch)
	var parts := PackedStringArray(["%s SURFACE" % String(_body().get("name", "MOON")).to_upper()])
	if ops != null:
		hud.text = "\n".join(ops.hud_lines())
	bar.visible = false
	var f := find_in_reach()
	var job_prompt := ops.prompt() if ops != null else ""
	if job_prompt != "":
		parts.append(job_prompt)
	elif not f.is_empty():
		parts.append("E: take the sample (%s)" % String(f.name) if String(f.kind) == "sample" else "E: strip salvage from the wreck")
	elif model.elapsed_s - _find_message_t < 4.0:
		parts.append(_find_message)
	else:
		parts.append("E: back aboard" if d <= 2.5 else "Airlock hatch %.0f m" % d)
	var held := Session.finds_aboard() if Session.slot >= 0 else {}
	if int(held.get("samples", 0)) + int(held.get("salvage", 0)) > 0:
		parts.append("Locker: %d samples, %d salvage" % [int(held.samples), int(held.salvage)])
	prompt.text = "   ".join(parts)


func _ground_for(t: SurfaceTerrain) -> MeshInstance3D:
	var body := _body()
	var g: Array = body.get("ground", [0.42, 0.41, 0.40])
	var r: Array = body.get("rock", [0.30, 0.29, 0.28])
	return t.build_mesh(float(model.land_cfg.get("terrain_size_m", 4000.0)), int(model.land_cfg.get("terrain_cells", 96)),
			Color(float(g[0]), float(g[1]), float(g[2])), Color(float(r[0]), float(r[1]), float(r[2])))


## Runs on a worker thread while the ship cruises, so the descent opens without a pause.
func _prebuild_ground() -> void:
	var t := _make_terrain()
	_ground_mesh = _ground_for(t)
	_ground_terrain = t


func _exit_tree() -> void:
	if _ground_task >= 0:
		WorkerThreadPool.wait_for_task_completion(_ground_task)
		_ground_task = -1


## Which surface site the ship is at: "pad" or "camp" (by the nearer pad).
func _site_here() -> String:
	var c := SurfaceFinds.camp_xz()
	return "camp" if Vector2(model.pos.x - c.x, model.pos.z - c.y).length() < Vector2(model.pos.x, model.pos.z).length() else "pad"


## From the airlock desk: out on the surface in the suit straight away.
func _suit_up() -> void:
	if _on_surface() and model.landed:
		go_outside()


## Out of air: the crew bring you in through the hatch.
func blackout() -> void:
	if not outside:
		return
	suit.place(suit_hatch)
	come_aboard()


## Coming aboard from the berth: standing in the airlock instead of behind the seats.
func walk_from_airlock() -> void:
	if walking and walk.stand_in_airlock():
		_apply_pose()

