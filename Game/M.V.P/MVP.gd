extends Node3D


@onready var custom_gridmap_object:Custom_Gridmap = $"Custom Gridmap"
@onready var sound:AudioStreamPlayer = $AudioStreamPlayer
@onready var current_mower:CharacterBody3D = $"Rider Mower"

# define scenes of the mower 

var rider_mower_scene = preload("res://Assets/Vehicles and Mowers/Mowers/Mower Rider.tscn")
var powered_mower_scene = preload("res://Assets/Vehicles and Mowers/Mowers/Non Rider Mower.tscn")
var push_mower_scene = preload("res://Assets/Vehicles and Mowers/Mowers/Push Mower.tscn")

var mowers_scene_list = {"push":push_mower_scene, 
"powered":powered_mower_scene,"rider":rider_mower_scene} 

var original_mower_transform = null # for reset use
var custom_gridmap_scene = preload("res://Mowing Section/Mowing Area/Mowing Ground/Custom Gridmap solution/custom_gridmap.tscn") # for reset use


@onready var hud = $CanvasLayer/MVP_HUD
@onready var preset_manager_object:preset_manager = $"PresetManager (Sky3D)"


func _physics_process(delta: float) -> void:
	# this allows the rain gpu emitter to be set correctly Here -> preset manager -> Rain handler
	preset_manager_object.get_and_set_mower_global_position(current_mower.global_position)


func _ready() -> void:
	# in case this gets moved around. This current Hardcoded value works.
	custom_gridmap_object.position = Vector3(-311.935,-492.234,-140.184)
	custom_gridmap_object.test_custom_gridmap(256) # TODO this line can be changed for different size areas
	sound.play() # start background ambience sound
	original_mower_transform = current_mower.transform
	
	## now we can move the mower around without concern. This line will snap it to the correct start position
	custom_gridmap_object.reset_start_area_global_position()
	 # add a small margin in on the y
	current_mower.global_position = custom_gridmap_object.get_mower_inital_position() + Vector3(0,2,0)

	## for current debugging purposes set time to day and weather to clear
	preset_manager_object.apply_time_of_day_preset("Day")
	
	## to manage sound effect of rain and stuff
	preset_manager_object.set_audio_player(sound)

func _input(event):
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_1:
			preset_manager_object.apply_time_of_day_preset("Day")
		if event.keycode == KEY_2:
			preset_manager_object.apply_time_of_day_preset("Evening")
		if event.keycode == KEY_3:
			preset_manager_object.apply_time_of_day_preset("Night")
		
		if event.keycode == KEY_7:
			preset_manager_object.apply_weather_preset("Clear")
		if event.keycode == KEY_8:
			preset_manager_object.apply_weather_preset("Foggy")
		if event.keycode == KEY_9:
			preset_manager_object.apply_weather_preset("Rain")


func _____Debug_Functions_____():
	pass
func _on_mvp_hud_mower_change_selected(mower_id: Variant) -> void:
	var current_transform = current_mower.transform
	var current_mouse_method = Input.mouse_mode
	remove_child(current_mower)
	
	#get the new mower type
	var new_mower:CharacterBody3D = mowers_scene_list.get(mower_id).instantiate()
	new_mower.transform = current_transform
	add_child(new_mower)
	current_mower = new_mower
	current_mower.collided.connect(custom_gridmap_object.custom_grid_map_collision_handler)
	Input.mouse_mode = current_mouse_method

func _on_mvp_hud_reset_map_and_location() -> void:
	# since for MVP I moved the gridmap to its location I need to store it here
	var old_gridmap_transform = custom_gridmap_object.transform
	custom_gridmap_object.queue_free() # delete old gridmap
	
	#make a new one and add it
	custom_gridmap_object = custom_gridmap_scene.instantiate()
	add_child(custom_gridmap_object)
	
	# the test gridmap function makes the new gridmap and mowing area
	custom_gridmap_object.test_custom_gridmap(256)
	
	#now move the gridmap back to orignal place
	custom_gridmap_object.transform =old_gridmap_transform
	current_mower.transform = original_mower_transform
	current_mower.collided.connect(custom_gridmap_object.custom_grid_map_collision_handler)

# control the speed of the mower using a slider
func _on_mvp_hud_ms_slider_value_changed(value: Variant) -> void:
	# get the speed which is set in the model and used in the Mower speed
	var current_speed = model.get_speed()
	
	# calculate the current speed
	current_speed = value
	
	# set the speed back in the model
	model.set_speed(current_speed)

func ______Time_Functions_____():
	pass

func _on_mvp_hud_tod_day_requested() -> void:
	preset_manager_object.apply_time_of_day_preset("Day")
	
func _on_mvp_hud_tod_evening_requested() -> void:
	preset_manager_object.apply_time_of_day_preset("Evening")

func _on_mvp_hud_tod_night_requested() -> void:
	preset_manager_object.apply_time_of_day_preset("Night")
	
# gets signal from MVP_HUD and changes time of day in Sky3d
func _on_mvp_hud_tod_slider_value_changed(value: Variant) -> void:
	## TODO remove this function as move to preset is complete
	preset_manager_object.set_time_of_day_normalized(value)
	

func ____Weather_Functions____():
	pass
func _on_mvp_hud_weather_clear_requested() -> void:
	preset_manager_object.apply_weather_preset("Clear") # Replace with function body.

func _on_mvp_hud_weather_foggy_requested() -> void:
	preset_manager_object.apply_weather_preset("Foggy")

func _on_mvp_hud_weather_rain_requested() -> void:
	preset_manager_object.apply_weather_preset("Rain")
