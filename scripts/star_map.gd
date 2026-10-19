class_name StarMap
extends CanvasLayer
## The map (M): where you are in the system, and where the system is in known space.
##
## System chart: the star, the orbits and belts and every body system_bodies.json names, the sites you
## can fly to, where you are, and on a run the route, how far along it you are, how far to go and when
## you'll get there, with arrows for where the nose points and where the ship is actually going.
## Known space: every system at its coordinates (coordinates.json, seen from above), the routes between
## them, yours ringed, and the line of a jump you're flying.
##
## Tab switches charts, the wheel or +/- zooms (out past the system goes to known space), drag pans,
## Home recentres, M or Esc closes. The scene hands the map its state through `source`, a Callable
## returning {system_id, site_id, where, run: {...}, jump: {...}, warp, fuel} (see FlightScene.map_state).
## Positions are a chart, not physics: distances are squashed (square root of the orbit) so the inner
## worlds and the giants fit on one screen.

const KEY_MAP := KEY_M
const AMBER := Color8(242, 167, 27)
const INK := Color8(230, 226, 214)
const DIM := Color8(140, 146, 156)
const FAINT := Color(0.55, 0.6, 0.7, 0.28)
const BACK := Color(0.03, 0.04, 0.06)   # opaque: the flight readouts mustn't show through
const NEAR := ["port", "depot", "moon", "pad", "camp", "world", "field"]   ## the sites round the main world, drawn in the close-up
const ROUTE := Color(0.35, 0.85, 1.0)

## Real orbits for Sol, in AU; everything else is placed by type.
const SOL_AU := {"mercury": 0.39, "venus": 0.72, "earth": 1.0, "mars": 1.52, "sol_belt": 2.7, "jupiter": 5.2, "saturn": 9.5}
## Where each site sits on the chart, by kind: next to the main world, on the moon, on the belt, or at a body.
const SITE_AT := {"venus": "venus", "jovian": "jupiter", "saturn": "saturn", "mars": "mars"}

var source: Callable          ## returns the state the map draws (see above)
var blocks_keys := false      ## true in ports: while the map is open, walking keys do nothing
var view := "system"
var zoom := {"system": 1.0, "space": 1.0}
var pan := {"system": Vector2.ZERO, "space": Vector2.ZERO}
var chart: Control
var _state: Dictionary = {}
var _dragging := false
var _mouse_was := Input.MOUSE_MODE_VISIBLE
var _refresh := 0.0

static var _bodies_cache: Dictionary = {}
static var _routes: Array = []


func _ready() -> void:
	layer = 40
	visible = false
	chart = Control.new()
	chart.set_anchors_preset(Control.PRESET_FULL_RECT)
	chart.mouse_filter = Control.MOUSE_FILTER_STOP
	chart.draw.connect(_draw_chart)
	chart.gui_input.connect(_chart_input)
	add_child(chart)


func is_open() -> bool:
	return visible


func open() -> void:
	visible = true
	_state = source.call() if source.is_valid() else {}
	pan[view] = Vector2.ZERO
	_mouse_was = Input.mouse_mode
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	chart.queue_redraw()


func close() -> void:
	visible = false
	_dragging = false
	Input.mouse_mode = _mouse_was


func toggle() -> void:
	if visible:
		close()
	else:
		open()


func _process(delta: float) -> void:
	if not visible:
		return
	_refresh -= delta
	if _refresh <= 0.0:   # four times a second is plenty for a chart
		_refresh = 0.25
		_state = source.call() if source.is_valid() else {}
		chart.queue_redraw()


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_MAP:
			toggle()
			get_viewport().set_input_as_handled()
			return
		if not visible:
			return
		match event.keycode:
			KEY_ESCAPE:
				close()
			KEY_TAB:
				view = "space" if view == "system" else "system"
			KEY_EQUAL, KEY_KP_ADD:
				_zoom_by(1.25)
			KEY_MINUS, KEY_KP_SUBTRACT:
				_zoom_by(0.8)
			KEY_HOME:
				pan[view] = Vector2.ZERO
				zoom[view] = 1.0
			_:
				if blocks_keys:
					get_viewport().set_input_as_handled()
				return
		chart.queue_redraw()
		get_viewport().set_input_as_handled()


func _chart_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			_zoom_by(1.15)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			_zoom_by(1.0 / 1.15)
		elif event.button_index == MOUSE_BUTTON_LEFT:
			_dragging = event.pressed
	elif event is InputEventMouseMotion and _dragging:
		pan[view] += event.relative
		chart.queue_redraw()


## Zooming out far enough on the system chart steps out to known space, and zooming well in on known
## space steps back into the system.
func _zoom_by(f: float) -> void:
	var z: float = zoom[view] * f
	if view == "system" and z < 0.45:
		view = "space"
		zoom.space = 1.0
		pan.space = Vector2.ZERO
	elif view == "space" and z > 4.0:
		view = "system"
		zoom.system = 1.0
		pan.system = Vector2.ZERO
	else:
		zoom[view] = clampf(z, 0.45, 4.0)
	chart.queue_redraw()


# ---- The system chart, as data (pure, so it tests headless) ------------------------------------

## The bodies of a system with their chart positions (in squashed AU), the belts as rings, and the
## body the main port orbits. {bodies: [{id, name, type, pos, orbit, parent, giant, ring}], primary}
static func system_chart(system_id: String) -> Dictionary:
	if _bodies_cache.has(system_id):
		return _bodies_cache[system_id]
	var raw: Array = []
	var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://data/world/system_bodies.json"))
	if typeof(parsed) == TYPE_DICTIONARY:
		for s in parsed.get("systems", []):
			if String(s.get("system_id", "")) == system_id:
				for b in s.get("bodies", []):
					if not bool(b.get("stub", false)):
						raw.append(b)
	var sys := Worlds.system(system_id)
	var dests: Array = sys.get("destinations", [])
	var primary := String(dests[0].get("id", "")) if not dests.is_empty() else ""
	if raw.is_empty():   # no bodies in canon: the main world on its own
		raw.append({"id": primary if primary != "" else system_id, "name": String(sys.get("name", system_id)), "type": "planet"})
	var ids := raw.map(func(b): return String(b.id))
	if not primary in ids:
		primary = String(raw[0].id)
	for b in raw:   # Sol's main world is Earth, whatever the list's first entry
		if system_id == "sol" and String(b.id) == "earth":
			primary = "earth"
	var out: Array = []
	var prim_pos := Vector2.ZERO
	# Planets and belts first, round the star; moons and habitats after, round the main world.
	var placed := {}
	for b in raw:
		var t := String(b.get("type", ""))
		var id := String(b.id)
		if _is_satellite(id, t) and id != primary:
			continue
		var au := _orbit_au(system_id, id, t)
		var ang := float(absi(hash(system_id + "|" + id)) % 3600) / 3600.0 * TAU
		var r := sqrt(au)
		var pos := Vector2(cos(ang), sin(ang)) * r
		var entry := {"id": id, "name": String(b.get("name", id)), "type": t, "pos": pos, "orbit": r, "parent": "",
				"giant": t.contains("giant"), "ring": t.contains("belt")}
		out.append(entry)
		placed[id] = entry
		if id == primary:
			prim_pos = pos
	var k := 0
	for b in raw:
		var t := String(b.get("type", ""))
		var id := String(b.id)
		if placed.has(id):
			continue
		var ang := float(absi(hash(system_id + "|" + id)) % 3600) / 3600.0 * TAU
		var d := 0.16 + 0.05 * k
		k += 1
		out.append({"id": id, "name": String(b.get("name", id)), "type": t, "pos": prim_pos + Vector2(cos(ang), sin(ang)) * d,
				"orbit": d, "parent": primary, "giant": false, "ring": false})
	var result := {"bodies": out, "primary": primary, "primary_pos": prim_pos}
	_bodies_cache[system_id] = result
	return result


static func _is_satellite(id: String, t: String) -> bool:
	return t.contains("moon") or t.contains("habitat") or t.contains("station") or t.contains("orbital") \
			or t == "settlement" or t == "minor_planet"


static func _orbit_au(system_id: String, id: String, t: String) -> float:
	if system_id == "sol" and SOL_AU.has(id):
		return float(SOL_AU[id])
	if t.contains("icy_belt"):
		return 7.0
	if t.contains("belt"):
		return 2.6
	if t.contains("giant"):
		return 5.0
	if id.ends_with("_inner") or id.ends_with("_starward") or t.begins_with("hot"):
		return 0.4
	if t.contains("icy") or id.ends_with("_outer"):
		return 8.0
	return 1.0


## Where each of the system's sites sits on the chart. {site_id: {pos, name, kind}}
static func site_positions(system_id: String) -> Dictionary:
	var c := system_chart(system_id)
	var prim: Vector2 = c.primary_pos
	var by_id := {}
	var moon := Vector2.INF
	var belt := Vector2.INF
	for b in c.bodies:
		by_id[String(b.id)] = b
		if moon == Vector2.INF and String(b.parent) != "" and String(b.type).contains("moon"):
			moon = b.pos
		if belt == Vector2.INF and bool(b.ring):
			belt = b.pos
	if moon == Vector2.INF:
		moon = prim + Vector2(0.17, -0.1)
	if belt == Vector2.INF:
		var a := float(absi(hash(system_id + "|belt")) % 3600) / 3600.0 * TAU
		belt = Vector2(cos(a), sin(a)) * sqrt(2.6)
	var out := {}
	for n in LocalSpace.nodes(system_id):
		var kind := String(n.kind)
		var at := prim
		match kind:
			"port":
				at = prim + Vector2(0.05, 0.05)
			"depot":
				at = prim + Vector2(-0.08, 0.06)
			"moon":
				at = moon + Vector2(0.04, 0.03)
			"pad":
				at = moon + Vector2(-0.015, -0.01)
			"camp":
				at = moon + Vector2(0.02, -0.03)
			"world":   # down on the main world itself
				at = prim + Vector2(-0.012, 0.012)
			"field":
				at = prim + Vector2(0.014, -0.01)
			"belt":
				at = belt
			_:
				var body := String(SITE_AT.get(kind, ""))
				at = (by_id[body].pos as Vector2) + Vector2(0.06, 0.06) if by_id.has(body) else prim
		out[String(n.id)] = {"pos": at, "name": String(n.name), "kind": kind}
	return out


## Where the ship is on the chart: at its site, or along a run from origin to destination.
static func ship_position(system_id: String, state: Dictionary) -> Vector2:
	var sites := site_positions(system_id)
	var run: Dictionary = state.get("run", {})
	if not run.is_empty() and sites.has(String(run.get("origin_id", ""))) and sites.has(String(run.get("dest_id", ""))):
		var a: Vector2 = sites[String(run.origin_id)].pos
		var b: Vector2 = sites[String(run.dest_id)].pos
		return a.lerp(b, clampf(float(run.get("progress", 0.0)), 0.0, 1.0))
	var here := String(state.get("site_id", ""))
	if sites.has(here):
		return sites[here].pos
	return system_chart(system_id).primary_pos


## Every system at its coordinates (light years, seen from above) and the routes between them.
static func space_chart() -> Dictionary:
	var systems := {}
	for sid in Worlds.system_ids():
		var c := Worlds.coordinate(sid)
		if not c.is_empty():
			systems[sid] = {"pos": Vector2(float(c.x), float(c.y)), "name": String(Worlds.system(sid).get("name", sid)),
					"tier": String((Worlds.system(sid).get("classification", ["developed"]) as Array)[0])}
	if _routes.is_empty():
		var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://data/world/routes.json"))
		if typeof(parsed) == TYPE_DICTIONARY:
			_routes = parsed.get("routes", [])
	var routes: Array = []
	for r in _routes:
		if systems.has(String(r.a)) and systems.has(String(r.b)):
			routes.append({"a": String(r.a), "b": String(r.b), "traffic": String(r.get("traffic", "")), "ly": float(r.get("distance_ly", 0.0))})
	return {"systems": systems, "routes": routes}


# ---- Drawing --------------------------------------------------------------------------------

func _draw_chart() -> void:
	var size := chart.size
	_taken.clear()
	chart.draw_rect(Rect2(Vector2.ZERO, size), BACK)
	var font := ThemeDB.fallback_font
	if view == "system":
		_draw_system(size, font)
	else:
		_draw_space(size, font)
	_draw_panel(size, font)
	var help := "M close   Tab %s   wheel or +/- zoom   drag to pan   Home recentre" % ("known space" if view == "system" else "this system")
	chart.draw_string(font, Vector2(20, size.y - 18), help, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, DIM)


func _draw_system(size: Vector2, font: Font) -> void:
	var sid := String(_state.get("system_id", Session.system_id()))
	var c := system_chart(sid)
	var reach := 0.5
	for b in c.bodies:
		reach = maxf(reach, (b.pos as Vector2).length() + 0.3)
	var scale := minf(size.x, size.y) * 0.44 / reach * float(zoom.system)
	var centre: Vector2 = size * 0.5 + Vector2(120, 0) + (pan.system as Vector2)
	var at := func(p: Vector2) -> Vector2: return centre + p * scale
	# The star.
	chart.draw_circle(centre, 14.0, Color(1.0, 0.85, 0.5, 0.18))
	chart.draw_circle(centre, 7.0, Color(1.0, 0.9, 0.6))
	_label(font, centre + Vector2(4, -6), String(Worlds.system(sid).get("name", sid)), 15, INK)
	# Orbits and belts.
	for b in c.bodies:
		if String(b.parent) != "":
			continue
		var r := float(b.orbit) * scale
		if bool(b.ring):
			for k in 3:
				chart.draw_arc(centre, r + (k - 1) * 4.0, 0, TAU, 160, Color(0.7, 0.62, 0.5, 0.22), 2.0)
		else:
			chart.draw_arc(centre, r, 0, TAU, 128, FAINT, 1.0)
	# Bodies.
	for b in c.bodies:
		var p: Vector2 = at.call(b.pos)
		var rad := 9.0 if bool(b.giant) else (5.0 if String(b.parent) == "" else 3.5)
		if String(b.id) == String(c.primary):
			rad = 7.0
		if bool(b.ring):
			chart.draw_circle(p, 3.0, Color(0.7, 0.62, 0.5))
		else:
			chart.draw_circle(p, rad, _body_colour(String(b.type), String(b.id) == String(c.primary)))
		_label(font, p, String(b.name), 13, DIM)
	# Sites.
	var sites := site_positions(sid)
	var here := String(_state.get("site_id", ""))
	var run: Dictionary = _state.get("run", {})
	var crowd := float(zoom.system) < 2.5   # zoomed out, the sites round the main world sit on top of each other
	for id in sites:
		var s: Dictionary = sites[id]
		var p: Vector2 = at.call(s.pos)
		var hot: bool = id == String(run.get("dest_id", "")) or (run.is_empty() and id == here)
		var col := AMBER if hot else Color(0.95, 0.8, 0.45, 0.75)
		chart.draw_colored_polygon(PackedVector2Array([p + Vector2(0, -5), p + Vector2(5, 0), p + Vector2(0, 5), p + Vector2(-5, 0)]), col)
		if crowd and String(s.kind) in NEAR:
			continue   # named in the close-up instead
		_label(font, p, _short(sid, String(s.name)), 13, col)
	if crowd:
		var pp: Vector2 = at.call(c.primary_pos)
		_label(font, pp + Vector2(0, 22), "port, depot, moon: close-up, bottom left", 12, Color(0.95, 0.8, 0.45, 0.75))
	# The run: the planned route, the part flown, and the ship with its nose and travel arrows.
	var ship: Vector2 = at.call(ship_position(sid, _state))
	if not run.is_empty() and sites.has(String(run.get("origin_id", ""))) and sites.has(String(run.get("dest_id", ""))):
		var a: Vector2 = at.call(sites[String(run.origin_id)].pos)
		var b2: Vector2 = at.call(sites[String(run.dest_id)].pos)
		_dashed(a, b2, Color(ROUTE, 0.55), 2.0)
		chart.draw_line(a, ship, ROUTE, 3.0)
		var along := (b2 - a).normalized() if a.distance_to(b2) > 1.0 else Vector2.RIGHT
		_arrow(ship, along.rotated(deg_to_rad(float(run.get("travel_off", 0.0)))), 34.0, ROUTE)   # where you're going
		_arrow(ship, along.rotated(deg_to_rad(float(run.get("heading_off", 0.0)))), 26.0, Color(0.4, 1.0, 0.55))   # where the nose points
	chart.draw_circle(ship, 6.0, Color(0.4, 1.0, 0.55))
	chart.draw_arc(ship, 11.0, 0, TAU, 32, Color(0.4, 1.0, 0.55, 0.6), 1.5)
	_draw_close_up(size, font, sid, c, sites, run, here)


## A close-up of the main world and the sites round it, bottom left: the port, the fuel depot, the
## moon with its station, pad and camp. Shows the route and the ship too when they're in it.
func _draw_close_up(size: Vector2, font: Font, sid: String, c: Dictionary, sites: Dictionary, run: Dictionary, here: String) -> void:
	var box := Rect2(Vector2(16, size.y - 300), Vector2(380, 250))
	chart.draw_rect(box, Color(0.06, 0.07, 0.1))
	chart.draw_rect(box, Color(AMBER, 0.5), false, 1.5)
	var prim: Vector2 = c.primary_pos
	var reach := 0.05
	for id in sites:
		if String(sites[id].kind) in NEAR:
			reach = maxf(reach, (sites[id].pos as Vector2).distance_to(prim))
	var mid := box.position + box.size * Vector2(0.42, 0.55)
	var k := minf(box.size.x, box.size.y) * 0.36 / reach
	var at := func(p: Vector2) -> Vector2: return mid + (p - prim) * k
	var pname := ""
	for b in c.bodies:
		if String(b.id) == String(c.primary):
			pname = String(b.name)
		if String(b.parent) == String(c.primary) or String(b.id) == String(c.primary):
			var bp: Vector2 = at.call(b.pos)
			if box.grow(-6).has_point(bp):
				var r := 16.0 if String(b.id) == String(c.primary) else 8.0
				chart.draw_circle(bp, r, _body_colour(String(b.type), String(b.id) == String(c.primary)))
				chart.draw_string(font, bp + Vector2(-r, r + 14), String(b.name), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, DIM)
	chart.draw_string(font, box.position + Vector2(12, 20), "Close-up: %s" % pname, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, AMBER)
	var a_id := String(run.get("origin_id", ""))
	var b_id := String(run.get("dest_id", ""))
	if sites.has(a_id) and sites.has(b_id) and String(sites[a_id].kind) in NEAR and String(sites[b_id].kind) in NEAR:
		var a: Vector2 = at.call(sites[a_id].pos)
		var b: Vector2 = at.call(sites[b_id].pos)
		_dashed(a, b, Color(ROUTE, 0.55), 2.0)
		var shp: Vector2 = a.lerp(b, clampf(float(run.get("progress", 0.0)), 0.0, 1.0))
		chart.draw_line(a, shp, ROUTE, 3.0)
		chart.draw_circle(shp, 5.0, Color(0.4, 1.0, 0.55))
	var row := 0
	for id in sites:
		var s: Dictionary = sites[id]
		if not String(s.kind) in NEAR:
			continue
		var p: Vector2 = at.call(s.pos)
		var hot: bool = id == b_id or (run.is_empty() and id == here)
		var col := AMBER if hot else Color(0.95, 0.8, 0.45, 0.8)
		chart.draw_colored_polygon(PackedVector2Array([p + Vector2(0, -5), p + Vector2(5, 0), p + Vector2(0, 5), p + Vector2(-5, 0)]), col)
		# Labels go in a column on the right, joined to their marker, so none overprint.
		var lp := Vector2(box.end.x - 158, box.position.y + 44 + row * 38)
		row += 1
		chart.draw_line(p, lp + Vector2(-4, -4), Color(col, 0.35), 1.0)
		chart.draw_string(font, lp, _short(sid, String(s.name)), HORIZONTAL_ALIGNMENT_LEFT, 154, 12, col)
		if id == here and run.is_empty():
			chart.draw_circle(p, 5.0, Color(0.4, 1.0, 0.55))


## A site's name without the system's name in front.
static func _short(sid: String, name: String) -> String:
	return name.trim_prefix(String(Worlds.system(sid).get("name", "")) + " ")


func _body_colour(t: String, primary: bool) -> Color:
	if primary:
		return Color(0.4, 0.65, 0.9)
	if t.contains("giant"):
		return Color(0.82, 0.7, 0.52)
	if t.contains("icy"):
		return Color(0.8, 0.86, 0.92)
	if t.begins_with("hot") or t.contains("hostile"):
		return Color(0.85, 0.55, 0.35)
	if t.contains("habitat") or t.contains("station") or t.contains("orbital"):
		return Color(0.6, 0.85, 0.9)
	return Color(0.6, 0.6, 0.62)


func _draw_space(size: Vector2, font: Font) -> void:
	var sp := space_chart()
	var here := String(_state.get("system_id", Session.system_id()))
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for sid in sp.systems:
		var p: Vector2 = sp.systems[sid].pos
		lo = Vector2(minf(lo.x, p.x), minf(lo.y, p.y))
		hi = Vector2(maxf(hi.x, p.x), maxf(hi.y, p.y))
	var span := maxf(hi.x - lo.x, hi.y - lo.y) + 4.0
	var scale := minf(size.x, size.y) * 0.85 / span * float(zoom.space)
	var mid := (lo + hi) * 0.5
	var centre: Vector2 = size * 0.5 + Vector2(120, 0) + (pan.space as Vector2)
	var at := func(p: Vector2) -> Vector2: return centre + (p - mid) * scale
	for r in sp.routes:
		var w := 2.5 if r.traffic == "heavy" else (1.6 if r.traffic in ["moderate", "medium"] else 1.0)
		chart.draw_line(at.call(sp.systems[r.a].pos), at.call(sp.systems[r.b].pos), Color(0.55, 0.65, 0.8, 0.35), w)
	var jump: Dictionary = _state.get("jump", {})
	var dest := String(jump.get("dest_system", ""))
	if dest != "" and sp.systems.has(dest) and sp.systems.has(String(jump.get("from_system", here))):
		var a: Vector2 = at.call(sp.systems[String(jump.get("from_system", here))].pos)
		var b: Vector2 = at.call(sp.systems[dest].pos)
		_dashed(a, b, ROUTE, 2.5)
		chart.draw_circle(a.lerp(b, clampf(float(jump.get("progress", 0.0)), 0.0, 1.0)), 6.0, Color(0.4, 1.0, 0.55))
	for sid in sp.systems:
		var s: Dictionary = sp.systems[sid]
		var p: Vector2 = at.call(s.pos)
		var col := {"core": INK, "developed": Color(0.75, 0.8, 0.9), "outer": Color(0.7, 0.75, 0.6), "frontier": Color(0.9, 0.65, 0.4),
				"extreme_frontier": Color(0.9, 0.45, 0.35)}.get(s.tier, DIM) as Color
		chart.draw_circle(p, 6.0 if sid == here else 4.5, col)
		if sid == here:
			chart.draw_arc(p, 13.0, 0, TAU, 40, Color(0.4, 1.0, 0.55), 2.0)
		if sid == dest:
			chart.draw_arc(p, 11.0, 0, TAU, 40, AMBER, 2.0)
		_label(font, p, String(s.name), 14, AMBER if sid == dest else (INK if sid == here else DIM))
	# A scale bar.
	var ly := 5.0
	var px := ly * scale
	var y := size.y - 50.0
	chart.draw_line(Vector2(size.x - 40 - px, y), Vector2(size.x - 40, y), DIM, 2.0)
	chart.draw_string(font, Vector2(size.x - 40 - px, y - 8), "%d light years" % int(ly), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, DIM)


## Where you are, in words, top left.
func _draw_panel(size: Vector2, font: Font) -> void:
	var lines: Array[String] = []
	var sid := String(_state.get("system_id", Session.system_id()))
	lines.append(("SYSTEM CHART  " if view == "system" else "KNOWN SPACE  ") + String(Worlds.system(sid).get("name", sid)).to_upper())
	lines.append(String(_state.get("where", "")))
	var run: Dictionary = _state.get("run", {})
	if not run.is_empty():
		lines.append("To %s" % String(run.get("dest_name", "the destination")))
		lines.append("%s to go, %d%% of the way" % [_km(float(run.get("range_m", 0.0))), int(float(run.get("progress", 0.0)) * 100.0)])
		var c := float(run.get("closing", 0.0))
		lines.append("Closing %s/s" % _km(c) if c >= 0.0 else "Moving away at %s/s" % _km(-c))
		var eta := float(run.get("eta_s", -1.0))
		var w := maxi(int(_state.get("warp", 1)), 1)
		if eta <= 0.0:
			lines.append("Arriving: not at this rate")
		elif w > 1:
			lines.append("Arriving in %s (%s at x%d)" % [_clock(eta), _clock(eta / w), w])
		else:
			lines.append("Arriving in %s" % _clock(eta))
		lines.append("Nose %d° off the route, travel %d° off" % [int(absf(float(run.get("heading_off", 0.0)))), int(absf(float(run.get("travel_off", 0.0))))])
	var jump: Dictionary = _state.get("jump", {})
	if not jump.is_empty():
		lines.append("Jump to %s, %.1f ly" % [String(Worlds.system(String(jump.get("dest_system", ""))).get("name", "?")), float(jump.get("ly", 0.0))])
	if _state.has("warp"):
		lines.append("Time x%d" % int(_state.warp))
	if _state.has("fuel"):
		lines.append("Fuel %.1f t" % float(_state.fuel))
	var box := Rect2(Vector2(16, 16), Vector2(330, 22 + lines.size() * 20))
	chart.draw_rect(box, Color(0.06, 0.07, 0.1, 0.9))
	chart.draw_rect(box, Color(AMBER, 0.6), false, 1.5)
	for i in lines.size():
		chart.draw_string(font, Vector2(28, 40 + i * 20), lines[i], HORIZONTAL_ALIGNMENT_LEFT, 310, 15 if i > 0 else 16, AMBER if i == 0 else INK)


var _taken: Array[Rect2] = []   ## label boxes already drawn this frame


## A label beside `p`, in the first of a few spots that doesn't overprint another label.
func _label(font: Font, p: Vector2, text: String, size: int, col: Color) -> void:
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var h := float(size) + 2.0
	var tries := [Vector2(9, -6), Vector2(9, size + 8), Vector2(9, -size - 10), Vector2(-w - 9, -6), Vector2(-w - 9, size + 8),
			Vector2(9, size * 2 + 12), Vector2(-w * 0.5, -size - 12)]
	var pick: Vector2 = tries[0]
	for t in tries:
		var r := Rect2(p + t - Vector2(0, h - 3), Vector2(w, h))
		var clear := true
		for q in _taken:
			if q.intersects(r):
				clear = false
				break
		if clear:
			pick = t
			break
	_taken.append(Rect2(p + pick - Vector2(0, h - 3), Vector2(w, h)))
	chart.draw_string(font, p + pick, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)


func _dashed(a: Vector2, b: Vector2, col: Color, w: float) -> void:
	var d := a.distance_to(b)
	if d < 1.0:
		return
	var dir := (b - a) / d
	var t := 0.0
	while t < d:
		chart.draw_line(a + dir * t, a + dir * minf(t + 8.0, d), col, w)
		t += 14.0


func _arrow(p: Vector2, dir: Vector2, length: float, col: Color) -> void:
	var tip := p + dir * length
	chart.draw_line(p, tip, col, 2.0)
	chart.draw_colored_polygon(PackedVector2Array([tip, tip - dir.rotated(0.45) * 9.0, tip - dir.rotated(-0.45) * 9.0]), col)


static func _km(m: float) -> String:
	return "%.1f km" % (m / 1000.0) if m < 100000.0 else "%s km" % ShipStats.commas(roundi(m / 1000.0))


static func _clock(s: float) -> String:
	if s >= 3600.0:
		return "%dh %02dm" % [int(s / 3600.0), int(fmod(s, 3600.0) / 60.0)]
	return "%dm %02ds" % [int(s / 60.0), int(fmod(s, 60.0))]
