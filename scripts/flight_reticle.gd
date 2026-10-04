class_name FlightReticle
extends Control
## Flight markers drawn over the chase view: where the nose points (a small wing-and-dot "boresight"),
## which way the ship is moving (prograde: a ring with three ticks) and the opposite way (retrograde:
## a ring with a cross). Positions are screen points; the flight scene fills them in each frame.

var nose := Vector2.INF
var prograde := Vector2.INF
var retrograde := Vector2.INF
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
	if retrograde != Vector2.INF:
		var r := retrograde
		draw_arc(r, 9.0, 0.0, TAU, 24, move_colour, 2.0, true)
		draw_line(r + Vector2(-6, -6), r + Vector2(6, 6), move_colour, 2.0, true)
		draw_line(r + Vector2(-6, 6), r + Vector2(6, -6), move_colour, 2.0, true)
