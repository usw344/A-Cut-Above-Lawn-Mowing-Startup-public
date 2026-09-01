extends Control
class_name JobIntroScreen

# ============================================================
# PUBLIC API
# ============================================================
#
# Host project should call:
#
#   show_job(
#       job_name: String,          # "A Residence"
#       job_size: String,          # "Medium Lawn"
#       reward: int,               # 240 -> "$240"
#       estimated_minutes: int)    # 12  -> "12 min"
#
#   set_contract_type(value: String)   # "Residential Contract"
#   set_site_notes(value: String)      # "A pond and six obstacles."
#   set_status(value: String)          # "PREPARING EQUIPMENT..."
#
#   show_intro()
#   hide_intro()
#   is_open() -> bool
#
# show_job() fills in the text AND shows the screen. Call show_intro()
# on its own only when re-showing an already-populated intro.
#
# Signals emitted:
#
#   intro_shown      # entrance animation finished
#   intro_hidden     # exit animation finished - safe to start gameplay
#
# ============================================================
# SCENE / RESOURCE REFERENCES
# ============================================================
#
# This script preloads nothing.
#
# Job Intro.tscn references exactly one external resource:
#
#   res://UI/Theme/Game UI.theme.tres   (root node theme property)
#
# If that path changes after copying, update it HERE (root node of the
# scene).
#
# ============================================================
# HOST INTEGRATION NOTES
# ============================================================
#
# Two jobs in one component:
#
#   1. Contract introduction - what the player just accepted.
#   2. Loading mask - the background is opaque, so the host can build,
#      move or stream the job scene behind it without it being seen.
#
# THERE IS NO LOADING INFRASTRUCTURE HERE. This screen does not call
# ResourceLoader, does not track progress and does not know what a scene
# is. set_status() is a plain text setter; the host writes whatever its
# real loading step is, then calls hide_intro() when the work is done.
#
# Typical use:
#
#   intro.show_job(job.customer_name, job.size_label, job.pay, job.minutes)
#   intro.set_status("PREPARING EQUIPMENT...")
#   await build_the_lawn()
#   intro.set_status("READY")
#   intro.hide_intro()
#
# The root is a full-rect Control with mouse_filter STOP, so it swallows
# clicks while it is up. process_mode is ALWAYS.
#
# The status line breathes gently while the screen is open, as a sign of
# life during a load. Set animate_status = false in the inspector to make
# it a plain static label.
#
# ============================================================


signal intro_shown()
signal intro_hidden()

## The sheet's padding, in pixels. Horizontal is wider than vertical because the
## sheet is a portrait block of text: the eye reads the side margins as the page
## and the top/bottom ones as the space above and below a paragraph.
const PAD_H: int = 44
const PAD_V: int = 34
## How wide the text column is. The sheet is this plus twice `PAD_H`.
const TEXT_MEASURE: int = 520

## Seconds for the screen to fade in / out.
@export var fade_time: float = 0.32
## Pixels the content block rises through on entrance.
@export var entrance_slide: float = 20.0
## The status line fades between 0.45 and 1.0 alpha while open.
@export var animate_status: bool = true

@onready var _holder: Control = %CardHolder
@onready var _contract_type: Label = %ContractType
@onready var _job_name: Label = %JobName
@onready var _job_size: Label = %JobSize
@onready var _time_value: Label = %EstimatedTimeValue
@onready var _reward_value: Label = %ContractValue
@onready var _status: Label = %StatusLabel

## Built in `_become_a_work_order()` rather than by the scene.
var _site_notes: Label = null
## The breathing space above the site line. Hidden with it, so an empty line
## does not leave a gap where a line used to be.
var _notes_gap: Control = null
## WHAT THE CONTRACT ASKS FOR, one line each, under the two figures. Built here
## rather than in the scene for the same reason the site line is: the scene
## predates contract terms.
var _term_lines: Array[Label] = []
## The column every line on the sheet is a direct child of.
var _column: Control = null
## What the business put on the trailer. One line, under the requirements.
var _equipment: Label = null
## Breathing space above the block. Hidden when there is nothing in it.
var _requirements_gap: Control = null
## ...and between the requirements and the trailer line.
var _equipment_gap: Control = null

var _open: bool = false
var _tween: Tween
var _status_tween: Tween


func _ready() -> void:
	visible = false
	modulate.a = 0.0
	mouse_filter = Control.MOUSE_FILTER_STOP
	process_mode = Node.PROCESS_MODE_ALWAYS
	_become_a_work_order()


## ---------------------------------------------------------------------------
## THE INTRO IS THE WORK ORDER, NOT A TITLE CARD
## ---------------------------------------------------------------------------
## This screen was cream text floating on a dark scrim - readable, and
## indistinguishable from a loading screen in any other game. What the player is
## actually being shown is the paperwork for the contract they just accepted,
## and the rest of the interface now draws paperwork on paper.
##
## So the existing column is wrapped in a cream sheet and repainted. The LAYOUT
## is untouched: it was already a heading, a rule, two rows and a status line,
## which is what a work order looks like.
func _become_a_work_order() -> void:
	var column := _holder.get_node_or_null(^"Column") as Control
	if column == null or column.get_parent() is MarginContainer:
		return
	var sheet := PanelContainer.new()
	sheet.name = "Sheet"
	# THE PADDING IS A CONTAINER, NOT A STYLEBOX. The first version put the
	# margins on the sheet's own stylebox, and `repaint_to_paper()` - which has
	# to replace that stylebox to change its colour - dropped them on the floor.
	# The card shipped with the heading clipped at the top, the values running
	# off the right edge and the status line cut in half at the bottom. A
	# MarginContainer cannot be repainted away, which is why the results sheet
	# has always used one.
	var pad := MarginContainer.new()
	pad.name = "Pad"
	for side in [&"margin_left", &"margin_right"]:
		pad.add_theme_constant_override(side, PAD_H)
	for side in [&"margin_top", &"margin_bottom"]:
		pad.add_theme_constant_override(side, PAD_V)

	_holder.remove_child(column)
	_holder.add_child(sheet)
	sheet.add_child(pad)
	pad.add_child(column)

	# EVERY WRAPPED LABEL DECLARES THE MEASURE IT WRAPS AT.
	#
	# A Label with `autowrap_mode` set and no minimum width reports a minimum
	# size derived from its CURRENT width, and a CenterContainer sizes itself
	# from its child's minimum. The two chase each other: the label wraps
	# narrower, so it needs to be taller, so the holder grows, and it does not
	# converge. Measured, the card holder came out 3,824 px tall on a Large
	# contract with site notes - the sheet was centred in a rectangle three and
	# a half screens high and drew far below the window.
	#
	# `JobName` was authored with the measure on it, which is why the fault only
	# ever showed on contracts whose property had something worth noting. The
	# site line is a wrapped label too and was added without one.
	column.custom_minimum_size = Vector2(TEXT_MEASURE, 0)
	_job_name.custom_minimum_size = Vector2(TEXT_MEASURE, 0)
	_job_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# A forty-point heading set on the font's default leading reads as three
	# separate lines rather than as one name. Tightened, a three-line contract
	# name holds together as a block.
	_job_name.add_theme_constant_override(&"line_spacing", -6)

	# The site line, for anything the property has on it that is worth knowing
	# before the machine is unloaded. Built here because the scene predates it.
	_site_notes = UITheme.label(column, "SiteNotes", "", UITheme.FONT_LABEL,
		UITheme.PAPER_INK_FAINT, true)
	_site_notes.custom_minimum_size = Vector2(TEXT_MEASURE, 0)
	var notes_gap := Control.new()
	notes_gap.name = "SiteNotesGap"
	notes_gap.custom_minimum_size = Vector2(0, 8)
	notes_gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(notes_gap)
	column.move_child(notes_gap, _job_size.get_index() + 1)
	column.move_child(_site_notes, notes_gap.get_index() + 1)
	notes_gap.visible = false
	_notes_gap = notes_gap
	_site_notes.visible = false

	_build_requirements(column)

	UITheme.repaint_to_paper(sheet)
	# Applied AFTER the repaint, deliberately: the repaint owns the colour, the
	# screen owns the shadow. Zero content margins because `Pad` is the padding.
	sheet.add_theme_stylebox_override("panel",
		UITheme.hud_panel(UITheme.RADIUS_PANEL, 0.0, 0.0))
	# The heading is the one thing on the sheet that is green.
	_job_name.add_theme_color_override("font_color", UITheme.HUD_GREEN)
	_contract_type.add_theme_color_override("font_color", UITheme.PAPER_INK_FAINT)


## THE REQUIREMENTS AND THE TRAILER, between the two figures and the status line.
##
## Placed AFTER the contract-value row and before the bottom rule, because the
## reading order of a work order is: who, what kind of place, what is on it, what
## it pays, what they want doing, and what you brought to do it with.
##
## EVERY LINE IS A DIRECT CHILD OF THE COLUMN, not of a VBoxContainer of its own.
## The first version nested them, and the card holder came out 2,731 px tall on a
## contract with three terms: a wrapped Label reports a minimum height derived
## from its CURRENT width, and inside a nested container that width is measured
## before the outer column has told it how wide it is. The site line has always
## been a direct child for the same reason, and it has always been fine.
func _build_requirements(column: Control) -> void:
	_column = column
	var gap := Control.new()
	gap.name = "RequirementsGap"
	gap.custom_minimum_size = Vector2(0, 14)
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(gap)
	gap.visible = false
	_requirements_gap = gap

	var equipment_gap := Control.new()
	equipment_gap.name = "EquipmentGap"
	equipment_gap.custom_minimum_size = Vector2(0, 8)
	equipment_gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(equipment_gap)
	equipment_gap.visible = false
	_equipment_gap = equipment_gap

	_equipment = UITheme.label(column, "Equipment", "", UITheme.FONT_LABEL,
		UITheme.PAPER_INK_FAINT, true)
	_equipment.custom_minimum_size = Vector2(TEXT_MEASURE, 0)
	_equipment.visible = false
	_reorder_block()


## Put the block back where it belongs in the column: after the contract-value
## row, before the bottom rule. Called whenever a line is added or removed, so
## the order cannot drift as the card is repopulated.
func _reorder_block() -> void:
	if _column == null:
		return
	var order: Array[Control] = []
	if _requirements_gap != null:
		order.append(_requirements_gap)
	order.append_array(_term_lines)
	if _equipment_gap != null:
		order.append(_equipment_gap)
	if _equipment != null:
		order.append(_equipment)
	# PUSH THE BLOCK TO THE END, THEN PUT THE SHEET'S FOOT BACK AFTER IT. Moving
	# each line to a fixed index counted from the bottom rule does not work,
	# because every move shifts the rule; this is order-independent.
	for control in order:
		_column.move_child(control, _column.get_child_count() - 1)
	for foot in ["BottomRuleGap", "BottomRule", "StatusGap", "StatusLabel"]:
		var node := _column.get_node_or_null(NodePath(foot)) as Control
		if node != null:
			_column.move_child(node, _column.get_child_count() - 1)


## What this customer wants beyond a cut lawn. `terms` is
## `ACAContractTerms.describe()`. An empty list hides the whole block, spacing
## and all, so a contract with no terms is exactly the card it always was.
func set_requirements(terms: Array) -> void:
	if _column == null:
		return
	for line in _term_lines:
		if is_instance_valid(line):
			_column.remove_child(line)
			line.queue_free()
	_term_lines.clear()

	if not terms.is_empty():
		_term_lines.append(_measured_line("RequirementsHeading",
			"THE CUSTOMER ASKS", UITheme.FONT_MICRO, UITheme.PAPER_INK_FAINT, false))
		for term: Dictionary in terms:
			var text := String(term["text"])
			var required := bool(term["mandatory"])
			if required:
				text += "  (required)"
			_term_lines.append(_measured_line("Term", text, UITheme.FONT_LABEL,
				UITheme.ORANGE if required else UITheme.PAPER_INK_DIM, true))

	_reorder_block()
	_update_block_visibility()


## What the business brought. Empty hides the line.
func set_equipment_line(value: String) -> void:
	if _equipment == null:
		return
	_equipment.text = value
	_equipment.visible = not value.is_empty()
	_update_block_visibility()


## A LABEL THAT IS TOLD HOW WIDE IT IS BEFORE IT IS GIVEN ANYTHING TO SAY.
##
## The order matters, and it is not obvious. A wrapped Label computes its
## minimum HEIGHT from the width it had when its text was last set - so a label
## created with its text already in it, before anything has told it it is 520 px
## wide, measures itself at nought width and reports a minimum height of one
## line per character. Inside a CenterContainer that minimum is what the whole
## card is centred in, and the card ends up 2,722 px down the screen.
##
## The site line has always been built empty and filled later, which is why it
## never showed this. Every wrapped line on the sheet is built the same way now.
func _measured_line(node_name: String, text: String, size: int,
		colour: Color, wrap: bool) -> Label:
	var line := Label.new()
	line.name = node_name
	line.add_theme_font_size_override("font_size", size)
	line.add_theme_color_override("font_color", colour)
	line.custom_minimum_size = Vector2(TEXT_MEASURE, 0)
	if wrap:
		line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_column.add_child(line)
	line.text = text
	return line


func _update_block_visibility() -> void:
	if _requirements_gap == null:
		return
	_requirements_gap.visible = not _term_lines.is_empty() \
		or (_equipment != null and _equipment.visible)


# ================================================================== content

func show_job(job_name: String, job_size: String, reward: int,
		estimated_minutes: int) -> void:
	_job_name.text = job_name.to_upper()
	_job_size.text = job_size
	_reward_value.text = UITheme.format_money(reward)
	_time_value.text = "%d min" % maxi(estimated_minutes, 0)
	show_intro()


## What the property has standing on it, in one plain sentence. Supplied by the
## host from the GENERATED property rather than from the contract, so it can
## never promise a pond that is not there. Empty hides the line.
func set_site_notes(value: String) -> void:
	if _site_notes == null:
		return
	_site_notes.text = value
	_site_notes.visible = not value.is_empty()
	if _notes_gap != null:
		_notes_gap.visible = _site_notes.visible


## The line above the job name, e.g. "Residential Contract".
func set_contract_type(value: String) -> void:
	_contract_type.text = value.to_upper()
	_contract_type.visible = not value.is_empty()


func set_status(value: String) -> void:
	_status.text = value.to_upper()
	_status.visible = not value.is_empty()


# =============================================================== visibility

func show_intro() -> void:
	if _open:
		return
	_open = true
	visible = true
	_kill()
	_holder.position.y = entrance_slide
	_tween = create_tween()
	_tween.set_parallel(true)
	_tween.tween_property(self, "modulate:a", 1.0, fade_time)
	_tween.tween_property(_holder, "position:y", 0.0, fade_time) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_tween.set_parallel(false)
	_tween.tween_callback(func() -> void: intro_shown.emit())
	_start_status_pulse()


func hide_intro() -> void:
	if not _open:
		return
	_open = false
	_stop_status_pulse()
	_kill()
	_tween = create_tween()
	_tween.tween_property(self, "modulate:a", 0.0, fade_time)
	_tween.tween_callback(func() -> void:
		visible = false
		intro_hidden.emit())


func is_open() -> bool:
	return _open


# ================================================================ internals

func _start_status_pulse() -> void:
	_stop_status_pulse()
	if not animate_status:
		_status.modulate.a = 1.0
		return
	_status_tween = create_tween()
	_status_tween.set_loops()
	_status_tween.tween_property(_status, "modulate:a", 0.45, 0.9) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_status_tween.tween_property(_status, "modulate:a", 1.0, 0.9) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func _stop_status_pulse() -> void:
	if _status_tween != null and _status_tween.is_valid():
		_status_tween.kill()
	_status.modulate.a = 1.0


func _kill() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
