extends Node3D
## Flying the ship. Leaves the dock, burns, turns, brakes and comes back in. Free flight for now:
## no sim time passes and jumps between stars are not here yet (see docs/runtime/economy-sim.md).
##
## Costs: fuel burned and hull repairs are charged and the clock advances when the flight ends.
## Controls: W/S throttle up/down, Z cut throttle, arrow keys pitch and yaw, Q/E roll, X braking
## autopilot, R toggle rotation assist, C camera, F dock when close and slow, Esc back to the dock.

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
const CLEAR_M := 3000.0
const WARPS := [1, 2, 5, 10, 25, 60]
var _impact_shown := -10.0
var _impacts_seen := 0


func _ready() -> void:
	_build_world()
	_build_ship()
	_build_hud()
	if not Session.flight_job.is_empty():
		_setup_transfer()


func _build_world() -> void:
	var env := Environment.new()
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
	var sun := DirectionalLight3D.new()
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
	job = Session.flight_job
	xfer = TransferFlight.plan(stats, float(job.dv_kms), String(job.key))
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


## Arrived at the marker: the destination's station comes up and the ship is brought to rest 1.5 km
## off its docking collar.
func _begin_approach() -> void:
	phase = "approach"
	station.visible = true
	station_label.text = String(job.destination).to_upper()
	model.station_solid = true
	model.pos = Vector3(0.35, 0.15, 1.0).normalized() * 1500.0
	model.vel = Vector3.ZERO
	model.braking = false
	model.throttle = 0.0
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
	model = FlightModel.from_stats(stats)
	model.place_at_dock(Vector3(0.35, 0.15, 1.0))
	com = stats.com
	ship_root = Node3D.new()
	add_child(ship_root)
	view = ShipView.new()
	ship_root.add_child(view)
	view.position = -com                       # turn about the centre of mass
	view.rebuild(ship, manifest)
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
	var help := Brand.note("W/S throttle   Z cut   arrows pitch+yaw   Q/E roll   X brake autopilot   R assist   C camera   F dock   , . time   Esc back to the dock", 13)
	help.autowrap_mode = TextServer.AUTOWRAP_OFF
	help.custom_minimum_size = Vector2(1000, 0)
	help.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT, Control.PRESET_MODE_MINSIZE, 20)
	layer.add_child(help)


func _process(delta: float) -> void:
	if leaving or model == null:
		return
	var turn := Vector3.ZERO
	if Input.is_key_pressed(KEY_UP): turn.x += 1.0
	if Input.is_key_pressed(KEY_DOWN): turn.x -= 1.0
	if Input.is_key_pressed(KEY_LEFT): turn.y += 1.0
	if Input.is_key_pressed(KEY_RIGHT): turn.y -= 1.0
	if Input.is_key_pressed(KEY_Q): turn.z += 1.0
	if Input.is_key_pressed(KEY_E): turn.z -= 1.0
	var thr := 0.0
	if Input.is_key_pressed(KEY_W): thr += 1.0
	if Input.is_key_pressed(KEY_S): thr -= 1.0
	if Input.is_key_pressed(KEY_Z):
		model.throttle = 0.0
	if turn != Vector3.ZERO or thr != 0.0:
		model.braking = false          # any pilot input takes the controls back
	if xfer == null:
		model.step(minf(delta, 0.05), turn, thr)
	else:
		var total := minf(delta, 0.05) * float(_warp())
		var n := maxi(1, ceili(total / 0.05))
		for i in n:
			model.step(total / float(n), turn, thr)
			if phase == "cruise" and xfer.arrived(model):
				_begin_approach()
				break
		if phase == "depart" and model.pos.length() > CLEAR_M:
			phase = "cruise"
			station.visible = false
			model.station_solid = false
		_wrap_markers()
	if model.impacts != _impacts_seen:
		_impacts_seen = model.impacts
		_impact_shown = model.elapsed_s
	_apply_pose()
	_update_hud()
	view.set_flames(model.throttle > 0.02 and model.has_fuel())
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
	if chase:
		var back := model.basis * Vector3(0, 6.0, 26.0)
		camera.global_position = model.pos + back
		camera.look_at(model.pos + model.basis * Vector3(0, 1.5, -10.0), model.basis.y)
	else:
		camera.global_position = model.pos + model.basis * cockpit_pos
		camera.global_basis = model.basis


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
	if xfer != null and phase != "approach":
		_update_transfer_hud()
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


func _unhandled_input(event: InputEvent) -> void:
	if leaving or not (event is InputEventKey) or not event.pressed or event.echo:
		return
	match event.keycode:
		KEY_X:
			model.braking = not model.braking
		KEY_R:
			model.assist = not model.assist
		KEY_C:
			chase = not chase
			_apply_pose()
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
	if xfer != null:
		Session.finish_local_flight(model.fuel_burned_t, model.elapsed_s, model.damage, _arrived, not model.has_fuel() and (phase != "approach" or not model.can_dock()))
	else:
		Session.finish_flight(model.fuel_burned_t, model.elapsed_s, model.damage)
	get_tree().change_scene_to_file(Session.DOCK_SCENE)
