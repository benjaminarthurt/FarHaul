class_name NewGamePanel
extends PanelContainer
## Choices for a new game: name, race, difficulty, starting world and which slot to save in.

signal begin(slot: int, player_name: String, race: String, difficulty: String, world_id: String)
signal back

var name_edit: LineEdit
var race_pick: OptionButton
var race_note: Label
var diff_buttons: Array[Button] = []
var diff_note: Label
var world_buttons: Array[Button] = []
var world_note: Label
var slot_buttons: Array[Button] = []
var slot_note: Label
var begin_btn: Button


func _init() -> void:
	add_theme_stylebox_override("panel", Brand.panel_box())
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	add_child(col)
	col.add_child(Brand.heading("NEW GAME", 18))

	col.add_child(Brand.heading("NAME"))
	name_edit = LineEdit.new()
	name_edit.text = "Ren Calloway"
	name_edit.max_length = 24
	name_edit.placeholder_text = "Your name"
	name_edit.custom_minimum_size = Vector2(320, 34)
	name_edit.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	name_edit.text_changed.connect(func(_t: String) -> void: _refresh())
	col.add_child(name_edit)

	col.add_child(Brand.heading("RACE"))
	var rrow := HBoxContainer.new()
	rrow.add_theme_constant_override("separation", 14)
	col.add_child(rrow)
	race_pick = OptionButton.new()
	race_pick.custom_minimum_size = Vector2(160, 32)
	for r in Worlds.RACES:
		race_pick.add_item(r.name)
	race_pick.item_selected.connect(func(_i: int) -> void: _refresh())
	rrow.add_child(race_pick)
	race_note = Brand.note("")
	race_note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rrow.add_child(race_note)

	col.add_child(Brand.heading("DIFFICULTY"))
	var drow := HBoxContainer.new()
	drow.add_theme_constant_override("separation", 6)
	col.add_child(drow)
	var dgroup := ButtonGroup.new()
	for d in Worlds.DIFFICULTIES:
		var b := Brand.toggle(d.name, dgroup)
		b.custom_minimum_size = Vector2(120, 0)
		b.pressed.connect(_refresh)
		drow.add_child(b)
		diff_buttons.append(b)
	diff_buttons[1].button_pressed = true
	diff_note = Brand.note("")
	col.add_child(diff_note)

	col.add_child(Brand.heading("STARTING WORLD"))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	col.add_child(grid)
	var wgroup := ButtonGroup.new()
	for w in Worlds.WORLDS:
		var b := Brand.toggle(w.name, wgroup)
		b.custom_minimum_size = Vector2(250, 0)
		b.pressed.connect(_refresh)
		grid.add_child(b)
		world_buttons.append(b)
	world_buttons[0].button_pressed = true
	world_note = Brand.note("")
	world_note.custom_minimum_size = Vector2(500, 0)
	col.add_child(world_note)

	col.add_child(Brand.heading("SAVE SLOT"))
	var srow := HBoxContainer.new()
	srow.add_theme_constant_override("separation", 6)
	col.add_child(srow)
	var sgroup := ButtonGroup.new()
	for i in SaveSlots.COUNT:
		var b := Brand.toggle(str(i + 1), sgroup)
		b.custom_minimum_size = Vector2(60, 0)
		b.pressed.connect(_refresh)
		srow.add_child(b)
		slot_buttons.append(b)
	slot_note = Brand.note("")
	col.add_child(slot_note)

	var brow := HBoxContainer.new()
	brow.add_theme_constant_override("separation", 10)
	col.add_child(brow)
	var back_btn := Button.new()
	back_btn.text = "BACK"
	Brand.style_button(back_btn, 18)
	back_btn.custom_minimum_size = Vector2(150, 0)
	back_btn.pressed.connect(func() -> void: back.emit())
	brow.add_child(back_btn)
	begin_btn = Button.new()
	begin_btn.text = "BEGIN"
	Brand.style_button(begin_btn, 18)
	begin_btn.custom_minimum_size = Vector2(200, 0)
	begin_btn.pressed.connect(_on_begin)
	brow.add_child(begin_btn)
	reset()


## Called each time the panel is opened: picks the first empty slot.
func reset() -> void:
	var s := SaveSlots.first_empty()
	slot_buttons[maxi(s, 0)].button_pressed = true
	_refresh()


func _index(buttons: Array[Button]) -> int:
	for i in buttons.size():
		if buttons[i].button_pressed:
			return i
	return 0


func selected_slot() -> int:
	return _index(slot_buttons)


func _refresh() -> void:
	race_note.text = Worlds.RACES[race_pick.selected].blurb
	diff_note.text = Worlds.DIFFICULTIES[_index(diff_buttons)].blurb
	var w: Dictionary = Worlds.WORLDS[_index(world_buttons)]
	world_note.text = "%s. You start at %s, a %s.\n%s" % [w.name, w.yard_name, String(w.yard_type).to_lower(), w.blurb]
	var s := selected_slot()
	if SaveSlots.exists(s):
		var p := SaveSlots.profile(s)
		slot_note.text = "Slot %d already holds %s's game. Starting here moves that save aside; it is not deleted." % [s + 1, p.name]
		slot_note.add_theme_color_override("font_color", Brand.AMBER)
	else:
		slot_note.text = "Slot %d is empty." % (s + 1)
		slot_note.add_theme_color_override("font_color", Brand.MUTED)
	begin_btn.disabled = name_edit.text.strip_edges() == ""


func _on_begin() -> void:
	begin.emit(selected_slot(), name_edit.text.strip_edges(), Worlds.RACES[race_pick.selected].id,
		Worlds.DIFFICULTIES[_index(diff_buttons)].id, Worlds.WORLDS[_index(world_buttons)].id)
