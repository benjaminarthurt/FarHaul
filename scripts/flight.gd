class_name FlightScene
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
var planet: MeshInstance3D    ## the system's world, far off in space (hidden over a moon)
var hud: Label
var prompt: Label
var notice := ""        ## a short message that wins the prompt for a few seconds (notice_s)
var notice_s := 0.0
var time_label: Label   ## the time compression readout, top right
var time_shown_s := 0.0  ## seconds left to show the readout at x1 after a , . or / press
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
## Flight keys still held from before you took the helm (E to sit down is also roll; W walked you to the
## seat). They are ignored until let go, so sitting down doesn't steer or cancel the braking autopilot.
var held_from_before: Array[int] = []
const FLIGHT_KEYS: Array[int] = [KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT, KEY_Q, KEY_E, KEY_W, KEY_S, KEY_Z]
var help: Label
var crosshair: Label
const MOUSE_TURN := 0.0025     ## radians per pixel of mouse movement, times the mouse sensitivity setting
const KEY_TURN := 1.8          ## radians per second with the arrow keys
const FLY_HELP := "W/S throttle   Z cut   arrows pitch+yaw   Q/E roll   X autopilot stop   V course hold   R assist   C camera   F dock   J jump (when clear)   , . time  / x1   G get up   Esc back to the dock   F10 menu"
const WALK_HELP := "WASD walk   mouse or arrows look   Shift run   E use (helm, ladder, airlock)   , . time  / x1   Esc frees the mouse   F10 menu"
const LAND_HELP := "Space lift jets   H hover hold   W/S main engine   arrows pitch+yaw   Q/E roll   Esc autoland   F unload (landed on the pad)   G get up   C camera   F10 menu"
const SUIT_HELP := "WASD walk   Shift run   Space jump (hold for suit jets)   mouse or arrows look   E use   Q back aboard (at the hatch)   F10 menu"
var ship_data: ShipData
var moon: MoonScenery          ## the ground and everything on it, once the ship is over a moon
var find_nodes := {}            ## find id -> its node on the ground (MoonScenery)
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
var _hazards_shown := 0
var _hazard_t := -100.0
var sounds: WorldAudio         ## room tone, engines, the suit's breathing, footsteps, cues
var _step_acc := 0.0
var _last_feet := Vector3.INF
var jump_c: JumpSequence       ## a flown star jump (scripts/flight/jump_sequence.gd)
var foot_c: OnFoot             ## walking the ship and the suit outside (scripts/flight/on_foot.gd)
var land_c: Landing            ## descents, lift-offs and the moon coming and going (scripts/flight/landing.gd)
var world_c: SpaceScenery      ## sky, sun, motes and the station (scripts/flight/space_scenery.gd)
var hud_c: FlightHud           ## builds and refreshes the readouts (scripts/flight/flight_hud.gd)
var ops: SurfaceOps            ## the suit's air, jets and scanner, mission points and crates (on the moon)


func _init() -> void:
	hud_c = FlightHud.new(self)
	jump_c = JumpSequence.new(self)
	foot_c = OnFoot.new(self)
	land_c = Landing.new(self)
	world_c = SpaceScenery.new(self)


func _ready() -> void:
	_build_world()
	_build_ship()
	model.station_boxes = world_c.boxes   # the station's modules are solid too
	_build_hud()
	sounds = WorldAudio.new()
	add_child(sounds)
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
	world_c._build_world()


func _make_station() -> Node3D:
	return world_c._make_station()


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


func _setup_jump() -> void:
	jump_c._setup_jump()


func _jumping() -> bool:
	return jump_c._jumping()


func _tune(key: String, fallback: float) -> float:
	return jump_c._tune(key, fallback)


func _jump_blocker() -> String:
	return jump_c._jump_blocker()


func _start_jump() -> void:
	jump_c._start_jump()


func _jump_step(delta: float) -> void:
	jump_c._jump_step(delta)


func _arrive_in_system() -> void:
	jump_c._arrive_in_system()


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
	model.course_hold = false
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
			cockpit_pos = ShipGrid.cell_to_world(m.cell) - com + Vector3(0, Interiors.FLOOR + 1.2, 0.05)   # seated eye height, between the seats
	camera = Camera3D.new()
	camera.fov = 70.0
	camera.far = 9000.0
	add_child(camera)
	camera.current = true
	_apply_pose()


func _build_hud() -> void:
	hud_c._build_hud()


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
		for k in held_from_before.duplicate():
			if not Input.is_key_pressed(k):
				held_from_before.erase(k)
		if _flight_key(KEY_UP): turn.x += 1.0
		if _flight_key(KEY_DOWN): turn.x -= 1.0
		if _flight_key(KEY_LEFT): turn.y += 1.0
		if _flight_key(KEY_RIGHT): turn.y -= 1.0
		if _flight_key(KEY_Q): turn.z += 1.0
		if _flight_key(KEY_E): turn.z -= 1.0
		if _flight_key(KEY_W): thr += 1.0
		if _flight_key(KEY_S): thr -= 1.0
		if _flight_key(KEY_Z):
			model.throttle = 0.0
	if turn != Vector3.ZERO or thr != 0.0:
		model.braking = false          # any pilot input takes the controls back
	if turn != Vector3.ZERO and model.course_hold:
		model.course_hold = false      # steering by hand: course hold lets go (the throttle stays the pilot's anyway)
		say("Course hold off.")
	if model.course_hold and not (phase == "cruise" or phase == "depart"):
		model.course_hold = false
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
	_mix_audio(delta)
	for ring in station.get_children():
		if ring.has_meta("spin"):
			ring.rotate_z(delta * 0.05)


## Time compression actually in use: the rate chosen with , and . brought down to the limit here.
func _warp() -> int:
	var cap := int(_warp_limit().max)
	var w := 1
	for r in WARPS:
		if r <= mini(WARPS[warp_index], cap):
			w = r
	return w


const WARP_FROM_M := 1000.0       ## time compression unlocks this far out from the station
const WARP_REAL_S := 10.0         ## never less than this many real seconds from arriving at the target


## How fast time may run here, and why if that is below the fastest: {max, why}. Off a run, near the
## station on the way out, on the approach and at the brake point (flying by hand) it is x1. Closing
## on the target it comes down in steps: x5 within 25 km, x2 within 5 km, and never so fast that the
## target is less than WARP_REAL_S real seconds away.
func _warp_limit() -> Dictionary:
	var top: int = WARPS[WARPS.size() - 1]
	if xfer == null:
		return {"max": 1, "why": "Time compression works on runs only"}
	if phase == "depart" and model.pos.length() < WARP_FROM_M:
		return {"max": 1, "why": "Time compression starts %.0f km out: %.1f km to go" % [WARP_FROM_M / 1000.0, (WARP_FROM_M - model.pos.length()) / 1000.0]}
	if phase == "approach":
		return {"max": 1, "why": "No time compression on the approach to the station"}
	if phase != "cruise" and phase != "depart":
		return {"max": 1, "why": "No time compression near the ground"}
	if phase == "cruise" and xfer.brake_now(model) and not model.braking:
		return {"max": 1, "why": "Held at x1 at the brake point: brake now (X)"}
	var cap := top
	var why := ""
	var rng := xfer.range_to(model)
	if rng < 5000.0:
		cap = 2
		why = "Max x2 within 5 km of the target"
	elif rng < 25000.0:
		cap = 5
		why = "Max x5 within 25 km of the target"
	var eta := xfer.eta_s(model)
	if eta > 0.0:
		var by_eta := 1
		for r in WARPS:
			if eta / float(r) >= WARP_REAL_S:
				by_eta = r
		if by_eta < cap:
			cap = by_eta
			why = "Max x%d: the target is %s away at this speed" % [by_eta, _clock(eta)]
	return {"max": cap, "why": why}


## Why time is held at x1 whatever rate is chosen, or "" when some compression is allowed.
func _warp_hold() -> String:
	var lim := _warp_limit()
	return String(lim.why) if int(lim.max) <= 1 else ""


## A message that takes the prompt for a few seconds.
func say(text: String, seconds := 3.0) -> void:
	notice = text
	notice_s = seconds


## Course hold on or off. It only engages on a run with the nose within COURSE_AIM_DEG of the target:
## the pilot lines up, then hands over.
const COURSE_AIM_DEG := 5.0
func toggle_course_hold() -> void:
	if model.course_hold:
		model.course_hold = false
		say("Course hold off.")
		return
	if xfer == null or not (phase == "cruise" or phase == "depart"):
		say("Course hold works on a run, on the way to the target.")
		return
	var off := model.aim_error_deg(xfer.target)
	if off > COURSE_AIM_DEG:
		say("Course hold: point within %.0f° of the diamond first (%.0f° off now)." % [COURSE_AIM_DEG, off], 4.0)
		return
	model.course_hold = true
	model.course_to = xfer.target
	model.braking = false
	say("Course hold on: it keeps your travel on the target. You keep the throttle.")


## What course hold is doing, for the prompt, or "" when it is off.
func course_status() -> String:
	if not model.course_hold:
		return ""
	var off := "   V or any turn: off"
	if model.trimming:
		var to := (model.course_to - model.pos).normalized()
		var drift := model.vel - to * maxf(model.vel.dot(to), 0.0)
		return "COURSE HOLD: trimming %.1f m/s of drift%s" % [drift.length(), off]
	if model.throttle > 0.0:
		return "COURSE HOLD: steering the burn onto the target%s" % off
	return "COURSE HOLD: on target%s" % off


## Out of fuel on a run, a tug takes you to whichever is nearer: on to the destination (and the run is
## delivered) or back to where you started. It can't land you, so a run to the surface goes back.
func tow_goes_on() -> bool:
	if xfer == null or model.has_fuel() or not (phase == "cruise" or phase == "depart"):
		return false
	if String(job.get("dest_kind", "")) in LocalSpace.SURFACE:
		return false
	return xfer.range_to(model) < model.pos.length()


## What the tug would cost, for the prompt.
static func tow_fee() -> int:
	var lv := SimShip.level(String(Session.profile.get("difficulty", "normal")))
	return roundi(float(LocalSpace.config()["board"]["tow_fee_cr"]) * float(lv.get("port_fee_mult", 1.0)))


## What the braking autopilot is doing, for the prompt, or "" when it is off.
func brake_status() -> String:
	if not model.braking:
		return ""
	var take := "   X or any control: take over"
	var at_target := model.brake_to != Vector3.INF
	match model.brake_state:
		"coasting":
			return "AUTOPILOT: stopping at the target. Coasting tail-first, burn in %s%s" % [_clock(model.brake_burn_in_s), take]
		"burning":
			var over := xfer.stopping_distance(model) - xfer.range_to(model) if xfer != null else 0.0
			if over > 5000.0:   # past the point of stopping in time: say so rather than promise the mark
				return "AUTOPILOT: too fast to stop at the target. Burning hard, you will overshoot by about %.0f km%s" % [over / 1000.0, take]
			return "AUTOPILOT: stopping at the target. Burning, %.1f km to go%s" % [(model.brake_to - model.pos).length() / 1000.0, take]
		"turning":
			return ("AUTOPILOT: turning tail-first to stop at the target" if at_target else "AUTOPILOT: turning tail-first to stop") + take
	if at_target:
		return "AUTOPILOT: moving away from the target, stopping here%s" % take
	return "AUTOPILOT: stopping here%s" % take


static func _clock(s: float) -> String:
	if s < 0.0:
		return "-"
	return "%d:%02d" % [int(s) / 60, int(s) % 60] if s < 3600.0 else "%dh %02dm" % [int(s) / 3600, (int(s) / 60) % 60]


## Choose a time compression rate (an index into WARPS); 0 is normal time.
func set_warp(i: int) -> void:
	warp_index = clampi(i, 0, WARPS.size() - 1)
	time_shown_s = 2.5   # every press answers on screen, even when nothing can change


## Keep the speed markers around the ship however far it has come.
func _wrap_markers() -> void:
	for m in sparks:
		var rel := m.position - model.pos
		rel = Vector3(fposmod(rel.x + 700.0, 1400.0) - 700.0, fposmod(rel.y + 700.0, 1400.0) - 700.0, fposmod(rel.z + 700.0, 1400.0) - 700.0)
		m.position = model.pos + rel


## A flight key held down by the pilot, not one still held from walking to the seat.
func _flight_key(k: int) -> bool:
	return Input.is_key_pressed(k) and not k in held_from_before


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


func _update_reticle() -> void:
	hud_c._update_reticle()


func _screen_dir(dir: Vector3) -> Vector2:
	return hud_c._screen_dir(dir)


func _update_transfer_hud() -> void:
	hud_c._update_transfer_hud()


func _update_hud() -> void:
	hud_c._update_hud()


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
		KEY_V:
			toggle_course_hold()
		KEY_X:
			model.braking = not model.braking
			if model.braking:
				model.course_hold = false   # the braking autopilot takes out drift too
			# On a run the autopilot stops at the target; anywhere else it stops the ship where it is.
			model.brake_to = xfer.target if model.braking and xfer != null and phase == "cruise" else Vector3.INF
		KEY_R:
			model.assist = not model.assist
		KEY_C:
			chase = not chase
			_apply_pose()
		KEY_J:
			if String(job.get("kind", "")) == "jump" and phase == "depart" and _jump_blocker() == "":
				_start_jump()
		KEY_PERIOD:
			set_warp(warp_index + 1)
		KEY_COMMA:
			set_warp(warp_index - 1)
		KEY_SLASH:
			set_warp(0)
		KEY_F:
			if model.can_dock():
				if phase == "approach":
					_arrived = true   # docked at the destination
				_return_to_dock()
		KEY_ESCAPE:
			if phase == "approach":
				_arrived = true   # the station's traffic control brings the ship in
			elif tow_goes_on():
				_arrived = true   # out of fuel nearer the destination: the tug takes you on and the run is delivered
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

func get_up() -> bool:
	return foot_c.get_up()


func sit_down() -> void:
	foot_c.sit_down()


func _berthed() -> bool:
	return foot_c._berthed()


func _walk_step(delta: float) -> void:
	foot_c._walk_step(delta)


func _walk_input(event: InputEvent) -> void:
	foot_c._walk_input(event)


func use() -> String:
	return foot_c.use()


func _walk_prompt() -> void:
	hud_c._walk_prompt()


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
	var sys := _system_id()
	return SurfaceTerrain.make(sys + LocalSpace.SEP + "moon", [SurfaceFinds.camp_xz()] + SurfaceSites.pads(sys), SurfaceSites.craters(sys))


func _pad_pos(kind: String) -> Vector3:
	return land_c._pad_pos(kind)


func _can_land() -> bool:
	return land_c._can_land()


func _stranded() -> bool:
	return land_c._stranded()


func _ensure_moon() -> void:
	land_c._ensure_moon()


func _begin_surface(kind: String) -> void:
	land_c._begin_surface(kind)


func _aim_descent_at(kind: String) -> void:
	land_c._aim_descent_at(kind)


func _begin_descent() -> void:
	land_c._begin_descent()


func _reach_orbit() -> void:
	land_c._reach_orbit()


func _begin_surface_free() -> void:
	land_c._begin_surface_free()


func _build_moon(body: Dictionary) -> void:
	moon = MoonScenery.new()
	add_child(moon)
	moon.build(_system_id(), model.terrain, model.land_cfg, body, model.rocks, _ground_mesh)
	pad_label = moon.pad_label
	find_nodes = moon.find_nodes


func find_in_reach() -> Dictionary:
	return foot_c.find_in_reach()


func take_find() -> String:
	return foot_c.take_find()


var _find_message := ""
var _find_message_t := -100.0


func _lift_command() -> float:
	return land_c._lift_command()


func _update_descent_hud() -> void:
	hud_c._update_descent_hud()


# --- On foot outside --------------------------------------------------------------------------------

func go_outside() -> bool:
	return foot_c.go_outside()


func come_aboard() -> bool:
	return foot_c.come_aboard()


func _suit_step(delta: float) -> void:
	foot_c._suit_step(delta)


func _suit_input(event: InputEvent) -> void:
	foot_c._suit_input(event)


func _suit_prompt() -> void:
	hud_c._suit_prompt()


## Runs on a worker thread while the ship cruises, so the descent opens without a pause.
func _prebuild_ground() -> void:
	var t := _make_terrain()
	_ground_mesh = MoonScenery.ground_mesh(t, model.land_cfg, _body())
	_ground_terrain = t


func _exit_tree() -> void:
	if _ground_task >= 0:
		WorkerThreadPool.wait_for_task_completion(_ground_task)
		_ground_task = -1


## Engines heard through the hull (not out on an airless moon), the ship's own hum aboard, the suit's
## breathing outside, and footsteps on deck or in the dust.
func _mix_audio(_delta: float) -> void:
	var fuel := model.has_fuel()
	var thr := absf(model.throttle) if fuel else 0.0
	var lift := model.lift if fuel else 0.0
	sounds.level("engine", 0.0 if outside else thr, 0.8 + 0.4 * thr)
	sounds.level("lift", 0.0 if outside else lift, 0.9 + 0.3 * lift)
	sounds.level("ship_hum", 0.0 if outside else (1.0 if walking else 0.55))
	var running := Input.is_key_pressed(KEY_SHIFT)
	sounds.level("breath", (1.0 if running else 0.7) if outside else 0.0, 1.15 if running else 1.0)
	var feet := Vector3.INF
	var on_ground := true
	if outside and suit != null:
		feet = suit.pos
		on_ground = suit.on_ground
	elif walking and walk != null:
		feet = walk.pos
	if feet == Vector3.INF or _last_feet == Vector3.INF:
		_last_feet = feet
		return
	if on_ground:
		_step_acc += Vector2(feet.x - _last_feet.x, feet.z - _last_feet.z).length()
	_last_feet = feet
	if _step_acc > (0.95 if running else 0.75):
		_step_acc = 0.0
		sounds.step("dust" if outside else "metal")


func _site_here() -> String:
	return foot_c._site_here()


func _suit_up() -> void:
	foot_c._suit_up()


func blackout() -> void:
	foot_c.blackout()


func walk_from_airlock() -> void:
	foot_c.walk_from_airlock()

