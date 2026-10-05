class_name OnFoot
extends RefCounted
## On your feet: getting up from the helm and walking the ship (ShipWalk), the airlock, stepping out
## onto a moon in the suit (SurfaceWalker), picking up finds, and coming back aboard. The walkers and
## the walking/outside flags stay on the scene.

var sc: FlightScene   ## the scene this works on


func _init(scene: FlightScene) -> void:
	sc = scene


## Leave the pilot's seat. Whatever the ship was doing it keeps doing: throttle, braking autopilot, assist.
func get_up() -> bool:
	if sc.walking or sc._jumping() or sc.walk == null or not sc.walk.stand_at_helm():
		return false
	sc.walking = true
	sc.view.set_interior(true)
	sc.help.text = sc.WALK_HELP
	sc.crosshair.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	sc._apply_pose()
	return true


## Back in the seat, at the controls as they were left.
func sit_down() -> void:
	if not sc.walking:
		return
	sc.walking = false
	sc.view.set_interior(false)
	sc.help.text = sc.LAND_HELP if sc._on_surface() else sc.FLY_HELP
	sc.crosshair.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	sc._apply_pose()


## Docked, or still at the berth the flight started from: the airlock lets you off.
func _berthed() -> bool:
	if sc._on_surface():
		return sc.model.landed
	if sc.model.can_dock():
		return true
	return sc.phase != "approach" and sc.phase != "cruise" and sc.model.pos.length() < 400.0 and sc.model.speed() < 1.0


func _walk_step(delta: float) -> void:
	var dir := Vector2.ZERO
	if Input.is_key_pressed(KEY_W): dir.y += 1.0
	if Input.is_key_pressed(KEY_S): dir.y -= 1.0
	if Input.is_key_pressed(KEY_D): dir.x += 1.0
	if Input.is_key_pressed(KEY_A): dir.x -= 1.0
	var yaw := 0.0
	var pitch := 0.0
	if Input.is_key_pressed(KEY_LEFT): yaw += 1.0
	if Input.is_key_pressed(KEY_RIGHT): yaw -= 1.0
	if Input.is_key_pressed(KEY_UP): pitch += 1.0
	if Input.is_key_pressed(KEY_DOWN): pitch -= 1.0
	sc.walk.look(yaw * sc.KEY_TURN * delta, pitch * sc.KEY_TURN * delta)
	sc.walk.step(minf(delta, 0.05), dir, Input.is_key_pressed(KEY_SHIFT))


func _walk_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		sc.walk.look(-event.relative.x * sc.MOUSE_TURN * GameSettings.mouse_sensitivity(), -event.relative.y * sc.MOUSE_TURN * GameSettings.mouse_sensitivity())
		return
	if event is InputEventMouseButton and event.pressed:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		return
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	match event.keycode:
		KEY_E:
			sc.use()
		KEY_ESCAPE:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		KEY_PERIOD:
			if sc.xfer != null:
				sc.warp_index = mini(sc.warp_index + 1, sc.WARPS.size() - 1)
		KEY_COMMA:
			sc.warp_index = maxi(sc.warp_index - 1, 0)


## E: sit at the helm, climb a ladder, or leave by the airlock when the ship is at a berth.
func use() -> String:
	if sc.walk.near_helm():
		sc.sit_down()
		return "helm"
	if sc.walk.climb() != 0:
		return "ladder"
	if sc.walk.near_airlock() and sc._on_surface() and sc.model.landed:
		sc.go_outside()
		return "outside"
	if sc.walk.near_airlock() and sc._berthed():
		if sc.phase == "approach":
			sc._arrived = true
		sc.sit_down()
		sc._return_to_dock()
		return "airlock"
	return ""


## The find within reach of the suit, or {}.
func find_in_reach() -> Dictionary:
	if sc.suit == null or Session.slot < 0:
		return {}
	var reach := float(SurfaceFinds.config().get("reach_m", 2.5))
	for f in Session.finds_here():
		if bool(f.taken):
			continue
		var d := sc.suit.distance_to(Vector3(float(f.x), 0, float(f.z)))
		if d <= (9.0 if String(f.kind) == "salvage" else reach):
			return f
	return {}


## E on foot next to a find: bag the sample or strip the wreck.
func take_find() -> String:
	var f := sc.find_in_reach()
	if f.is_empty():
		return ""
	var r := Session.take_find(String(f.id))
	if bool(r.ok) and sc.sounds != null:
		sc.sounds.play("done")
	if bool(r.ok) and sc.find_nodes.has(String(f.id)):
		(sc.find_nodes[String(f.id)] as Node3D).visible = false
	sc._find_message = String(r.message)
	sc._find_message_t = sc.model.elapsed_s
	return String(r.message)


## Out through the airlock onto the surface (the ship must be down).
func go_outside() -> bool:
	if sc.phase != "descent" or not sc.model.landed or sc.walk.airlock == Vector3.INF:
		return false
	var cells: Array[Vector3i] = []
	for m in sc.ship_data.modules:
		for c in sc.ship_data.world_cells(m.id, m.cell, m.rot):
			cells.append(c)
	var origin := sc.model.pos + sc.model.basis * sc.view.position
	var out_dir := -sc.walk.airlock_face
	var hatch_local := Vector3(sc.walk.airlock.x, 0, sc.walk.airlock.z) + out_dir * 2.6
	sc.suit_hatch = origin + sc.model.basis * hatch_local
	sc.suit = SurfaceWalker.make(sc.model.terrain, sc.model.gravity, cells, origin, sc.model.basis)
	sc.suit.rocks = sc.model.rocks
	sc.suit.max_slope_deg = float(SurfaceSites.config().get("walk_slope_deg", 30.0))
	sc.suit.place(sc.suit_hatch)
	sc.suit.face(sc.model.basis * out_dir)
	if sc.ops == null:
		sc.ops = SurfaceOps.new()
		sc.moon.add_child(sc.ops)
		sc.ops.setup(sc, sc._site_here())
	sc.outside = true
	sc.ops.begin_outing()
	sc.walking = false
	sc.view.set_interior(false)
	sc.help.text = sc.SUIT_HELP
	sc.crosshair.visible = true
	sc._apply_pose()
	return true


## Back in through the airlock.
func come_aboard() -> bool:
	if not sc.outside or sc.suit.distance_to(sc.suit_hatch) > 2.5:
		return false
	if sc.ops != null:
		sc.ops.end_outing()
	sc.bar.visible = true
	sc.outside = false
	sc.walking = true
	sc.walk.stand_in_airlock()
	sc.view.set_interior(true)
	sc.help.text = sc.WALK_HELP
	sc._apply_pose()
	return true


func _suit_step(delta: float) -> void:
	var dir := Vector2.ZERO
	if Input.is_key_pressed(KEY_W): dir.y += 1.0
	if Input.is_key_pressed(KEY_S): dir.y -= 1.0
	if Input.is_key_pressed(KEY_D): dir.x += 1.0
	if Input.is_key_pressed(KEY_A): dir.x -= 1.0
	var yaw := 0.0
	var pitch := 0.0
	if Input.is_key_pressed(KEY_LEFT): yaw += 1.0
	if Input.is_key_pressed(KEY_RIGHT): yaw -= 1.0
	if Input.is_key_pressed(KEY_UP): pitch += 1.0
	if Input.is_key_pressed(KEY_DOWN): pitch -= 1.0
	sc.suit.look(yaw * sc.KEY_TURN * delta, pitch * sc.KEY_TURN * delta)
	sc.suit.step(minf(delta, 0.05), dir, Input.is_key_pressed(KEY_SHIFT), Input.is_key_pressed(KEY_SPACE), Input.is_key_pressed(KEY_SPACE))
	if sc.ops != null:
		sc.ops.step(minf(delta, 0.05), Input.is_key_pressed(KEY_SHIFT) and dir != Vector2.ZERO)


func _suit_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		sc.suit.look(-event.relative.x * sc.MOUSE_TURN * GameSettings.mouse_sensitivity(), -event.relative.y * sc.MOUSE_TURN * GameSettings.mouse_sensitivity())
		return
	if event is InputEventMouseButton and event.pressed:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		return
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	match event.keycode:
		KEY_E:
			if sc.ops != null and sc.ops.use() != "":
				return
			if sc.take_find() == "":
				sc.come_aboard()
		KEY_Q:
			sc.come_aboard()
		KEY_ESCAPE:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


## Which surface site the ship is at: "pad" or "camp" (by the nearer pad).
func _site_here() -> String:
	var c := SurfaceFinds.camp_xz()
	return "camp" if Vector2(sc.model.pos.x - c.x, sc.model.pos.z - c.y).length() < Vector2(sc.model.pos.x, sc.model.pos.z).length() else "pad"


## From the airlock desk: out on the surface in the suit straight away.
func _suit_up() -> void:
	if sc._on_surface() and sc.model.landed:
		sc.go_outside()


## Out of air: the crew bring you in through the hatch.
func blackout() -> void:
	if not sc.outside:
		return
	sc.suit.place(sc.suit_hatch)
	sc.come_aboard()


## Coming aboard from the berth: standing in the airlock instead of behind the seats.
func walk_from_airlock() -> void:
	if sc.walking and sc.walk.stand_in_airlock():
		sc._apply_pose()
