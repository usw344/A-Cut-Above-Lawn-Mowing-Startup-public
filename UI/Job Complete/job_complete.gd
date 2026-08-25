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
signal results_shown()

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
