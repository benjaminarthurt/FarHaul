extends SceneTree
## Times the slow moments: new game, loading, the board, each scene, the moon descent and a waited day.
## Run: godot --headless --path . --script res://tests/probe_speed.gd
func _initialize() -> void:
	SaveSlots.dir = "user://test_saves_probe_speed"
	process_frame.connect(_run, CONNECT_ONE_SHOT)
func _t(label: String, t0: int) -> int:
	var t := Time.get_ticks_msec()
	print("%-28s %6d ms" % [label, t - t0])
	return t
func _run() -> void:
	var t := Time.get_ticks_msec()
	Session.begin_new(2, "Pilot", "human", "normal", "roosevelt_independent_yards")
	t = _t("new game (sim warm-up)", t)
	Session.load_slot(2)
	t = _t("load the slot", t)
	var offers := Contracts.offers_from(Session.system_id())
	t = _t("contract board", t)
	var d: Node = load("res://scenes/dock.tscn").instantiate()
	root.add_child(d)
	t = _t("dock scene", t)
	d.queue_free()
	await process_frame
	t = Time.get_ticks_msec()
	var b: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(b)
	t = _t("shipyard scene", t)
	b.queue_free()
	await process_frame
	t = Time.get_ticks_msec()
	Session.flight_job = {}
	var f: Node = load("res://scenes/flight.tscn").instantiate()
	root.add_child(f)
	t = _t("flight scene", t)
	f.job = {"dest_id": "x__moon", "destination": "Moon"}
	f._begin_descent()
	t = _t("moon descent build", t)
	var r := Session.wait_days(1)
	t = _t("wait a day", t)
	quit()
