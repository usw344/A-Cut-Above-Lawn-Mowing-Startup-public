extends Spatial

var label_text = "Placeholder"
var collision_label = ""


# Called when the node enters the scene tree for the first time.
func _ready():
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
#func _process(delta):
#	pass


func set_label_text(new_text):
	$Label3D.text = new_text


func set_collision_label(label):
	collision_label = label
	
func get_collision_label():
	return collision_label
