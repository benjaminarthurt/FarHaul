class_name PassengersAboard
extends RefCounted
## The passengers aboard during a flight (Passengers), seen when you walk the ship: dressed for travel,
## not work (Figure outfit "passenger"), in the beds they paid for: the stateroom, the quarters, a
## cabin, or a spare crew bunk. Walk up to one and they have something to say about it.

var sc: FlightScene
var figures: Array[Figure] = []
var _placed := false

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


## Who's within arm's reach: "MAGS OSEI, PASSENGER TO CONCORD, IN A CABIN: The viewport's..." or "".
func near_line() -> String:
	if not sc.walking or sc.walk == null:
		return ""
	for f in figures:
		if Vector2(f.position.x - sc.walk.pos.x, f.position.z - sc.walk.pos.z).length() < 1.6 and absf(f.position.y - sc.walk.pos.y) < 1.0:
			return line_for(f.get_meta("booking"), int(f.get_meta("tier")), int(f.get_meta("n")))
	return ""


static func line_for(b: Dictionary, t: int, n: int) -> String:
	var said: Dictionary = Passengers.cfg().get("aboard", {})
	var late := Session.day() > int(b.get("due_day", 1 << 30))
	var pool: Array = said.get("late" if late else String(Passengers.tier(t).id), ["..."])
	var line := String(pool[absi(hash(String(b.get("id", "")) + str(n))) % pool.size()])
	if line.contains("%s"):
		line = line % String(b.get("dest_name", "there"))
	var who := String(b.get("person", "")) if n == 0 else "%s's party" % String(b.get("person", "")).get_slice(" ", 0)
	return "%s, PASSENGER TO %s\n\"%s\"" % [who.to_upper(), String(b.get("dest_name", "")).to_upper(), line]
