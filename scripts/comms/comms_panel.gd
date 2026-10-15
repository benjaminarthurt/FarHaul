class_name CommsPanel
extends CanvasLayer
## The radio, on screen (Comms): Y anywhere aboard opens the list of who's in range and what you can say
## to each (click, or the number keys); Y or Esc closes it. Whatever is being said shows as a subtitle at
## the bottom of the screen whether the panel is open or not, typing out as it's spoken.

const KEY := KEY_Y

var comms: Comms
var panel: PanelContainer
var list: VBoxContainer
var log_label: Label
var sub_panel: PanelContainer
var sub_label: Label
var _sig := ""
var _buttons: Array[Button] = []
var _mouse_before := Input.MOUSE_MODE_VISIBLE
var _refresh := 0.0


func _init(c: Comms) -> void:
	comms = c
	layer = 6
	name = "CommsPanel"


func _ready() -> void:
	panel = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.04, 0.06, 0.08, 0.93)
	sb.border_color = Brand.AMBER
	sb.set_border_width_all(2)
	sb.set_content_margin_all(14)
	panel.add_theme_stylebox_override("panel", sb)
	panel.anchor_left = 1.0
	panel.anchor_right = 1.0
	panel.offset_left = -500
	panel.offset_right = -16
	panel.offset_top = 16
	panel.anchor_bottom = 1.0
	panel.offset_bottom = -170
	panel.visible = false
	add_child(panel)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 6)
	scroll.add_child(box)
	box.add_child(Brand.heading("COMMS", 18))
	box.add_child(Brand.note("Who's in range. Click, or press the number. Y or Esc closes.", 13))
	list = VBoxContainer.new()
	list.add_theme_constant_override("separation", 4)
	box.add_child(list)
	box.add_child(Brand.heading("LOG", 14))
	log_label = Label.new()
	log_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	log_label.custom_minimum_size = Vector2(440, 0)
	log_label.add_theme_font_size_override("font_size", 13)
	log_label.modulate = Color(0.8, 0.85, 0.9)
	box.add_child(log_label)
	# The subtitle: whoever's talking, at the bottom of the screen.
	sub_panel = PanelContainer.new()
	var ss := StyleBoxFlat.new()
	ss.bg_color = Color(0.0, 0.0, 0.0, 0.62)
	ss.set_content_margin_all(10)
	ss.set_corner_radius_all(4)
	sub_panel.add_theme_stylebox_override("panel", ss)
	sub_panel.anchor_left = 0.5
	sub_panel.anchor_right = 0.5
	sub_panel.anchor_top = 1.0
	sub_panel.anchor_bottom = 1.0
	sub_panel.offset_left = -430
	sub_panel.offset_right = 430
	sub_panel.offset_top = -205
	sub_panel.offset_bottom = -128
	sub_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sub_panel.visible = false
	add_child(sub_panel)
	sub_label = Label.new()
	sub_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sub_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	sub_label.add_theme_font_size_override("font_size", 18)
	sub_panel.add_child(sub_label)


func is_open() -> bool:
	return panel.visible


func open() -> void:
	if panel.visible:
		return
	_mouse_before = Input.mouse_mode
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	panel.visible = true
	_sig = ""
	_rebuild()


func close() -> void:
	if not panel.visible:
		return
	panel.visible = false
	Input.mouse_mode = _mouse_before


func toggle() -> void:
	if panel.visible:
		close()
	else:
		open()


func _input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var menu := get_tree().current_scene.get_node_or_null("GameMenu") if get_tree().current_scene != null else null
	if menu != null and menu.has_method("is_open") and menu.is_open():
		return
	if event.keycode == KEY:
		var map := get_tree().current_scene.get_node_or_null("StarMap") if get_tree().current_scene != null else null
		if map != null and map.visible:
			return
		toggle()
		get_viewport().set_input_as_handled()
		return
	if not panel.visible:
		return
	if event.keycode == KEY_ESCAPE:
		close()
		get_viewport().set_input_as_handled()
		return
	if event.keycode >= KEY_1 and event.keycode <= KEY_9:
		var i: int = event.keycode - KEY_1
		var live := _buttons.filter(func(b: Button) -> bool: return not b.disabled)
		if i < live.size():
			live[i].emit_signal("pressed")
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	var said := comms.shown()
	var who := String(comms.current.get("who", ""))
	sub_panel.visible = said != ""
	if said != "":
		sub_label.text = "%s:  %s" % [who, said] if who != "" else said
		sub_label.add_theme_color_override("font_color", Brand.AMBER if who == "YOU" else (Color(1.0, 0.45, 0.4) if who.begins_with("DISTRESS") else Color(0.75, 0.95, 1.0)))
	if not panel.visible:
		return
	_refresh -= delta
	if _refresh <= 0.0:
		_refresh = 0.3
		_rebuild()


func _rebuild() -> void:
	var cs := comms.contacts()
	var sig := ""
	for c in cs:
		sig += "%s|%d|" % [String(c.id), roundi(float(c.dist_m) / 100.0)]
		for o in c.options:
			sig += "%s%s%s;" % [String(o.id), String(o.text), str(o.enabled)]
	var lines := PackedStringArray()
	for l in comms.log.slice(maxi(0, comms.log.size() - 8)):
		lines.append("%s: %s" % [String(l.who), String(l.text)])
	log_label.text = "\n".join(lines) if not lines.is_empty() else "Nothing said yet."
	if sig == _sig:
		return
	_sig = sig
	for ch in list.get_children():
		ch.queue_free()
	_buttons.clear()
	if cs.is_empty():
		list.add_child(Brand.note("Nobody in range. Space is big; radios aren't.", 14))
	var n := 0
	for c in cs:
		var d := float(c.dist_m)
		var where := "" if d < 0.0 else ("  ·  %d m" % roundi(d) if d < 2000.0 else "  ·  %.1f km" % (d / 1000.0))
		var head := Label.new()
		head.text = String(c.name).to_upper() + where
		head.add_theme_font_size_override("font_size", 14)
		head.modulate = Color(1.0, 0.5, 0.45) if String(c.kind) == "distress" else Color(0.75, 0.9, 1.0)
		list.add_child(head)
		for o in c.options:
			var b := Button.new()
			var enabled := bool(o.enabled)
			if enabled:
				n += 1
			b.text = ("%d  %s" % [n, String(o.text)]) if enabled and n <= 9 else ("    " + String(o.text) + ("  (%s)" % String(o.why) if not enabled and String(o.why) != "" else ""))
			b.alignment = HORIZONTAL_ALIGNMENT_LEFT
			b.disabled = not enabled
			b.focus_mode = Control.FOCUS_NONE
			b.add_theme_font_size_override("font_size", 14)
			var cid := String(c.id)
			var oid := String(o.id)
			b.pressed.connect(func() -> void:
				var r := comms.act(cid, oid)
				if not bool(r.ok):
					comms.sc.say(String(r.message), 3.0)
				_sig = ""
				_rebuild())
			list.add_child(b)
			_buttons.append(b)
