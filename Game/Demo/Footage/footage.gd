extends Node3D

"""

A demo scene designed to get the best possible footage for trailors and capsulate art. 

"""
@onready var custom_gridmap_object:Custom_Gridmap = $"Custom Gridmap"

var mowers
var current_mower:CharacterBody3D = null
func _ready() -> void:
	custom_gridmap_object.test_custom_gridmap(256)
	current_mower = $LawnMover02
	mowers = [$LawnMover02,$"Rider Mower",$"Push Mower"]
	
	remove_child(mowers[1])
	remove_child(mowers[2])
	
func _process(delta: float) -> void:
	pass
	
func _input(event: InputEvent) -> void:
	if Input.is_action_just_pressed("Day"):
		$Sky3D.current_time = 11.72 ## default day recording time
	elif Input.is_action_just_pressed("Sunset"):
		$Sky3D.current_time = 16.77
	elif Input.is_action_just_pressed("Night"):
		$Sky3D.current_time = 22.31
	elif Input.is_action_just_pressed("mower_1"): #hand mower
		select_mower(1)
	elif Input.is_action_just_pressed("mower_2"): # rider mower
		select_mower(2)
	elif Input.is_action_just_pressed("mower_3"): # push mower
		select_mower(3)
	
func time_toggle():
	$Sky3D.current_time = 16.77
func select_mower(type:int):
	##remove old mower from scene
	#save transform
	var current_transform = current_mower.transform
	remove_child(current_mower)
	
	var new_mower = mowers[type-1]
	new_mower.transform = current_transform
	add_child(new_mower)
	 
	
	
