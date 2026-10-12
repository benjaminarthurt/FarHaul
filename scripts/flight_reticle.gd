class_name FlightReticle
extends Control
## Flight markers drawn over the chase view: where the nose points (a small wing-and-dot "boresight"),
## which way the ship is moving (prograde: a ring with three ticks, labelled TRAVEL) and the opposite
## way (retrograde: a ring with a cross, labelled REVERSE). When the target or the direction of travel
## is off screen, an arrow at the edge of the screen points the way to turn, with a label. Positions
## are screen points; the flight scene fills them in each frame.

var nose := Vector2.INF
var prograde := Vector2.INF
var retrograde := Vector2.INF
var target_edge := Vector2.INF    ## where the off-screen target arrow sits, or INF when it is on screen
var target_edge_dir := Vector2.ZERO
var target_text := ""
var target_colour := Color(1.0, 0.62, 0.15, 0.95)
var travel_edge := Vector2.INF
var travel_edge_dir := Vector2.ZERO
var colour := Color(0.55, 1.0, 0.75, 0.9)
var move_colour := Color(1.0, 0.82, 0.35, 0.9)


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)


func _draw() -> void:
	if nose != Vector2.INF:
		var c := nose
		draw_arc(c, 5.0, 0.0, TAU, 16, colour, 2.0, true)
		draw_line(c + Vector2(-26, 0), c + Vector2(-9, 0), colour, 2.0, true)
		draw_line(c + Vector2(9, 0), c + Vector2(26, 0), colour, 2.0, true)
		draw_line(c + Vector2(-26, 0), c + Vector2(-26, 7), colour, 2.0, true)
		draw_line(c + Vector2(26, 0), c + Vector2(26, 7), colour, 2.0, true)
	if prograde != Vector2.INF:
		var p := prograde
		draw_arc(p, 9.0, 0.0, TAU, 24, move_colour, 2.0, true)
		draw_line(p + Vector2(0, -9), p + Vector2(0, -17), move_colour, 2.0, true)
		draw_line(p + Vector2(-9, 0), p + Vector2(-17, 0), move_colour, 2.0, true)
		draw_line(p + Vector2(9, 0), p + Vector2(17, 0), move_colour, 2.0, true)
		draw_circle(p, 2.0, move_colour)
		_label(p + Vector2(0, 32), "TRAVEL", move_colour)
	if retrograde != Vector2.INF:
		var r := retrograde
		draw_arc(r, 9.0, 0.0, TAU, 24, move_colour, 2.0, true)
		draw_line(r + Vector2(-6, -6), r + Vector2(6, 6), move_colour, 2.0, true)
		draw_line(r + Vector2(-6, 6), r + Vector2(6, -6), move_colour, 2.0, true)
		_label(r + Vector2(0, 26), "REVERSE", move_colour)
	if target_edge != Vector2.INF:
		_arrow(target_edge, target_edge_dir, target_colour, 16.0)
		_label(_beside(target_edge, target_edge_dir, 16.0), target_text, target_colour, 15)
	if travel_edge != Vector2.INF:
		_arrow(travel_edge, travel_edge_dir, move_colour, 11.0)
		_label(_beside(travel_edge, travel_edge_dir, 11.0), "TRAVEL", move_colour)


## Where an arrow's label goes: below it, or above it when the arrow points down.
func _beside(at: Vector2, dir: Vector2, size: float) -> Vector2:
	return at + (Vector2(0, -size - 8.0) if dir.y > 0.5 else Vector2(0, size + 18.0))


## A filled arrowhead at `at` pointing along `dir` (screen space).
func _arrow(at: Vector2, dir: Vector2, col: Color, size: float) -> void:
	var side := Vector2(-dir.y, dir.x)
	draw_colored_polygon(PackedVector2Array([at + dir * size, at - dir * size * 0.6 + side * size * 0.8, at - dir * size * 0.6 - side * size * 0.8]), col)


## A small centred label with a dark outline so it reads over stars and stations.
func _label(at: Vector2, text: String, col: Color, size := 13) -> void:
	if text == "":
		return
	var font := ThemeDB.fallback_font
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	draw_string_outline(font, at - Vector2(w * 0.5, 0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, 4, Color(0, 0, 0, 0.8))
	draw_string(font, at - Vector2(w * 0.5, 0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)
