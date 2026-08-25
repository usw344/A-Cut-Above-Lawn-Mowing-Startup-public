extends Control
class_name GameplayHUD

# ============================================================
# PUBLIC API
# ============================================================
#
# Host project should call:
#
#   set_job_name(value: String)          # "A Residence"
#   set_job_size(value: String)          # "Medium Lawn"
#   set_property_type(value: String)     # "Residential"
#   set_reward(value: int)               # 240  -> renders "$240"
#
#   set_progress(value: float)           # 0.0 - 1.0  (animated)
#   set_progress_immediate(value: float) # 0.0 - 1.0  (no tween)
#   set_area(cut: int, total: int)       # square units cut / to cut
#   set_site_notes(pond: bool, obstacles: int)
#   set_fuel(value: float)               # 0.0 - 1.0  (animated)
#   set_status(value: String)            # "MOWING" / "TRIMMING" / ...
#
#   set_game_time(value: String)         # "09:41" - already formatted
#   set_weather(value: String)           # "Clear"
#   set_day(value: String)               # "Day 3"
#
#   show_hud()                           # fade in
#   hide_hud()                           # fade out
#   is_hud_visible() -> bool
#
#   set_pause_hint_visible(value: bool)  # hide the ESC chip if the host
#                                        # has no pause, or on gamepad
#
# Read-back helpers (useful for demos, tests and debug overlays):
#
#   progress() -> float
#   fuel() -> float
#   job_name_text() / reward_text() / game_time_text() / weather_text()
#
# NORMALISATION: every 0-1 parameter above is 0.0 -> 1.0, NOT 0 -> 100.
# Values are clamped, so passing 1.4 or -0.2 is safe. Percentages are
# formatted for display by UITheme.percent_text().
#
# Signals emitted:
#
#   pause_requested          # the ESC chip was clicked
#   low_fuel_entered         # fuel crossed below LOW_FUEL_THRESHOLD
#   low_fuel_exited          # fuel came back above it (e.g. refuel)
#
# The low-fuel signals are a convenience for the host: hook them up to a
# toast, or ignore them entirely. The HUD colours its own gauge either way.
#
# ============================================================
# THE DESIGN, AND WHAT CHANGED
# ============================================================
#
# This HUD used to be four charcoal-green slate panels. It was legible,
# it was consistent with everything else drawn over the world, and it
# looked like a debug overlay that had been tidied up.
#
# What it is now is THE OPERATOR'S JOB SHEET, pinned to the four corners
# of the view:
#
#   top left      the contract. Site, what kind of property, the one
#                 objective, and a short checklist of what the property
#                 actually contains.
#   top centre    the day, the clock and the weather, in one pill.
#   top right     fuel.
#   bottom left   the minimap. Not owned by this script - the host places
#                 MinimapPanel there - but styled to match, so the four
#                 corners read as one interface.
#   bottom right  the pause hint, and nothing else.
#
# THE MIDDLE OF THE SCREEN IS EMPTY AND STAYS EMPTY. Everything above
# hugs an edge, and the tallest card is under a third of the screen.
#
# Surfaces are warm cream (`UITheme.HUD_BG`) with `PAPER_INK` on them,
# forest green for progress and for the header band, and one restrained
# mower orange - on the low-fuel state, which is the only thing on this
# HUD that ever wants to interrupt. Marks are drawn by `UIGlyph`; there
# are no icon fonts and no image assets anywhere in this file.
#
# WHAT IT DELIBERATELY DOES NOT DO, having been pointed at a reference
# image: no scattered decorative flowers, no second decorative frame
# around every panel, no legend card in the corner explaining the game to
# a player who is already playing it, and no ornament that carries no
# information. The warmth and the checklist are the ideas worth taking.
#
# ============================================================
# THE LAYOUT IS BUILT IN CODE
# ============================================================
#
# `Gameplay HUD.tscn` is now a bare Control carrying this script and the
# shared theme. Every child is built by `_build()` below.
#
# That is a deliberate reversal. The scene held about forty nodes and a
# dozen inline StyleBoxFlat sub-resources, each a copy of a colour that
# also lives in `UITheme`; restyling it meant editing colour literals in
# a text file that no reviewer could read. The layout is now one function
# that can be read top to bottom, and every colour comes from the theme
# by name.
#
# The public API is unchanged, and `%`-unique names are gone with the
# scene that needed them.
#
# ============================================================
# SCENE / RESOURCE REFERENCES
# ============================================================
#
# This script preloads nothing.
#
# Gameplay HUD.tscn references exactly one external resource:
#
#   res://UI/Theme/Game UI.theme.tres   (root node theme property)
#
# There are NO references to town scenes, job scenes, or game scripts.
#
# ============================================================
# HOST INTEGRATION NOTES
# ============================================================
#
# This component owns presentation only.
# It does NOT read the player, the mower, or any job model.
# The host supplies progress / fuel / job information through the public
# API above, typically once per frame or whenever a value changes.
#
# PLACEMENT: add the scene under a CanvasLayer (or any Control) in the
# host HUD. The root is a full-rect Control whose mouse_filter is IGNORE,
# so it never steals clicks from the game; only the ESC chip is clickable.
#
# PAUSING: the HUD does not read the Escape key and does not pause the
# tree. It only emits pause_requested when its chip is clicked. Keep
# Escape handling in the host, or in Pause Menu.tscn, which does read it.
#
# ============================================================


signal pause_requested()
signal low_fuel_entered()
signal low_fuel_exited()

## Fuel at or below this fraction turns the gauge amber and relabels it.
@export_range(0.0, 1.0, 0.01) var low_fuel_threshold: float = 0.2
## Below this it turns red. Purely cosmetic thresholds.
@export_range(0.0, 1.0, 0.01) var critical_fuel_threshold: float = 0.08
## Seconds for the progress / fuel bars to catch up to a new value.
@export var bar_tween_time: float = 0.25

## How far the cards sit from the edge of the screen.
const EDGE_MARGIN := 22.0
## The contract card's width. Wide enough for a long site name on two lines and
## for the widest checklist row, narrow enough to leave the view alone.
const JOB_CARD_WIDTH := 344.0
const FUEL_CARD_WIDTH := 190.0

var _job_name: Label = null
var _job_meta: Label = null
var _status: Label = null
var _percent: Label = null
var _progress_bar: ProgressBar = null
var _reward: Label = null
var _time: Label = null
var _weather: Label = null
var _weather_glyph: UIGlyph = null
var _day: Label = null
var _fuel_caption: Label = null
var _fuel_percent: Label = null
var _fuel_bar: ProgressBar = null
var _fuel_glyph: UIGlyph = null
var _pause_hint: Button = null

## The checklist rows. Each is { dot: Control, label: Label, value: Label }.
var _row_area: Dictionary = {}
var _row_features: Dictionary = {}
var _row_contract: Dictionary = {}

var _progress: float = 0.0
var _fuel: float = 1.0
var _low_fuel: bool = false
var _progress_tween: Tween
var _fuel_tween: Tween
var _built: bool = false


func _ready() -> void:
	_build()
	_apply_progress(_progress)
	_apply_fuel(_fuel)


# =================================================================== the build

## THE FRAME. One row across the top holding the contract and the fuel at its
## two ends, one centring container over it for the environment pill, and one
## chip in the bottom right. Everything else is a child of those.
##
## Anchors and offsets are set EXPLICITLY rather than through `position`, which
## is what the first version did and why the fuel card left the screen: setting
## `position` on a control whose anchors are not at the origin overwrites the
## offsets the preset just computed, and the result is a panel measured from the
## wrong corner.
func _build() -> void:
	if _built:
		return
	_built = true
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	var top := HBoxContainer.new()
	top.name = "Top Row"
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.anchor_right = 1.0
	top.offset_left = EDGE_MARGIN
	top.offset_right = -EDGE_MARGIN
	top.offset_top = EDGE_MARGIN
	top.grow_horizontal = Control.GROW_DIRECTION_BOTH
	add_child(top)

	_build_job_card(top)
	var gap := Control.new()
	gap.name = "Gap"
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(gap)
	_build_fuel_card(top)

	# The environment pill is centred on the SCREEN, not on the space between
	# the two cards, so it does not shuffle sideways when a site name is long.
	var centre := CenterContainer.new()
	centre.name = "Top Centre"
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	centre.anchor_right = 1.0
	centre.offset_top = EDGE_MARGIN
	centre.grow_horizontal = Control.GROW_DIRECTION_BOTH
	add_child(centre)
	_build_environment_strip(centre)

	_build_pause_hint()


## TOP LEFT. The contract, and what the property has on it.
func _build_job_card(parent: Node) -> void:
	var card := _card(parent, "Job Card")
	card.custom_minimum_size = Vector2(JOB_CARD_WIDTH, 0)

	var column := VBoxContainer.new()
	column.name = "Column"
	column.add_theme_constant_override("separation", 4)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(column)

	# The header: a leaf, then the site. The leaf is the game's mark and this is
	# the one place per screen it appears.
	# The header sits on a band of the faintest possible green. It is the one
	# piece of decoration on the card, it is there to separate the site name from
	# the numbers under it, and at this alpha it reads as paper stock rather than
	# as a coloured box.
	var band := PanelContainer.new()
	band.name = "Header Band"
	band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	band.add_theme_stylebox_override("panel", UITheme.stylebox(
		Color(UITheme.HUD_GREEN.r, UITheme.HUD_GREEN.g, UITheme.HUD_GREEN.b, 0.085),
		UITheme.RADIUS_CHIP, 0.0, UITheme.HAIRLINE, 10.0, 7.0))
	column.add_child(band)

	var header := HBoxContainer.new()
	header.name = "Header"
	header.add_theme_constant_override("separation", 8)
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	band.add_child(header)
	var leaf := UIGlyph.make(UIGlyph.Kind.LEAF, 19.0, UITheme.HUD_GREEN)
	leaf.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header.add_child(leaf)
	_job_name = UITheme.label(header, "JobName", "PROPERTY",
		UITheme.FONT_SUBHEAD, UITheme.PAPER_INK, true)
	_job_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	_job_meta = UITheme.label(column, "JobMeta", "", UITheme.FONT_MICRO,
		UITheme.PAPER_INK_FAINT)

	column.add_child(_spacer(6))

	# THE OBJECTIVE. One line, a percentage, and a bar - the reference image's
	# best idea, and the only thing on this card that moves while mowing.
	var objective := HBoxContainer.new()
	objective.name = "Objective"
	objective.add_theme_constant_override("separation", 8)
	objective.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(objective)
	var stripes := UIGlyph.make(UIGlyph.Kind.STRIPES, 15.0, UITheme.HUD_GREEN)
	stripes.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	objective.add_child(stripes)
	_status = UITheme.label(objective, "StatusCaption", "MOW THE ENTIRE LAWN",
		UITheme.FONT_LABEL, UITheme.PAPER_INK_DIM)
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# THE NUMBER THE PLAYER WATCHES, and it is the largest thing on the card
	# after the site name for exactly that reason.
	_percent = UITheme.label(objective, "ProgressPercent", "0%",
		UITheme.FONT_SUBHEAD, UITheme.HUD_GREEN)

	_progress_bar = ProgressBar.new()
	_progress_bar.name = "ProgressBar"
	_progress_bar.custom_minimum_size = Vector2(0, 11)
	_progress_bar.max_value = 1.0
	_progress_bar.step = 0.0001
	_progress_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UITheme.style_paper_progress(_progress_bar)
	column.add_child(_progress_bar)

	column.add_child(_spacer(9))
	column.add_child(_rule())
	column.add_child(_spacer(7))

	# THE CHECKLIST. Real numbers only: how much ground there is, what is
	# standing on it, and what the contract pays.
	_row_area = _checklist_row(column, UIGlyph.Kind.STRIPES, "Cut all grass", "")
	_row_features = _checklist_row(column, UIGlyph.Kind.STONE,
		"Mow around obstacles", "")
	_row_contract = _checklist_row(column, UIGlyph.Kind.LEAF, "Contract", "")
	_reward = _row_contract["value"]
	_reward.add_theme_color_override("font_color", UITheme.HUD_GREEN)


## TOP CENTRE. Day, clock, weather - the three things a player checks without
## looking away from the lawn for long.
func _build_environment_strip(parent: Node) -> void:
	var strip := _card(parent, "Environment", UITheme.hud_chip(UITheme.RADIUS_CHIP))

	var row := HBoxContainer.new()
	row.name = "Row"
	row.add_theme_constant_override("separation", 10)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	strip.add_child(row)

	var sun := UIGlyph.make(UIGlyph.Kind.SUN, 15.0, UITheme.HUD_GREEN)
	sun.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(sun)
	_time = UITheme.label(row, "TimeValue", "08:00", UITheme.FONT_BODY,
		UITheme.PAPER_INK)
	row.add_child(_divider())
	_day = UITheme.label(row, "DayValue", "Day 1", UITheme.FONT_BODY,
		UITheme.PAPER_INK_DIM)
	row.add_child(_divider())
	_weather_glyph = UIGlyph.make(UIGlyph.Kind.CLOUD, 15.0, UITheme.HUD_GREEN)
	_weather_glyph.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_weather_glyph)
	_weather = UITheme.label(row, "WeatherValue", "Clear", UITheme.FONT_BODY,
		UITheme.PAPER_INK)


## TOP RIGHT. Fuel, and the one place on this HUD that is allowed to shout.
func _build_fuel_card(parent: Node) -> void:
	var card := _card(parent, "Fuel")
	card.custom_minimum_size = Vector2(FUEL_CARD_WIDTH, 0)

	var column := VBoxContainer.new()
	column.name = "Column"
	column.add_theme_constant_override("separation", 5)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(column)

	var row := HBoxContainer.new()
	row.name = "Row"
	row.add_theme_constant_override("separation", 8)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(row)
	_fuel_glyph = UIGlyph.make(UIGlyph.Kind.DROP, 15.0, UITheme.HUD_GREEN)
	_fuel_glyph.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_fuel_glyph)
	_fuel_caption = UITheme.label(row, "FuelCaption", "FUEL", UITheme.FONT_LABEL,
		UITheme.PAPER_INK_DIM)
	_fuel_caption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_fuel_percent = UITheme.label(row, "FuelPercent", "100%", UITheme.FONT_LABEL,
		UITheme.PAPER_INK)

	_fuel_bar = ProgressBar.new()
	_fuel_bar.name = "FuelBar"
	_fuel_bar.custom_minimum_size = Vector2(0, 9)
	_fuel_bar.max_value = 1.0
	_fuel_bar.step = 0.0001
	_fuel_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UITheme.style_paper_progress(_fuel_bar)
	column.add_child(_fuel_bar)


## BOTTOM RIGHT. One chip, and only while there is something to say.
func _build_pause_hint() -> void:
	_pause_hint = Button.new()
	_pause_hint.name = "PauseHint"
	_pause_hint.text = "ESC   Pause"
	_pause_hint.focus_mode = Control.FOCUS_NONE
	_pause_hint.add_theme_font_size_override("font_size", UITheme.FONT_MICRO)
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		_pause_hint.add_theme_stylebox_override(state,
			UITheme.hud_chip(UITheme.RADIUS_CHIP))
	for key in ["font_color", "font_hover_color", "font_pressed_color",
			"font_focus_color"]:
		_pause_hint.add_theme_color_override(key, UITheme.PAPER_INK_DIM)
	add_child(_pause_hint)
	_pause_hint.anchor_left = 1.0
	_pause_hint.anchor_right = 1.0
	_pause_hint.anchor_top = 1.0
	_pause_hint.anchor_bottom = 1.0
	_pause_hint.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_pause_hint.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_pause_hint.offset_right = -EDGE_MARGIN
	_pause_hint.offset_bottom = -EDGE_MARGIN
	_pause_hint.pressed.connect(func() -> void: pause_requested.emit())


# ================================================================ build pieces

## A cream card. It sizes to its content and sits at the TOP of whatever row it
## is placed in, so two cards of different heights still line up along their top
## edges rather than being stretched to match.
func _card(parent: Node, node_name: String,
		style: StyleBoxFlat = null) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.name = node_name
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	panel.add_theme_stylebox_override("panel",
		style if style != null else UITheme.hud_panel())
	parent.add_child(panel)
	return panel


## One checklist line: a mark, what it is, and the number. Returns the parts so
## the setters can reach them without a node path.
func _checklist_row(parent: Node, kind: UIGlyph.Kind, text: String,
		value: String) -> Dictionary:
	var row := HBoxContainer.new()
	row.name = "Row " + text
	row.add_theme_constant_override("separation", 8)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(row)

	var mark := UIGlyph.make(kind, 13.0, UITheme.PAPER_INK_FAINT)
	mark.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(mark)
	var caption := UITheme.label(row, "Caption", text, UITheme.FONT_MICRO,
		UITheme.PAPER_INK_DIM)
	caption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var readout := UITheme.label(row, "Value", value, UITheme.FONT_MICRO,
		UITheme.PAPER_INK)
	return {"mark": mark, "label": caption, "value": readout}


func _spacer(height: float) -> Control:
	var gap := Control.new()
	gap.name = "Gap"
	gap.custom_minimum_size = Vector2(0, height)
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return gap


func _rule() -> ColorRect:
	var line := ColorRect.new()
	line.name = "Rule"
	line.color = UITheme.PAPER_RULE
	line.custom_minimum_size = Vector2(0, 1)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return line


func _divider() -> ColorRect:
	var line := ColorRect.new()
	line.name = "Divider"
	line.color = UITheme.PAPER_RULE
	line.custom_minimum_size = Vector2(1, 14)
	line.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return line


# ============================================================ job identity

func set_job_name(value: String) -> void:
	_build()
	_job_name.text = value.to_upper()


func set_job_size(value: String) -> void:
	_build()
	_set_meta(value, _property_type)


## "Residential", "Rural", "Public"... Shown beside the lawn size.
func set_property_type(value: String) -> void:
	_build()
	_set_meta(_lawn_size, value)


var _lawn_size: String = ""
var _property_type: String = ""


func _set_meta(size_text: String, type_text: String) -> void:
	_lawn_size = size_text
	_property_type = type_text
	var parts := PackedStringArray()
	if not type_text.is_empty():
		parts.append(type_text)
	if not size_text.is_empty():
		parts.append(size_text)
	_job_meta.text = "   ".join(parts)
	_job_meta.visible = not parts.is_empty()


## Contract value in whole currency units. 240 renders as "$240".
func set_reward(value: int) -> void:
	_build()
	_reward.text = UITheme.format_money(value)


## How much ground there is, and how much of it is done. Both in square world
## units, which is exactly what `ACALawn` counts.
func set_area(cut: int, total: int) -> void:
	_build()
	var row_value: Label = _row_area["value"]
	if total <= 0:
		row_value.text = ""
		return
	row_value.text = "%s / %s m²" % [_grouped(cut), _grouped(total)]


## What is standing on the contract. Both come from the generated property, so
## a card never claims a pond a property does not have.
func set_site_notes(pond: bool, obstacles: int) -> void:
	_build()
	var caption: Label = _row_features["label"]
	var row_value: Label = _row_features["value"]
	var mark: UIGlyph = _row_features["mark"]
	if obstacles > 0 and pond:
		caption.text = "Mow around the pond and rocks"
		row_value.text = str(obstacles)
		mark.set_kind(UIGlyph.Kind.WATER)
	elif pond:
		caption.text = "Mow around the pond"
		row_value.text = "1"
		mark.set_kind(UIGlyph.Kind.WATER)
	elif obstacles > 0:
		caption.text = "Mow around obstacles"
		row_value.text = str(obstacles)
		mark.set_kind(UIGlyph.Kind.STONE)
	else:
		caption.text = "Open ground"
		row_value.text = "clear"
		mark.set_kind(UIGlyph.Kind.STRIPES)


# ================================================================ progress

## Expects 0.0 - 1.0. Animates the bar; safe to call every frame.
func set_progress(value: float) -> void:
	_build()
	var target := clampf(value, 0.0, 1.0)
	if is_equal_approx(target, _progress):
		return
	_progress = target
	_percent.text = UITheme.percent_text(target)
	if _progress_tween != null and _progress_tween.is_valid():
		_progress_tween.kill()
	_progress_tween = create_tween()
	_progress_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_progress_tween.tween_property(_progress_bar, "value", target, bar_tween_time)
	# The bar goes bright green as the job closes out - a small reward
	# for finishing, without adding an effect.
	var fill := UITheme.HUD_GREEN_BRIGHT if target >= 1.0 else UITheme.HUD_GREEN
	UITheme.style_paper_progress(_progress_bar, fill)
	_percent.add_theme_color_override("font_color", fill)


## Same value range, but snaps. Use when jumping states (respawn, reload).
func set_progress_immediate(value: float) -> void:
	_build()
	_progress = clampf(value, 0.0, 1.0)
	if _progress_tween != null and _progress_tween.is_valid():
		_progress_tween.kill()
	_apply_progress(_progress)


func progress() -> float:
	return _progress


## The objective line. Defaults to the whole objective rather than a verb,
## because a checklist item reads better than a status light.
func set_status(value: String) -> void:
	_build()
	_status.text = value.to_upper()


# ==================================================================== fuel

## Expects 0.0 - 1.0. Colours itself amber / red as it runs down.
func set_fuel(value: float) -> void:
	_build()
	var target := clampf(value, 0.0, 1.0)
	if is_equal_approx(target, _fuel):
		return
	var was_low := _low_fuel
	_fuel = target
	_fuel_percent.text = UITheme.percent_text(target)
	if _fuel_tween != null and _fuel_tween.is_valid():
		_fuel_tween.kill()
	_fuel_tween = create_tween()
	_fuel_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_fuel_tween.tween_property(_fuel_bar, "value", target, bar_tween_time)
	_style_fuel(target)

	_low_fuel = target <= low_fuel_threshold
	if _low_fuel and not was_low:
		low_fuel_entered.emit()
	elif was_low and not _low_fuel:
		low_fuel_exited.emit()


func fuel() -> float:
	return _fuel


# ============================================================== read-backs
##
## WHAT THE HUD IS CURRENTLY SHOWING, as text.
##
## These exist because `Flow Test` used to reach into the scene for
## `%JobName` and read its `.text`, and when the layout moved into code
## those unique names went with the scene that held them. A test that
## walks a component's node paths is a test that breaks every time the
## component is laid out again, which is exactly what happened.
##
## So the component answers instead. The host sets a value, the HUD
## renders it, and anything that wants to know what is on screen asks
## for it by name rather than by path.

func job_name_text() -> String:
	_build()
	return _job_name.text


func reward_text() -> String:
	_build()
	return _reward.text


func game_time_text() -> String:
	_build()
	return _time.text


func weather_text() -> String:
	_build()
	return _weather.text


# ============================================================ environment

## Already-formatted clock text, e.g. "09:41". The HUD does not simulate
## time; UITheme.format_clock() is available if the host has raw seconds.
func set_game_time(value: String) -> void:
	_build()
	_time.text = value


func set_weather(value: String) -> void:
	_build()
	_weather.text = value
	# The mark follows the word. Nothing is communicated by the mark ALONE.
	var lower := value.to_lower()
	if lower.contains("rain") or lower.contains("storm"):
		_weather_glyph.set_kind(UIGlyph.Kind.RAIN)
	elif lower.contains("fog") or lower.contains("cloud") or lower.contains("overcast"):
		_weather_glyph.set_kind(UIGlyph.Kind.CLOUD)
	else:
		_weather_glyph.set_kind(UIGlyph.Kind.SUN)


func set_day(value: String) -> void:
	_build()
	_day.text = value
	_day.visible = not value.is_empty()


# ============================================================= visibility

func show_hud() -> void:
	_build()
	visible = true
	var t := create_tween()
	t.tween_property(self, "modulate:a", 1.0, UITheme.FADE)


func hide_hud() -> void:
	var t := create_tween()
	t.tween_property(self, "modulate:a", 0.0, UITheme.FADE)
	t.tween_callback(func() -> void: visible = false)


func is_hud_visible() -> bool:
	return visible and modulate.a > 0.01


func set_pause_hint_visible(value: bool) -> void:
	_build()
	_pause_hint.visible = value


# ================================================================ internal

func _apply_progress(value: float) -> void:
	_progress_bar.value = value
	_percent.text = UITheme.percent_text(value)


func _apply_fuel(value: float) -> void:
	_fuel_bar.value = value
	_fuel_percent.text = UITheme.percent_text(value)
	_style_fuel(value)


## THE ONE PLACE ORANGE APPEARS on this HUD. A gauge that is merely low is
## amber; a gauge that is about to strand the player is red, and both change
## the CAPTION as well as the colour.
func _style_fuel(value: float) -> void:
	var colour := UITheme.HUD_GREEN
	var caption := "FUEL"
	if value <= critical_fuel_threshold:
		colour = UITheme.URGENT
		caption = "FUEL CRITICAL"
	elif value <= low_fuel_threshold:
		colour = UITheme.ORANGE
		caption = "FUEL LOW"
	UITheme.style_paper_progress(_fuel_bar, colour)
	_fuel_caption.text = caption
	_fuel_glyph.set_colour(colour)
	var normal := colour == UITheme.HUD_GREEN
	_fuel_caption.add_theme_color_override("font_color",
		UITheme.PAPER_INK_DIM if normal else colour)
	_fuel_percent.add_theme_color_override("font_color",
		UITheme.PAPER_INK if normal else colour)


## 20736 -> "20,736". Thousands separators, because a bare five-digit number is
## not something a player parses at a glance.
static func _grouped(value: int) -> String:
	var digits := str(absi(value))
	var out := ""
	var count := 0
	for i in range(digits.length() - 1, -1, -1):
		out = digits[i] + out
		count += 1
		if count % 3 == 0 and i > 0:
			out = "," + out
	return ("-" if value < 0 else "") + out
