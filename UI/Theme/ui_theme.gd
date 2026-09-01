extends RefCounted
class_name UITheme

# ============================================================
# PUBLIC API
# ============================================================
#
# The single place where the UI palette, corner radii and type scale
# are defined. Every component in res://UI/ reads from here.
#
# ------------------------------------------------------------------
# THE VISUAL IDENTITY
# ------------------------------------------------------------------
#
# Modern rustic with cozy illustrated accents: roughly three parts
# grounded structure to one part personality. Warm, inviting, readable,
# rural, low-poly - and above all NOT the generic dark glass panel that
# every other game ships.
#
# The palette is five colours and their weights:
#
#   warm cream       every piece of text, and the surface of anything
#                    that reads as PAPER (a work order, a job sheet)
#   charcoal green   every panel drawn over the world. Charcoal with a
#                    GREEN cast, never blue-grey: over a green world a
#                    blue panel reads as a foreign object laid on top
#                    of the game rather than as part of it
#   forest green     the primary action, and progress
#   muted sage       secondary information and rules
#   mower orange     ONE accent, used sparingly, for the thing on screen
#                    that most wants the eye
#
# Two surface families exist and they are not interchangeable:
#
#   SLATE   PANEL_BG / CARD_BG / CHIP_BG with INK on top. Charcoal
#           green, translucent over gameplay and opaque when menus
#           stack. Everything drawn over the world uses this.
#   PAPER   PAPER_BG / PAPER_BG2 with PAPER_INK on top. Warm cream,
#           always opaque. Used where the fiction is a printed
#           document - the job board's work orders, the results sheet.
#
# ACCESSIBILITY, and these are requirements rather than preferences:
#
#   * INK on PANEL_BG and PAPER_INK on PAPER_BG both clear 4.5:1.
#     INK_ON_ACCENT on ACCENT is about 5.2:1, so a primary button's
#     label passes for BODY text and not only for headings.
#   * INK_FAINT is for decoration, never for information.
#   * NOTHING is communicated by colour alone. The fuel gauge changes
#     its CAPTION as well as its colour; a disabled control is dimmed
#     AND stops taking focus; an urgent notification carries a word.
#   * Focus is a two-pixel ACCENT_BRIGHT ring, present on every
#     interactive style, so a keyboard is a first-class way to drive
#     every screen.
#   * FONT_MICRO is the floor, and it is 12 rather than the 11 it used
#     to be. Nothing readable is smaller.
#   * Animation is restrained and short. FADE is a fifth of a second.
#
# Constants (read directly, e.g. UITheme.ACCENT):
#
#   Text        INK, INK_DIM, INK_FAINT, INK_ON_ACCENT
#   Accent      ACCENT, ACCENT_BRIGHT, SAGE, ORANGE, WARN, URGENT, MONEY
#   Surfaces    PANEL_BG, PANEL_BG2, CARD_BG, CHIP_BG, BUTTON_BG,
#               TRACK_BG, HAIRLINE
#               PANEL_SOLID, PANEL_SOLID2 - opaque, for stacking menus
#   Paper       PAPER_BG, PAPER_BG2, PAPER_INK, PAPER_INK_DIM,
#               PAPER_INK_FAINT, PAPER_RULE
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
#   style_accent_button(button, height, font_size) -> Button
#   style_danger_button(button, height, font_size) -> Button
#   style_progress(bar, fill_colour) -> ProgressBar
#   paper_panel(radius) -> StyleBoxFlat
#   status_colour(kind) -> Color          # &"ok" / &"warn" / &"urgent"
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
const INK := Color(0.957, 0.929, 0.874)
const INK_DIM := Color(0.769, 0.745, 0.686)
const INK_FAINT := Color(0.588, 0.576, 0.522)
## Text drawn on top of an ACCENT fill (primary buttons, filled chips).
const INK_ON_ACCENT := Color(0.965, 0.945, 0.898)

# -------------------------------------------------------------- accents
const ACCENT := Color(0.216, 0.427, 0.267)
const ACCENT_BRIGHT := Color(0.545, 0.780, 0.478)
const WARN := Color(0.851, 0.639, 0.267)
const URGENT := Color(0.784, 0.361, 0.259)
## Money readouts use the bright accent so payouts read as positive.
const MONEY := Color(0.545, 0.780, 0.478)
## Muted sage. Secondary information, rules and quiet dividers, on either
## surface family.
const SAGE := Color(0.612, 0.694, 0.573)
## THE mower-orange accent, and the reason it has its own name rather than
## being reached for as a literal: it is meant to appear about once per
## screen. Used everywhere it stops meaning anything.
const ORANGE := Color(0.851, 0.478, 0.169)
const ORANGE_DIM := Color(0.639, 0.361, 0.129)

# ----------------------------------------------------------------- paper
## The second surface family. Warm cream, for anything whose fiction is a
## printed document. See the note at the top of this file.
const PAPER_BG := Color(0.949, 0.925, 0.867)
const PAPER_BG2 := Color(0.980, 0.965, 0.925)
const PAPER_INK := Color(0.157, 0.180, 0.153)
const PAPER_INK_DIM := Color(0.353, 0.396, 0.337)
const PAPER_INK_FAINT := Color(0.502, 0.537, 0.478)
const PAPER_RULE := Color(0.157, 0.180, 0.153, 0.16)

# ------------------------------------------------------ paper over the world
## THE MOWING HUD'S SURFACE, and the reason PAPER is no longer described as
## "always opaque".
##
## The HUD used to be SLATE, because the old rule was that anything drawn over
## gameplay is slate and only documents are paper. That rule produced a correct,
## legible, and completely forgettable interface: a dark grey box on a green
## field. What the game actually wants over the lawn is the thing the operator
## would really have on the machine with them - the job sheet - and a job sheet
## is paper.
##
## So paper comes outside. These three are the same cream as `PAPER_BG`, at the
## alpha and the edge treatment a panel needs when there is a moving world
## behind it:
##
##   HUD_BG      cream, a few percent open so the lawn is felt through it
##   HUD_EDGE    a warm brown-green rule, darker than PAPER_RULE, because over a
##               bright lawn a sixteen-percent black line disappears
##   HUD_SHADOW  what actually separates the card from the world. A soft dark
##               band under the panel does more for legibility than another ten
##               percent of opacity, and costs the view nothing.
const HUD_BG := Color(0.957, 0.937, 0.886, 0.955)
const HUD_BG2 := Color(0.910, 0.882, 0.812, 0.955)
const HUD_EDGE := Color(0.259, 0.286, 0.220, 0.320)
const HUD_SHADOW := Color(0.075, 0.098, 0.071, 0.300)
## The green a HUD card's header band and its progress fill are drawn in. A
## touch deeper than ACCENT so it holds against cream rather than against
## charcoal.
const HUD_GREEN := Color(0.243, 0.435, 0.278)
const HUD_GREEN_BRIGHT := Color(0.400, 0.612, 0.337)
## The empty part of a bar drawn ON paper. TRACK_BG is nearly black and reads as
## a hole punched in the card.
const PAPER_TRACK := Color(0.820, 0.796, 0.729, 1.0)

# ------------------------------------------------------------- surfaces
const PANEL_BG := Color(0.114, 0.133, 0.114, 0.940)
const PANEL_BG2 := Color(0.153, 0.176, 0.149, 0.960)
## Opaque versions of the two panel tones. Menus that can stack on top of
## one another (pause -> settings -> controls) use these, so the screen
## underneath never ghosts through. Panels that sit over live gameplay
## keep the translucent versions above.
const PANEL_SOLID := Color(0.114, 0.133, 0.114, 1.000)
const PANEL_SOLID2 := Color(0.153, 0.176, 0.149, 1.000)
const CARD_BG := Color(0.098, 0.118, 0.102, 0.920)
const CHIP_BG := Color(0.196, 0.224, 0.188, 0.900)
const BUTTON_BG := Color(0.227, 0.259, 0.216)
const BUTTON_DISABLED_BG := Color(0.184, 0.204, 0.176, 0.800)
## Empty portion of a progress bar / fuel gauge.
const TRACK_BG := Color(0.071, 0.086, 0.071, 0.900)
const HAIRLINE := Color(0.960, 0.933, 0.882, 0.100)

# --------------------------------------------------------------- scrims
## Over live gameplay: partial alpha so the lawn stays visible.
const SCRIM_LIGHT := Color(0.047, 0.059, 0.047, 0.550)
## Over a full-screen menu, where nothing behind needs to read.
const SCRIM_HEAVY := Color(0.047, 0.059, 0.047, 0.880)

# ---------------------------------------------------------------- radii
## Slightly tighter than they were. A large corner radius reads as soft and
## modern; a rustic interface wants to read as BUILT, and the difference
## between the two is a couple of pixels on every corner in the game.
const RADIUS_PANEL := 12.0
const RADIUS_CARD := 10.0
const RADIUS_CHIP := 8.0
const RADIUS_BUTTON := 7.0
const RADIUS_BAR := 3.0

# ----------------------------------------------------------- type scale
const FONT_DISPLAY := 40
const FONT_TITLE := 30
const FONT_HEADING := 22
const FONT_SUBHEAD := 18
const FONT_BODY := 15
const FONT_LABEL := 14
const FONT_META := 14
## THE FLOOR. Nothing in this game is drawn smaller than this, and it went up
## from eleven because eleven pixels of a default font at 1080p is not a size
## anybody should be asked to read a fuel percentage at.
const FONT_MICRO := 12

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
		stylebox(Color(0.957, 0.929, 0.874, 0.050), RADIUS_BUTTON, 2.0, ACCENT_BRIGHT))
	b.add_theme_stylebox_override("disabled", stylebox(BUTTON_DISABLED_BG, RADIUS_BUTTON))
	b.add_theme_color_override("font_color", fg)
	b.add_theme_color_override("font_hover_color", fg)
	b.add_theme_color_override("font_pressed_color", fg)
	b.add_theme_color_override("font_focus_color", fg)
	b.add_theme_color_override("font_disabled_color", INK_FAINT)
	# EVERY BUTTON IN THE PROJECT COMES THROUGH HERE, which is why the press and
	# hover cues are attached here rather than in forty-six screens. `AppUI`
	# owns the players; this only asks for them. See `ACAUISound`.
	_attach_sound(b, ACAUISound.CLICK)
	return b


## The ONE mower-orange control on a screen: the thing the player most likely
## came to this screen to press. Deliberately a separate helper from
## `style_button(primary)` so reaching for it is a decision rather than a habit.
static func style_accent_button(b: Button, height: float = 40.0,
		font_size: int = FONT_BODY) -> Button:
	b.custom_minimum_size = Vector2(0, height)
	b.add_theme_font_size_override("font_size", font_size)
	b.add_theme_stylebox_override("normal", stylebox(ORANGE, RADIUS_BUTTON))
	b.add_theme_stylebox_override("hover", stylebox(ORANGE.lightened(0.12), RADIUS_BUTTON))
	b.add_theme_stylebox_override("pressed", stylebox(ORANGE_DIM, RADIUS_BUTTON))
	b.add_theme_stylebox_override("focus",
		stylebox(Color(1, 1, 1, 0.05), RADIUS_BUTTON, 2.0, ACCENT_BRIGHT))
	b.add_theme_stylebox_override("disabled", stylebox(BUTTON_DISABLED_BG, RADIUS_BUTTON))
	for key in ["font_color", "font_hover_color", "font_pressed_color",
			"font_focus_color"]:
		b.add_theme_color_override(key, PAPER_INK)
	b.add_theme_color_override("font_disabled_color", INK_FAINT)
	# THE ONE ORANGE CONTROL GETS THE CONFIRM CUE, not the ordinary click. It is
	# the thing the player came to the screen to press, and it should sound like
	# a decision rather than like a tab.
	_attach_sound(b, ACAUISound.CONFIRM)
	return b


## A HUD card: warm cream over live gameplay, with an edge that holds against a
## bright lawn and a drop shadow that does the separating. Use with PAPER_INK
## text, exactly like `paper_panel()`.
##
## The shadow is an EXPANDED margin rather than a second panel, so a card is
## still one node and one draw.
static func hud_panel(radius: float = RADIUS_PANEL, margin_h: float = 16.0,
		margin_v: float = 12.0, tone: Color = HUD_BG) -> StyleBoxFlat:
	var s := stylebox(tone, radius, 1.0, HUD_EDGE, margin_h, margin_v)
	s.shadow_color = HUD_SHADOW
	s.shadow_size = 6
	s.shadow_offset = Vector2(0, 2)
	return s


## A small cream pill, for the environment strip and the contextual hints.
static func hud_chip(radius: float = RADIUS_CHIP) -> StyleBoxFlat:
	return hud_panel(radius, 13.0, 7.0)


## A bar drawn ON a HUD card. Separate from `style_progress()` because that one
## fills its track with `TRACK_BG`, which is nearly black and punches a hole in
## the paper.
static func style_paper_progress(bar: ProgressBar,
		fill_colour: Color = HUD_GREEN) -> ProgressBar:
	bar.show_percentage = false
	bar.add_theme_stylebox_override("background",
		stylebox(PAPER_TRACK, RADIUS_BAR, 0.0, HAIRLINE, 0, 0))
	bar.add_theme_stylebox_override("fill",
		stylebox(fill_colour, RADIUS_BAR, 0.0, HAIRLINE, 0, 0))
	return bar


## ---------------------------------------------------------------------------
## REPAINTING A SLATE SCREEN AS PAPER
## ---------------------------------------------------------------------------
## Several screens were authored as SLATE - a dark panel with cream text - and
## are being moved to PAPER now that the mowing HUD has made cream the game's
## surface over the world. Their LAYOUT is fine; it is only the colours that are
## from the old family.
##
## Rebuilding each scene to change its colours would be a lot of risk for a
## repaint, so this walks the subtree instead and swaps one family for the
## other, by name. It is deliberately a SMALL, TOTAL mapping - every slate
## colour has exactly one paper counterpart, listed below - so what it does can
## be predicted by reading it rather than by running it.
##
##   INK, INK_ON_ACCENT  -> PAPER_INK
##   INK_DIM             -> PAPER_INK_DIM
##   INK_FAINT, SAGE     -> PAPER_INK_FAINT
##   ACCENT, ACCENT_BRIGHT, MONEY -> HUD_GREEN
##   HAIRLINE            -> PAPER_RULE
##
## WARN, URGENT and ORANGE are left alone: all three were chosen to carry a
## warning, and all three still carry it on cream. So are BUTTONS, for the
## reason given at the branch that skips them.
##
## Call it ONCE, from `_ready()`, on the card rather than on the whole screen -
## a scrim is not part of the card and should stay dark.
static func repaint_to_paper(root: Node) -> void:
	if root == null:
		return
	if root is PanelContainer or root is Panel:
		# A REPAINT CHANGES COLOUR, NOT LAYOUT. A PanelContainer's content
		# margins live on its stylebox, so replacing the box outright throws
		# away the padding the screen was composed with and presses the text
		# flat against all four edges. Whatever margins the panel already had
		# are carried across. (The Job Intro's work order shipped with none for
		# exactly this reason.)
		var panel := root as Control
		var was := panel.get_theme_stylebox(&"panel")
		var mh := 0.0
		var mv := 0.0
		if was != null:
			mh = maxf(was.content_margin_left, was.content_margin_right)
			mv = maxf(was.content_margin_top, was.content_margin_bottom)
			mh = maxf(mh, 0.0)
			mv = maxf(mv, 0.0)
		panel.add_theme_stylebox_override("panel",
			paper_panel(RADIUS_PANEL, mh, mv))
	elif root is Label:
		var label := root as Label
		label.add_theme_color_override("font_color",
			_to_paper(label.get_theme_color(&"font_color")))
	elif root is RichTextLabel:
		var rich := root as RichTextLabel
		rich.add_theme_color_override("default_color",
			_to_paper(rich.get_theme_color(&"default_color")))
	elif root is ColorRect:
		var rect := root as ColorRect
		rect.color = _to_paper(rect.color)
	elif root is ProgressBar:
		var bar := root as ProgressBar
		var fill := bar.get_theme_stylebox(&"fill") as StyleBoxFlat
		style_paper_progress(bar,
			_to_paper(fill.bg_color) if fill != null else HUD_GREEN)
	elif root is Button:
		# LEFT ALONE, DELIBERATELY. A button is a control rather than a surface:
		# it already carries its own fill, and all three of the shared button
		# styles read on cream as well as they do on charcoal. Restyling them
		# here - which the first version did - flattened every secondary button
		# on a screen into the primary green and threw the hierarchy away.
		return
	for child in root.get_children():
		repaint_to_paper(child)


## The paper counterpart of one slate colour. Anything not in the table is
## returned unchanged, alpha included, so a colour this was not written for
## survives rather than being guessed at.
static func _to_paper(colour: Color) -> Color:
	for pair in [
			[INK, PAPER_INK], [INK_ON_ACCENT, PAPER_INK],
			[INK_DIM, PAPER_INK_DIM],
			[INK_FAINT, PAPER_INK_FAINT], [SAGE, PAPER_INK_FAINT],
			[ACCENT, HUD_GREEN], [ACCENT_BRIGHT, HUD_GREEN], [MONEY, HUD_GREEN],
			[HAIRLINE, PAPER_RULE],
		]:
		var from: Color = pair[0]
		if _near(colour.r, from.r) and _near(colour.g, from.g) and _near(colour.b, from.b):
			var to: Color = pair[1]
			return Color(to.r, to.g, to.b, colour.a)
	return colour


## Colour channels within half a step of an eight-bit value. `is_equal_approx`
## is far too strict for colours that were authored as three decimal places.
static func _near(a: float, b: float) -> bool:
	return absf(a - b) < 0.004


## A PAPER surface: opaque warm cream with a soft rule around it. Use with
## PAPER_INK text; INK on this is unreadable and is meant to be.
static func paper_panel(radius: float = RADIUS_CARD,
		margin_h: float = 16.0, margin_v: float = 12.0) -> StyleBoxFlat:
	return stylebox(PAPER_BG, radius, 1.0, PAPER_RULE, margin_h, margin_v)


## The colour for a state, so no screen invents its own mapping.
## NOTHING SHOULD RELY ON THIS ALONE - see the accessibility note at the top.
## A caption changes with the colour, every time.
static func status_colour(kind: StringName) -> Color:
	match kind:
		&"warn":
			return WARN
		&"urgent":
			return URGENT
		&"accent":
			return ORANGE
		&"money":
			return MONEY
		_:
			return ACCENT


## Destructive actions (Abandon, Quit). Muted until hovered - this is a
## cozy game, not an alarm.
static func style_danger_button(b: Button, height: float = 40.0,
		font_size: int = FONT_BODY) -> Button:
	b.custom_minimum_size = Vector2(0, height)
	b.add_theme_font_size_override("font_size", font_size)
	b.add_theme_stylebox_override("normal",
		stylebox(Color(0.208, 0.153, 0.129, 0.900), RADIUS_BUTTON, 1.0,
			Color(0.784, 0.361, 0.259, 0.350)))
	b.add_theme_stylebox_override("hover",
		stylebox(Color(0.482, 0.243, 0.180), RADIUS_BUTTON, 1.0,
			Color(0.784, 0.361, 0.259, 0.600)))
	b.add_theme_stylebox_override("pressed",
		stylebox(Color(0.376, 0.192, 0.145), RADIUS_BUTTON))
	b.add_theme_stylebox_override("focus",
		stylebox(Color(0.957, 0.929, 0.874, 0.050), RADIUS_BUTTON, 2.0, URGENT))
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


## Ask `AppUI` for this button's sounds. Silent - and harmless - when there is
## no `AppUI`, which is how the headless suites and the standalone tooling build
## controls.
static func _attach_sound(b: Button, cue: StringName) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return
	var ui := tree.root.get_node_or_null(^"AppUI")
	if ui == null or not ui.has_method(&"attach_button_sound"):
		return
	ui.call(&"attach_button_sound", b, cue)
