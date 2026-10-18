class_name Rivals
extends RefCounted
## Other salvage crews (comms.json "rivals"). Some derelicts draw a rival: a salvage tug already there
## with its beacon on the wreck when you arrive, or one that turns up while you're working it. They park
## alongside and strip it at their own pace: panels, the cargo hatch, then the hold.
##
## Claim beacons settle who was first. Fire one at a wreck from anywhere aboard (the radio, within 2 km)
## and it's yours; they're bought at the repair desk (Session.claim_beacons). Hail a rival to:
## - **split it**: they take every other piece that's left and leave the rest to you;
## - **warn them off**: likely to work when your beacon was first, unlikely when theirs was, and standing
##   helps either way. Refused, they carry on.
## Or race them. Take pieces from a wreck they claimed first (or from their half of a split) and they file
## a complaint with the port: standing, at the end of the flight.

var comms: Comms
var sc: FlightScene
var rivals: Array = []      ## {d, ship, name, species, state: coming|working|gone, claim, deal, share, t, cut, voice, home, spark}
var _seen := {}             ## derelicts already rolled for a rival (by id_base)
var jumped := 0             ## pieces taken from someone else's claim this flight
var rep := 0
var notes: Array = []


func _init(c: Comms) -> void:
	comms = c
	sc = c.sc


static func cfg() -> Dictionary:
	return Comms.cfg().get("rivals", {})


static func beacons() -> int:
	return int(Session.profile.get("claim_beacons", int(cfg().get("beacons_start", 2)))) if Session.slot >= 0 else 0


static func claims() -> Dictionary:
	return Session.profile.get("claims", {}) if Session.slot >= 0 else {}


static func _claim(id: String, who: String) -> void:
	var c: Dictionary = claims().duplicate()
	c[id] = who
	if c.size() > 60:   # wrecks change every day: forget old claims
		for k in c.keys().slice(0, c.size() - 60):
			c.erase(k)
	Session.profile["claims"] = c


## Who holds the claim on derelict `id`: "you", "them" or "".
static func claim_of(id: String) -> String:
	return String(claims().get(id, "")).get_slice(":", 0)


func _rival_for(d: Dictionary) -> Dictionary:
	for r in rivals:
		if r.d == d:
			return r
	return {}


func _near(d: Dictionary, m: float) -> bool:
	return is_instance_valid(d.ship) and (d.ship as NpcShip).global_position.distance_to(sc.model.pos) <= m


# --- Every frame --------------------------------------------------------------------------------------

func step(dt: float) -> void:
	var t := sc.traffic_c
	if t == null or t.root == null:
		return
	var k := cfg()
	for d in t.derelicts:
		var id := String(d.get("id_base", ""))
		if id == "" or _seen.has(id) or not _near(d, float(k.get("near_m", 3000))):
			continue
		_seen[id] = true
		_roll(d)
	for r in rivals:
		_work(r, dt)


## Does this wreck draw a rival, and are they there already? Fixed by the wreck, so it's the same all day.
func _roll(d: Dictionary) -> void:
	var k := cfg()
	var id := String(d.id_base)
	var g := RandomNumberGenerator.new()
	g.seed = hash("rival|" + id)
	if g.randf() > float(k.get("deep_chance" if bool(d.deep) else "chance", 0.35)):
		return
	var names: Array = k.get("names", ["Mud Lark"])
	var nm := String(names[g.randi() % names.size()])
	var sp := Crew._species(g)
	var there := g.randf() < float(k.get("there_first", 0.4)) and claim_of(id) != "you"
	var after: Array = k.get("arrive_after_s", [180, 480])
	var r := {"d": d, "name": nm, "species": sp, "state": "coming", "claim": claim_of(id), "deal": "", "share": [], "t": g.randf_range(float(after[0]), float(after[1])),
			"cut": 0.0, "voice": RadioVoice.voice(sp, hash("rival|" + nm)), "warned": false, "ship": null, "spark": null,
			"jumper": g.randf() < float(Hazards.config().jumpers.get("chance", 0.3)), "reported": false, "took": 0}   # a claim-jumper ignores beacons
	if claim_of(id) == "them":
		there = true   # they beaconed it earlier today
	rivals.append(r)
	if there:
		_arrive(r, true)


func _spot(r: Dictionary) -> Vector3:
	var w: NpcShip = r.d.ship
	var away := (w.global_position - sc.model.pos)
	var side := away.cross(Vector3.UP).normalized() if away.cross(Vector3.UP).length() > 0.1 else Vector3.RIGHT
	return w.position + side * (w.radius + 35.0) + Vector3(0, 12, 0)


func _arrive(r: Dictionary, already: bool) -> void:
	var s := NpcShip.make([ShipPresets.NPC_POD, ShipPresets.STARTER, ShipPresets.NPC_SURVEYOR][absi(hash(String(r.name))) % 3], "SALVAGE  %s" % String(r.name).to_upper())
	s.label.modulate = Color(1.0, 0.75, 0.3)
	sc.traffic_c.root.add_child(s)
	r.ship = s
	var spot := _spot(r)
	var id := String(r.d.id_base)
	if already:
		s.position = spot
		r.state = "working"
		if claim_of(id) == "":
			_claim(id, "them:" + String(r.name))
		r.claim = claim_of(id)
		comms.incoming(_who(r), comms._line("rival_there", {"them": String(r.name), "wreck": _wreck(r)}), r.voice, _dist(r))
	else:
		s.position = spot + (spot - (r.d.ship as NpcShip).position).normalized() * 3000.0
		r.state = "arriving"
		if claim_of(id) == "you":
			r.claim = "you"
			comms.incoming(_who(r), comms._line("rival_jump" if jumping(r) else "rival_yours", {"them": String(r.name), "wreck": _wreck(r)}), r.voice, _dist(r))
		else:
			_claim(id, "them:" + String(r.name))
			r.claim = "them"
			comms.incoming(_who(r), comms._line("rival_claim", {"them": String(r.name), "wreck": _wreck(r)}), r.voice, _dist(r))
	_beacon_light(r.d, "them" if r.claim == "them" else "you")


func _work(r: Dictionary, dt: float) -> void:
	var k := cfg()
	if String(r.state) == "gone" or not is_instance_valid(r.d.ship) or (r.ship != null and not is_instance_valid(r.ship)):
		r.state = "gone"   # the scene moved on (a new station, a jump): they're out of sight
		return
	if r.ship != null:
		(r.ship as NpcShip).show_tag(sc.model.pos, 8000.0)
	match String(r.state):
		"coming":
			if not _near(r.d, float(k.get("stay_m", 8000))):
				return
			r.t = float(r.t) - dt
			if float(r.t) <= 0.0:
				_arrive(r, false)
		"arriving":
			var s: NpcShip = r.ship
			var to: Vector3 = _spot(r) - s.position
			var step_m := float(k.get("speed_m_s", 60)) * dt
			if to.length() <= step_m:
				s.position = _spot(r)
				s.set_flames(false)
				r.state = "working"
			else:
				s.position += to.normalized() * step_m
				s.basis = Basis.looking_at(to.normalized(), Vector3.UP)
				s.set_flames(true)
		"working":
			r.cut = float(r.cut) + dt
			var every: Array = k.get("cut_every_s", [35, 60])
			var need := lerpf(float(every[0]), float(every[1]), 0.5)
			if jumping(r):
				need /= float(Hazards.config().jumpers.get("cut_speed", 1.6))   # in a hurry: it isn't theirs
			var p := _next(r)
			if p.is_empty():
				if String(r.deal) == "":   # stripped: what's left is anyone's
					r.deal = "done"
					var c: Dictionary = claims().duplicate()
					c.erase(String(r.d.id_base))
					Session.profile["claims"] = c
				_leave(r, "rival_done")
				return
			_spark(r, p)
			if float(r.cut) >= need:
				r.cut = 0.0
				sc.traffic_c.take(p, false)
				_mark(String(p.id))
				r.took = int(r.get("took", 0)) + 1
		"leaving":
			var s: NpcShip = r.ship
			if not is_instance_valid(s):
				r.state = "gone"
				return
			var away: Vector3 = (s.position - (r.d.ship as NpcShip).position).normalized()
			s.position += away * float(k.get("speed_m_s", 60)) * dt
			s.set_flames(true)
			if s.position.distance_to((r.d.ship as NpcShip).position) > 4000.0:
				s.queue_free()
				r.state = "gone"


## What they'll cut next: their share after a split, otherwise panels, then the hatch, then the hold.
func _next(r: Dictionary) -> Dictionary:
	var pts: Array = r.d.points
	var share: Array = r.share
	var order := ["panel", "hatch", "item"]
	for kind in order:
		for p in pts:
			if bool(p.taken) or String(p.kind) != kind:
				continue
			if not share.is_empty() and not share.has(String(p.id)) and kind != "hatch":   # the hatch opens for both
				continue
			if kind == "item":
				if not bool((p.hatch as Dictionary).get("taken", false)) or String((p.item as Dictionary).get("kind", "")) in ["survivor", "body"]:
					continue
			return p
	return {}


func _mark(id: String) -> void:
	var taken: Array = (Session.profile.get("salvage_taken", []) as Array).duplicate()
	taken.append(id)
	Session.profile["salvage_taken"] = taken.slice(maxi(0, taken.size() - 300))


func _leave(r: Dictionary, line: String) -> void:
	if String(r.state) in ["leaving", "gone"]:
		return
	r.state = "leaving"
	if r.spark != null and is_instance_valid(r.spark):
		(r.spark as Node3D).queue_free()
	if line != "":
		comms._say(_who(r), comms._line(line, {"them": String(r.name), "wreck": _wreck(r)}), r.voice, _dist(r))


## A torch at work on the wreck: a flickering orange light where they're cutting.
func _spark(r: Dictionary, p: Dictionary) -> void:
	var w: NpcShip = r.d.ship
	if r.spark == null or not is_instance_valid(r.spark):
		var n := Node3D.new()
		var l := OmniLight3D.new()
		l.light_color = Color(1.0, 0.6, 0.25)
		l.omni_range = 20.0
		n.add_child(l)
		var mi := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.45
		sm.height = 0.9
		sm.material = Interiors.glow(Color(1.0, 0.8, 0.4), 5.0)
		mi.mesh = sm
		n.add_child(mi)
		w.body.add_child(n)
		r.spark = n
	var n2: Node3D = r.spark
	n2.position = (p.pos as Vector3) + (p.normal as Vector3) * 0.4
	(n2.get_child(0) as OmniLight3D).light_energy = 1.5 + 2.5 * absf(sin(float(r.cut) * 23.0) * cos(float(r.cut) * 9.0))


## The beacon on a wreck: a blinking light on a short mast, green for yours, amber for theirs.
func _beacon_light(d: Dictionary, whose: String) -> void:
	var w: NpcShip = d.ship
	var old := w.get_node_or_null("ClaimBeacon")
	if old != null:
		old.free()
	var n := Node3D.new()
	n.name = "ClaimBeacon"
	n.position = Vector3(0, w.radius * 0.6 + 2.0, 0)
	var col := Color(0.3, 1.0, 0.45) if whose == "you" else Color(1.0, 0.6, 0.15)
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.6
	sm.height = 1.2
	sm.material = Interiors.glow(col, 4.0)
	mi.mesh = sm
	n.add_child(mi)
	var l := OmniLight3D.new()
	l.light_color = col
	l.light_energy = 3.0
	l.omni_range = 25.0
	n.add_child(l)
	w.add_child(n)
	w.title = w.title.get_slice("  ·  ", 0) + ("  ·  YOUR CLAIM" if whose == "you" else "  ·  CLAIMED")


func _who(r: Dictionary) -> String:
	return "Salvage tug %s" % String(r.name)


func _wreck(r: Dictionary) -> String:
	return String(r.d.name)


func _dist(r: Dictionary) -> float:
	return clampf((r.d.ship as NpcShip).global_position.distance_to(sc.model.pos) / 25000.0, 0.0, 1.0)


# --- You took something ---------------------------------------------------------------------------

## The player took point `p` off derelict `d` (Traffic.on_take): claim jumping if it was theirs.
func took(d: Dictionary, p: Dictionary) -> void:
	var r := _rival_for(d)
	var theirs := false
	if not r.is_empty():
		match String(r.deal):
			"split":
				theirs = (r.share as Array).has(String(p.id))
			"warned", "done":
				theirs = false
			_:
				theirs = String(r.claim) == "them"
	else:
		theirs = claim_of(String(d.get("id_base", ""))) == "them"
	if theirs:
		jumped += 1


# --- The radio --------------------------------------------------------------------------------------

func contacts() -> Array:
	var out := []
	var t := sc.traffic_c
	if t == null or t.root == null or not t.root.visible:
		return out
	var k := cfg()
	for d in t.derelicts:
		if not is_instance_valid(d.ship):
			continue
		var dist: float = (d.ship as NpcShip).global_position.distance_to(sc.model.pos)
		var id := String(d.get("id_base", ""))
		if dist <= float(k.get("beacon_range_m", 2000)) * 2.0 and claim_of(id) == "":
			var n := beacons()
			var ok := dist <= float(k.get("beacon_range_m", 2000)) and n > 0
			out.append({"id": "wreck:" + id, "kind": "wreck", "name": (d.ship as NpcShip).title, "dist_m": dist,
					"options": [comms._opt("beacon", "Fire a claim beacon at it (%d aboard)" % n, ok, "No beacons aboard: the repair desk sells them" if n <= 0 else "Within %.0f km" % (float(k.get("beacon_range_m", 2000)) / 1000.0))]})
	for r in rivals:
		if not String(r.state) in ["working", "arriving"] or r.ship == null or not is_instance_valid(r.ship):
			continue
		var dist: float = (r.ship as NpcShip).global_position.distance_to(sc.model.pos)
		var opts := []
		var dealt := String(r.deal) != ""
		opts.append(comms._opt("split", "Split it: half each", not dealt, "Already settled" if dealt else ""))
		opts.append(comms._opt("warn", "This one's ours. Clear off.", not dealt and not bool(r.warned), "They've heard you" if bool(r.warned) else "Already settled"))
		if jumping(r):
			opts.append(comms._opt("report", "Report them to the port authority", not bool(r.reported), "Reported"))
		out.append({"id": "rival:" + String(r.d.id_base), "kind": "rival", "name": _who(r).to_upper(), "dist_m": dist, "options": opts})
	return out


func act(c: Dictionary, option: String) -> Dictionary:
	var id := String(c.id).get_slice(":", 1)
	if String(c.kind) == "wreck":
		return _fire(id)
	var r: Dictionary = {}
	for x in rivals:
		if String(x.d.id_base) == id:
			r = x
	if r.is_empty():
		return {"ok": false, "message": "They've gone."}
	var k := cfg()
	if jumping(r) and option in ["split", "warn"]:   # a claim-jumper doesn't deal
		if option == "warn":
			r.warned = true
			comms._you_say(comms._line("you_warn", {"them": String(r.name)}))
		else:
			comms._you_say(comms._line("you_split", {"them": String(r.name)}))
		comms._say(_who(r), comms._line("rival_jump_no", {"them": String(r.name)}), r.voice, _dist(r))
		return {"ok": true, "message": "They're claim-jumpers. They don't deal. You could report them."}
	match option:
		"report":
			return _report(r)
		"split":
			comms._you_say(comms._line("you_split", {"them": String(r.name)}))
			var left := (r.d.points as Array).filter(func(p): return not bool(p.taken) and String(p.kind) in ["panel", "item"] and not (String(p.kind) == "item" and String((p.item as Dictionary).get("kind", "")) in ["survivor", "body"]))
			var share := []
			for i in left.size():
				if i % 2 == 1:
					share.append(String(left[i].id))
			r.share = share
			r.deal = "split"
			comms._say(_who(r), comms._line("rival_split", {"them": String(r.name)}), r.voice, _dist(r))
			if share.is_empty():
				_leave(r, "")
			return {"ok": true, "message": "Split: they take %d of the %d pieces left." % [share.size(), left.size()]}
		"warn":
			r.warned = true
			comms._you_say(comms._line("you_warn", {"them": String(r.name)}))
			var chance := float(k.get("warn_first" if String(r.claim) == "you" else "warn_second", 0.15))
			chance += clampf(float(Session.profile.get("rep", 0)) * float(k.get("warn_rep_per_point", 0.005)), 0.0, 0.25)
			var g := RandomNumberGenerator.new()
			g.seed = hash("warn|" + id)
			if g.randf() < chance:
				r.deal = "warned"
				_claim(id, "you")
				_beacon_light(r.d, "you")
				_leave(r, "rival_warned_ok")
				return {"ok": true, "message": "They're leaving. The wreck's yours."}
			comms._say(_who(r), comms._line("rival_warned_no" if String(r.claim) == "them" else "rival_warned_no_yours", {"them": String(r.name)}), r.voice, _dist(r))
			return {"ok": true, "message": "They're staying."}
	return {"ok": false, "message": "Nothing to say."}


## A crew cutting a wreck under your beacon, not caring whose it is.
static func jumping(r: Dictionary) -> bool:
	return bool(r.get("jumper", false)) and String(r.get("claim", "")) == "you"


## Report claim-jumpers: sometimes a patrol is near and they run; either way the port authority pays a
## bounty on what they took, and your standing goes up, once the flight's over.
func _report(r: Dictionary) -> Dictionary:
	r.reported = true
	comms._you_say(comms._line("you_report", {"them": String(r.name)}))
	var g := RandomNumberGenerator.new()
	g.seed = hash("report|" + String(r.d.id_base))
	if g.randf() < float(Hazards.config().jumpers.get("patrol_chance", 0.45)):
		r.deal = "reported"
		_leave(r, "rival_report_go")
		return {"ok": true, "message": "A patrol's near. They're running. The bounty's yours once you're in port."}
	comms._say(_who(r), comms._line("rival_report_stay", {"them": String(r.name)}), r.voice, _dist(r))
	return {"ok": true, "message": "Reported. No patrol close enough to stop them, but the port authority pays a bounty on whatever they take."}


func _fire(id: String) -> Dictionary:
	var d: Dictionary = {}
	for x in sc.traffic_c.derelicts:
		if String(x.get("id_base", "")) == id:
			d = x
	if d.is_empty():
		return {"ok": false, "message": "No wreck there."}
	Session.profile["claim_beacons"] = beacons() - 1
	_claim(id, "you")
	_beacon_light(d, "you")
	Session.save_profile()
	comms._you_say(comms._line("you_beacon", {"wreck": String(d.name)}))
	var r := _rival_for(d)
	if not r.is_empty() and String(r.state) == "coming":
		r.claim = "you"
	return {"ok": true, "message": "Claim beacon on the %s. It's yours, for anyone who checks." % String(d.name).trim_prefix("the ")}


func settlement() -> Dictionary:
	var out := {"rep": rep, "notes": notes.duplicate(), "bounty_cr": 0}
	var jc: Dictionary = Hazards.config().jumpers
	for r in rivals:
		if not bool(r.get("reported", false)):
			continue
		var b := roundi(float(int(r.get("took", 0))) * float(SurfaceFinds.value("salvage")) * float(jc.get("bounty_share", 0.5)))
		out.rep = int(out.rep) + int(jc.get("report_rep", 2))
		out.bounty_cr = int(out.bounty_cr) + b
		out.notes.append("The port authority fined the %s for claim-jumping your wreck%s" % [String(r.name),
				": a bounty of %s cr on the %d piece%s they took." % [ShipStats.commas(b), int(r.took), "" if int(r.took) == 1 else "s"] if b > 0 else ". They took nothing, so there's no bounty, just the satisfaction."])
	if jumped > 0:
		out.rep = int(out.rep) + int(cfg().get("jump_rep", -2))
		var who := ""
		for r in rivals:
			if String(r.claim) == "them" or String(r.deal) == "split":
				who = String(r.name)
		out.notes.append("The %s filed a claim-jumping complaint with the port authority: %d piece%s off a wreck that was theirs." % [who if who != "" else "salvage crew", jumped, "" if jumped == 1 else "s"])
	return out
