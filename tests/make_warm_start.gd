extends SceneTree
## Rebuilds data/runtime/warm_start.bin: the economy after its warm-up, shipped so a new game starts in
## a moment instead of seconds. Run after changing anything in data/world or data/runtime:
##   godot --headless --path . --script res://tests/make_warm_start.gd
func _initialize() -> void:
	var ok := SimWorld.write_warm_start(ProjectSettings.globalize_path(SimWorld.WARM_START))
	print("warm start: %s (%s)" % ["written" if ok else "FAILED", SimWorld.data_fingerprint()])
	quit(0 if ok else 1)
