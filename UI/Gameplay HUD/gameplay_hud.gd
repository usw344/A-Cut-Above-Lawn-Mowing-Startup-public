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
#   set_reward(value: int)               # 240  -> renders "$240"
#
#   set_progress(value: float)           # 0.0 - 1.0  (animated)
#   set_progress_immediate(value: float) # 0.0 - 1.0  (no tween)
#   set_fuel(value: float)               # 0.0 - 1.0  (animated)
#   set_status(value: String)            # "MOWING" / "TRIMMING" / ...
#
#   set_game_time(value: String)         # "09:41" - already formatted
#   set_weather(value: String)           # "Clear"
#
#   show_hud()                           # fade in
#   hide_hud()                           # fade out
#   is_hud_visible() -> bool
#
#   set_pause_hint_visible(value: bool)  # hide the ESC chip if the host
#                                        # has no pause, or on gamepad
#
# Read-back helpers (useful for demos / debug overlays):
#
#   progress() -> float
#   fuel() -> float
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
# SCENE / RESOURCE REFERENCES
# ============================================================
#
# This script preloads nothing.
#
# Gameplay HUD.tscn references exactly one external resource:
#
#   res://UI/Theme/Game UI.theme.tres   (root node theme property)
#
# If that path changes after copying the component into another project,
# update it HERE - reassign the theme on the root node of the scene, or
# clear it and the HUD falls back to the engine default theme (it will
# still lay out correctly, it will just look generic).
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
# Typical wiring in the host:
#
#   @onready var hud: GameplayHUD = $HUD/GameplayHUD
#
#   func _ready() -> void:
#       hud.pause_requested.connect(_on_pause_requested)
#       hud.set_job_name(job.customer_name)
#       hud.set_job_size(job.size_label)
#       hud.set_reward(job.payout)
#       hud.show_hud()
#
#   func _process(_delta: float) -> void:
#       hud.set_progress(lawn.mowed_fraction())   # 0.0 - 1.0
#       hud.set_fuel(mower.fuel_fraction())       # 0.0 - 1.0
#       hud.set_game_time(clock.display_text())
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

@onready var _job_name: Label = %JobName
@onready var _job_size: Label = %JobSize
@onready var _status: Label = %StatusCaption
@onready var _percent: Label = %ProgressPercent
@onready var _progress_bar: ProgressBar = %ProgressBar
@onready var _reward: Label = %RewardValue
@onready var _time: Label = %TimeValue
@onready var _weather: Label = %WeatherValue
@onready var _fuel_caption: Label = %FuelCaption
@onready var _fuel_percent: Label = %FuelPercent
@onready var _fuel_bar: ProgressBar = %FuelBar
@onready var _pause_hint: Button = %PauseHint

var _progress: float = 0.0
var _fuel: float = 1.0
var _low_fuel: bool = false
var _progress_tween: Tween
var _fuel_tween: Tween


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pause_hint.pressed.connect(func() -> void: pause_requested.emit())
	_apply_progress(_progress)
	_apply_fuel(_fuel)


# ============================================================ job identity

func set_job_name(value: String) -> void:
	_job_name.text = value.to_upper()


func set_job_size(value: String) -> void:
	_job_size.text = value
	_job_size.visible = not value.is_empty()


## Contract value in whole currency units. 240 renders as "$240".
func set_reward(value: int) -> void:
	_reward.text = UITheme.format_money(value)


# ================================================================ progress

## Expects 0.0 - 1.0. Animates the bar; safe to call every frame.
func set_progress(value: float) -> void:
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
	var fill := UITheme.ACCENT_BRIGHT if target >= 1.0 else UITheme.ACCENT
	UITheme.style_progress(_progress_bar, fill)


## Same value range, but snaps. Use when jumping states (respawn, reload).
func set_progress_immediate(value: float) -> void:
	_progress = clampf(value, 0.0, 1.0)
	if _progress_tween != null and _progress_tween.is_valid():
		_progress_tween.kill()
	_apply_progress(_progress)


func progress() -> float:
	return _progress


## The caption above the progress bar. Defaults to "MOWING".
func set_status(value: String) -> void:
	_status.text = value.to_upper()


# ==================================================================== fuel

## Expects 0.0 - 1.0. Colours itself amber / red as it runs down.
func set_fuel(value: float) -> void:
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


# ============================================================ environment

## Already-formatted clock text, e.g. "09:41". The HUD does not simulate
## time; UITheme.format_clock() is available if the host has raw seconds.
func set_game_time(value: String) -> void:
	_time.text = value


func set_weather(value: String) -> void:
	_weather.text = value


# ============================================================= visibility

func show_hud() -> void:
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
	_pause_hint.visible = value


# ================================================================ internal

func _apply_progress(value: float) -> void:
	_progress_bar.value = value
	_percent.text = UITheme.percent_text(value)


func _apply_fuel(value: float) -> void:
	_fuel_bar.value = value
	_fuel_percent.text = UITheme.percent_text(value)
	_style_fuel(value)


func _style_fuel(value: float) -> void:
	var colour := UITheme.ACCENT
	var caption := "FUEL"
	if value <= critical_fuel_threshold:
		colour = UITheme.URGENT
		caption = "FUEL CRITICAL"
	elif value <= low_fuel_threshold:
		colour = UITheme.WARN
		caption = "FUEL LOW"
	UITheme.style_progress(_fuel_bar, colour)
	_fuel_caption.text = caption
	_fuel_caption.add_theme_color_override("font_color",
		UITheme.INK_FAINT if colour == UITheme.ACCENT else colour)
	_fuel_percent.add_theme_color_override("font_color",
		UITheme.INK_DIM if colour == UITheme.ACCENT else colour)
