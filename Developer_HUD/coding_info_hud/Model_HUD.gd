extends CanvasLayer

##Model Class For HUD
onready var labels = {
	"position_label": $PositionInfo,
	"pause_label": $Pause_Notification,
	"cell_item_ident": $Cell_item_ident
}
onready var buttons = {
	"increase_speed": $IncreaseSpeed,
	"decrease_speed": $DecreaseSpeed
}
var current_speed =  0


# Called when the node enters the scene tree for the first time.
func _ready():
	pass
	
	
func get_label(labelID):
	if labelID in labels:
		return labels[labelID]
	return null

func get_current_speed(prev_speed):
	prev_speed += current_speed
	current_speed = 0
	return prev_speed

"""
Function to increase speed when button is clicked
"""
func _on_IncreaseSpeed_pressed():
	current_speed += 1

"""
Function to decrease speed when button is clicked
"""
func _on_DecreaseSpeed_pressed():
	current_speed -= 1
