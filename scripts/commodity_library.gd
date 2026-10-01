class_name CommodityLibrary
extends RefCounted
## What can be hauled. Placeholder goods and prices for now; real trading will set prices per location.
## Units: tonnes and credits per tonne.

var defs: Dictionary = {}  # StringName -> {name: String, price: float, color: Color}
var order: Array[StringName] = []


func _init() -> void:
	_add(&"water", "Water", 30.0, Color(0.35, 0.6, 0.9))
	_add(&"ore", "Iron ore", 90.0, Color(0.6, 0.4, 0.3))
	_add(&"food", "Food", 150.0, Color(0.5, 0.7, 0.35))
	_add(&"machinery", "Machinery", 600.0, Color(0.74, 0.58, 0.22))
	_add(&"electronics", "Electronics", 1500.0, Color(0.65, 0.4, 0.8))


func _add(id: StringName, label: String, price: float, col: Color) -> void:
	defs[id] = {"name": label, "price": price, "color": col}
	order.append(id)


func has(id: StringName) -> bool:
	return defs.has(id)


func label(id: StringName) -> String:
	return defs[id].name if defs.has(id) else String(id)


func price(id: StringName) -> float:
	return defs[id].price if defs.has(id) else 0.0


func color(id: StringName) -> Color:
	return defs[id].color if defs.has(id) else Color(0.7, 0.7, 0.7)
