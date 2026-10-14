class_name GameMenu
extends CanvasLayer
## The in-game menu, in every scene but the title: Esc (or F10) anywhere. It pauses the game and offers
## Resume, whatever the scene adds (menu_actions(): in flight, the tug or turning back), Save game,
## Settings, Main menu and Quit. A scene that needs Esc for itself for a moment (a desk open in a port)
## says so with wants_escape(). F3 toggles a frame-rate readout.
## GameSettings.apply_scene adds one to each scene (attach()).

const KEY := KEY_F10
const PERF_KEY := KEY_F3

static var show_perf := false   ## the F3 readout stays on across scenes until turned off

var panel: PanelContainer
var list: VBoxContainer
var note: Label
var settings: SettingsPanel
var perf: Label
var dim: ColorRect
var _mouse_before := Input.MOUSE_MODE_VISIBLE
var _perf_t := 0.0
var in_flight := false
var extra: VBoxContainer   ## the scene's own actions (menu_actions()), rebuilt each time the menu opens


## Add the menu to `scene` once (not on the title screen).
static func attach(scene: Node) -> GameMenu:
	if scene == null or scene.get_node_or_null("GameMenu") != null:
		return null
	if scene.scene_file_path == Session.BOOT_SCENE or scene.scene_file_path == "":
		return null
	var m := GameMenu.new()
	m.name = "GameMenu"
	m.in_flight = scene.scene_file_path == Session.FLIGHT_SCENE
	scene.add_child(m)
	return m


func _ready() -> void:
	layer = 50
	process_mode = Node.PROCESS_MODE_ALWAYS
	dim = ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.visible = false
	add_child(dim)
	panel = PanelContainer.new()
	var box := Brand.panel_box().duplicate() as StyleBoxFlat
	box.bg_color.a = 1.0
	panel.add_theme_stylebox_override("panel", box)
	panel.visible = false
	add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_MINSIZE)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	list = VBoxContainer.new()
	list.add_theme_constant_override("separation", 8)
	list.custom_minimum_size = Vector2(320, 0)
	panel.add_child(list)
	list.add_child(Brand.heading("PAUSED", 20))
	_button("RESUME", close)
	_button("TRADE REPORT  (N)", func() -> void:
		close()
		var r := TradeReport.find(get_tree())
		if r != null:
			r.open())
	extra = VBoxContainer.new()
	extra.add_theme_constant_override("separation", 8)
	list.add_child(extra)
	_button("SAVE GAME", _save)
	_button("SETTINGS", _settings)
	_button("MAIN MENU", _main_menu)
	_button("QUIT TO DESKTOP", func() -> void: get_tree().quit())
	note = Brand.note("", 13)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.custom_minimum_size = Vector2(320, 0)
	list.add_child(note)
	settings = SettingsPanel.new()
	settings.visible = false
	settings.back.connect(func() -> void:
		settings.visible = false
		panel.visible = true)
	add_child(settings)
	settings.set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_MINSIZE)
	settings.grow_horizontal = Control.GROW_DIRECTION_BOTH
	settings.grow_vertical = Control.GROW_DIRECTION_BOTH
	perf = Label.new()
	perf.add_theme_font_size_override("font_size", 14)
	perf.add_theme_color_override("font_color", Color(0.6, 1.0, 0.7))
	perf.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	perf.add_theme_constant_override("outline_size", 4)
	perf.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE, 12)
	perf.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	perf.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	perf.visible = show_perf
	add_child(perf)


func _button(text: String, cb: Callable) -> void:
	var b := Button.new()
	b.text = text
	Brand.style_button(b, 18)
	b.pressed.connect(cb)
	list.add_child(b)


func is_open() -> bool:
	return panel.visible or settings.visible


func open() -> void:
	if is_open():
		return
	_mouse_before = Input.mouse_mode
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	note.text = "A save keeps the game as you left port; this flight is not saved. Officially, it never happened." if in_flight else ""
	if ShipRemote.instance != null:   # where the phone goes, in case it wandered off
		note.text = (note.text + "\n\n" if note.text != "" else "") + "Ship remote: " + ShipRemote.where()
	for c in extra.get_children():
		c.queue_free()
	var scene := get_parent()
	if scene != null and scene.has_method("menu_actions"):
		for a in scene.menu_actions():
			var act: Dictionary = a
			var b := Button.new()
			b.text = String(act.text)
			Brand.style_button(b, 18)
			var cb: Callable = act.call
			b.pressed.connect(func() -> void:
				close()
				cb.call())
			extra.add_child(b)
	if bool(GameSettings.get_value("cheats")) and Session.slot >= 0:   # debug: Settings > Debug cheats
		extra.add_child(Brand.heading("CHEATS", 15))
		for c in Cheats.actions(scene):
			var act: Dictionary = c
			var b := Button.new()
			b.text = String(act.text)
			Brand.style_button(b, 15)
			var kind: String = act.kind
			b.pressed.connect(func() -> void:
				var msg := Cheats.run(scene, kind)
				note.text = msg)
			extra.add_child(b)
		if bool(Session.profile.get("cheated", false)):
			note.text = (note.text + "\n\n" if note.text != "" else "") + "Cheats have been used on this save."
	dim.visible = true
	panel.visible = true
	get_tree().paused = true


func close() -> void:
	panel.visible = false
	settings.visible = false
	dim.visible = false
	get_tree().paused = false
	Input.mouse_mode = _mouse_before


func _save() -> void:
	note.text = ("Saved to slot %d." % (Session.slot + 1)) if Session.save_profile() else "Not part of a saved game, so nothing was saved."


func _settings() -> void:
	panel.visible = false
	settings.visible = true


func _main_menu() -> void:
	get_tree().paused = false
	Session.skip_intro = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().change_scene_to_file(Session.BOOT_SCENE)


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	if event.keycode == PERF_KEY:
		show_perf = not show_perf
		perf.visible = show_perf
		get_viewport().set_input_as_handled()
	elif event.keycode == KEY:
		if is_open():
			close()
		else:
			open()
		get_viewport().set_input_as_handled()
	elif event.keycode == KEY_ESCAPE:
		if is_open():
			close()
		else:
			var scene := get_parent()
			if scene != null and scene.has_method("wants_escape") and scene.wants_escape():
				return   # the scene closes its own panel first
			open()
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if not perf.visible:
		return
	_perf_t -= delta
	if _perf_t > 0.0:
		return
	_perf_t = 0.25
	perf.text = "%d FPS   %.1f ms\n%d draw calls   %d objects\n%.0f MB video" % [
		Engine.get_frames_per_second(), Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
		Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),
		Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0]
