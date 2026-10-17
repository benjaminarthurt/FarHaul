class_name PassengersAboard
extends RefCounted
## The passengers aboard during a flight (Passengers), seen when you walk the ship: dressed for travel,
## not work (Figure outfit "passenger"), in the beds they paid for: the stateroom, the quarters, a
## cabin, or a spare crew bunk. Walk up to one and they have something to say about it, out loud when
## there's a recording of it (VoiceBank): once each time you come up to them.

var sc: FlightScene
var figures: Array[Figure] = []
var _placed := false
var _near: Figure = null      ## who you're standing by: they've had their say until you walk away

## Where each tier of bed is, by module id, in order of preference.
const ROOMS := {
	0: ["bunk", "room_2x2"],
	1: ["pax_cabin"],
	2: ["pax_quarters"],
	3: ["pax_stateroom"],
}
## Coats for travelling in: none of them a crew job's colour.
const COATS := [Color(0.86, 0.80, 0.66), Color(0.45, 0.25, 0.50), Color(0.15, 0.48, 0.50), Color(0.24, 0.24, 0.27),
		Color(0.55, 0.70, 0.86), Color(0.82, 0.52, 0.58), Color(0.62, 0.58, 0.40), Color(0.92, 0.92, 0.9)]


func _init(scene: FlightScene) -> void:
	sc = scene


## One per person aboard, up to max_figures: {booking, tier, n}.
static func people() -> Array:
	var out := []
	var cap := int(Passengers.cfg().get("max_figures", 10))
	for b in Passengers.aboard():
		var beds: Array = b.get("beds", [])
		for k in int(b.get("seats", 0)):
			if out.size() < cap:
				out.append({"booking": b, "tier": int(beds[k]) if k < beds.size() else 0, "n": k})
	return out


func _place() -> void:
	if _placed or sc.walk == null or sc.view == null or sc.ship_data == null:
		return
	_placed = true
	var doors := _doors()
	var taken: Array[Vector3] = []
	if sc.crew_c != null:
		for f in sc.crew_c.figures:
			taken.append(f.position)
	for p in people():
		var b: Dictionary = p.booking
		var spot := Vector3.INF
		var centre := Vector3.ZERO
		for want in ROOMS.get(int(p.tier), []) + ["tee", "corridor", ""]:
			var best := -1.0
			for c in sc.walk.cells:   # every free spot in every cell of that kind of room: the one furthest from anyone
				var mi: int = sc.walk.cells[c]
				if want != "" and String(sc.ship_data.modules[mi].id) != want:
					continue
				var base := Vector3(Vector3i(c)) * ShipGrid.CELL
				base.y = ShipWalk.deck_y((c as Vector3i).y)
				for x in [0.0, 0.5, -0.5, 1.0, -1.0]:
					for z in [0.0, 0.5, -0.5, 1.0, -1.0]:
						var at: Vector3 = base + Vector3(x, 0, z)
						if not sc.walk.free_at(at) or not _clear(at, doors):
							continue
						var room := 9.0
						for t in taken:
							room = minf(room, t.distance_to(at))
						if room > 0.8 and room > best:
							best = room
							spot = at
							centre = base
			if spot != Vector3.INF:
				break
		if spot == Vector3.INF:
			continue
		taken.append(spot)
		var seed_v := hash("%s|%d" % [String(b.get("id", "")), int(p.n)])
		var f := Figure.make(COATS[absi(seed_v) % COATS.size()], seed_v, false, String(b.get("species", "human")), "passenger")
		f.position = spot
		var face := centre - spot
		if face.length() > 0.01:
			f.rotation.y = atan2(-face.x, -face.z)
		f.visible = false
		f.set_meta("booking", b)
		f.set_meta("tier", int(p.tier))
		f.set_meta("n", int(p.n))
		sc.view.add_child(f)
		var mouth := AudioStreamPlayer3D.new()
		mouth.name = "Voice"
		mouth.bus = GameSettings.bus("Effects")
		mouth.position = Vector3(0, 1.55, 0)
		mouth.unit_size = 3.0
		mouth.max_distance = 12.0
		f.add_child(mouth)
		figures.append(f)


## The middle of every doorway aboard, in the walk's space.
func _doors() -> Array[Vector3]:
	var out: Array[Vector3] = []
	for m in sc.ship_data.modules:
		for sk in sc.ship_data.world_sockets(m.id, m.cell, int(m.rot)):
			if sk.kind == ModuleSocket.DOOR and (sk.dir as Vector3i).y == 0:
				var at := (Vector3(sk.cell) + Vector3(sk.dir) * 0.5) * ShipGrid.CELL
				at.y = ShipWalk.deck_y((sk.cell as Vector3i).y)
				out.append(at)
	return out


## Not in the way: the helm, the airlock, a doorway.
func _clear(at: Vector3, doors: Array[Vector3]) -> bool:
	for p in [sc.walk.helm_stand, sc.walk.airlock]:
		if p != Vector3.INF and Vector2(at.x - p.x, at.z - p.z).length() < 1.0 and absf(at.y - p.y) < 1.0:
			return false
	for d in doors:
		if Vector2(at.x - d.x, at.z - d.z).length() < 1.1 and absf(at.y - d.y) < 1.0:
			return false
	return true


func step() -> void:
	if Passengers.count() == 0:
		return
	if sc.crew_c != null:
		sc.crew_c._place_figures()   # the crew take their posts first
	_place()
	for f in figures:
		f.visible = sc.walking
		f.look_at_point = sc.view.to_global(sc.walk.pos + Vector3(0, 1.6, 0)) if sc.walking and f.position.distance_to(sc.walk.pos) < 4.0 else Vector3.INF
	var by := _nearest()
	if by != _near:
		_near = by
		if by != null:
			_speak(by)


func _nearest() -> Figure:
	if not sc.walking or sc.walk == null:
		return null
	for f in figures:
		if Vector2(f.position.x - sc.walk.pos.x, f.position.z - sc.walk.pos.z).length() < 1.6 and absf(f.position.y - sc.walk.pos.y) < 1.0:
			return f
	return null


## Say their line out loud, if it's recorded.
func _speak(f: Figure) -> void:
	if not VoiceBank.enabled() or not f.has_node("Voice"):
		return
	var b: Dictionary = f.get_meta("booking")
	var ref := line_ref(b, int(f.get_meta("tier")), int(f.get_meta("n")))
	var parts := VoiceBank.clips([ref], String(b.get("species", "human")), hash("%s|%d" % [String(b.get("id", "")), int(f.get_meta("n"))]))
	if parts.is_empty():
		return
	var sp := String(b.get("species", "human"))
	var seed_v := hash("%s|%d" % [String(b.get("id", "")), int(f.get_meta("n"))])
	if sp != "human" and not f.has_meta("heard"):   # their own language first, the first time you meet
		parts = VoiceBank.with_lead(parts, RadioVoice.voice(sp, seed_v), float(VoiceBank.translator().get("aboard_lead_s", 0.45)))
	f.set_meta("heard", true)
	var stream := VoiceBank.joined(parts)
	var mouth := f.get_node("Voice") as AudioStreamPlayer3D
	mouth.bus = VoiceBank.species_bus(sp, false)
	mouth.stream = stream
	mouth.play()
	var layers := VoiceBank.layer_buses(sp, false)
	for k in layers.size():   # a Kesh's octave-down, an Ilyan's octave-up, from the same spot
		var name := "Layer%d" % k
		if not f.has_node(name):
			var lp := AudioStreamPlayer3D.new()
			lp.name = name
			lp.position = mouth.position
			lp.unit_size = mouth.unit_size
			lp.max_distance = mouth.max_distance
			f.add_child(lp)
		var lp3 := f.get_node(name) as AudioStreamPlayer3D
		lp3.bus = layers[k]
		lp3.stream = stream
		lp3.play()


## Who's within arm's reach: "MAGS OSEI, PASSENGER TO CONCORD, IN A CABIN: The viewport's..." or "".
func near_line() -> String:
	var f := _nearest()
	return line_for(f.get_meta("booking"), int(f.get_meta("tier")), int(f.get_meta("n"))) if f != null else ""


## Which of passengers.json's aboard lines this passenger says: {key "aboard:<pool>", index}.
## Their species' own way of putting it (passengers.json aboard_by_species) where there is one.
static func line_ref(b: Dictionary, t: int, n: int) -> Dictionary:
	var late := Session.day() > int(b.get("due_day", 1 << 30))
	var key := "late" if late else String(Passengers.tier(t).id)
	var sp := String(b.get("species", "human"))
	var own: Array = ((Passengers.cfg().get("aboard_by_species", {}) as Dictionary).get(sp, {}) as Dictionary).get(key, [])
	var pool: Array = own if not own.is_empty() else (Passengers.cfg().get("aboard", {}) as Dictionary).get(key, ["..."])
	var tag := "aboard:" + key + ("@" + sp if not own.is_empty() else "")
	return {"key": tag, "index": absi(hash(String(b.get("id", "")) + str(n))) % pool.size(), "args": {}, "pool": pool}


static func line_for(b: Dictionary, t: int, n: int) -> String:
	var ref := line_ref(b, t, n)
	var pool: Array = ref.pool
	var line := String(pool[int(ref.index)])
	if line.contains("%s"):
		line = line % String(b.get("dest_name", "there"))
	var who := String(b.get("person", "")) if n == 0 else "%s's party" % String(b.get("person", "")).get_slice(" ", 0)
	return "%s, PASSENGER TO %s\n\"%s\"" % [who.to_upper(), String(b.get("dest_name", "")).to_upper(), line]
