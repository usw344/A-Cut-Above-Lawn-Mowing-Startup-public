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
	if column == null or column.get_parent() is PanelContainer:
		return
	var sheet := PanelContainer.new()
	sheet.name = "Sheet"
	sheet.add_theme_stylebox_override("panel",
		UITheme.hud_panel(UITheme.RADIUS_PANEL, 40.0, 30.0))
	# NO minimum size of its own. The column inside already declares 520, and a
	# sheet narrower than its contents does not shrink them - it lets them hang
	# over both edges, which is exactly what the first attempt did.
	_holder.remove_child(column)
	_holder.add_child(sheet)
	sheet.add_child(column)

	# The site line, for anything the property has on it that is worth knowing
	# before the machine is unloaded. Built here because the scene predates it.
	_site_notes = UITheme.label(column, "SiteNotes", "", UITheme.FONT_LABEL,
		UITheme.PAPER_INK_FAINT, true)
	column.move_child(_site_notes, _job_size.get_index() + 1)
	_site_notes.visible = false

	UITheme.repaint_to_paper(sheet)
	# The heading is the one thing on the sheet that is green.
	_job_name.add_theme_color_override("font_color", UITheme.HUD_GREEN)
	_contract_type.add_theme_color_override("font_color", UITheme.PAPER_INK_FAINT)


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
