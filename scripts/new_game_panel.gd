class_name NewGamePanel
extends PanelContainer
## Choices for a new game: name, species, difficulty, starting yard and which slot to save in.
## Species and systems come from data/world/ (see Worlds). The yard list can also be loaded from canonical data.

signal begin(slot: int, player_name: String, species_id: String, difficulty: String, world_id: String)
signal back

var name_edit: LineEdit
var species_pick: OptionButton
var species_note: Label
var species_list: Array = []
var diff_buttons: Array[Button] = []
var diff_note: Label
var world_buttons: Array[Button] = []
var world_ids: Array = []
var world_note: Label
var slot_buttons: Array[Button] = []
var slot_note: Label
var begin_btn: Button
var starting_yards: Array = []


func _init() -> void:
	var box := Brand.panel_box()
	box.content_margin_top = 10
	box.content_margin_bottom = 12
	add_theme_stylebox_override("panel", box)
	species_list = Worlds.species_list()
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 5)
	add_child(col)
	col.add_child(Brand.heading("NEW GAME", 18))

	col.add_child(Brand.heading("NAME"))
	name_edit = LineEdit.new()
	name_edit.text = "Ren Calloway"
	name_edit.max_length = 24
	name_edit.placeholder_text = "Your name"
	name_edit.custom_minimum_size = Vector2(320, 32)
	name_edit.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	name_edit.text_changed.connect(func(_t: String) -> void: _refresh())
	col.add_child(name_edit)

	col.add_child(Brand.heading("SPECIES"))
		species_pick = OptionButton.new()
		species_pick.custom_minimum_size = Vector2(200, 32)
		species_pick.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		for s in species_list:
			species_pick.add_item(s.name)
		species_pick.item_selected.connect(func(_i: int) -> void: _on_species())
		col.add_child(species_pick)
		species_note = Brand.note("")
		species_note.custom_minimum_size = Vector2(560, 48)
		col.add_child(species_note)

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

		col.add_child(Brand.heading("STARTING YARD"))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	col.add_child(grid)
	var wgroup := ButtonGroup.new()
		starting_yards = Worlds.starting_yards()
		for y in starting_yards:
			var b := Brand.toggle(y.name, wgroup)
		b.custom_minimum_size = Vector2(250, 0)
		b.pressed.connect(_refresh)
		grid.add_child(b)
		world_buttons.append(b)
	if not world_buttons.is_empty():
		world_buttons[0].button_pressed = true
	world_note = Brand.note("")
	world_note.custom_minimum_size = Vector2(560, 64)
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
	_update_starts()
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


func selected_species() -> Dictionary:
	return species_list[species_pick.selected]


func selected_world_id() -> String:
	return world_ids[_index(world_buttons)]


## The first starting place is always the species' own home system, so it changes with the species.
func _on_species() -> void:
	_update_starts()
	_refresh()


func _update_starts() -> void:
	var sp := selected_species()
	world_ids = Worlds.start_ids(sp.id)
	for i in world_buttons.size():
		var w := Worlds.world(world_ids[i])
		world_buttons[i].text = "%s%s" % [w.name, "  (home)" if i == 0 else ""]


func _refresh() -> void:
	var sp := selected_species()
	var strengths := ", ".join(PackedStringArray(sp.strengths.slice(0, 3)))
	var home: String = sp.homeworld if sp.homeworld == sp.home_system else "%s, %s" % [sp.homeworld, sp.home_system]
	species_note.text = "Home: %s%s. %s Known for %s." % [home, (", " + sp.gravity + " gravity") if sp.gravity != "" else "", sp.identity, strengths]
	diff_note.text = Worlds.DIFFICULTIES[_index(diff_buttons)].blurb
		if starting_yards.is_empty():
			var w := Worlds.world(selected_world_id())
			world_note.text = "Yard: %s, at %s. Population %s.\n%s Sells %s; needs %s." % [w.yard_name, w.yard_at,
				w.population, w.blurb, _few(w.exports), _few(w.imports)]
		else:
			var y: Dictionary = starting_yards[_index(world_buttons)]
			var tier := Worlds.yard_tier(String(y.tier))
			var service: Dictionary = y.get("service", {})
			world_note.text = "%s — %s / %s. %s. Largest build: %s. Build %.0f%%, repair %.0f%% of baseline.\n%s" % [
				y.name, y.system_id, y.destination_id, tier.get("name", y.tier),
				String(y.largest_hull_class).replace("_", " "),
				float(service.get("build_price_multiplier", 1.0)) * 100.0,
				float(service.get("repair_price_multiplier", 1.0)) * 100.0,
				y.narrative,
			]
	var s := selected_slot()
	if SaveSlots.exists(s):
		var p := SaveSlots.profile(s)
		slot_note.text = "Slot %d already holds %s's game. Starting here moves that save aside; it is not deleted." % [s + 1, p.name]
		slot_note.add_theme_color_override("font_color", Brand.AMBER)
	else:
		slot_note.text = "Slot %d is empty." % (s + 1)
		slot_note.add_theme_color_override("font_color", Brand.MUTED)
	begin_btn.disabled = name_edit.text.strip_edges() == ""


static func _few(list: Array) -> String:
	return ", ".join(PackedStringArray(list.slice(0, 3)))


func _on_begin() -> void:
		if starting_yards.is_empty():
			begin.emit(selected_slot(), name_edit.text.strip_edges(), selected_species().id,
				Worlds.DIFFICULTIES[_index(diff_buttons)].id, selected_world_id())
			return
		begin.emit(selected_slot(), name_edit.text.strip_edges(), selected_species().id,
			Worlds.DIFFICULTIES[_index(diff_buttons)].id, starting_yards[_index(world_buttons)].id)
