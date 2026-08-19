class_name ACABusinessHUD
extends CanvasLayer
## Lightweight supporting UI for the Business Town.
##
## Deliberately not a menu framework: a title bar with placeholder economy readouts,
## one location card, and one stand-in destination screen.

signal open_requested()
signal back_requested()
signal placeholder_closed()

@export var money_label: Label
@export var day_label: Label
@export var hint_label: Label
@export var building_panel: ACABuildingPanel
@export var placeholder_screen: ACAPlaceholderScreen
@export var job_board: ACAJobBoard

const HINT_OVERVIEW := "Click a location to visit it"
const HINT_SELECTED := "Back returns to the town"


func _ready() -> void:
	if building_panel != null:
		building_panel.open_pressed.connect(func() -> void: open_requested.emit())
		building_panel.back_pressed.connect(func() -> void: back_requested.emit())
	if placeholder_screen != null:
		placeholder_screen.closed.connect(func() -> void: placeholder_closed.emit())
	set_hint(HINT_OVERVIEW)
	if job_board != null:
		job_board.set_manager(JobManager)


## Placeholder economy readout. A Cut Above drives these once it owns the data.
func set_funds(amount: int) -> void:
	if money_label != null:
		money_label.text = "$%s" % _grouped(amount)


func set_day(day: int) -> void:
	if day_label != null:
		day_label.text = "Day %d" % day



func open_jobs() -> void:
	if job_board == null:
		push_warning("BusinessHUD: JobBoard is not assigned.")
		return
	job_board.open()

func set_hint(text: String) -> void:
	if hint_label != null:
		hint_label.text = text

func is_modal_open() -> bool:
	return (is_placeholder_open() or (job_board != null and job_board.is_open()))

func close_active_modal() -> void:
	if job_board != null and job_board.is_open():
		job_board.close()
		return

	if is_placeholder_open():
		close_placeholder()

func show_building(b: ACAInteractiveBuilding) -> void:
	if building_panel != null:
		building_panel.show_building(b.display_name, b.description, b.action_label,
			b.accent_color, b.enabled)
	set_hint(HINT_SELECTED)


func hide_building() -> void:
	if building_panel != null:
		building_panel.hide_panel()
	set_hint(HINT_OVERVIEW)


func open_placeholder(b: ACAInteractiveBuilding) -> void:
	if placeholder_screen != null:
		placeholder_screen.open(b.display_name, b.accent_color)


func is_placeholder_open() -> bool:
	return placeholder_screen != null and placeholder_screen.is_open()


func close_placeholder() -> void:
	if placeholder_screen != null:
		placeholder_screen.close()


func _grouped(value: int) -> String:
	var s := str(absi(value))
	var out := ""
	var count := 0
	for i in range(s.length() - 1, -1, -1):
		out = s[i] + out
		count += 1
		if count % 3 == 0 and i > 0:
			out = "," + out
	return ("-" if value < 0 else "") + out
