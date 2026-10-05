class_name PlaceScene
extends Node3D
## Walking the place your ship is berthed at, in first person. Ports, fuel depots, belt works and a moon
## base's orbital station have a concourse; a moon base's pad has the base's hab; a mining camp has the
## foreman's hut. Desks along the walls do what the station terminal's buttons do (that menu is still
## there, at the terminal kiosk or with T). The gate leads back aboard your ship.

const HELP := "WASD walk   mouse or arrows look   Shift run   E use a desk   T station terminal   Esc menu"
const MOUSE_TURN := 0.0025
const KEY_TURN := 1.8
const REACH := 2.4

var walker: ShipWalk
var camera: Camera3D
var desks: Array[Dictionary] = []   ## {id, label, pos: where you stand to use it}
var kind := "concourse"              ## concourse, hab or hut
var site: Dictionary = {}
var info: Label
var prompt: Label
var crosshair: Label
var panel: PanelContainer
var panel_list: VBoxContainer
var panel_status: Label
var open_desk := ""
var leaving := false
var fade: ColorRect
var _mats := {}
var style: Dictionary = {}   ## SystemStyle for this site: size, colours, crowd, props
var hud_layer: CanvasLayer
var hint_box: PanelContainer   ## a one-time pointer, when there is one (Hints)
var build_c: PlaceBuilder   ## builds the room and everything in it (scripts/place/place_builder.gd)
var desks_c: PlaceDesks     ## what each desk shows (scripts/place/place_desks.gd)
var people: Array[Figure] = []
var _ship_data: ShipData
var ship_outside: ShipView   ## your ship, seen through the concourse window
var strollers: Array[Dictionary] = []   ## people walking about: {fig, path, i, wait, speed}
var audio: WorldAudio
var _step_acc := 0.0


func _init() -> void:
	build_c = PlaceBuilder.new(self)
	desks_c = PlaceDesks.new(self)


func _ready() -> void:
	if Session.slot >= 0:
		Session.profile["location"] = "dock"
		Session.save_profile()
	site = Session.port() if Session.slot >= 0 else {}
	var k := String(LocalSpace.node(String(Session.profile.get("port_id", ""))).get("kind", "port"))
	kind = "hab" if k == "pad" else ("hut" if k == "camp" else "concourse")
	style = SystemStyle.for_site(String(Session.profile.get("port_id", "")))   # this system's look (scripts/identity)
	_build_env()
	walker = ShipWalk.new()
	walker.walls[0] = []
	walker.furniture[0] = []
	match kind:
		"hab":
			_build_hab()
		"hut":
			_build_hut()
		_:
			_build_concourse()
	camera = Camera3D.new()
	camera.fov = 72.0
	camera.near = 0.05
	camera.far = 6000.0
	add_child(camera)
	camera.current = true
	_build_hud()
	audio = WorldAudio.new()
	add_child(audio)
	audio.level("port_hum" if kind == "concourse" else "hab_hum", 1.0 if kind != "hut" else 0.7)
	GameSettings.apply_scene(self, 60.0)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_apply_camera()
	_refresh_info()
	if Session.flash != "":
		_say(Session.flash)
		Session.flash = ""
	_show_hint()
	fade.color.a = 1.0   # and in from black
	create_tween().tween_property(fade, "color:a", 0.0, 0.35)


# --- Building the place ------------------------------------------------------------------------------

func _build_env() -> void:
	build_c._build_env()


func _mat(col: Color, glow := false) -> StandardMaterial3D:
	return build_c._mat(col, glow)


## Walk the strollers on: toward the next waypoint, turning smoothly; stop short of you, and pause a
## few seconds at each point.
func _move_strollers(delta: float) -> void:
	Strollers.step(strollers, delta, walker.pos)


func _place_name() -> String:
	return build_c._place_name()


func _build_concourse() -> void:
	build_c._build_concourse()


func _build_hab() -> void:
	build_c._build_hab()


func _build_hut() -> void:
	build_c._build_hut()


# --- On foot -----------------------------------------------------------------------------------------

func _process(delta: float) -> void:
	if leaving:
		return
	if open_desk == "":
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
		walker.look(yaw * KEY_TURN * delta, pitch * KEY_TURN * delta)
		var before := walker.pos
		walker.step(minf(delta, 0.05), dir, Input.is_key_pressed(KEY_SHIFT))
		walker.pos = Strollers.push_out(strollers, walker.pos)   # you bump into walking people rather than through them
		_step_acc += Vector2(walker.pos.x - before.x, walker.pos.z - before.z).length()
		if _step_acc > (0.95 if Input.is_key_pressed(KEY_SHIFT) else 0.75):
			_step_acc = 0.0
			audio.step("metal")
	_move_strollers(delta)
	_apply_camera()
	var eye := walker.eye()
	for f in people:   # people look at you when you come near
		f.look_at_point = eye if f.position.distance_to(Vector3(eye.x, f.position.y, eye.z)) < 6.0 else Vector3.INF
	var d := desk_in_reach()
	prompt.text = "" if open_desk != "" else ("E: %s" % String(d.label) if not d.is_empty() else "")


func _apply_camera() -> void:
	camera.position = walker.eye()
	camera.basis = walker.look_basis()


## The desk you are standing at (closest within reach), or {}.
func desk_in_reach() -> Dictionary:
	var best: Dictionary = {}
	var best_d := REACH
	for d in desks:
		var p: Vector3 = d.pos
		var dist := Vector2(walker.pos.x - p.x, walker.pos.z - p.z).length()
		if dist <= best_d:
			best_d = dist
			best = d
	return best


func _unhandled_input(event: InputEvent) -> void:
	if leaving:
		return
	if open_desk != "":
		if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
			close_desk()
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		walker.look(-event.relative.x * MOUSE_TURN * GameSettings.mouse_sensitivity(), -event.relative.y * MOUSE_TURN * GameSettings.mouse_sensitivity())
		return
	if event is InputEventMouseButton and event.pressed:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		return
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	match event.keycode:
		KEY_E:
			var d := desk_in_reach()
			if not d.is_empty():
				use_desk(String(d.id))
		KEY_T:
			use_desk("terminal")
		KEY_ESCAPE:
			var m := get_node_or_null("GameMenu") as GameMenu
			if m != null:
				m.open()
				get_viewport().set_input_as_handled()
			else:
				Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


## A one-time pointer for new captains (Hints), in a box at the top; it fades after a while.
func _show_hint() -> void:
	if Session.slot < 0:
		return
	var h := Hints.next(kind)
	if h.is_empty():
		return
	Hints.mark_seen(String(h.id))
	hint_box = PanelContainer.new()
	var sb := Brand.panel_box().duplicate() as StyleBoxFlat
	sb.border_color = Brand.AMBER
	hint_box.add_theme_stylebox_override("panel", sb)
	var l := Label.new()
	l.text = String(h.text)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(520, 0)
	l.add_theme_font_size_override("font_size", 16)
	l.add_theme_color_override("font_color", Brand.OFFWHITE)
	hint_box.add_child(l)
	hud_layer.add_child(hint_box)
	hint_box.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE, 24)
	hint_box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	hint_box.offset_left += 110.0   # clear of the place name and credits at the top left
	hint_box.offset_right += 110.0
	var tw := create_tween()
	tw.tween_interval(16.0)
	tw.tween_property(hint_box, "modulate:a", 0.0, 1.5)
	tw.tween_callback(hint_box.hide)


# --- HUD and the desk panel --------------------------------------------------------------------------

func _build_hud() -> void:
	var layer := CanvasLayer.new()
	hud_layer = layer
	add_child(layer)
	info = Label.new()
	info.position = Vector2(28, 24)
	info.add_theme_font_size_override("font_size", 17)
	info.add_theme_color_override("font_color", Brand.OFFWHITE)
	layer.add_child(info)
	prompt = Label.new()
	prompt.add_theme_font_size_override("font_size", 22)
	prompt.add_theme_color_override("font_color", Brand.AMBER)
	prompt.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM, Control.PRESET_MODE_MINSIZE, 60)
	prompt.grow_horizontal = Control.GROW_DIRECTION_BOTH
	layer.add_child(prompt)
	crosshair = Label.new()
	crosshair.text = "+"
	crosshair.add_theme_font_size_override("font_size", 22)
	crosshair.add_theme_color_override("font_color", Color(Brand.OFFWHITE, 0.7))
	crosshair.set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_MINSIZE)
	layer.add_child(crosshair)
	var help := Brand.note(HELP, 13)
	help.autowrap_mode = TextServer.AUTOWRAP_OFF
	help.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT, Control.PRESET_MODE_MINSIZE, 20)
	layer.add_child(help)
	panel = PanelContainer.new()
	var solid := Brand.panel_box().duplicate() as StyleBoxFlat
	solid.bg_color.a = 1.0
	panel.add_theme_stylebox_override("panel", solid)
	panel.visible = false
	layer.add_child(panel)
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.offset_left = 120
	panel.offset_right = -120
	panel.offset_top = 50
	panel.offset_bottom = -50
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	panel.add_child(col)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(scroll)
	panel_list = VBoxContainer.new()
	panel_list.add_theme_constant_override("separation", 5)
	panel_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(panel_list)
	panel_status = Label.new()
	panel_status.add_theme_color_override("font_color", Brand.AMBER)
	panel_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(panel_status)
	var close := Button.new()
	close.text = "CLOSE (Esc)"
	Brand.style_button(close, 16)
	close.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	close.pressed.connect(close_desk)
	col.add_child(close)
	fade = ColorRect.new()
	fade.color = Color(0, 0, 0, 0)
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(fade)
	fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _refresh_info() -> void:
	var lines := PackedStringArray([_place_name(),
		"%s  ·  %s" % [String(Worlds.system(Session.system_id()).get("name", Session.system_id().capitalize())), {"concourse": "Station concourse", "hab": "Moon base hab", "hut": "Mining camp"}[kind]]])
	if Session.slot >= 0:
		lines.append("Credits %s cr    Day %d    Hull %d%%" % [ShipStats.commas(int(Session.profile.credits)), Session.day(), roundi((1.0 - float(Session.profile.get("hull_damage", 0.0))) * 100.0)])
		lines.append("Standing: %s" % People.standing(int(Session.profile.get("rep", 0))))
		var c := Session.active_contract()
		if not c.is_empty():
			var due := ""
			if c.has("due_hour") and Session.sim != null and String(c.get("status", "")) != "arrived":
				var left := int(c.due_hour) - int(Session.sim.hour)
				due = "  (due in %d h)" % left if left >= 0 else "  (late)"
			lines.append("Active: %s%s%s" % [String(c.get("title", "")), "  (arrived: deliver it)" if String(c.get("status", "")) == "arrived" else "", due])
		var held := Session.mission()
		if not held.is_empty():
			lines.append("Mission: %s (%s on the clock)" % [String(held.title), SurfaceWork.clock(float(held.limit_s) - float(held.get("elapsed_s", 0.0)))])
		var f := Session.finds_aboard()
		if int(f.value) > 0:
			lines.append("Locker: %s" % SurfaceFinds.describe(f))
	info.text = "\n".join(lines)


func _say(msg: String) -> void:
	if panel_status != null:
		panel_status.text = msg
	prompt.text = msg


func close_desk() -> void:
	open_desk = ""
	panel.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_refresh_info()


func _clear_panel(title: String, note := "") -> void:
	for c in panel_list.get_children():
		c.queue_free()
	panel_list.add_child(Brand.heading(title.to_upper(), 17))
	if note != "":
		var n := Brand.note(note, 14)
		n.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		panel_list.add_child(n)


func _action(text: String, cb: Callable, enabled := true) -> Button:
	var b := Button.new()
	b.text = text
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	Brand.style_button(b, 15)
	b.disabled = not enabled
	b.pressed.connect(func() -> void: audio.play("ui"))
	b.pressed.connect(cb)
	panel_list.add_child(b)
	return b


func _go(scene: String) -> void:
	if leaving:
		return
	leaving = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var tw := create_tween()   # a short fade to black, then the next place
	tw.tween_property(fade, "color:a", 1.0, 0.25)
	tw.tween_callback(func() -> void: get_tree().change_scene_to_file(scene))


## Open a desk (also callable from tests). Most desks show a panel; the terminal and gate move on.
func use_desk(id: String) -> void:
	if id == "terminal":
		_go(Session.DOCK_SCENE)
		return
	open_desk = id
	audio.play("ui")
	panel.visible = true
	panel_status.text = ""
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_fill(id)


func _fill(id: String) -> void:
	desks_c._fill(id)


func _refill() -> void:
	_refresh_info()
	if open_desk != "":
		_fill(open_desk)


# --- Desks -------------------------------------------------------------------------------------------


