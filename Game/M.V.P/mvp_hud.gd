extends Control

@onready var FPS_Counter: Label = $"FPS counter"
@onready var speed_control = $"VBoxContainer/Mower Speed Slider"

@onready var credits: Label = $ColorRect/Credits
@onready var credits2: Label = $ColorRect2/Credits2
@onready var credit1_colorRect: ColorRect = $ColorRect
@onready var credit2_colorRect: ColorRect = $ColorRect2

@onready var credit_button: Button = $"Credit Button"

@onready var day_preset_button: Button = $"VBoxContainer/Time of Day Preset Container/Day Preset"
@onready var evening_preset_button: Button = $"VBoxContainer/Time of Day Preset Container/Evening Preset"
@onready var night_preset_button: Button = $"VBoxContainer/Time of Day Preset Container/Night Preset"

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


func _physics_process(delta: float) -> void:
	update_debug_stats()
	


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

	credits.visible = false
	credits2.visible = false
	credit1_colorRect.visible = false
	credit2_colorRect.visible = false

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
			if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
				Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			else:
				Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


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


func _on_credit_button_pressed():
	credits.visible = !credits.visible
	credits2.visible = !credits2.visible
	credit1_colorRect.visible = !credit1_colorRect.visible
	credit2_colorRect.visible = !credit2_colorRect.visible
	


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
