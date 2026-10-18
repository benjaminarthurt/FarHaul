class_name TradeReport
extends CanvasLayer
## The trade report (N, anywhere in a game; also the pause menu and the freight office): the economy
## simulation made visible. Four pages, drawn from TradeData:
##   Overview:   freight and goods money and tonnes over the last 30 days, ships at work, the shelves
##               running short and every system's prices against the going rate.
##   Flows:      known space with the week's freight drawn on its lanes, every ship where it is (loaded,
##               empty, or you), and the busiest lanes.
##   Companies:  each carrier company's fleet, freight earned and share over 30 days, and cash; you
##               ranked among them.
##   Your mark:  what you've hauled, earned and relieved, your share of the trade, and who you've supplied.
##   Growth:     frontier growth (Development): this system's sites, how big, which way, and why; what
##               grew and shrank lately; every system's size.
## 1-5 or Tab switch pages, N or Esc closes. The game pauses while it's open.
## GameSettings.apply_scene adds one to each scene (attach()).

const KEY := KEY_N
const PAGES := ["overview", "flows", "companies", "you", "growth"]
const TITLES := {"overview": "OVERVIEW", "flows": "FLOWS", "companies": "COMPANIES", "you": "YOUR MARK", "growth": "GROWTH"}

const BACK := Color(0.03, 0.04, 0.06)
const PLATE := Color(0.065, 0.075, 0.1)
const RULE := Color(0.55, 0.6, 0.7, 0.18)
const INK := Color8(230, 226, 214)
const DIM := Color8(140, 146, 156)
const AMBER := Color8(242, 167, 27)      ## money
const GOODS := Color(0.35, 0.85, 1.0)    ## goods and tonnes
const YOU := Color(0.4, 1.0, 0.55)       ## you, wherever you are
const ALARM := Color8(236, 78, 58)

var page := "overview"
var board: Control
var tabs: HBoxContainer
var _buttons := {}
var _data := {}          ## the open page's TradeData
var _t := 0.0            ## animation clock (the game is paused; this isn't)
var _refresh := 0.0
var _mouse_before := Input.MOUSE_MODE_VISIBLE
var _paused_before := false


static func attach(scene: Node) -> TradeReport:
	if scene == null or scene.get_node_or_null("TradeReport") != null:
		return null
	if scene.scene_file_path == Session.BOOT_SCENE or scene.scene_file_path == "":
		return null
	var r := TradeReport.new()
	r.name = "TradeReport"
	scene.add_child(r)
	return r


## The report in the current scene, if there is one.
static func find(tree: SceneTree) -> TradeReport:
	if tree == null or tree.current_scene == null:
		return null
	return tree.current_scene.get_node_or_null("TradeReport") as TradeReport


func _ready() -> void:
	layer = 45
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	board = Control.new()
	board.set_anchors_preset(Control.PRESET_FULL_RECT)
	board.mouse_filter = Control.MOUSE_FILTER_STOP
	board.draw.connect(_draw_board)
	add_child(board)
	tabs = HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 6)
	tabs.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE, 18)
	tabs.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	add_child(tabs)
	var group := ButtonGroup.new()
	for i in PAGES.size():
		var id: String = PAGES[i]
		var b := Brand.toggle("%d  %s" % [i + 1, TITLES[id]], group, 14)
		b.button_pressed = id == page
		b.pressed.connect(func() -> void: show_page(id))
		tabs.add_child(b)
		_buttons[id] = b


func is_open() -> bool:
	return visible


func open(which := "") -> void:
	if which != "":
		page = which
	if not visible:
		_mouse_before = Input.mouse_mode
		_paused_before = get_tree().paused
	visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().paused = true
	show_page(page)


func close() -> void:
	if not visible:
		return
	visible = false
	get_tree().paused = _paused_before
	Input.mouse_mode = _mouse_before


func toggle() -> void:
	if visible:
		close()
	else:
		open()


func show_page(id: String) -> void:
	page = id
	if _buttons.has(id):
		(_buttons[id] as Button).button_pressed = true
	_load()
	board.queue_redraw()


func _load() -> void:
	var sim := Session.sim
	_data = {}
	if sim == null:
		return
	match page:
		"overview":
			_data = TradeData.overview(sim)
		"flows":
			_data = TradeData.flows(sim, 7)
		"companies":
			_data = {"rows": TradeData.companies(sim)}
		"you":
			_data = TradeData.player(sim)
		"growth":
			_data = TradeData.growth(sim, Session.system_id())


func _input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	if event.keycode == KEY:
		if get_viewport().gui_get_focus_owner() is LineEdit:
			return   # typing a ship's name
		var menu := get_parent().get_node_or_null("GameMenu") as GameMenu
		if menu != null and menu.is_open():
			return
		toggle()
		get_viewport().set_input_as_handled()
		return
	if not visible:
		return
	match event.keycode:
		KEY_ESCAPE:
			close()
		KEY_1, KEY_2, KEY_3, KEY_4, KEY_5:
			show_page(PAGES[event.keycode - KEY_1])
		KEY_TAB:
			show_page(PAGES[(PAGES.find(page) + 1) % PAGES.size()])
	get_viewport().set_input_as_handled()   # nothing else hears keys while it's open


func _process(delta: float) -> void:
	if not visible:
		return
	_t += delta
	_refresh -= delta
	if _refresh <= 0.0:
		_refresh = 1.0
		_load()   # cheap, and ships keep moving if the world is (the phone can unpause it)
	if page == "flows":
		board.queue_redraw()


# ---- Formatting -----------------------------------------------------------------------------------

static func cr(v: float) -> String:
	var a := absf(v)
	var s := ""
	if a >= 1.0e6:
		s = "%.2fM" % (a / 1.0e6)
	elif a >= 1.0e5:
		s = "%dk" % roundi(a / 1000.0)
	else:
		s = ShipStats.commas(roundi(a))
	return ("-" if v < 0.0 else "") + s + " cr"


static func tonnes(v: float) -> String:
	if v >= 10000.0:
		return "%sk t" % ("%.1f" % (v / 1000.0))
	if v >= 100.0:
		return "%s t" % ShipStats.commas(roundi(v))
	return "%.1f t" % v


static func change(v: float) -> String:
	if absf(v) < 0.005:
		return "level with last week"
	return "%s%d%% on last week" % ["+" if v > 0.0 else "", roundi(v * 100.0)]


# ---- Drawing --------------------------------------------------------------------------------------

var _font: Font


func _text(p: Vector2, s: String, size: int, col: Color, width := -1.0, align := HORIZONTAL_ALIGNMENT_LEFT) -> void:
	board.draw_string(_font, p, s, align, width, size, col, TextServer.JUSTIFICATION_NONE)


func _w(s: String, size: int) -> float:
	return _font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x


## `s` cut to fit `width`, with an ellipsis.
func _fit(s: String, size: int, width: float) -> String:
	if _w(s, size) <= width:
		return s
	while s.length() > 1 and _w(s + "…", size) > width:
		s = s.left(s.length() - 1)
	return s + "…"


func _heading(p: Vector2, s: String, width: float) -> void:
	_text(p, s, 14, AMBER)
	board.draw_line(p + Vector2(0, 8), p + Vector2(width, 8), RULE, 1.0)


func _draw_board() -> void:
	_font = ThemeDB.fallback_font
	var size := board.size
	board.draw_rect(Rect2(Vector2.ZERO, size), BACK)
	board.draw_rect(Rect2(0, 0, size.x, 4), AMBER)
	var sim := Session.sim
	_text(Vector2(24, 38), "TRADE REPORT", 24, AMBER)
	var sub := "No game running, so no economy. Bliss." if sim == null else "Known space, day %d. What the freight does while you aren't looking." % SimWorld.day(sim)
	_text(Vector2(24, 60), _fit(sub, 14, size.x - tabs.size.x - 60.0), 14, DIM)
	_text(Vector2(24, size.y - 16), "N or Esc close    1-5 or Tab switch pages    the game waits while you read", 13, DIM)
	if sim == null or _data.is_empty():
		return
	var area := Rect2(24, 84, size.x - 48, size.y - 84 - 36)
	match page:
		"overview":
			_draw_overview(area)
		"flows":
			_draw_flows(area)
		"companies":
			_draw_companies(area)
		"you":
			_draw_you(area)
		"growth":
			_draw_growth(area)


## A line of daily values, scaled to its own peak, in `r`.
func _spark(r: Rect2, values: Array, col: Color) -> void:
	if values.size() < 2:
		return
	var peak := 0.0
	for v in values:
		peak = maxf(peak, float(v))
	if peak <= 0.0:
		board.draw_line(Vector2(r.position.x, r.end.y), r.end, Color(col, 0.4), 1.5)
		return
	var pts := PackedVector2Array()
	for i in values.size():
		pts.append(Vector2(r.position.x + r.size.x * i / float(values.size() - 1), r.end.y - r.size.y * float(values[i]) / peak))
	var fill := PackedVector2Array(pts)
	fill.append(r.end)
	fill.append(Vector2(r.position.x, r.end.y))
	board.draw_colored_polygon(fill, Color(col, 0.12))
	board.draw_polyline(pts, col, 2.0, true)
	board.draw_circle(pts[pts.size() - 1], 3.0, col)


func _readout(r: Rect2, label: String, value: String, note: String, col: Color, series: Array) -> void:
	board.draw_rect(r, PLATE)
	board.draw_rect(Rect2(r.position, Vector2(3, r.size.y)), col)
	_text(r.position + Vector2(16, 24), label, 13, DIM)
	_text(r.position + Vector2(16, 58), value, 28, INK)
	_text(r.position + Vector2(16, 80), _fit(note, 13, r.size.x - 32), 13, col)
	if not series.is_empty():
		_spark(Rect2(r.position + Vector2(16, 92), Vector2(r.size.x - 32, r.size.y - 104)), series, col)


func _draw_overview(a: Rect2) -> void:
	var d := _data
	var gap := 14.0
	var w := (a.size.x - gap * 3.0) / 4.0
	var h := 168.0
	var cs: Dictionary = d.carriers
	var ks: Dictionary = d.contracts
	_readout(Rect2(a.position, Vector2(w, h)), "FREIGHT PAID, LAST 7 DAYS", cr(float(d.freight_cr.week)), change(float(d.freight_cr.change)), AMBER, d.series.freight_cr)
	_readout(Rect2(a.position + Vector2(w + gap, 0), Vector2(w, h)), "GOODS BOUGHT AND DELIVERED", cr(float(d.goods_cr.week)), change(float(d.goods_cr.change)), AMBER, d.series.goods_cr)
	_readout(Rect2(a.position + Vector2((w + gap) * 2.0, 0), Vector2(w, h)), "TONNES MOVED", tonnes(float(d.t.week)), change(float(d.t.change)), GOODS, d.series.t)
	var r4 := Rect2(a.position + Vector2((w + gap) * 3.0, 0), Vector2(w, h))
	_readout(r4, "SHIPS AT WORK", "%d of %d" % [int(cs.working), int(cs.total)], "%d under way loaded" % int(cs.loaded), GOODS, [])
	_text(r4.position + Vector2(16, 112), "%d jobs on the boards" % int(ks.open), 14, INK)
	_text(r4.position + Vector2(16, 134), "%d being hauled" % int(ks.moving), 14, INK)
	_text(r4.position + Vector2(16, 156), "carriers hold %s" % cr(float(cs.cash)), 13, DIM)
	# Running short, and prices.
	var top := a.position.y + h + 34.0
	var lw := a.size.x * 0.58
	_heading(Vector2(a.position.x, top), "RUNNING SHORT", lw)
	var y := top + 30.0
	var rows: Array = d.tight
	if rows.is_empty():
		_text(Vector2(a.position.x, y), "Every shelf in known space is stocked. Enjoy it; it won't last.", 14, DIM)
	for row in rows:
		if y > a.end.y - 30.0:
			break
		var st := String(row.state)
		var chip_col: Color = ALARM if st == "out" else (AMBER if st == "critical" else DIM)
		var chip := {"out": "OUT", "critical": "CRITICAL", "short": "SHORT"}[st] as String
		board.draw_rect(Rect2(a.position.x, y - 14, 74, 19), Color(chip_col, 0.18))
		_text(Vector2(a.position.x + 6, y), chip, 12, chip_col)
		_text(Vector2(a.position.x + 86, y), _fit("%s, %s" % [row.name, row.system_name], 15, lw - 86 - 160), 15, INK)
		var cover := "nothing left" if st == "out" else "%.1f days left" % float(row.cover_days)
		_text(Vector2(a.position.x + lw - 160, y), cover, 13, DIM, 92, HORIZONTAL_ALIGNMENT_RIGHT)
		_text(Vector2(a.position.x + lw - 64, y), "%+d%%" % roundi((float(row.price) - 1.0) * 100.0), 15, AMBER, 64, HORIZONTAL_ALIGNMENT_RIGHT)
		var goods: Array = row.goods
		var line := ", ".join(goods.slice(0, 3)).to_lower()
		if goods.size() > 3:
			line += " and %d more" % (goods.size() - 3)
		_text(Vector2(a.position.x + 86, y + 18), _fit(line, 13, lw - 86 - 70), 13, DIM)
		y += 44.0

	# Every system's prices against the going rate, dearest first.
	var px := a.position.x + lw + 30.0
	var pw := a.end.x - px
	_heading(Vector2(px, top), "PRICES AGAINST THE GOING RATE", pw)
	var ds := TradeData.days(Session.sim)
	var now: Dictionary = {}
	for i in range(ds.size() - 1, -1, -1):
		if not (ds[i].prices as Dictionary).is_empty():
			now = ds[i].prices
			break
	var then: Dictionary = ds[maxi(0, ds.size() - 8)].prices if not ds.is_empty() else {}
	var sids := now.keys()
	sids.sort_custom(func(x, z) -> bool: return float(now[x]) > float(now[z]))
	var here := Session.system_id()
	var rh := minf(22.0, (a.end.y - top - 30.0) / maxf(float(sids.size()), 1.0))
	var name_w := 112.0
	var mid := px + name_w + (pw - name_w - 56.0) * 0.5
	var half := (pw - name_w - 56.0) * 0.5
	board.draw_line(Vector2(mid, top + 16), Vector2(mid, top + 20 + rh * sids.size()), RULE, 1.0)
	y = top + 30.0
	for sid in sids:
		var v := float(now[sid])
		var col := YOU if String(sid) == here else INK
		_text(Vector2(px, y), _fit(TradeData.system_name(String(sid)), 13, name_w - 8), 13, col)
		var len := clampf((v - 1.0) / 0.6, -1.0, 1.0) * half
		board.draw_rect(Rect2(minf(mid, mid + len), y - 11, absf(len), rh * 0.55), AMBER if len > 0.0 else GOODS)
		var arrow := ""
		if then.has(sid):
			var dv := v - float(then[sid])
			arrow = "▲" if dv > 0.02 else ("▼" if dv < -0.02 else "")
		_text(Vector2(px + pw - 56, y), "%+d%% %s" % [roundi((v - 1.0) * 100.0), arrow], 12, DIM, 56, HORIZONTAL_ALIGNMENT_RIGHT)
		y += rh
	_text(Vector2(mid - half, y + 8), "cheap", 12, GOODS)
	_text(Vector2(mid + half - 30, y + 8), "dear", 12, AMBER)


func _draw_flows(a: Rect2) -> void:
	var d := _data
	var sp := StarMap.space_chart()
	var mw := a.size.x * 0.64
	var map := Rect2(a.position, Vector2(mw, a.size.y))
	board.draw_rect(map, PLATE)
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for sid in sp.systems:
		var p: Vector2 = sp.systems[sid].pos
		lo = Vector2(minf(lo.x, p.x), minf(lo.y, p.y))
		hi = Vector2(maxf(hi.x, p.x), maxf(hi.y, p.y))
	var span := Vector2(maxf(hi.x - lo.x, 1.0), maxf(hi.y - lo.y, 1.0))
	var scale := minf((map.size.x - 120.0) / span.x, (map.size.y - 80.0) / span.y)
	var centre := map.get_center()
	var mid := (lo + hi) * 0.5
	var at := func(p: Vector2) -> Vector2: return centre + (p - mid) * scale
	for r in sp.routes:   # the routes, faintly
		board.draw_line(at.call(sp.systems[r.a].pos), at.call(sp.systems[r.b].pos), Color(0.55, 0.65, 0.8, 0.14), 1.0)
	var lanes: Array = d.lanes
	var peak := 1.0
	for l in lanes:
		peak = maxf(peak, float(l.t))
	for l in lanes:   # the week's freight, A to B, offset to one side so both directions show
		if not sp.systems.has(l.a) or not sp.systems.has(l.b) or l.a == l.b:
			continue
		var p0: Vector2 = at.call(sp.systems[l.a].pos)
		var p1: Vector2 = at.call(sp.systems[l.b].pos)
		var dir := (p1 - p0).normalized()
		var off := Vector2(-dir.y, dir.x) * 3.0
		p0 += off
		p1 += off
		var mine := float(l.player_t) > 0.0
		var wgt := 1.5 + 7.0 * sqrt(float(l.t) / peak)
		var col := YOU if mine else GOODS
		board.draw_line(p0, p1, Color(col, 0.35), wgt)
		var n := 1 + int(5.0 * float(l.t) / peak)   # cargo flowing along it
		var len := p0.distance_to(p1)
		for k in n:
			var u := fmod(_t * 40.0 / maxf(len, 1.0) + float(k) / float(n), 1.0)
			board.draw_circle(p0.lerp(p1, u), 1.5 + wgt * 0.25, Color(col, 0.9))
	var sys: Dictionary = d.systems
	var here := Session.system_id()
	_labels.clear()
	for sid in sp.systems:
		var p: Vector2 = at.call(sp.systems[sid].pos)
		var s: Dictionary = sys.get(sid, {})
		var vol := float(s.get("in_t", 0.0)) + float(s.get("out_t", 0.0))
		var rad := 4.0 + 10.0 * sqrt(vol / maxf(peak * 2.0, 1.0))
		board.draw_circle(p, rad, Color(0.1, 0.12, 0.16))
		var net := float(s.get("out_t", 0.0)) - float(s.get("in_t", 0.0))   # exporters amber, importers blue
		board.draw_arc(p, rad, 0, TAU, 32, (AMBER if net > 0.0 else GOODS) if vol > 0.0 else DIM, 2.0)
		if String(sid) == here:
			board.draw_arc(p, rad + 6.0, 0, TAU, 40, YOU, 2.0)
		_label(p, rad, String(sp.systems[sid].name), YOU if String(sid) == here else INK)
	for s in d.ships:   # every ship, where it is right now
		if not sp.systems.has(s.a) or not sp.systems.has(s.b):
			continue
		var p: Vector2 = (at.call(sp.systems[s.a].pos) as Vector2).lerp(at.call(sp.systems[s.b].pos), float(s.progress))
		if s.a == s.b:
			continue   # in port: the system's circle is enough
		var col: Color = YOU if bool(s.player) else (AMBER if bool(s.loaded) else DIM)
		var q := 4.0 if bool(s.player) else 3.0
		board.draw_colored_polygon(PackedVector2Array([p + Vector2(0, -q), p + Vector2(q, 0), p + Vector2(0, q), p + Vector2(-q, 0)]), col)
	# Legend.
	var ly := map.end.y - 14.0
	var lx := map.position.x + 14.0
	for item in [[GOODS, "freight this week"], [YOU, "yours"], [AMBER, "ship, loaded"], [DIM, "ship, empty"]]:
		board.draw_circle(Vector2(lx + 5, ly - 4), 4.0, item[0])
		_text(Vector2(lx + 14, ly), item[1], 12, DIM)
		lx += _w(item[1], 12) + 34.0
	# The busiest lanes.
	var px := map.end.x + 24.0
	var pw := a.end.x - px
	_heading(Vector2(px, a.position.y + 14), "BUSIEST LANES, LAST %d DAYS" % maxi(int(d.days), 1), pw)
	var y := a.position.y + 44.0
	if lanes.is_empty():
		_text(Vector2(px, y), "Nothing's been delivered yet. Give it a day.", 14, DIM)
	for l in lanes:
		if y > a.end.y - 70.0:
			break
		var mine := float(l.player_t) > 0.0
		_text(Vector2(px, y), _fit("%s → %s" % [TradeData.system_name(String(l.a)), TradeData.system_name(String(l.b))], 15, pw - 90), 15, YOU if mine else INK)
		_text(Vector2(px + pw - 86, y), tonnes(float(l.t)), 14, GOODS, 86, HORIZONTAL_ALIGNMENT_RIGHT)
		_text(Vector2(px, y + 18), _fit("%s, mostly %s%s" % [cr(float(l.cr)), String(l.top).to_lower(), "; you carried %s" % tonnes(float(l.player_t)) if mine else ""], 12, pw), 12, DIM)
		y += 44.0
	var moving := 0
	var loaded := 0
	for s in d.ships:
		if s.a != s.b:
			moving += 1
			if bool(s.loaded):
				loaded += 1
	_text(Vector2(px, a.end.y - 34), "%d ships between systems right now, %d of them loaded." % [moving, loaded], 13, DIM)
	_text(Vector2(px, a.end.y - 14), "Rings: amber sends out more than it takes in, blue the reverse.", 12, DIM)


var _labels: Array[Rect2] = []   ## system names already placed on the flows map


## A system's name beside its circle: right, left, above or below, whichever doesn't overprint.
func _label(p: Vector2, rad: float, text: String, col: Color) -> void:
	var w := _w(text, 13)
	var spots := [p + Vector2(rad + 5, 4), p + Vector2(-rad - 5 - w, 4), p + Vector2(-w * 0.5, -rad - 6), p + Vector2(-w * 0.5, rad + 15)]
	var at: Vector2 = spots[0]
	for sp in spots:
		var box := Rect2(sp + Vector2(-2, -13), Vector2(w + 4, 17))
		if not _labels.any(func(r: Rect2) -> bool: return r.intersects(box)):
			at = sp
			break
	_labels.append(Rect2(at + Vector2(-2, -13), Vector2(w + 4, 17)))
	_text(at, text, 13, col)


func _draw_companies(a: Rect2) -> void:
	var rows: Array = _data.rows
	var cols := [["", 28.0], ["COMPANY", 0.0], ["SHIPS", 90.0], ["AT WORK", 90.0], ["FREIGHT EARNED, 30 DAYS", 330.0], ["CASH", 130.0]]
	var fixed := 0.0
	for c in cols:
		fixed += float(c[1])
	var name_w := a.size.x - fixed
	var xs := []
	var x := a.position.x
	for c in cols:
		xs.append(x)
		x += float(c[1]) if float(c[1]) > 0.0 else name_w
	var y := a.position.y + 14.0
	for i in cols.size():
		_text(Vector2(xs[i], y), String(cols[i][0]), 12, DIM)
	board.draw_line(Vector2(a.position.x, y + 8), Vector2(a.end.x, y + 8), RULE, 1.0)
	var peak := 0.0
	for r in rows:
		peak = maxf(peak, float(r.revenue_30))
	var rh := minf(30.0, (a.size.y - 40.0) / maxf(float(rows.size()), 1.0))
	y += 8.0 + rh
	for r in rows:
		var you := bool(r.player)
		if you:
			board.draw_rect(Rect2(a.position.x - 8, y - rh + 7, a.size.x + 16, rh - 2), Color(YOU, 0.08))
		var col := YOU if you else INK
		_text(Vector2(xs[0], y), str(int(r.rank)), 14, DIM)
		_text(Vector2(xs[1], y), _fit(String(r.name) if not you else "You: %s" % Session.ship_label(), 15, name_w - 12), 15, col)
		_text(Vector2(xs[2], y), str(int(r.ships)), 14, col)
		_text(Vector2(xs[3], y), str(int(r.working)), 14, col)
		var bw := 200.0 * (float(r.revenue_30) / peak if peak > 0.0 else 0.0)
		board.draw_rect(Rect2(xs[4], y - 11, maxf(bw, 1.0), 10), YOU if you else AMBER)
		_text(Vector2(xs[4] + 210, y), "%s  %d%%" % [cr(float(r.revenue_30)), roundi(float(r.share) * 100.0)], 13, col)
		_text(Vector2(xs[5], y), cr(float(r.cash)), 14, col, 130, HORIZONTAL_ALIGNMENT_RIGHT)
		y += rh


func _stat(p: Vector2, value: String, label: String, col := INK) -> void:
	_text(p, value, 26, col)
	_text(p + Vector2(0, 20), label, 13, DIM)


func _draw_you(a: Rect2) -> void:
	var d := _data
	var lw := a.size.x * 0.36
	var x := a.position.x
	var y := a.position.y + 30.0
	if float(d.t) <= 0.0 and float(d.salvage_cr) <= 0.0:
		_text(Vector2(x, y), "The economy hasn't noticed you yet.", 20, INK)
		_text(Vector2(x, y + 26), "Take a job at the freight office and give it something to notice.", 14, DIM)
		y += 70.0
	_stat(Vector2(x, y + 20), tonnes(float(d.t)), "delivered: %s between systems, %s in-system" % [tonnes(float(d.interstellar_t)), tonnes(float(d.local_t))], GOODS)
	_stat(Vector2(x, y + 82), cr(float(d.cr)), "earned hauling, over %d deliveries" % int(d.deliveries), AMBER)
	_stat(Vector2(x, y + 144), "%.1f%%" % (float(d.share_30) * 100.0), "of all the freight paid in known space, last 30 days", YOU)
	_stat(Vector2(x, y + 206), "%d of %d" % [int(d.rank), int(d.companies)], "among the carrier companies, by freight earned")
	_stat(Vector2(x, y + 268), str(int(d.relieved)), "deliveries that reached a shelf running short", ALARM if int(d.relieved) > 0 else INK)
	_stat(Vector2(x, y + 330), cr(float(d.salvage_cr)), "salvage and finds sold")
	# Earnings, day by day.
	var cx := x + lw + 20.0
	var cw := a.size.x * 0.3
	_heading(Vector2(cx, a.position.y + 14), "YOUR TAKINGS, DAY BY DAY", cw)
	var series: Array = d.series
	var chart := Rect2(cx, a.position.y + 40, cw, 180)
	board.draw_rect(chart, PLATE)
	var peak := 0.0
	for v in series:
		peak = maxf(peak, float(v))
	if series.size() > 0:
		var bw := chart.size.x / float(series.size())
		for i in series.size():
			var hgt := (chart.size.y - 16.0) * (float(series[i]) / peak if peak > 0.0 else 0.0)
			board.draw_rect(Rect2(chart.position.x + i * bw + 1, chart.end.y - 4 - hgt, maxf(bw - 2.0, 1.0), hgt), YOU if i == series.size() - 1 else Color(YOU, 0.55))
	_text(Vector2(cx, chart.end.y + 18), "%d days, best %s, %s in all" % [series.size(), cr(peak), cr(float(d.cr_30))], 12, DIM)
	_heading(Vector2(cx, chart.end.y + 54), "WHERE YOU'VE DELIVERED  (%d SYSTEMS)" % int(d.system_count), cw)
	var yy := chart.end.y + 82.0
	for s in d.systems:
		_text(Vector2(cx, yy), String(s.name), 14, INK)
		_text(Vector2(cx + cw - 90, yy), tonnes(float(s.t)), 14, GOODS, 90, HORIZONTAL_ALIGNMENT_RIGHT)
		yy += 22.0
	# Who you've supplied.
	var fx := cx + cw + 30.0
	var fw := a.end.x - fx
	_heading(Vector2(fx, a.position.y + 14), "WHO YOU'VE SUPPLIED  (%d)" % int(d.facility_count), fw)
	yy = a.position.y + 44.0
	if (d.facilities as Array).is_empty():
		_text(Vector2(fx, yy), _fit("Nobody yet. Interstellar freight and", 13, fw), 13, DIM)
		_text(Vector2(fx, yy + 18), _fit("salvage sold in port go on their shelves.", 13, fw), 13, DIM)
	for f in d.facilities:
		_text(Vector2(fx, yy), _fit(String(f.name), 14, fw - 80), 14, INK)
		_text(Vector2(fx + fw - 80, yy), tonnes(float(f.t)), 13, GOODS, 80, HORIZONTAL_ALIGNMENT_RIGHT)
		_text(Vector2(fx, yy + 17), String(f.system_name), 12, DIM)
		yy += 42.0


const STAGE_COL := [Color8(120, 110, 104), Color8(196, 120, 72), Color8(214, 168, 80), Color8(170, 196, 120), Color(0.35, 0.85, 1.0), Color8(230, 226, 214)]


func _arrow(tr: float) -> String:
	if tr > 0.03:
		return "▲"
	if tr < -0.03:
		return "▼"
	return "·"


func _arrow_col(tr: float) -> Color:
	return YOU if tr > 0.03 else (ALARM if tr < -0.03 else DIM)


## Frontier growth: this system's sites on the left with a bar from abandoned to core (its canon size
## marked), what changed lately in the middle, every system on the right.
func _draw_growth(a: Rect2) -> void:
	var d := _data
	if bool(d.get("off", false)):
		_text(a.position + Vector2(0, 30), "Nothing grows here. This world isn't keeping track.", 20, INK)
		return
	var lw := a.size.x * 0.46
	var x := a.position.x
	_heading(Vector2(x, a.position.y + 14), "%s  ·  %s %s" % [String(d.system_name).to_upper(), Development.stage_name(int(d.system_stage)).to_upper(), _arrow(float(d.system_trend))], lw)
	var y := a.position.y + 46.0
	var bar_x := x + lw * 0.42
	var bar_w := lw * 0.3
	for r in d.sites:
		var col := YOU if bool(r.here) else INK
		_text(Vector2(x, y), _fit(String(r.name), 15, lw * 0.4), 15, col)
		board.draw_rect(Rect2(bar_x, y - 11, bar_w, 9), PLATE)
		var f := clampf(float(r.score) / 5.5, 0.0, 1.0)
		board.draw_rect(Rect2(bar_x, y - 11, maxf(2.0, bar_w * f), 9), STAGE_COL[int(r.stage)])
		var cx := bar_x + bar_w * clampf(float(r.canon) / 5.5, 0.0, 1.0)
		board.draw_line(Vector2(cx, y - 14), Vector2(cx, y + 1), DIM, 1.0)
		_text(Vector2(bar_x + bar_w + 10, y), String(r.stage_name), 13, STAGE_COL[int(r.stage)])
		_text(Vector2(x + lw - 16, y), _arrow(float(r.trend)), 15, _arrow_col(float(r.trend)))
		var note := String(r.why)
		if float(r.you_share) >= 0.05:
			note += ";  you bring %d%% of it" % roundi(float(r.you_share) * 100.0)
		_text(Vector2(x, y + 17), _fit(note, 12, lw - 8), 12, DIM)
		y += 44.0
	_text(Vector2(x, y + 6), _fit("Bars run from abandoned to core. The tick is where each one started.", 12, lw), 12, DIM)
	# What changed.
	var mx := x + lw + 24.0
	var mw := a.size.x * 0.27
	_heading(Vector2(mx, a.position.y + 14), "CHANGES, LAST 30 DAYS", mw)
	var yy := a.position.y + 46.0
	if (d.changes as Array).is_empty():
		_text(Vector2(mx, yy), _fit("Nothing's changed size. Give it time.", 13, mw), 13, DIM)
	for c in (d.changes as Array).slice(0, 12):
		var verb := "grew to %s" % Development.stage_name(int(c.to)) if bool(c.up) else ("was abandoned" if int(c.to) == 0 else "shrank to %s" % Development.stage_name(int(c.to)))
		if int(c.from) == 0:
			verb = "was resettled"
		_text(Vector2(mx, yy), _fit(String(c.name), 14, mw), 14, YOU if bool(c.up) else ALARM)
		_text(Vector2(mx, yy + 17), _fit("%s, %s" % [verb, "today" if int(c.ago) == 0 else "%d day%s ago" % [int(c.ago), "" if int(c.ago) == 1 else "s"]], 12, mw), 12, DIM)
		yy += 38.0
	# Every system.
	var sx := mx + mw + 24.0
	var sw := a.end.x - sx
	_heading(Vector2(sx, a.position.y + 14), "KNOWN SPACE  ·  SPACE WEATHER", sw)
	yy = a.position.y + 44.0
	var rh := minf(24.0, (a.size.y - 60.0) / maxf(1.0, float((d.systems as Array).size())))
	for r in d.systems:
		_text(Vector2(sx, yy), _fit(String(r.name), 14, sw * 0.5), 14, YOU if bool(r.here) else INK)
		if String(r.get("storm", "")) != "":
			_text(Vector2(sx + sw * 0.52, yy), _fit(String(r.storm).to_upper(), 12, sw * 0.38), 12, ALARM if String(r.storm) == "storm" else AMBER)
		else:
			_text(Vector2(sx + sw * 0.52, yy), _fit(String(r.stage_name), 13, sw * 0.38), 13, STAGE_COL[int(r.stage)])
		_text(Vector2(sx + sw - 14, yy), _arrow(float(r.trend)), 14, _arrow_col(float(r.trend)))
		yy += rh
