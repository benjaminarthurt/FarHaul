class_name Brand
extends RefCounted
## Far Haul's identity in one place: name, tagline, colours and shared helpers.
## Source of truth is docs/far-haul-concept.md and docs/design-reference/art-direction.md.
## The same palette is used by tools/make_brand_assets.py.

const NAME := "FAR HAUL"
const TAGLINE := "BUILD YOUR SHIP.  HAUL THE FREIGHT.  PUSH THE FRONTIER."
const STAGE := "Ship builder prototype"  # shown on the title screen until the game grows up

const STEEL_DARK := Color8(13, 16, 21)
const STEEL := Color8(28, 33, 41)
const STEEL_LIGHT := Color8(48, 56, 68)
const OFFWHITE := Color8(230, 226, 214)
const AMBER := Color8(242, 167, 27)  # hazard markings, the one accent colour
const MUTED := Color8(140, 146, 156)

const LOGO := "res://assets/brand/logo.png"
const WORDMARK := "res://assets/brand/wordmark.png"
const SPLASH := "res://assets/brand/boot_splash.png"
const INTRO_VIDEO := "res://assets/video/intro.ogv"
const THEME_MUSIC := "res://assets/audio/music/far_haul_theme.mp3"


static func version() -> String:
	return str(ProjectSettings.get_setting("application/config/version", "0.0.0"))


## Freight container code in the style of the art-direction doc (FHCU 882193-4).
## `seed_value` makes it stable, so the same box always reads the same.
static func container_code(seed_value: int) -> String:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var serial := rng.randi_range(100000, 999999)
	var check := (serial * 7 + 3) % 10
	return "FHCU %d-%d" % [serial, check]


## Flat industrial button look: dark plate, amber bar on the left when hovered or focused.
static func style_button(b: Button, size: int = 22) -> void:
	b.add_theme_color_override("font_color", OFFWHITE)
	b.add_theme_color_override("font_hover_color", AMBER)
	b.add_theme_color_override("font_focus_color", AMBER)
	b.add_theme_color_override("font_pressed_color", AMBER)
	b.add_theme_color_override("font_disabled_color", Color(MUTED, 0.5))
	b.add_theme_font_size_override("font_size", size)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.focus_mode = Control.FOCUS_ALL
	b.add_theme_stylebox_override("normal", _plate(STEEL, 0))
	b.add_theme_stylebox_override("disabled", _plate(STEEL_DARK, 0))
	b.add_theme_stylebox_override("hover", _plate(STEEL_LIGHT, 6))
	b.add_theme_stylebox_override("focus", _plate(STEEL_LIGHT, 6))
	b.add_theme_stylebox_override("pressed", _plate(STEEL_LIGHT, 6))


static func _plate(fill: Color, bar: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(fill, 0.92)
	s.border_color = AMBER
	s.border_width_left = bar
	s.content_margin_left = 22
	s.content_margin_right = 22
	s.content_margin_top = 11
	s.content_margin_bottom = 11
	return s


## Dark steel panel used by the menu screens.
static func panel_box() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(STEEL_DARK, 0.94)
	s.border_color = STEEL_LIGHT
	s.set_border_width_all(2)
	s.border_width_top = 4
	s.border_color = AMBER
	s.content_margin_left = 26
	s.content_margin_right = 26
	s.content_margin_top = 18
	s.content_margin_bottom = 18
	return s


static func heading(text: String, size: int = 14) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", AMBER)
	return l


static func note(text: String, size: int = 13) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", MUTED)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


## A button that stays selected, for choosing one option from a group.
static func toggle(text: String, group: ButtonGroup, size: int = 16) -> Button:
	var b := Button.new()
	b.text = text
	b.toggle_mode = true
	b.button_group = group
	style_button(b, size)
	b.add_theme_stylebox_override("normal", _plate(STEEL, 0))
	b.add_theme_stylebox_override("pressed", _plate(STEEL_LIGHT, 6))
	b.add_theme_color_override("font_pressed_color", AMBER)
	b.add_theme_color_override("font_hover_pressed_color", AMBER)
	b.add_theme_stylebox_override("hover_pressed", _plate(STEEL_LIGHT, 6))
	return b
