extends Node
## Start-up flow: splash, then the intro video, then the title screen (continue, new game, load,
## settings). A game then opens at the dock or shipyard where it was saved.
## Any key, click or tap skips the splash and the intro. Missing or broken video is skipped.
## Env vars for testing: FARHAUL_SKIP_INTRO=1 goes straight to the title screen.

enum Stage { SPLASH, INTRO, TITLE }

const SPLASH_HOLD := 1.8

var stage := Stage.SPLASH
var stage_time := 0.0
var leaving := false

var splash_layer: CanvasLayer
var splash_pic: TextureRect
var intro_layer: CanvasLayer
var player: VideoStreamPlayer
var skip_hint: Label
var title_layer: CanvasLayer
var title_box: Control
var fade: ColorRect
var world: Node3D
var camera: Camera3D
var orbit := 0.0
var orbit_centre := Vector3.ZERO
var continue_btn: Button
var last_label: Label
var menu_box: Control
var brand_bits: Array[Control] = []  ## logo and tagline, hidden while a panel is open
var new_panel: NewGamePanel
var load_panel: LoadPanel
var settings_panel: SettingsPanel


func _ready() -> void:
	DisplayServer.window_set_title(Brand.NAME)
	_build_world()
	_build_title()
	_build_panels()
	_build_splash()
	_build_intro()
	fade = ColorRect.new()
	fade.color = Color.BLACK
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fl := CanvasLayer.new()
	fl.layer = 100
	add_child(fl)
	fl.add_child(fade)
	fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	if OS.has_environment("FARHAUL_SKIP_INTRO") or Session.skip_intro:
		Session.skip_intro = false
		_enter_title(false)
	else:
		_enter_splash()


# --- Stages ----------------------------------------------------------------------------------

## Controls under a CanvasLayer can be left at size 0 if they were laid out before the window was
## ready, so re-fit the full-screen ones whenever a stage starts.
func _fit_full(c: Control) -> void:
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _enter_splash() -> void:
	_fit_full(splash_layer.get_child(0))
	_fit_full(splash_pic)
	stage = Stage.SPLASH
	stage_time = 0.0
	splash_layer.visible = true
	intro_layer.visible = false
	title_layer.visible = false
	world.visible = false
	splash_pic.modulate.a = 0.0
	fade.color.a = 0.0
	var tw := create_tween()
	tw.tween_property(splash_pic, "modulate:a", 1.0, 0.7)
	tw.tween_interval(SPLASH_HOLD)
	tw.tween_callback(_enter_intro)
	splash_pic.set_meta("tween", tw)


func _enter_intro() -> void:
	if stage != Stage.SPLASH:
		return
	_kill_splash_tween()
	if not ResourceLoader.exists(Brand.INTRO_VIDEO):
		_enter_title(true)
		return
	var stream := load(Brand.INTRO_VIDEO) as VideoStream
	if stream == null:
		_enter_title(true)
		return
	stage = Stage.INTRO
	stage_time = 0.0
	_fit_full(intro_layer.get_child(0))
	_fit_full(player)
	splash_layer.visible = false
	intro_layer.visible = true
	player.stream = stream
	player.play()
	skip_hint.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_interval(1.5)
	tw.tween_property(skip_hint, "modulate:a", 0.8, 0.6)


func _enter_title(animate: bool) -> void:
	if stage == Stage.TITLE and title_layer.visible:
		return
	_kill_splash_tween()
	player.stop()
	stage = Stage.TITLE
	stage_time = 0.0
	splash_layer.visible = false
	intro_layer.visible = false
	world.visible = true
	title_layer.visible = true
	if animate:
		fade.color.a = 1.0
		create_tween().tween_property(fade, "color:a", 0.0, 0.8)
	else:
		fade.color.a = 0.0
	SaveSlots.import_legacy()
	_show_menu()


func _kill_splash_tween() -> void:
	if splash_pic and splash_pic.has_meta("tween"):
		var tw: Tween = splash_pic.get_meta("tween")
		if tw and tw.is_valid():
			tw.kill()


func _process(delta: float) -> void:
	stage_time += delta
	if stage == Stage.INTRO and not player.is_playing() and stage_time > 0.5:
		_enter_title(true)
	if stage == Stage.TITLE:
		orbit += delta * 0.12
		var r := 23.0
		camera.position = orbit_centre + Vector3(sin(orbit) * r, 5.5 + sin(orbit * 0.7) * 1.2, cos(orbit) * r)
		camera.look_at(orbit_centre + Vector3(0, 0.3, 0))
		title_box.modulate.a = minf(1.0, stage_time / 0.8)


func _unhandled_input(event: InputEvent) -> void:
	var pressed: bool = (event is InputEventKey and event.pressed and not event.echo) \
		or (event is InputEventMouseButton and event.pressed) \
		or (event is InputEventScreenTouch and event.pressed)
	if not pressed:
		return
	if stage == Stage.SPLASH:
		_enter_intro()
	elif stage == Stage.INTRO:
		_enter_title(true)


# --- Title actions ---------------------------------------------------------------------------

func _show_menu() -> void:
	new_panel.visible = false
	load_panel.visible = false
	settings_panel.visible = false
	menu_box.visible = true
	for b in brand_bits:
		b.modulate.a = 1.0
	var latest := SaveSlots.latest()
	continue_btn.disabled = latest < 0
	if latest >= 0:
		var p := SaveSlots.profile(latest)
		last_label.text = "Slot %d: %s, %s" % [latest + 1, p.name, Worlds.world(p.world).name]
	else:
		last_label.text = "No saved games yet"
	(continue_btn if latest >= 0 else menu_box.get_child(1)).grab_focus()


func _show_panel(panel: Control) -> void:
	new_panel.visible = false
	load_panel.visible = false
	settings_panel.visible = false
	panel.visible = true
	for b in brand_bits:
		b.modulate.a = 0.0


func _on_continue() -> void:
	var latest := SaveSlots.latest()
	if latest >= 0 and Session.load_slot(latest):
		_enter_game()


func _on_new() -> void:
	new_panel.reset()
	_show_panel(new_panel)


func _on_load() -> void:
	load_panel.refresh()
	_show_panel(load_panel)


func _on_settings() -> void:
	_show_panel(settings_panel)


func _on_begin(slot: int, player_name: String, species_id: String, difficulty: String, world_id: String) -> void:
	if Session.begin_new(slot, player_name, species_id, difficulty, world_id):
		_enter_game()


func _on_load_chosen(slot: int) -> void:
	if Session.load_slot(slot):
		_enter_game()


## Fades out and opens the saved game at its last place: the dock, or the shipyard.
func _enter_game() -> void:
	if leaving:
		return
	leaving = true
	var tw := create_tween()
	tw.tween_property(fade, "color:a", 1.0, 0.4)
	tw.tween_callback(func() -> void: get_tree().change_scene_to_file(Session.scene_path()))


func _on_quit() -> void:
	get_tree().quit()


# --- Construction ----------------------------------------------------------------------------

func _build_world() -> void:
	world = Node3D.new()
	add_child(world)
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
	world.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35, 35, 0)
	sun.light_color = Color(1.0, 0.94, 0.85)
	sun.light_energy = 1.3
	world.add_child(sun)
	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-15, -140, 0)
	rim.light_color = Color(0.55, 0.7, 1.0)
	rim.light_energy = 0.6
	rim.shadow_enabled = false
	world.add_child(rim)

	var lib := ModuleLibrary.new()
	var ship := ShipData.new(lib)
	ShipPresets.build(ship)
	var view := ShipView.new()
	world.add_child(view)
	view.rebuild(ship)
	view.set_flames(true)
	var st := ShipStats.compute(ship)
	orbit_centre = st.centre
	camera = Camera3D.new()
	camera.fov = 42.0
	camera.h_offset = -4.5  # pushes the ship to the right, clear of the menu
	world.add_child(camera)
	camera.current = true


func _build_splash() -> void:
	splash_layer = CanvasLayer.new()
	splash_layer.layer = 10
	add_child(splash_layer)
	var bg := ColorRect.new()
	bg.color = Brand.STEEL_DARK
	splash_layer.add_child(bg)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	splash_pic = TextureRect.new()
	splash_pic.texture = load(Brand.SPLASH)
	splash_pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	splash_pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	splash_layer.add_child(splash_pic)
	splash_pic.set_anchors_preset(Control.PRESET_FULL_RECT)


func _build_intro() -> void:
	intro_layer = CanvasLayer.new()
	intro_layer.layer = 20
	add_child(intro_layer)
	var bg := ColorRect.new()
	bg.color = Color.BLACK
	intro_layer.add_child(bg)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	player = VideoStreamPlayer.new()
	player.expand = true
	player.mouse_filter = Control.MOUSE_FILTER_IGNORE
	intro_layer.add_child(player)
	player.set_anchors_preset(Control.PRESET_FULL_RECT)
	skip_hint = Label.new()
	skip_hint.text = "PRESS ANY KEY TO SKIP"
	skip_hint.add_theme_color_override("font_color", Brand.MUTED)
	skip_hint.add_theme_font_size_override("font_size", 14)
	intro_layer.add_child(skip_hint)
	skip_hint.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT, Control.PRESET_MODE_MINSIZE, 24)


func _build_title() -> void:
	title_layer = CanvasLayer.new()
	title_layer.layer = 5
	add_child(title_layer)
	# Darkens the left side so the menu reads over the sky.
	var grad := Gradient.new()
	grad.set_color(0, Color(Brand.STEEL_DARK, 0.88))
	grad.set_color(1, Color(Brand.STEEL_DARK, 0.0))
	grad.set_offset(1, 0.7)
	var gt := GradientTexture2D.new()
	gt.gradient = grad
	gt.fill_from = Vector2(0, 0)
	gt.fill_to = Vector2(1, 0)
	var shade_tex := TextureRect.new()
	shade_tex.texture = gt
	shade_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	shade_tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_layer.add_child(shade_tex)
	shade_tex.set_anchors_preset(Control.PRESET_FULL_RECT)

	title_box = MarginContainer.new()
	title_box.add_theme_constant_override("margin_left", 72)
	title_box.add_theme_constant_override("margin_top", 56)
	title_box.add_theme_constant_override("margin_bottom", 40)
	title_layer.add_child(title_box)
	title_box.set_anchors_preset(Control.PRESET_FULL_RECT)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	title_box.add_child(col)

	var logo := TextureRect.new()
	logo.texture = load(Brand.LOGO)
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
	logo.custom_minimum_size = Vector2(520, 150)
	logo.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	col.add_child(logo)
	brand_bits.append(logo)

	var tag := Label.new()
	tag.text = Brand.TAGLINE
	tag.add_theme_color_override("font_color", Brand.MUTED)
	tag.add_theme_font_size_override("font_size", 13)
	col.add_child(tag)
	brand_bits.append(tag)

	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 36)
	col.add_child(gap)

	var menu := VBoxContainer.new()
	menu.add_theme_constant_override("separation", 8)
	menu.custom_minimum_size = Vector2(330, 0)
	menu.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	col.add_child(menu)
	menu_box = menu
	continue_btn = _menu_button(menu, "CONTINUE", _on_continue)
	_menu_button(menu, "NEW GAME", _on_new)
	_menu_button(menu, "LOAD GAME", _on_load)
	_menu_button(menu, "SETTINGS", _on_settings)
	_menu_button(menu, "QUIT", _on_quit)
	last_label = Label.new()
	last_label.add_theme_color_override("font_color", Brand.MUTED)
	last_label.add_theme_font_size_override("font_size", 13)
	col.add_child(last_label)
	col.move_child(last_label, menu.get_index() + 1)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(spacer)

	var foot := Label.new()
	foot.text = "%s   v%s   %s" % [Brand.STAGE.to_upper(), Brand.version(), Brand.container_code(1)]
	foot.add_theme_color_override("font_color", Color(Brand.MUTED, 0.7))
	foot.add_theme_font_size_override("font_size", 12)
	col.add_child(foot)


func _build_panels() -> void:
	new_panel = NewGamePanel.new()
	new_panel.begin.connect(_on_begin)
	new_panel.back.connect(_show_menu)
	load_panel = LoadPanel.new()
	load_panel.chosen.connect(_on_load_chosen)
	load_panel.back.connect(_show_menu)
	settings_panel = SettingsPanel.new()
	settings_panel.back.connect(_show_menu)
	for p in [new_panel, load_panel, settings_panel]:
		p.visible = false
		title_layer.add_child(p)
		p.anchor_left = 0.0
		p.anchor_right = 0.0
		p.anchor_top = 0.5
		p.anchor_bottom = 0.5
		p.offset_left = 440
		p.offset_right = 440
		p.offset_top = 0
		p.offset_bottom = 0
		p.grow_horizontal = Control.GROW_DIRECTION_END
		p.grow_vertical = Control.GROW_DIRECTION_BOTH


func _menu_button(parent: Control, text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	Brand.style_button(b)
	b.pressed.connect(cb)
	parent.add_child(b)
	return b
