extends Node3D
## The dock: where a saved game rests between jobs. It is the way into the shipyard (ship builder),
## which only exists at a yard, so which one you reach depends on your starting world.
## Freight contracts can be accepted, loaded, departed and delivered here while physical flight is built.

var camera: Camera3D
var centre := Vector3.ZERO
var orbit := 0.0
var fade: ColorRect
var status: Label
var contract_panel: PanelContainer
var contract_list: VBoxContainer
var depart_btn: Button
var deliver_btn: Button
var wait_btn: Button
var helm_btn: Button
var fly_btn: Button
var run_btn: Button
var fly_panel: PanelContainer
var fly_list: VBoxContainer
var side: PanelContainer      ## right-hand panel that shows the freight board or the fly-empty list
var card: PanelContainer      ## the "about this system" card, hidden while the side panel is open
var leaving := false
const SIDE_LEFT := 470.0      ## where the side panel starts, clear of the menu buttons


func _ready() -> void:
	if Session.slot >= 0:
		Session.profile["location"] = "dock"
		Session.save_profile()
	_build_world()
	_build_ui()
	GameSettings.apply_scene(self, 90.0)


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
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 72)
	margin.add_theme_constant_override("margin_top", 56)
	margin.add_theme_constant_override("margin_bottom", 40)
	layer.add_child(margin)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var left_scroll := ScrollContainer.new()   # a short window scrolls the column instead of cutting it off
	left_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	left_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER   # the wheel scrolls it; no bar across the ship
	left_scroll.follow_focus = true   # keyboard focus on a button below the fold scrolls it into view
	margin.add_child(left_scroll)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_scroll.add_child(col)

	var w := Worlds.world(Session.system_id())
	var current_port := Session.port()
	var where := Label.new()
	where.text = String(current_port.get("name", w.name)).to_upper()
	where.add_theme_font_size_override("font_size", 40)
	where.add_theme_color_override("font_color", Brand.OFFWHITE)
	col.add_child(where)
	var yard := Label.new()
	yard.text = "%s  ·  %s" % [String(Session.system_id()).replace("_", " ").capitalize(), String(current_port.get("type", "port")).replace("_", " ").capitalize()]
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
	_row(grid, "Captain", "%s, %s" % [p.name, Worlds.species(p.species).name])
	_row(grid, "Ship", Session.ship_label())
	_row(grid, "Credits", "%s cr" % ShipStats.commas(int(p.credits)))
	_row(grid, "Difficulty", Worlds.difficulty(p.difficulty).name)
	if Session.sim != null:
		_row(grid, "Day", str(Session.day()))
		if int(p.get("bankruptcies", 0)) > 0:
			_row(grid, "Bankruptcies", str(int(p.bankruptcies)))
		var runway := SimWorld.runway_days(Session.sim)
		_row(grid, "Running costs", "%s cr/day  ·  cash lasts %s" % [ShipStats.commas(roundi(SimWorld.daily_cost(Session.sim))),
				"over a year" if runway > 365 else "%d days" % runway])
		var pay: Array[String] = []
		for r in SimWorld.payroll_lines(Session.sim):
			pay.append("%s %s" % [String(r.role).get_slice(" (", 0), ShipStats.commas(roundi(r.pay))])
		if _sublight():
			var price := Session.drive_price()
			_row(grid, "FTL drive", "not fitted  ·  drive and radiator cost about %s cr  ·  %s" % [ShipStats.commas(price),
					"you can afford it" if int(p.credits) >= price else "%s cr to save" % ShipStats.commas(price - int(p.credits))])
		_row(grid, "Crew pay", "%s cr/day  ·  %s rates" % [", ".join(pay), String(Session.sim.carriers[SimWorld.PLAYER]["home"]).replace("_", " ").capitalize()])
	if Session.insolvent():
		var broke := Brand.note("INSOLVENT. Your cash is gone and the bank is taking the ship. This run is over: start a new game from the main menu.", 16)
		broke.add_theme_color_override("font_color", Color(0.95, 0.4, 0.3))
		broke.custom_minimum_size = Vector2(440, 0)
		col.add_child(broke)
		var rep := Session.run_report()
		var recap := Brand.note("Your run: %d days, %d jobs, %.0f t hauled. Freight paid %s cr, running costs %s cr." % [int(rep.days), int(rep.jobs), float(rep.tonnes),
				ShipStats.commas(roundi(float(rep.revenue))), ShipStats.commas(roundi(float(rep.costs)))], 15)
		recap.custom_minimum_size = Vector2(440, 0)
		col.add_child(recap)
		var offer := Brand.note("Or let the bank step in: it takes the ship at half price, clears your debt and lends you a starter hauler with ten days of running costs. It goes on your record.", 15)
		offer.custom_minimum_size = Vector2(440, 0)
		col.add_child(offer)
	elif Session.sim != null and SimWorld.runway_days(Session.sim) < 7 and Session.active_contract().is_empty():
		var warn := Brand.note("Cash covers less than a week of running costs. Take freight now.", 15)
		warn.add_theme_color_override("font_color", Brand.AMBER)
		col.add_child(warn)
	col.add_child(_gap(10))

	var menu := VBoxContainer.new()
	menu.add_theme_constant_override("separation", 8)
	menu.custom_minimum_size = Vector2(340, 0)
	menu.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	col.add_child(menu)
	_button(menu, "STEP AWAY FROM THE TERMINAL", func() -> void: _go(Session.PLACE_SCENE)).tooltip_text = "Back to walking the station, base or camp."
	if Session.insolvent():
		_button(menu, "LET THE BANK STEP IN", _restructure)
	var yard_btn := _button(menu, "ENTER SHIPYARD", _enter_yard)
	_button(menu, "CONTRACT BOARD", _show_contracts)
	depart_btn = _button(menu, "DEPART", _depart)
	deliver_btn = _button(menu, "DELIVER FREIGHT", _deliver)
	helm_btn = _button(menu, "TAKE THE HELM", _take_helm)
	helm_btn.tooltip_text = "Fly the ship in free flight around the dock. No time passes and nothing is lost: it is practice until star jumps arrive."
	wait_btn = _button(menu, "WAIT A DAY", _wait_day)
	fly_btn = _button(menu, "FLY EMPTY", _show_destinations)
	wait_btn.tooltip_text = "Let a day pass. The rest of the economy keeps moving; your crew and ship still cost money."
	fly_btn.tooltip_text = "Fly without cargo to another system, to reach freight or leave a port with none."
	var finds := Session.finds_aboard() if Session.slot >= 0 else {}
	if int(finds.get("value", 0)) > 0:
		_button(menu, "SELL FINDS  %s cr" % ShipStats.commas(int(finds.value)), _sell_finds).tooltip_text = "%s from the moon, sold here." % SurfaceFinds.describe(finds).capitalize()
	_button(menu, "SAVE GAME", _save)
	_button(menu, "NEW GAME" if Session.insolvent() else "MAIN MENU", _main_menu)
	status = Label.new()
	status.add_theme_color_override("font_color", Brand.MUTED)
	status.add_theme_font_size_override("font_size", 13)
	col.add_child(status)
	yard_btn.tooltip_text = "The shipyard is where you build and fit your ship. It is only open at a yard like this one."
	# The freight board and the fly-empty list open in a scrolling panel on the right, so they are on
	# screen however long the menu is.
	side = PanelContainer.new()
	side.visible = false
	var solid := Brand.panel_box().duplicate() as StyleBoxFlat
	solid.bg_color.a = 1.0      # solid, so the dock text behind does not show through
	side.add_theme_stylebox_override("panel", solid)
	layer.add_child(side)
	side.set_anchors_preset(Control.PRESET_FULL_RECT)
	side.offset_left = SIDE_LEFT
	side.offset_top = 40
	side.offset_right = -40
	side.offset_bottom = -40
	var side_scroll := ScrollContainer.new()
	side_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	side.add_child(side_scroll)
	var side_col := VBoxContainer.new()
	side_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	side_scroll.add_child(side_col)
	contract_panel = PanelContainer.new()
	contract_panel.visible = false
	contract_panel.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	side_col.add_child(contract_panel)
	contract_list = VBoxContainer.new()
	contract_list.add_theme_constant_override("separation", 4)
	contract_panel.add_child(contract_list)
	fly_panel = PanelContainer.new()
	fly_panel.visible = false
	fly_panel.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	side_col.add_child(fly_panel)
	fly_list = VBoxContainer.new()
	fly_list.add_theme_constant_override("separation", 4)
	fly_panel.add_child(fly_list)
	var note := Brand.note("The shipyard is where you build and fit your ship. It is only open at a yard like this one.")
	note.custom_minimum_size = Vector2(380, 0)
	col.add_child(note)

	card = PanelContainer.new()
	card.add_theme_stylebox_override("panel", Brand.panel_box())
	layer.add_child(card)
	layer.move_child(card, side.get_index())   # under the side panel
	card.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT, Control.PRESET_MODE_MINSIZE, 40)
	card.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	card.grow_vertical = Control.GROW_DIRECTION_BEGIN
	var info := VBoxContainer.new()
	info.add_theme_constant_override("separation", 6)
	info.custom_minimum_size = Vector2(400, 0)
	card.add_child(info)
	info.add_child(Brand.heading("ABOUT " + String(w.name).to_upper()))
	info.add_child(Brand.note(w.blurb, 15))
	info.add_child(Brand.note("Sells: %s.\nNeeds: %s." % [_few(w.exports), _few(w.imports)], 14))
	if not w.neighbours.is_empty():
		info.add_child(Brand.note("Direct routes to %s." % ", ".join(PackedStringArray(w.neighbours)), 14))
	_refresh_actions()
	if Session.flash != "":
		status.text = Session.flash
		Session.flash = ""
	yard_btn.grab_focus()
	if Session.insolvent():
		yard_btn.disabled = true

	fade = ColorRect.new()
	fade.color = Color(0, 0, 0, 1)
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fl := CanvasLayer.new()
	fl.layer = 100
	add_child(fl)
	fl.add_child(fade)
	fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	create_tween().tween_property(fade, "color:a", 0.0, 0.5)


static func _few(list: Array) -> String:
	return ", ".join(PackedStringArray(list.slice(0, 3)))


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


func _site_name(port_id: String, fallback: String = "") -> String:
	var real := Worlds.port(port_id)
	if not real.is_empty():
		return String(real.get("name", fallback))
	return String(LocalSpace.node(port_id).get("name", fallback))


func _sublight() -> bool:
	return Session.sim != null and not bool(SimWorld.player(Session.sim).get("ftl", true))


func _show_contracts() -> void:
	if Session.insolvent():
		status.text = "No one will give a bankrupt captain freight."
		return
	contract_panel.visible = not contract_panel.visible
	fly_panel.visible = false
	_sync_side()
	for child in contract_list.get_children():
		child.queue_free()
	if not contract_panel.visible:
		return
	var system_id := Session.system_id()
	var port := Session.port()
	var heading := Brand.heading("FREIGHT BOARD — %s" % String(port.get("name", system_id)).to_upper(), 15)
	contract_list.add_child(heading)
	var offers := Contracts.offers_from(system_id)
	if _sublight():
		contract_list.add_child(Brand.note("No FTL drive fitted: you can only haul inside this system. Fit a drive in the shipyard to take freight between stars.", 14))
	if offers.is_empty():
		contract_list.add_child(Brand.note("No profitable freight is posted here right now."))
		return
	var active := Session.active_contract()
	if not active.is_empty():
		contract_list.add_child(Brand.note("ACTIVE: %s — %.1f t loaded for %s" % [active.title, float(active.accepted_tonnes), _site_name(String(active.destination_port_id), "its destination")]))
		return
	var board_ship := _ship_for_board()
	var board_stats := Session.ship_stats(board_ship) if board_ship != null else {}
	for c in offers:
		var goods := Worlds.commodity(String(c.commodity))
		var line := Button.new()
		if bool(c.get("local", false)) and not board_stats.is_empty():
			var trip := Session.local_trip_cost(board_stats, float(c.offer), float(c.dv_kms))
			var lands := String(LocalSpace.node(String(c.destination_port_id)).get("kind", "")) == "moon" and float(board_stats.get("lift", 0.0)) > 0.0
			line.text = (("SURFACE  %s" if bool(c.get("surface", false)) else "LOCAL  %s") + "  →  %s\n%.1f t  ·  %.1f km/s  ·  %d h  ·  %s cr/t  ·  up to %s cr, fuel about %s cr" + ("  ·  +%d%% if you land it" % roundi(float(SurfaceTerrain.config().get("surface_bonus", 0.25)) * 100.0) if lands else "") + "\nACCEPT & LOAD") % [
				goods.name, _site_name(String(c.destination_port_id)), float(c.offer), float(c.dv_kms), int(c.hours),
				ShipStats.commas(int(c.rate)), ShipStats.commas(roundi(float(c.offer) * float(c.rate))), ShipStats.commas(roundi(float(trip.total)))]
		else:
			var destination := Worlds.port(String(c.destination_port_id))
			line.text = "%s  →  %s\n%.1f t available  ·  %.2f ly  ·  %s cr/t  ·  up to %s cr%s\nACCEPT & LOAD" % [
				goods.name, destination.get("name", c.destination_system_id), float(c.offer), float(c.distance_ly),
				ShipStats.commas(int(c.rate)), ShipStats.commas(roundi(float(c.offer) * float(c.rate))),
				"  ·  due in %.0f days" % float(c.deadline_days) if c.has("sim_contract") else ""]
		Brand.style_button(line, 14)
		line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		line.pressed.connect(func() -> void: _accept(c))
		contract_list.add_child(line)


## One panel at a time on the right; the system card shows when neither is open.
func _sync_side() -> void:
	side.visible = contract_panel.visible or fly_panel.visible
	card.visible = not side.visible


func _accept(c: Dictionary) -> void:
	var result := Session.accept_contract(c)
	status.text = result.message
	_refresh_actions()
	if bool(result.ok):
		_show_contracts()
		_show_contracts()


func _ship_for_board() -> ShipData:
	var loaded := Session._load_ship(SaveSlots.read(Session.slot))
	return loaded.ship if not loaded.is_empty() else null


func _refresh_actions() -> void:
	if depart_btn == null or deliver_btn == null:
		return
	var c := Session.active_contract()
	if wait_btn != null:
		var idle := c.is_empty() and Session.sim != null and not Session.insolvent()
		wait_btn.disabled = not idle
		helm_btn.disabled = Session.insolvent()
		fly_btn.disabled = not idle
		if _sublight():
			fly_btn.tooltip_text = "Fly without cargo to another site in this system, to reach better jobs."
	var site := String(Session.profile.get("port_id", ""))
	if run_btn != null:
		var local := bool(c.get("local", false))
		run_btn.visible = not c.is_empty()
		run_btn.text = "FLY THE RUN" if local else "FLY THE JUMP"
		var at_start := String(c.get("origin_port_id", "")) == site if local else String(c.get("origin_system_id", "")) == Session.system_id()
		run_btn.disabled = c.is_empty() or not at_start or String(c.get("status", "")) == "arrived"
	depart_btn.text = "DEPART ON A HARD BURN" if c.has("due_hour") else "DEPART"
	if bool(c.get("local", false)):
		depart_btn.disabled = String(c.get("origin_port_id", "")) != site or String(c.get("status", "")) == "arrived"
		deliver_btn.disabled = String(c.get("destination_port_id", "")) != site or String(c.get("status", "")) != "arrived"
		return
	depart_btn.disabled = c.is_empty() or String(c.get("origin_system_id", "")) != Session.system_id()
	deliver_btn.disabled = c.is_empty() or String(c.get("destination_system_id", "")) != Session.system_id()


func _restructure() -> void:
	var result := Session.restructure()
	status.text = result.message
	if bool(result.ok):
		get_tree().reload_current_scene()


func _take_helm() -> void:
	Session.flight_job = {}   # practice flight, not a run
	_go(Session.FLIGHT_SCENE)


func _wait_day() -> void:
	var result := Session.wait_days(1)
	status.text = result.message
	if bool(result.ok):
		get_tree().reload_current_scene()


func _show_destinations() -> void:
	fly_panel.visible = not fly_panel.visible
	contract_panel.visible = false
	_sync_side()
	for child in fly_list.get_children():
		child.queue_free()
	if not fly_panel.visible or Session.sim == null:
		return
	if _sublight():
		_show_sites()
		return
	fly_list.add_child(Brand.heading("FLY EMPTY — NEAREST FIRST", 15))
	var options := SimWorld.destinations(Session.sim)
	if options.is_empty():
		fly_list.add_child(Brand.note("No other system is within reach of your tanks."))
		return
	fly_list.add_child(Brand.note("You pay fuel, port fees, crew and ship costs for the trip and earn nothing until you load freight."))
	for o in options.slice(0, 8):
		var sid: String = o.system_id
		var line := Button.new()
		line.text = "%s\n%.2f ly  ·  %.1f days  ·  about %s cr  ·  %s" % [Worlds.system(sid).get("name", sid), float(o.ly), float(o.days),
				ShipStats.commas(roundi(float(o.cost))), "%d freight posted" % int(o.freight) if int(o.freight) > 0 else "no freight posted"]
		Brand.style_button(line, 14)
		line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		line.pressed.connect(func() -> void: _fly(sid))
		fly_list.add_child(line)


func _show_sites() -> void:
	fly_list.add_child(Brand.heading("FLY EMPTY — SITES IN THIS SYSTEM", 15))
	var sites := Session.local_sites()
	if sites.is_empty():
		fly_list.add_child(Brand.note("Nowhere else in this system is within reach of your tanks."))
		return
	fly_list.add_child(Brand.note("You pay fuel, a berth fee and running costs and earn nothing until you load a job there.", 14))
	for o in sites:
		var sid: String = o.id
		var line := Button.new()
		line.text = "%s\n%.1f km/s  ·  %d h  ·  about %s cr  ·  %s" % [o.name, float(o.dv_kms), int(o.hours), ShipStats.commas(roundi(float(o.cost))),
				"%d jobs posted" % int(o.jobs) if int(o.jobs) > 0 else "no jobs posted"]
		Brand.style_button(line, 14)
		line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		line.pressed.connect(func() -> void: _hop(sid))
		fly_list.add_child(line)


func _hop(site_id: String) -> void:
	var result := Session.local_reposition(site_id)
	status.text = result.message
	if bool(result.ok):
		get_tree().reload_current_scene()


func _fly(system_id: String) -> void:
	var result := Session.travel_empty(system_id)
	status.text = result.message
	if bool(result.ok):
		get_tree().reload_current_scene()


func _fly_run() -> void:
	var c := Session.active_contract()
	var r := Session.begin_local_flight() if bool(c.get("local", false)) else Session.begin_jump_flight()
	if bool(r.ok):
		_go(Session.FLIGHT_SCENE)
	else:
		status.text = r.message


func _depart() -> void:
	var result := Session.depart_active_contract(Session.active_contract().has("due_hour"))   # a rush goes on a hard burn
	status.text = result.message
	if bool(result.ok):
		get_tree().reload_current_scene()
	else:
		_refresh_actions()


func _deliver() -> void:
	var result := Session.deliver_active_contract()
	status.text = result.message
	if bool(result.ok):
		get_tree().reload_current_scene()
	else:
		_refresh_actions()


func _enter_yard() -> void:
	Session.profile["location"] = "shipyard"
	Session.save_profile()
	_go(Session.YARD_SCENE)


func _sell_finds() -> void:
	var r := Session.sell_finds()
	status.text = r.message
	if bool(r.ok):
		Session.flash = String(r.message)
		get_tree().reload_current_scene()


func _save() -> void:
	status.text = "Saved to slot %d" % (Session.slot + 1) if Session.save_profile() else "Not part of a saved game, so nothing was saved"


func _main_menu() -> void:
	Session.save_profile()
	Session.skip_intro = true
	_go(Session.BOOT_SCENE)
