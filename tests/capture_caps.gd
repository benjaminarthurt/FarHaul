extends SceneTree
## Renders door caps: a ship with a solid cap and a porthole cap over spare doorways, from outside in flight
## (under the hull), from the builder's view (no hull) and from inside, looking out of the porthole.
## xvfb-run -a godot --path . --resolution 1280x720 -s tests/capture_caps.gd -- OUT
const CAPS_SHIP := [
	[&"cockpit", Vector3i(0, 0, 0), 0],
	[&"tee", Vector3i(0, 0, 1), 0],
	[&"airlock", Vector3i(1, 0, 1), 0],
	[&"tee", Vector3i(0, 0, 2), 2],
	[&"porthole_cap", Vector3i(-1, 0, 2), 3],
	[&"tee", Vector3i(0, 0, 3), 0],
	[&"door_cap", Vector3i(1, 0, 3), 1],
	[&"cargo_hold", Vector3i(0, 0, 4), 0],
	[&"engineering", Vector3i(0, 0, 6), 0],
	[&"engine", Vector3i(0, 0, 7), 0],
	[&"radiator", Vector3i(1, 0, 6), 0],
	[&"radiator", Vector3i(-1, 0, 6), 2],
	[&"radiator", Vector3i(1, 0, 5), 0],
	[&"tank", Vector3i(-1, 0, 4), 0],
]
func _initialize() -> void:
	SaveSlots.dir = "user://test_saves_capture_caps_%d" % OS.get_process_id()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SaveSlots.dir))
	process_frame.connect(_run, CONNECT_ONE_SHOT)
func _shot(out: String, name: String) -> void:
	for i in 3:
		await process_frame
	for i in 3:
		await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png("%s/%s.png" % [out, name])
	print("shot ", name)
func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var out := "/tmp/caps_frames" if args.is_empty() else String(args[0])
	DirAccess.make_dir_recursive_absolute(out)
	Session.begin_new(2, "Pilot", "human", "normal", "roosevelt_independent_yards")
	var ship := ShipData.new(ModuleLibrary.new())
	var err := ShipPresets.build(ship, CAPS_SHIP)
	print("build: ", err if err != "" else "ok", "  open doors ", ship.open_doors().size())
	var data := SaveSlots.read(Session.slot)
	data["modules"] = (JSON.parse_string(ship.to_json()) as Dictionary)["modules"]
	data["cargo"] = CargoManifest.new(ship).to_dict()
	SaveSlots.write(Session.slot, data)
	Session.flight_job = {}
	var f: Node = load(Session.FLIGHT_SCENE).instantiate()
	root.add_child(f)
	await process_frame
	f.set_process(false)
	f.station.visible = false
	f.hud.get_parent().visible = false
	var c: Vector3 = f.ship_root.global_position
	var b: Basis = f.ship_root.global_basis
	var cam: Camera3D = f.camera
	var port: Vector3 = b * (Vector3(-1, 0, 2) * ShipGrid.CELL - f.com)
	var solid: Vector3 = b * (Vector3(1, 0, 3) * ShipGrid.CELL - f.com)
	for v in [["a_porthole_side", Vector3(-12, 3, 6), port], ["b_solid_side", Vector3(12, 4, 5), solid], ["c_porthole_close", Vector3(-4.5, 0.8, 1.0), port]]:
		cam.global_position = c + v[2] + b * v[1]
		cam.look_at(c + v[2], b.y)
		await _shot(out, v[0])
	f.view.skin = false   # the builder's view: no hull
	f.view.rebuild(ship)
	for v in [["d_builder_porthole", Vector3(-5, 5, 3), port], ["e_builder_solid", Vector3(5, 5, 3), solid]]:
		cam.global_position = c + v[2] + b * v[1]
		cam.look_at(c + v[2], b.y)
		await _shot(out, v[0])
	f.view.skin = true
	f.view.rebuild(ship)
	f.get_up()
	f.hud.get_parent().visible = false
	f.help.visible = false
	f.crosshair.visible = false
	f.walk.pos = Vector3(0, 0, 2) * ShipGrid.CELL + Vector3(0.4, ShipWalk.deck_y(0), 0)
	f.walk.face(Vector3(-1, 0, 0))
	f.walk.pitch = 0.0
	f._apply_pose()
	await _shot(out, "f_inside_porthole")
	f.walk.pos = Vector3(0, 0, 3) * ShipGrid.CELL + Vector3(-0.4, ShipWalk.deck_y(0), 0)
	f.walk.face(Vector3(1, 0, 0))
	f._apply_pose()
	await _shot(out, "g_inside_solid")
	quit(0)
