class_name SettingsPanel
extends PanelContainer
## Placeholder settings. Nothing here is wired up yet; each row says so.

signal back

const ROWS := [
	["Master volume", "slider"],
	["Music volume", "slider"],
	["Effects volume", "slider"],
	["Fullscreen", "check"],
	["Mouse sensitivity", "slider"],
	["Interface size", "slider"],
	["Graphics quality", "choice"],
	["Key bindings", "button"],
]


func _init() -> void:
	add_theme_stylebox_override("panel", Brand.panel_box())
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	add_child(col)
	col.add_child(Brand.heading("SETTINGS", 18))
	col.add_child(Brand.note("These are placeholders. None of them do anything yet."))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 28)
	grid.add_theme_constant_override("v_separation", 10)
	col.add_child(grid)
	for r in ROWS:
		var l := Label.new()
		l.text = r[0]
		l.custom_minimum_size = Vector2(190, 0)
		l.add_theme_color_override("font_color", Brand.OFFWHITE)
		grid.add_child(l)
		grid.add_child(_control(r[1]))
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 10)
	col.add_child(spacer)
	var b := Button.new()
	b.text = "BACK"
	Brand.style_button(b, 18)
	b.pressed.connect(func() -> void: back.emit())
	b.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	b.custom_minimum_size = Vector2(160, 0)
	col.add_child(b)


func _control(kind: String) -> Control:
	var c: Control
	match kind:
		"slider":
			var s := HSlider.new()
			s.value = 70
			s.custom_minimum_size = Vector2(240, 22)
			s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			s.editable = false
			c = s
		"check":
			var cb := CheckBox.new()
			cb.disabled = true
			c = cb
		"choice":
			var o := OptionButton.new()
			o.add_item("Auto")
			o.disabled = true
			c = o
		_:
			var b := Button.new()
			b.text = "Change"
			b.disabled = true
			c = b
	c.focus_mode = Control.FOCUS_NONE
	return c
