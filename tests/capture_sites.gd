extends SceneTree
## Renders the outpost, the ice mine and the glass crater from the air and on foot (xvfb-run).
## xvfb-run -a godot --path . -s tests/capture_sites.gd -- /tmp/sites_frames
func _initialize() -> void:
	SaveSlots.dir = "user://test_saves_capture_sites"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SaveSlots.dir))
	process_frame.connect(_run, CONNECT_ONE_SHOT)
func _run() -> void:
	var out := "/tmp/sites_frames"
	for a in OS.get_cmdline_user_args():
		out = a
	DirAccess.make_dir_recursive_absolute(out)
	Session.begin_new(2, "Pilot", "human", "normal", "roosevelt_independent_yards")
	var data := SaveSlots.read(Session.slot)
	var ship := ShipData.new(ModuleLibrary.new())
	ShipPresets.build(ship, ShipPresets.STARTER_LANDER)
	data["modules"] = (JSON.parse_string(ship.to_json()) as Dictionary)["modules"]
	SaveSlots.write(Session.slot, data)
	var sys := Session.system_id()
	Session.profile["port_id"] = sys + LocalSpace.SEP + "pad"
	Session.save_profile()
	Session.flight_job = {}
	var f: Node = load(Session.FLIGHT_SCENE).instantiate()
	root.add_child(f)
	await process_frame
	await process_frame
	var n := 1
	for st in SurfaceSites.sites(sys):
		var p := Vector3(float(st.x), 0, float(st.z))
		var cam: Camera3D = f.camera
		var g: float = f.model.terrain.height(p.x, p.z)
		var from := p + Vector3(-420, g + 260, 330) if String(st.id) == "crater" else p + Vector3(-180, g + 90, 140)
		cam.global_position = from
		cam.look_at(Vector3(p.x, g, p.z), Vector3.UP)
		await _shot(out, "%02d_%s_air" % [n, st.id], f, cam)
		n += 1
	var cr := SurfaceSites.site(sys, "crater")
	var cam2: Camera3D = f.camera
	var cx := float(cr.x)
	var cz := float(cr.z)
	cam2.global_position = Vector3(cx - 60, f.model.terrain.height(cx - 60, cz) + 1.7, cz + 20)
	cam2.look_at(Vector3(cx + 200, f.model.terrain.height(cx + 200, cz) + 10, cz), Vector3.UP)
	await _shot(out, "04_crater_floor", f, cam2)
	var o := SurfaceSites.site(sys, "outpost")
	cam2.global_position = Vector3(float(o.x) - 20, f.model.terrain.height(float(o.x) - 20, float(o.z)) + 1.7, float(o.z) + 25)
	cam2.look_at(Vector3(float(o.x) + 25, f.model.terrain.height(float(o.x) + 25, float(o.z)) + 2, float(o.z) - 8), Vector3.UP)
	await _shot(out, "05_outpost_ground", f, cam2)
	quit(0)
func _shot(out: String, name: String, f: Node, cam: Camera3D) -> void:
	f.set_process(false)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png("%s/%s.png" % [out, name])
	print("shot ", name)
