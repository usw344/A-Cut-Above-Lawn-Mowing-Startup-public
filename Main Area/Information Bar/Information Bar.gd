extends CanvasLayer

signal time_button_signal

signal weather_button_signal

signal money_button_signal

signal settings_button_signal


@onready var time_button:Button = $Control/Background/Time_Button
@onready var weather_button:Button = $Control/Background/Weather_Button
@onready var money_button:Button = $Control/Background/Money_Button
@onready var settings_button:Button = $Control/Background/Settings_Button

# Called when the node enters the scene tree for the first time.
func _ready():
	pass

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	pass

func setup_signals() -> void:
	"""
	Setup the various button signals to their wrapper functions which then broadcast 
	(currently these broadcast signals are recieved by the Main Area scene)
	"""
	time_button.connect("pressed",signal_time_button)
	weather_button.connect("pressed",signal_weather_button)
	money_button.connect("pressed",signal_money_button)
	settings_button.connect("pressed",signal_settings_button)
	
	
func signal_time_button() ->void:
	emit_signal("time_button_signal")

func signal_weather_button() ->void:
	emit_signal("weather_button_signal")

func signal_money_button() ->void:
	emit_signal("money_button_signal")

func signal_settings_button() ->void:
	emit_signal("settings_button_signal")

