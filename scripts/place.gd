extends Node3D
## Walking the place your ship is berthed at, in first person. Ports, fuel depots, belt works and a moon
## base's orbital station have a concourse; a moon base's pad has the base's hab; a mining camp has the
## foreman's hut. Desks along the walls do what the station terminal's buttons do (that menu is still
## there, at the terminal kiosk or with T). The gate leads back aboard your ship.

const HELP := "WASD walk   mouse or arrows look   Shift run   E use a desk   T station terminal   Esc frees the mouse"
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
var people: Array[Figure] = []
var audio: WorldAudio
var _step_acc := 0.0


func _ready() -> void:
	if Session.slot >= 0:
		Session.profile["location"] = "dock"
		Session.save_profile()
	site = Session.port() if Session.slot >= 0 else {}
	var k := String(LocalSpace.node(String(Session.profile.get("port_id", ""))).get("kind", "port"))
	kind = "hab" if k == "pad" else ("hut" if k == "camp" else "concourse")
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
	fade.color.a = 1.0   # and in from black
	create_tween().tween_property(fade, "color:a", 0.0, 0.35)


# --- Building the place ------------------------------------------------------------------------------

func _build_env() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = SpaceSky.make()
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.glow_intensity = 0.7
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.58, 0.65)
	env.ambient_light_energy = 0.35
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, 30, 0)
	sun.light_energy = 0.6 if kind == "concourse" else 0.15
	sun.set_meta("no_shadow", true)
	add_child(sun)


func _mat(col: Color, glow := false) -> StandardMaterial3D:
	var key := "%s|%s" % [col.to_html(), glow]
	if not _mats.has(key):
		_mats[key] = Interiors.glow(col, 1.4) if glow else Interiors.flat(col, 0.8)
	return _mats[key]


## A box in the world; `solid` makes it something the walker bumps into.
func _box(pos: Vector3, size: Vector3, col: Color, solid := true, glow := false) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	b.material = _mat(col, glow)
	mi.mesh = b
	mi.position = pos
	add_child(mi)
	if solid:
		(walker.furniture[0] as Array).append(Rect2(pos.x - size.x * 0.5, pos.z - size.z * 0.5, size.x, size.z))
	return mi


## A room: floor, ceiling and four walls (`window_north` cuts a long window in the north wall).
func _room(w: float, d: float, h: float, wall: Color, floor_col: Color, window_north := false, ceiling := true) -> void:
	var fl := _box(Vector3(0, -0.1, 0), Vector3(w, 0.2, d), floor_col, false)
	var fm := Interiors.flat(floor_col, 0.75)
	SurfaceTextures.apply_panel(fm)   # deck plating
	(fl.mesh as BoxMesh).material = fm
	if ceiling:
		_box(Vector3(0, h + 0.1, 0), Vector3(w, 0.2, d), wall.darkened(0.25), false)
	for side in [-1.0, 1.0]:
		_wall(Vector3(side * w * 0.5, h * 0.5, 0), Vector3(0.3, h, d), wall)
		if side < 0.0 and window_north:
			_wall(Vector3(0, 0.6, -d * 0.5), Vector3(w, 1.2, 0.3), wall)
			_wall(Vector3(0, h - 0.6, -d * 0.5), Vector3(w, 1.2, 0.3), wall)
			var glass := MeshInstance3D.new()
			var gb := BoxMesh.new()
			gb.size = Vector3(w, h - 2.4, 0.05)
			gb.material = Interiors.glass(Color(0.3, 0.45, 0.6), 0.12)
			glass.mesh = gb
			glass.position = Vector3(0, h * 0.5, -d * 0.5)
			add_child(glass)
			for x in range(int(-w * 0.5) + 4, int(w * 0.5), 6):   # window mullions
				_box(Vector3(x, h * 0.5, -d * 0.5 + 0.05), Vector3(0.2, h - 2.4, 0.2), wall.darkened(0.3), false)
		else:
			_wall(Vector3(0, h * 0.5, side * d * 0.5), Vector3(w, h, 0.3), wall)
	for x in range(int(-w * 0.5) + 4, int(w * 0.5) - 1, 8):   # ceiling lights
		for z in [-d * 0.25, d * 0.25]:
			if ceiling:
				_box(Vector3(x, h - 0.05, z), Vector3(2.4, 0.08, 0.5), Color(1.0, 0.95, 0.85), false, true)
			var lamp := OmniLight3D.new()
			lamp.position = Vector3(x, h - 0.6, z)
			lamp.omni_range = 9.0
			lamp.light_energy = 1.1
			lamp.light_color = Color(1.0, 0.94, 0.85)
			add_child(lamp)
	(walker.walls[0] as Array).append(Rect2(-w * 0.5 - 1.0, -d * 0.5 - 1.0, 1.0 + 0.15, d + 2.0))
	(walker.walls[0] as Array).append(Rect2(w * 0.5 - 0.15, -d * 0.5 - 1.0, 1.15, d + 2.0))
	(walker.walls[0] as Array).append(Rect2(-w * 0.5 - 1.0, -d * 0.5 - 1.0, w + 2.0, 1.15))
	(walker.walls[0] as Array).append(Rect2(-w * 0.5 - 1.0, d * 0.5 - 0.15, w + 2.0, 1.15))


func _wall(pos: Vector3, size: Vector3, col: Color) -> void:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	var m := Interiors.flat(col, 0.85)
	SurfaceTextures.apply_panel(m)
	b.material = m
	mi.mesh = b
	mi.position = pos
	add_child(mi)


## A desk: counter, lit sign and someone behind it. `face` points from the counter into the room.
func _desk(id: String, label: String, pos: Vector3, face: Vector3, col: Color, staffed := true) -> void:
	var across := Vector3(-face.z, 0, face.x)
	var size := Vector3(absf(across.x) * 3.2 + absf(face.x) * 0.9, 1.1, absf(across.z) * 3.2 + absf(face.z) * 0.9)
	_box(pos + Vector3(0, 0.55, 0), size, Color(0.22, 0.24, 0.28))
	_box(pos + Vector3(0, 1.12, 0), size + Vector3(0.1, 0.04, 0.1), col.darkened(0.2), false)
	var sign_pos := pos - face * 1.2 + Vector3(0, 2.9, 0)
	_box(sign_pos, Vector3(absf(across.x) * 3.0 + 0.1, 0.7, absf(across.z) * 3.0 + 0.1), col, false, true)
	var text := Label3D.new()
	text.text = label.to_upper()
	text.font_size = 56
	text.pixel_size = 0.006
	text.outline_size = 0
	text.modulate = Color(0.08, 0.08, 0.1)
	text.position = sign_pos + face * 0.08
	text.rotation.y = atan2(face.x, face.z)
	add_child(text)
	if staffed:
		_person(pos - face * 0.8, face, col)
	desks.append({"id": id, "label": label, "pos": pos + face * 1.25})


## A person (Figure) facing `face`, solid to walk into.
func _person(at: Vector3, face: Vector3, col: Color, seated := false) -> Figure:
	var f := Figure.make(col, hash("%s|%s" % [at, Session.day()]), seated)
	f.position = at
	f.rotation.y = atan2(-face.x, -face.z)
	add_child(f)
	people.append(f)
	if not seated:
		(walker.furniture[0] as Array).append(Rect2(at.x - 0.3, at.z - 0.3, 0.6, 0.6))
	return f


## A painted walkway line on the floor between two points.
func _walk_line(from: Vector3, to: Vector3) -> void:
	var mid := (from + to) * 0.5
	var along := to - from
	var size := Vector3(absf(along.x) + 0.12, 0.012, absf(along.z) + 0.12)
	_box(Vector3(mid.x, 0.006, mid.z), size, Color(0.85, 0.65, 0.18), false)


## A planter: a box of soil with a few round shrubs.
func _planter(at: Vector3) -> void:
	_box(at + Vector3(0, 0.3, 0), Vector3(1.6, 0.6, 0.8), Color(0.32, 0.33, 0.36))
	var leaf := _mat(Color(0.22, 0.48, 0.25))
	for i in 3:
		var mi := MeshInstance3D.new()
		var sph := SphereMesh.new()
		sph.radius = 0.32 + 0.06 * i
		sph.height = (0.32 + 0.06 * i) * 1.6
		sph.radial_segments = 8
		sph.rings = 4
		sph.material = leaf
		mi.mesh = sph
		mi.position = at + Vector3(-0.5 + i * 0.5, 0.75 + 0.05 * i, 0)
		add_child(mi)


## A rack of glowing grow-trays.
func _hydro_rack(at: Vector3) -> void:
	_box(at + Vector3(0, 1.1, 0), Vector3(0.6, 2.2, 1.8), Color(0.55, 0.56, 0.58))
	for k in 3:
		_box(at + Vector3(0.1, 0.5 + k * 0.65, 0), Vector3(0.45, 0.2, 1.6), Color(0.3, 0.7, 0.3))
		_box(at + Vector3(0.1, 0.78 + k * 0.65, 0), Vector3(0.45, 0.03, 1.6), Color(0.85, 0.45, 1.0), false, true)


## A hanging screen listing the freight posted here, both sides.
func _freight_board(at: Vector3, face := Vector3(0, 0, 1)) -> void:
	var across := Vector3(-face.z, 0, face.x)
	_box(at, Vector3(absf(across.x) * 4.6 + 0.12, 1.5, absf(across.z) * 4.6 + 0.12), Color(0.08, 0.09, 0.11), false)
	for c in [-1.0, 1.0]:   # hanging cables
		_box(at + across * c * 2.0 + Vector3(0, 1.3, 0), Vector3(0.04, 1.1, 0.04), Color(0.2, 0.2, 0.22), false)
	var lines := PackedStringArray(["FREIGHT POSTED HERE"])
	var offers := Contracts.offers_from(Session.system_id()) if Session.slot >= 0 else []
	for o in offers.slice(0, 5):
		var dest := String(LocalSpace.node(String(o.destination_port_id)).get("name", "")) if bool(o.get("local", false)) else String(Worlds.port(String(o.destination_port_id)).get("name", ""))
		lines.append("%s  %.1f t  %s cr/t" % [dest.trim_prefix(String(Worlds.system(Session.system_id()).get("name", "")) + " ").substr(0, 22), float(o.offer), ShipStats.commas(int(o.rate))])
	if offers.is_empty():
		lines.append("NOTHING POSTED TODAY")
	for side in [1.0, -1.0]:
		var l := Label3D.new()
		l.text = "\n".join(lines)
		l.font_size = 32
		l.pixel_size = 0.0056
		l.modulate = Color(1.0, 0.75, 0.3)
		l.outline_size = 0
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.position = at + face * side * 0.08
		l.rotation.y = atan2(face.x * side, face.z * side)
		add_child(l)


## The gate back aboard: a lit door with your ship's name over it.
func _gate(pos: Vector3, face: Vector3, label: String) -> void:
	var across := Vector3(-face.z, 0, face.x)
	_box(pos + Vector3(0, 1.5, 0) - face * 0.1, Vector3(absf(across.x) * 2.4 + 0.2, 3.0, absf(across.z) * 2.4 + 0.2), Color(0.3, 0.33, 0.38), false)
	_box(pos + Vector3(0, 1.4, 0) + face * 0.06, Vector3(absf(across.x) * 1.8 + 0.05, 2.6, absf(across.z) * 1.8 + 0.05), Color(0.15, 0.17, 0.2), false)
	_box(pos + Vector3(0, 3.3, 0) + face * 0.1, Vector3(absf(across.x) * 3.4 + 0.1, 0.5, absf(across.z) * 3.4 + 0.1), Brand.AMBER, false, true)
	var text := Label3D.new()
	text.text = label
	text.font_size = 44
	text.pixel_size = 0.006
	text.outline_size = 0
	text.modulate = Color(0.08, 0.08, 0.1)
	text.position = pos + Vector3(0, 3.3, 0) + face * 0.2
	text.rotation.y = atan2(face.x, face.z)
	add_child(text)
	desks.append({"id": "gate", "label": "your ship: %s" % Session.ship_label(), "pos": pos + face * 1.3})


func _big_sign(text: String, pos: Vector3, yaw: float) -> void:
	var l := Label3D.new()
	l.text = text
	l.font_size = 120
	l.pixel_size = minf(0.008, 12.0 / (maxf(1.0, text.length()) * 120.0 * 0.62))   # fit a long name on the wall
	l.modulate = Brand.AMBER
	l.position = pos
	l.rotation.y = yaw
	add_child(l)


func _place_name() -> String:
	return String(site.get("name", LocalSpace.node(String(Session.profile.get("port_id", ""))).get("name", "Station"))).to_upper()


func _build_concourse() -> void:
	_room(44.0, 14.0, 5.0, Color(0.42, 0.45, 0.5), Color(0.2, 0.21, 0.23), true)
	var face_n := Vector3(0, 0, -1)
	_desk("freight", "Freight office", Vector3(-14, 0, 5.2), face_n, Color(0.95, 0.65, 0.2))
	_desk("fuel", "Fuel and repairs", Vector3(-5, 0, 5.2), face_n, Color(0.4, 0.8, 1.0))
	if String(LocalSpace.node(String(Session.profile.get("port_id", ""))).get("kind", "port")) == "port":
		_desk("yard", "Shipyard", Vector3(4, 0, 5.2), face_n, Color(0.9, 0.85, 0.4))
	_desk("bar", "Bar and bunks", Vector3(14, 0, 5.2), face_n, Color(0.85, 0.35, 0.3))
	for x in [11.0, 13.0, 15.0, 17.0]:   # bar stools
		_box(Vector3(x, 0.4, 3.7), Vector3(0.45, 0.8, 0.45), Color(0.6, 0.25, 0.2))
	var asking := Session.people_here() if Session.slot >= 0 else []
	var jackets := [Color(0.3, 0.5, 0.75), Color(0.55, 0.7, 0.35), Color(0.7, 0.45, 0.65)]
	for i in mini(asking.size(), 3):   # the people with work, waiting at the bar
		_person(Vector3([10.2, 17.8, 19.6][i], 0, 2.9), Vector3(0, 0, -1), jackets[i])
	# The terminal kiosk in the middle, and benches.
	_box(Vector3(0, 0.75, -1.5), Vector3(0.8, 1.5, 0.5), Color(0.16, 0.17, 0.2))
	_box(Vector3(0, 1.3, -1.24), Vector3(0.6, 0.4, 0.04), Color(0.3, 0.85, 1.0), false, true)
	desks.append({"id": "terminal", "label": "Station terminal", "pos": Vector3(0, 0, -0.5)})
	for x in [-9.0, 9.0]:
		_box(Vector3(x, 0.25, -3.5), Vector3(4.0, 0.5, 0.8), Color(0.35, 0.3, 0.28))
	_walk_line(Vector3(-21, 0, 0), Vector3(20, 0, 0))   # the walkway down the middle, and a line to each desk
	for x in [-14.0, -5.0, 4.0, 14.0]:
		_walk_line(Vector3(x, 0, 0.2), Vector3(x, 0, 3.6))
	for x in [-17.0, -2.0, 7.0, 19.0]:
		_planter(Vector3(x, 0, -5.6))
	for x in [-16.0, -8.0, 0.0, 8.0, 16.0]:   # roof beams
		_box(Vector3(x, 4.8, 0), Vector3(0.35, 0.3, 14.0), Color(0.3, 0.32, 0.36), false)
	_freight_board(Vector3(0, 3.4, -1.5), Vector3(1, 0, 0))
	_gate(Vector3(-21.8, 0, 0), Vector3(1, 0, 0), "BERTH 3  %s" % Session.ship_label().to_upper())
	_big_sign(_place_name(), Vector3(21.7, 3.2, 0), -PI * 0.5)
	walker.pos = Vector3(-19.5, 0, 0)
	walker.face(Vector3(1, 0, 0))


func _build_hab() -> void:
	_room(20.0, 20.0, 4.5, Color(0.7, 0.69, 0.64), Color(0.32, 0.31, 0.3), false, false)
	var dome := MeshInstance3D.new()   # the dome over the room
	var sph := SphereMesh.new()
	sph.radius = 14.0
	sph.height = 14.0
	sph.is_hemisphere = true
	sph.material = Interiors.flat(Color(0.72, 0.71, 0.66), 0.9)
	(sph.material as StandardMaterial3D).cull_mode = BaseMaterial3D.CULL_DISABLED
	dome.mesh = sph
	dome.position = Vector3(0, 4.5, 0)
	dome.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(dome)
	_desk("dispatch", "Dispatch", Vector3(0, 0, -8.2), Vector3(0, 0, 1), Color(0.95, 0.65, 0.2))
	_desk("lab", "Survey lab", Vector3(8.2, 0, -2), Vector3(-1, 0, 0), Color(0.4, 1.0, 0.8))
	_desk("store", "Suit store", Vector3(8.2, 0, 5), Vector3(-1, 0, 0), Color(0.6, 0.6, 1.0))
	_desk("fuel", "Pad fuel and repairs", Vector3(0, 0, 8.2), Vector3(0, 0, -1), Color(0.4, 0.8, 1.0))
	_box(Vector3(-2, 0.75, 1), Vector3(0.8, 1.5, 0.5), Color(0.16, 0.17, 0.2))
	_box(Vector3(-2, 1.3, 1.26), Vector3(0.6, 0.4, 0.04), Color(0.3, 0.85, 1.0), false, true)
	desks.append({"id": "terminal", "label": "Base terminal", "pos": Vector3(-2, 0, 2)})
	for z in [-7.0, -4.5, 4.5, 7.0]:   # hydroponic racks either side of the airlock
		_hydro_rack(Vector3(-9.2, 0, z))
	_walk_line(Vector3(-9, 0, 0), Vector3(7, 0, 0))
	_freight_board(Vector3(3.5, 3.0, 0), Vector3(-1, 0, 0))
	_gate(Vector3(-9.8, 0, 0), Vector3(1, 0, 0), "AIRLOCK  PAD 1")
	_big_sign(_place_name(), Vector3(0, 3.95, 9.8), PI)
	walker.pos = Vector3(-7.5, 0, 0)
	walker.face(Vector3(1, 0, 0))


func _build_hut() -> void:
	_room(14.0, 9.0, 3.4, Color(0.62, 0.55, 0.4), Color(0.25, 0.22, 0.18))
	_desk("foreman", "Foreman", Vector3(0, 0, -2.9), Vector3(0, 0, 1), Color(1.0, 0.55, 0.3))
	_desk("exchange", "Ore and parts exchange", Vector3(5.4, 0, 1.5), Vector3(-1, 0, 0), Color(0.8, 0.7, 0.4))
	_box(Vector3(1.5, 0.75, 3.6), Vector3(0.8, 1.5, 0.5), Color(0.16, 0.17, 0.2))
	desks.append({"id": "terminal", "label": "Camp terminal", "pos": Vector3(1.5, 0, 2.6)})
	for i in 3:   # crates
		_box(Vector3(-3.5 + i * 1.3, 0.6, 3.6), Vector3(1.1, 1.2, 1.1), Color(0.45, 0.35, 0.2))
	_box(Vector3(-2.0, 0.75, -0.4), Vector3(1.8, 0.08, 1.0), Color(0.4, 0.33, 0.24))   # a table, a worker on a break
	_box(Vector3(-2.0, 0.37, -0.4), Vector3(0.12, 0.74, 0.12), Color(0.25, 0.22, 0.2), false)
	_box(Vector3(-2.0, 0.45, -1.25), Vector3(0.5, 0.06, 0.5), Color(0.3, 0.3, 0.32), false)
	_person(Vector3(-2.0, 0, -1.2), Vector3(0, 0, 1), Color(0.75, 0.45, 0.2), true)
	for i in 4:   # suit lockers on the back wall
		_box(Vector3(2.6 + i * 0.7, 1.0, -4.15), Vector3(0.6, 2.0, 0.4), Color(0.35, 0.4, 0.38))
	_gate(Vector3(-6.8, 0, 0), Vector3(1, 0, 0), "AIRLOCK")
	walker.pos = Vector3(-4.8, 0, -1)
	walker.face(Vector3(1, 0, 0))


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
		_step_acc += Vector2(walker.pos.x - before.x, walker.pos.z - before.z).length()
		if _step_acc > (0.95 if Input.is_key_pressed(KEY_SHIFT) else 0.75):
			_step_acc = 0.0
			audio.step("metal")
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
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


# --- HUD and the desk panel --------------------------------------------------------------------------

func _build_hud() -> void:
	var layer := CanvasLayer.new()
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
	match id:
		"freight", "dispatch", "foreman":
			_desk_freight(id)
		"fuel":
			_desk_fuel()
		"yard":
			_clear_panel("Shipyard", "Build, refit and fit parts to your ship. The yard can change anything, at a price.")
			_action("ENTER THE SHIPYARD", func() -> void:
				Session.profile["location"] = "shipyard"
				Session.save_profile()
				_go(Session.YARD_SCENE), not Session.insolvent())
		"bar":
			_desk_bar()
		"lab":
			_desk_sell("Survey lab", "The lab pays well for rock samples and glass crystals. It has no use for salvage or ice.", {"sample": 1.4, "rare": 1.4, "salvage": 0.0, "ice": 0.0})
		"exchange":
			_desk_sell("Ore and parts exchange", "The camp buys anything, cheaply, except ice: the drills need water, and it pays well for that.", {"sample": 0.8, "salvage": 0.9, "ice": 1.3, "rare": 0.8})
		"store":
			_desk_store()
		"gate":
			_desk_gate()


func _refill() -> void:
	_refresh_info()
	if open_desk != "":
		_fill(open_desk)


# --- Desks -------------------------------------------------------------------------------------------

func _desk_freight(id: String) -> void:
	var title: String = {"freight": "Freight office", "dispatch": "Dispatch", "foreman": "Foreman"}[id]
	_clear_panel(title)
	if Session.insolvent():
		panel_list.add_child(Brand.note("No one will give a bankrupt captain freight. The bank will take the ship at half price, clear the debt and lend you a starter hauler.", 15))
		_action("LET THE BANK STEP IN", func() -> void:
			var r := Session.restructure()
			Session.flash = String(r.message)
			if bool(r.ok):
				get_tree().reload_current_scene())
		return
	var c := Session.active_contract()
	var here := String(Session.profile.get("port_id", ""))
	if not c.is_empty():
		if id != "freight":
			_missions_section()
		var local := bool(c.get("local", false))
		var arrived := String(c.get("status", "")) == "arrived"
		var load_text := "%d passengers aboard" % int(c.seats) if String(c.get("person_kind", "")) == "passenger" else "%.1f t aboard" % float(c.get("accepted_tonnes", c.get("offer", 0.0)))
		panel_list.add_child(Brand.note("ACTIVE: %s, %s." % [String(c.title), load_text], 15))
		var at_start := String(c.get("origin_port_id", "")) == here if local else String(c.get("origin_system_id", "")) == Session.system_id()
		var at_end := (String(c.get("destination_port_id", "")) == here or (bool(c.get("surface", false)) and LocalSpace.is_surface(here))) if local else String(c.get("destination_system_id", "")) == Session.system_id()
		if arrived and at_end and Session.surface_site() == "camp" and String(c.get("person_kind", "")) != "passenger":
			var t := float(c.get("accepted_tonnes", c.get("offer", 0.0)))
			var uc := SurfaceWork.unload_cfg()
			_action("PAY THE CAMP CREW TO UNLOAD  %d%% of the pay, %d hours" % [roundi(float(uc.get("camp_crew_share", 0.15)) * 100.0), int(uc.get("camp_crew_hours", 8))], func() -> void:
				var r := Session.deliver_active_contract()
				_say(String(r.message))
				_refill())
			_action("UNLOAD IT YOURSELF  %d crates, in the suit" % SurfaceWork.crates_for(t), func() -> void:
				var r := Session.start_manual_unload()
				if bool(r.ok):
					Session.flight_job = {}
					_go(Session.FLIGHT_SCENE)
				else:
					_say(String(r.message)))
		elif arrived and at_end:
			_action("DELIVER THE LOAD", func() -> void:
				var r := Session.deliver_active_contract()
				_say(String(r.message))
				_refill())
		elif at_start and not arrived:
			_action("FLY THE RUN YOURSELF" if local else "FLY THE JUMP YOURSELF", func() -> void:
				var r := Session.begin_local_flight() if local else Session.begin_jump_flight()
				if bool(r.ok):
					_go(Session.FLIGHT_SCENE)
				else:
					_say(String(r.message)))
			_action("DEPART ON AUTOPILOT", func() -> void:
				var r := Session.depart_active_contract()
				_say(String(r.message))
				_refill())
			if c.has("due_hour"):
				var hb := People.hard_burn()
				_action("HARD BURN ON AUTOPILOT  (%d%% of the time, %d%% of the fuel)" % [roundi(float(hb.time) * 100.0), roundi(float(hb.fuel) * 100.0)], func() -> void:
					var r := Session.depart_active_contract(true)
					_say(String(r.message))
					_refill())
		return
	if id != "freight":
		_missions_section()
		_people_section()
		panel_list.add_child(Brand.heading("POSTED WORK", 15))
	var offers := Contracts.offers_from(Session.system_id())
	if offers.is_empty():
		panel_list.add_child(Brand.note("Nothing posted here right now. Wait a day at the bunks, or fly empty somewhere busier.", 15))
	var stats := {}
	var loaded := Session._load_ship(SaveSlots.read(Session.slot)) if Session.slot >= 0 else {}
	if not loaded.is_empty():
		stats = Session.ship_stats(loaded.ship)
	for o in offers:
		var job: Dictionary = o
		_action(_offer_text(job, stats), func() -> void:
			var r := Session.accept_contract(job)
			_say(String(r.message))
			_refill())
	panel_list.add_child(Brand.heading("FLY EMPTY", 15))
	if Session.sim != null and not bool(SimWorld.player(Session.sim).get("ftl", true)):
		for s in Session.local_sites():
			var sid := String(s.id)
			_action("%s  ·  %.1f km/s  ·  %d h  ·  about %s cr  ·  %d jobs there" % [String(s.name), float(s.dv_kms), int(s.hours), ShipStats.commas(roundi(float(s.cost))), int(s.jobs)], func() -> void:
				var r := Session.local_reposition(sid)
				Session.flash = String(r.message)
				if bool(r.ok):
					get_tree().reload_current_scene()
				else:
					_say(String(r.message)))
	elif Session.sim != null:
		for o in SimWorld.destinations(Session.sim).slice(0, 6):
			var sys := String(o.system_id)
			_action("%s  ·  %.2f ly  ·  %.1f days  ·  about %s cr" % [String(Worlds.system(sys).get("name", sys)), float(o.ly), float(o.days), ShipStats.commas(roundi(float(o.cost)))], func() -> void:
				var r := Session.travel_empty(sys)
				Session.flash = String(r.message)
				if bool(r.ok):
					get_tree().reload_current_scene()
				else:
					_say(String(r.message)))


func _offer_text(c: Dictionary, stats: Dictionary) -> String:
	var goods := Worlds.commodity(String(c.commodity))
	if bool(c.get("local", false)):
		var tag := "SURFACE" if bool(c.get("surface", false)) else "LOCAL"
		var dest := String(LocalSpace.node(String(c.destination_port_id)).get("name", c.destination_port_id))
		var fuel := ""
		if not stats.is_empty():
			fuel = ", fuel about %s cr" % ShipStats.commas(roundi(float(Session.local_trip_cost(stats, float(c.offer), float(c.dv_kms)).total)))
		return "%s  %s  →  %s\n%.1f t  ·  %.1f km/s  ·  %d h  ·  %s cr/t  ·  up to %s cr%s" % [tag, goods.get("name", c.commodity), dest, float(c.offer), float(c.dv_kms), int(c.hours),
				ShipStats.commas(int(c.rate)), ShipStats.commas(roundi(float(c.offer) * float(c.rate))), fuel]
	var port := Worlds.port(String(c.destination_port_id))
	return "%s  →  %s\n%.1f t  ·  %.2f ly  ·  %s cr/t  ·  up to %s cr" % [goods.get("name", c.commodity), port.get("name", c.destination_system_id), float(c.offer), float(c.distance_ly),
			ShipStats.commas(int(c.rate)), ShipStats.commas(roundi(float(c.offer) * float(c.rate)))]


## People asking in person (People): rush jobs, passengers and sealed crates.
func _people_section() -> void:
	var rep := int(Session.profile.get("rep", 0))
	var nxt := People.next_standing(rep)
	panel_list.add_child(Brand.heading("PEOPLE WITH WORK", 15))
	panel_list.add_child(Brand.note("Your standing: %s (%d%s). Standing raises what people offer, up to +15%%." % [People.standing(rep), rep,
			", %s at %d" % [People.standing(nxt), nxt] if nxt > 0 else ""], 13))
	var busy := not Session.active_contract().is_empty()
	var people := Session.people_here()
	if people.is_empty():
		panel_list.add_child(Brand.note("No one is asking today.", 14))
	for j in people:
		var job: Dictionary = j
		var tag := String(job.person_kind).to_upper()
		var pay := int(job.fare) if job.person_kind == "passenger" else roundi(float(job.offer) * float(job.rate))
		var size := "%d seat%s" % [int(job.seats), "" if int(job.seats) == 1 else "s"] if job.person_kind == "passenger" else "%.1f t" % float(job.offer)
		var txt := "%s  %s: \"%s\"\n%s  ·  %s  ·  %d h  ·  pays %s cr  ·  %s" % [tag, String(job.person), String(job.line), String(job.title), size, int(job.hours),
				ShipStats.commas(pay), String(job.get("locked", job.blurb))]
		_action(txt, func() -> void:
			var r := Session.accept_contract(job)
			_say(String(r.message))
			_refill(), not busy and not job.has("locked"))


func _desk_fuel() -> void:
	var mult := Session.site_fuel_mult()
	_clear_panel("Fuel and repairs", "Fuel here costs %d%% of the system price (%s). You are charged for what you burn when you leave or land." % [roundi(mult * 100.0),
			"cheap: a fuel depot" if mult < 0.95 else ("dear: it has to come up from the surface or down from orbit" if mult > 1.2 else "the usual")])
	var dmg := float(Session.profile.get("hull_damage", 0.0))
	panel_list.add_child(Brand.note("Hull: %d%%%s" % [roundi((1.0 - dmg) * 100.0), "" if dmg <= 0.0 else ". A damaged hull loses thrust until it is fixed."], 15))
	var cost := Session.repair_cost()
	_action("REPAIR THE HULL  %s cr" % ShipStats.commas(cost) if cost > 0 else "THE HULL NEEDS NO WORK", func() -> void:
		var r := Session.repair_hull()
		_say(String(r.message))
		_refill(), cost > 0)
	var f := Session.finds_aboard()
	if int(f.value) > 0:
		_action("SELL YOUR FINDS  %s cr  (%s)" % [ShipStats.commas(int(f.value)), SurfaceFinds.describe(f)], func() -> void:
			var r := Session.sell_finds()
			_say(String(r.message))
			_refill())


func _desk_bar() -> void:
	_clear_panel("Bar and bunks", "Captains and crews pass through here between jobs, and some of them have work that never reaches the board.")
	_people_section()
	panel_list.add_child(Brand.heading("BUNKS", 15))
	var idle := Session.active_contract().is_empty() and Session.sim != null and not Session.insolvent()
	_action("RENT A BUNK AND WAIT A DAY", func() -> void:
		var r := Session.wait_days(1)
		Session.flash = String(r.message)
		if bool(r.ok):
			get_tree().reload_current_scene()
		else:
			_say(String(r.message)), idle)


func _desk_sell(title: String, note: String, rates: Dictionary) -> void:
	_clear_panel(title, note)
	var f := Session.finds_aboard()
	var value := Session.finds_value(rates)
	panel_list.add_child(Brand.note("In your locker: %s." % SurfaceFinds.describe(f), 15))
	_action("SELL  %s cr" % ShipStats.commas(value) if value > 0 else "NOTHING THEY WANT", func() -> void:
		var r := Session.sell_finds(rates)
		_say(String(r.message))
		_refill(), value > 0)


func _desk_store() -> void:
	var owned := Session.gear_owned()
	_clear_panel("Suit store", "Kit for working outside. Your suit holds %s of air." % SurfaceWork.clock(SurfaceWork.o2_capacity(owned)))
	for gid in SurfaceWork.GEAR_ORDER:
		var g := SurfaceWork.gear(gid)
		var have: bool = gid in owned
		var blocked: bool = g.has("needs") and not String(g.needs) in owned
		var txt := "%s  ·  %s\n%s" % [String(g.name).to_upper(), "OWNED" if have else "%s cr" % ShipStats.commas(int(g.price)), String(g.blurb)]
		if blocked:
			txt += "  (needs the %s)" % String(SurfaceWork.gear(String(g.needs)).name).to_lower()
		var id: String = gid
		_action(txt, func() -> void:
			var r := Session.buy_gear(id)
			_say(String(r.message))
			_refill(), not have and not blocked)


## Timed jobs on foot around this site (SurfaceWork), and the one you hold.
func _missions_section() -> void:
	if Session.surface_site() == "":
		return
	panel_list.add_child(Brand.heading("SURFACE WORK", 15))
	var held := Session.mission()
	if not held.is_empty():
		var left := 0
		for d in held.done:
			if not bool(d):
				left += 1
		panel_list.add_child(Brand.note("HELD: %s, %d of %d left, %s on the clock (it runs while you are outside). Pays %s cr. Suit up at the %s." % [
				String(held.title), left, held.done.size(), SurfaceWork.clock(float(held.limit_s) - float(held.get("elapsed_s", 0.0))),
				ShipStats.commas(int(held.pay)), "airlock"], 14))
		_action("GIVE IT UP  (standing −2)", func() -> void:
			var r := Session.fail_mission("given up")
			_say(String(r.message))
			_refill())
		return
	for mm in Session.missions_here():
		var m: Dictionary = mm
		_action("%s  ·  %d m on foot  ·  %s on the clock  ·  pays %s cr\n%s" % [String(m.title).to_upper(), int(m.walk_m), SurfaceWork.clock(float(m.limit_s)),
				ShipStats.commas(int(m.pay)), "Taken." if bool(m.taken) else String(m.blurb)], func() -> void:
			var r := Session.take_mission(m)
			_say(String(r.message))
			_refill(), not bool(m.taken))


func _desk_gate() -> void:
	_clear_panel("Your ship: %s" % Session.ship_label(), "Through the gate and aboard.")
	var c := Session.active_contract()
	var here := String(Session.profile.get("port_id", ""))
	if not c.is_empty() and String(c.get("status", "")) != "arrived":
		var local := bool(c.get("local", false))
		var at_start := String(c.get("origin_port_id", "")) == here if local else String(c.get("origin_system_id", "")) == Session.system_id()
		if at_start:
			_action("FLY THE RUN" if local else "FLY THE JUMP", func() -> void:
				var r := Session.begin_local_flight() if local else Session.begin_jump_flight()
				if bool(r.ok):
					_go(Session.FLIGHT_SCENE)
				else:
					_say(String(r.message)))
	_action("TAKE THE HELM", func() -> void:
		Session.flight_job = {}
		_go(Session.FLIGHT_SCENE), not Session.insolvent())
	_action("GO ABOARD AND WALK THE SHIP", func() -> void:
		Session.flight_job = {}
		Session.walk_aboard = true
		_go(Session.FLIGHT_SCENE), not Session.insolvent())
	if Session.surface_site() != "":
		_action("SUIT UP AND GO OUTSIDE  (%s of air)" % SurfaceWork.clock(SurfaceWork.o2_capacity(Session.gear_owned())), func() -> void:
			Session.flight_job = {}
			Session.suit_up = true
			_go(Session.FLIGHT_SCENE), not Session.insolvent())
