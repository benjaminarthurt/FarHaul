class_name ShipData
extends RefCounted
## The ship as plain data: a list of {id, cell, rot}. Nothing 3D in here.
## Flight, interior walking, saving and NPC ships should all read from this.

var library: ModuleLibrary
var modules: Array[Dictionary] = []  # each: {id: StringName, cell: Vector3i, rot: int 0..3}
var occupied: Dictionary = {}  # Vector3i -> index into modules


func _init(lib: ModuleLibrary) -> void:
	library = lib


# --- Queries ------------------------------------------------------------------------------

func world_cells(id: StringName, origin: Vector3i, rot: int) -> Array[Vector3i]:
	var out: Array[Vector3i] = []
	for c in library.get_def(id).get_cells():
		out.append(origin + ShipGrid.rotate_cell(c, rot))
	return out


func world_sockets(id: StringName, origin: Vector3i, rot: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for s in library.get_def(id).sockets:
		out.append({
			"cell": origin + ShipGrid.rotate_cell(s.cell, rot),
			"dir": ShipGrid.rotate_cell(s.dir, rot),
			"kind": s.kind,
		})
	return out


## Empty string means the module can go there; otherwise the reason it can't.
func check_place(id: StringName, origin: Vector3i, rot: int) -> String:
	for c in world_cells(id, origin, rot):
		if occupied.has(c):
			return "Overlaps another module"
	if modules.is_empty():
		return ""  # first module can go anywhere

	# Try it: does the new module end up attached to anything, in either direction?
	var trial: Array[Dictionary] = []
	for m in modules:
		trial.append(m)
	trial.append({"id": id, "cell": origin, "rot": rot})
	var trial_occ := occupied.duplicate()
	for c in world_cells(id, origin, rot):
		trial_occ[c] = trial.size() - 1
	var adj := _adjacency(trial, trial_occ)
	if adj[trial.size() - 1].is_empty():
		return "Needs a matching door or mount touching the ship"
	return ""


# --- Edits (each returns "" on success, or an error message) ---------------------------------

func add(id: StringName, origin: Vector3i, rot: int) -> String:
	var err := check_place(id, origin, rot)
	if err != "":
		return err
	modules.append({"id": id, "cell": origin, "rot": ((rot % 4) + 4) % 4})
	occupied = _build_occupied(modules)
	return ""


## Removes the module occupying `cell`, unless that would split the ship into pieces.
func remove_at(cell: Vector3i) -> String:
	if not occupied.has(cell):
		return "Nothing there to remove"
	var idx: int = occupied[cell]
	var rest: Array[Dictionary] = []
	for i in modules.size():
		if i != idx:
			rest.append(modules[i])
	if not _is_one_piece(rest):
		return "Removing that would split the ship in two"
	modules = rest
	occupied = _build_occupied(modules)
	return ""


## Doorways that open onto space: a door socket whose neighbouring cell is empty or holds an
## external part. (A door facing another room's blank wall is sealed by that wall.)
func open_doors() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for mi in modules.size():
		var m: Dictionary = modules[mi]
		for s in world_sockets(m.id, m.cell, m.rot):
			if s.kind != ModuleSocket.DOOR:
				continue
			var nb: Vector3i = s.cell + s.dir
			var open := not occupied.has(nb)
			if not open:
				var other: Dictionary = modules[occupied[nb]]
				open = not library.get_def(other.id).pressurized
			if open:
				out.append({"module": mi, "cell": s.cell, "dir": s.dir})
	return out


func clear() -> void:
	modules = []
	occupied = {}


# --- Save / load -----------------------------------------------------------------------------

func to_json() -> String:
	var arr := []
	for m in modules:
		arr.append({"id": String(m.id), "cell": [m.cell.x, m.cell.y, m.cell.z], "rot": m.rot})
	return JSON.stringify({"version": 1, "modules": arr}, "\t")


## Replaces the ship with the saved one. Returns false (and changes nothing) if the data
## is malformed, uses unknown modules, overlaps, or isn't one connected ship.
func from_json(text: String) -> bool:
	var json := JSON.new()
	if json.parse(text) != OK:
		return false
	var parsed: Variant = json.data
	if typeof(parsed) != TYPE_DICTIONARY or not parsed.has("modules"):
		return false
	var fresh: Array[Dictionary] = []
	var occ := {}
	for e in parsed["modules"]:
		if typeof(e) != TYPE_DICTIONARY or not e.has("id") or not e.has("cell"):
			return false
		var id := StringName(str(e["id"]))
		if not library.has_def(id):
			return false
		var c: Array = e["cell"]
		if c.size() != 3:
			return false
		var origin := Vector3i(int(c[0]), int(c[1]), int(c[2]))
		var rot := ((int(e.get("rot", 0)) % 4) + 4) % 4
		for wc in world_cells(id, origin, rot):
			if occ.has(wc):
				return false
			occ[wc] = fresh.size()
		fresh.append({"id": id, "cell": origin, "rot": rot})
	if not _is_one_piece(fresh):
		return false
	modules = fresh
	occupied = occ
	return true


# --- Internals -------------------------------------------------------------------------------

func _build_occupied(list: Array[Dictionary]) -> Dictionary:
	var occ := {}
	for i in list.size():
		var m: Dictionary = list[i]
		for c in world_cells(m.id, m.cell, m.rot):
			occ[c] = i
	return occ


## Index of the module that socket `s` attaches to, or -1 if it attaches to nothing.
## A socket attaches to a socket of the same kind facing it. A MOUNT socket also attaches
## to any bare (doorless) face of a pressurised module.
func _mate_of(s: Dictionary, list: Array[Dictionary], occ: Dictionary) -> int:
	var nb: Vector3i = s.cell + s.dir
	if not occ.has(nb):
		return -1
	var j: int = occ[nb]
	var other: Dictionary = list[j]
	var facing: Vector3i = -s.dir  # the neighbour's face that touches us
	var blocked := false
	for t in world_sockets(other.id, other.cell, other.rot):
		if t.cell == nb and t.dir == facing:
			if t.kind == s.kind:
				return j
			blocked = true  # that face has a doorway, so nothing can bolt over it
	if s.kind == ModuleSocket.MOUNT and not blocked and library.get_def(other.id).pressurized:
		return j
	return -1


## For each module, the indices of modules attached to it (a link counts from either side).
func _adjacency(list: Array[Dictionary], occ: Dictionary) -> Array:
	var adj: Array = []
	for i in list.size():
		adj.append([])
	for i in list.size():
		var m: Dictionary = list[i]
		for s in world_sockets(m.id, m.cell, m.rot):
			var j := _mate_of(s, list, occ)
			if j != -1 and j != i:
				if not adj[i].has(j):
					adj[i].append(j)
				if not adj[j].has(i):
					adj[j].append(i)
	return adj


## True if every module is reachable from the first through doors and mounts.
func _is_one_piece(list: Array[Dictionary]) -> bool:
	if list.size() <= 1:
		return true
	var adj := _adjacency(list, _build_occupied(list))
	var seen := {0: true}
	var stack: Array[int] = [0]
	while not stack.is_empty():
		var i: int = stack.pop_back()
		for j in adj[i]:
			if not seen.has(j):
				seen[j] = true
				stack.append(j)
	return seen.size() == list.size()
