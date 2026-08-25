class_name ACAJobUIStyle
extends RefCounted
## The Job UI's visual language, in one place.
##
## Matched by eye to the Business Town HUD (charcoal-green panels, rounded chips,
## forest green accent) so the Job Board sits over the live 3D town without
## looking like a different game - but defined here, in the portable folder, so
## nothing is loaded from the Town project at runtime. No theme file, no
## imported fonts, no external textures: plain Godot controls only.
##
## THE BOARD IS DARK AND THE OFFERS ON IT ARE PAPER. That is the whole idea of
## the screen: a job the player can take is a printed work order, so it gets a
## warm cream sheet with charcoal ink on it and one orange control, sitting on
## the same charcoal-green surface as every other panel in the game. It is the
## `PAPER` half of the palette in `res://UI/Theme/ui_theme.gd`, kept as its own
## constants here because this folder is deliberately portable and loads nothing
## from outside itself.

const INK := Color(0.957, 0.929, 0.874)
const INK_DIM := Color(0.769, 0.745, 0.686)
const INK_FAINT := Color(0.588, 0.576, 0.522)
const ACCENT := Color(0.216, 0.427, 0.267)
const ACCENT_BRIGHT := Color(0.545, 0.780, 0.478)
const WARN := Color(0.851, 0.639, 0.267)
const URGENT := Color(0.784, 0.361, 0.259)

const PANEL_BG := Color(0.114, 0.133, 0.114, 0.940)
const PANEL_BG2 := Color(0.153, 0.176, 0.149, 0.960)
const CARD_BG := Color(0.098, 0.118, 0.102, 0.920)
const CHIP_BG := Color(0.196, 0.224, 0.188, 0.900)
const BUTTON_BG := Color(0.227, 0.259, 0.216)
const HAIRLINE := Color(0.960, 0.933, 0.882, 0.100)
## THE mower-orange accent. One per card: the button that takes the contract.
const ORANGE := Color(0.851, 0.478, 0.169)

# --------------------------------------------------------------------- paper
## The work-order surface, and the ink that goes on it. Anything drawn on
## `PAPER_BG` must use these; `INK` on cream is unreadable and is meant to be.
const PAPER_BG := Color(0.949, 0.925, 0.867)
const PAPER_BG2 := Color(0.980, 0.965, 0.925)
const PAPER_INK := Color(0.157, 0.180, 0.153)
const PAPER_INK_DIM := Color(0.353, 0.396, 0.337)
const PAPER_INK_FAINT := Color(0.502, 0.537, 0.478)
const PAPER_RULE := Color(0.157, 0.180, 0.153, 0.16)
## Money on a cream sheet has to be a DARK green; the bright one used on the
## dark panels disappears against paper.
const PAPER_MONEY := Color(0.157, 0.396, 0.216)

## Partial alpha on purpose: the live 3D town must stay visible behind the
## board when it is used as a Town modal.
const DIM := Color(0.047, 0.059, 0.047, 0.550)

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
	var fg := Color(0.965, 0.945, 0.898) if primary else INK
	b.add_theme_stylebox_override("normal", stylebox(base, 8))
	b.add_theme_stylebox_override("hover", stylebox(base.lightened(0.12), 8))
	b.add_theme_stylebox_override("pressed", stylebox(base.darkened(0.15), 8))
	b.add_theme_stylebox_override("focus", stylebox(Color(0, 0, 0, 0), 8, 2.0, INK_DIM))
	b.add_theme_stylebox_override("disabled", stylebox(Color(0.184, 0.204, 0.176, 0.800), 8))
	b.add_theme_color_override("font_color", fg)
	b.add_theme_color_override("font_hover_color", fg)
	b.add_theme_color_override("font_pressed_color", fg)
	b.add_theme_color_override("font_focus_color", fg)
	b.add_theme_color_override("font_disabled_color", INK_FAINT)
	return b


## THE ONE CONTROL ON A WORK ORDER. Mower orange on cream, with charcoal text,
## and a forest-green focus ring so a keyboard is a first-class way to take a
## contract. A secondary paper button is a plain outline: on a printed sheet the
## thing you press should be the only thing that is filled in.
static func style_paper_button(b: Button, primary: bool, height: float = 36.0,
		font_size: int = 14) -> Button:
	b.custom_minimum_size = Vector2(0, height)
	b.add_theme_font_size_override("font_size", font_size)
	var base := ORANGE if primary else Color(0.157, 0.180, 0.153, 0.06)
	var fg := PAPER_INK
	b.add_theme_stylebox_override("normal",
		stylebox(base, 8, 0.0 if primary else 1.0, PAPER_RULE))
	b.add_theme_stylebox_override("hover",
		stylebox(base.lightened(0.10), 8, 0.0 if primary else 1.0, PAPER_RULE))
	b.add_theme_stylebox_override("pressed", stylebox(base.darkened(0.15), 8))
	b.add_theme_stylebox_override("focus",
		stylebox(Color(0, 0, 0, 0), 8, 3.0, ACCENT))
	b.add_theme_stylebox_override("disabled",
		stylebox(Color(0.157, 0.180, 0.153, 0.08), 8))
	for key in ["font_color", "font_hover_color", "font_pressed_color",
			"font_focus_color"]:
		b.add_theme_color_override(key, fg)
	b.add_theme_color_override("font_disabled_color", PAPER_INK_FAINT)
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
	b.add_theme_stylebox_override("normal", stylebox(Color(0.153, 0.176, 0.149, 0.000), 8))
	b.add_theme_stylebox_override("hover", stylebox(Color(0.196, 0.224, 0.188, 0.550), 8))
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
		b.add_theme_color_override("font_color", Color(0.965, 0.945, 0.898))
		b.add_theme_color_override("font_hover_color", Color(0.965, 0.945, 0.898))
		b.add_theme_color_override("font_focus_color", Color(0.965, 0.945, 0.898))
	else:
		b.add_theme_stylebox_override("normal", stylebox(Color(0.153, 0.176, 0.149, 0.000), 8))
		b.add_theme_stylebox_override("hover", stylebox(Color(0.196, 0.224, 0.188, 0.550), 8))
		b.add_theme_color_override("font_color", INK_DIM)
		b.add_theme_color_override("font_hover_color", INK)
		b.add_theme_color_override("font_focus_color", INK_DIM)


## Colour for an offer countdown: calm, then amber, then red as it runs out.
## Urgency ON PAPER. The dark-panel amber and salmon are both too light to read
## against cream, so the paper variants are darker rather than the same colours
## reused - and the card ALSO changes its wording as an offer runs down, so the
## information does not depend on anyone telling these three apart.
static func urgency_colour(minutes_left: float) -> Color:
	if minutes_left <= 30.0:
		return Color(0.639, 0.239, 0.145)
	if minutes_left <= 90.0:
		return Color(0.596, 0.404, 0.106)
	return PAPER_INK_DIM
