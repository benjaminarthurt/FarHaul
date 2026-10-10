extends SceneTree
## Renders the info site's "every system its own place" screenshots with the HUD hidden
## (run under xvfb-run, not --headless). Saves PNGs to the output folder; they are converted to JPEG
## for site/img.
## xvfb-run -a godot --path . --resolution 1280x720 -s tests/capture_site_shots.gd -- /tmp/site_shots
const PLACES := [
	# [file, port id or "sys__kind", walker position, facing]
	["sys-keshar", "keshar", Vector3(-22.0, 0, 1.5), Vector3(1, 0, -0.18)],
	["sys-ilos", "ilos", Vector3(-22.0, 0, 1.5), Vector3(1, 0, -0.2)],
	["sys-veyara", "veyara", Vector3(-22.0, 0, 1.5), Vector3(1, 0, -0.2)],
	["sys-orun", "orun", Vector3(-22.0, 0, 1.5), Vector3(1, 0, -0.15)],
	["sys-meridian", "port_meridian", Vector3(-14.0, 0, 1.5), Vector3(1, 0, -0.25)],
	["sys-talos", "talos", Vector3(-12.0, 0, 1.2), Vector3(1, 0, -0.25)],
	["sys-pelagos", "pelagos", Vector3(-17.0, 0, 1.0), Vector3(1, 0, -0.3)],
	["sys-keshar-hab", "keshar__pad", Vector3(-7.5, 0, 0), Vector3(1, 0, -0.35)],
]
const STATIONS := [
	# [file, port id or "sys__kind", camera position, looking at]
	["stn-iron-gate", "iron_gate", Vector3(-46, 22, -88), Vector3(0, 0, -30)],
	["stn-belt", "carver__belt", Vector3(-58, 16, -118), Vector3(0, -2, -55)],
	["stn-depot", "veyara__depot", Vector3(-44, 20, -88), Vector3(0, 0, -32)],
	["stn-ilos", "ilos", Vector3(-58, 26, -104), Vector3(0, 0, -45)],
]
func _initialize() -> void:
	SaveSlots.dir = "user://test_saves_capture_site_%d" % OS.get_process_id()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SaveSlots.dir))
	process_frame.connect(_run, CONNECT_ONE_SHOT)
func _id(key: String) -> Array:
	if LocalSpace.SEP in key:
		return [key.get_slice(LocalSpace.SEP, 0), key]
	return [key, String(Worlds.primary_port(key).id)]
func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var out := "/tmp/site_shots" if args.is_empty() else String(args[0])
	DirAccess.make_dir_recursive_absolute(out)
	Session.begin_new(2, "Pilot", "human", "normal", "roosevelt_independent_yards")
	Session.flight_job = {}
	Session.profile["hints_seen"] = ["welcome", "holding", "arrived", "money", "hab", "hut"]
	for s in PLACES:
		var ids := _id(String(s[1]))
		Session.profile["system_id"] = ids[0]
		Session.profile["port_id"] = ids[1]
		var p: Node = load(Session.PLACE_SCENE).instantiate()
		root.add_child(p)
		await process_frame
		p.walker.pos = s[2]
		p.walker.face(s[3])
		p._apply_camera()
		_hide_hud(p)
		await _shot(out, s[0])
		p.queue_free()
		await process_frame
	for s in STATIONS:
		var ids := _id(String(s[1]))
		Session.profile["system_id"] = ids[0]
		Session.profile["port_id"] = ids[1]
		var f: Node = load(Session.FLIGHT_SCENE).instantiate()
		root.add_child(f)
		await process_frame
		f.set_process(false)
		var cam: Camera3D = f.camera
		cam.global_position = s[2]
		cam.look_at(s[3], Vector3.UP)
		_hide_hud(f)
		await _shot(out, s[0])
		f.queue_free()
		await process_frame
	quit(0)
func _hide_hud(n: Node) -> void:
	for c in n.find_children("*", "CanvasLayer", true, false):
		(c as CanvasLayer).visible = false
func _shot(out: String, name: String) -> void:
	for i in 4:
		await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png("%s/%s.png" % [out, name])
	print("shot ", name)
