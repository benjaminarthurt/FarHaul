class_name Comms
extends RefCounted
## The radio, in flight (data/runtime/comms.json). Who's in range (contacts()), what you can say to each
## (their options) and what happens when you do (act()):
##
## - **traffic control** at the station you're near: clearance to dock, a berth, sometimes a hold while
##   another ship comes out of the collar first. Docking without clearance is a fine and a lecture.
## - **pad control** at the moon base, and the **foreman** at a mining camp: clearance to land.
## - **ships**: haulers parked by the port sell fuel (they come alongside) and anyone will pass on news
##   from the economy; when you're dry, a ship in range can tow you in, as can the port tug.
## - **distress calls**: now and then on a run, a living ship out of fuel or with a dead drive calls for
##   help. Brake alongside and sell them fuel, or take the crew aboard as survivors (PortAuthority).
##   Ignore it and word gets round.
##
## Everything said plays through the radio with the words as a subtitle (`current`), and goes in the log:
## the recorded line if there is one (VoiceBank, through the Radio bus with hiss and squelch), otherwise
## RadioVoice's babble. What it costs or earns is settled when the flight ends (Session.flight_extra "comms").

const PATH := "res://data/runtime/comms.json"
const SQUELCH_S := 0.14   ## the squelch opening before a recorded line

static var _cfg: Dictionary = {}

var sc: FlightScene
var player: AudioStreamPlayer
var voice_player: AudioStreamPlayer   ## a recorded line, on the Radio bus
var hiss_player: AudioStreamPlayer    ## the carrier under it
var queue: Array = []        ## lines waiting to be said: {who, text, voice, dist, sound, refs}
var current := {}            ## the line being said: {who, text, t, dur}
var log: Array = []          ## what's been said, oldest first: {who, text}
var _task := -1              ## a voice being made on a worker thread
var _made: AudioStreamWAV
var _making := {}
var layer_players: Array[AudioStreamPlayer] = []   ## a species' extra voices (VoiceBank.layer_buses)
var _heard := {}             ## callers heard this flight (by voice seed): the translator's quicker the second time
var _pending: Array = []     ## lines made by _line since the last thing said: {text, key, index, args}
var rng := RandomNumberGenerator.new()

var clear_for := ""          ## the station or site that cleared you to dock or land ("" none)
var berth := 0
var hold := {}               ## {mover, other, t, site}: told to wait while a ship comes out
var fuel_deal := {}          ## a hauler bringing fuel: {ship, home, t, price, stage, done, name, voice}
var distress := {}           ## a ship calling for help on this run: {ship, name, species, crew, problem, key, helped, voice}
var news_given := {}         ## contacts that have told you all they know
var rivals: Rivals           ## other salvage crews and claim beacons (scripts/comms/rivals.gd)
var _speed_t := -100.0
var _elapsed := 0.0
var settle := {"fine_cr": 0, "fine_rep": 0, "fuel_bought_cr": 0, "fuel_bought_t": 0.0, "fuel_sold_cr": 0, "fuel_sold_t": 0.0,
		"tow_delta_cr": 0, "tow_by": "", "rep": 0, "notes": []}


static func cfg() -> Dictionary:
	if _cfg.is_empty():
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		_cfg = parsed if typeof(parsed) == TYPE_DICTIONARY else {}
	return _cfg


func _init(scene: FlightScene) -> void:
	sc = scene
	rng.seed = hash("comms|%d|%s" % [Session.day(), String(Session.profile.get("port_id", ""))])
	player = AudioStreamPlayer.new()
	player.bus = GameSettings.bus("Effects")
	player.volume_db = -4.0
	sc.add_child(player)
	voice_player = AudioStreamPlayer.new()
	voice_player.bus = VoiceBank.radio_bus()
	sc.add_child(voice_player)
	hiss_player = AudioStreamPlayer.new()
	hiss_player.bus = GameSettings.bus("Effects")
	sc.add_child(hiss_player)
	rivals = Rivals.new(self)


# --- Who's out there --------------------------------------------------------------------------------

func _you() -> String:
	var n := String(Session.profile.get("ship_name", "")).strip_edges()
	return n if n != "" else "Freighter"


func _station_name() -> String:
	if sc.phase == "approach":
		return String(sc.job.get("destination", "the station"))
	return String(Session.port().get("name", "the station"))


func _station_id() -> String:
	return String(sc.job.get("dest_id", "")) if sc.phase == "approach" else String(Session.profile.get("port_id", ""))


func _station_up() -> bool:
	return sc.station != null and sc.station.visible and not sc._on_surface() and not sc._jumping() and sc.phase != "cruise"


func _control(name: String) -> String:
	return name.trim_suffix(" Station") + " Traffic"


## The surface site the ship is coming down to or sitting on: {id, kind: pad|camp, name}, or {}.
func _site() -> Dictionary:
	if not sc._on_surface():
		return {}
	var id := String(sc.job.get("dest_id", "")) if sc.phase == "descent" and not sc.job.is_empty() else String(Session.profile.get("port_id", ""))
	if not LocalSpace.is_surface(id):
		id = Session.system_id() + LocalSpace.SEP + String(sc._target_kind)
	var kind := String(LocalSpace.node(id).get("kind", sc._target_kind))
	return {"id": id, "kind": kind, "name": String(LocalSpace.node(id).get("name", "the base"))}


func _species_here() -> String:
	var sp: Array = Worlds.system(Session.system_id()).get("home_species_ids", ["human"])
	return String(sp[0]) if not sp.is_empty() else "human"


## Every NPC ship you could call: [{ship, kind: hauler|mover|pod|orbiter|passer}].
func _ships() -> Array:
	var t := sc.traffic_c
	var out := []
	if t == null or t.root == null or not t.root.visible:
		return out
	for s in t.parked:
		out.append({"ship": s, "kind": "hauler"})
	for m in t.movers:
		if (m.ship as NpcShip).visible:
			out.append({"ship": m.ship, "kind": "mover"})
	for o in t.orbiters:
		out.append({"ship": o.ship, "kind": "orbiter"})
	if t.passer != null:
		out.append({"ship": t.passer, "kind": "passer"})
	return out


func _stranded() -> bool:
	return not sc.model.has_fuel() or sc.model.disabled()


## Who's in range now, nearest first, with what you can say to each:
## [{id, kind, name, dist_m, options: [{id, text, enabled, why}]}].
func contacts() -> Array:
	var out := []
	var r: Dictionary = cfg().get("range_m", {})
	var pos: Vector3 = sc.model.pos
	if _station_up() and pos.length() <= float(r.get("control", 60000)):
		out.append({"id": "control", "kind": "control", "name": _control(_station_name()), "dist_m": pos.length(), "options": _control_options()})
	var site := _site()
	if not site.is_empty():
		out.append({"id": "pad", "kind": String(site.kind), "name": ("%s pad control" % String(site.name)) if String(site.kind) == "pad" else "%s foreman" % String(site.name),
				"dist_m": pos.distance_to(sc.model.pad), "options": _pad_options(site)})
	if not distress.is_empty() and not bool(distress.get("gone", false)) and is_instance_valid(distress.get("ship", null)):
		var d: float = (distress.ship as NpcShip).global_position.distance_to(pos)
		if d <= float(r.get("distress", 400000)):
			out.append({"id": "distress", "kind": "distress", "name": "DISTRESS  %s" % String(distress.name), "dist_m": d, "options": _distress_options(d)})
	var ships := []
	for e in _ships():
		var s: NpcShip = e.ship
		var d := s.global_position.distance_to(pos)
		if d <= float(r.get("ship", 25000)):
			ships.append({"id": "ship:" + s.title, "kind": String(e.kind), "name": s.title, "dist_m": d, "options": _ship_options(e, d), "ship": s})
	ships.append_array(rivals.contacts())
	ships.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.dist_m) < float(b.dist_m))
	out.append_array(ships)
	if _stranded():
		out.append({"id": "tug", "kind": "tug", "name": "Port tug, by relay", "dist_m": -1.0,
				"options": [{"id": "tow", "text": "Call the tug  %s cr" % ShipStats.commas(_tug_fee()), "enabled": true, "why": ""}]})
	return out


func _opt(id: String, text: String, enabled := true, why := "") -> Dictionary:
	return {"id": id, "text": text, "enabled": enabled, "why": why}


func _control_options() -> Array:
	var c: Dictionary = cfg().get("clearance", {})
	var sid := _station_id()
	if clear_for == sid:
		return [_opt("clearance", "Confirm clearance: berth %d" % berth)]
	if not hold.is_empty():
		return [_opt("clearance", "Holding for the %s" % String(hold.other), false, "Wait for them to clear the collar")]
	return [_opt("clearance", "Request clearance to dock")]


func _pad_options(site: Dictionary) -> Array:
	if clear_for == String(site.id):
		return [_opt("clearance", ("Confirm: pad %d" % berth) if String(site.kind) == "pad" else "Confirm: the flat bit")]
	return [_opt("clearance", "Request clearance to land")]


func _ship_options(e: Dictionary, d: float) -> Array:
	var s: NpcShip = e.ship
	var out := []
	var kind := String(e.kind)
	var id := "ship:" + s.title
	out.append(_opt("news", "Ask for news", not news_given.has(id), "They've told you all they know"))
	if kind == "hauler":
		var busy := not fuel_deal.is_empty() and not bool(fuel_deal.get("done", false))
		var room := float(sc.stats.get("fuel", sc.model.fuel_t)) - sc.model.fuel_t
		var deal := _fuel_terms(s)
		out.append(_opt("fuel", ("Buy %.0f t of fuel at %s cr/t" % [minf(float(deal.t), room), ShipStats.commas(int(deal.price))]) if room >= 0.5 else "Buy fuel",
				not busy and room >= 0.5, "Tanks are full" if room < 0.5 else "A transfer's already on"))
	elif kind == "passer":
		out.append(_opt("fuel", "Buy fuel", false, "They're doing %d m/s the other way" % roundi(sc.traffic_c.passer_vel.length())))
	if _stranded() and kind in ["hauler", "passer", "orbiter"]:
		out.append(_opt("tow", "Ask for a tow  %s cr" % ShipStats.commas(_tow_terms(s))))
	return out


func _distress_options(d: float) -> Array:
	var near := d <= float((cfg().get("distress", {}) as Dictionary).get("stop_m", 70)) * 4.0 and sc.model.speed() <= 5.0
	var why := "" if near else "Brake alongside first (X stops you there)"
	var out := []
	if not bool(distress.get("answered", false)):
		out.append(_opt("answer", "Answer: we're coming"))
	var wants := _rescue_terms()
	out.append(_opt("fuel", "Sell them %.0f t of fuel at %s cr/t" % [float(wants.t), ShipStats.commas(int(wants.price))],
			near and sc.model.fuel_t > float(wants.t) + 0.5 and not bool(distress.get("fuelled", false)), why if not near else ("You'd be dry yourself" if sc.model.fuel_t <= float(wants.t) + 0.5 else "They have what they need")))
	var room := _room()
	out.append(_opt("crew", "Take the %d aboard" % int(distress.crew), near and room >= int(distress.crew), why if not near else "No room for %d: %d free bed%s and the jump seat" % [int(distress.crew), maxi(room - 1, 0), "" if room - 1 == 1 else "s"]))
	if room < int(distress.crew):
		out.append(_opt("report", "Report them to the port", not bool(distress.get("reported", false)), "Already reported"))
	return out


## Beds for survivors right now: free beds of any kind, and the jump seat if nobody's in it.
func _room() -> int:
	var lay := Passengers.layout(Session.ship_stats(sc.ship_data)) if sc.ship_data != null and Session.slot >= 0 else {"free": [0, 0, 0, 0], "over": 0}
	var n := 0
	for f in lay.free:
		n += maxi(0, int(f))
	return n + (1 if int(lay.over) == 0 else 0)


# --- Prices -------------------------------------------------------------------------------------------

## What fuel costs at the port here, a tonne.
static func port_fuel_price() -> float:
	if Session.sim == null:
		return 120.0
	var lv := SimShip.level(String(Session.profile.get("difficulty", "normal")))
	return float(SimShip.config()["fuel"]["units_per_tonne"]) * float(Session.sim.p["fuel_cr_per_unit"]) * float(Session.sim.fuel_factor.get(Session.system_id(), 1.0)) \
			* float(lv.get("fuel_price_mult", 1.0))


func _fuel_terms(s: NpcShip) -> Dictionary:
	var f: Dictionary = cfg().get("fuel", {})
	var r := RandomNumberGenerator.new()
	r.seed = hash(s.title + str(Session.day()))
	var st: Array = f.get("spare_t", [2, 8])
	var off := clampf(float(Session.profile.get("rep", 0)) * float(f.get("rep_discount_per_point", 0.004)), 0.0, float(f.get("rep_discount_max", 0.2)))
	return {"t": float(r.randi_range(int(st[0]), int(st[1]))), "price": roundi(port_fuel_price() * float(f.get("hauler_price_x", 1.6)) * (1.0 - off))}


func _rescue_terms() -> Dictionary:
	var f: Dictionary = cfg().get("fuel", {})
	return {"t": float(distress.get("wants_t", 3)), "price": roundi(port_fuel_price() * float(f.get("rescue_price_x", 2.5)))}


func _tug_fee() -> int:
	return FlightScene.tow_fee()


func _tow_terms(s: NpcShip) -> int:
	var t: Dictionary = cfg().get("tow", {})
	var r := RandomNumberGenerator.new()
	r.seed = hash("tow|" + s.title + str(Session.day()))
	var x: Array = t.get("hauler_x", [0.6, 1.4])
	var far := float(t.get("far_x", 1.3)) if sc.phase == "cruise" else 1.0   # out on a run, they know you've no choice
	return roundi(float(_tug_fee()) * r.randf_range(float(x[0]), float(x[1])) * far / 10.0) * 10


# --- Talking ------------------------------------------------------------------------------------------

## Say `option` to contact `id` ("control", "pad", "distress", "tug" or "ship:<title>"). {ok, message}.
func act(id: String, option: String) -> Dictionary:
	for c in contacts():
		if String(c.id) != id:
			continue
		for o in c.options:
			if String(o.id) != option:
				continue
			if not bool(o.enabled):
				return {"ok": false, "message": String(o.why)}
			return _do(c, option)
		return {"ok": false, "message": "They don't do that."}
	return {"ok": false, "message": "Nobody by that name in range."}


## The remote's form: "contact|option".
func act_id(both: String) -> Dictionary:
	return act(both.get_slice("|", 0), both.get_slice("|", 1))


func _do(c: Dictionary, option: String) -> Dictionary:
	var kind := String(c.kind)
	match kind:
		"control":
			return _request_dock(c)
		"pad", "camp":
			return _request_land(c)
		"tug":
			_you_say("Port tug, %s. We're dry. Come and get us." % _you())
			_say("Port tug", _line("tug_offer", {"fee": "%s cr" % ShipStats.commas(_tug_fee())}), _voice("tug", _species_here()), 0.3)
			sc.call_for_help()
			return {"ok": true, "message": "Tug called."}
		"distress":
			return _distress_act(option)
		"wreck", "rival":
			return rivals.act(c, option)
	var s: NpcShip = c.ship
	var v := _voice(s.title, _ship_species(s))
	var dist := clampf(float(c.dist_m) / float((cfg().get("range_m", {}) as Dictionary).get("ship", 25000)), 0.0, 1.0)
	match option:
		"news":
			_you_say(_line("you_hail", {"them": _short(s.title)}))
			news_given[String(c.id)] = true
			_say(_short(s.title), _news(), v, dist)
			return {"ok": true, "message": "News from the %s." % _short(s.title)}
		"fuel":
			var terms := _fuel_terms(s)
			var room := float(sc.stats.get("fuel", sc.model.fuel_t)) - sc.model.fuel_t
			var t := minf(float(terms.t), room)
			_you_say(_line("you_hail", {"them": _short(s.title)}))
			_say(_short(s.title), _line("fuel_offer", {"t": "%.0f" % t, "price": ShipStats.commas(int(terms.price))}) + " " + _line("fuel_coming"), v, dist)
			fuel_deal = {"ship": s, "home": s.position, "t": t, "given": 0.0, "price": int(terms.price), "stage": "approach", "done": false, "name": _short(s.title), "voice": v, "nag": 0.0}
			return {"ok": true, "message": "The %s is coming alongside with %.0f t." % [_short(s.title), t]}
		"tow":
			var fee := _tow_terms(s)
			_you_say(_line("you_hail", {"them": _short(s.title)}))
			_say(_short(s.title), _line("tow_offer", {"fee": "%s cr" % ShipStats.commas(fee)}), v, dist)
			settle.tow_delta_cr = fee - _tug_fee()
			settle.tow_by = _short(s.title)
			sc.call_for_help()
			return {"ok": true, "message": "The %s has your line." % _short(s.title)}
	return {"ok": false, "message": "Nothing to say."}


func _request_dock(c: Dictionary) -> Dictionary:
	var sid := _station_id()
	var name := String(c.name)
	var v := _voice("control|" + sid, _species_here())
	var dist := clampf(float(c.dist_m) / 60000.0, 0.0, 1.0)
	var k: Dictionary = cfg().get("clearance", {})
	_you_say(_line("you_clearance", {"control": name}))
	if clear_for == sid:
		_say(name, _line("already", {"berth": str(berth)}), v, dist)
		return {"ok": true, "message": "Cleared: berth %d." % berth}
	if sc.hazard_c != null and not sc.hazard_c.storm_now.is_empty():   # a solar storm on: control wants everyone inside
		_say(name, _line("storm_advice"), v, dist)
	var mover := _free_mover()
	if hold.is_empty() and not mover.is_empty() and rng.randf() < float(k.get("hold_chance", 0.3)):
		mover.rest = 0.0
		mover.out = true
		mover.t = 0.0
		hold = {"mover": mover, "other": _short((mover.ship as NpcShip).title), "t": 0.0, "site": sid, "name": name, "voice": v}
		_say(name, _line("hold", {"other": String(hold.other)}), v, dist)
		_lamps("hold")
		return {"ok": true, "message": "Told to hold for the %s." % String(hold.other)}
	_grant(sid, name, v, dist, "cleared")
	return {"ok": true, "message": "Cleared: berth %d." % berth}


func _grant(sid: String, name: String, v: Dictionary, dist: float, key: String, extra := {}) -> void:
	var b: Array = (cfg().get("clearance", {}) as Dictionary).get("berths", [2, 14])
	clear_for = sid
	berth = rng.randi_range(int(b[0]), int(b[1]))
	var args := {"berth": str(berth)}
	args.merge(extra)
	_say(name, _line(key, args), v, dist)
	_lamps("clear")


func _request_land(c: Dictionary) -> Dictionary:
	var site := _site()
	var v := _voice("pad|" + String(site.id), _species_here())
	_you_say(_line("you_pad", {"control": String(c.name)}))
	_grant(String(site.id), String(c.name), v, 0.3, "pad_cleared" if String(site.kind) == "pad" else "camp_cleared")
	return {"ok": true, "message": "Cleared to land."}


## A mover resting out of sight, to send out of the collar while you hold.
func _free_mover() -> Dictionary:
	if sc.traffic_c == null:
		return {}
	for m in sc.traffic_c.movers:
		if String(m.state) == "rest" and String((m.ship as NpcShip).title).find("SURVEY") < 0:
			return m
	return {}


## The collar's lamps: amber while you hold, green once you're cleared.
func _lamps(state: String) -> void:
	if sc.station == null:
		return
	var old := sc.station.get_node_or_null("ClearanceLamps")
	if old != null:
		old.free()
	var root := Node3D.new()
	root.name = "ClearanceLamps"
	sc.station.add_child(root)
	var col := Color(0.25, 1.0, 0.4) if state == "clear" else Color(1.0, 0.65, 0.15)
	for k in 6:
		var a := k * TAU / 6.0
		var mi := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 1.3
		sm.height = 2.6
		sm.material = Interiors.glow(col, 3.0)
		mi.mesh = sm
		mi.position = Vector3(cos(a) * 9.0, sin(a) * 9.0, 32.6)
		root.add_child(mi)
	var l := OmniLight3D.new()
	l.light_color = col
	l.light_energy = 4.0
	l.omni_range = 45.0
	l.position = Vector3(0, 0, 36)
	root.add_child(l)


func _distress_act(option: String) -> Dictionary:
	var v: Dictionary = distress.voice
	var dist := clampf((distress.ship as NpcShip).global_position.distance_to(sc.model.pos) / 60000.0, 0.0, 1.0)
	var dc: Dictionary = cfg().get("distress", {})
	match option:
		"answer":
			distress["answered"] = true
			_you_say("%s, this is %s. We hear you. Hold on." % [String(distress.name), _you()])
			_say(String(distress.name), _line("sos_answer"), v, dist)
			return {"ok": true, "message": "They know you're coming. X brakes you alongside."}
		"fuel":
			var terms := _rescue_terms()
			var t := float(terms.t)
			sc.model.fuel_t -= t
			sc.model.fuel_burned_t += t   # the port tops you up afterwards, at its price
			var cr := roundi(t * float(terms.price))
			settle.fuel_sold_cr = int(settle.fuel_sold_cr) + cr
			settle.fuel_sold_t = float(settle.fuel_sold_t) + t
			settle.rep = int(settle.rep) + int(dc.get("fuel_rep", 1))
			distress["fuelled"] = true
			distress["helped"] = true
			_say(String(distress.name), _line("sos_fuel", {"t": "%.0f" % t, "price": ShipStats.commas(int(terms.price))}) + " " + _line("sos_bye"), v, dist)
			return {"ok": true, "message": "Sold them %.0f t for %s cr." % [t, ShipStats.commas(cr)]}
		"crew":
			var res: Array = (Session.profile.get("rescued", []) as Array).duplicate(true)
			for p in distress.people:
				var who: Dictionary = (p as Dictionary).duplicate()
				who["handed"] = false
				res.append(who)
			Session.profile["rescued"] = res
			Session.save_profile()
			distress["helped"] = true
			distress["gone"] = true
			settle.rep = int(settle.rep) + int(dc.get("helped_rep", 3))
			_say(String(distress.name), _line("sos_crew"), v, dist)
			(distress.ship as NpcShip).label.text = "ABANDONED  %s" % String(distress.name)
			return {"ok": true, "message": "%d aboard from the %s. Any port's freight office will take it from here." % [int(distress.crew), String(distress.name)]}
		"report":
			distress["reported"] = true
			distress["helped"] = true
			settle.rep = int(settle.rep) + 1
			_you_say("All stations, %s. The %s is adrift on this route, %d aboard. We've no room. Send a boat." % [_you(), String(distress.name), int(distress.crew)])
			_say(String(distress.name), _line("sos_room"), v, dist)
			return {"ok": true, "message": "Reported. The port will send its own boat."}
	return {"ok": false, "message": "Nothing to say."}


# --- Lines ----------------------------------------------------------------------------------------------

func _line(key: String, args := {}) -> String:
	var pool: Array = (cfg().get("lines", {}) as Dictionary).get(key, ["..."])
	var a := {"you": _you()}
	a.merge(args, true)
	var i := rng.randi() % pool.size()
	var text := String(pool[i]).format(a)
	_pending.append({"text": text, "key": "comms:" + key, "index": i, "args": a})   # which line it was, for VoiceBank
	if _pending.size() > 24:
		_pending.pop_front()
	return text


## The lines made by _line that `text` is made of, in order (a news item picked from several, or two lines
## said together); forgets the rest.
func _refs_for(text: String) -> Array:
	var out := []
	var at := 0
	for p in _pending:
		var k := text.find(String(p.text), at)
		if k >= 0 and String(p.text) != "":
			out.append(p)
			at = k + String(p.text).length()
	_pending.clear()
	var said := ""
	for p in out:
		said += String(p.text)
	return out if said.replace(" ", "") == text.replace(" ", "") else []


static func _short(title: String) -> String:
	var bits := title.split("  ")
	return String(bits[bits.size() - 1]).strip_edges() if bits.size() > 1 else title.capitalize()


func _ship_species(s: NpcShip) -> String:
	var pool := ["human", "human", "kesh", "ilyan", "vey", "orun", _species_here(), _species_here()]
	return pool[absi(hash(s.title)) % pool.size()]


func _voice(who: String, species: String) -> Dictionary:
	return RadioVoice.voice(species, hash(who))


## Something the economy knows, in a captain's words.
func _news() -> String:
	var opts := []
	if Session.sim != null:
		for row in TradeData.tight(Session.sim, 6):
			opts.append(_line("news_tight", {"place": String(row.name), "goods": String((row.goods as Array)[0]).to_lower() if not (row.goods as Array).is_empty() else "everything"}))
		for row in TradeData.price_movers(Session.sim, 4):
			if absf(float(row.change)) >= 3.0:
				opts.append(_line("news_price", {"place": String(row.name), "dir": "up" if float(row.change) > 0.0 else "down", "pct": "%d%%" % roundi(absf(float(row.change)))}))
		for st in Hazards.known(Session.system_id(), Session.sim.now_hour()):   # the space weather, first of all
			if int(st.start) > Session.sim.now_hour():
				var wl := _line("news_storm", {"when": Hazards.describe(st, Session.sim.now_hour())})
				opts.append(wl)
				opts.append(wl)
				opts.append(wl)
		for e in Development.recent(Session.sim, 21, Session.system_id()):   # frontier growth: who grew, shrank or emptied
			var key := "news_empty" if int(e.to) == 0 else ("news_grew" if int(e.to) > int(e.from) else "news_shrank")
			var line := _line(key, {"place": String(LocalSpace.node(String(e.site)).get("name", e.site))})
			opts.append(line)
			opts.append(line)   # this week's news first: it's what everyone's talking about
	if sc.traffic_c != null:
		for d in sc.traffic_c.derelicts:
			if not bool(d.deep):
				opts.append(_line("news_wreck", {"wreck": String(d.name), "km": "%.0f" % ((d.ship as NpcShip).global_position.length() / 1000.0)}))
	if opts.is_empty():
		return _line("news_none")
	return String(opts[rng.randi() % opts.size()])


func _you_say(text: String) -> void:
	_pending.clear()
	queue.append({"who": "YOU", "text": text, "voice": {}, "dist": 0.0, "sound": "click"})


## Queue a line from someone over the radio.
func _say(who: String, text: String, v: Dictionary, dist := 0.2, sound := "") -> void:
	var refs := _refs_for(text)
	text = _in_their_words(text, refs, String(v.get("species", "human")))
	queue.append({"who": who, "text": text, "voice": v, "dist": dist, "sound": sound, "refs": refs})


## The species' own version of each line in `refs` (comms.json species_lines: a Kesh controller is formal,
## an Ilyan clipped, a Vey warm, an Orun always "we"), swapped into `text`. Humans keep the base lines.
func _in_their_words(text: String, refs: Array, species: String) -> String:
	var own: Dictionary = (cfg().get("species_lines", {}) as Dictionary).get(species, {})
	if own.is_empty():
		return text
	for r in refs:
		var key := String(r.key).trim_prefix("comms:")
		var pool: Array = own.get(key, [])
		if pool.is_empty():
			continue
		var i := rng.randi() % pool.size()
		var e = pool[i]
		var shown := String(e[0] if e is Array else e).format(r.args)
		text = text.replace(String(r.text), shown)
		r.text = shown
		r.key = "comms:%s@%s" % [key, species]
		r.index = i
	return text


## A call coming in unasked: the chime first (or the SOS beacon), then the line.
func incoming(who: String, text: String, v: Dictionary, dist := 0.2, sos := false) -> void:
	queue.append({"who": "", "text": "", "voice": {}, "dist": dist, "sound": "sos" if sos else "chime"})
	_say(who, text, v, dist)


# --- Every frame --------------------------------------------------------------------------------------

## `dt` is game seconds; `real` real seconds (for the lines being said).
func step(dt: float, real: float) -> void:
	_elapsed += dt
	_play(real)
	_hold_step(dt)
	_fuel_step(dt)
	_distress_step()
	_speed_step()
	if sc.traffic_c != null and not sc.traffic_c.on_take.is_valid():
		sc.traffic_c.on_take = rivals.took
	rivals.step(dt)


func _play(real: float) -> void:
	if not current.is_empty():
		current.t = float(current.t) + real
		if current.has("rec"):
			_recorded_step()
		if float(current.t) < float(current.dur) + 0.6:
			return
		current = {}
	if _task >= 0:
		if not WorkerThreadPool.is_task_completed(_task):
			return
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1
		_start(_making, _made)
		return
	if queue.is_empty():
		return
	var l: Dictionary = queue.pop_front()
	if (l.voice as Dictionary).is_empty():   # a sound, or your own words (no voice: you know what you said)
		var s: AudioStreamWAV = RadioVoice.sos() if String(l.sound) == "sos" else (RadioVoice.chime() if String(l.sound) == "chime" else RadioVoice.click())
		_start(l, s)
		return
	if VoiceBank.enabled() and not (l.get("refs", []) as Array).is_empty():
		var v: Dictionary = l.voice
		var parts := VoiceBank.clips(l.refs, String(v.get("species", "human")), int(v.get("seed", 0)))
		if not parts.is_empty():
			_start_recorded(l, parts)
			return
	_making = l
	_task = WorkerThreadPool.add_task(func() -> void: _made = RadioVoice.speech(String(l.text), l.voice, float(l.dist)), false, "radio voice")


func _start(l: Dictionary, s: AudioStreamWAV) -> void:
	var dur := s.get_length() if s != null else 0.5
	if String(l.text) != "":
		dur = maxf(dur, float(String(l.text).length()) * 0.035)
		current = {"who": String(l.who), "text": String(l.text), "t": 0.0, "dur": dur}
		log.append({"who": String(l.who), "text": String(l.text)})
		if log.size() > 30:
			log.pop_front()
	else:
		current = {"who": "", "text": "", "t": 0.0, "dur": dur}
	if s != null and player.is_inside_tree():
		player.stream = s
		player.play()


## A recorded line: the squelch opens, the words over the carrier hiss, the squelch closes with the beep.
func _start_recorded(l: Dictionary, parts: Array[AudioStream]) -> void:
	var v: Dictionary = l.voice
	var sp := String(v.get("species", "human"))
	var seed_v := int(v.get("seed", 1))
	var lead := 0.0
	if sp != "human":   # their own language first, until the translator catches up
		lead = float(VoiceBank.sound(sp).get("lead_s", 0.0)) if not _heard.has(seed_v) else float(VoiceBank.translator().get("lead_again_s", 0.3))
	_heard[seed_v] = true
	parts = VoiceBank.with_lead(parts, v, lead)
	var len := VoiceBank.length(parts)
	var dist := float(l.dist)
	current = {"who": String(l.who), "text": String(l.text), "t": 0.0, "dur": SQUELCH_S + len + 0.3,
			"rec": {"stream": VoiceBank.joined(parts), "len": len, "dist": dist, "seed": seed_v, "species": sp, "lead": lead, "on": false, "off": false}}
	log.append({"who": String(l.who), "text": String(l.text)})
	if log.size() > 30:
		log.pop_front()
	if player.is_inside_tree():
		player.stream = RadioVoice.squelch(true, int(current.rec.seed))
		player.play()
		hiss_player.stream = RadioVoice.hiss()
		hiss_player.volume_db = lerpf(-30.0, -17.0, clampf(dist, 0.0, 1.0))
		hiss_player.play()


func _recorded_step() -> void:
	var r: Dictionary = current.rec
	var t := float(current.t)
	if not bool(r.on) and t >= SQUELCH_S:
		r.on = true
		if voice_player.is_inside_tree():
			voice_player.bus = VoiceBank.species_bus(String(r.species))
			VoiceBank.radio_bus(float(r.dist))
			voice_player.stream = r.stream
			voice_player.play()
			var layers := VoiceBank.layer_buses(String(r.species))
			while layer_players.size() < layers.size():
				var lp := AudioStreamPlayer.new()
				sc.add_child(lp)
				layer_players.append(lp)
			for k in layers.size():
				layer_players[k].bus = layers[k]
				layer_players[k].stream = r.stream
				layer_players[k].play()
	if not bool(r.off) and t >= SQUELCH_S + float(r.len):
		r.off = true
		if player.is_inside_tree():
			hiss_player.stop()
			player.stream = RadioVoice.squelch(false, int(r.seed) + 1)
			player.play()


## The share of the current line's words shown so far (they type out as it's said).
func shown() -> String:
	if current.is_empty() or String(current.text) == "":
		return ""
	var n := int(ceil(float(String(current.text).length()) * clampf(float(current.t) / maxf(float(current.dur) * 0.9, 0.1), 0.0, 1.0)))
	return String(current.text).substr(0, n)


func _hold_step(dt: float) -> void:
	if hold.is_empty():
		return
	hold.t = float(hold.t) + dt
	var m: Dictionary = hold.mover
	var k: Dictionary = cfg().get("clearance", {})
	var s: NpcShip = m.ship
	var gone := String(m.state) == "rest" and float(m.t) > 0.5 or (s.visible and s.position.length() > float(k.get("hold_clear_m", 1500)))
	if gone or float(hold.t) > float(k.get("hold_max_s", 45)):
		var h := hold
		hold = {}
		_grant(String(h.site), String(h.name), h.voice, 0.2, "after_hold", {"other": String(h.other)})


func _fuel_step(dt: float) -> void:
	if fuel_deal.is_empty() or bool(fuel_deal.done):
		return
	var f: Dictionary = cfg().get("fuel", {})
	var s: NpcShip = fuel_deal.ship
	if not is_instance_valid(s):
		fuel_deal = {}
		return
	var side := sc.model.basis.x * (sc.model.radius_m + float(f.get("alongside_m", 45)))
	match String(fuel_deal.stage):
		"approach":
			var to: Vector3 = sc.model.pos + side - s.position
			var step_m := float(f.get("approach_m_s", 30)) * dt + sc.model.vel.length() * dt
			if to.length() <= step_m + 2.0:
				s.position = sc.model.pos + side
				fuel_deal.stage = "transfer"
			else:
				s.position += to.normalized() * step_m
				s.basis = Basis.looking_at(to.normalized(), Vector3.UP)
				s.set_flames(true)
		"transfer":
			s.position = sc.model.pos + side   # matched with you
			s.set_flames(false)
			var still: bool = sc.model.throttle < 0.02 and sc.model.ang.length() < 0.05 and sc.model.strafe == Vector2.ZERO
			if not still:
				fuel_deal.nag = float(fuel_deal.nag) - dt
				if float(fuel_deal.nag) <= 0.0:
					fuel_deal.nag = 20.0
					_say(String(fuel_deal.name), _line("fuel_wait"), fuel_deal.voice, 0.05)
				return
			var room := float(sc.stats.get("fuel", sc.model.fuel_t)) - sc.model.fuel_t
			var add := minf(minf(float(f.get("transfer_t_s", 0.5)) * dt, float(fuel_deal.t) - float(fuel_deal.given)), room)
			sc.model.fuel_t += add
			sc.model.fuel_burned_t = maxf(0.0, sc.model.fuel_burned_t - add)   # the port won't sell you this again
			fuel_deal.given = float(fuel_deal.given) + add
			if float(fuel_deal.given) >= float(fuel_deal.t) - 0.001 or room - add <= 0.001:
				var cr := roundi(float(fuel_deal.given) * float(fuel_deal.price))
				settle.fuel_bought_cr = int(settle.fuel_bought_cr) + cr
				settle.fuel_bought_t = float(settle.fuel_bought_t) + float(fuel_deal.given)
				_say(String(fuel_deal.name), _line("fuel_done", {"t": "%.1f" % float(fuel_deal.given)}), fuel_deal.voice, 0.05)
				fuel_deal.stage = "leave"
		"leave":
			var home: Vector3 = fuel_deal.home
			var to := home - s.position
			var step_m := float(f.get("approach_m_s", 30)) * dt
			if to.length() <= step_m:
				s.position = home
				s.set_flames(false)
				fuel_deal.done = true
			else:
				s.position += to.normalized() * step_m
				s.basis = Basis.looking_at(to.normalized(), Vector3.UP)
				s.set_flames(true)


## On a run, now and then: somebody calling for help, out along the route.
func _distress_step() -> void:
	if sc.xfer == null or not (sc.phase == "cruise" or sc.phase == "depart") or sc.traffic_c == null:
		return
	var key := String(sc.job.get("key", ""))
	if key == "" or String(distress.get("key", "")) == key:
		return
	var dc: Dictionary = cfg().get("distress", {})
	var r := RandomNumberGenerator.new()
	r.seed = hash("distress|" + key)
	if r.randf() > float(dc.get("chance", 0.2)) or String(sc.job.get("dest_kind", "")) in LocalSpace.SURFACE:
		distress = {"key": key, "gone": true, "none": true}
		return
	var route := sc.xfer.target.normalized()
	var side := route.cross(Vector3.UP)
	side = (side if side.length() > 0.1 else route.cross(Vector3.RIGHT)).normalized().rotated(route, r.randf() * TAU)
	var along: Array = dc.get("along", [0.25, 0.65])
	var side_m: Array = dc.get("side_m", [2000, 7000])
	var at := sc.xfer.target * r.randf_range(float(along[0]), float(along[1])) + side * r.randf_range(float(side_m[0]), float(side_m[1]))
	var names: Array = dc.get("names", ["Long Patience"])
	var nm := String(names[r.randi() % names.size()])
	var sp := Crew._species(r)
	var s := NpcShip.make([ShipPresets.STARTER_FTL, ShipPresets.NPC_HAULER, ShipPresets.STARTER_CABIN][r.randi() % 3], "DISTRESS  %s" % nm)
	s.position = at
	s.label.modulate = Color(1.0, 0.35, 0.3)
	sc.traffic_c.root.add_child(s)
	sc.traffic_c.stops.append(s)
	var cr: Array = dc.get("crew", [1, 4])
	var n := r.randi_range(int(cr[0]), int(cr[1]))
	var people := []
	for k in n:
		var psp := sp if k == 0 or r.randf() < 0.6 else Crew._species(r)
		var role: String = Crew.ROLES[r.randi() % Crew.ROLES.size()]
		var skill := Crew._skill(r)
		var lines: Array = (Crew.cfg().get("lines", {}) as Dictionary).get(role, [""])
		people.append({"name": Crew.make_name(psp, r), "species": psp, "role": role, "skill": skill, "wage": roundi(Crew.base_wage(role, skill)),
				"line": String(lines[r.randi() % lines.size()]) if not lines.is_empty() else "", "ship": nm})
	var wt: Array = (cfg().get("fuel", {}) as Dictionary).get("rescue_wants_t", [2, 5])
	var probs: Array = dc.get("problems", ["We're adrift."])
	distress = {"key": key, "ship": s, "name": nm, "species": sp, "crew": n, "people": people, "wants_t": float(r.randi_range(int(wt[0]), int(wt[1]))),
			"problem": String(probs[r.randi() % probs.size()]), "voice": RadioVoice.voice(sp, hash("distress|" + nm)), "helped": false}
	var spn := String(Worlds.species(sp).get("name", sp)) if not Worlds.species(sp).is_empty() else sp.capitalize()
	incoming("DISTRESS  " + nm, _line("sos", {"them": nm, "species": spn, "problem": String(distress.problem), "crew": "%d" % n}), distress.voice, 0.85, true)


## Coming in hot near the collar: traffic control says so (once every minute and a half).
func _speed_step() -> void:
	if not _station_up() or sc.leaving or not (sc.phase in ["free", "approach"]):
		return
	var k: Dictionary = cfg().get("clearance", {})
	var to: Vector3 = sc.model.port_pos() - sc.model.pos
	var near := to.length() < float(k.get("speed_warn_m", 2000))
	var closing: bool = sc.model.vel.dot(to.normalized()) > 0.0
	if near and closing and sc.model.speed() > float(k.get("speed_warn_m_s", 40)) and _elapsed - _speed_t > 90.0:
		_speed_t = _elapsed
		incoming(_control(_station_name()), _line("speed", {"speed": "%d m/s" % roundi(sc.model.speed())}), _voice("control|" + _station_id(), _species_here()), 0.15)


# --- Arriving -----------------------------------------------------------------------------------------

## The ship has docked (or landed on a pad or at a camp) by its own hand: no clearance, a fine and a
## lecture. `site` is the station or surface site id; `camp` for a camp's smaller fine.
func arrived(site: String, camp := false) -> void:
	if clear_for == site:
		return
	var k: Dictionary = cfg().get("clearance", {})
	var lv := SimShip.level(String(Session.profile.get("difficulty", "normal")))
	var fine := roundi(float(k.get("camp_fine_cr" if camp else "fine_cr", 300)) * float(lv.get("port_fee_mult", 1.0)))
	settle.fine_cr = int(settle.fine_cr) + fine
	settle.fine_rep = int(settle.fine_rep) + int(k.get("fine_rep", -1))
	var who := _control(_station_name()) if not camp and not sc._on_surface() else String(_site().get("name", "Pad control"))
	var line := _line("camp_fined" if camp else "fined", {"fine": "%s cr" % ShipStats.commas(fine)})
	settle.notes.append("%s: \"%s\"" % [who, line])


## What the flight's radio comes to, for Session (flight_extra "comms"), with the ignored distress call.
func settlement() -> Dictionary:
	var out := settle.duplicate(true)
	var rv := rivals.settlement()
	out.rep = int(out.rep) + int(rv.rep)
	out.notes.append_array(rv.notes)
	out["bounty_cr"] = int(rv.get("bounty_cr", 0))
	if not distress.is_empty() and not bool(distress.get("none", false)) and not bool(distress.get("helped", false)):
		out.rep = int(out.rep) + int((cfg().get("distress", {}) as Dictionary).get("ignored_rep", -1))
		out.notes.append("Somebody heard you hear the %s's mayday, and kept flying." % String(distress.name))
	return out


## For the ship remote and the panel.
func state() -> Dictionary:
	var cs := []
	for c in contacts():
		cs.append({"id": String(c.id), "kind": String(c.kind), "name": String(c.name), "dist_m": float(c.dist_m), "options": c.options})
	return {"contacts": cs, "log": log.slice(maxi(0, log.size() - 12)), "now": {"who": String(current.get("who", "")), "text": shown()},
			"cleared": clear_for != "", "berth": berth, "holding": not hold.is_empty()}
