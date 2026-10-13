extends SceneTree
## Runs a flight with the ship remote on, for looking at the page from a browser (or a test driving it):
## a run from Earth's port to the Saturn ring yards, partway along. Quits after the given seconds.
## godot --headless --path . -s tests/serve_remote.gd -- [seconds] [hull left, 0..1: knocks the ship down to it] [flight|eva|port]
## "eva" puts the captain out on the tether (with a crew aboard); "port" stands them in the concourse with
## a two-bunk ship and one hand hired, for the desks.
func _initialize() -> void:
	SaveSlots.dir = "user://test_saves_serve_remote_%d" % OS.get_process_id()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SaveSlots.dir))
	process_frame.connect(_run, CONNECT_ONE_SHOT)
func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var secs := 60.0 if args.is_empty() else float(args[0])
	GameSettings.set_value("remote", true)
	GameSettings.set_value("remote_code", "424242")
	Session.begin_new(2, "Mara Voss", "human", "normal", "roosevelt_independent_yards")
	Session.profile["system_id"] = "sol"
	Session.profile["port_id"] = String(Worlds.primary_port("sol").id)
	var mode := String(args[2]) if args.size() > 2 else "flight"
	var roster := []
	for r in (["engineer"] if mode == "port" else ["engineer", "deck_tech", "pilot"]):
		var c: Dictionary = Crew.candidates("serve", roster.size() * 3 + 1, 1.0)[0]
		c["role"] = r
		c["id"] = "serve-" + r
		c["skill"] = 3
		roster.append(c)
	Session.profile["crew"] = roster
	Session.profile["patch_kits"] = 3
	Session.profile["spares_kits"] = 1
	Session.profile["wear"] = {"5:engine": 0.62, "6:radiator": 0.81}
	Session.profile["hints_seen"] = ["welcome", "money", "crew"]
	Session.save_profile()
	if mode == "port":
		var data := SaveSlots.read(Session.slot)
		var cabin := ShipData.new(ModuleLibrary.new())
		ShipPresets.build(cabin, ShipPresets.STARTER_CABIN)
		data["modules"] = (JSON.parse_string(cabin.to_json()) as Dictionary)["modules"]
		data["cargo"] = CargoManifest.new(cabin).to_dict()
		data["profile"] = Session.profile
		SaveSlots.write(Session.slot, data)
		var pl: Node = load(Session.PLACE_SCENE).instantiate()
		root.add_child(pl)
		current_scene = pl
		print("remote at ", ShipRemote.where())
		await create_timer(secs).timeout
		quit(0)
		return
	var dest := LocalSpace.node("sol__saturn")
	Session.flight_job = {"kind": "run", "contract_id": "remote", "dv_kms": 8.0, "hours": 96, "destination": String(dest.name), "key": "remote",
			"dest_kind": "saturn", "dest_id": "sol__saturn", "origin_kind": "port", "origin_id": String(Session.profile.port_id), "system_id": "sol"}
	var f: Node = load(Session.FLIGHT_SCENE).instantiate()
	root.add_child(f)
	current_scene = f
	await process_frame
	f.phase = "cruise"
	f.model.pos = f.xfer.target * 0.42
	f.model.vel = (f.xfer.target - f.model.pos).normalized() * 2600.0
	f.model.basis = Basis(Vector3.UP, 0.2) * Basis.looking_at(f.xfer.target - f.model.pos)
	f.station.visible = false
	f.warp_index = 2
	if args.size() > 1:
		f.model.cargo_t = maxf(f.model.cargo_t, 6.0)
		f.model.hurt(f.model.hull() - float(args[1]))
	f.model.retro_kn = 20.0   # show the thrusters on the remote
	f.model.rcs_x_kn = 10.0
	f.model.rcs_y_kn = 10.0
	f._wear_apply_t = 1.0e9   # keep them: the wear step would put the ship's real (unfitted) thrusters back
	if mode == "eva":
		f.warp_index = 0
		f.model.vel = f.model.vel.normalized() * 300.0
		f.get_up()
		f.walk.stand_in_airlock()
		f.use()
		f.eva.pos = f.eva.anchor + Vector3(0, 0, 1) * 21.0
		f.eva.o2 = f.eva.o2_max * 0.62
		f.eva.strain = 0.18
	print("remote at ", ShipRemote.where())
	await create_timer(secs).timeout
	quit(0)
