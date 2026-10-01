extends Node3D
## Ship builder prototype. Pick a module, rotate it, click to snap it onto the ship.
## Everything (camera, lights, UI) is created in code so there's nothing to wire up in the editor.

const GOOD := Color(0.25, 1.0, 0.4, 0.45)
const BAD := Color(1.0, 0.25, 0.25, 0.45)
const GRID_HALF := 12  # grid extends this many cells each way from the origin
const SAVE_PATH := "user://ship.json"

var library: ModuleLibrary
var ship: ShipData
var ship_view: ShipView

var selected := 0  # index into library.order
var rot := 0  # quarter-turns around Y
var level := 0  # which deck (Y layer) we're building on

var ghost: Node3D
var ghost_mat: StandardMaterial3D
var hover_active := false
var hover_cell := Vector3i.ZERO
var hover_error := ""  # "" means the ghost's position is valid

var camera: Camera3D
var cam_target := Vector3.ZERO
var cam_yaw := 0.6
var cam_pitch := 0.9
var cam_dist := 24.0

var grid: MeshInstance3D
var com_marker: MeshInstance3D
var buttons: Array[Button] = []
var info_label: Label
var stats_label: Label
var warn_label: Label
var message := ""


func _ready() -> void:
	library = ModuleLibrary.new()
	ship = ShipData.new(library)

	_setup_environment()
	_setup_camera()
	_setup_grid()
	_setup_com_marker()
	ship_view = ShipView.new()
	add_child(ship_view)
	_setup_ui()

	_select(0)
	_set_level(0)
	_refresh_ship()


# --- Setup -----------------------------------------------------------------------------------

func _setup_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.04, 0.05, 0.09)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.6, 0.65, 0.75)
	env.ambient_light_energy = 0.8
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var sun := DirectionalLight3D.new()  # no shadows: cheap on integrated GPUs
	sun.rotation_degrees = Vector3(-55, 35, 0)
	sun.light_energy = 0.9
	add_child(sun)


func _setup_camera() -> void:
	camera = Camera3D.new()
	camera.fov = 55.0
	camera.far = 500.0
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


func _setup_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)

	# Left: palette and controls.
	var panel := PanelContainer.new()
	panel.position = Vector2(12, 12)
	layer.add_child(panel)
	var box := VBoxContainer.new()
	panel.add_child(box)

	var shown_external_header := false
	box.add_child(_header("HULL (walkable)"))
	for i in library.order.size():
		var def := library.get_def(library.order[i])
		if not def.pressurized and not shown_external_header:
			shown_external_header = true
			box.add_child(_header("EXTERNAL (bolt-on)"))
		var key := "%d" % ((i + 1) % 10) if i < 10 else " "
		var b := Button.new()
		b.text = "%s  %s" % [key, def.display_name]
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.focus_mode = Control.FOCUS_NONE  # keep keyboard shortcuts working after a click
		b.pressed.connect(_select.bind(i))
		box.add_child(b)
		buttons.append(b)

	var row := HBoxContainer.new()
	box.add_child(row)
	_add_action_button(row, "Rotate (R)", _rotate)
	_add_action_button(row, "Save (S)", _save)
	_add_action_button(row, "Load (L)", _load)
	_add_action_button(row, "Clear (C)", _clear)

	info_label = Label.new()
	box.add_child(info_label)

	# Right: ship stats.
	var stats_panel := PanelContainer.new()
	layer.add_child(stats_panel)
	var stats_box := VBoxContainer.new()
	stats_panel.add_child(stats_box)
	stats_label = Label.new()
	stats_label.custom_minimum_size = Vector2(250, 0)
	stats_box.add_child(stats_label)
	warn_label = Label.new()
	warn_label.custom_minimum_size = Vector2(250, 0)
	warn_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	warn_label.modulate = Color(1.0, 0.6, 0.3)
	stats_box.add_child(warn_label)
	stats_panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE, 12)
	stats_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN


func _header(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.modulate = Color(0.7, 0.8, 1.0)
	return l


func _add_action_button(parent: Control, text: String, callback: Callable) -> void:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(callback)
	parent.add_child(b)


# --- Input -----------------------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
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
				cam_dist = maxf(6.0, cam_dist * 0.9)
				_update_camera()
			MOUSE_BUTTON_WHEEL_DOWN:
				cam_dist = minf(120.0, cam_dist / 0.9)
				_update_camera()
	elif event is InputEventKey and event.pressed and not event.echo:
		_on_key(event.keycode)


func _on_key(key: Key) -> void:
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
		_update_ghost()


# --- Camera ----------------------------------------------------------------------------------

func _update_camera() -> void:
	var offset := Vector3(0, 0, cam_dist)
	offset = offset.rotated(Vector3.RIGHT, -cam_pitch).rotated(Vector3.UP, cam_yaw)
	camera.position = cam_target + offset
	camera.look_at(cam_target, Vector3.UP)


func _pan(rel: Vector2) -> void:
	var basis := camera.global_transform.basis
	var right := Vector3(basis.x.x, 0, basis.x.z).normalized()
	var fwd := Vector3(-basis.z.x, 0, -basis.z.z).normalized()
	cam_target += (-right * rel.x + fwd * rel.y) * cam_dist * 0.0015
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

	for j in buttons.size():
		buttons[j].modulate = Color(1.0, 0.95, 0.5) if j == i else Color.WHITE
	_update_ghost()
	_refresh_info()


func _override_materials(node: Node, mat: Material) -> void:
	if node is MeshInstance3D:
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
	cam_target.y = level * ShipGrid.CELL
	_update_camera()
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


func _update_ghost() -> void:
	if ghost == null:
		return
	var cell: Variant = _mouse_cell()
	if cell == null:
		hover_active = false
		ghost.visible = false
		return
	hover_active = true
	hover_cell = cell
	hover_error = ship.check_place(library.order[selected], hover_cell, rot)
	ghost_mat.albedo_color = GOOD if hover_error == "" else BAD
	ghost.position = ShipGrid.cell_to_world(hover_cell)
	ghost.rotation.y = rot * PI / 2.0
	ghost.visible = not Input.is_key_pressed(KEY_SHIFT)  # hide while removing


func _on_click() -> void:
	if not hover_active:
		return
	if Input.is_key_pressed(KEY_SHIFT):
		message = ship.remove_at(hover_cell)
	else:
		message = ship.add(library.order[selected], hover_cell, rot)
	_refresh_ship()


## Call after any change to the ship: rebuilds visuals, stats, and the centre-of-mass marker.
func _refresh_ship() -> void:
	ship_view.rebuild(ship)
	var st := ShipStats.compute(ship)
	com_marker.visible = not ship.modules.is_empty()
	com_marker.position = st.com
	stats_label.text = ShipStats.format(st)
	warn_label.text = "\n".join(PackedStringArray(st.warnings))
	_update_ghost()
	_refresh_info()


# --- Save / load / clear -------------------------------------------------------------------

func _save() -> void:
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		message = "Could not save (error %d)" % FileAccess.get_open_error()
	else:
		f.store_string(ship.to_json())
		f.close()
		message = "Saved to " + ProjectSettings.globalize_path(SAVE_PATH)
	_refresh_info()


func _load() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		message = "No saved ship yet (press S first)"
	elif ship.from_json(FileAccess.get_file_as_string(SAVE_PATH)):
		message = "Loaded"
	else:
		message = "Save file couldn't be loaded"
	_refresh_ship()


func _clear() -> void:
	ship.clear()
	message = "Cleared"
	_refresh_ship()


# --- UI text ---------------------------------------------------------------------------------

func _refresh_info() -> void:
	info_label.text = "Deck %d   Rotation %d°\n%s\n\n%s" % [
		level, rot * 90, message,
		"Click place   Shift+click remove\nR rotate   Q/E deck down/up\n[ ] or 1-9,0 pick module\nRight-drag orbit   Wheel zoom\nMiddle-drag or arrows pan\nS save   L load   C clear\nYellow ball = centre of mass",
	]
