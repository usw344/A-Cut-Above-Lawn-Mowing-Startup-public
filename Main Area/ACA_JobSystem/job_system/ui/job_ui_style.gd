class_name ACAJobUIStyle
extends RefCounted
## The Job UI's visual language, in one place.
##
## Matched by eye to the Business Town HUD (dark slate panels, rounded chips,
## the same green accent) so the Job Board sits over the live 3D town without
## looking like a different game - but defined here, in the portable folder, so
## nothing is loaded from the Town project at runtime. No theme file, no
## imported fonts, no external textures: plain Godot controls only.

const INK := Color(0.937, 0.949, 0.937)
const INK_DIM := Color(0.678, 0.714, 0.729)
const INK_FAINT := Color(0.478, 0.529, 0.545)
const ACCENT := Color(0.420, 0.686, 0.353)
const ACCENT_BRIGHT := Color(0.635, 0.855, 0.545)
const WARN := Color(0.855, 0.647, 0.310)
const URGENT := Color(0.878, 0.482, 0.373)

const PANEL_BG := Color(0.118, 0.145, 0.161, 0.94)
const PANEL_BG2 := Color(0.153, 0.184, 0.196, 0.96)
const CARD_BG := Color(0.106, 0.129, 0.145, 0.92)
const CHIP_BG := Color(0.208, 0.251, 0.259, 0.9)
const BUTTON_BG := Color(0.235, 0.278, 0.294)
const HAIRLINE := Color(1, 1, 1, 0.08)

## Partial alpha on purpose: the live 3D town must stay visible behind the
## board when it is used as a Town modal.
const DIM := Color(0.043, 0.059, 0.067, 0.55)

## Leaves the host's 58 px top information bar uncovered.
const TOP_BAR_HEIGHT := 58.0


static func stylebox(bg: Color, radius: float = 10.0, border: float = 0.0,
		border_colour: Color = HAIRLINE, margin_h: float = 14.0,
		margin_v: float = 8.0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.corner_radius_top_left = int(radius)
	s.corner_radius_top_right = int(radius)
	s.corner_radius_bottom_left = int(radius)
	s.corner_radius_bottom_right = int(radius)
	if border > 0.0:
		s.border_width_left = int(border)
		s.border_width_right = int(border)
		s.border_width_top = int(border)
		s.border_width_bottom = int(border)
		s.border_color = border_colour
	s.content_margin_left = margin_h
	s.content_margin_right = margin_h
	s.content_margin_top = margin_v
	s.content_margin_bottom = margin_v
	return s


static func label(parent: Node, node_name: String, text: String, size: int,
		colour: Color, wrap: bool = false) -> Label:
	var l := Label.new()
	l.name = node_name
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", colour)
	if wrap:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(l)
	return l


static func style_button(b: Button, primary: bool, height: float = 36.0,
		font_size: int = 14) -> Button:
	b.custom_minimum_size = Vector2(0, height)
	b.add_theme_font_size_override("font_size", font_size)
	var base := ACCENT if primary else BUTTON_BG
	var fg := Color(0.075, 0.114, 0.086) if primary else INK
	b.add_theme_stylebox_override("normal", stylebox(base, 8))
	b.add_theme_stylebox_override("hover", stylebox(base.lightened(0.12), 8))
	b.add_theme_stylebox_override("pressed", stylebox(base.darkened(0.15), 8))
	b.add_theme_stylebox_override("focus", stylebox(Color(0, 0, 0, 0), 8, 2.0, INK_DIM))
	b.add_theme_stylebox_override("disabled", stylebox(Color(0.192, 0.216, 0.227, 0.8), 8))
	b.add_theme_color_override("font_color", fg)
	b.add_theme_color_override("font_hover_color", fg)
	b.add_theme_color_override("font_pressed_color", fg)
	b.add_theme_color_override("font_focus_color", fg)
	b.add_theme_color_override("font_disabled_color", INK_FAINT)
	return b


static func button(parent: Node, node_name: String, text: String, primary: bool,
		height: float = 36.0, font_size: int = 14) -> Button:
	var b := Button.new()
	b.name = node_name
	b.text = text
	parent.add_child(b)
	return style_button(b, primary, height, font_size)


## Tab selector: a toggle button that reads as a chip rather than a raw button.
static func style_tab(b: Button) -> Button:
	b.toggle_mode = true
	b.custom_minimum_size = Vector2(126, 34)
	b.add_theme_font_size_override("font_size", 13)
	b.add_theme_stylebox_override("normal", stylebox(Color(0.145, 0.176, 0.192, 0.0), 8))
	b.add_theme_stylebox_override("hover", stylebox(Color(0.208, 0.251, 0.259, 0.55), 8))
	b.add_theme_stylebox_override("pressed", stylebox(CHIP_BG, 8))
	b.add_theme_stylebox_override("focus", stylebox(Color(0, 0, 0, 0), 8))
	var on := stylebox(ACCENT, 8)
	b.add_theme_stylebox_override("hover_pressed", on)
	b.add_theme_color_override("font_color", INK_DIM)
	b.add_theme_color_override("font_hover_color", INK)
	b.add_theme_color_override("font_pressed_color", INK)
	b.add_theme_color_override("font_focus_color", INK_DIM)
	return b


## Applied at runtime by job_board.gd when the selected tab changes: the chip
## fills with the accent colour and the text flips to the dark ink.
static func set_tab_selected(b: Button, selected: bool) -> void:
	if selected:
		b.add_theme_stylebox_override("normal", stylebox(ACCENT, 8))
		b.add_theme_stylebox_override("hover", stylebox(ACCENT.lightened(0.1), 8))
		b.add_theme_color_override("font_color", Color(0.075, 0.114, 0.086))
		b.add_theme_color_override("font_hover_color", Color(0.075, 0.114, 0.086))
		b.add_theme_color_override("font_focus_color", Color(0.075, 0.114, 0.086))
	else:
		b.add_theme_stylebox_override("normal", stylebox(Color(0.145, 0.176, 0.192, 0.0), 8))
		b.add_theme_stylebox_override("hover", stylebox(Color(0.208, 0.251, 0.259, 0.55), 8))
		b.add_theme_color_override("font_color", INK_DIM)
		b.add_theme_color_override("font_hover_color", INK)
		b.add_theme_color_override("font_focus_color", INK_DIM)


## Colour for an offer countdown: calm, then amber, then red as it runs out.
static func urgency_colour(minutes_left: float) -> Color:
	if minutes_left <= 30.0:
		return URGENT
	if minutes_left <= 90.0:
		return WARN
	return INK_DIM
