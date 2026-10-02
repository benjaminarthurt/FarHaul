class_name SaveSlots
extends RefCounted
## Five save slots, one JSON file each. A save holds the ship, its cargo, progress and the
## player's profile (name, race, difficulty, world, ship name, where they are).
## Nothing here ever deletes a save: overwriting a slot parks the old file beside it first.

const COUNT := 5
const LEGACY_AUTOSAVE := "user://autosave.json"

static var dir := "user://saves"


static func path(slot: int) -> String:
	return "%s/slot_%d.json" % [dir, slot + 1]


static func exists(slot: int) -> bool:
	return FileAccess.file_exists(path(slot))


## The whole save as a dictionary, or {} if the slot is empty or unreadable.
static func read(slot: int) -> Dictionary:
	if not exists(slot):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path(slot)))
	return parsed if typeof(parsed) == TYPE_DICTIONARY else {}


## The profile part of a slot (see Session.default_profile), or {} if empty.
static func profile(slot: int) -> Dictionary:
	var data := read(slot)
	if data.is_empty():
		return {}
	var p: Variant = data.get("profile", {})
	var out := Session.default_profile()
	if typeof(p) == TYPE_DICTIONARY:
		out.merge(p, true)
	return out


static func write(slot: int, data: Dictionary) -> bool:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	if data.has("profile") and typeof(data.profile) == TYPE_DICTIONARY:
		data.profile["saved_at"] = int(Time.get_unix_time_from_system())
	var f := FileAccess.open(path(slot), FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(data, "\t"))
	f.close()
	return true


## Moves an existing save aside under a timestamped name so it can be restored by hand.
static func park(slot: int) -> void:
	if not exists(slot):
		return
	var stamp := Time.get_datetime_string_from_system().replace(":", "-")
	DirAccess.rename_absolute(ProjectSettings.globalize_path(path(slot)),
		ProjectSettings.globalize_path("%s/slot_%d-replaced-%s.json" % [dir, slot + 1, stamp]))


## The slot saved most recently, or -1 if there are none.
static func latest() -> int:
	var best := -1
	var best_time := -1
	for i in COUNT:
		if not exists(i):
			continue
		var t := int(profile(i).get("saved_at", 0))
		if t > best_time:
			best_time = t
			best = i
	return best


static func first_empty() -> int:
	for i in COUNT:
		if not exists(i):
			return i
	return -1


## Brings an old single-file autosave into slot 1 the first time, leaving the original in place.
static func import_legacy() -> void:
	if not FileAccess.file_exists(LEGACY_AUTOSAVE) or latest() >= 0:
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(LEGACY_AUTOSAVE))
	if typeof(parsed) != TYPE_DICTIONARY or not parsed.has("modules"):
		return
	var p := Session.default_profile()
	p["location"] = "shipyard"
	parsed["profile"] = p
	write(0, parsed)
