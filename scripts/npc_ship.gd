class_name NpcShip
extends Node3D
## Somebody else's ship, for looking at (Traffic): the outer hull and the parts bolted to it, nav lights,
## the engine's plume when it burns, and a name tag. No interiors: nobody's going in, except into a
## derelict through a hole you cut yourself. Built from a ShipData layout, centred on its centre of mass,
## nose along -Z like the player's ship.

var ship: ShipData
var radius := 10.0          ## for collisions: roughly the hull's half-length
var label: Label3D
var title := ""             ## what the tag says ("MERIDIAN OUTBOUND  Marigold")
var wreck := false
var damage: ShipDamage      ## a wreck's scorches and sparks
var body: Node3D            ## everything, offset so the centre of mass sits at the node's origin
var _flames: Array[Node3D] = []
var _lights: Array[MeshInstance3D] = []
var _t := 0.0


static func make(layout: Array, name_text: String, is_wreck := false) -> NpcShip:
	var n := NpcShip.new()
	n.ship = ShipData.new(ModuleLibrary.new())
	ShipPresets.build(n.ship, layout)
	n.title = name_text
	n.wreck = is_wreck
	n._build()
	return n


func _build() -> void:
	var st := ShipStats.compute(ship)
	radius = float(st.get("radius", 10.0))
	body = Node3D.new()
	body.name = "Body"
	body.position = -(st.com as Vector3)
	add_child(body)
	var skin := ShipSkin.build(ship)
	body.add_child(skin)
	var press := ShipSkin.pressurised_cells(ship)
	for m in ship.modules:
		var def: ModuleDef = ship.library.get_def(m.id)
		if def.pressurized or def.seal:
			continue
		var node := def.build_visual()
		node.position = ShipGrid.cell_to_world(m.cell) + ShipSkin.mount_offset(ship, m, press)
		node.rotation.y = m.rot * PI / 2.0
		body.add_child(node)
		_collect(node)
	set_flames(false)
	if wreck:
		damage = ShipDamage.new()
		damage.setup(ship)
		body.add_child(damage)
		damage.set_damage(0.85)
		_darken(skin)
	else:   # nav lights: red to port, green to starboard, white strobes fore and aft
		var lo := Vector3(INF, INF, INF)
		var hi := -lo
		for c in press:
			var p := Vector3(c) * ShipGrid.CELL
			lo = Vector3(minf(lo.x, p.x), minf(lo.y, p.y), minf(lo.z, p.z))
			hi = Vector3(maxf(hi.x, p.x), maxf(hi.y, p.y), maxf(hi.z, p.z))
		var h := ShipGrid.CELL * 0.5 + 0.6
		var mid_z := (lo.z + hi.z) * 0.5
		_light(Vector3(lo.x - h, 0, mid_z), Color(1.0, 0.2, 0.15))
		_light(Vector3(hi.x + h, 0, mid_z), Color(0.2, 1.0, 0.35))
		_light(Vector3((lo.x + hi.x) * 0.5, h, lo.z - h), Color(1, 1, 1))
		_light(Vector3((lo.x + hi.x) * 0.5, h, hi.z + h), Color(1, 1, 1))
	label = Label3D.new()
	label.text = title
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.fixed_size = true
	label.pixel_size = 0.0011
	label.font_size = 26
	label.outline_size = 6
	label.modulate = Color(1.0, 0.72, 0.3) if wreck else Color(0.75, 0.85, 1.0)
	label.no_depth_test = true
	label.position = Vector3(0, radius * 0.6 + 3.0, 0)
	label.visible = false
	add_child(label)


func _collect(node: Node) -> void:
	if node is Node3D and node.has_meta("flame"):
		_flames.append(node)
	for c in node.get_children():
		_collect(c)


func set_flames(on: bool) -> void:
	for f in _flames:
		f.visible = on


func _light(pos: Vector3, col: Color) -> void:
	var mi := MeshInstance3D.new()
	var sp := SphereMesh.new()
	sp.radius = 0.35
	sp.height = 0.7
	sp.radial_segments = 8
	sp.rings = 4
	sp.material = Interiors.glow(col, 4.0)
	mi.mesh = sp
	mi.position = pos
	body.add_child(mi)
	_lights.append(mi)


## A dead ship: the paint goes dull and dark.
func _darken(node: Node) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.22, 0.21, 0.2)
		m.roughness = 0.95
		mi.material_override = m
	for c in node.get_children():
		_darken(c)


## Show the tag with the distance when the viewer is within `range_m`.
func show_tag(viewer: Vector3, range_m: float) -> void:
	var d := global_position.distance_to(viewer)
	label.visible = d < range_m and d > radius * 2.0
	if label.visible:
		label.text = "%s\n%s" % [title, ("%.1f km" % (d / 1000.0)) if d >= 1000.0 else "%d m" % roundi(d)]


func _process(delta: float) -> void:
	_t += delta
	for i in _lights.size():   # side lights steady, strobes blink
		_lights[i].visible = i < 2 or fmod(_t + i * 0.37, 1.6) < 0.12
