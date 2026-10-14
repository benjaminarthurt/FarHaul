class_name OnFoot
extends RefCounted
## On your feet: getting up from the helm and walking the ship (ShipWalk), the airlock, stepping out
## onto a moon in the suit (SurfaceWalker), picking up finds, and coming back aboard. The walkers and
## the walking/outside flags stay on the scene.

var sc: FlightScene   ## the scene this works on


var _stow_refused := ""   ## what the hatch wouldn't take (no room): not retried until you've moved off
var boarding: Boarding   ## inside a derelict, from a space walk (scripts/flight/boarding.gd)


func _init(scene: FlightScene) -> void:
	sc = scene
	boarding = Boarding.new(scene)


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
	sc.held_from_before.clear()
	for k in sc.FLIGHT_KEYS:   # E (to sit) and W (to walk here) are flight keys too: ignore them until let go
		if Input.is_key_pressed(k):
			sc.held_from_before.append(k)
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
		KEY_PERIOD:
			sc.set_warp(sc.warp_index + 1)
		KEY_COMMA:
			sc.set_warp(sc.warp_index - 1)
		KEY_SLASH:
			sc.set_warp(0)


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
	if sc.walk.near_airlock() and space_walk_blocker() == "":
		go_space_walk()
		return "space walk"
	return ""


# --- Space walks (SpaceWalk) -------------------------------------------------------------------------

## Why the airlock won't let you out on a tether right now, or "".
func space_walk_blocker() -> String:
	if sc._on_surface() or sc._jumping() or sc.eva != null or sc.walk.airlock == Vector3.INF:
		return "not here"
	if sc.phase == "spool" or sc.phase == "warp":
		return "not mid-jump"
	return ""


## Out of the airlock on the tether. Nobody's at the helm: the ship carries on doing whatever it was,
## and if that's burning, braking or spinning, the tether will feel it. Time runs at x1 while someone's
## outside.
func go_space_walk() -> bool:
	if space_walk_blocker() != "":
		return false
	var owned: Array = Session.gear_owned() if Session.slot >= 0 else []
	sc.eva = SpaceWalk.make(sc.ship_data, sc.walk.airlock, -sc.walk.airlock_face, SurfaceWork.o2_capacity(owned))
	sc.eva.sc = sc
	sc.eva.com = sc.com
	sc.eva.last_ship_vel = sc.model.vel
	sc.set_warp(0)
	_build_eva_ui()
	sc.walking = false
	sc.view.set_interior(false)
	sc.help.text = sc.EVA_HELP
	sc.crosshair.visible = true
	sc.bar.visible = false
	var line := MeshInstance3D.new()   # the tether: a thin yellow line from the hatch to the suit
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.015
	cyl.bottom_radius = 0.015
	cyl.height = 1.0
	cyl.radial_segments = 6
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.95, 0.75, 0.15)
	m.emission_enabled = true
	m.emission = Color(0.5, 0.35, 0.05)
	cyl.material = m
	line.mesh = cyl
	sc.view.add_child(line)
	sc.eva.tether_line = line
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	var cut := sc.crew_c != null and sc.crew_c.before_space_walk()   # a pilot aboard cuts the engines first
	var busy := sc.model.throttle > 0.01 or sc.model.braking or sc.model.course_hold or sc.model.ang.length() > 0.02
	var helm := "The ship's still under way and nobody's driving: mind the tether." if busy else "The ship's coasting; nobody's driving."
	if sc.crew_c != null and sc.crew_c.has("pilot"):
		helm = ("%s cut the engines before you opened the hatch. " % sc.crew_c._name("pilot") if cut else "") + "%s has the helm and won't burn with you outside." % sc.crew_c._name("pilot")
	_eva_say("Outside, clipped on. %s Wrench (1) for loose plating, torch (2) for holes." % helm)
	sc._apply_pose()
	return true


## Back in through the hatch (or reeled in), standing in the airlock.
func end_space_walk(why := "") -> void:
	if sc.eva == null:
		return
	if boarding.active:
		boarding.leave()
	if sc.eva.tether_line != null:
		sc.eva.tether_line.queue_free()
	_free_eva_ui()
	if sc.eva.carrying > 0 and not bool(Session.flight_extra.get("adrift", false)):
		_eva_stow()   # reeled in with it: it comes too
	var fixed := sc.eva.repairs
	sc.eva = null
	sc.walking = true
	sc.walk.stand_in_airlock()
	sc.view.set_interior(true)
	sc.help.text = sc.WALK_HELP
	sc.bar.visible = true
	if why != "":
		sc.say(why, 5.0)
	elif fixed > 0:
		sc.say("Back aboard. %d spot%s fixed; hull at %d%%." % [fixed, "" if fixed == 1 else "s", roundi(sc.model.hull() * 100.0)], 4.0)
	sc._apply_pose()


func _eva_say(text: String) -> void:
	if sc.eva != null:
		sc.eva.message = text
		sc.eva.message_t = 4.0


const PART := 1000   ## space-walk targets at or above this are working parts (PART + module index); below, hull marks
const SALVAGE := 100000   ## and at or above this, salvage panels on a derelict (SALVAGE + index into _salvage)

var _salvage: Array = []   ## the salvage points in reach this step (Traffic.salvage_points), indexed by target - SALVAGE


## Salvage panels on derelicts near the suit, {SALVAGE + k: where, in the ship view's frame}.
func _eva_salvage() -> Dictionary:
	var out := {}
	_salvage.clear()
	if sc.traffic_c == null or sc.eva == null:
		return out
	var to_view := sc.view.global_transform.affine_inverse()
	var suit_world := sc.view.global_transform * sc.eva.pos
	for p in sc.traffic_c.salvage_points():
		if (p.world as Vector3).distance_to(suit_world) > 60.0:
			continue
		out[SALVAGE + _salvage.size()] = to_view * (p.world as Vector3)
		_salvage.append(p)
	return out


## A derelict's hull near the suit is solid too: spheres per compartment, in the ship view's frame.
func _eva_wreck_hulls() -> void:
	var e := sc.eva
	if sc.traffic_c == null:
		e.spheres = []
		return
	var to_view := sc.view.global_transform.affine_inverse()
	var out := []
	for sp in sc.traffic_c.wreck_spheres(sc.view.global_transform * e.pos):
		out.append({"centre": to_view * (sp.centre as Vector3), "radius": float(sp.radius)})
	e.spheres = out


## The torch is through: a panel cut free and in your hands, a hatch cut open, or a hold item grabbed.
func _eva_cut(i: int) -> void:
	var p: Dictionary = _salvage[i - SALVAGE]
	sc.traffic_c.take(p.point)
	if sc.sounds != null:
		sc.sounds.play("done")
	match String(p.kind):
		"door":
			_mark_taken(String(p.id))
			Session.save_profile()
			_eva_say("Their airlock door's open. Inside it's dark, and it's been dark a while. Hold E to go in.")
		"enter":
			var why := boarding.enter(p.derelict)
			if why != "":
				_eva_say(why)
		"hatch":
			_mark_taken(String(p.id))
			Session.save_profile()
			var n := 0
			for d in sc.traffic_c.derelicts:
				for q in d.points:
					if q.has("hatch") and q.hatch == p.point and not bool(q.taken):
						n += 1
			_eva_say("Hatch cut open. %s out of the hold. One armful at a time, back to your hatch." % ("Nothing drifts" if n == 0 else ("One thing drifts" if n == 1 else "%d things drift" % n)))
		"item":
			sc.eva.carry = (p.item as Dictionary).duplicate()
			sc.eva.carrying = 1
			sc.eva.carrying_id = String(p.id)
			_room.clear()
			_eva_say("Got %s. Back to the hatch with it." % Salvage.describe(p.item))
		_:
			sc.eva.carry = {}
			sc.eva.carrying = int(p.parts)
			sc.eva.carrying_id = String(p.id)
			_eva_say("Panel cut free: %d salvage parts. Haul it back to the hatch; the hold won't come to you." % int(p.parts))


func _mark_taken(id: String) -> void:
	var taken: Array = (Session.profile.get("salvage_taken", []) as Array).duplicate()
	taken.append(id)
	Session.profile["salvage_taken"] = taken.slice(maxi(0, taken.size() - 300))


## Back at the hatch with salvage: panels into the locker, hold items into the hold or the lockers.
func _eva_stow() -> void:
	var e := sc.eva
	if e == null or e.carrying <= 0:
		return
	if not e.carry.is_empty():
		_mark_taken(e.carrying_id)
		var r := Salvage.stow(e.carry)
		if bool(r.ok):
			sc.model.cargo_t += float(r.tonnes)   # she's heavier now
		elif String(e.carry.get("kind", "")) in ["body", "survivor"]:   # not someone you let drift
			var taken2: Array = Session.profile.get("salvage_taken", [])
			taken2.erase(e.carrying_id)
			_stow_refused = e.carrying_id
			_eva_say(String(r.message) + " They stay with you until there's room.")
			return
		else:
			var taken: Array = Session.profile.get("salvage_taken", [])
			taken.erase(e.carrying_id)
			Session.save_profile()
			r.message = String(r.message) + " You let it go by the hatch."
		_eva_say(String(r.message))
		_room.clear()
		e.carry = {}
		e.carrying = 0
		e.carrying_id = ""
		return
	var key: String = SurfaceFinds.KINDS.get("salvage", "salvage")
	Session.profile[key] = int(Session.profile.get(key, 0)) + e.carrying
	_mark_taken(e.carrying_id)
	_eva_say("Stowed %d salvage parts. %d in the locker: any dock's exchange will buy them." % [e.carrying, int(Session.profile[key])])
	e.carrying = 0
	e.carrying_id = ""


## Worn or failed working parts a space walk can do something about: {PART + module index: where}.
func _eva_parts() -> Dictionary:
	var out := {}
	if sc.ship_data == null:
		return out
	var floor_w := float(Wear.cfg().get("eva_floor", 0.5))
	for p in Wear.parts(sc.ship_data, sc.wear):
		if float(p.wear) > floor_w + 0.005 and int(p.i) < sc.view.get_child_count():
			out[PART + int(p.i)] = _part_pos(int(p.i))
	return out


## Where a part is, in the ship view's frame (the low-profile ones sit against the hull).
func _part_pos(i: int) -> Vector3:
	var node := sc.view.get_child(i) as Node3D
	var body := node.get_node_or_null("Body") as Node3D
	return node.position + (node.basis * body.position if body != null else Vector3.ZERO)


func _part(i: int) -> Dictionary:
	for p in Wear.parts(sc.ship_data, sc.wear):
		if int(p.i) == i - PART:
			return p
	return {}


## Everything there is to work on: hull marks, working parts and salvage panels on a derelict nearby.
func _eva_targets() -> Dictionary:
	var out := _eva_marks()
	out.merge(_eva_parts())
	out.merge(_eva_salvage())
	return out


var _room := {}   ## hold item id -> why it won't fit ("" if it will), so the save isn't read every frame

## Why salvage target `i` (a panel, a hatch or a hold item) can't be worked right now, or "".
func _salvage_blocked(i: int, in_hand: String) -> String:
	if sc.eva != null and sc.eva.carrying > 0:
		return "Your hands are full. Haul this lot back to the hatch first."
	var p: Dictionary = _salvage[i - SALVAGE] if i - SALVAGE < _salvage.size() else {}
	match String(p.get("kind", "panel")):
		"door":
			if in_hand != "torch":
				return "Their airlock door's sealed shut with nobody to open it. The torch (2) will ask nicely."
		"enter":
			return ""
		"item":
			var id := String(p.id)
			if not _room.has(id):
				_room[id] = Salvage.room_for(p.item)
			return String(_room[id])
		"hatch":
			if in_hand != "torch":
				return "The hatch is welded shut, or near enough. That's a job for the torch (2)."
		_:
			if in_hand != "torch":
				return "Cutting a panel free wants the torch (2). A wrench would only knock politely."
	return ""


## Why part target `i` can't be worked on right now, or "".
func _part_blocked(i: int, in_hand: String) -> String:
	var p := _part(i)
	if p.is_empty():
		return "Nothing to do there."
	if in_hand != "wrench":
		return "Machinery wants the wrench (1). The torch would only make it modern art."
	if float(p.wear) >= 1.0 and Session.spares_kits() <= 0:
		return "%s has failed: it needs a spares kit, and you have none. The repair desk sells them." % String(p.name)
	return ""


## The marks showing on the hull, {index: where}, in the ship view's frame.
func _eva_marks() -> Dictionary:
	var out := {}
	var dmg: ShipDamage = sc.view._damage
	if dmg == null:
		return out
	for i in dmg.visible_marks():
		out[i] = dmg.sites[i].pos
	return out


func _eva_step(delta: float) -> void:
	if boarding.active:
		boarding.step(delta)
		if sc.eva != null:
			_update_eva_ui()
		return
	var e := sc.eva
	var mv := Vector3.ZERO
	if Input.is_key_pressed(KEY_W): mv.z += 1.0
	if Input.is_key_pressed(KEY_S): mv.z -= 1.0
	if Input.is_key_pressed(KEY_D): mv.x += 1.0
	if Input.is_key_pressed(KEY_A): mv.x -= 1.0
	if Input.is_key_pressed(KEY_SPACE): mv.y += 1.0
	if Input.is_key_pressed(KEY_CTRL): mv.y -= 1.0
	var yaw := 0.0
	var pitch := 0.0
	if Input.is_key_pressed(KEY_LEFT): yaw += 1.0
	if Input.is_key_pressed(KEY_RIGHT): yaw -= 1.0
	if Input.is_key_pressed(KEY_UP): pitch += 1.0
	if Input.is_key_pressed(KEY_DOWN): pitch -= 1.0
	e.look(yaw * sc.KEY_TURN * delta, pitch * sc.KEY_TURN * delta)
	var dt := minf(delta, 0.05)
	var a_ship := Vector3.ZERO   # the ship's acceleration since last frame, in its own axes
	if e.last_ship_vel != Vector3.INF and dt > 0.0:
		a_ship = sc.model.basis.inverse() * ((sc.model.vel - e.last_ship_vel) / dt)
	e.last_ship_vel = sc.model.vel
	var was_snapped := e.snapped
	e.step(dt, mv, Input.is_key_pressed(KEY_SHIFT), a_ship, sc.model.ang)
	e.message_t = maxf(0.0, e.message_t - dt)
	if e.snapped and not was_snapped:
		tether_snapped()
	_eva_wreck_hulls()
	eva_work(dt, Input.is_key_pressed(KEY_E) or Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT))
	if not e.at_hatch():
		_stow_refused = ""
	if e.carrying > 0 and e.at_hatch() and e.carrying_id != _stow_refused:
		_eva_stow()
	_eva_tether()
	_eva_tools(dt)
	_update_eva_ui()
	if e.snapped and (e.distance() > float(e.cfg.get("adrift_lost_m", 150.0)) or e.o2 <= 0.0):
		adrift_rescue()
	elif e.o2 <= 0.0:
		end_space_walk("OUT OF AIR. The winch reeled you in through the hatch, gasping. Next time, watch the gauge.")


## The tether's gone: no winch, no limit. The suit's jets still work, if the ship holds still long enough.
func tether_snapped() -> void:
	if sc.eva.tether_line != null:
		sc.eva.tether_line.queue_free()
		sc.eva.tether_line = null
	if sc.alarm != null:
		sc.alarm.play()
	_eva_say("TETHER SNAPPED. You're adrift. Jet back to the hatch before the ship leaves without you.")


## Lost in the dark (too far, or out of air with no tether to reel in): a tug fishes you out and tows
## the ship in, for a fee. The flight ends.
func adrift_rescue() -> void:
	Session.flight_extra["adrift"] = true
	end_space_walk("")
	sc.sit_down()
	sc._return_to_dock()


## Hold E (or the mouse button) on a mark with the right tool to fix it. Returns what happened, for
## tests: "", "working", "done" or a refusal. `tool` overrides what's in hand.
func eva_work(dt: float, holding: bool, tool := "") -> String:
	var e := sc.eva
	if e == null:
		return ""
	if tool != "":
		e.tool = tool
	var i := e.mark_in_reach(_eva_targets())
	if not holding or i < 0:
		e.work_t = 0.0
		e.work_on = -1
		return ""
	var why := _salvage_blocked(i, e.tool) if i >= SALVAGE else (_part_blocked(i, e.tool) if i >= PART else SpaceWalk.blocked(i, sc.model.hull(), Session.patch_kits(), e.tool))
	if why != "":
		e.work_t = 0.0
		_eva_say(why)
		return why
	if e.work_on != i:
		e.work_on = i
		e.work_t = 0.0
	e.work_t += dt
	if e.work_t < _work_s(i):
		return "working"
	if i >= SALVAGE:
		_eva_cut(i)
	elif i >= PART:
		_eva_service(i)
	else:
		_eva_repair(i)
	e.work_t = 0.0
	e.work_on = -1
	return "done"


func _work_s(i: int) -> float:
	if i >= SALVAGE:
		var kind := String(_salvage[i - SALVAGE].kind) if i - SALVAGE < _salvage.size() else "panel"
		if kind == "hatch":
			return float(Salvage.cfg().get("cut_s", 14.0))
		if kind == "door":
			return float(Boarding.cfg().get("door_cut_s", 10.0))
		if kind == "enter":
			return 0.3
		if kind == "item":
			return float(Salvage.cfg().get("grab_s", 1.5))
		return float((Traffic.config().get("derelicts", {}) as Dictionary).get("cut_s", 7.0))
	if i >= PART:
		var p := _part(i)
		return float(Wear.cfg().get("eva_replace_s", 10.0)) if not p.is_empty() and float(p.wear) >= 1.0 else float(Wear.cfg().get("eva_service_s", 6.0))
	return sc.eva.work_s(i)


## A part seen to: serviced (worn), or brought back with a spares kit (failed).
func _eva_service(i: int) -> void:
	var p := _part(i)
	if p.is_empty():
		return
	var failed := float(p.wear) >= 1.0
	if failed:
		Session.profile["spares_kits"] = maxi(0, Session.spares_kits() - 1)
	sc.wear[String(p.key)] = Wear.eva_fixed(float(p.wear))
	Wear.apply(sc.model, sc.ship_data, sc.wear)
	sc.eva.repairs += 1
	if sc.sounds != null:
		sc.sounds.play("done")
	_eva_say(("%s back from the dead: new seals and a pump from the spares kit. %d%%." if failed else "%s serviced: cleaned, tightened, persuaded. %d%%. The rest is yard work.") % [String(p.name), Wear.condition(float(sc.wear[String(p.key)]))])


## A mark fixed: hull back, a kit used if it was a hole, a welded plate where the mark was.
func _eva_repair(i: int) -> void:
	var kit := ShipDamage.needs_kit(i)
	if kit:
		Session.profile["patch_kits"] = maxi(0, Session.patch_kits() - 1)
	sc.model.damage = SpaceWalk.repaired(sc.model.damage)
	var patches: Array = Session.profile.get("hull_patches", [])
	if not patches.has(i):
		patches.append(i)
	Session.profile["hull_patches"] = patches
	sc.view.set_patched(patches)
	sc.view.set_damage(sc.model.damage)
	sc._hull_warned = sc._hull_passed()
	sc.eva.repairs += 1
	if sc.sounds != null:
		sc.sounds.play("done")
	_eva_say(("Hole patched. %d kit%s left." % [Session.patch_kits(), "" if Session.patch_kits() == 1 else "s"] if kit else "Plating seated and bolted down. Free, apart from the dignity.") + "  Hull %d%%." % roundi(sc.model.hull() * 100.0))


## Lay the tether from the clip to the suit.
func _eva_tether() -> void:
	var e := sc.eva
	if e == null or e.tether_line == null:
		return
	var a := e.anchor
	var b := e.pos + e.look_basis() * Vector3(0, -0.6, 0.2)   # clipped to the suit's belt, not its eyes
	var d := b - a
	e.tether_line.position = (a + b) * 0.5
	if d.length() > 0.01:   # the cylinder runs along its Y: turn it onto the line and stretch it to length
		e.tether_line.basis = Basis(Quaternion(Vector3.UP, d.normalized())) * Basis.from_scale(Vector3(1, d.length(), 1))


func _eva_input(event: InputEvent) -> void:
	if boarding.active:
		boarding.input(event)
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		sc.eva.look(-event.relative.x * sc.MOUSE_TURN * GameSettings.mouse_sensitivity(), -event.relative.y * sc.MOUSE_TURN * GameSettings.mouse_sensitivity())
		return
	if event is InputEventMouseButton and event.pressed:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		return
	if event is InputEventMouseButton and event.pressed and (event.button_index == MOUSE_BUTTON_WHEEL_UP or event.button_index == MOUSE_BUTTON_WHEEL_DOWN):
		sc.eva.tool = "torch" if sc.eva.tool == "wrench" else "wrench"
		return
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	if event.keycode == KEY_1:
		sc.eva.tool = "wrench"
		return
	if event.keycode == KEY_2:
		sc.eva.tool = "torch"
		return
	if sc.eva.at_hatch() and (event.keycode == KEY_Q or (event.keycode == KEY_E and sc.eva.mark_in_reach(_eva_targets()) < 0)):
		end_space_walk()


## The HUD on a space walk: air, tether, kits, hull; the prompt says what's in reach.
func _eva_hud() -> void:
	if boarding.active:
		boarding.hud()
		return
	var e := sc.eva
	var low := e.o2 < e.o2_max * 0.2
	var cap := float(e.cfg.get("repair_cap_hull", 0.5))
	sc.hud.text = "\n".join(PackedStringArray([
		"SPACE WALK    %s" % ("ADRIFT  %.0f m from the hatch" % e.distance() if e.snapped else "TETHER  %.0f m left" % e.tether_left()),
		"AIR  %s%s" % [SurfaceWork.clock(e.o2), "   LOW: HEAD BACK" if low else ""],
		"IN HAND  %s    PATCH KITS  %d    SPARES  %d%s" % ["WRENCH (1)" if e.tool == "wrench" else "TORCH (2)", Session.patch_kits(), Session.spares_kits(),
				("    CARRYING  %s: TO THE HATCH" % (Salvage.describe(e.carry).to_upper() if not e.carry.is_empty() else "%d SALVAGE PARTS" % e.carrying)) if e.carrying > 0 else ""],
		"HULL  %d%%%s    JOBS  %d" % [roundi(sc.model.hull() * 100.0), "  (space-walk limit)" if sc.model.hull() >= cap - 0.001 else "", _eva_targets().size()],
	]))
	var i := e.mark_in_reach(_eva_targets())
	var hint := ""
	if e.message_t > 0.0:
		hint = e.message
	elif i >= SALVAGE:
		var why := _salvage_blocked(i, e.tool)
		var sp: Dictionary = _salvage[i - SALVAGE]
		var kind := String(sp.kind)
		if why != "":
			hint = why
		elif e.work_on == i:
			hint = "%s  %d%%" % [{"hatch": "CUTTING THE HATCH OPEN", "item": "GETTING A GRIP", "door": "CUTTING THEIR DOOR OPEN", "enter": "IN YOU GO"}.get(kind, "CUTTING THE PANEL FREE"), roundi(e.work_t / _work_s(i) * 100.0)]
		elif kind == "door":
			hint = "Their airlock door, sealed. Hold E (or click): torch it open and go aboard"
		elif kind == "enter":
			hint = "Their airlock, cut open. Hold E (or click): go in"
		elif kind == "hatch":
			hint = "The cargo hatch, sealed. Hold E (or click): torch it open and see what they were carrying"
		elif kind == "item":
			hint = "%s. Hold E (or click): take it%s" % [Salvage.sentence(Salvage.describe(sp.item)), " (it goes in the hold)" if Salvage.needs_hold(sp.item) else ""]
		else:
			hint = "A salvage panel (%d parts). Hold E (or click): torch it free" % int(sp.parts)
	elif i >= PART:
		var p := _part(i)
		var why := _part_blocked(i, e.tool)
		if why != "":
			hint = why
		elif e.work_on == i:
			hint = "%s  %d%%" % ["FITTING SPARES" if float(p.wear) >= 1.0 else "SERVICING", roundi(e.work_t / _work_s(i) * 100.0)]
		elif float(p.wear) >= 1.0:
			hint = "%s: FAILED. Hold E (or click): fit the spares kit (1 of %d)" % [String(p.name), Session.spares_kits()]
		else:
			hint = "%s: %d%%. Hold E (or click): service it with the wrench (free, up to %d%%)" % [String(p.name), Wear.condition(float(p.wear)), Wear.condition(float(Wear.cfg().get("eva_floor", 0.5)))]
	elif i >= 0:
		var why := SpaceWalk.blocked(i, sc.model.hull(), Session.patch_kits(), e.tool)
		if why != "":
			hint = why
		elif e.work_on == i:
			hint = "%s  %d%%" % ["WELDING A PATCH" if ShipDamage.needs_kit(i) else "SEATING THE PLATING", roundi(e.work_t / _work_s(i) * 100.0)]
		elif ShipDamage.needs_kit(i):
			hint = "A hole. Hold E (or click): torch a patch over it (1 kit of %d)" % Session.patch_kits()
		else:
			hint = "Loose plating. Hold E (or click): wrench it down (free)"
	elif e.at_hatch():
		hint = "E or Q: back aboard"
	elif e.snapped:
		hint = "ADRIFT. Jet back to the hatch (it's %.0f m). Past %.0f m, a tug fishes you out, at a price." % [e.distance(), float(e.cfg.get("adrift_lost_m", 150.0))]
	elif e.strain > 0.6:
		hint = "TETHER STRAIN %d%%. The ship's dragging you. Get in close to the hull or it'll snap." % roundi(e.strain * 100.0)
	elif e.tether_left() < 2.0:
		hint = "End of the tether. It's %.0f m, not a suggestion." % e.tether_m
	elif _eva_targets().is_empty():
		hint = "Nothing to fix out here. The hatch is where you left it."
	else:
		hint = "Drift to a scorch mark or a tagged part and hold E. WASD drift, Space/Ctrl up/down, Shift for more jet."
	if e.at_hatch() and i >= 0 and e.message_t <= 0.0:
		hint += "   Q: back aboard"
	sc.prompt.text = hint



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


# --- Space-walk gauges and tools ---------------------------------------------------------------------

var _eva_ui: Control
var _air_bar: ProgressBar
var _strain_bar: ProgressBar
var _rope_bar: ProgressBar
var _tools: Node3D
var _wrench: Node3D
var _torch: Node3D
var _flame: MeshInstance3D
var _torch_light: OmniLight3D
var _sparks: CPUParticles3D
var _swing := 0.0


static func _gauge_box(col: Color) -> StyleBoxFlat:
	var b := StyleBoxFlat.new()
	b.bg_color = col
	b.set_corner_radius_all(3)
	return b


func _gauge(parent: Control, label: String, col: Color) -> ProgressBar:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	parent.add_child(row)
	var l := Label.new()
	l.text = label
	l.custom_minimum_size = Vector2(74, 0)
	l.add_theme_font_size_override("font_size", 14)
	l.add_theme_color_override("font_color", Brand.OFFWHITE)
	row.add_child(l)
	var b := ProgressBar.new()
	b.custom_minimum_size = Vector2(220, 16)
	b.max_value = 1.0
	b.show_percentage = false
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	b.add_theme_stylebox_override("background", _gauge_box(Color(0.1, 0.12, 0.15, 0.85)))
	b.add_theme_stylebox_override("fill", _gauge_box(col))
	row.add_child(b)
	return b


## The gauges: air left, tether paid out, and the strain on it.
func _build_eva_ui() -> void:
	_free_eva_ui()
	_eva_ui = VBoxContainer.new()
	_eva_ui.add_theme_constant_override("separation", 6)
	_eva_ui.position = Vector2(28, 150)
	sc.hud.get_parent().add_child(_eva_ui)
	_air_bar = _gauge(_eva_ui, "AIR", Color(0.35, 0.7, 1.0))
	_rope_bar = _gauge(_eva_ui, "TETHER", Color(0.95, 0.75, 0.15))
	_strain_bar = _gauge(_eva_ui, "STRAIN", Color(0.4, 0.85, 0.45))
	_build_tools()


func _free_eva_ui() -> void:
	if _eva_ui != null and is_instance_valid(_eva_ui):
		_eva_ui.queue_free()
	_eva_ui = null
	if _tools != null and is_instance_valid(_tools):
		_tools.queue_free()
	_tools = null
	if _sparks != null and is_instance_valid(_sparks):
		_sparks.queue_free()
	_sparks = null
	for k in _part_tags:
		if is_instance_valid(_part_tags[k]):
			(_part_tags[k] as Label3D).queue_free()
	_part_tags.clear()


func _update_eva_ui() -> void:
	var e := sc.eva
	if e == null or _eva_ui == null:
		return
	_air_bar.value = e.o2 / maxf(e.o2_max, 1.0)
	var low := e.o2 < e.o2_max * 0.2
	_air_bar.add_theme_stylebox_override("fill", _gauge_box(Brand.ALARM if low else Color(0.35, 0.7, 1.0)))
	_rope_bar.value = 1.0 if e.snapped else clampf(e.distance() / e.tether_m, 0.0, 1.0)
	_rope_bar.modulate = Color(1, 1, 1, 0.35) if e.snapped else Color.WHITE
	_strain_bar.value = 1.0 if e.snapped else clampf(e.strain, 0.0, 1.0)
	var col := Color(0.4, 0.85, 0.45) if e.strain < 0.4 else (Brand.AMBER if e.strain < 0.75 else Brand.ALARM)
	_strain_bar.add_theme_stylebox_override("fill", _gauge_box(Brand.ALARM if e.snapped else col))


## A wrench and a torch held in front of the camera, low and to the right.
func _build_tools() -> void:
	_tools = Node3D.new()
	_tools.name = "EvaTools"
	sc.camera.add_child(_tools)
	_tools.position = Vector3(0.3, -0.26, -0.6)
	var steel := Interiors.flat(Color(0.62, 0.64, 0.68), 0.35, 0.85)
	var grip := Interiors.flat(Color(0.75, 0.25, 0.12), 0.8, 0.1)
	var glove := Interiors.flat(Color(0.55, 0.56, 0.58), 0.9, 0.0)   # the suit's glove, holding it
	# The wrench: a red grip, a steel shank and an open jaw, held pointing up and away.
	_wrench = Node3D.new()
	_tools.add_child(_wrench)
	_box(_wrench, Vector3(0, -0.03, 0.03), Vector3(0.06, 0.05, 0.07), glove)
	_box(_wrench, Vector3(0, 0.06, 0), Vector3(0.035, 0.14, 0.035), grip)
	_box(_wrench, Vector3(0, 0.2, 0), Vector3(0.03, 0.18, 0.018), steel)
	_box(_wrench, Vector3(-0.03, 0.31, 0), Vector3(0.02, 0.06, 0.02), steel)
	_box(_wrench, Vector3(0.03, 0.31, 0), Vector3(0.02, 0.06, 0.02), steel)
	_box(_wrench, Vector3(0, 0.285, 0), Vector3(0.08, 0.02, 0.02), steel)
	_wrench.rotation_degrees = Vector3(-35, 0, -15)
	# The torch: a tank-grey body, a bent copper neck, a nozzle, and a flame when it's lit.
	_torch = Node3D.new()
	_tools.add_child(_torch)
	_box(_torch, Vector3(0, -0.03, 0.03), Vector3(0.06, 0.05, 0.07), glove)
	var body := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.035
	cyl.bottom_radius = 0.04
	cyl.height = 0.2
	cyl.material = Interiors.flat(Color(0.3, 0.32, 0.36), 0.6, 0.4)
	body.mesh = cyl
	body.position = Vector3(0, 0.08, 0)
	_torch.add_child(body)
	_box(_torch, Vector3(0, 0.2, -0.03), Vector3(0.02, 0.06, 0.02), Interiors.flat(Color(0.72, 0.42, 0.2), 0.4, 0.7))
	_box(_torch, Vector3(0, 0.23, -0.08), Vector3(0.018, 0.018, 0.08), steel)
	_flame = MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 0.03
	cone.height = 0.22
	var fm := StandardMaterial3D.new()
	fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fm.albedo_color = Color(0.6, 0.85, 1.0)
	fm.emission_enabled = true
	fm.emission = Color(0.6, 0.85, 1.0)
	fm.emission_energy_multiplier = 4.0
	cone.material = fm
	_flame.mesh = cone
	_flame.position = Vector3(0, 0.23, -0.23)
	_flame.rotation_degrees.x = -90.0
	_flame.visible = false
	_torch.add_child(_flame)
	var glow := MeshInstance3D.new()   # the hot spot at the nozzle: the flame points away from you, so this is what you see
	var q := QuadMesh.new()
	q.size = Vector2(0.14, 0.14)
	var gm := StandardMaterial3D.new()
	gm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	gm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	gm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	gm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	gm.albedo_texture = ShipDamage._puff_texture()
	gm.albedo_color = Color(0.7, 0.9, 1.0)
	q.material = gm
	glow.mesh = q
	glow.position = Vector3(0, -0.1, 0.0)
	_flame.add_child(glow)
	_torch_light = OmniLight3D.new()
	_torch_light.light_color = Color(0.6, 0.8, 1.0)
	_torch_light.omni_range = 4.0
	_torch_light.light_energy = 0.0
	_torch_light.position = Vector3(0, 0.23, -0.25)
	_torch.add_child(_torch_light)
	_torch.rotation_degrees = Vector3(-30, 0, -10)
	# Sparks where the work is: out on the hull, placed on the mark being worked.
	_sparks = CPUParticles3D.new()
	_sparks.amount = 60
	_sparks.lifetime = 0.35
	_sparks.emitting = false
	_sparks.spread = 80.0
	_sparks.gravity = Vector3.ZERO
	_sparks.initial_velocity_min = 1.0
	_sparks.initial_velocity_max = 3.0
	var g := Gradient.new()
	g.set_color(0, Color(1.0, 0.95, 0.7, 1.0))
	g.set_color(1, Color(1.0, 0.4, 0.1, 0.0))
	_sparks.color_ramp = g
	var sm := BoxMesh.new()
	sm.size = Vector3(0.008, 0.008, 0.05)
	var smat := StandardMaterial3D.new()
	smat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	smat.vertex_color_use_as_albedo = true
	smat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sm.material = smat
	_sparks.mesh = sm
	_sparks.particle_flag_align_y = true
	sc.view.add_child(_sparks)


func _box(parent: Node3D, at: Vector3, size: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	b.material = mat
	mi.mesh = b
	mi.position = at
	parent.add_child(mi)


## The tool in hand, and it moving when it's working: the wrench rocks, the torch lights and throws sparks.
func _eva_tools(dt: float) -> void:
	var e := sc.eva
	if e == null or _tools == null:
		return
	_wrench.visible = e.tool == "wrench"
	_torch.visible = e.tool == "torch"
	var working := e.work_on >= 0 and e.work_t > 0.0
	_swing += dt * (9.0 if working else 0.0)
	_wrench.rotation_degrees = Vector3(-35 + (sin(_swing) * 25.0 if working and e.tool == "wrench" else 0.0), 0, -15)
	_tools.position = Vector3(0.3, -0.26, -0.6) + (Vector3.ZERO if not working else Vector3(-0.05, 0.03, -0.05))
	var grabbing := working and e.work_on >= SALVAGE and e.work_on - SALVAGE < _salvage.size() and String(_salvage[e.work_on - SALVAGE].kind) == "item"
	var lit := working and e.tool == "torch" and not grabbing
	_flame.visible = lit
	_flame.scale = Vector3.ONE * (0.8 + 0.4 * randf()) if lit else Vector3.ONE
	_torch_light.light_energy = (2.5 + randf() * 1.5) if lit else 0.0
	_sparks.emitting = working and not grabbing
	if working and e.work_on >= SALVAGE:   # cutting a derelict's panel
		var sv := _eva_salvage()
		if sv.has(e.work_on):
			_sparks.position = sv[e.work_on]
			_sparks.direction = (e.pos - (sv[e.work_on] as Vector3)).normalized()
	elif working and e.work_on >= PART:
		_sparks.position = _part_pos(e.work_on - PART)
		_sparks.direction = Vector3.UP
	elif working:
		var site: Dictionary = sc.view._damage.sites[e.work_on]
		_sparks.position = site.pos
		_sparks.direction = site.normal
	if working:
		_sparks.color_ramp.set_color(0, Color(0.7, 0.9, 1.0, 1.0) if lit else Color(1.0, 0.95, 0.7, 1.0))
	_update_part_tags()


var _part_tags := {}   ## module index -> Label3D naming a worn part, while outside


## Name tags on the parts that want attention, so they can be found from outside.
func _update_part_tags() -> void:
	var want := _eva_parts()
	for k in _part_tags.keys():
		if not want.has(PART + int(k)) and is_instance_valid(_part_tags[k]):
			(_part_tags[k] as Label3D).visible = false
	for t in want:
		var i := int(t) - PART
		var tag: Label3D = _part_tags.get(i)
		if tag == null or not is_instance_valid(tag):
			tag = Label3D.new()
			tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			tag.no_depth_test = true
			tag.font_size = 40
			tag.pixel_size = 0.004
			tag.outline_size = 8
			sc.view.add_child(tag)
			_part_tags[i] = tag
		var p := _part(int(t))
		tag.visible = true
		tag.position = (want[t] as Vector3) + Vector3(0, 1.2, 0)
		tag.text = "%s  %s" % [String(p.name).to_upper(), "FAILED" if float(p.wear) >= 1.0 else "%d%%" % Wear.condition(float(p.wear))]
		tag.modulate = Brand.ALARM if float(p.wear) >= 1.0 else Brand.AMBER
