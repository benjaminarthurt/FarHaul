class_name Boarding
extends RefCounted
## Going aboard a derelict, from a space walk (OnFoot): in through the airlock door you cut open, on mag
## boots and suit air, with the suit lamp and the emergency lights. Its rooms are built from its layout
## (ShipView, powered down) and walked like your own ship (ShipWalk). What's aboard comes from Wreckage:
## the log at the helm, the flight recorder, loose crates and lockers, the crew who didn't make it and,
## now and then, one who did. One thing in hand at a time (SpaceWalk.carry); out through the airlock you go
## back to drifting, and your own hatch stows it (Salvage.stow).
## The space walk (sc.eva) carries on underneath: the air is the suit's, and the tether waits at their door.

var sc: FlightScene
var active := false
var derelict: Dictionary = {}   ## Traffic's derelict being walked
var contents: Dictionary = {}   ## Wreckage.roll for it
var walk: ShipWalk
var view: ShipView              ## the wreck's rooms, child of its body
var items: Array = []           ## [{id, item, pos (wreck frame), node, taken}]
var reading := false            ## the log is up
var message := ""
var message_t := 0.0
var _lamp: SpotLight3D
var _lights: Array[OmniLight3D] = []
var _t := 0.0
var _log_panel: PanelContainer
var _log_label: Label
var _ambient_was := -1.0
var _sun_was := -1.0


func _init(scene: FlightScene) -> void:
	sc = scene


static func cfg() -> Dictionary:
	return Wreckage.cfg()


func ship() -> NpcShip:
	return derelict.get("ship", null)


## Through the cut door of `d` (a Traffic derelict). Returns "" or why not.
func enter(d: Dictionary) -> String:
	var s: NpcShip = d.get("ship", null)
	if s == null or sc.eva == null:
		return "Nothing to go into."
	if sc.eva.carrying > 0:
		return "Hands full. Take that home first."
	derelict = d
	var base := String(d.get("id_base", s.title))
	contents = Wreckage.roll(s.ship, _ship_name(d), bool(d.get("deep", false)), base)
	view = ShipView.new()
	view.name = "Aboard"
	s.body.add_child(view)
	view.rebuild(s.ship)
	var kids := view.get_children()
	for i in mini(s.ship.modules.size(), kids.size()):
		if not s.ship.library.get_def(s.ship.modules[i].id).pressurized:
			(kids[i] as Node).queue_free()   # outside parts are outside; the hull already has them
	view.set_interior(true)
	_power_down(view)
	walk = ShipWalk.build(s.ship, view)
	walk.stand_in_airlock()
	_place_items(base)
	_lamp = SpotLight3D.new()
	_lamp.light_energy = 5.0
	_lamp.spot_range = 18.0
	_lamp.spot_angle = 38.0
	_lamp.spot_attenuation = 0.8
	_lamp.light_color = Color(1.0, 0.95, 0.85)
	sc.camera.add_child(_lamp)
	for i in s.ship.modules.size():   # the emergency lights, on what's left in the batteries
		var def := s.ship.library.get_def(s.ship.modules[i].id)
		if not def.pressurized:
			continue
		var l := OmniLight3D.new()
		l.light_color = Color(1.0, 0.18, 0.12)
		l.light_energy = 0.5
		l.omni_range = 4.5
		l.position = ShipGrid.cell_to_world(s.ship.modules[i].cell) + Vector3(0, ShipGrid.CELL * 0.35, 0)
		view.add_child(l)
		_lights.append(l)
	_build_log_panel()
	if sc.world_env != null:   # it's dark in here: only the lamp, the emergency lights and the windows
		_ambient_was = sc.world_env.ambient_light_energy
		sc.world_env.ambient_light_energy = 0.0
	if sc.sun != null:
		_sun_was = sc.sun.light_energy
		sc.sun.light_energy = _sun_was * 0.1
	active = true
	reading = false
	_say("Inside the %s. No power, no air, no gravity: the boots hold you to the deck. Your air's still ticking." % _ship_name(d))
	return ""


static func _ship_name(d: Dictionary) -> String:
	var nm := String(d.get("name", "wreck"))
	for p in ["the ", "an ", "a "]:
		nm = nm.trim_prefix(p)
	return nm.capitalize() if nm == nm.to_lower() else nm


## Back out through their airlock, onto the space walk, outside their door.
func leave() -> void:
	if not active:
		return
	active = false
	reading = false
	var s := ship()
	var e := sc.eva
	if e != null and s != null and is_instance_valid(s):
		var out := -walk.airlock_face
		var door := walk.airlock + Vector3(0, 1.6, 0) + out * (ShipGrid.CELL * 0.5 + ShipSkin.GAP + ShipSkin.T + 1.0)
		var to_view := sc.view.global_transform.affine_inverse()
		e.pos = to_view * (s.body.global_transform * door)
		e.vel = Vector3.ZERO
		e.face((to_view.basis * (s.body.global_basis * out)).normalized())
	_clear()


func _clear() -> void:
	if _ambient_was >= 0.0 and sc.world_env != null:
		sc.world_env.ambient_light_energy = _ambient_was
	if _sun_was >= 0.0 and sc.sun != null:
		sc.sun.light_energy = _sun_was
	_ambient_was = -1.0
	_sun_was = -1.0
	if _lamp != null and is_instance_valid(_lamp):
		_lamp.queue_free()
	_lamp = null
	if view != null and is_instance_valid(view):
		view.queue_free()
	view = null
	_lights.clear()
	items.clear()
	if _log_panel != null and is_instance_valid(_log_panel):
		_log_panel.queue_free()
	_log_panel = null


## Lights out: nothing glows that needs power.
func _power_down(node: Node) -> void:
	if node is OmniLight3D and node.has_meta("interior_light"):
		(node as OmniLight3D).visible = false
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		var mat: Material = mi.material_override
		if mat == null and mi.mesh != null and mi.mesh.get_surface_count() > 0:
			mat = mi.mesh.surface_get_material(0)
		if mat is StandardMaterial3D and (mat as StandardMaterial3D).emission_enabled:
			var m := (mat as StandardMaterial3D).duplicate() as StandardMaterial3D
			m.emission_enabled = false
			m.albedo_color = m.albedo_color.darkened(0.5)
			mi.material_override = m
	for c in node.get_children():
		_power_down(c)


# --- What's aboard -------------------------------------------------------------------------------

const SPOTS := [Vector2(0.0, 0.0), Vector2(0.75, 0.6), Vector2(-0.75, 0.6), Vector2(0.75, -0.6), Vector2(-0.75, -0.6), Vector2(0.0, 0.9), Vector2(0.0, -0.9)]


func _place_items(base: String) -> void:
	items.clear()
	var taken: Array = Session.profile.get("salvage_taken", []) if Session.slot >= 0 else []
	var used := {}
	var list: Array = contents.get("items", [])
	for k in list.size():
		var it: Dictionary = list[k]
		var id := "%s|in|%d" % [base, k]
		if id in taken or _carried_id() == id:
			continue
		var p := _spot_in(int(it.at), int(it.slot), used)
		if p == Vector3.INF:
			continue
		var node := _item_node(it, k)
		node.position = p
		view.add_child(node)
		items.append({"id": id, "item": it, "pos": p, "node": node})


func _carried_id() -> String:
	return String(sc.eva.carrying_id) if sc.eva != null else ""


## A free spot on the deck of module `mi`, preferring its `slot`th spot.
func _spot_in(mi: int, slot: int, used: Dictionary) -> Vector3:
	var cells := []
	for c in walk.cells:
		if int(walk.cells[c]) == mi:
			cells.append(c)
	if cells.is_empty():
		for c in walk.cells:
			cells.append(c)
	cells.sort()
	for k in cells.size() * SPOTS.size():
		var c: Vector3i = cells[(slot + k) % cells.size()]
		var o: Vector2 = SPOTS[(slot + k / cells.size()) % SPOTS.size()]
		var p := ShipGrid.cell_to_world(c) + Vector3(o.x, 0, o.y)
		p.y = ShipWalk.deck_y(c.y)
		var key := "%.1f,%.1f,%.1f" % [p.x, p.y, p.z]
		if used.has(key):
			continue
		used[key] = true
		return p
	return Vector3.INF


func _item_node(it: Dictionary, k: int) -> Node3D:
	var root := Node3D.new()
	var box := func(size: Vector3, at: Vector3, col: Color, glow := 0.0) -> void:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = size
		var m := StandardMaterial3D.new()
		m.albedo_color = col
		m.roughness = 0.8
		if glow > 0.0:
			m.emission_enabled = true
			m.emission = col
			m.emission_energy_multiplier = glow
		bm.material = m
		mi.mesh = bm
		mi.position = at
		root.add_child(mi)
	match String(it.kind):
		"crate":
			box.call(Vector3(0.9, 0.7, 0.7), Vector3(0, 0.35, 0), Salvage.clib().color(StringName(String(it.commodity))).darkened(0.15))
			box.call(Vector3(0.92, 0.08, 0.72), Vector3(0, 0.55, 0), Color(1.0, 0.75, 0.2), 0.25)
		"supplies":
			box.call(Vector3(0.6, 1.5, 0.4), Vector3(0, 0.75, 0), Color(0.3, 0.55, 0.35))
			box.call(Vector3(0.62, 0.08, 0.42), Vector3(0, 1.2, 0), Color(1.0, 0.75, 0.2), 0.25)
		"recorder":
			box.call(Vector3(0.6, 0.5, 0.5), Vector3(0, 0.25, 0), Color(1.0, 0.45, 0.1))
			box.call(Vector3(0.62, 0.06, 0.52), Vector3(0, 0.4, 0), Color(1.0, 0.85, 0.4), 0.8)
		"body":   # a sealed bag on the deck, laid out with care
			var mi := MeshInstance3D.new()
			var cm := CapsuleMesh.new()
			cm.radius = 0.24
			cm.height = 1.8
			var m := StandardMaterial3D.new()
			m.albedo_color = Color(0.16, 0.17, 0.19)
			m.roughness = 0.6
			cm.material = m
			mi.mesh = cm
			mi.rotation = Vector3(0, float(k) * 0.7, PI * 0.5)
			mi.position = Vector3(0, 0.24, 0)
			root.add_child(mi)
		"survivor":
			var f := Figure.make(Color(0.85, 0.5, 0.15), absi(hash(String(it.name))), true, String(it.get("species", "")))
			root.add_child(f)
	return root


## The item within reach of the walker, or {}.
func nearest() -> Dictionary:
	if walk == null:
		return {}
	var reach := float(cfg().get("reach_m", 1.7))
	var best := {}
	var best_d := INF
	for e in items:
		var p: Vector3 = e.pos
		if roundi((p.y - Interiors.FLOOR) / ShipGrid.CELL) != walk.level():
			continue
		var d := Vector2(p.x - walk.pos.x, p.z - walk.pos.z).length()
		if d <= reach and d < best_d:
			best = e
			best_d = d
	return best


## L at the helm: the log, up or down.
func read_log() -> String:
	if not active:
		return ""
	if reading:
		reading = false
		_log_panel.visible = false
		return "closed"
	if not walk.near_helm():
		return ""
	reading = true
	_log_label.text = "\n".join(PackedStringArray(contents.get("log", [])))
	_log_panel.visible = true
	return "reading"


## E aboard: leave by the airlock, take what's in reach, or read the log at the helm. Returns what happened.
func use() -> String:
	if not active:
		return ""
	if reading:
		reading = false
		_log_panel.visible = false
		return "closed"
	if walk.near_airlock():
		leave()
		sc.foot_c._eva_say("Back outside the %s. Your own hatch is where you left it." % _ship_name(derelict) if sc.eva.carrying <= 0 else "Out of the %s with %s. Now the hard part: the trip home." % [_ship_name(derelict), Salvage.describe(sc.eva.carry)])
		return "left"
	var it := nearest()
	if not it.is_empty():
		return take(it)
	if walk.near_helm():
		return read_log()
	return ""


## Pick up item entry `e` (from `items`).
func take(e: Dictionary) -> String:
	var it: Dictionary = e.item
	if sc.eva.carrying > 0:
		_say("Your hands are full. One thing at a time; there's a lot of dark between here and home.")
		return "full"
	var why := Salvage.room_for(it)
	if why != "" and String(it.kind) == "survivor":   # nobody's left behind for want of a bed
		_say(PortAuthority.report(it))
		var taken: Array = (Session.profile.get("salvage_taken", []) as Array).duplicate()
		taken.append(String(e.id))
		Session.profile["salvage_taken"] = taken
		Session.save_profile()
		items.erase(e)
		return "reported"
	if why != "":
		_say(why)
		return "room"
	sc.eva.carry = it.duplicate()
	sc.eva.carrying = 1
	sc.eva.carrying_id = String(e.id)
	(e.node as Node3D).queue_free()
	items.erase(e)
	if sc.sounds != null:
		sc.sounds.play("done")
	match String(it.kind):
		"body":
			_say("You bring %s with you, gently. The airlock's the way out." % String(it.name))
		"survivor":
			_say("%s grips your arm. \"I heard the cutter. I thought I'd dreamed it.\" Clip them to your tether and get them home." % String(it.name))
		_:
			_say("Got %s. Back out through the airlock with it." % Salvage.describe(it))
	return "taken"


func _say(text: String) -> void:
	message = text
	message_t = 5.0


# --- Every frame ---------------------------------------------------------------------------------

func step(delta: float) -> void:
	var e := sc.eva
	if not active or e == null:
		return
	_t += delta
	message_t = maxf(0.0, message_t - delta)
	e.o2 = maxf(0.0, e.o2 - delta * (1.4 if Input.is_key_pressed(KEY_SHIFT) else 1.0))
	if e.o2 <= 0.0:
		leave()
		sc.foot_c.end_space_walk("OUT OF AIR inside a dead ship. The tether winch dragged you out through their door and home. Next time, watch the gauge.")
		return
	if not reading:
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
		walk.look(yaw * sc.KEY_TURN * delta, pitch * sc.KEY_TURN * delta)
		walk.step(minf(delta, 0.05), dir * (0.7 if e.carrying > 0 else 1.0), Input.is_key_pressed(KEY_SHIFT) and e.carrying <= 0)
	for i in _lights.size():   # the emergency lights, failing politely
		_lights[i].light_energy = 0.22 + 0.12 * sin(_t * 3.0 + float(i) * 1.7) + (0.0 if fmod(_t + float(i) * 2.3, 7.0) > 0.12 else -0.2)


func input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		walk.look(-event.relative.x * sc.MOUSE_TURN * GameSettings.mouse_sensitivity(), -event.relative.y * sc.MOUSE_TURN * GameSettings.mouse_sensitivity())
		return
	if event is InputEventMouseButton and event.pressed:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		return
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	match event.keycode:
		KEY_E:
			use()
		KEY_L:
			read_log()
		KEY_Q:
			if reading:
				use()
			elif walk.near_airlock():
				use()


## Where the eye is, in the world.
func eye_transform() -> Transform3D:
	var s := ship()
	return s.body.global_transform * Transform3D(walk.look_basis(), walk.eye())


func hud() -> void:
	var e := sc.eva
	var low := e.o2 < e.o2_max * 0.2
	sc.hud.text = "\n".join(PackedStringArray([
		"ABOARD THE %s    %s" % [_ship_name(derelict).to_upper(), walk.room().to_upper()],
		"AIR  %s%s" % [SurfaceWork.clock(e.o2), "   LOW: GET OUT AND HEAD BACK" if low else ""],
		"CARRYING  %s" % Salvage.describe(e.carry).to_upper() if e.carrying > 0 else "HANDS FREE",
	]))
	var hint := ""
	var near := nearest()
	if reading:
		hint = "L, E or Q: done reading"
	elif message_t > 0.0:
		hint = message
	elif walk.near_airlock():
		hint = "E: out through the airlock%s" % (" with %s" % Salvage.describe(e.carry) if e.carrying > 0 else "")
	elif not near.is_empty():
		var it: Dictionary = near.item
		var why := "" if e.carrying <= 0 else "Hands full."
		if why == "":
			why = _room_note(it)
			if why != "" and String(it.kind) == "survivor":
				why = "No bunk and the jump seat's taken. E: report them; the port will send a boat"
		hint = "%s. %s" % [Salvage.sentence(_label(it)), why if why != "" else "E: take %s" % ("them" if String(it.kind) in ["body", "survivor"] else "it")]
		if walk.near_helm():
			hint += "    L: read the log"
	elif walk.near_helm():
		hint = "The helm. The log's still running on the last of the batteries. E: read it"
	else:
		hint = "WASD walk, mouse look. The lamp goes where you look. The airlock is the way out."
	sc.prompt.text = hint


var _room_cache := {}


func _room_note(it: Dictionary) -> String:
	var k := str(it.get("kind", "")) + str(it.get("name", it.get("commodity", "")))
	if not _room_cache.has(k):
		_room_cache[k] = Salvage.room_for(it)
	return String(_room_cache[k])


func _label(it: Dictionary) -> String:
	match String(it.kind):
		"body":
			return "%s, of the %s's crew" % [String(it.name), _ship_name(derelict)]
		"survivor":
			return "%s, in the cold bunk. Alive" % String(it.name)
		"supplies":
			return "a locker: %s" % Salvage.describe(it).trim_prefix("a supplies locker: ")
		"recorder":
			return "the flight recorder (the insurer pays about %s cr for it)" % ShipStats.commas(int(it.bounty))
	return Salvage.describe(it)


func _build_log_panel() -> void:
	_log_panel = PanelContainer.new()
	_log_panel.add_theme_stylebox_override("panel", Brand.panel_box())
	_log_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_MINSIZE)
	_log_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_log_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	_log_panel.add_child(box)
	box.add_child(Brand.heading("LOG OF THE %s" % _ship_name(derelict).to_upper(), 18))
	_log_label = Brand.note("", 16)
	_log_label.add_theme_color_override("font_color", Brand.OFFWHITE)
	_log_label.custom_minimum_size = Vector2(560, 0)
	box.add_child(_log_label)
	box.add_child(Brand.note("L, E or Q: done reading", 13))
	_log_panel.visible = false
	sc.hud.get_parent().add_child(_log_panel)
