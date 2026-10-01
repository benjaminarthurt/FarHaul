class_name CargoManifest
extends RefCounted
## What a ship is actually carrying. Plain data, no 3D.
##
## Every cargo module has `cargo_slots` containers of equal size (`cargo_capacity / cargo_slots`).
## A container holds one commodity and can be partly full, so a location with less freight than
## the ship has room for is fine: you simply fly with spare space. Loading tops up partly full
## containers of the same commodity first, then opens empty ones. Unloading empties the least
## full containers first, so loads consolidate instead of leaving many part-full containers.

const EPS := 0.0005

var ship: ShipData
var commodities: CommodityLibrary
var contents: Dictionary = {}  # slot key -> {commodity: StringName, tonnes: float}


func _init(s: ShipData, lib: CommodityLibrary = null) -> void:
	ship = s
	commodities = lib if lib != null else CommodityLibrary.new()


# --- Slots -----------------------------------------------------------------------------------

static func slot_key(origin: Vector3i, index: int) -> String:
	return "%d,%d,%d:%d" % [origin.x, origin.y, origin.z, index]


## Every container on the ship, in placement order: {key, module (index into ship.modules), index, capacity}.
func slots() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for mi in ship.modules.size():
		var m: Dictionary = ship.modules[mi]
		var d := ship.library.get_def(m.id)
		if d.cargo_slots <= 0:
			continue
		var cap := d.cargo_capacity / float(d.cargo_slots)
		for i in d.cargo_slots:
			out.append({"key": slot_key(m.cell, i), "module": mi, "index": i, "capacity": cap})
	return out


## Drop anything that no longer fits the ship (module gone, unknown commodity, over capacity).
func prune() -> void:
	var cap := {}
	for s in slots():
		cap[s.key] = s.capacity
	for k in contents.keys():
		var e: Dictionary = contents[k]
		if not cap.has(k) or not commodities.has(e.commodity) or e.tonnes <= EPS:
			contents.erase(k)
		else:
			e.tonnes = minf(e.tonnes, cap[k])


# --- Queries ---------------------------------------------------------------------------------

func capacity() -> float:
	var t := 0.0
	for s in slots():
		t += s.capacity
	return t


func total() -> float:
	var t := 0.0
	for k in contents:
		t += contents[k].tonnes
	return t


func total_of(c: StringName) -> float:
	var t := 0.0
	for k in contents:
		if contents[k].commodity == c:
			t += contents[k].tonnes
	return t


## commodity -> tonnes aboard.
func by_commodity() -> Dictionary:
	var out := {}
	for k in contents:
		var c: StringName = contents[k].commodity
		out[c] = out.get(c, 0.0) + contents[k].tonnes
	return out


## Containers that hold anything.
func slots_in_use() -> int:
	return contents.size()


## Tonnes of `c` that could still be loaded: room in its part-full containers plus every empty one.
func free_space_for(c: StringName) -> float:
	var t := 0.0
	for s in slots():
		if not contents.has(s.key):
			t += s.capacity
		elif contents[s.key].commodity == c:
			t += s.capacity - contents[s.key].tonnes
	return t


## Tonnes of cargo in the module at `module_index`.
func mass_at(module_index: int) -> float:
	var t := 0.0
	for s in slots():
		if s.module == module_index and contents.has(s.key):
			t += contents[s.key].tonnes
	return t


## Market value of everything aboard at the library's placeholder prices.
func value() -> float:
	var v := 0.0
	for k in contents:
		v += contents[k].tonnes * commodities.price(contents[k].commodity)
	return v


## "" if the module under `cell` can be removed, otherwise why not.
func blocks_removal(cell: Vector3i) -> String:
	if not ship.occupied.has(cell):
		return ""
	var t := mass_at(ship.occupied[cell])
	if t > EPS:
		return "Unload its %.1f t of cargo first" % t
	return ""


## Fill fraction 0..1 of one container, for visuals.
func fill_of(key: String) -> float:
	if not contents.has(key):
		return 0.0
	for s in slots():
		if s.key == key:
			return contents[key].tonnes / s.capacity
	return 0.0


# --- Loading and unloading -------------------------------------------------------------------

## Load up to `tonnes` of `c`. Returns how much actually went aboard, which is less than asked
## when the ship runs out of room for it.
func load(c: StringName, tonnes: float) -> float:
	if not commodities.has(c) or tonnes <= EPS:
		return 0.0
	var left := tonnes
	var all := slots()
	for pass_index in 2:  # first top up part-full containers of this commodity, then open empty ones
		for s in all:
			if left <= EPS:
				break
			var held := 0.0
			if contents.has(s.key):
				if pass_index == 1 or contents[s.key].commodity != c:
					continue
				held = contents[s.key].tonnes
			elif pass_index == 0:
				continue
			var put := minf(s.capacity - held, left)
			if put <= EPS:
				continue
			contents[s.key] = {"commodity": c, "tonnes": snappedf(held + put, 0.001)}
			left -= put
	return snappedf(tonnes - maxf(left, 0.0), 0.001)


## Take off up to `tonnes` of `c`, least full containers first. Returns how much came off.
func unload(c: StringName, tonnes: float) -> float:
	var keys: Array = []
	for k in contents:
		if contents[k].commodity == c:
			keys.append(k)
	keys.sort_custom(func(a: String, b: String) -> bool:
		var ta: float = contents[a].tonnes
		var tb: float = contents[b].tonnes
		return a > b if is_equal_approx(ta, tb) else ta < tb)
	var left := tonnes
	for k in keys:
		if left <= EPS:
			break
		var held: float = contents[k].tonnes
		var take := minf(held, left)
		var rest := snappedf(held - take, 0.001)
		if rest <= EPS:
			contents.erase(k)
		else:
			contents[k].tonnes = rest
		left -= take
	return snappedf(tonnes - maxf(left, 0.0), 0.001)


## Empty the ship. Returns commodity -> tonnes removed.
func unload_all() -> Dictionary:
	var out := by_commodity()
	contents.clear()
	return out


# --- Save / load -----------------------------------------------------------------------------

func to_dict() -> Dictionary:
	var out := {}
	for k in contents:
		out[k] = {"commodity": String(contents[k].commodity), "tonnes": contents[k].tonnes}
	return out


## Replace the manifest from saved data. Entries that don't fit this ship are skipped.
func from_dict(data: Variant) -> void:
	contents = {}
	if typeof(data) != TYPE_DICTIONARY:
		return
	for k in data:
		var e: Variant = data[k]
		if typeof(k) != TYPE_STRING or typeof(e) != TYPE_DICTIONARY:
			continue
		if not e.has("commodity") or not e.has("tonnes"):
			continue
		var c := StringName(str(e["commodity"]))
		var t := float(e["tonnes"])
		if commodities.has(c) and t > EPS:
			contents[k] = {"commodity": c, "tonnes": t}
	prune()
