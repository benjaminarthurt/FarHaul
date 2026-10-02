extends Node3D
## The shipyard: a free-build ship designer. Place parts, check the stats, preview the ship with cargo aboard.
## Contracts, money and flight belong to the game proper, not here.
## Everything (camera, lights, UI) is created in code so there's nothing to wire up in the editor.

const GOOD := Color(0.25, 1.0, 0.4, 0.45)
const BAD := Color(1.0, 0.25, 0.25, 0.45)
const GRID_HALF := 12  # grid extends this many cells each way from the origin
const SAVE_PATH := "user://ship.json"
const AUTOSAVE_PATH := "user://autosave.json"
const OK_COLOR := Color(0.35, 0.85, 0.45)
const BAD_COLOR := Color(0.95, 0.35, 0.3)
const WARN_COLOR := Color(1.0, 0.7, 0.25)

var library: ModuleLibrary
var ship: ShipData
var manifest: CargoManifest  ## what the ship is carrying
var ship_view: ShipView
var history := ShipHistory.new()

var busy := false  ## reserved for animations that should freeze editing
var muted := false
var autosave_enabled := not OS.has_environment("FARHAUL_NOSAVE")
var last_stats: Dictionary = {}

# Building
var selected := 0  # index into library.order
var rot := 0  # quarter-turns around Y
var level := 0  # which deck (Y layer) we're building on
var hide_decks_above := false
var pop_index := -1

var ghost: Node3D
var ghost_mat: StandardMaterial3D
var hover_active := false
var hover_cell := Vector3i.ZERO
var hover_rot := 0
var hover_error := ""  # "" means the ghost's position is valid

# Camera
var camera: Camera3D
var cam_target := Vector3.ZERO
var cam_goal_target := Vector3.ZERO
var cam_yaw := 0.6
var cam_pitch := 0.9
var cam_dist := 24.0
var cam_goal_dist := 24.0

var grid: MeshInstance3D
var com_marker: MeshInstance3D

# UI
var buttons: Array[Button] = []
var info_label: Label
var stats_label: Label
var warn_label: Label
var top_label: Label
var help_label: Label
var message := ""
var meters: Dictionary = {}
var commodity_pick: OptionButton
var amount_box: SpinBox
var cargo_label: Label
var undo_button: Button
var redo_button: Button
var tip_panel: PanelContainer
var tip_label: Label
var welcome_panel: PanelContainer
var sfx_players: Array[AudioStreamPlayer] = []
var sfx_next := 0


func _ready() -> void:
	library = ModuleLibrary.new()
	ship = ShipData.new(library)
	manifest = CargoManifest.new(ship)

	_setup_environment()
	_setup_camera()
	_setup_grid()
	_setup_com_marker()
	ship_view = ShipView.new()
	add_child(ship_view)
	_setup_ui()
	_setup_sfx()

	_select(0)
	_set_level(0)
	var resumed := autosave_enabled and FileAccess.file_exists(AUTOSAVE_PATH) and _load_from(AUTOSAVE_PATH)
	if not resumed:
		ShipPresets.build(ship)
		welcome_panel.visible = true
	_refresh_ship()
	_frame_ship(true)


# --- Setup -----------------------------------------------------------------------------------

func _setup_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = SpaceSky.make()
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true  # lets lit windows, vents and engines bloom
	env.glow_intensity = 0.9
	env.glow_bloom = 0.08
	env.glow_hdr_threshold = 0.9
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.45, 0.5, 0.62)
	env.ambient_light_energy = 0.55
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var sun := DirectionalLight3D.new()  # warm key light with soft-ish shadows: the builder scene is tiny
	sun.rotation_degrees = Vector3(-50, 40, 0)
	sun.light_color = Color(1.0, 0.94, 0.85)
	sun.light_energy = 1.25
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 90.0
	sun.shadow_blur = 1.5
	add_child(sun)

	var fill := DirectionalLight3D.new()  # cool rim from the other side, no shadow
	fill.rotation_degrees = Vector3(-25, -140, 0)
	fill.light_color = Color(0.55, 0.7, 1.0)
	fill.light_energy = 0.45
	add_child(fill)


func _setup_camera() -> void:
	camera = Camera3D.new()
	camera.fov = 55.0
	camera.far = 2000.0
	add_child(camera)
	_update_camera()


func _setup_grid() -> void:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.5, 0.6, 0.8, 0.25)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA

	var im := ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_LINES, mat)
	var extent := (GRID_HALF + 0.5) * ShipGrid.CELL
	for i in range(-GRID_HALF, GRID_HALF + 2):
		var p := (i - 0.5) * ShipGrid.CELL  # lines sit on cell boundaries
		im.surface_add_vertex(Vector3(p, 0, -extent))
		im.surface_add_vertex(Vector3(p, 0, extent))
		im.surface_add_vertex(Vector3(-extent, 0, p))
		im.surface_add_vertex(Vector3(extent, 0, p))
	im.surface_end()

	grid = MeshInstance3D.new()
	grid.mesh = im
	add_child(grid)


## A yellow ball showing the ship's centre of mass, drawn on top of everything.
func _setup_com_marker() -> void:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.85, 0.2)
	mat.no_depth_test = true
	mat.render_priority = 10
	var sphere := SphereMesh.new()
	sphere.radius = 0.45
	sphere.height = 0.9
	sphere.material = mat
	com_marker = MeshInstance3D.new()
	com_marker.mesh = sphere
	com_marker.visible = false
	add_child(com_marker)


func _setup_sfx() -> void:
	for i in 6:
		var p := AudioStreamPlayer.new()
		p.volume_db = -6.0
		add_child(p)
		sfx_players.append(p)


func _sfx(sound: StringName) -> void:
	if muted:
		return
	var p := sfx_players[sfx_next]
	sfx_next = (sfx_next + 1) % sfx_players.size()
	p.stream = Sfx.stream(sound)
	p.play()


func _make_theme() -> Theme:
	var t := Theme.new()
	t.default_font_size = 14
	var panel := StyleBoxFlat.new()
	panel.bg_color = Color(0.06, 0.07, 0.10, 0.90)
	panel.set_corner_radius_all(6)
	panel.set_content_margin_all(10)
	panel.border_color = Color(0.25, 0.3, 0.4, 0.8)
	panel.set_border_width_all(1)
	t.set_stylebox("panel", "PanelContainer", panel)
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		var sb := StyleBoxFlat.new()
		sb.set_corner_radius_all(4)
		sb.content_margin_left = 8
		sb.content_margin_right = 8
		sb.content_margin_top = 3
		sb.content_margin_bottom = 3
		match state:
			"hover":
				sb.bg_color = Color(0.20, 0.24, 0.32)
			"pressed":
				sb.bg_color = Color(0.30, 0.36, 0.50)
			"disabled":
				sb.bg_color = Color(0.10, 0.11, 0.14)
			_:
				sb.bg_color = Color(0.13, 0.15, 0.20)
		t.set_stylebox(state, "Button", sb)
	t.set_constant("separation", "VBoxContainer", 3)
	return t


func _setup_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var ui := Control.new()
	ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.theme = _make_theme()
	layer.add_child(ui)

	_build_palette(ui)
	_build_top_bar(ui)
	_build_right_column(ui)

	help_label = Label.new()
	help_label.text = "Click place  ·  Shift+click remove\nR rotate  ·  Q/E deck  ·  Ctrl+Z undo  ·  F frame\nRight-drag orbit  ·  wheel zoom  ·  middle-drag pan\nH hide upper decks  ·  M mute  ·  F1 help"
	help_label.modulate = Color(0.75, 0.8, 0.9, 0.7)
	help_label.add_theme_font_size_override("font_size", 12)
	help_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(help_label)
	help_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT, Control.PRESET_MODE_MINSIZE, 12)
	help_label.grow_vertical = Control.GROW_DIRECTION_BEGIN

	# Cursor tooltip.
	tip_panel = PanelContainer.new()
	tip_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tip_panel.visible = false
	ui.add_child(tip_panel)
	tip_label = Label.new()
	tip_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tip_panel.add_child(tip_label)

	_build_welcome(ui)


func _build_palette(ui: Control) -> void:
	var panel := PanelContainer.new()
	panel.position = Vector2(12, 12)
	ui.add_child(panel)
	var box := VBoxContainer.new()
	panel.add_child(box)

	var group_titles := {
		&"hull": "HULL (walkable)",
		&"cargo": "CARGO",
		&"external": "EXTERNAL (bolt-on)",
	}
	var last_group: StringName = &""
	for i in library.order.size():
		var def := library.get_def(library.order[i])
		if def.group != last_group:
			last_group = def.group
			box.add_child(_header(group_titles.get(def.group, String(def.group).to_upper())))
		var key := "%d" % ((i + 1) % 10) if i < 10 else " "
		var b := Button.new()
		b.text = "%s  %s   %s" % [key, def.display_name, ShipStats.commas(def.cost)]
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.focus_mode = Control.FOCUS_NONE  # keep keyboard shortcuts working after a click
		b.tooltip_text = _module_tooltip(def)
		b.pressed.connect(_select.bind(i))
		box.add_child(b)
		buttons.append(b)

	var row := HBoxContainer.new()
	box.add_child(row)
	_add_action_button(row, "Rotate (R)", _rotate)
	_add_action_button(row, "Save (S)", _save)
	_add_action_button(row, "Load (L)", _load)
	_add_action_button(row, "Clear (C)", _clear)
	var row2 := HBoxContainer.new()
	box.add_child(row2)
	undo_button = _add_action_button(row2, "Undo", _undo)
	redo_button = _add_action_button(row2, "Redo", _redo)
	_add_action_button(row2, "Starter ship", _load_starter)
	_add_action_button(row2, "Frame (F)", _frame_ship)

	info_label = Label.new()
	info_label.custom_minimum_size = Vector2(270, 0)
	info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(info_label)


func _build_top_bar(ui: Control) -> void:
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(panel)
	top_label = Label.new()
	top_label.add_theme_font_size_override("font_size", 16)
	panel.add_child(top_label)
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE, 12)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH


func _build_right_column(ui: Control) -> void:
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 8)
	ui.add_child(right)

	var stats_panel := PanelContainer.new()
	right.add_child(stats_panel)
	var stats_box := VBoxContainer.new()
	stats_panel.add_child(stats_box)
	stats_label = Label.new()
	stats_label.custom_minimum_size = Vector2(330, 0)
	stats_box.add_child(stats_label)
	meters["power"] = _make_meter(stats_box, "Power")
	meters["heat"] = _make_meter(stats_box, "Cooling")
	meters["cargo"] = _make_meter(stats_box, "Cargo")
	warn_label = Label.new()
	warn_label.custom_minimum_size = Vector2(330, 0)
	warn_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	warn_label.modulate = WARN_COLOR
	stats_box.add_child(warn_label)

	var cargo_panel := PanelContainer.new()
	right.add_child(cargo_panel)
	var cbox := VBoxContainer.new()
	cargo_panel.add_child(cbox)
	cbox.add_child(_header("CARGO PREVIEW"))
	var crow := HBoxContainer.new()
	cbox.add_child(crow)
	commodity_pick = OptionButton.new()
	commodity_pick.focus_mode = Control.FOCUS_NONE
	commodity_pick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for id in manifest.commodities.order:
		commodity_pick.add_item(manifest.commodities.label(id))
	crow.add_child(commodity_pick)
	amount_box = SpinBox.new()
	amount_box.min_value = 0
	amount_box.max_value = 500
	amount_box.step = 0.5
	amount_box.value = 20
	amount_box.suffix = "t"
	crow.add_child(amount_box)
	var brow := HBoxContainer.new()
	cbox.add_child(brow)
	_add_action_button(brow, "Load", _load_cargo)
	_add_action_button(brow, "Unload", _unload_cargo)
	_add_action_button(brow, "Unload all", _unload_all)
	var hint := Label.new()
	hint.text = "Fill the hold to see the ship loaded. Nothing is bought or sold here."
	hint.modulate = Color(0.65, 0.7, 0.8)
	hint.add_theme_font_size_override("font_size", 12)
	cbox.add_child(hint)
	cargo_label = Label.new()
	cargo_label.custom_minimum_size = Vector2(330, 0)
	cargo_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	cbox.add_child(cargo_label)

	right.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE, 12)
	right.grow_horizontal = Control.GROW_DIRECTION_BEGIN


func _build_welcome(ui: Control) -> void:
	welcome_panel = PanelContainer.new()
	welcome_panel.visible = false
	ui.add_child(welcome_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	welcome_panel.add_child(box)
	var title := Label.new()
	title.text = "FAR HAUL  ·  SHIPYARD"
	title.add_theme_font_size_override("font_size", 22)
	box.add_child(title)
	var body := Label.new()
	body.custom_minimum_size = Vector2(460, 0)
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.text = "Design your ship here. Parts are free.\n\n1. Build. Click to place a part, Shift+click to remove it. Green ghost means it fits, red tells you why not. Cyan rings are open doorways: cap them so the hull is sealed.\n2. Watch the power, cooling and cargo meters on the right.\n3. Use Cargo preview to see how the ship looks fully loaded. Save when you are happy."
	box.add_child(body)
	var go := Button.new()
	go.text = "Start building"
	go.focus_mode = Control.FOCUS_NONE
	go.pressed.connect(func() -> void: welcome_panel.visible = false)
	box.add_child(go)
	welcome_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_MINSIZE, 0)
	welcome_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	welcome_panel.grow_vertical = Control.GROW_DIRECTION_BOTH


func _header(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.modulate = Color(0.7, 0.8, 1.0)
	return l


func _add_action_button(parent: Control, text: String, callback: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(callback)
	parent.add_child(b)
	return b


## A labelled bar. Returns {bar, fill, value} for `_set_meter`.
func _make_meter(parent: Control, title: String) -> Dictionary:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var name_label := Label.new()
	name_label.text = title
	name_label.custom_minimum_size = Vector2(62, 0)
	row.add_child(name_label)
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.min_value = 0.0
	bar.max_value = 1.0
	bar.custom_minimum_size = Vector2(120, 12)
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var fill := StyleBoxFlat.new()
	fill.set_corner_radius_all(3)
	bar.add_theme_stylebox_override("fill", fill)
	var back := StyleBoxFlat.new()
	back.bg_color = Color(0.12, 0.14, 0.19)
	back.set_corner_radius_all(3)
	bar.add_theme_stylebox_override("background", back)
	row.add_child(bar)
	var value := Label.new()
	value.custom_minimum_size = Vector2(110, 0)
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(value)
	return {"bar": bar, "fill": fill, "value": value}


## `ratio` 0..1 fills the bar. Colour goes amber then red as it nears or passes `warn_above` and 1.
func _set_meter(m: Dictionary, ratio: float, text: String, colour_by_load := true) -> void:
	m.bar.value = clampf(ratio, 0.0, 1.0)
	m.value.text = text
	var col := Color(0.35, 0.6, 0.95)
	if colour_by_load:
		col = OK_COLOR if ratio <= 0.85 else (WARN_COLOR if ratio <= 1.0 else BAD_COLOR)
	m.fill.bg_color = col


func _module_tooltip(def: ModuleDef) -> String:
	var lines := PackedStringArray([def.display_name, "Cost %s cr   Mass %.1f t" % [ShipStats.commas(def.cost), def.mass]])
	if def.power != 0.0:
		lines.append("Power %+.0f kW" % def.power)
	if def.heat != 0.0:
		lines.append("Heat %+.0f kW%s" % [def.heat, " (cooling)" if def.heat < 0.0 else ""])
	if def.thrust > 0.0:
		lines.append("Thrust %.0f kN" % def.thrust)
	if def.fuel > 0.0:
		lines.append("Fuel %.0f t" % def.fuel)
	if def.cargo_slots > 0:
		lines.append("Cargo %d containers, %.0f t" % [def.cargo_slots, def.cargo_capacity])
	if def.helm:
		lines.append("Flight controls")
	if def.airlock:
		lines.append("Crew way in and out")
	lines.append("Walkable hull" if def.pressurized else "Bolts on outside")
	return "\n".join(lines)


# --- Input -----------------------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		get_viewport().gui_release_focus()  # so typed shortcuts reach us after using a text box
	if busy:
		return
	if event is InputEventMouseMotion:
		if event.button_mask & MOUSE_BUTTON_MASK_RIGHT:
			cam_yaw -= event.relative.x * 0.005
			cam_pitch = clampf(cam_pitch + event.relative.y * 0.005, 0.15, 1.5)
			_update_camera()
		elif event.button_mask & MOUSE_BUTTON_MASK_MIDDLE:
			_pan(event.relative)
		_update_ghost()
	elif event is InputEventMouseButton and event.pressed:
		match event.button_index:
			MOUSE_BUTTON_LEFT:
				_on_click()
			MOUSE_BUTTON_WHEEL_UP:
				cam_goal_dist = maxf(6.0, cam_goal_dist * 0.88)
			MOUSE_BUTTON_WHEEL_DOWN:
				cam_goal_dist = minf(150.0, cam_goal_dist / 0.88)
	elif event is InputEventKey and event.pressed and not event.echo:
		_on_key(event.keycode)


func _on_key(key: Key) -> void:
	if Input.is_key_pressed(KEY_CTRL):
		match key:
			KEY_Z:
				if Input.is_key_pressed(KEY_SHIFT):
					_redo()
				else:
					_undo()
			KEY_Y:
				_redo()
		return
	match key:
		KEY_R:
			_rotate()
		KEY_Q:
			_set_level(level - 1)
		KEY_E:
			_set_level(level + 1)
		KEY_S:
			_save()
		KEY_L:
			_load()
		KEY_C:
			_clear()
		KEY_F:
			_frame_ship()
		KEY_H:
			hide_decks_above = not hide_decks_above
			ship_view.set_deck_filter(level, hide_decks_above)
			message = "Upper decks hidden" if hide_decks_above else "Showing all decks"
			_refresh_info()
		KEY_M:
			muted = not muted
			message = "Sound off" if muted else "Sound on"
			_refresh_info()
		KEY_F1:
			welcome_panel.visible = not welcome_panel.visible
		KEY_BRACKETRIGHT:
			_select((selected + 1) % library.order.size())
		KEY_BRACKETLEFT:
			_select((selected - 1 + library.order.size()) % library.order.size())
		_:
			var i := -1
			if key >= KEY_1 and key <= KEY_9:
				i = int(key) - int(KEY_1)
			elif key == KEY_0:
				i = 9
			if i >= 0 and i < library.order.size():
				_select(i)


func _process(delta: float) -> void:
	var v := Vector2.ZERO
	if not busy:
		if Input.is_key_pressed(KEY_LEFT):
			v.x -= 1.0
		if Input.is_key_pressed(KEY_RIGHT):
			v.x += 1.0
		if Input.is_key_pressed(KEY_UP):
			v.y -= 1.0
		if Input.is_key_pressed(KEY_DOWN):
			v.y += 1.0
	if v != Vector2.ZERO:
		_pan(-v * 500.0 * delta)
	# Ease the camera toward where it wants to be.
	var k := 1.0 - exp(-10.0 * delta)
	if cam_target.distance_to(cam_goal_target) > 0.002 or absf(cam_dist - cam_goal_dist) > 0.002:
		cam_target = cam_target.lerp(cam_goal_target, k)
		cam_dist = lerpf(cam_dist, cam_goal_dist, k)
		_update_camera()
		_update_ghost()


# --- Camera ----------------------------------------------------------------------------------

func _update_camera() -> void:
	var offset := Vector3(0, 0, cam_dist)
	offset = offset.rotated(Vector3.RIGHT, -cam_pitch).rotated(Vector3.UP, cam_yaw)
	# Look slightly below the target so the ship sits in the clear middle.
	var view := -offset.normalized()
	var up := (Vector3.UP - view * view.dot(Vector3.UP)).normalized()
	var focus := cam_target - up * cam_dist * 0.04
	camera.position = focus + offset
	camera.look_at(focus, Vector3.UP)


func _pan(rel: Vector2) -> void:
	var basis := camera.global_transform.basis
	var right := Vector3(basis.x.x, 0, basis.x.z).normalized()
	var fwd := Vector3(-basis.z.x, 0, -basis.z.z).normalized()
	cam_goal_target += (-right * rel.x + fwd * rel.y) * cam_dist * 0.0015


## Swing the camera to look at the whole ship.
func _frame_ship(immediate := false) -> void:
	if ship.modules.is_empty():
		cam_goal_target = Vector3(0, level * ShipGrid.CELL, 0)
		cam_goal_dist = 24.0
	else:
		var lo := Vector3(INF, INF, INF)
		var hi := Vector3(-INF, -INF, -INF)
		for c in ship.occupied:
			var p := ShipGrid.cell_to_world(c)
			lo = Vector3(minf(lo.x, p.x), minf(lo.y, p.y), minf(lo.z, p.z))
			hi = Vector3(maxf(hi.x, p.x), maxf(hi.y, p.y), maxf(hi.z, p.z))
		cam_goal_target = (lo + hi) * 0.5
		cam_goal_dist = clampf((hi - lo).length() * 0.5 * 2.3 + 8.0, 14.0, 120.0)
	if immediate:
		cam_target = cam_goal_target
		cam_dist = cam_goal_dist
		_update_camera()


# --- Selection, ghost, placement -----------------------------------------------------------

func _select(i: int) -> void:
	selected = i
	if ghost != null:
		remove_child(ghost)
		ghost.queue_free()

	ghost_mat = StandardMaterial3D.new()
	ghost_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ghost_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ghost_mat.albedo_color = GOOD

	ghost = library.get_def(library.order[i]).build_visual()
	_override_materials(ghost, ghost_mat)
	add_child(ghost)

	_style_buttons()
	_update_ghost()
	_refresh_info()
	if is_node_ready() and not sfx_players.is_empty():
		_sfx(&"select")


func _style_buttons() -> void:
	for j in buttons.size():
		if j == selected:
			buttons[j].modulate = Color(1.0, 0.95, 0.5)
		else:
			buttons[j].modulate = Color.WHITE


func _override_materials(node: Node, mat: Material) -> void:
	if node is MeshInstance3D:
		if node.has_meta("flame"):
			node.visible = false
		node.material_override = mat
	for child in node.get_children():
		_override_materials(child, mat)


func _rotate() -> void:
	rot = (rot + 1) % 4
	_update_ghost()
	_refresh_info()


func _set_level(l: int) -> void:
	level = clampi(l, -6, 6)
	grid.position.y = level * ShipGrid.CELL - ShipGrid.CELL * 0.5  # sits on this deck's floor
	cam_goal_target.y = level * ShipGrid.CELL
	ship_view.set_deck_filter(level, hide_decks_above)
	_update_ghost()
	_refresh_info()


## Which grid cell is under the mouse, found by casting a ray onto the current deck's floor plane.
func _mouse_cell() -> Variant:
	var mp := get_viewport().get_mouse_position()
	var from := camera.project_ray_origin(mp)
	var dir := camera.project_ray_normal(mp)
	var floor_y := level * ShipGrid.CELL - ShipGrid.CELL * 0.5
	var hit: Variant = Plane(Vector3.UP, floor_y).intersects_ray(from, dir)
	if hit == null:
		return null
	var c := ShipGrid.world_to_cell(hit)
	c.y = level
	return c


## The rotation to use at `cell`: the one the player chose if it fits, otherwise the first turn that does.
func _fit_rotation(id: StringName, cell: Vector3i) -> int:
	if ship.check_place(id, cell, rot) == "":
		return rot
	for k in range(1, 4):
		var r := (rot + k) % 4
		if ship.check_place(id, cell, r) == "":
			return r
	return rot


func _update_ghost() -> void:
	if ghost == null:
		return
	var cell: Variant = _mouse_cell()
	if busy or cell == null or get_viewport().gui_get_hovered_control() != null:
		hover_active = false
		ghost.visible = false
		tip_panel.visible = false
		return
	var def := library.get_def(library.order[selected])
	var removing := Input.is_key_pressed(KEY_SHIFT)
	hover_active = true
	hover_cell = cell
	hover_rot = _fit_rotation(def.id, cell)
	hover_error = ship.check_place(def.id, cell, hover_rot)
	var note := ""
	if hover_error == "":
		if hover_rot != rot:
			note = "  (turned to fit)"
	ghost_mat.albedo_color = GOOD if hover_error == "" else BAD
	ghost.position = ShipGrid.cell_to_world(hover_cell)
	ghost.rotation.y = hover_rot * PI / 2.0
	ghost.visible = not removing  # hide while removing

	if removing:
		if ship.occupied.has(cell):
			var m: Dictionary = ship.modules[ship.occupied[cell]]
			var gone := library.get_def(m.id)
			_show_tip("Remove %s" % gone.display_name, WARN_COLOR)
		else:
			tip_panel.visible = false
	elif hover_error != "":
		_show_tip(hover_error, BAD_COLOR)
	else:
		_show_tip("%s%s" % [def.display_name, note], OK_COLOR)


func _show_tip(text: String, col: Color) -> void:
	tip_label.text = text
	tip_label.modulate = col
	tip_panel.visible = true
	var mp := get_viewport().get_mouse_position() + Vector2(18, 20)
	var vp := get_viewport().get_visible_rect().size
	tip_panel.position = Vector2(minf(mp.x, vp.x - tip_panel.size.x - 8.0), minf(mp.y, vp.y - tip_panel.size.y - 8.0))


func _on_click() -> void:
	if busy or not hover_active:
		return
	var before := _snapshot()
	if Input.is_key_pressed(KEY_SHIFT):
		var err := manifest.blocks_removal(hover_cell)
		if err == "":
			err = ship.remove_at(hover_cell)
		message = err
		_sfx(&"remove" if err == "" else &"error")
	else:
		var err := hover_error
		if err == "":
			err = ship.add(library.order[selected], hover_cell, hover_rot)
		message = err
		if err == "":
			pop_index = ship.modules.size() - 1
			_sfx(&"place")
		else:
			_sfx(&"error")
	_commit(before)
	_refresh_ship()


# --- Money -----------------------------------------------------------------------------------

func _ship_cost() -> int:
	var total := 0
	for m in ship.modules:
		total += library.get_def(m.id).cost
	return total


# --- Undo / redo -----------------------------------------------------------------------------

func _snapshot() -> Dictionary:
	return {"ship": ship.to_json(), "cargo": manifest.to_dict()}


func _restore(snap: Dictionary) -> void:
	ship.from_json(snap.ship)
	manifest.from_dict(snap.cargo)


## Record `before` for undo if anything actually changed since.
func _commit(before: Dictionary) -> void:
	if JSON.stringify(before) != JSON.stringify(_snapshot()):
		history.record(before)


func _undo() -> void:
	if busy or not history.can_undo():
		return
	_restore(history.undo(_snapshot()))
	message = "Undid last change"
	_sfx(&"remove")
	_refresh_ship()


func _redo() -> void:
	if busy or not history.can_redo():
		return
	_restore(history.redo(_snapshot()))
	message = "Redid change"
	_sfx(&"place")
	_refresh_ship()


# --- Refreshing everything ---------------------------------------------------------------------

## Call after any change to the ship, cargo or money.
func _refresh_ship() -> void:
	manifest.prune()
	ship_view.rebuild(ship, manifest, pop_index)
	pop_index = -1
	var st := ShipStats.compute(ship, 1.0, manifest)
	last_stats = st
	com_marker.visible = not ship.modules.is_empty() and not busy
	com_marker.position = st.com
	stats_label.text = ShipStats.format(st)
	warn_label.text = "\n".join(PackedStringArray(st.warnings))

	var p_ratio: float = st.power_use / st.power_gen if st.power_gen > 0.0 else (2.0 if st.power_use > 0.0 else 0.0)
	_set_meter(meters.power, p_ratio, "%.0f / %.0f kW" % [st.power_use, st.power_gen])
	var h_ratio: float = st.heat_gen / st.cooling if st.cooling > 0.0 else (2.0 if st.heat_gen > 0.0 else 0.0)
	_set_meter(meters.heat, h_ratio, "%.0f / %.0f kW" % [st.heat_gen, st.cooling])
	var c_ratio: float = st.cargo_mass / st.cargo_capacity if st.cargo_capacity > 0.0 else 0.0
	_set_meter(meters.cargo, c_ratio, "%.1f / %.0f t" % [st.cargo_mass, st.cargo_capacity], false)

	_refresh_cargo_label()
	_refresh_top()
	_style_buttons()
	undo_button.disabled = not history.can_undo()
	redo_button.disabled = not history.can_redo()
	_update_ghost()
	_refresh_info()
	if autosave_enabled and not busy:
		_write_save(AUTOSAVE_PATH)


func _refresh_top() -> void:
	top_label.text = "Parts  %d     Ship value  %s cr" % [ship.modules.size(), ShipStats.commas(_ship_cost())]
	top_label.modulate = Color.WHITE


func _refresh_info() -> void:
	info_label.text = "Deck %d   Rotation %d°\n%s" % [level, rot * 90, message]


## One line per cargo module showing each container: commodity and tonnes, or empty.
func _refresh_cargo_label() -> void:
	var lines := PackedStringArray()
	var by_module := {}
	for s in manifest.slots():
		if not by_module.has(s.module):
			by_module[s.module] = []
		var cell := "[empty]"
		if manifest.contents.has(s.key):
			var e: Dictionary = manifest.contents[s.key]
			cell = "[%s %.1f/%.0f]" % [manifest.commodities.label(e.commodity), e.tonnes, s.capacity]
		by_module[s.module].append(cell)
	for mi in by_module:
		var m: Dictionary = ship.modules[mi]
		lines.append("%s (%d,%d,%d)" % [library.get_def(m.id).display_name, m.cell.x, m.cell.y, m.cell.z])
		lines.append("  " + " ".join(PackedStringArray(by_module[mi])))
	if lines.is_empty():
		lines.append("No cargo modules yet")
	cargo_label.text = "\n".join(lines)


# --- Cargo ---------------------------------------------------------------------------------------

func _load_cargo() -> void:
	var c: StringName = manifest.commodities.order[commodity_pick.selected]
	var offered := amount_box.value
	var before := _snapshot()
	var loaded := manifest.load(c, offered)
	var goods := manifest.commodities.label(c)
	if is_zero_approx(offered):
		message = "Nothing on offer"
	elif manifest.capacity() <= 0.0:
		message = "No cargo space on this ship"
	elif loaded < offered - 0.001:
		message = "Loaded %.1f t of %s; no room for the other %.1f t" % [loaded, goods, offered - loaded]
	else:
		message = "Loaded %.1f t of %s; %.1f t of space still free" % [loaded, goods, manifest.free_space_for(c)]
	_sfx(&"place" if loaded > 0.0 else &"error")
	_commit(before)
	_refresh_ship()


func _unload_cargo() -> void:
	var c: StringName = manifest.commodities.order[commodity_pick.selected]
	var asked := amount_box.value
	var before := _snapshot()
	var removed := manifest.unload(c, asked)
	if removed < asked - 0.001:
		message = "Removed %.1f t of %s (that was all there was)" % [removed, manifest.commodities.label(c)]
	else:
		message = "Removed %.1f t of %s" % [removed, manifest.commodities.label(c)]
	_sfx(&"remove" if removed > 0.0 else &"error")
	_commit(before)
	_refresh_ship()


func _unload_all() -> void:
	var before := _snapshot()
	var gone := manifest.unload_all()
	var total := 0.0
	for c in gone:
		total += gone[c]
	message = "Unloaded %.1f t" % total
	_sfx(&"remove")
	_commit(before)
	_refresh_ship()


# --- Save / load / clear -------------------------------------------------------------------

func _save_dict() -> Dictionary:
	var data: Dictionary = JSON.parse_string(ship.to_json())
	data["cargo"] = manifest.to_dict()
	return data


func _write_save(path: String) -> bool:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(_save_dict(), "\t"))
	f.close()
	return true


## Replaces the ship, cargo and progress from a save file. Returns false and changes nothing if it can't.
func _load_from(path: String) -> bool:
	var text := FileAccess.get_file_as_string(path)
	if not ship.from_json(text):
		return false
	var parsed: Variant = JSON.parse_string(text)
	manifest.from_dict(parsed.get("cargo", {}))
	return true


func _save() -> void:
	if _write_save(SAVE_PATH):
		message = "Saved to " + ProjectSettings.globalize_path(SAVE_PATH)
	else:
		message = "Could not save (error %d)" % FileAccess.get_open_error()
	_refresh_info()


func _load() -> void:
	if busy:
		return
	if not FileAccess.file_exists(SAVE_PATH):
		message = "No saved ship yet (press S first)"
	else:
		var before := _snapshot()
		if _load_from(SAVE_PATH):
			message = "Loaded"
			_commit(before)
			_frame_ship()
		else:
			message = "Save file couldn't be loaded"
	_refresh_ship()


func _clear() -> void:
	if busy:
		return
	var before := _snapshot()
	ship.clear()
	manifest.contents.clear()
	message = "Cleared"
	_sfx(&"remove")
	_commit(before)
	_refresh_ship()


func _load_starter() -> void:
	if busy:
		return
	var before := _snapshot()
	manifest.contents.clear()
	var err := ShipPresets.build(ship)
	message = "Started from the starter ship" if err == "" else err
	_sfx(&"place")
	_commit(before)
	_refresh_ship()
	_frame_ship()
