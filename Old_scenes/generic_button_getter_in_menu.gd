extends VBoxContainer


var buttons = []


func _ready():
	for i in self.get_children():
		buttons.append(i)
		
		
func get_buttons():
	return buttons
