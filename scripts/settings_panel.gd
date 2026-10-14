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
	var remote := _check("remote")
	remote.toggled.connect(func(_on: bool) -> void:
		ShipRemote.sync(get_tree())
		_remote_note())
	_row(grid, "Ship remote (phone or tablet)", remote)
	_row(grid, "Debug cheats (pause menu)", _check("cheats"))
	_remote_info = Brand.note("", 13)
	_remote_info.custom_minimum_size = Vector2(460, 0)
	_remote_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_remote_info)
	_new_code = Button.new()
	_new_code.text = "NEW CODE"
	Brand.style_button(_new_code, 14)
	_new_code.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_new_code.pressed.connect(func() -> void:
		ShipRemote.new_code()
		_remote_note())
	col.add_child(_new_code)
	_remote_note()
	var keys := Brand.note("Keys: WASD and arrows, shown on screen in each mode. Rebinding isn't built yet. The developer has a list.", 13)
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


var _remote_info: Label
var _new_code: Button


## Where to point the phone, and the code, while the remote is on.
func _remote_note() -> void:
	var on := bool(GameSettings.get_value("remote"))
	_new_code.visible = on
	if not on:
		_remote_info.text = "The ship remote turns a phone or tablet on your network into a second cockpit screen: gauges, the map and the controls. Off until you want it."
		return
	var trouble := ShipRemote.instance.status if ShipRemote.instance != null else ""
	_remote_info.text = trouble if trouble != "" else \
			"On the phone, open %s and enter the code. Same Wi-Fi only. Windows may ask to let Far Haul through the firewall: allow it on private networks. NEW CODE unpairs every device." % ShipRemote.where()


func _row(grid: GridContainer, label: String, control: Control) -> void:
	var l := Label.new()
	l.text = label
	l.custom_minimum_size = Vector2(190, 0)
	l.add_theme_color_override("font_color", Brand.OFFWHITE)
	grid.add_child(l)
	grid.add_child(control)


## An on/off switch for a setting: a plain button that says ON or OFF, because the stock checkbox
## all but vanished against the panel and an option nobody can see is an option nobody uses.
func _check(key: String) -> Button:
	var b := Button.new()
	b.toggle_mode = true
	b.focus_mode = Control.FOCUS_ALL
	b.custom_minimum_size = Vector2(96, 34)
	b.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	b.add_theme_font_size_override("font_size", 15)
	var off := _switch_box(Brand.STEEL_LIGHT, Brand.MUTED)
	var on := _switch_box(Brand.AMBER, Brand.AMBER)
	b.add_theme_stylebox_override("normal", off)
	b.add_theme_stylebox_override("hover", _switch_box(Brand.STEEL_LIGHT, Brand.AMBER))
	b.add_theme_stylebox_override("focus", _switch_box(Color(0, 0, 0, 0), Brand.AMBER))
	b.add_theme_stylebox_override("pressed", on)
	b.add_theme_stylebox_override("hover_pressed", on)
	b.add_theme_color_override("font_color", Brand.OFFWHITE)
	b.add_theme_color_override("font_hover_color", Brand.OFFWHITE)
	b.add_theme_color_override("font_focus_color", Brand.OFFWHITE)
	b.add_theme_color_override("font_pressed_color", Brand.STEEL_DARK)
	b.add_theme_color_override("font_hover_pressed_color", Brand.STEEL_DARK)
	b.toggled.connect(func(pressed: bool) -> void:
		b.text = "ON" if pressed else "OFF"
		GameSettings.set_value(key, pressed))
	b.button_pressed = bool(GameSettings.get_value(key))
	b.text = "ON" if b.button_pressed else "OFF"
	return b


static func _switch_box(fill: Color, edge: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = fill
	sb.border_color = edge
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(4)
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 4
	sb.content_margin_bottom = 4
	return sb


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
