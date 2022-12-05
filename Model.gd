extends Node

var grass_stored = 0
var funds = 0


func _ready():
	pass
	
func set_grass(val):
	grass_stored = val


func get_grass():
	return grass_stored 

func set_funds(val):
	funds = val
	
func get_funds():
	return funds
