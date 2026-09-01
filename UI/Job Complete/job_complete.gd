extends Control
class_name JobCompleteScreen

# ============================================================
# PUBLIC API
# ============================================================
#
# Host project should call:
#
#   show_results(
#       customer_name: String,      # "A Residence"
#       completion: float,          # 0.0 - 1.0  (1.0 = 100%)
#       elapsed_seconds: float,     # 522.0 -> shown as "08:42"
#       base_pay: int,              # 240
#       bonus: int = 0)             # 25; the Bonus row hides when 0
#
#   hide_results()
#   is_open() -> bool
#   finish_animation()              # snap the entrance / count-up to its end
#   set_button_text(value: String)  # default "RETURN TO TOWN"
#
# Signals emitted:
#
#   return_to_town_requested        # the button was pressed
#   results_shown                   # entrance animation finished
#
# NORMALISATION: completion is 0.0 -> 1.0, NOT 0 -> 100.
# elapsed_seconds is raw seconds; the screen formats it itself.
# base_pay / bonus are whole currency units and are formatted as money.
#
# ============================================================
# SCENE / RESOURCE REFERENCES
# ============================================================
#
# This script preloads nothing.
#
# Job Complete.tscn references exactly one external resource:
#
#   res://UI/Theme/Game UI.theme.tres   (root node theme property)
#
# If that path changes after copying, update it HERE (root node of the
# scene). No other component, scene or script is referenced.
#
# ============================================================
# HOST INTEGRATION NOTES
# ============================================================
#
# Presentation only. This screen does NOT:
#   - complete the job in any job system
#   - pay the player or touch any economy
#   - change scene when the button is pressed
#
# It emits return_to_town_requested and stops there. The host decides
# what returning to town means (usually: fade out, swap scenes, fade in).
#
# Typical wiring in the host:
#
#   results.return_to_town_requested.connect(_on_return_to_town)
#   results.show_results(job.customer_name, 1.0, job.elapsed, job.pay, tip)
#
# The bonus row is optional presentation. Pass 0 (the default) if the
# production game has no bonus concept - the row and its rule disappear
# and the layout closes up.
#
# The root is a full-rect Control with mouse_filter STOP: while it is
# open it swallows clicks so they cannot reach gameplay behind it. The
# scrim is deliberately partial alpha so the finished lawn stays visible.
#
# PAUSING: process_mode is ALWAYS, so the screen still animates if the
# host has paused the tree. It never pauses or unpauses anything itself.
#
# ============================================================


signal return_to_town_requested()
## The player chose to drive straight to the next contract on the day's list
## instead of going back to the yard. The host decides what that means; this
## screen emits it and stops, exactly as it does for the button above.
signal next_stop_requested()
signal results_shown()

## How wide a wrapped line on the card is. The card's own column is 452 across.
const TEXT_MEASURE: int = 452

## Seconds the total spends counting up. Short on purpose.
@export var count_up_time: float = 0.55
## Seconds for the card to fade and slide into place.
@export var entrance_time: float = 0.30
## How far the card slides up during the entrance, in pixels.
@export var entrance_slide: float = 26.0

## The centring wrapper, not the card itself: the card is laid out by a
## CenterContainer, so its position would be overwritten every frame. The
## wrapper is a plain anchored Control, so it is safe to slide.
@onready var _holder: Control = %CardHolder
@onready var _customer: Label = %CustomerName
@onready var _completion_value: Label = %CompletionValue
@onready var _completion_bar: ProgressBar = %CompletionBar
@onready var _time_value: Label = %TimeValue
@onready var _base_value: Label = %BasePayValue
@onready var _bonus_row: HBoxContainer = %BonusRow
@onready var _bonus_value: Label = %BonusValue
@onready var _total_value: Label = %TotalValue
@onready var _button: Button = %ReturnButton

## THE MEASURED STATISTICS. Built in code rather than authored into the scene,
## because every one of them is a reading a system already keeps and the scene
## predates all of them. Cleared and rebuilt per contract.
var _extra_rows: Array[Control] = []
var _column: VBoxContainer = null
## The review: a rating, the customer's line, and what it did to the business.
var _review_block: Array[Control] = []

var _open: bool = false
var _total: int = 0
var _completion_target: float = 0.0
var _tween: Tween


func _ready() -> void:
	visible = false
	modulate.a = 0.0
	mouse_filter = Control.MOUSE_FILTER_STOP
	_button.pressed.connect(func() -> void: return_to_town_requested.emit())
	# THE RESULTS SHEET IS PAPER, for the same reason the job board's offers are:
	# what the player is looking at is the finished work order. Repainted rather
	# than rebuilt - the layout was already right.
	var card := _holder.get_node_or_null(^"Card") as Control
	_column = card.find_child("Column", true, false) as VBoxContainer if card != null else null
	if card != null:
		UITheme.repaint_to_paper(card)
		card.add_theme_stylebox_override("panel",
			UITheme.hud_panel(UITheme.RADIUS_PANEL, 0.0, 0.0))
		var title := card.find_child("Title", true, false) as Label
		if title != null:
			title.add_theme_color_override("font_color", UITheme.HUD_GREEN)
		var accent := card.find_child("AccentBar", true, false) as ColorRect
		if accent != null:
			accent.color = UITheme.ORANGE


func _gui_input(event: InputEvent) -> void:
	# Clicking anywhere while the numbers are still rolling snaps them to
	# the final values, so the screen never feels like it is holding you up.
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		finish_animation()


# =================================================================== display

func show_results(customer_name: String, completion: float,
		elapsed_seconds: float, base_pay: int, bonus: int = 0) -> void:
	_customer.text = customer_name.to_upper()
	_completion_value.text = UITheme.percent_text(completion)
	_time_value.text = UITheme.format_clock(elapsed_seconds)
	_base_value.text = UITheme.format_money(base_pay)
	_bonus_value.text = UITheme.format_money(bonus)
	_bonus_row.visible = bonus != 0
	_total = base_pay + bonus
	_total_value.text = UITheme.format_money(0)

	# A full clean sweep gets the bright accent; anything less stays calm.
	_completion_target = clampf(completion, 0.0, 1.0)
	UITheme.style_progress(_completion_bar,
		UITheme.ACCENT_BRIGHT if _completion_target >= 1.0 else UITheme.ACCENT)
	_completion_bar.value = 0.0

	_open = true
	visible = true
	_animate_in(_completion_target)


## ---------------------------------------------------------------------------
## THE REST OF THE STORY
## ---------------------------------------------------------------------------
## `show_results()` is unchanged and still takes the five things it always did.
## Everything below is ADDITIVE: a host that knows nothing about clippings, terms
## or reviews calls the old function and gets the old card.
##
## `summary` is `GameSession.job_settled`'s dictionary. Only keys that are
## actually present produce a line - nothing here invents a statistic, and a
## contract with no terms and no clippings shows the card it always showed.
func show_details(summary: Dictionary) -> void:
	_clear_details()
	if _column == null:
		return

	# --- what the machine did on this property ---
	var collected := float(summary.get("collected_kg", 0.0))
	var spilled := float(summary.get("spilled_kg", 0.0))
	var fuel_used := float(summary.get("fuel_used", 0.0))
	var auto_cells := int(summary.get("autonomous_cells", 0))

	if collected > 0.0 or spilled > 0.0:
		var value := int(floor(collected * Clippings.fresh_price_per_kg()))
		_detail_row("Clippings collected", "%s   -   worth about %s" % [
			ACAClippings.format_kg(collected), UITheme.format_money(value)],
			UITheme.MONEY)
		if spilled > 1.0:
			# NOT A PENALTY, A READING. It is the reason a collection term was
			# missed, and without it the player has no way to know why.
			_detail_row("Left on the lawn", ACAClippings.format_kg(spilled),
				UITheme.WARN)
	if fuel_used > 0.0:
		_detail_row("Fuel used", "%.0f units   -   about %s" % [fuel_used,
			UITheme.format_money(Economy.fuel_cost_for_units(fuel_used))],
			UITheme.INK_DIM)
	if auto_cells > 0:
		var who := String(summary.get("autonomous_name", "The autonomous machine"))
		_detail_row(who, "%d square metres of it" % auto_cells, UITheme.ACCENT_BRIGHT)

	# --- what the customer asked for ---
	var met := int(summary.get("terms_met", 0))
	var missed := int(summary.get("terms_missed", 0))
	if (met | missed) != 0:
		_detail_gap(8)
		_line("TermsHeading", "WHAT THE CUSTOMER ASKED FOR",
			UITheme.FONT_MICRO, UITheme.INK_FAINT)
	for flag: int in [int(ACAContractTerms.Flag.COLLECT),
			int(ACAContractTerms.Flag.ON_TIME),
			int(ACAContractTerms.Flag.NO_DRY_TANK),
			int(ACAContractTerms.Flag.PATTERN),
			int(ACAContractTerms.Flag.CONSERVE)]:
		var name := ACAContractTerms.flag_name(flag)
		if met & flag:
			_detail_row(name, "met", UITheme.ACCENT_BRIGHT)
		elif missed & flag:
			_detail_row(name, "not met", UITheme.URGENT)

	# --- HOW IT WAS DONE, and what the ground was like while it was.
	_show_finish(summary)
	_show_conservation(summary)
	_show_workmanship(summary)
	_show_transformation(summary)

	# --- the review ---
	var stars := int(summary.get("review_stars", 0))
	if stars > 0:
		_review(summary, stars)

	# A SHEET WITH MORE TO SAY SAYS IT CLOSER TOGETHER. The card's own spacing
	# was composed for five figures; with the clippings, the fuel, the escort,
	# three scored terms and a review on it, that spacing puts a Large contract's
	# results 734 px tall - fourteen past the bottom of a 1280x720 window.
	# Measured by `Card Layout Probe`, which is what found it.
	if not _extra_rows.is_empty():
		_compact_spacing(true)


## ---------------------------------------------------------------------------
## THE THREE THINGS THIS EXPANSION ADDED TO A RESULTS SHEET
## ---------------------------------------------------------------------------
## Each of them prints ONLY when it applies, which on an ordinary contract is
## none of them - the sheet a player saw before this pass is the sheet they see
## after it unless something new actually happened on the property.

## HOW IT WAS CUT, and what the ground was doing while it was. Always shown,
## because both are true of every contract and both are things the player chose
## or planned around.
func _show_finish(summary: Dictionary) -> void:
	var machine := String(summary.get("machine_name", ""))
	var mode := String(summary.get("mode_name", ""))
	var ground := String(summary.get("ground_name", ""))
	if machine.is_empty() and mode.is_empty():
		return
	_detail_gap(8)
	_line("HowHeading", "HOW IT WAS DONE", UITheme.FONT_MICRO, UITheme.INK_FAINT)
	if not machine.is_empty():
		_detail_row("Machine", machine, UITheme.INK_DIM)
	if not mode.is_empty():
		_detail_row("Configuration", mode, UITheme.INK_DIM)
	if not ground.is_empty():
		_detail_row("Ground", ground, UITheme.INK_DIM)

	# THE REQUESTED FINISH, scored. The verdict is already in the terms above;
	# this is the measurement behind it, which is what lets a player who missed
	# it understand why.
	var pattern := int(summary.get("pattern", ACAFinishPattern.Pattern.NONE))
	if pattern == ACAFinishPattern.Pattern.NONE:
		return
	var met := bool(summary.get("pattern_met", false))
	_detail_row(ACAFinishPattern.pattern_name(pattern),
		ACAFinishPattern.result_line({
			"pattern": pattern, "met": met,
			"share": summary.get("pattern_share", 0.0),
			"note": summary.get("pattern_note", ""),
		}), UITheme.ACCENT_BRIGHT if met else UITheme.WARN)


## PROTECTED PLANTING, and only on a property that had some.
func _show_conservation(summary: Dictionary) -> void:
	if int(summary.get("protected_cells", 0)) <= 0:
		return
	var damage := float(summary.get("protected_damage", 0.0))
	var percent := int(round(damage * 100.0))
	if damage <= ACAContractTerms.CONSERVATION_TOLERANCE:
		_detail_row("Protected planting",
			"left alone" if percent <= 0 else "%d%% clipped - within tolerance" % percent,
			UITheme.ACCENT_BRIGHT)
	else:
		_detail_row("Protected planting", "%d%% of it was cut" % percent,
			UITheme.URGENT)


## HOW WELL IT WAS DRIVEN. Recognition, not scoring.
##
## Two readings the cutter took while it was cutting - how much of the ground
## the deck passed over was standing grass, and how many times the machine
## touched something solid. Neither is a term of the contract, neither is paid,
## and neither is ever shown as a failure: an ordinary job simply says nothing
## here, and a well driven one gets a line.
##
## That is deliberate. The point is to notice good work, not to grade every
## contract - a player who is enjoying mowing badly is still enjoying mowing.

## BOTH SET FROM MEASURED DRIVING, not from a number that sounded about right.
## `Dev tools/Validation/Workmanship Probe.tscn` drives real machines over a
## real property in a clean parallel pattern and then over the same strip
## repeatedly:
##
##     machine   tidy    re-covering the same strip
##     rider     0.85    0.57
##     push      0.96    0.39
##
## CLEAN PASSES sits above the worst deliberately sloppy run and well below the
## worst tidy one. LOW OVERLAP sits just under the best tidy run, so it means
## something.
##
## THE CALIBRATION IS FROM PARTIAL RUNS, five lanes rather than a whole lawn. A
## finished contract will read LOWER than these, because the last of a job is
## spent hunting the patches that were missed, and that travel is over ground
## already cut. That direction is the safe one: it makes a callout rarer, and
## the only thing a callout ever does is say something encouraging.
const CLEAN_PASSES_COVERAGE := 0.62
## The stricter one. A tidy route with almost no ground taken twice.
const LOW_OVERLAP_COVERAGE := 0.80

func _show_workmanship(summary: Dictionary) -> void:
	var coverage := float(summary.get("coverage", 0.0))
	var contacts := int(summary.get("contacts", 0))
	# Nothing was measured - a contract finished from a development shortcut, or
	# an older save's summary. Say nothing rather than praising a job that was
	# never driven.
	if coverage <= 0.0:
		return

	var callouts := PackedStringArray()
	if coverage >= LOW_OVERLAP_COVERAGE:
		callouts.append("LOW OVERLAP")
	elif coverage >= CLEAN_PASSES_COVERAGE:
		callouts.append("CLEAN PASSES")
	if contacts == 0:
		callouts.append("PRECISION FINISH")
	if callouts.is_empty():
		return

	_detail_gap(8)
	_line("WorkmanshipHeading", "HOW IT WAS DRIVEN", UITheme.FONT_MICRO,
		UITheme.INK_FAINT)
	for callout in callouts:
		_detail_row(callout, _workmanship_note(callout, coverage),
			UITheme.ACCENT_BRIGHT)


static func _workmanship_note(callout: String, coverage: float) -> String:
	match callout:
		"LOW OVERLAP":
			return "%d%% of your passes were on standing grass" \
				% int(round(coverage * 100.0))
		"CLEAN PASSES":
			return "%d%% of your passes were on standing grass" \
				% int(round(coverage * 100.0))
		"PRECISION FINISH":
			return "you did not touch a thing on the property"
	return ""


## THE PROPERTY MOVED ON, and only when the business's work is what moved it.
## This is the payoff of a recovery contract and it is worth its own line.
func _show_transformation(summary: Dictionary) -> void:
	if int(summary.get("condition_stage_change", 0)) <= 0:
		return
	var after := int(summary.get("condition_stage_after",
		ACAPropertyCondition.Stage.MAINTAINED))
	_detail_gap(6)
	var premium := int(summary.get("recovery_premium", 0))
	if premium > 0:
		_detail_row("Recovery premium", UITheme.format_money(premium), UITheme.MONEY)
	_detail_row("The property is now",
		ACAPropertyCondition.stage_name(after).to_lower(), UITheme.ACCENT_BRIGHT)
	var note := _wrapped(ACAPropertyCondition.stage_note(after),
		UITheme.FONT_MICRO, UITheme.INK_FAINT)
	_attach(note)


## THE DAY IS A ROUTE. When the business has another contract open that the
## player could drive straight to, the sheet offers it - and taking it keeps the
## tank, the catcher, the trailer's load and the loadout exactly as they are.
func show_next_stop(site_name: String) -> void:
	if _next_button != null and is_instance_valid(_next_button):
		_next_button.queue_free()
		_next_button = null
	if site_name.is_empty():
		return
	_next_button = Button.new()
	_next_button.name = "NextStopButton"
	_next_button.text = "STRAIGHT ON TO %s" % site_name.to_upper()
	UITheme.style_button(_next_button, false, 46.0)
	_next_button.pressed.connect(func() -> void: next_stop_requested.emit())
	_attach(_next_button)
	_extra_rows.append(_next_button)


var _next_button: Button = null


## The customer's rating and their line, then what it did to the business.
func _review(summary: Dictionary, stars: int) -> void:
	_detail_gap(10)
	_detail_rule()
	_detail_gap(8)

	var rating := _line("Rating", "%s   %d / 5" % [_star_marks(stars), stars],
		UITheme.FONT_BODY, UITheme.WARN)
	_review_block.append(rating)

	var text := String(summary.get("review_text", ""))
	if not text.is_empty():
		_review_block.append(_wrapped(text, UITheme.FONT_META, UITheme.INK_DIM))

	var change := float(summary.get("reputation_change", 0.0))
	var reputation := float(summary.get("reputation", 0.0))
	_detail_row("Reputation", "%d / 100   (%+.1f)" % [int(round(reputation)), change],
		UITheme.ACCENT_BRIGHT if change >= 0.0 else UITheme.URGENT)

	var services := int(summary.get("services", 0))
	if services > 1:
		_detail_row("Repeat customer", "%d visits   -   loyalty %d" % [
			services, int(round(float(summary.get("loyalty", 0.0))))],
			UITheme.ACCENT_BRIGHT)
	elif services == 1:
		_detail_row("New customer", "on the books now", UITheme.INK_DIM)


## Filled and empty marks with the number always beside them - nothing on this
## card is ever said by a symbol alone.
static func _star_marks(stars: int) -> String:
	var out := ""
	for i in 5:
		out += "*" if i < stars else "."
	return out


func _clear_details() -> void:
	for row in _extra_rows + _review_block:
		if is_instance_valid(row):
			row.queue_free()
	_extra_rows.clear()
	_review_block.clear()
	_compact_spacing(false)


## The card's authored gaps, and what they become on a full sheet. Applied to
## the SCENE's own gap nodes rather than by rebuilding the card, so the layout
## the screen was composed with is still the layout, just tighter.
const GAP_SIZES := {
	"TitleGap": [14, 10],
	"StatsGap": [22, 14],
	"PayGap": [20, 12],
	"BonusGap": [10, 7],
	"TotalGap": [14, 10],
	"ButtonGap": [26, 24],
}


func _compact_spacing(compact: bool) -> void:
	if _column == null:
		return
	for gap_name: String in GAP_SIZES:
		var gap := _column.get_node_or_null(NodePath(gap_name)) as Control
		if gap == null:
			continue
		var sizes: Array = GAP_SIZES[gap_name]
		gap.custom_minimum_size = Vector2(0, float(sizes[1 if compact else 0]))


## One key/value line, in the same form as the rows the scene already has.
func _detail_row(key: String, value: String, colour: Color) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var k := UITheme.label(row, "Key", key, UITheme.FONT_LABEL, UITheme.INK_DIM)
	k.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UITheme.label(row, "Value", value, UITheme.FONT_LABEL, colour)
	_attach(row)
	# The card is repainted to paper in `_ready()`, which has already happened,
	# so anything added afterwards has to be repainted on its own.
	UITheme.repaint_to_paper(row)


func _line(node_name: String, text: String, size: int, colour: Color) -> Label:
	var label := Label.new()
	label.name = node_name
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", colour)
	_attach(label)
	label.text = text
	return label


## A wrapped line. Built EMPTY and filled after it is in the tree and has been
## given a measure: a wrapped Label sizes its height from the width it had when
## its text was set, and one created with its text already in it reports a
## minimum height of one line per character.
func _wrapped(text: String, size: int, colour: Color) -> Label:
	var label := Label.new()
	label.name = "Wrapped"
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", colour)
	label.custom_minimum_size = Vector2(TEXT_MEASURE, 0)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_attach(label)
	label.text = text
	return label


func _detail_gap(height: int) -> void:
	var gap := Control.new()
	gap.name = "DetailGap"
	gap.custom_minimum_size = Vector2(0, height)
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_attach(gap)


func _detail_rule() -> void:
	var rule := ColorRect.new()
	rule.name = "DetailRule"
	rule.color = UITheme.PAPER_RULE
	rule.custom_minimum_size = Vector2(0, 1)
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_attach(rule)


## Add a line to the card, above the RETURN button. Everything the scene already
## had keeps its order; the new lines go between the totals and the button.
func _attach(control: Control) -> void:
	_column.add_child(control)
	_extra_rows.append(control)
	var button_parent := _button.get_parent()
	if button_parent == _column:
		_column.move_child(_button, _column.get_child_count() - 1)
	else:
		var holder := button_parent as Control
		while holder != null and holder.get_parent() != _column:
			holder = holder.get_parent() as Control
		if holder != null:
			_column.move_child(holder, _column.get_child_count() - 1)


func hide_results() -> void:
	if not _open:
		return
	_open = false
	_kill_tween()
	_tween = create_tween()
	_tween.tween_property(self, "modulate:a", 0.0, UITheme.FADE)
	_tween.tween_callback(func() -> void: visible = false)


func is_open() -> bool:
	return _open


func set_button_text(value: String) -> void:
	_button.text = value


## Jump the entrance, the bar and the count-up straight to their end state.
func finish_animation() -> void:
	if not _open:
		return
	_kill_tween()
	modulate.a = 1.0
	_holder.position.y = 0.0
	_completion_bar.value = _completion_target
	_total_value.text = UITheme.format_money(_total)
	_button.grab_focus()


# ================================================================= internals

func _animate_in(completion: float) -> void:
	_kill_tween()
	modulate.a = 0.0
	_holder.position.y = entrance_slide

	_tween = create_tween()
	_tween.set_parallel(true)
	_tween.tween_property(self, "modulate:a", 1.0, entrance_time)
	_tween.tween_property(_holder, "position:y", 0.0, entrance_time) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

	# Bar sweep and money count-up start together, just after the card lands.
	_tween.tween_property(_completion_bar, "value", completion, 0.45) \
		.set_delay(entrance_time * 0.6) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_tween.tween_method(_set_total_display, 0, _total, count_up_time) \
		.set_delay(entrance_time * 0.6) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

	_tween.set_parallel(false)
	_tween.tween_callback(func() -> void:
		_button.grab_focus()
		results_shown.emit())


func _set_total_display(value: int) -> void:
	_total_value.text = UITheme.format_money(value)


func _kill_tween() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
