extends SceneTree
## Renders the freight office's standing section, opened to who thinks what (run under xvfb-run, not --headless).
## xvfb-run -a godot --path . --rendering-driver opengl3 -s tests/capture_standing.gd -- /tmp/standing_frames
func _initialize() -> void:
	SaveSlots.dir = "user://test_saves_capture_standing"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SaveSlots.dir))
	process_frame.connect(_run, CONNECT_ONE_SHOT)


func _run() -> void:
	var out := "/tmp/standing_frames"
	for a in OS.get_cmdline_user_args():
		out = a
	DirAccess.make_dir_recursive_absolute(out)
	Hazards.off = true
	Session.begin_new(2, "Pilot", "human", "normal", "roosevelt_independent_yards")
	var port := String(Session.profile.port_id)
	var st := Reputation.state(Session.profile)
	var now := Session._now_h()
	st.places = {port: 22.0, "new_houston__moon": 9.0, "new_houston__camp": -14.0, String(LocalSpace.nodes("keshar")[0].id): 31.0}
	st.species = {"human": 6.0, "kesh": 12.0, "vey": -4.0}
	Reputation.record(st, now, "new_houston", port, -6.0, "record")   # docked without asking, more than once
	Reputation.record(st, now, "new_houston", port, 3.0, "rescue", ["ilyan"])
	Session.profile["location"] = "dock"
	Session.profile["hints_seen"] = ["welcome", "money", "crew", "holding", "arrived", "hab", "hut"]
	Session.save_profile()
	var p: Node = load(Session.PLACE_SCENE).instantiate()
	root.add_child(p)
	await process_frame
	p.desks_c._standing_open = true
	p.use_desk("freight")
	await process_frame
	await process_frame
	var sc := _scroller(p.panel)
	if sc != null:
		sc.scroll_vertical = 100000
	await _shot(out, "01_standing")
	quit(0)


func _scroller(n: Node) -> ScrollContainer:
	if n is ScrollContainer:
		return n
	for c in n.get_children():
		var s := _scroller(c)
		if s != null:
			return s
	return null


func _shot(out: String, name: String) -> void:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png("%s/%s.png" % [out, name])
	print("shot ", name)
