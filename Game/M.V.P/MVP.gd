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

func _physics_process(delta: float) -> void:
	pass
	
func _ready() -> void:
	custom_gridmap_object.test_custom_gridmap(256)
	sound.play() # start background ambience sound
	original_mower_transform = current_mower.transform

# gets signal from MVP_HUD and changes time of day in Sky3d
func _on_mvp_hud_tod_slider_value_changed(value: Variant) -> void:
	$Sky3D.current_time = value


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
