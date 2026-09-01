extends Control

@onready var FPS_Counter: Label = $"FPS counter"
@onready var speed_control = $"VBoxContainer/Mower Speed Slider"

# The old in-HUD credits panel was removed 2026-08-19. Credits are a Main Menu
# screen now (UI/Credits/), driven by the res://Credits/ folder. The licence
# text this HUD carried was migrated there verbatim first.

@onready var day_preset_button: Button = $"VBoxContainer/Time of Day Preset Container/Day Preset"
@onready var evening_preset_button: Button = $"VBoxContainer/Time of Day Preset Container/Evening Preset"
@onready var night_preset_button: Button = $"VBoxContainer/Time of Day Preset Container/Night Preset"

# ------------------------------------------------------- FUEL (DEVELOPMENT)
#
# This row is the ONLY place Auto Refuel is exposed. It is a development cheat
# and must never appear on the production Gameplay HUD. See MowerFuel.
@onready var auto_refuel_check: CheckBox = $"VBoxContainer/Fuel Container/Auto Refuel"
@onready var refuel_button: Button = $"VBoxContainer/Fuel Container/Refuel Now"
@onready var drain_button: Button = $"VBoxContainer/Fuel Container/Drain"
@onready var fuel_readout: Label = $"VBoxContainer/Fuel Container/Fuel Readout"

@onready var clear_weather_button: Button = $"VBoxContainer/Weather Preset Container/Clear"
@onready var foggy_weather_button: Button = $"VBoxContainer/Weather Preset Container/Foggy"
@onready var rain_weather_button: Button = $"VBoxContainer/Weather Preset Container/Rain"


# define the signals to emit so that the MVP scene can connect to them
signal tod_slider_value_changed(value) # time of day slider
signal ms_slider_value_changed(value)  # mower speed

signal mower_change_selected(mower_id)
signal reset_map_and_location

# time of day preset button signals
signal tod_day_requested
signal tod_evening_requested
signal tod_night_requested

# weather preset button signals
signal weather_clear_requested
signal weather_foggy_requested
signal weather_rain_requested

# development fuel controls
signal auto_refuel_toggled(enabled: bool)
signal refuel_requested
signal drain_fuel_requested


func _physics_process(delta: float) -> void:
	update_debug_stats()
	update_fuel_readout()



func _ready() -> void:
	speed_control.set_value_no_signal(model.get_speed())

	if not day_preset_button.pressed.is_connected(_on_day_preset_pressed):
		day_preset_button.pressed.connect(_on_day_preset_pressed)

	if not evening_preset_button.pressed.is_connected(_on_evening_preset_pressed):
		evening_preset_button.pressed.connect(_on_evening_preset_pressed)

	if not night_preset_button.pressed.is_connected(_on_night_preset_pressed):
		night_preset_button.pressed.connect(_on_night_preset_pressed)

	if not clear_weather_button.pressed.is_connected(_on_clear_weather_pressed):
		clear_weather_button.pressed.connect(_on_clear_weather_pressed)

	if not foggy_weather_button.pressed.is_connected(_on_foggy_weather_pressed):
		foggy_weather_button.pressed.connect(_on_foggy_weather_pressed)

	if not rain_weather_button.pressed.is_connected(_on_rain_weather_pressed):
		rain_weather_button.pressed.connect(_on_rain_weather_pressed)

	# Development fuel row. The checkbox mirrors MowerFuel rather than owning
	# the state, so F8 and the HUD can never disagree.
	auto_refuel_check.set_pressed_no_signal(MowerFuel.auto_refuel())
	_refresh_auto_refuel_text()
	if not auto_refuel_check.toggled.is_connected(_on_auto_refuel_toggled):
		auto_refuel_check.toggled.connect(_on_auto_refuel_toggled)
	if not refuel_button.pressed.is_connected(_on_refuel_pressed):
		refuel_button.pressed.connect(_on_refuel_pressed)
	if not drain_button.pressed.is_connected(_on_drain_pressed):
		drain_button.pressed.connect(_on_drain_pressed)
	MowerFuel.auto_refuel_changed.connect(_on_mower_fuel_auto_refuel_changed)


func update_debug_stats():
	var fps = Performance.get_monitor(Performance.TIME_FPS)

	var ram_bytes = Performance.get_monitor(Performance.MEMORY_STATIC)
	var ram_mb = ram_bytes / 1024.0 / 1024.0

	var process_time = Performance.get_monitor(Performance.TIME_PROCESS)
	var physics_time = Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)
	var cpu_ms = (process_time + physics_time) * 1000.0

	FPS_Counter.text = "FPS: %d\nRAM: %.2f MB\nCPU: %.2f ms" % [
		int(fps),
		ram_mb,
		cpu_ms
	]


func _input(event):
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_SLASH:
			# The cursor is owned by AppUI; see Game/App/app_ui.gd.
			AppUI.toggle_mouse_capture()
		# H used to toggle this HUD from here. H is the Developer Debugger now
		# (Dev tools/Developer Debugger/), which replaced this HUD as the normal
		# developer interface, so the old binding is gone rather than fighting
		# it. Visibility is still driven by MVP.dev_toggle_debug_hud().


# need this function to map slider value for TOD
func map_0_100_to_time(value: float) -> float:
	return (value / 100.0) * 23.99


func _on_time_of_day_slider_value_changed(value: float) -> void:
	emit_signal("tod_slider_value_changed", map_0_100_to_time(value))


func _on_popup_menu_id_pressed(id: int) -> void:
	# popup menu these index pos correspond to these Mowers
	var mowers = ["push", "powered", "rider"]
	emit_signal("mower_change_selected", mowers[id])


func _on_reset_button_pressed() -> void:
	emit_signal("reset_map_and_location")


func _on_mower_speed_slider_value_changed(value: float) -> void:
	emit_signal("ms_slider_value_changed", value)


func _on_day_preset_pressed() -> void:
	emit_signal("tod_day_requested")


func _on_evening_preset_pressed() -> void:
	emit_signal("tod_evening_requested")


func _on_night_preset_pressed() -> void:
	emit_signal("tod_night_requested")


func _on_clear_weather_pressed() -> void:
	emit_signal("weather_clear_requested")


func _on_foggy_weather_pressed() -> void:
	emit_signal("weather_foggy_requested")


func _on_rain_weather_pressed() -> void:
	emit_signal("weather_rain_requested")


# ------------------------------------------------------- FUEL (DEVELOPMENT)

## Live tank readout, so the effect of Auto Refuel is visible: the bar should
## still be seen falling and being topped up, not pinned at 100%.
func update_fuel_readout() -> void:
	fuel_readout.text = "%d%%  (auto %s)" % [
		int(round(MowerFuel.fraction() * 100.0)), MowerFuel.auto_refuel_text()]


func _refresh_auto_refuel_text() -> void:
	auto_refuel_check.text = "AUTO REFUEL: %s" % MowerFuel.auto_refuel_text()


func _on_auto_refuel_toggled(pressed: bool) -> void:
	emit_signal("auto_refuel_toggled", pressed)


## MowerFuel is the authority; F8 and the trailer can change it too.
func _on_mower_fuel_auto_refuel_changed(enabled: bool) -> void:
	auto_refuel_check.set_pressed_no_signal(enabled)
	_refresh_auto_refuel_text()


func _on_refuel_pressed() -> void:
	emit_signal("refuel_requested")


func _on_drain_pressed() -> void:
	emit_signal("drain_fuel_requested")
#extends Control
#
#@onready var FPS_Counter: Label = $"FPS counter"
#@onready var speed_control = $"VBoxContainer/Mower Speed Slider"
#
#@onready var credits: Label = $Credits
#@onready var credits2: Label = $Credits2
#
#@onready var credit_button: Button = $"Credit Button"
#
#
##define the signals to emit so that the MVP scene can connect to them 
#signal tod_slider_value_changed(value) #time of day slider
#signal ms_slider_value_changed(value)  # mower speed
#
#signal mower_change_selected(mower_id)
#signal reset_map_and_location
#
#
#
#func _physics_process(delta: float) -> void:
	#update_debug_stats()
	#
	#
#func _ready() -> void:
	#speed_control.set_value_no_signal(model.get_speed())
	### these should not be 
	#credits.visible = false
	#credits2.visible = false
#func update_debug_stats():
	#var fps = Performance.get_monitor(Performance.TIME_FPS)
#
	#var ram_bytes = Performance.get_monitor(Performance.MEMORY_STATIC)
	#var ram_mb = ram_bytes / 1024.0 / 1024.0
#
	#var process_time = Performance.get_monitor(Performance.TIME_PROCESS)
	#var physics_time = Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)
	#var cpu_ms = (process_time + physics_time) * 1000.0
#
	#FPS_Counter.text = "FPS: %d\nRAM: %.2f MB\nCPU: %.2f ms" % [
		#int(fps),
		#ram_mb,
		#cpu_ms
	#]
#
#func _input(event):
	#if event is InputEventKey and event.pressed and not event.echo:
		#if event.keycode == KEY_SLASH:
			#if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
				#Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			#else:
				#Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
#
#
## need this function to map slider value for TOD
#func map_0_100_to_time(value: float) -> float:
	#return (value / 100.0) * 23.99
#
#func _on_time_of_day_slider_value_changed(value: float) -> void:
	#emit_signal("tod_slider_value_changed",map_0_100_to_time(value))
#
#
#func _on_popup_menu_id_pressed(id: int) -> void:
	## popup menu these index pos correspond to these Mowers
	#var mowers = ["push","powered","rider"]  
	#emit_signal("mower_change_selected",mowers[id])
#
#func _on_reset_button_pressed() -> void:
	#emit_signal("reset_map_and_location")
#
#
#func _on_mower_speed_slider_value_changed(value: float) -> void:
	#emit_signal("ms_slider_value_changed",value)
#
#func _on_credit_button_pressed():
	#credits.visible = !credits.visible
	#credits2.visible = !credits2.visible
