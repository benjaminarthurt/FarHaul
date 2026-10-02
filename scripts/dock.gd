extends Node3D
## The dock: where a saved game rests between jobs. It is the way into the shipyard (ship builder),
## which only exists at a yard, so which one you reach depends on your starting world.
## Contract board and departure are placeholders until those parts of the game exist.

var camera: Camera3D
var centre := Vector3.ZERO
var orbit := 0.0
var fade: ColorRect
var status: Label
var contract_panel: PanelContainer
var contract_list: VBoxContainer
var leaving := false


func _ready() -> void:
	if Session.slot >= 0:
		Session.profile["location"] = "dock"
		Session.save_profile()
	_build_world()
	_build_ui()


func _process(delta: float) -> void:
	orbit += delta * 0.12
	var r := 23.0
	camera.position = centre + Vector3(sin(orbit) * r, 5.5 + sin(orbit * 0.7) * 1.2, cos(orbit) * r)
	camera.look_at(centre + Vector3(0, 0.3, 0))


func _build_world() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = SpaceSky.make()
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.glow_intensity = 0.9
	env.glow_bloom = 0.08
	env.glow_hdr_threshold = 0.9
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.45, 0.5, 0.62)
	env.ambient_light_energy = 0.5
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35, 35, 0)
	sun.light_color = Color(1.0, 0.94, 0.85)
	sun.light_energy = 1.3
	add_child(sun)
	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-15, -140, 0)
	rim.light_color = Color(0.55, 0.7, 1.0)
	rim.light_energy = 0.6
	add_child(rim)

	var lib := ModuleLibrary.new()
	var ship := ShipData.new(lib)
	var loaded := Session.slot >= 0 and SaveSlots.exists(Session.slot) and ship.from_json(FileAccess.get_file_as_string(SaveSlots.path(Session.slot)))
	if not loaded:
		ShipPresets.build(ship)
	var view := ShipView.new()
	add_child(view)
	var manifest := CargoManifest.new(ship)
	view.rebuild(ship, manifest)
	var st := ShipStats.compute(ship)
	centre = st.centre
	camera = Camera3D.new()
	camera.fov = 42.0
	camera.h_offset = -4.5
	add_child(camera)
	camera.current = true


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var grad := Gradient.new()
	grad.set_color(0, Color(Brand.STEEL_DARK, 0.88))
	grad.set_color(1, Color(Brand.STEEL_DARK, 0.0))
	grad.set_offset(1, 0.7)
	var gt := GradientTexture2D.new()
	gt.gradient = grad
	gt.fill_from = Vector2(0, 0)
	gt.fill_to = Vector2(1, 0)
	var shade := TextureRect.new()
	shade.texture = gt
	shade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(shade)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 72)
	margin.add_theme_constant_override("margin_top", 56)
	margin.add_theme_constant_override("margin_bottom", 40)
	layer.add_child(margin)
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	margin.add_child(col)

	var w := Session.world()
	var where := Label.new()
	where.text = String(w.name).to_upper()
	where.add_theme_font_size_override("font_size", 40)
	where.add_theme_color_override("font_color", Brand.OFFWHITE)
	col.add_child(where)
	var yard := Label.new()
	yard.text = "%s  ·  %s  ·  %s" % [w.name, Worlds.yard_tier(String(w.tier)).name, String(w.system_id).replace("_", " ").capitalize()]
	yard.add_theme_font_size_override("font_size", 18)
	yard.add_theme_color_override("font_color", Brand.AMBER)
	col.add_child(yard)
	col.add_child(_gap(14))

	var p := Session.profile
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 24)
	grid.add_theme_constant_override("v_separation", 4)
	col.add_child(grid)
	_row(grid, "Captain", "%s, %s" % [p.name, Worlds.race(p.race).name])
	_row(grid, "Ship", Session.ship_label())
	_row(grid, "Credits", "%s cr" % ShipStats.commas(int(p.credits)))
	_row(grid, "Difficulty", Worlds.difficulty(p.difficulty).name)
	col.add_child(_gap(18))

	var menu := VBoxContainer.new()
	menu.add_theme_constant_override("separation", 8)
	menu.custom_minimum_size = Vector2(340, 0)
	menu.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	col.add_child(menu)
	var yard_btn := _button(menu, "ENTER SHIPYARD", _enter_yard)
	_button(menu, "CONTRACT BOARD", _show_contracts)
	_button(menu, "DEPART  (coming soon)", Callable()).disabled = true
	_button(menu, "SAVE GAME", _save)
	_button(menu, "MAIN MENU", _main_menu)
	status = Label.new()
	status.add_theme_color_override("font_color", Brand.MUTED)
	status.add_theme_font_size_override("font_size", 13)
	col.add_child(status)
	contract_panel = PanelContainer.new()
	contract_panel.visible = false
	contract_panel.add_theme_stylebox_override("panel", Brand.panel_box())
	contract_panel.custom_minimum_size = Vector2(520, 0)
	col.add_child(contract_panel)
	contract_list = VBoxContainer.new()
	contract_list.add_theme_constant_override("separation", 4)
	contract_panel.add_child(contract_list)
	var note := Brand.note("The shipyard is where you build and fit your ship. It is only open at a yard like this one.")
	note.custom_minimum_size = Vector2(380, 0)
	col.add_child(note)
	yard_btn.grab_focus()

	fade = ColorRect.new()
	fade.color = Color(0, 0, 0, 1)
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fl := CanvasLayer.new()
	fl.layer = 100
	add_child(fl)
	fl.add_child(fade)
	fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	create_tween().tween_property(fade, "color:a", 0.0, 0.5)


func _gap(h: int) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	return c


func _row(grid: GridContainer, label: String, value: String) -> void:
	var a := Label.new()
	a.text = label
	a.add_theme_color_override("font_color", Brand.MUTED)
	grid.add_child(a)
	var b := Label.new()
	b.text = value
	b.add_theme_color_override("font_color", Brand.OFFWHITE)
	grid.add_child(b)


func _button(parent: Control, text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	Brand.style_button(b, 20)
	if cb.is_valid():
		b.pressed.connect(cb)
	parent.add_child(b)
	return b


func _go(scene: String) -> void:
	if leaving:
		return
	leaving = true
	var tw := create_tween()
	tw.tween_property(fade, "color:a", 1.0, 0.35)
	tw.tween_callback(func() -> void: get_tree().change_scene_to_file(scene))


func _show_contracts() -> void:
	contract_panel.visible = not contract_panel.visible
	for child in contract_list.get_children():
		child.queue_free()
	if not contract_panel.visible:
		return
	var system_id := Worlds.yard_system(String(Session.profile.world))
	var port := Worlds.primary_port(system_id)
	var heading := Brand.heading("FREIGHT BOARD — %s" % String(port.get("name", system_id)).to_upper(), 15)
	contract_list.add_child(heading)
	var offers := Contracts.offers_from(system_id)
	if offers.is_empty():
		contract_list.add_child(Brand.note("No profitable scheduled freight is posted here right now."))
		return
	for c in offers:
		var goods := Worlds.commodity(String(c.commodity))
		var destination := Worlds.port(String(c.destination_port_id))
		var line := Label.new()
		line.text = "%s  →  %s\n%.1f t available  ·  %.2f ly  ·  %s cr/t  ·  up to %s cr" % [
			goods.name, destination.get("name", c.destination_system_id), float(c.offer), float(c.distance_ly),
			ShipStats.commas(int(c.rate)), ShipStats.commas(roundi(float(c.offer) * float(c.rate)))]
		line.add_theme_color_override("font_color", Brand.OFFWHITE)
		contract_list.add_child(line)


func _enter_yard() -> void:
	Session.profile["location"] = "shipyard"
	Session.save_profile()
	_go(Session.YARD_SCENE)


func _save() -> void:
	status.text = "Saved to slot %d" % (Session.slot + 1) if Session.save_profile() else "Not part of a saved game, so nothing was saved"


func _main_menu() -> void:
	Session.save_profile()
	Session.skip_intro = true
	_go(Session.BOOT_SCENE)
