extends Node
class_name Job_Type

"""
A more complex data structure that functions both as a reference to get the different types 
and sizes avaiable in the game. But also to store that data for a given job instance
"""

var diffculty:String
var size:String

var diffculty_values:Array = ["Easy", "Medium", "Hard"]
var size_values:Array = ["Small","Medium","Large"]

# Called when the node enters the scene tree for the first time.
func _ready():
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	pass

func init():
	pass


func set_size(s:String) -> void:
	size = s 
func set_diffculty(d:String) ->void:
	diffculty = d
	
func get_diffculty() ->String:
	return diffculty
func get_size() -> String:
	return size

func get_diffculty_values() -> Array:
	return diffculty_values
func get_size_values() ->Array:
	return size_values
