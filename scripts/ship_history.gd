class_name ShipHistory
extends RefCounted
## Undo and redo as whole-ship snapshots. A snapshot is whatever dictionary the caller wants
## (ship JSON plus cargo). Ships are tiny, so storing copies is simpler than storing diffs.

const LIMIT := 60

var _undo: Array[Dictionary] = []
var _redo: Array[Dictionary] = []


func can_undo() -> bool:
	return not _undo.is_empty()


func can_redo() -> bool:
	return not _redo.is_empty()


## Call with the state from BEFORE a change.
func record(before: Dictionary) -> void:
	_undo.append(before)
	if _undo.size() > LIMIT:
		_undo.pop_front()
	_redo.clear()


## Pass the current state; returns the one to restore.
func undo(current: Dictionary) -> Dictionary:
	var prev: Dictionary = _undo.pop_back()
	_redo.append(current)
	return prev


func redo(current: Dictionary) -> Dictionary:
	var next: Dictionary = _redo.pop_back()
	_undo.append(current)
	return next


func clear() -> void:
	_undo.clear()
	_redo.clear()
