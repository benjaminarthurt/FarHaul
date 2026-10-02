class_name CommodityLibrary
extends RefCounted
## Canonical freight catalogue loaded from data/world/commodities.json.
## CargoManifest still measures ship capacity in tonnes; JSON mass/unit and SCU fields are retained
## for the market/contract layer and future physical container loading.

const PATH := "res://data/world/commodities.json"

var defs: Dictionary = {}  # StringName -> canonical commodity record plus runtime display fields
var order: Array[StringName] = []


func _init() -> void:
	if not FileAccess.file_exists(PATH):
		push_error("Missing commodity data: %s" % PATH)
		return
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("Invalid commodity JSON: %s" % PATH)
		return
	for raw in parsed.get("commodities", []):
		var id := StringName(String(raw.id))
		var d: Dictionary = raw.duplicate(true)
		d["price"] = float(raw.get("base_value", 0))
		d["color"] = _category_color(String(raw.get("category", "")))
		defs[id] = d
		order.append(id)


func _category_color(category: String) -> Color:
	match category:
		"food", "agriculture": return Color(0.5, 0.7, 0.35)
		"medical", "biological": return Color(0.35, 0.75, 0.7)
		"raw_material": return Color(0.55, 0.48, 0.42)
		"chemical": return Color(0.75, 0.65, 0.25)
		"research", "information": return Color(0.55, 0.55, 0.9)
		"ship_industrial", "industrial", "infrastructure": return Color(0.72, 0.56, 0.24)
		"manufactured", "consumer": return Color(0.62, 0.45, 0.78)
		"environmental": return Color(0.3, 0.62, 0.82)
		_: return Color(0.7, 0.7, 0.7)


func has(id: StringName) -> bool:
	return defs.has(id)


func label(id: StringName) -> String:
	return defs[id].name if defs.has(id) else String(id)


func price(id: StringName) -> float:
	return defs[id].price if defs.has(id) else 0.0


func color(id: StringName) -> Color:
	return defs[id].color if defs.has(id) else Color(0.7, 0.7, 0.7)


func record(id: StringName) -> Dictionary:
	return defs.get(id, {})


func tonnes_per_unit(id: StringName) -> float:
	return float(defs[id].mass_kg_per_unit) / 1000.0 if defs.has(id) else 0.0
