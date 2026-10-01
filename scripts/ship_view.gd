class_name ShipView
extends Node3D
## Turns ShipData into 3D nodes. Rebuilds everything on change, which is plenty fast
## at builder scale (tens of modules). Later: keep a node per module and diff instead.
##
## Also draws pulsing rings on open doorways, can hide decks above the one being built on,
## and can light the engine plumes.

var _rings: Array[Node3D] = []
var _flames: Array[MeshInstance3D] = []
var _flames_on := false
var _time := 0.0
var _ring_mesh: TorusMesh
var _ring_mat: StandardMaterial3D

var hide_above := false
var deck := 0


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
	for mi in ship.modules.size():
		var m: Dictionary = ship.modules[mi]
		var node := ship.library.get_def(m.id).build_visual()
		node.position = ShipGrid.cell_to_world(m.cell)
		node.rotation.y = m.rot * PI / 2.0
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
	set_deck_filter(deck, hide_above)
	set_flames(_flames_on)


func set_deck_filter(level: int, hide: bool) -> void:
	deck = level
	hide_above = hide
	for child in get_children():
		if child.has_meta("deck"):
			child.visible = not (hide and int(child.get_meta("deck")) > level)


func set_flames(on: bool) -> void:
	_flames_on = on
	for f in _flames:
		f.visible = on


func _collect_flames(node: Node) -> void:
	if node is MeshInstance3D and node.has_meta("flame"):
		_flames.append(node)
	for c in node.get_children():
		_collect_flames(c)


func _process(delta: float) -> void:
	_time += delta
	var pulse := 1.0 + 0.1 * sin(_time * 4.0)
	for r in _rings:
		r.scale = Vector3.ONE * pulse
	if _flames_on:
		for f in _flames:
			f.scale = Vector3(1.0 + 0.08 * sin(_time * 53.0), 1.0 + 0.18 * sin(_time * 31.0 + 1.0), 1.0 + 0.08 * sin(_time * 47.0))


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
