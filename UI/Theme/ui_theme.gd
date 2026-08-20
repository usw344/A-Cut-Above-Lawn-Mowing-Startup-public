extends RefCounted
class_name UITheme

# ============================================================
# PUBLIC API
# ============================================================
#
# The single place where the UI palette, corner radii and type scale
# are defined. Every component in res://UI/ reads from here.
#
# Constants (read directly, e.g. UITheme.ACCENT):
#
#   Text        INK, INK_DIM, INK_FAINT, INK_ON_ACCENT
#   Accent      ACCENT, ACCENT_BRIGHT, WARN, URGENT, MONEY
#   Surfaces    PANEL_BG, PANEL_BG2, CARD_BG, CHIP_BG, BUTTON_BG,
#               TRACK_BG, HAIRLINE
#               PANEL_SOLID, PANEL_SOLID2 - opaque, for stacking menus
#   Scrims      SCRIM_LIGHT (over gameplay), SCRIM_HEAVY (over menus)
#   Radii       RADIUS_PANEL / CARD / CHIP / BUTTON / BAR
#   Type scale  FONT_DISPLAY / TITLE / HEADING / SUBHEAD / BODY /
#               LABEL / META / MICRO
#   Timing      FADE_FAST, FADE, FADE_SLOW, SLIDE
#
# Static helpers:
#
#   stylebox(bg, radius, border, border_colour, margin_h, margin_v) -> StyleBoxFlat
#   label(parent, node_name, text, size, colour, wrap) -> Label
#   style_button(button, primary, height, font_size) -> Button
#   style_danger_button(button, height, font_size) -> Button
#   style_progress(bar, fill_colour) -> ProgressBar
#   format_money(amount) -> String        # 1234 -> "$1,234"
#   format_clock(seconds) -> String       # 522.0 -> "08:42"
#   percent_text(value_0_to_1) -> String  # 0.723 -> "72%"
#
# ============================================================
# SCENE / RESOURCE REFERENCES
# ============================================================
#
# None. This script preloads nothing and has no dependencies.
#
# The generated Theme resource that ships alongside it is:
#
#   res://UI/Theme/Game UI.theme.tres
#
# ...which every component scene assigns to its root node theme
# property. If the UI folder moves after copying, that path is the one
# to re-point; it appears as an ext_resource in each .tscn.
#
# ============================================================
# HOST INTEGRATION NOTES
# ============================================================
#
# Palette matched by eye to the existing A Cut Above screens:
#   res://ACA_JobSystem/job_system/ui/job_ui_style.gd  (Job Board)
#   res://ACA_BusinessTown/UI/                         (Town HUD)
# The colour values below are deliberately identical to that file, so
# new UI sits next to the Job Board without a seam.
#
# No fonts are imported. Everything uses the Godot default font at the
# sizes below. To swap in a real font later, set default_font on
# Game UI.theme.tres - one place, whole UI.
#
# To restyle: change the constants here, then re-run
#   res://UI/_tools/Build UI.tscn
# which regenerates Game UI.theme.tres and every component scene.
#
# ============================================================


# ---------------------------------------------------------------- text
const INK := Color(0.937, 0.949, 0.937)
const INK_DIM := Color(0.678, 0.714, 0.729)
const INK_FAINT := Color(0.478, 0.529, 0.545)
## Text drawn on top of an ACCENT fill (primary buttons, filled chips).
const INK_ON_ACCENT := Color(0.075, 0.114, 0.086)

# -------------------------------------------------------------- accents
const ACCENT := Color(0.420, 0.686, 0.353)
const ACCENT_BRIGHT := Color(0.635, 0.855, 0.545)
const WARN := Color(0.855, 0.647, 0.310)
const URGENT := Color(0.878, 0.482, 0.373)
## Money readouts use the bright accent so payouts read as positive.
const MONEY := Color(0.635, 0.855, 0.545)

# ------------------------------------------------------------- surfaces
const PANEL_BG := Color(0.118, 0.145, 0.161, 0.94)
const PANEL_BG2 := Color(0.153, 0.184, 0.196, 0.96)
## Opaque versions of the two panel tones. Menus that can stack on top of
## one another (pause -> settings -> controls) use these, so the screen
## underneath never ghosts through. Panels that sit over live gameplay
## keep the translucent versions above.
const PANEL_SOLID := Color(0.118, 0.145, 0.161, 1.0)
const PANEL_SOLID2 := Color(0.153, 0.184, 0.196, 1.0)
const CARD_BG := Color(0.106, 0.129, 0.145, 0.92)
const CHIP_BG := Color(0.208, 0.251, 0.259, 0.9)
const BUTTON_BG := Color(0.235, 0.278, 0.294)
const BUTTON_DISABLED_BG := Color(0.192, 0.216, 0.227, 0.8)
## Empty portion of a progress bar / fuel gauge.
const TRACK_BG := Color(0.075, 0.094, 0.106, 0.9)
const HAIRLINE := Color(1, 1, 1, 0.08)

# --------------------------------------------------------------- scrims
## Over live gameplay: partial alpha so the lawn stays visible.
const SCRIM_LIGHT := Color(0.043, 0.059, 0.067, 0.55)
## Over a full-screen menu, where nothing behind needs to read.
const SCRIM_HEAVY := Color(0.043, 0.059, 0.067, 0.88)

# ---------------------------------------------------------------- radii
const RADIUS_PANEL := 14.0
const RADIUS_CARD := 12.0
const RADIUS_CHIP := 10.0
const RADIUS_BUTTON := 8.0
const RADIUS_BAR := 3.0

# ----------------------------------------------------------- type scale
const FONT_DISPLAY := 40
const FONT_TITLE := 30
const FONT_HEADING := 22
const FONT_SUBHEAD := 18
const FONT_BODY := 15
const FONT_LABEL := 14
const FONT_META := 13
const FONT_MICRO := 11

# --------------------------------------------------------------- timing
const FADE_FAST := 0.12
const FADE := 0.20
const FADE_SLOW := 0.32
const SLIDE := 0.28


# ======================================================== style helpers

static func stylebox(bg: Color, radius: float = RADIUS_CHIP, border: float = 0.0,
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


## Convenience for scene-building code. Runtime scripts rarely need this.
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


static func style_button(b: Button, primary: bool, height: float = 40.0,
		font_size: int = FONT_BODY) -> Button:
	var base := ACCENT if primary else BUTTON_BG
	var fg := INK_ON_ACCENT if primary else INK
	b.custom_minimum_size = Vector2(0, height)
	b.add_theme_font_size_override("font_size", font_size)
	b.add_theme_stylebox_override("normal", stylebox(base, RADIUS_BUTTON))
	b.add_theme_stylebox_override("hover", stylebox(base.lightened(0.12), RADIUS_BUTTON))
	b.add_theme_stylebox_override("pressed", stylebox(base.darkened(0.15), RADIUS_BUTTON))
	b.add_theme_stylebox_override("focus",
		stylebox(Color(1, 1, 1, 0.04), RADIUS_BUTTON, 2.0, ACCENT_BRIGHT))
	b.add_theme_stylebox_override("disabled", stylebox(BUTTON_DISABLED_BG, RADIUS_BUTTON))
	b.add_theme_color_override("font_color", fg)
	b.add_theme_color_override("font_hover_color", fg)
	b.add_theme_color_override("font_pressed_color", fg)
	b.add_theme_color_override("font_focus_color", fg)
	b.add_theme_color_override("font_disabled_color", INK_FAINT)
	return b


## Destructive actions (Abandon, Quit). Muted until hovered - this is a
## cozy game, not an alarm.
static func style_danger_button(b: Button, height: float = 40.0,
		font_size: int = FONT_BODY) -> Button:
	b.custom_minimum_size = Vector2(0, height)
	b.add_theme_font_size_override("font_size", font_size)
	b.add_theme_stylebox_override("normal",
		stylebox(Color(0.235, 0.184, 0.180, 0.9), RADIUS_BUTTON, 1.0,
			Color(0.878, 0.482, 0.373, 0.35)))
	b.add_theme_stylebox_override("hover",
		stylebox(Color(0.502, 0.259, 0.212), RADIUS_BUTTON, 1.0,
			Color(0.878, 0.482, 0.373, 0.6)))
	b.add_theme_stylebox_override("pressed",
		stylebox(Color(0.400, 0.204, 0.169), RADIUS_BUTTON))
	b.add_theme_stylebox_override("focus",
		stylebox(Color(1, 1, 1, 0.04), RADIUS_BUTTON, 2.0, URGENT))
	b.add_theme_stylebox_override("disabled", stylebox(BUTTON_DISABLED_BG, RADIUS_BUTTON))
	b.add_theme_color_override("font_color", URGENT)
	b.add_theme_color_override("font_hover_color", INK)
	b.add_theme_color_override("font_pressed_color", INK)
	b.add_theme_color_override("font_focus_color", URGENT)
	b.add_theme_color_override("font_disabled_color", INK_FAINT)
	return b


static func style_progress(bar: ProgressBar, fill_colour: Color = ACCENT) -> ProgressBar:
	bar.show_percentage = false
	bar.add_theme_stylebox_override("background",
		stylebox(TRACK_BG, RADIUS_BAR, 0.0, HAIRLINE, 0, 0))
	bar.add_theme_stylebox_override("fill",
		stylebox(fill_colour, RADIUS_BAR, 0.0, HAIRLINE, 0, 0))
	return bar


# ======================================================== text formatting

## 1234 -> "$1,234". Negative amounts render as "-$1,234".
static func format_money(amount: int) -> String:
	var sign_text := "-" if amount < 0 else ""
	var digits := str(absi(amount))
	var out := ""
	var count := 0
	for i in range(digits.length() - 1, -1, -1):
		out = digits[i] + out
		count += 1
		if count % 3 == 0 and i > 0:
			out = "," + out
	return "%s$%s" % [sign_text, out]


## 522.0 -> "08:42". Past an hour it becomes "1:02:03".
static func format_clock(seconds: float) -> String:
	var total := int(maxf(seconds, 0.0))
	var hours := total / 3600
	var minutes := (total % 3600) / 60
	var secs := total % 60
	if hours > 0:
		return "%d:%02d:%02d" % [hours, minutes, secs]
	return "%02d:%02d" % [minutes, secs]


## Expects 0.0 - 1.0. Values outside that range are clamped.
static func percent_text(value: float) -> String:
	return "%d%%" % int(round(clampf(value, 0.0, 1.0) * 100.0))
