class_name ACAJobBoard
extends Control
## The Job interface: Available / Current / Past.
##
## A read-only view over ACAJobManager. It holds no job database of its own -
## every rebuild re-reads the manager's collections, and every player action is
## a call into the manager's public API.
##
## Designed to be dropped into a host HUD as a modal over a live 3D scene:
##  - full-rect, but offset_top leaves the host's top information bar visible
##  - the dim layer is partial alpha, so the 3D town keeps showing through
##  - mouse_filter STOP swallows clicks before they reach the host's picking
##  - `opened` / `closed` let the host disable its own interaction
##
## The board never reaches into the host: it does not know what a town, a
## building or a camera is.

signal opened()
signal closed()

enum Tab { AVAILABLE, CURRENT, PAST }

const DEFAULT_CARD_SCENE := "res://Main Area/ACA_JobSystem/job_system/ui/JobCard.tscn"
const FADE_TIME := 0.18
const COUNTDOWN_INTERVAL := 0.5
const MESSAGE_SECONDS := 3.5

## Wired in JobBoard.tscn. The fallback keeps the board working if it is built
## from script instead of instanced.
@export var card_scene: PackedScene

@export var title_label: Label
@export var subtitle_label: Label
@export var close_button: Button
@export var available_tab_button: Button
@export var current_tab_button: Button
@export var past_tab_button: Button
@export var list_container: VBoxContainer
@export var scroll: ScrollContainer
@export var empty_label: Label
@export var message_label: Label

## Close the board when the player presses the cancel action (Esc by default).
@export var close_on_ui_cancel: bool = true

var _manager: ACAJobManager
var _tab: int = Tab.AVAILABLE
var _open: bool = false
var _cards: Array[ACAJobCard] = []
var _fade: Tween
var _countdown: Timer
var _message_timer: Timer


func _ready() -> void:
	visible = false
	modulate.a = 0.0
	mouse_filter = Control.MOUSE_FILTER_STOP

	if close_button != null:
		close_button.pressed.connect(close)
	if available_tab_button != null:
		available_tab_button.pressed.connect(func() -> void: show_tab(Tab.AVAILABLE))
	if current_tab_button != null:
		current_tab_button.pressed.connect(func() -> void: show_tab(Tab.CURRENT))
	if past_tab_button != null:
		past_tab_button.pressed.connect(func() -> void: show_tab(Tab.PAST))

	# One timer for the whole board keeps every offer countdown ticking.
	# Individual jobs and cards never own timers.
	_countdown = Timer.new()
	_countdown.name = "CountdownTick"
	_countdown.wait_time = COUNTDOWN_INTERVAL
	_countdown.timeout.connect(_refresh_countdowns)
	add_child(_countdown)

	_message_timer = Timer.new()
	_message_timer.name = "MessageTimer"
	_message_timer.one_shot = true
	_message_timer.wait_time = MESSAGE_SECONDS
	_message_timer.timeout.connect(_clear_message)
	add_child(_message_timer)

	_clear_message()
	_sync_tab_buttons()


# ============================================================ manager binding

## INTEGRATION POINT - the board reads everything from this manager.
func set_manager(manager: ACAJobManager) -> void:
	if _manager == manager:
		return
	_disconnect_manager()
	_manager = manager
	if _manager == null:
		return
	_manager.available_jobs_changed.connect(_on_available_changed)
	_manager.current_jobs_changed.connect(_on_current_changed)
	_manager.past_jobs_changed.connect(_on_past_changed)
	_manager.job_accept_failed.connect(_on_accept_failed)
	if _open:
		_rebuild()


func manager() -> ACAJobManager:
	return _manager


func _disconnect_manager() -> void:
	if _manager == null:
		return
	_manager.available_jobs_changed.disconnect(_on_available_changed)
	_manager.current_jobs_changed.disconnect(_on_current_changed)
	_manager.past_jobs_changed.disconnect(_on_past_changed)
	_manager.job_accept_failed.disconnect(_on_accept_failed)


# =============================================================== modal control

func open(tab: int = -1) -> void:
	if tab >= 0:
		_tab = tab
	if _open:
		_rebuild()
		return
	_open = true
	visible = true
	_rebuild()
	_countdown.start()
	_animate(1.0)
	opened.emit()


func close() -> void:
	if not _open:
		return
	_open = false
	_countdown.stop()
	_clear_message()
	_animate(0.0)
	closed.emit()


func toggle() -> void:
	if _open:
		close()
	else:
		open()


func is_open() -> bool:
	return _open


func _unhandled_key_input(event: InputEvent) -> void:
	if not _open or not close_on_ui_cancel:
		return
	if event.is_action_pressed(&"ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


func _animate(target: float) -> void:
	if _fade != null and _fade.is_valid():
		_fade.kill()
	_fade = create_tween()
	_fade.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_fade.tween_property(self, ^"modulate:a", target, FADE_TIME)
	if target <= 0.0:
		_fade.tween_callback(func() -> void: visible = false)


# ==================================================================== tabs

func show_tab(tab: int) -> void:
	_tab = tab
	_clear_message()
	_sync_tab_buttons()
	_rebuild()
	if scroll != null:
		scroll.scroll_vertical = 0


func current_tab() -> int:
	return _tab


func _sync_tab_buttons() -> void:
	var buttons := {
		Tab.AVAILABLE: available_tab_button,
		Tab.CURRENT: current_tab_button,
		Tab.PAST: past_tab_button,
	}
	var counts := {
		Tab.AVAILABLE: _manager.available_jobs().size() if _manager != null else 0,
		Tab.CURRENT: _manager.current_jobs().size() if _manager != null else 0,
		Tab.PAST: _manager.past_jobs().size() if _manager != null else 0,
	}
	var titles := {
		Tab.AVAILABLE: "AVAILABLE",
		Tab.CURRENT: "CURRENT",
		Tab.PAST: "PAST",
	}
	for tab: int in buttons:
		var b: Button = buttons[tab]
		if b == null:
			continue
		b.text = "%s  %d" % [titles[tab], counts[tab]]
		b.button_pressed = tab == _tab
		ACAJobUIStyle.set_tab_selected(b, tab == _tab)


# ================================================================= rebuilding

func _on_available_changed() -> void:
	_sync_tab_buttons()
	if _open and _tab == Tab.AVAILABLE:
		_rebuild()


func _on_current_changed() -> void:
	_sync_tab_buttons()
	if _open and _tab == Tab.CURRENT:
		_rebuild()


func _on_past_changed() -> void:
	_sync_tab_buttons()
	if _open and _tab == Tab.PAST:
		_rebuild()


func _rebuild() -> void:
	if list_container == null:
		return
	_clear_cards()
	_sync_tab_buttons()
	if _manager == null:
		_set_empty("No job manager connected.")
		_set_subtitle("")
		return

	var jobs: Array[ACAJob] = []
	var mode := ACAJobCard.Mode.AVAILABLE
	match _tab:
		Tab.AVAILABLE:
			jobs = _manager.available_jobs()
			mode = ACAJobCard.Mode.AVAILABLE
		Tab.CURRENT:
			jobs = _manager.current_jobs()
			mode = ACAJobCard.Mode.CURRENT
		Tab.PAST:
			jobs = _manager.past_jobs()
			# Newest first: the most recent work reads as the top of the ledger.
			jobs.reverse()
			mode = ACAJobCard.Mode.PAST

	_set_subtitle(_subtitle_for(jobs.size()))

	if jobs.is_empty():
		_set_empty(_empty_text())
		return
	_set_empty("")

	for job in jobs:
		var card := _make_card()
		if card == null:
			return
		list_container.add_child(card)
		card.bind(job, _manager, mode)
		_cards.append(card)

	if _tab == Tab.AVAILABLE:
		_apply_accept_availability()


func _make_card() -> ACAJobCard:
	var scene := card_scene
	if scene == null:
		scene = load(DEFAULT_CARD_SCENE)
	if scene == null:
		push_error("ACAJobBoard: no card scene available at %s" % DEFAULT_CARD_SCENE)
		return null
	var card := scene.instantiate() as ACAJobCard
	if card == null:
		push_error("ACAJobBoard: card scene root is not an ACAJobCard")
		return null
	card.accept_pressed.connect(_on_accept_pressed)
	card.action_pressed.connect(_on_begin_pressed)
	return card


## V1 holds one contract at a time, so the Accept buttons grey out while the
## player already has a job. The message on click still explains why.
func _apply_accept_availability() -> void:
	var blocked := _manager != null and not _manager.has_current_capacity()
	for card in _cards:
		card.set_action_disabled(blocked)


func _clear_cards() -> void:
	_cards.clear()
	if list_container == null:
		return
	for child in list_container.get_children():
		list_container.remove_child(child)
		child.queue_free()


func _refresh_countdowns() -> void:
	if not _open or _tab != Tab.AVAILABLE:
		return
	for card in _cards:
		card.refresh_countdown()


# ================================================================ player input

func _on_accept_pressed(job_id: StringName) -> void:
	if _manager == null:
		return
	if _manager.accept_job(job_id):
		show_tab(Tab.CURRENT)


func _on_begin_pressed(job_id: StringName) -> void:
	if _manager == null:
		return

	var job := _manager.get_job(job_id)
	if job == null:
		return

	if job.progress >= 1.0:
		_manager.complete_job(job_id)
	else:
		# Emits ACAJobManager.begin_job_requested and stops.
		# The host project does the actual gameplay transition.
		_manager.begin_new_job(job_id)


func _on_accept_failed(_job_id: StringName, reason: String) -> void:
	show_message(reason)


# ==================================================================== display

func show_message(text: String) -> void:
	if message_label == null:
		return
	message_label.text = text
	message_label.visible = not text.is_empty()
	if not text.is_empty():
		_message_timer.start()


func _clear_message() -> void:
	if message_label != null:
		message_label.text = ""
		message_label.visible = false


func _set_empty(text: String) -> void:
	if empty_label == null:
		return
	empty_label.text = text
	empty_label.visible = not text.is_empty()


func _set_subtitle(text: String) -> void:
	if subtitle_label != null:
		subtitle_label.text = text


func _subtitle_for(count: int) -> String:
	match _tab:
		Tab.AVAILABLE:
			if count == 1:
				return "1 offer on the board"
			return "%d offers on the board" % count
		Tab.CURRENT:
			return "%d of %d contracts accepted" % [count, _manager.max_current_jobs()]
		Tab.PAST:
			if count == 1:
				return "1 completed job"
			return "%d completed jobs" % count
	return ""


func _empty_text() -> String:
	match _tab:
		Tab.AVAILABLE:
			if _manager != null and _manager.max_available_jobs() <= 0:
				return "Nobody is looking for work right now.\nDemand should pick up later."
			return "No offers on the board yet.\nNew work comes in through the day."
		Tab.CURRENT:
			return "You have not taken on any work.\nAccept an offer from the Available tab."
		Tab.PAST:
			return "No finished jobs yet.\nCompleted work is recorded here."
	return ""
