class_name ACAJobCard
extends PanelContainer
## One contract row. A pure view: it holds a reference to the job it is showing
## and nothing else. It never mutates job state and never keeps its own copy of
## the job database - ACAJobManager owns all of that.
##
## The same scene serves all three tabs; bind() relabels the rows. That is why
## the action button is generic: BEGIN JOB becomes RETURN TO JOB for a
## partially completed contract without any structural change.

signal accept_pressed(job_id: StringName)
signal action_pressed(job_id: StringName)

enum Mode { AVAILABLE, CURRENT, PAST }

@export var accent_bar: ColorRect
@export var title_label: Label
@export var meta_label: Label
@export var row_a_key: Label
@export var row_a_value: Label
@export var row_b_key: Label
@export var row_b_value: Label
@export var row_c: Control
@export var row_c_key: Label
@export var row_c_value: Label
@export var progress_bar: ProgressBar
@export var footer: Control
@export var footer_label: Label
@export var action_button: Button

var _job: ACAJob
var _mode: int = Mode.AVAILABLE
var _manager: ACAJobManager


func _ready() -> void:
	if action_button != null:
		action_button.pressed.connect(_on_action_pressed)


func job() -> ACAJob:
	return _job


func job_id() -> StringName:
	return _job.id if _job != null else &""


## Fill the card from a job. `manager` is read-only here - it supplies the
## estimated-time calculation and the world clock.
func bind(target: ACAJob, manager: ACAJobManager, mode: int) -> void:
	_job = target
	_manager = manager
	_mode = mode
	if _job == null:
		return

	if title_label != null:
		title_label.text = _job.job_site.to_upper()
	if meta_label != null:
		meta_label.text = "%s   -   %s" % [_job.property_type_name(), _job.lawn_size_name()]

	match mode:
		Mode.AVAILABLE:
			_bind_available()
		Mode.CURRENT:
			_bind_current()
		Mode.PAST:
			_bind_past()


func _bind_available() -> void:
	_set_row(row_a_key, row_a_value, "Estimated Time", _manager.estimated_time_text(_job),
		ACAJobUIStyle.PAPER_INK)
	_set_row(row_b_key, row_b_value, "Pay", _job.pay_text(), ACAJobUIStyle.PAPER_MONEY)
	# WHAT KIND OF PLACE IT IS, when the host has told the manager. The third row
	# already exists and is unused on an offer, so a work order gains a line
	# without the card gaining a node.
	var note := _manager.site_note(_job)
	if note.is_empty():
		_show(row_c, false)
	else:
		_set_row(row_c_key, row_c_value, "Site", note, ACAJobUIStyle.PAPER_INK_DIM)
		_show(row_c, true)
	_show(progress_bar, false)
	if accent_bar != null:
		accent_bar.color = ACAJobUIStyle.ORANGE
	_show(footer, true)
	if action_button != null:
		action_button.text = "ACCEPT"
		action_button.disabled = false
		ACAJobUIStyle.style_paper_button(action_button, true)
	refresh_countdown()


func _bind_current() -> void:
	_set_row(row_a_key, row_a_value, "Pay", _job.pay_text(), ACAJobUIStyle.PAPER_MONEY)
	_set_row(row_b_key, row_b_value, "Estimated Time", _manager.estimated_time_text(_job),
		ACAJobUIStyle.PAPER_INK)
	_set_row(row_c_key, row_c_value, "Progress", "%d%%" % _job.progress_percent(),
		ACAJobUIStyle.PAPER_INK)
	_show(row_c, true)
	_show(progress_bar, true)
	if progress_bar != null:
		progress_bar.value = _job.progress_percent()
	if accent_bar != null:
		accent_bar.color = ACAJobUIStyle.ACCENT
	_show(footer, true)
	if footer_label != null:
		footer_label.text = _job.status_name()
		footer_label.add_theme_color_override("font_color", ACAJobUIStyle.PAPER_INK_DIM)
	if action_button != null:
		if _job.progress >= 1.0:
			action_button.text = "COMPLETE JOB"
		elif _job.is_partially_complete():
			action_button.text = "RETURN TO JOB"
		else:
			action_button.text = "BEGIN JOB"

		action_button.disabled = false
		ACAJobUIStyle.style_paper_button(action_button, true)


func _bind_past() -> void:
	_set_row(row_a_key, row_a_value, "Pay", _job.pay_text(), ACAJobUIStyle.PAPER_MONEY)
	_set_row(row_b_key, row_b_value, "Completed", _completed_text(), ACAJobUIStyle.PAPER_INK_DIM)
	_show(row_c, false)
	_show(progress_bar, false)
	if accent_bar != null:
		accent_bar.color = ACAJobUIStyle.PAPER_INK_FAINT
	_show(footer, false)


func _completed_text() -> String:
	if _job.completed_game_time < 0.0 or _manager == null:
		return "Complete"
	return _manager.time_provider().format_timestamp(_job.completed_game_time)


## Available tab only: re-render the offer countdown. Driven by the board's
## single low-frequency timer, never by _process on this card.
func refresh_countdown() -> void:
	if _mode != Mode.AVAILABLE or _job == null or _manager == null:
		return
	var left := _job.time_remaining(_manager.now())
	if footer_label != null:
		footer_label.text = "Offer expires in %s" % ACAGameTime.format_duration(left)
		footer_label.add_theme_color_override("font_color", ACAJobUIStyle.urgency_colour(left))


func set_action_disabled(disabled: bool) -> void:
	if action_button != null:
		action_button.disabled = disabled


func _on_action_pressed() -> void:
	if _job == null:
		return
	if _mode == Mode.AVAILABLE:
		accept_pressed.emit(_job.id)
	else:
		action_pressed.emit(_job.id)


func _set_row(key: Label, value: Label, key_text: String, value_text: String,
		value_colour: Color) -> void:
	if key != null:
		key.text = key_text
	if value != null:
		value.text = value_text
		value.add_theme_color_override("font_color", value_colour)


func _show(node: Control, visible_state: bool) -> void:
	if node != null:
		node.visible = visible_state
