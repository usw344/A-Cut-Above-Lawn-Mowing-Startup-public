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
	update_information_bar()

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
	"""
	Wrapper function to send out signal that the settings menue has been clicked. 
	
	The idea is that the signal from this function should be recieved by the Main Area
	
	FOR NOW: this function receives the signal from the Setting_Button object. This could change going forward. 
	"""
	emit_signal("settings_button_signal")


func update_information_bar():
	"""
	Get the basic information for the display and update it into the information bar
	
	TODO: see if this can be made more efficient. Right now it just checks every frame.
	
	NOTE: this is a wrapper function. If going forward any changes are made to the UI, this function will encapsulate 
	the logic of updating the information display
	"""
	
	# grab the current button objects
	var time_button:Button = $Control/Background/Time_Button
	var weather_button:Button = $Control/Background/Weather_Button
	var money_button:Button = $Control/Background/Money_Button
	
	
	# get the value from the model for this 
	time_button.text = model.get_game_time()
	weather_button.text = model.get_game_weather()
	money_button.text = model.get_game_money()
	
	
