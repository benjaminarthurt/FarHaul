extends SceneTree
## The economy skips searches an idle carrier already knows will find nothing (EconomySim.search_cache).
## This checks the skip changes nothing: ten days with and without it end in exactly the same state,
## and that it is faster. Run: godot --headless --path . --script res://tests/test_sim_speed.gd
var fails := 0
func check(ok: bool, msg: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + msg)
	if not ok:
		fails += 1
func _initialize() -> void:
	var a := SimWorld.warmed()
	var b := SimWorld.warmed()
	b.search_cache = false
	var t := Time.get_ticks_msec()
	a.run_days(10)
	var ta := Time.get_ticks_msec() - t
	t = Time.get_ticks_msec()
	b.run_days(10)
	var tb := Time.get_ticks_msec() - t
	check(str(a.to_state()) == str(b.to_state()), "ten days end in the same state with and without the skip")
	check(ta < tb, "and run faster with it (%d ms against %d ms)" % [ta, tb])
	# From a cold start too, where the board churns most (the bug this caught: freight taken earlier in
	# the same hour changes what the next carrier sees).
	var c := EconomySim.new()
	c.load_all("res://data/world/", "res://data/runtime/", SimWorld.SCENARIO)
	var d := EconomySim.new()
	d.load_all("res://data/world/", "res://data/runtime/", SimWorld.SCENARIO)
	d.search_cache = false
	c.run_days(60)
	d.run_days(60)
	check(str(c.to_state()) == str(d.to_state()), "sixty days from a cold start end the same")
	print("DONE fails=", fails)
	quit(1 if fails > 0 else 0)
