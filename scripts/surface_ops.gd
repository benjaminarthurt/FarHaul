class_name SurfaceOps
extends Node3D
## What goes on while you are outside on a moon (the flight scene adds one under its moon node): the
## suit's air and jets, the scanner, the marked points of a surface mission and their clock, and the
## crates when you unload at the camp by hand. See SurfaceWork and docs/runtime/surface_work.md.

var flight: Node            ## the flight scene (suit, suit_hatch, model, camera, find_nodes, come_aboard)
var o2 := 0.0               ## seconds of air left
var o2_max := 0.0
var owned: Array = []
var message := ""
var message_t := -100.0
var clock := 0.0            ## seconds outside on this outing
var point_nodes: Array[Node3D] = []
var carrying := false
var carry_node: MeshInstance3D
var stack_root: Node3D       ## crates on the ground by the camp hut
var hold_t := 0.0           ## seconds E has been held on a drill
var site := ""              ## the surface site the ship is at: "pad" or "camp"
var _blackout := false


func setup(f: Node, at_site: String) -> void:
	flight = f
	site = at_site
	_build_mission()
	_build_unload()


func _mat(col: Color, glow := false) -> StandardMaterial3D:
	return Interiors.glow(col, 1.8) if glow else Interiors.flat(col, 0.8)


func _ground(x: float, z: float) -> Vector3:
	return Vector3(x, flight.model.terrain.height(x, z), z)


func _tag(text: String, col: Color, y: float) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font_size = 30
	l.fixed_size = true
	l.pixel_size = 0.0012
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.modulate = col
	l.position = Vector3(0, y, 0)
	return l


# --- Mission points ----------------------------------------------------------------------------------

## The mission held, if it is for this site of this system.
func mission_here() -> Dictionary:
	var m := Session.mission()
	if m.is_empty() or String(m.get("site", "")) != site or String(m.get("system_id", "")) != String(flight._system_id()):
		return {}
	return m


func _build_mission() -> void:
	for n in point_nodes:
		n.queue_free()
	point_nodes.clear()
	var m := mission_here()
	if m.is_empty():
		return
	var pts: Array = m.points
	for i in pts.size():
		var root := Node3D.new()
		root.position = _ground(float(pts[i][0]), float(pts[i][1]))
		add_child(root)
		var kind := String(m.kind)
		var col := Color(1.0, 0.75, 0.25)
		match kind:
			"survey":
				var pole := MeshInstance3D.new()
				var cyl := CylinderMesh.new()
				cyl.top_radius = 0.06
				cyl.bottom_radius = 0.08
				cyl.height = 2.4
				cyl.material = _mat(Color(0.75, 0.75, 0.78))
				pole.mesh = cyl
				pole.position = Vector3(0, 1.2, 0)
				root.add_child(pole)
				root.add_child(_tag("SURVEY POINT %d" % (i + 1), col, 3.4))
			"rescue":
				var body := MeshInstance3D.new()
				var cap := CapsuleMesh.new()
				cap.radius = 0.3
				cap.height = 1.8
				cap.material = _mat(Color(0.9, 0.9, 0.85))
				body.mesh = cap
				body.rotation_degrees = Vector3(0, 30, 90)
				body.position = Vector3(0, 0.35, 0)
				root.add_child(body)
				root.add_child(_tag("SURVEYOR (suit failing)", Color(1.0, 0.45, 0.35), 2.4))
			"drill":
				var rig := MeshInstance3D.new()
				var b := BoxMesh.new()
				b.size = Vector3(1.6, 4.0, 1.6)
				b.material = _mat(Color(0.55, 0.5, 0.35))
				rig.mesh = b
				rig.position = Vector3(0, 2.0, 0)
				root.add_child(rig)
				root.add_child(_tag("STALLED DRILL", col, 5.2))
		var light := MeshInstance3D.new()   # a beacon lamp on every point
		var sph := SphereMesh.new()
		sph.radius = 0.18
		sph.height = 0.36
		sph.material = _mat(col, true)
		light.mesh = sph
		light.position = Vector3(0, 2.6 if kind != "drill" else 4.3, 0)
		light.name = "Lamp"
		root.add_child(light)
		point_nodes.append(root)
		_mark_done(i, bool(m.done[i]))


func _mark_done(i: int, done: bool) -> void:
	if i >= point_nodes.size():
		return
	var lamp := point_nodes[i].get_node_or_null("Lamp") as MeshInstance3D
	if lamp != null and done:
		(lamp.mesh as SphereMesh).material = _mat(Color(0.3, 1.0, 0.45), true)
	for c in point_nodes[i].get_children():
		if c is Label3D and done:
			c.modulate = Color(0.4, 1.0, 0.5)
			c.text = "DONE"


## The mission point within reach (index), or -1.
func point_in_reach() -> int:
	var m := mission_here()
	if m.is_empty() or flight.suit == null:
		return -1
	var pts: Array = m.points
	for i in pts.size():
		if bool(m.done[i]):
			continue
		if flight.suit.distance_to(Vector3(float(pts[i][0]), 0, float(pts[i][1]))) <= (3.5 if String(m.kind) == "drill" else 2.5):
			return i
	return -1


func _point_done(i: int) -> String:
	var m := Session.mission()
	m.done[i] = true
	_mark_done(i, true)
	var left := 0
	for d in m.done:
		if not bool(d):
			left += 1
	if left == 0:
		return String(Session.complete_mission().message)
	Session.profile["mission"] = m
	Session.save_profile()
	return "%s %d of %d. %d to go." % ["Beacon placed:" if String(m.kind) == "survey" else "Done:", m.done.size() - left, m.done.size(), left]


# --- Unloading crates at the camp ----------------------------------------------------------------------

func _build_unload() -> void:
	if stack_root != null:
		stack_root.queue_free()
		stack_root = null
	if site != "camp":
		return
	var d := SurfaceWork.drop_xz()
	stack_root = Node3D.new()
	stack_root.position = _ground(d.x, d.y)
	add_child(stack_root)
	var ring := MeshInstance3D.new()
	var tor := TorusMesh.new()
	tor.inner_radius = float(SurfaceWork.unload_cfg().get("drop_radius_m", 6.0)) - 0.25
	tor.outer_radius = float(SurfaceWork.unload_cfg().get("drop_radius_m", 6.0))
	tor.material = _mat(Color(1.0, 0.6, 0.2), true)
	ring.mesh = tor
	ring.position = Vector3(0, 0.05, 0)
	ring.name = "Ring"
	stack_root.add_child(ring)
	stack_root.add_child(_tag("CRATE STACK", Color(1.0, 0.65, 0.3), 3.0))
	_refresh_stack()


func _refresh_stack() -> void:
	if stack_root == null:
		return
	var u := Session.unloading()
	stack_root.get_node("Ring").visible = not u.is_empty()
	for c in stack_root.get_children():
		if c.has_meta("crate"):
			c.queue_free()
	var n := int(u.get("done", 0))
	for i in n:
		var cr := _crate_mesh()
		cr.position = Vector3((i % 3) * 1.15 - 1.15, 0.5 + (i / 9) * 1.0, ((i / 3) % 3) * 1.15 - 1.15)
		cr.set_meta("crate", true)
		stack_root.add_child(cr)


func _crate_mesh() -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = Vector3(1.0, 1.0, 1.0)
	b.material = _mat(Color(0.75, 0.55, 0.25))
	mi.mesh = b
	return mi


func _set_carrying(on: bool) -> void:
	carrying = on
	if on and carry_node == null:
		carry_node = _crate_mesh()
		carry_node.scale = Vector3.ONE * 0.42
		carry_node.position = Vector3(0, -0.62, -1.0)
		flight.camera.add_child(carry_node)
	if carry_node != null:
		carry_node.visible = on
	_apply_suit()


# --- The suit ----------------------------------------------------------------------------------------

func _apply_suit() -> void:
	var w: SurfaceWalker = flight.suit
	if w == null:
		return
	var s := SurfaceWork.suit_cfg()
	w.speed_mult = (float(s.get("boots_speed_mult", 1.3)) if "boots" in owned else 1.0) * (float(s.get("carry_speed_mult", 0.6)) if carrying else 1.0)
	w.can_jump = not carrying
	w.jet_accel = float(s.get("jet_accel_g", 1.8)) * w.gravity if "jetpack" in owned else 0.0


## Stepping out: a full suit.
func begin_outing() -> void:
	owned = Session.gear_owned()
	o2_max = SurfaceWork.o2_capacity(owned)
	o2 = o2_max
	clock = 0.0
	_blackout = false
	flight.suit.jet_fuel = float(SurfaceWork.suit_cfg().get("jet_fuel_s", 6.0))
	_set_carrying(false)
	_build_mission()
	_refresh_stack()


## Coming aboard: the suit refills, the mission clock stops.
func end_outing() -> void:
	if carrying:
		_set_carrying(false)
	Session.save_profile()


func step(delta: float, running: bool) -> void:
	if flight.suit == null or _blackout:
		return
	var s := SurfaceWork.suit_cfg()
	clock += delta
	o2 -= delta * (float(s.get("run_o2_mult", 1.5)) if running else 1.0)
	_update_tags()
	var m := mission_here()
	if not m.is_empty():
		m["elapsed_s"] = float(m.get("elapsed_s", 0.0)) + delta
		Session.profile["mission"] = m
		if String(m.kind) == "drill":
			var i := point_in_reach()
			if i >= 0 and Input.is_key_pressed(KEY_E):
				hold_t += delta
				if hold_t >= float(m.get("hold_s", 5.0)):
					hold_t = 0.0
					_say(_point_done(i))
			else:
				hold_t = 0.0
		if not Session.mission().is_empty() and float(m.elapsed_s) > float(m.limit_s):
			_say(String(Session.fail_mission("out of time").message))
			_build_mission()
	if o2 <= 0.0:
		_blackout = true
		var msg := Session.suit_rescue()
		if flight.has_method("blackout"):
			flight.blackout()
		_say(msg)
		_build_mission()


## E outside: a mission point, or a crate. Returns what happened, or "" when E is for something else.
func use() -> String:
	var u := Session.unloading()
	var hatch: bool = flight.suit.distance_to(flight.suit_hatch) <= 2.5
	if not u.is_empty() and site == "camp":
		if not carrying and hatch and int(u.done) < int(u.crates):
			_set_carrying(true)
			return _say("Crate %d of %d: carry it to the stack by the hut." % [int(u.done) + 1, int(u.crates)])
		if carrying and flight.suit.distance_to(_ground(SurfaceWork.drop_xz().x, SurfaceWork.drop_xz().y)) <= float(SurfaceWork.unload_cfg().get("drop_radius_m", 6.0)):
			_set_carrying(false)
			var r := Session.crate_carried()
			_refresh_stack()
			return _say(String(r.message))
		if carrying:
			return _say("Carry the crate to the stack by the hut (%.0f m)." % flight.suit.distance_to(_ground(SurfaceWork.drop_xz().x, SurfaceWork.drop_xz().y)))
	var i := point_in_reach()
	if i >= 0:
		var m := mission_here()
		if String(m.kind) == "drill":
			return _say("Hold E to work the drill head free.")
		return _say(_point_done(i))
	return ""


func _say(msg: String) -> String:
	message = msg
	message_t = clock
	return msg


## Sample tags show near to, or anywhere with the scanner.
func _update_tags() -> void:
	var scan := "scanner" in owned
	var r := float(SurfaceWork.suit_cfg().get("tag_range_m", 45.0))
	for id in flight.find_nodes:
		var n: Node3D = flight.find_nodes[id]
		for c in n.get_children():
			if c is Label3D:
				c.visible = scan or flight.suit.distance_to(n.position) <= r


## The nearest thing worth walking to that the scanner can see: {name, dist, bearing} or {}.
func scan() -> Dictionary:
	if not ("scanner" in owned) or flight.suit == null:
		return {}
	var best := {}
	var best_d := float(SurfaceWork.suit_cfg().get("scanner_range_m", 1500.0))
	var m := mission_here()
	if not m.is_empty():
		var pts: Array = m.points
		for i in pts.size():
			if not bool(m.done[i]):
				var p := Vector3(float(pts[i][0]), 0, float(pts[i][1]))
				var d: float = flight.suit.distance_to(p)
				if d < best_d * 4.0:   # the mission's points always show
					return _bearing("mission point", p, d)
	for f in Session.finds_here():
		if bool(f.taken):
			continue
		var p := Vector3(float(f.x), 0, float(f.z))
		var d: float = flight.suit.distance_to(p)
		if d < best_d:
			best_d = d
			best = _bearing("sample" if String(f.kind) == "sample" else "wreck", p, d)
	return best


func _bearing(name: String, p: Vector3, d: float) -> Dictionary:
	var to := Vector2(p.x - flight.suit.pos.x, p.z - flight.suit.pos.z)
	var fwd := Vector2(-sin(flight.suit.yaw), -cos(flight.suit.yaw))
	var ang := rad_to_deg(fwd.angle_to(to))   # + to the right
	var hour := wrapi(roundi(ang / 30.0), 0, 12)
	return {"name": name, "dist": d, "clock": 12 if hour == 0 else hour}


## The suit's readout for the HUD.
func hud_lines() -> PackedStringArray:
	var lines := PackedStringArray()
	var low := o2 < o2_max * float(SurfaceWork.suit_cfg().get("low_o2_frac", 0.2))
	var jets := ""
	if "jetpack" in owned:
		jets = "    JETS  %d%%" % roundi(flight.suit.jet_fuel / float(SurfaceWork.suit_cfg().get("jet_fuel_s", 6.0)) * 100.0)
	lines.append("AIR  %s%s%s" % [SurfaceWork.clock(o2), "  LOW: HEAD BACK" if low else "", jets])
	var m := Session.mission()
	if not m.is_empty():
		if mission_here().is_empty():
			lines.append("MISSION  %s: at the %s" % [String(m.title), "mining camp" if String(m.site) == "camp" else "base pad"])
		else:
			var left := 0
			for d in m.done:
				if not bool(d):
					left += 1
			lines.append("MISSION  %s    %d left    %s to go" % [String(m.title).to_upper(), left, SurfaceWork.clock(float(m.limit_s) - float(m.get("elapsed_s", 0.0)))])
			if hold_t > 0.0:
				lines.append("DRILL  %d%%" % roundi(hold_t / float(m.get("hold_s", 5.0)) * 100.0))
	var u := Session.unloading()
	if not u.is_empty() and site == "camp":
		lines.append("UNLOADING  %d of %d crates on the stack%s" % [int(u.done), int(u.crates), "    CARRYING ONE" if carrying else ""])
	var sc := scan()
	if not sc.is_empty():
		lines.append("SCANNER  %s %.0f m at %d o'clock" % [String(sc.name), float(sc.dist), int(sc.clock)])
	return lines


## The prompt for E, or "" when nothing here is for the suit's work.
func prompt() -> String:
	if clock - message_t < 4.0 and message != "":
		return message
	var u := Session.unloading()
	if not u.is_empty() and site == "camp":
		if carrying:
			var d: float = flight.suit.distance_to(_ground(SurfaceWork.drop_xz().x, SurfaceWork.drop_xz().y))
			return "E: put the crate on the stack" if d <= float(SurfaceWork.unload_cfg().get("drop_radius_m", 6.0)) else "Carry it to the crate stack, %.0f m" % d
		if flight.suit.distance_to(flight.suit_hatch) <= 2.5 and int(u.done) < int(u.crates):
			return "E: take a crate from the hold   Q: back aboard"
	var i := point_in_reach()
	if i >= 0:
		match String(mission_here().kind):
			"survey": return "E: set the survey beacon"
			"rescue": return "E: hook the surveyor to your spare air"
			"drill": return "Hold E: free the drill head"
	return ""
