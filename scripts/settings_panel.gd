class_name SettingsPanel
extends PanelContainer
## The settings screen: graphics quality, display, audio and mouse. Changes apply at once and are saved
## (GameSettings, settings.cfg beside the saves).

signal back

var _quality: OptionButton


func _init() -> void:
	add_theme_stylebox_override("panel", Brand.panel_box())
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	add_child(col)
	col.add_child(Brand.heading("SETTINGS", 18))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 28)
	grid.add_theme_constant_override("v_separation", 10)
	col.add_child(grid)

	_quality = OptionButton.new()
	for q in ["Low", "Medium", "High"]:
		_quality.add_item(q)
	_quality.selected = GameSettings.QUALITIES.find(GameSettings.quality())
	_quality.item_selected.connect(func(i: int) -> void:
		GameSettings.set_value("quality", GameSettings.QUALITIES[i])
		if is_inside_tree() and get_tree().current_scene != null:
			GameSettings.apply_scene(get_tree().current_scene))
	_row(grid, "Graphics quality", _quality)
	_row(grid, "Fullscreen", _check("fullscreen"))
	_row(grid, "Vertical sync", _check("vsync"))
	_row(grid, "Interface size", _slider("ui_scale", 0.75, 1.5, 0.05))
	_row(grid, "Master volume", _slider("master", 0.0, 1.0, 0.05))
	_row(grid, "Music volume", _slider("music", 0.0, 1.0, 0.05))
	_row(grid, "Effects volume", _slider("effects", 0.0, 1.0, 0.05))
	_row(grid, "Mouse sensitivity", _slider("mouse", 0.2, 3.0, 0.1))
	var keys := Brand.note("Keys: WASD and arrows, shown on screen in each mode. Rebinding is not built yet.", 13)
	keys.custom_minimum_size = Vector2(460, 0)
	keys.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(keys)
	var q_note := Brand.note("Low: no shadows. Medium: sun shadows, 2x anti-aliasing. High: sharper shadows, ambient occlusion, 4x anti-aliasing.", 12)
	q_note.custom_minimum_size = Vector2(460, 0)
	q_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(q_note)
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 6)
	col.add_child(spacer)
	var b := Button.new()
	b.text = "BACK"
	Brand.style_button(b, 18)
	b.pressed.connect(func() -> void: back.emit())
	b.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	b.custom_minimum_size = Vector2(160, 0)
	col.add_child(b)


func _row(grid: GridContainer, label: String, control: Control) -> void:
	var l := Label.new()
	l.text = label
	l.custom_minimum_size = Vector2(190, 0)
	l.add_theme_color_override("font_color", Brand.OFFWHITE)
	grid.add_child(l)
	grid.add_child(control)


func _check(key: String) -> CheckBox:
	var cb := CheckBox.new()
	cb.button_pressed = bool(GameSettings.get_value(key))
	cb.toggled.connect(func(on: bool) -> void: GameSettings.set_value(key, on))
	return cb


func _slider(key: String, lo: float, hi: float, step: float) -> HSlider:
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.value = float(GameSettings.get_value(key))
	s.custom_minimum_size = Vector2(240, 22)
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	s.value_changed.connect(func(v: float) -> void: GameSettings.set_value(key, v))
	return s
