class_name ShipView
extends Node3D
## Turns ShipData into 3D nodes. Rebuilds everything on change, which is plenty fast
## at builder scale (tens of modules). Later: keep a node per module and diff instead.
##
## Also draws pulsing rings on open doorways, can hide decks above the one being built on,
## and can light the engine plumes.

var _rings: Array[Node3D] = []
var _flames: Array[Node3D] = []      ## plume pivots at each engine's mouth (EngineParts.plume)
var _flames_on := false
var _throttle := 1.0
var _lift_flames: Array[Node3D] = []
var _lift_dirty := true
var _time := 0.0
var _ring_mesh: TorusMesh
var _ring_mat: StandardMaterial3D

var hide_above := false
var deck := 0
var skin := false   ## wear the outer hull (ShipSkin): in flight and on the menus, not in the builder
var _damage: ShipDamage        ## scorches, venting and sparks on the skin (set_damage)
var _damage_level := 0.0


func _ready() -> void:
	_ring_mesh = TorusMesh.new()
	_ring_mesh.inner_radius = 0.6
	_ring_mesh.outer_radius = 0.84
	_ring_mesh.rings = 24
	_ring_mesh.ring_segments = 8
	_ring_mat = StandardMaterial3D.new()
	_ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ring_mat.albedo_color = Color(0.3, 0.9, 1.0)
	_ring_mat.emission_enabled = true
	_ring_mat.emission = Color(0.3, 0.9, 1.0)
	_ring_mat.emission_energy_multiplier = 1.4
	_ring_mesh.material = _ring_mat


## With a manifest, containers show what they hold. `pop_index` makes that module pop into place.
func rebuild(ship: ShipData, manifest: CargoManifest = null, pop_index := -1) -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_rings.clear()
	_flames.clear()
	_lift_dirty = true
	_retro_dirty = true
	_rcs_dirty = true
	var press := ShipSkin.pressurised_cells(ship) if skin else {}
	for mi in ship.modules.size():
		var m: Dictionary = ship.modules[mi]
		var node := ship.library.get_def(m.id).build_visual()
		node.position = ShipGrid.cell_to_world(m.cell)
		if skin:   # external parts sit out on the skin, not buried in it
			node.position += ShipSkin.mount_offset(ship, m, press)
		node.rotation.y = m.rot * PI / 2.0
		if ship.library.get_def(m.id).hug:
			_hug(node, ship, m)
		node.set_meta("deck", m.cell.y)
		if manifest != null:
			_apply_cargo(node, m.cell, manifest)
		_collect_flames(node)
		add_child(node)
		if mi == pop_index:
			node.scale = Vector3.ONE * 0.6
			var t := create_tween()
			t.tween_property(node, "scale", Vector3.ONE, 0.28).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	for d in ship.open_doors():
		var ring := MeshInstance3D.new()
		ring.mesh = _ring_mesh
		var n := Vector3(d.dir)
		ring.position = ShipGrid.cell_to_world(d.cell) + n * (ShipGrid.CELL * 0.5 + 0.03)
		ring.basis = Basis(Quaternion(Vector3.UP, n))
		add_child(ring)
		_rings.append(ring)
	if skin:   # under a hull nobody needs to see in from above, and from inside you'd see the hull
		add_child(ShipSkin.build(ship))
		_set_ceilings(self, true)
		_damage = ShipDamage.new()
		_damage.setup(ship)
		add_child(_damage)
		_damage.set_damage(_damage_level)
		_damage.set_patched(_patched)
	else:
		_damage = null
	set_deck_filter(deck, hide_above)
	set_flames(_flames_on)


## Slide a low-profile part's body flat against the hull it's bolted to, and turn it so its thin side
## faces the hull: on top or underneath it lies flat; on a side it stands on edge.
func _hug(node: Node3D, ship: ShipData, m: Dictionary) -> void:
	var body := node.get_node_or_null("Body") as Node3D
	if body == null:
		return
	var hull := {}
	for other in ship.modules:
		if ship.library.get_def(other.id).pressurized:
			for c in ship.world_cells(other.id, other.cell, other.rot):
				hull[c] = true
	var cell: Vector3i = m.cell
	for n in [Vector3i(0, -1, 0), Vector3i(0, 1, 0), Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]:
		if hull.has(cell + n):
			var local := Basis(Vector3.UP, m.rot * PI / 2.0).inverse() * Vector3(n)
			body.position = local * HUG_IN
			if absf(local.x) > 0.5:
				body.rotation.z = PI * 0.5 * signf(local.x)   # on a side: the flat foot turns to face it
			elif local.y > 0.5:
				body.rotation.z = PI                       # underneath a deck above: upside down
			return


const HUG_IN := 1.2   ## how far a low-profile part's body moves from its cell's centre toward the hull


func set_deck_filter(level: int, hide: bool) -> void:
	deck = level
	hide_above = hide
	for child in get_children():
		if child.has_meta("deck"):
			child.visible = not (hide and int(child.get_meta("deck")) > level)


var _patched: Array = []


## Spots welded over on a space walk (ShipDamage mark indexes).
func set_patched(list: Array) -> void:
	_patched = list.duplicate()
	if _damage != null:
		_damage.set_patched(_patched)


## How battered the hull looks, 0 (new) .. 1 (breached). Only a skinned ship shows it.
func set_damage(d: float) -> void:
	_damage_level = d
	if _damage != null:
		_damage.set_damage(d)


func set_flames(on: bool) -> void:
	_flames_on = on
	for f in _flames:
		f.visible = on


## How hard the engines burn, 0..1: the plumes grow longer and brighter with it.
func set_throttle(t: float) -> void:
	_throttle = clampf(t, 0.0, 1.0)
	for f in _flames:
		for c in f.get_children():
			if c is GeometryInstance3D:
				(c as GeometryInstance3D).set_instance_shader_parameter("power", 0.35 + 0.65 * _throttle)


func _collect_flames(node: Node) -> void:
	if node is Node3D and node.has_meta("flame"):
		_flames.append(node)
	for c in node.get_children():
		_collect_flames(c)


func _process(delta: float) -> void:
	_time += delta
	var pulse := 1.0 + 0.1 * sin(_time * 4.0)
	for r in _rings:
		r.scale = Vector3.ONE * pulse
	if _flames_on:   # a little life in the plume; its length follows the throttle
		var length := 0.4 + 0.6 * _throttle
		for f in _flames:
			f.scale = Vector3(1.0 + 0.03 * sin(_time * 53.0), length * (1.0 + 0.05 * sin(_time * 31.0 + 1.0)), 1.0 + 0.03 * sin(_time * 47.0))


func _apply_cargo(node: Node, origin: Vector3i, manifest: CargoManifest) -> void:
	if node is Node3D and node.has_meta("slot"):
		var key := CargoManifest.slot_key(origin, node.get_meta("slot"))
		var fill := manifest.fill_of(key)
		node.visible = fill > 0.0
		if fill > 0.0:
			var h: float = node.get_meta("height")
			var h_now := maxf(h * fill, 0.15)
			node.scale.y = h_now / h
			node.position.y = float(node.get_meta("bottom_y")) + h_now * 0.5
			var goods: StringName = manifest.contents[key].commodity
			var col := manifest.commodities.color(goods)
			_paint(node, col)
			_stencil(node, manifest.commodities.label(goods), col)
		return
	for child in node.get_children():
		_apply_cargo(child, origin, manifest)


## Recolour a container (body and ribs) to its commodity.
func _paint(node: Node, col: Color) -> void:
	if node is MeshInstance3D and node.has_meta("paint"):
		var mat := StandardMaterial3D.new()
		mat.albedo_color = col.darkened(1.0 - float(node.get_meta("paint")))
		mat.roughness = 0.8
		SurfaceTextures.apply_panel(mat)
		node.material_override = mat
	for child in node.get_children():
		_paint(child, col)


## Stencil the commodity name on both sides of a container.
func _stencil(container: Node3D, text: String, col: Color) -> void:
	for side in [-1.0, 1.0]:
		var label := Label3D.new()
		label.text = text.to_upper()
		label.font_size = 64
		label.pixel_size = 0.0042
		label.modulate = Color(0.95, 0.95, 0.9) if col.get_luminance() < 0.45 else Color(0.1, 0.1, 0.12)
		label.outline_size = 0
		var box_x := 0.5 * float(container.get_meta("width"))
		label.position = Vector3(side * (box_x + 0.04), 0, 0)
		label.rotation_degrees.y = 90.0 * side
		label.scale.y = 1.0 / maxf(container.scale.y, 0.05)  # stay readable on part-full boxes
		container.add_child(label)


## Walking inside: ceilings go solid (they are see-through so the builder can look in from above).
func set_interior(on: bool) -> void:
	_set_ceilings(self, on or skin)


func _set_ceilings(node: Node, on: bool) -> void:
	if node is MeshInstance3D and node.has_meta("ceiling"):
		var mi := node as MeshInstance3D
		if on:
			var src := (mi.mesh as PrimitiveMesh).material as StandardMaterial3D if mi.mesh is PrimitiveMesh else null
			var m := StandardMaterial3D.new()
			m.albedo_color = Color(src.albedo_color, 1.0) if src != null else Color(0.35, 0.37, 0.4)
			m.roughness = 0.8
			SurfaceTextures.apply_panel(m)
			mi.material_override = m
		else:
			mi.material_override = null
	for c in node.get_children():
		_set_ceilings(c, on)


## Lift-jet plumes under lander legs. The plumes are found once per rebuild.
var _retro_flames: Array[Node3D] = []
var _retro_dirty := true


## The braking thrusters' plumes, out of the bow.
func set_retro_flames(on: bool) -> void:
	if _retro_dirty or (_retro_flames.size() > 0 and not is_instance_valid(_retro_flames[0])):
		_retro_flames.clear()
		_find_tag(self, "retro_flame", _retro_flames)
		_retro_dirty = false
	for f in _retro_flames:
		f.visible = on


var _rcs_flames: Array = []   ## [plume, push direction in the ship's frame]
var _rcs_dirty := true


## Light the manoeuvring nozzles that push the way `strafe` asks (x right, y up, in the ship's frame).
func set_rcs(strafe: Vector2) -> void:
	if _rcs_dirty or (_rcs_flames.size() > 0 and not is_instance_valid(_rcs_flames[0][0])):
		_rcs_flames.clear()
		if not is_inside_tree():
			return
		var found: Array[Node3D] = []
		_find_tag(self, "rcs_flame", found)
		var to_ship := global_basis.inverse()
		for f in found:   # a plume runs along its pivot's +Y, away from the nozzle: the push is the other way
			_rcs_flames.append([f, -(to_ship * f.global_basis.y).normalized()])
		_rcs_dirty = false
	var want := Vector3(strafe.x, strafe.y, 0.0)
	for pair in _rcs_flames:
		(pair[0] as Node3D).visible = want.length() > 0.05 and (pair[1] as Vector3).dot(want) > 0.5


func _find_tag(node: Node, tag: String, out: Array[Node3D]) -> void:
	if node is Node3D and node.has_meta(tag):
		out.append(node)
	for c in node.get_children():
		_find_tag(c, tag, out)


func set_lift_flames(on: bool) -> void:
	if _lift_dirty:
		_lift_flames.clear()
		_find_lift(self)
		_lift_dirty = false
	for f in _lift_flames:
		f.visible = on


func _find_lift(node: Node) -> void:
	if node is Node3D and node.has_meta("lift_flame"):
		_lift_flames.append(node)
	for c in node.get_children():
		_find_lift(c)
