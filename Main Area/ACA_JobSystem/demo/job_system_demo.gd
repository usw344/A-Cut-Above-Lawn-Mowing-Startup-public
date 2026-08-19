extends Node
## STANDALONE DEMO / TEST HARNESS - development only.
##
## Runs the complete Job System with no host game: a debug world clock, debug
## season/economy/climate inputs, and the real production Job Board UI on top
## of a stand-in backdrop that plays the part of the live 3D town.
##
## Nothing under job_system/ loads anything from this folder. Deleting demo/
## leaves the production system intact.
##
## The debug controls look utilitarian on purpose. The Job Board itself is the
## real, shipping interface.

const BOARD_SCENE := "res://Main Area/ACA_JobSystem/job_system/ui/JobBoard.tscn"

const S := preload("res://Main Area/ACA_JobSystem/job_system/ui/job_ui_style.gd")

const JUMP_MINUTES := [30.0, 60.0, 240.0, 1440.0]
const JUMP_LABELS := ["+30m", "+1h", "+4h", "+1d"]

var _manager: ACAJobManager
var _clock: ACAJobDebugTimeProvider
var _board: ACAJobBoard

var _readout: Label
var _log: Label
var _speed_label: Label
var _host_interaction_enabled := true

var _season_buttons: Array[Button] = []
var _economy_buttons: Array[Button] = []
var _climate_buttons: Array[Button] = []


func _ready() -> void:
	_build_world()
	_build_ui()
	_refresh_readout()

	var ticker := Timer.new()
	ticker.name = "ReadoutTick"
	ticker.wait_time = 0.25
	ticker.autostart = true
	ticker.timeout.connect(_refresh_readout)
	add_child(ticker)


# =============================================================== system wiring

func _build_world() -> void:
	# 1. the debug clock stands in for the game's authoritative world clock
	_clock = ACAJobDebugTimeProvider.new(8.0 * 60.0)
	_clock.set_speed(10.0)  # 10 game minutes per real second keeps tests quick

	# 2. one authoritative manager
	_manager = ACAJobManager.new()
	_manager.name = "JobManager"
	add_child(_manager)
	_manager.set_time_provider(_clock)

	# 3. host-side listeners
	_manager.begin_job_requested.connect(_on_begin_job_requested)
	_manager.job_generated.connect(_on_job_generated)
	_manager.job_expired.connect(_on_job_expired)
	_manager.job_accepted.connect(_on_job_accepted)
	_manager.job_completed.connect(_on_job_completed)
	_manager.market_strength_changed.connect(_on_market_strength_changed)


## THE HOST'S JOB, not the Job System's. In A Cut Above this is where the town
## hands control to the mowing scene. The demo only proves the signal arrives -
## it deliberately changes no scenes.
func _on_begin_job_requested(job: ACAJob) -> void:
	_log_line("BEGIN JOB REQUESTED -> %s (%s %s). Host loads the mowing scene here."
		% [job.job_site, job.lawn_size_name(), str(job.grid_size)])


func _on_job_generated(job: ACAJob) -> void:
	_log_line("Offer arrived: %s (%s)" % [job.job_site, job.lawn_size_name()])


func _on_job_expired(job: ACAJob) -> void:
	_log_line("Offer expired: %s" % job.job_site)


func _on_job_accepted(job: ACAJob) -> void:
	_log_line("Accepted: %s" % job.job_site)


func _on_job_completed(job: ACAJob) -> void:
	_log_line("Completed: %s" % job.job_site)


func _on_market_strength_changed(strength: int) -> void:
	_log_line("Market strength is now %d" % strength)


func _on_board_opened() -> void:
	_host_interaction_enabled = false
	_log_line("Board opened - host interaction disabled")


func _on_board_closed() -> void:
	_host_interaction_enabled = true
	_log_line("Board closed - host interaction restored")


# ========================================================================= UI

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	layer.name = "DemoUI"
	add_child(layer)

	var root := Control.new()
	root.name = "Root"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(root)

	_build_backdrop(root)
	_build_top_bar(root)

	# The production Job Board, instanced exactly as the Town will instance it.
	var scene: PackedScene = load(BOARD_SCENE)
	_board = scene.instantiate() as ACAJobBoard
	root.add_child(_board)
	_board.set_manager(_manager)
	# The host disables its own world interaction while the board is open.
	_board.opened.connect(_on_board_opened)
	_board.closed.connect(_on_board_closed)

	_build_debug_panel(root)
	_board.open()


## Stand-in for the live 3D town. The demo has no 3D scene; this exists only so
## the board's dim layer and top-bar gap can be judged against something.
func _build_backdrop(root: Control) -> void:
	var bg := ColorRect.new()
	bg.name = "Backdrop"
	bg.color = Color(0.180, 0.239, 0.204)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(bg)

	var note := S.label(bg, "BackdropNote",
		"STANDALONE DEMO BACKDROP - in A Cut Above the live 3D town renders here",
		12, Color(0.404, 0.510, 0.435), false)
	note.anchor_top = 1.0
	note.anchor_bottom = 1.0
	note.anchor_right = 1.0
	note.offset_top = -34.0
	note.offset_bottom = -12.0
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	note.mouse_filter = Control.MOUSE_FILTER_IGNORE


## Mimics the Town's 58 px top information bar so the modal layout can be
## checked. The real bar belongs to the host game.
func _build_top_bar(root: Control) -> void:
	var bar := PanelContainer.new()
	bar.name = "TopBar"
	bar.anchor_right = 1.0
	bar.offset_bottom = S.TOP_BAR_HEIGHT
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_theme_stylebox_override("panel", S.stylebox(S.PANEL_BG, 0, 0.0, S.HAIRLINE, 22, 8))
	root.add_child(bar)

	var row := HBoxContainer.new()
	row.name = "Row"
	row.add_theme_constant_override("separation", 14)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(row)

	var brand := VBoxContainer.new()
	brand.name = "Brand"
	brand.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	brand.add_theme_constant_override("separation", -2)
	brand.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(brand)
	S.label(brand, "Title", "A CUT ABOVE", 20, S.INK)
	S.label(brand, "Subtitle", "MOW & GROW", 10, S.ACCENT)

	var gap := Control.new()
	gap.name = "Gap"
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(gap)

	_readout = S.label(row, "Readout", "", 12, S.INK_DIM)
	_readout.size_flags_vertical = Control.SIZE_SHRINK_CENTER


# ============================================================== debug controls

func _build_debug_panel(root: Control) -> void:
	var panel := PanelContainer.new()
	panel.name = "DebugPanel"
	panel.offset_left = 16.0
	panel.offset_top = S.TOP_BAR_HEIGHT + 12.0
	panel.offset_right = 300.0
	panel.add_theme_stylebox_override("panel",
		S.stylebox(Color(0.055, 0.071, 0.078, 0.95), 10, 1.0, S.HAIRLINE, 0, 0))
	root.add_child(panel)

	var margin := MarginContainer.new()
	margin.name = "Margin"
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 12)
	panel.add_child(margin)

	var col := VBoxContainer.new()
	col.name = "Column"
	col.add_theme_constant_override("separation", 7)
	margin.add_child(col)

	S.label(col, "DebugTitle", "DEBUG CONTROLS (dev only)", 12, S.WARN)

	_section(col, "SEASON")
	_season_buttons = _button_row(col, "SeasonRow",
		["Spring", "Summer", "Autumn", "Winter"], _on_season_pressed)
	_mark_selected(_season_buttons, _clock.season())

	_section(col, "ECONOMY")
	_economy_buttons = _button_row(col, "EconomyRow",
		["Recession", "Slow", "Normal", "Booming"], _on_economy_pressed)
	_mark_selected(_economy_buttons, _manager.economy)

	_section(col, "CLIMATE")
	_climate_buttons = _button_row(col, "ClimateRow",
		["Wet", "Normal", "Dry", "Drought"], _on_climate_pressed)
	_mark_selected(_climate_buttons, _manager.climate)

	_section(col, "GAME TIME")
	_button_row(col, "JumpRow", JUMP_LABELS, _on_jump_pressed)
	_button_row(col, "SpeedRow", ["Pause", "x1", "x10", "x60"], _on_speed_pressed)
	_speed_label = S.label(col, "SpeedLabel", "", 11, S.INK_FAINT)

	_section(col, "JOB TESTING")
	_button_row(col, "JobRow1", ["Force offer", "Open board"], _on_market_test_pressed)
	_button_row(col, "JobRow2", ["+25% progress", "Complete job"], _on_job_test_pressed)
	_button_row(col, "JobRow3", ["Clear all", "Seed 928471"], _on_utility_pressed)

	_section(col, "EVENT LOG")
	_log = S.label(col, "Log", "", 11, S.INK_DIM, true)
	_log.custom_minimum_size = Vector2(264, 92)
	_log.vertical_alignment = VERTICAL_ALIGNMENT_TOP


func _on_season_pressed(index: int) -> void:
	_clock.set_season(index)
	_manager.evaluate_now()
	_mark_selected(_season_buttons, index)
	_refresh_readout()


func _on_economy_pressed(index: int) -> void:
	_manager.set_economy(index)
	_manager.evaluate_now()
	_mark_selected(_economy_buttons, index)
	_refresh_readout()


func _on_climate_pressed(index: int) -> void:
	_manager.set_climate(index)
	_manager.evaluate_now()
	_mark_selected(_climate_buttons, index)
	_refresh_readout()


func _on_jump_pressed(index: int) -> void:
	_clock.advance_minutes(JUMP_MINUTES[index])
	# A jump is exactly what the manager must tolerate: it compares absolute
	# times, so one evaluation catches the market up.
	_manager.evaluate_now()
	_log_line("Clock jumped %s" % JUMP_LABELS[index])
	_refresh_readout()


func _on_speed_pressed(index: int) -> void:
	match index:
		0:
			_clock.set_paused(not _clock.paused)
		1:
			_clock.set_paused(false)
			_clock.set_speed(1.0)
		2:
			_clock.set_paused(false)
			_clock.set_speed(10.0)
		3:
			_clock.set_paused(false)
			_clock.set_speed(60.0)
	_refresh_readout()


func _on_market_test_pressed(index: int) -> void:
	if index == 0:
		_manager.debug_force_offer()
	else:
		_board.open()


func _on_job_test_pressed(index: int) -> void:
	var current := _manager.current_jobs()
	if current.is_empty():
		_log_line("No current job to update")
		return
	var job: ACAJob = current[0]
	if index == 0:
		_manager.update_job_progress(job.id, job.progress + 0.25)
		_log_line("Progress -> %d%%" % job.progress_percent())
	else:
		_manager.complete_job(job.id)


func _on_utility_pressed(index: int) -> void:
	if index == 0:
		_manager.debug_clear_all()
		_log_line("All job collections cleared")
		return
	var job := _manager.debug_add_offer_with_seed(928471)
	_log_line("Seed 928471 -> %s / %s / $%d"
		% [job.job_site, job.lawn_size_name(), job.base_pay])


func _section(parent: Node, text: String) -> void:
	S.label(parent, "Section" + text.replace(" ", ""), text, 11, S.INK_FAINT)


func _button_row(parent: Node, node_name: String, labels: Array,
		on_press: Callable) -> Array[Button]:
	var row := HBoxContainer.new()
	row.name = node_name
	row.add_theme_constant_override("separation", 4)
	parent.add_child(row)
	var made: Array[Button] = []
	for i in labels.size():
		var b := S.button(row, "B%d" % i, str(labels[i]), false, 26, 11)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(on_press.bind(i))
		made.append(b)
	return made


func _mark_selected(buttons: Array[Button], index: int) -> void:
	for i in buttons.size():
		S.style_button(buttons[i], i == index, 26, 11)


# =================================================================== readouts

func _refresh_readout() -> void:
	if _readout != null:
		var next := _manager.minutes_until_next_arrival()
		var next_text := "-" if is_inf(next) else ACAGameTime.format_duration(next)
		_readout.text = "%s   |   Market %d (cap %d)   |   Offers %d / Current %d / Past %d   |   Next offer ~%s" % [
			_clock.calendar_text(),
			_manager.market_strength(),
			_manager.max_available_jobs(),
			_manager.available_jobs().size(),
			_manager.current_jobs().size(),
			_manager.past_jobs().size(),
			next_text,
		]
	if _speed_label != null:
		_speed_label.text = "clock %s   |   host input: %s" % [
			_clock.speed_text(),
			"on" if _host_interaction_enabled else "blocked",
		]


func _log_line(text: String) -> void:
	print("[demo] ", text)
	if _log == null:
		return
	var kept: Array[String] = []
	for line in _log.text.split("\n", false):
		kept.append(line)
	kept.append(text)
	while kept.size() > 6:
		kept.remove_at(0)
	_log.text = "\n".join(kept)
