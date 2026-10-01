class_name ShipView
extends Node3D
## Turns ShipData into 3D nodes. Rebuilds everything on change, which is plenty fast
## at builder scale (tens of modules). Later: keep a node per module and diff instead.


func rebuild(ship: ShipData) -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	for m in ship.modules:
		var node := ship.library.get_def(m.id).build_visual()
		node.position = ShipGrid.cell_to_world(m.cell)
		node.rotation.y = m.rot * PI / 2.0
		add_child(node)
