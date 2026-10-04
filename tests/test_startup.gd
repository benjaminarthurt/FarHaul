extends SceneTree
## Startup speed and settings: the shipped warm start matches the data (rebuild it with
## tests/make_warm_start.gd if this fails), a new game starts quickly, and settings save and load.
## Run: godot --headless --path . --script res://tests/test_startup.gd
var fails := 0
func check(ok: bool, msg: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + msg)
	if not ok:
		fails += 1
func _initialize() -> void:
	SaveSlots.dir = "user://test_saves_startup"
	process_frame.connect(_run, CONNECT_ONE_SHOT)
func _run() -> void:
	var f := FileAccess.open_compressed(SimWorld.WARM_START, FileAccess.READ, FileAccess.COMPRESSION_ZSTD)
	check(f != null, "the warm start ships with the game")
	var stored: Dictionary = f.get_var() if f != null else {}
	check(String(stored.get("fingerprint", "")) == SimWorld.data_fingerprint(), "the warm start matches the current data (else run tests/make_warm_start.gd)")
	var t := Time.get_ticks_msec()
	check(Session.begin_new(1, "Quick", "human", "normal", "roosevelt_independent_yards"), "a new game starts")
	var ms := Time.get_ticks_msec() - t
	check(ms < 2000, "in %d ms" % ms)
	check(Session.day() == SimWorld.WARMUP_DAYS, "on day %d, straight after the warm-up" % Session.day())
	var local := 0
	for o in Contracts.offers_from(Session.system_id()):
		if bool(o.get("local", false)):
			local += 1
	check(local >= 3, "with local work on the board (%d runs)" % local)
	# Settings round trip.
	GameSettings.reload()
	check(GameSettings.quality() == "medium", "graphics default to medium")
	GameSettings.set_value("quality", "high")
	GameSettings.set_value("music", 0.3)
	GameSettings.reload()
	check(GameSettings.quality() == "high" and is_equal_approx(float(GameSettings.get_value("music")), 0.3), "settings save and load")
	check(AudioServer.get_bus_index("Music") >= 0 and AudioServer.get_bus_index("Effects") >= 0, "music and effects buses exist")
	check(absf(AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Music")) - linear_to_db(0.3)) < 0.01, "the music volume is applied")
	GameSettings.set_value("quality", "medium")
	GameSettings.set_value("music", 0.7)
	print("startup tests: %s" % ("FAIL (%d)" % fails if fails > 0 else "all passed"))
	quit(1 if fails > 0 else 0)
