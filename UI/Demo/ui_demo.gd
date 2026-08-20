extends Control
class_name UIDemo

# ============================================================
# WHAT THIS IS
# ============================================================
#
# The sandbox showcase. It is NOT a component and it is NOT meant to be
# copied into the production game - it exists so every component can be
# exercised without the real mowing game.
#
# It also doubles as the integration example: every signal connection in
# _wire_components() below is the connection the host game will need to
# make. Read that one function and you know how the pieces fit together.
#
# Fake flow:
#
#   Fake Town -> Job Intro -> fade -> Gameplay HUD -> Pause / Resume
#             -> progress reaches 100% -> Job Complete -> fade -> Fake Town
#
# ============================================================
# SCENE / RESOURCE REFERENCES
# ============================================================
#
# Every component is INSTANCED IN "UI Demo.tscn", not preloaded here, so
# the scene file is the single place that lists them:
#
#   res://UI/Gameplay HUD/Gameplay HUD.tscn
#   res://UI/Job Complete/Job Complete.tscn
#   res://UI/Job Intro/Job Intro.tscn
#   res://UI/Pause Menu/Pause Menu.tscn
#   res://UI/Notifications/Notifications.tscn
#   res://UI/Transitions/Transition.tscn
#   res://UI/Settings/Settings.tscn
#   res://UI/Controls Help/Controls Help.tscn
#   res://UI/Dialogs/Confirmation Dialog.tscn
#   res://UI/Theme/Game UI.theme.tres
#
# ============================================================
# HOST INTEGRATION NOTES
# ============================================================
#
# The demo owns all the decisions the components refuse to make:
# which screen is visible, what "abandon" means, when a job is complete.
# That split is the whole point - see UI/README.md.
#
# The demo does NOT set get_tree().paused when the pause menu opens,
# because pausing the tree would freeze the demo controls too. A real
# host SHOULD pause there; see the note in _on_pause_opened().
#
# PRESS F1 (or the HIDE button) to collapse the demo control panel. Do
# that before taking screenshots or recording footage - the panel is a
# test rig, and with it collapsed the components have the whole screen.
#
# ============================================================


enum State { TOWN, JOB }

## Seconds the Job Intro stays up before the demo fades into gameplay.
const INTRO_HOLD := 2.0
## Fake job presets the demo cycles through. The long one is deliberate:
## it tests name truncation in the HUD.
const JOB_NAMES: PackedStringArray = [
	"A person Residence",
	"Some Park & Recreation Grounds",
	"Another Farm",
]
const JOB_SIZES: PackedStringArray = ["Small Lawn", "Medium Lawn", "Large Lawn"]
const REWARDS: PackedInt32Array = [120, 240, 1250, 12500]
const BONUSES: PackedInt32Array = [0, 25, 150]
const WEATHERS: PackedStringArray = ["Clear", "Cloudy", "Light Rain", "Overcast"]
const RESOLUTIONS: Array[Vector2i] = [
	Vector2i(1920, 1080), Vector2i(1600, 900), Vector2i(1280, 720)
]
## Mowed stripes drawn on the fake lawn, driven by the progress slider.
const LAWN_STRIPES := 16
const UNMOWED := Color(0.180, 0.325, 0.161)
## Two mowed tones, alternating, so the cut area reads as mower passes
## rather than one flat block of colour.
const MOWED := Color(0.376, 0.588, 0.310)
const MOWED_ALT := Color(0.325, 0.529, 0.267)

# --------------------------------------------------------------- components
@onready var _hud: GameplayHUD = %GameplayHUD
@onready var _results: JobCompleteScreen = %JobComplete
@onready var _intro: JobIntroScreen = %JobIntro
@onready var _pause: PauseMenu = %PauseMenu
@onready var _toasts: NotificationCenter = %Notifications
@onready var _transition: TransitionLayer = %Transition
@onready var _settings: SettingsMenu = %Settings
@onready var _controls: ControlsHelp = %ControlsHelp
@onready var _dialog: ConfirmationPrompt = %ConfirmationDialog

# ------------------------------------------------------------- demo chrome
@onready var _town_screen: Control = %TownScreen
@onready var _town_backdrop: Control = %TownBackdrop
@onready var _lawn_backdrop: Control = %LawnBackdrop
@onready var _stripes: HBoxContainer = %LawnStripes
@onready var _state_label: Label = %StateValue

@onready var _job_option: OptionButton = %JobNameOption
@onready var _size_option: OptionButton = %JobSizeOption
@onready var _reward_option: OptionButton = %RewardOption
@onready var _bonus_option: OptionButton = %BonusOption
@onready var _weather_option: OptionButton = %WeatherOption

@onready var _progress_slider: HSlider = %ProgressSlider
@onready var _progress_value: Label = %ProgressValue
@onready var _fuel_slider: HSlider = %FuelSlider
@onready var _fuel_value: Label = %FuelValue
@onready var _clock_slider: HSlider = %ClockSlider
@onready var _clock_value: Label = %ClockValue
@onready var _elapsed_slider: HSlider = %ElapsedSlider
@onready var _elapsed_value: Label = %ElapsedValue

@onready var _complete_button: Button = %CompleteButton
@onready var _debug_panel: Control = %DebugPanel
@onready var _debug_toggle: Button = %DebugToggle

var _state: int = State.TOWN
## What the confirmation dialog should run if the player confirms. Cleared
## on both answers, so a cancelled dialog can never fire a stale action.
var _pending_confirm: Callable = Callable()


func _unhandled_input(event: InputEvent) -> void:
	# F1 collapses the test rig for a clean look at the components.
	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo and key.keycode == KEY_F1:
		_toggle_debug_panel()
		get_viewport().set_input_as_handled()


func _ready() -> void:
	_build_lawn_stripes()
	_populate_options()
	_wire_components()
	_wire_demo_controls()

	_enter_town(true)
	_push_job_data()
	_on_progress_changed(_progress_slider.value)
	_on_fuel_changed(_fuel_slider.value)
	_on_clock_changed(_clock_slider.value)
	_on_elapsed_changed(_elapsed_slider.value)


# ============================================================================
# WIRING - this is the part worth copying into the host game
# ============================================================================

func _wire_components() -> void:
	# The HUD asks to pause; the host decides that means "open the menu".
	_hud.pause_requested.connect(_on_pause_requested)
	_hud.low_fuel_entered.connect(func() -> void:
		_toasts.warning("Fuel low", "%s remaining" % UITheme.percent_text(_hud.fuel())))

	# The pause menu reports intent only. Everything below is the host's call.
	_pause.opened.connect(_on_pause_opened)
	_pause.closed.connect(_on_pause_closed)
	_pause.settings_requested.connect(func() -> void: _settings.open())
	_pause.restart_job_requested.connect(_on_restart_requested)
	_pause.abandon_job_requested.connect(_on_abandon_requested)
	_pause.quit_to_menu_requested.connect(_on_quit_requested)

	_settings.back_requested.connect(func() -> void: _settings.close())
	_settings.controls_requested.connect(func() -> void: _controls.open())
	_settings.apply_requested.connect(_on_settings_applied)

	# The results screen never changes scene itself - the demo does.
	_results.return_to_town_requested.connect(_on_return_to_town)

	# One dialog instance serves every confirmation. The host holds the
	# action to run rather than reconnecting the signal each time.
	_dialog.confirmed.connect(_on_dialog_confirmed)
	_dialog.cancelled.connect(_on_dialog_cancelled)


func _wire_demo_controls() -> void:
	%BeginJobButton.pressed.connect(_begin_job)
	%TownSettingsButton.pressed.connect(func() -> void: _settings.open())
	%TownNotifyButton.pressed.connect(func() -> void:
		_toasts.info("New contracts available", "3 jobs posted this morning"))
	%TownControlsButton.pressed.connect(func() -> void: _controls.open())

	_job_option.item_selected.connect(func(_i: int) -> void: _push_job_data())
	_size_option.item_selected.connect(func(_i: int) -> void: _push_job_data())
	_reward_option.item_selected.connect(func(_i: int) -> void: _push_job_data())
	_bonus_option.item_selected.connect(func(_i: int) -> void: _push_job_data())
	_weather_option.item_selected.connect(func(i: int) -> void:
		_hud.set_weather(WEATHERS[i]))

	_progress_slider.value_changed.connect(_on_progress_changed)
	_fuel_slider.value_changed.connect(_on_fuel_changed)
	_clock_slider.value_changed.connect(_on_clock_changed)
	_elapsed_slider.value_changed.connect(_on_elapsed_changed)

	%FinishButton.pressed.connect(func() -> void: _progress_slider.value = 1.0)
	%LowFuelButton.pressed.connect(func() -> void: _fuel_slider.value = 0.18)
	%RefuelButton.pressed.connect(func() -> void: _fuel_slider.value = 1.0)
	_complete_button.pressed.connect(_show_results)

	%NotifyInfoButton.pressed.connect(func() -> void:
		_toasts.info("Job accepted", _job_option.get_item_text(_job_option.selected)))
	%NotifySuccessButton.pressed.connect(func() -> void:
		_toasts.success("Lawn section cleared", "Front yard complete"))
	%NotifyWarningButton.pressed.connect(func() -> void:
		_toasts.warning("Fuel low", "18% remaining"))
	%NotifyErrorButton.pressed.connect(func() -> void:
		_toasts.error("Obstacle struck", "Watch the flower beds"))
	%NotifyMoneyButton.pressed.connect(func() -> void:
		_toasts.money("Contract complete", "+%s" % UITheme.format_money(_reward())))
	%NotifyBurstButton.pressed.connect(_notification_burst)

	%PauseButton.pressed.connect(_on_pause_requested)
	%TransitionButton.pressed.connect(func() -> void:
		_transition.set_title("Travelling", _job_name())
		_transition.fade_out_and_in(0.5))
	%ControlsButton.pressed.connect(func() -> void: _controls.open())
	%SettingsButton.pressed.connect(func() -> void: _settings.open())
	%DialogButton.pressed.connect(_on_abandon_requested)

	_debug_toggle.pressed.connect(_toggle_debug_panel)
	for i in RESOLUTIONS.size():
		var button := get_node("%%ResolutionButton%d" % i) as Button
		button.pressed.connect(_apply_window_size.bind(RESOLUTIONS[i]))


# ============================================================================
# FAKE FLOW
# ============================================================================

func _begin_job() -> void:
	_intro.set_contract_type("Residential Contract")
	_intro.show_job(_job_name(), _job_size(), _reward(), _estimated_minutes())
	_intro.set_status("Preparing equipment...")
	_toasts.success("Job accepted", _job_name())

	# Hold the intro, then fade into gameplay. A real host would await its
	# own loading here instead of a timer.
	var hold := get_tree().create_timer(INTRO_HOLD)
	hold.timeout.connect(func() -> void:
		_intro.set_status("Ready")
		_transition.screen_covered.connect(_swap_to_job, CONNECT_ONE_SHOT)
		_transition.fade_to_black())


## Runs while the screen is fully covered - the host swaps content here.
func _swap_to_job() -> void:
	_intro.hide_intro()
	_enter_job()
	_transition.fade_from_black()


func _on_return_to_town() -> void:
	_transition.screen_covered.connect(func() -> void:
		_results.hide_results()
		_enter_town(false)
		_transition.fade_from_black(), CONNECT_ONE_SHOT)
	_transition.fade_to_black()


func _enter_town(instant: bool) -> void:
	_state = State.TOWN
	_state_label.text = "TOWN"
	_town_screen.visible = true
	_town_backdrop.visible = true
	_lawn_backdrop.visible = false
	if instant:
		_hud.visible = false
		_hud.modulate.a = 0.0
	else:
		_hud.hide_hud()
	# Escape belongs to the pause menu only while a job is running.
	_pause.open_on_escape = false
	_complete_button.disabled = true


func _enter_job() -> void:
	_state = State.JOB
	_state_label.text = "JOB"
	_town_screen.visible = false
	_town_backdrop.visible = false
	_lawn_backdrop.visible = true
	_hud.show_hud()
	_pause.open_on_escape = true
	_pause.set_context(_job_name())
	_refresh_complete_button()


func _show_results() -> void:
	if _state != State.JOB:
		return
	_results.show_results(_job_name(), _progress_slider.value,
		_elapsed_slider.value, _reward(), _bonus())


# ============================================================================
# HOST DECISIONS - what the pause menu signals actually mean here
# ============================================================================

func _on_pause_requested() -> void:
	_pause.set_context(_job_name() if _state == State.JOB else "")
	_pause.open()


func _on_pause_opened() -> void:
	# A REAL HOST SHOULD DO THIS HERE:
	#   get_tree().paused = true
	#   Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	# The demo deliberately does not, because pausing the tree would also
	# freeze the demo controls on the right.
	pass


func _on_pause_closed() -> void:
	# ...and undo it here.
	pass


func _ask(title: String, message: String, confirm_text: String,
		on_confirm: Callable) -> void:
	_pending_confirm = on_confirm
	_dialog.show_confirmation(title, message, confirm_text, "CANCEL")


func _on_dialog_confirmed() -> void:
	var action := _pending_confirm
	_pending_confirm = Callable()
	if action.is_valid():
		action.call()


func _on_dialog_cancelled() -> void:
	_pending_confirm = Callable()


func _on_restart_requested() -> void:
	_ask("RESTART JOB?", "Current progress will be reset.", "RESTART",
		func() -> void:
			_pause.close()
			_progress_slider.value = 0.0
			_elapsed_slider.value = 0.0
			_toasts.info("Job restarted", _job_name()))


func _on_abandon_requested() -> void:
	_ask("ABANDON JOB?", "Progress on this contract may be lost.", "ABANDON",
		func() -> void:
			_pause.close()
			_toasts.error("Contract abandoned", _job_name())
			_on_return_to_town())


func _on_quit_requested() -> void:
	_ask("QUIT TO MENU?",
		"Any unsaved progress on this contract will be lost.", "QUIT",
		func() -> void:
			_pause.close()
			_toasts.info("Quit to menu", "The host game would change scene here")
			_on_return_to_town())


func _on_settings_applied(settings: Dictionary) -> void:
	# A real host would write these into its config and apply them. The
	# demo just proves the dictionary arrives intact.
	_settings.close()
	_toasts.success("Settings applied",
		"Quality %s   Master %s" % [settings["quality_name"],
			UITheme.percent_text(settings["master_volume"])])


# ============================================================================
# DEMO CONTROL HANDLERS
# ============================================================================

func _push_job_data() -> void:
	_hud.set_job_name(_job_name())
	_hud.set_job_size(_job_size())
	_hud.set_reward(_reward())
	_hud.set_weather(WEATHERS[_weather_option.selected])
	_pause.set_context(_job_name() if _state == State.JOB else "")


func _on_progress_changed(value: float) -> void:
	_progress_value.text = UITheme.percent_text(value)
	_hud.set_progress(value)
	_paint_lawn(value)
	_refresh_complete_button()


func _on_fuel_changed(value: float) -> void:
	_fuel_value.text = UITheme.percent_text(value)
	_hud.set_fuel(value)


## Slider 0-1 maps onto a working day, 06:00 to 20:00.
func _on_clock_changed(value: float) -> void:
	var minutes := int(round(lerpf(6.0 * 60.0, 20.0 * 60.0, value)))
	var text := "%02d:%02d" % [minutes / 60, minutes % 60]
	_clock_value.text = text
	_hud.set_game_time(text)


func _on_elapsed_changed(value: float) -> void:
	_elapsed_value.text = UITheme.format_clock(value)


func _refresh_complete_button() -> void:
	_complete_button.disabled = _state != State.JOB \
		or _progress_slider.value < 1.0


func _notification_burst() -> void:
	# Six at once against max_visible = 3, so the queue is visibly working.
	_toasts.info("Contract posted", "Ridgeway Cul-de-sac")
	_toasts.success("Section cleared", "Back yard")
	_toasts.warning("Fuel low", "18% remaining")
	_toasts.money("Payment received", "+$240")
	_toasts.error("Blade jam", "Reverse to clear")
	_toasts.info("Weather changing", "Light rain expected")


func _toggle_debug_panel() -> void:
	var open: bool = not %DebugBody.visible
	%DebugBody.visible = open
	_debug_toggle.text = "HIDE" if open else "SHOW"
	# Collapse the panel to its header as well as emptying it, otherwise
	# the full-height rect keeps covering the HUD chips behind it.
	_debug_panel.anchor_bottom = 1.0 if open else 0.0
	_debug_panel.offset_bottom = -20.0 if open else _debug_panel.offset_top


## Demo-only. Components never touch DisplayServer themselves.
func _apply_window_size(size: Vector2i) -> void:
	if DisplayServer.window_get_mode() != DisplayServer.WINDOW_MODE_WINDOWED:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(size)
	var screen_size := DisplayServer.screen_get_size()
	DisplayServer.window_set_position((screen_size - size) / 2)
	_toasts.info("Window resized", "%d x %d" % [size.x, size.y])


# ============================================================================
# FAKE SCENERY
# ============================================================================

func _build_lawn_stripes() -> void:
	for i in LAWN_STRIPES:
		var stripe := ColorRect.new()
		stripe.name = "Stripe%d" % i
		stripe.color = UNMOWED
		stripe.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		stripe.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_stripes.add_child(stripe)


## The fake lawn mows itself as the progress slider moves, so the HUD has
## something honest to sit on top of in screenshots.
func _paint_lawn(progress: float) -> void:
	var mowed := progress * float(LAWN_STRIPES)
	for i in _stripes.get_child_count():
		var stripe := _stripes.get_child(i) as ColorRect
		if float(i) < mowed:
			stripe.color = MOWED if i % 2 == 0 else MOWED_ALT
		else:
			stripe.color = UNMOWED


# ============================================================================
# SMALL READERS
# ============================================================================

func _job_name() -> String:
	return JOB_NAMES[_job_option.selected]


func _job_size() -> String:
	return JOB_SIZES[_size_option.selected]


func _reward() -> int:
	return REWARDS[_reward_option.selected]


func _bonus() -> int:
	return BONUSES[_bonus_option.selected]


func _estimated_minutes() -> int:
	return [8, 12, 20][_size_option.selected]


func _populate_options() -> void:
	for value in JOB_NAMES:
		_job_option.add_item(value)
	for value in JOB_SIZES:
		_size_option.add_item(value)
	for value in REWARDS:
		_reward_option.add_item(UITheme.format_money(value))
	for value in BONUSES:
		_bonus_option.add_item(UITheme.format_money(value))
	for value in WEATHERS:
		_weather_option.add_item(value)
	_job_option.selected = 0
	_size_option.selected = 1
	_reward_option.selected = 1
	_bonus_option.selected = 1
	_weather_option.selected = 0
