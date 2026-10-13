class_name CrewWork
extends RefCounted
## The crew at work during a flight (Crew): the engineer servicing worn parts, the deck tech out on
## the hull fixing marks while the engines are quiet, and the pilot minding the helm when the captain
## isn't at it. Everything they do follows the captain's own space-walk rules: no part better than the
## wrench's floor, no hull past 50%, holes only with a patch kit, failed parts only with a spares kit.

var sc: FlightScene
var roster: Array = []
var wear_mult := 1.0
var engineer_t := 0.0      ## game seconds towards the engineer's next job
var deck_t := 0.0          ## and the deck tech's (only counts while the engines are quiet)
var pilot_braked := false  ## the pilot has taken the brake point this run
var pilot_waiting := false ## the pilot is holding off braking because someone's outside
var jobs := 0              ## things the crew did this flight (for tests and the log)
var figures: Array[Figure] = []   ## the crew aboard, at their posts, seen when you walk the ship
var passengers := false    ## a passenger run: the steward has someone to look after

## Where each job stands its watch, by module id, in order of preference.
const POSTS := {
	"engineer": ["engineering", "tee"],
	"deck_tech": ["airlock", "tee"],
	"pilot": ["cockpit"],
	"loadmaster": ["cargo_hold", "tee"],
	"steward": ["room_2x2", "bunk", "tee"],
}
const JACKETS := {
	"engineer": Color(0.85, 0.55, 0.15), "deck_tech": Color(0.85, 0.75, 0.2), "pilot": Color(0.2, 0.35, 0.65),
	"loadmaster": Color(0.35, 0.5, 0.3), "steward": Color(0.6, 0.25, 0.3),
}


func _init(scene: FlightScene) -> void:
	sc = scene
	roster = (Session.crew() as Array).duplicate(true) if Session.slot >= 0 else []
	wear_mult = Crew.wear_mult(roster)
	passengers = Session.slot >= 0 and String(Session.active_contract().get("person_kind", "")) == "passenger"


func has(role_id: String) -> bool:
	return Crew.skill(roster, role_id) > 0


func _name(role_id: String) -> String:
	return Crew.short(Crew.who(roster, role_id))


## One line for the HUD: who's aboard, by job.
func hud_line() -> String:
	if roster.is_empty():
		return ""
	var bits := PackedStringArray()
	for p in roster:
		bits.append("%s %s" % [Crew.short(p), Crew.role_name(String(p.role))])
	return "CREW  " + ", ".join(bits).to_upper()


## What each of them is up to, for the ship remote: [{name, role, role_name, skill, doing}].
func status() -> Array:
	var out := []
	for p in roster:
		var r := String(p.get("role", ""))
		var best: bool = Crew.who(roster, r) == p   # a second of the same job helps out, but the best one leads
		out.append({"name": String(p.get("name", "")), "role": r, "role_name": Crew.role_name(r), "skill": int(p.get("skill", 1)),
				"doing": _doing(r) if best else "Helping %s" % Crew.short(Crew.who(roster, r))})
	return out


func _doing(r: String) -> String:
	match r:
		"engineer":
			var kits := [Session.spares_kits()]
			var probe := sc.wear.duplicate()
			if sc.ship_data == null or Crew.service_one(sc.ship_data, probe, kits).is_empty():
				return "Nothing to service: every part as good as a wrench gets it"
			return "Next part serviced in %s" % SurfaceWork.clock(maxf(0.0, Crew.every_s(roster, "engineer", "service_every_s") - engineer_t))
		"deck_tech":
			var cap := float(SpaceWalk.tuning().get("repair_cap_hull", 0.5))
			var shown: Array = sc.view._damage.visible_marks() if sc.view != null and sc.view._damage != null else []
			if shown.is_empty():
				return "Nothing to fix: the hull's sound"
			if sc.model.hull() >= cap - 0.001:
				return "Hull at %d%%: the rest is yard work" % roundi(cap * 100.0)
			if Crew.pick_mark(shown, sc.model.hull(), Session.patch_kits()) < 0:
				return "Only holes left, and no patch kits"
			if not _quiet():
				return "Waiting for the engines to go quiet before going out"
			return "Out on the hull in %s" % SurfaceWork.clock(maxf(0.0, Crew.every_s(roster, "deck_tech", "fix_every_s") - deck_t))
		"pilot":
			if pilot_waiting and sc.eva != null:
				return "Holding off braking: you're on the tether"
			if sc.model.braking and pilot_braked:
				return "Has the helm: braking for the target"
			if sc.walking or sc.eva != null:
				return "Has the helm while you're up"
			return "Standing by in the cockpit"
		"loadmaster":
			return "Load lashed down" if sc.model.cargo_t > 0.01 else "Nothing aboard to lash"
		"steward":
			return "Looking after the passengers" if passengers else "No passengers: polishing the galley"
	return ""


func _quiet() -> bool:
	var m := sc.model
	return m.throttle < 0.02 and not m.braking and m.retro <= 0.0 and m.strafe == Vector2.ZERO and m.ang.length() < 0.05 \
			and not sc._jumping() and not sc.leaving


## Put the crew at their posts aboard: Figures in the ship view's rooms.
func _place_figures() -> void:
	if not figures.is_empty() or sc.walk == null or sc.view == null or sc.ship_data == null:
		return
	var used := {}
	for p in roster:
		var r := String(p.get("role", ""))
		var spot := Vector3.INF
		var centre := Vector3.ZERO
		for want in POSTS.get(r, ["tee"]) + [""]:
			for c in sc.walk.cells:
				var mi: int = sc.walk.cells[c]
				if used.has(c) or (want != "" and String(sc.ship_data.modules[mi].id) != want):
					continue
				var base := Vector3(Vector3i(c)) * ShipGrid.CELL
				base.y = ShipWalk.deck_y((c as Vector3i).y)
				for x in [1.0, -1.0, 0.5, -0.5, 0.0]:   # off to the side of the room if there's space, out of the aisle
					for z in [0.5, -0.5, 1.0, -1.0, 0.0]:
						var at: Vector3 = base + Vector3(x, 0, z)
						if spot == Vector3.INF and sc.walk.free_at(at) and _clear_of_doors(at):
							spot = at
				if spot != Vector3.INF:
					used[c] = true
					centre = base
					break
			if spot != Vector3.INF:
				break
		if spot == Vector3.INF:
			continue
		var f := Figure.make(JACKETS.get(r, Color(0.5, 0.5, 0.5)), hash(String(p.get("id", ""))), false, String(p.get("species", "human")))
		f.position = spot
		var face := centre - spot
		if face.length() > 0.01:
			f.rotation.y = atan2(-face.x, -face.z)   # turned in towards the middle of the room
		f.visible = false
		f.set_meta("who", "%s, %s" % [String(p.get("name", "")), Crew.role_name(r).to_lower()])
		f.set_meta("i", roster.find(p))
		sc.view.add_child(f)
		figures.append(f)


## Who's within arm's reach of you aboard, and what they're like: "KAVA TEM, ENGINEER: ...", or "".
func near_line() -> String:
	if not sc.walking or sc.walk == null:
		return ""
	for i in figures.size():
		var f := figures[i]
		if Vector2(f.position.x - sc.walk.pos.x, f.position.z - sc.walk.pos.z).length() < 1.6 and absf(f.position.y - sc.walk.pos.y) < 1.0:
			var p: Dictionary = roster[int(f.get_meta("i", i))]
			var line := String(p.get("line", ""))
			return String(f.get_meta("who", "")).to_upper() + ((": " + line) if line != "" else "")
	return ""


## Not standing where the captain has to: behind the helm, in the airlock's middle, under a hatch.
func _clear_of_doors(at: Vector3) -> bool:
	for p in [sc.walk.helm_stand, sc.walk.airlock]:
		if p != Vector3.INF and Vector2(at.x - p.x, at.z - p.z).length() < 1.0 and absf(at.y - p.y) < 1.0:
			return false
	var c := ShipGrid.world_to_cell(at - Vector3(0, Interiors.FLOOR, 0))
	return not sc.walk.hatches.has(c) or Vector2(at.x - float(c.x) * ShipGrid.CELL, at.z - float(c.z) * ShipGrid.CELL).length() > 0.9


## `dt` is game seconds (time compression included).
func step(dt: float) -> void:
	if roster.is_empty() or sc.leaving or sc.ship_data == null:
		return
	_place_figures()
	for f in figures:
		f.visible = sc.walking
		f.look_at_point = sc.view.to_global(sc.walk.pos + Vector3(0, 1.6, 0)) if sc.walking and f.position.distance_to(sc.walk.pos) < 4.0 else Vector3.INF
	if dt <= 0.0:
		return
	if has("engineer"):
		engineer_t += dt
		if engineer_t >= Crew.every_s(roster, "engineer", "service_every_s"):
			engineer_t = 0.0
			_engineer_job()
	if has("deck_tech") and _quiet() and not (sc._on_surface() and not sc.model.landed):
		deck_t += dt
		if deck_t >= Crew.every_s(roster, "deck_tech", "fix_every_s"):
			deck_t = 0.0
			_deck_job()
	if has("pilot"):
		_pilot_step()


func _engineer_job() -> bool:
	var spares := [Session.spares_kits()]
	var r := Crew.service_one(sc.ship_data, sc.wear, spares)
	if r.is_empty():
		return false
	Session.profile["spares_kits"] = int(spares[0])
	Wear.apply(sc.model, sc.ship_data, sc.wear)
	jobs += 1
	sc.say(("%s put the %s back together with a spares kit: %d%%." if bool(r.failed) else "%s serviced the %s: %d%%. Past that it's yard work.") % [_name("engineer"), String(r.name).to_lower(), int(r.condition)], 5.0)
	return true


func _deck_job() -> bool:
	var dmg := sc.view._damage if sc.view != null else null
	if dmg == null:
		return false
	var i := Crew.pick_mark(dmg.visible_marks(), sc.model.hull(), Session.patch_kits())
	if i < 0:
		return false
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
	jobs += 1
	sc.say(("%s went out and welded a patch over a hole (%d kit%s left). Hull %d%%." if kit else "%s went out and seated some loose plating. Hull %d%%.") % (
			[_name("deck_tech"), Session.patch_kits(), "" if Session.patch_kits() == 1 else "s", roundi(sc.model.hull() * 100.0)] if kit
			else [_name("deck_tech"), roundi(sc.model.hull() * 100.0)]), 5.0)
	return true


## The captain's out of the seat: the pilot takes the brake point on a run, but not with anyone on the
## end of a tether.
func _pilot_step() -> void:
	var away := sc.walking or sc.eva != null
	if not away or sc.xfer == null or sc.phase != "cruise" or sc.model.braking or pilot_braked:
		return
	if not sc.xfer.brake_now(sc.model):
		return
	if sc.eva != null:
		if not pilot_waiting:
			pilot_waiting = true
			sc.say("%s: \"Brake point. I'm not braking with you on a tether. Come in.\"" % _name("pilot"), 6.0)
		return
	pilot_braked = true
	sc.model.braking = true
	sc.model.course_hold = false
	sc.model.brake_to = sc.xfer.target
	sc.say("%s took the helm at the brake point and is bringing her in." % _name("pilot"), 6.0)


## Someone's going outside: the pilot cuts everything that would fling them off. Returns true if it did.
func before_space_walk() -> bool:
	if not has("pilot"):
		return false
	var m := sc.model
	var busy := m.throttle > 0.01 or m.braking or m.course_hold or m.retro > 0.0
	m.throttle = 0.0
	m.braking = false
	m.course_hold = false
	m.retro = 0.0
	m.strafe = Vector2.ZERO
	return busy


## The days of a jump: the drive's wear on the engines and radiators (less with an engineer), and the
## crew's work on the way, on this flight's own hull and wear.
func after_jump(hours: float) -> void:
	if sc.ship_data == null:
		return
	var wc := Wear.cfg()
	Wear.add(sc.wear, sc.ship_data, "engine", float(wc.get("jump_engine", 0.03)) * wear_mult)
	Wear.add(sc.wear, sc.ship_data, "radiator", float(wc.get("jump_radiator", 0.02)) * wear_mult)
	var done := {"fixed": 0, "kits_used": 0, "serviced": 0, "revived": 0}
	for k in Crew.jobs_in(roster, "deck_tech", "fixes_per_trip_hour", hours):
		var kits := Session.patch_kits()
		if not _deck_job():
			break
		done.fixed = int(done.fixed) + 1
		if Session.patch_kits() < kits:
			done.kits_used = int(done.kits_used) + 1
	for k in Crew.jobs_in(roster, "engineer", "services_per_trip_hour", hours):
		var kits := Session.spares_kits()
		if not _engineer_job():
			break
		done["revived" if Session.spares_kits() < kits else "serviced"] = int(done["revived" if Session.spares_kits() < kits else "serviced"]) + 1
	Wear.apply(sc.model, sc.ship_data, sc.wear)
	var note := Crew.work_note(roster, done)
	if note != "":
		sc.say(note.strip_edges(), 6.0)
