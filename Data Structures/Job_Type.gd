extends Node
class_name Job_Type


var diffculty:String
var size:String

# Called when the node enters the scene tree for the first time.
func _ready():
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	pass

func set_size(s:String) -> void:
	size = s 
func set_diffculty(d:String) ->void:
	diffculty = d
	
func get_diffculty() ->String:
	return diffculty
func get_size() -> String:
	return size
