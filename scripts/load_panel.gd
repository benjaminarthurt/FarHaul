class_name LoadPanel
extends PanelContainer
## Lists the five save slots. Choosing a filled slot loads it.

signal chosen(slot: int)
signal back

var rows: Array[Button] = []


func _init() -> void:
	add_theme_stylebox_override("panel", Brand.panel_box())
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	add_child(col)
	col.add_child(Brand.heading("LOAD GAME", 18))
	for i in SaveSlots.COUNT:
		var b := Button.new()
		Brand.style_button(b, 15)
		b.custom_minimum_size = Vector2(520, 62)
		b.pressed.connect(func() -> void: chosen.emit(i))
		col.add_child(b)
		rows.append(b)
	var back_btn := Button.new()
	back_btn.text = "BACK"
	Brand.style_button(back_btn, 18)
	back_btn.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	back_btn.custom_minimum_size = Vector2(160, 0)
	back_btn.pressed.connect(func() -> void: back.emit())
	col.add_child(back_btn)
	refresh()


## One short description of a save for lists: who, where, which ship, how much money.
static func describe(slot: int) -> String:
	if not SaveSlots.exists(slot):
		return "SLOT %d\nEmpty" % (slot + 1)
	var p := SaveSlots.profile(slot)
	var when := ""
	if int(p.saved_at) > 0:
		when = "   " + Time.get_datetime_string_from_unix_time(int(p.saved_at), true).substr(0, 16)
	var where := "In the shipyard" if p.location == "shipyard" else "Docked"
	return "SLOT %d   %s, %s%s\n%s at %s   ·   %s   ·   %s cr" % [
		slot + 1, p.name, Worlds.species(p.get("species", p.get("race", "human"))).name, when,
		where, Worlds.world(p.world).name, Session.ship_label_for(p), ShipStats.commas(int(p.credits))]


func refresh() -> void:
	for i in rows.size():
		rows[i].text = describe(i)
		rows[i].disabled = not SaveSlots.exists(i)
