extends Node

var grass_stored = 0



func _ready():
	pass
	
func set_grass(val):
	grass_stored = val


func get_grass():
	return grass_stored 
