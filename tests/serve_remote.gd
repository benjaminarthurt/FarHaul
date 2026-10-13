extends SceneTree
## Runs a flight with the ship remote on, for looking at the page from a browser (or a test driving it):
## a run from Earth's port to the Saturn ring yards, partway along. Quits after the given seconds.
## godot --headless --path . -s tests/serve_remote.gd -- [seconds] [hull left, 0..1: knocks the ship down to it]
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
	print("remote at ", ShipRemote.where())
	await create_timer(secs).timeout
	quit(0)
