extends CanvasLayer

onready var tween = $Tween
onready var width = get_viewport().size.x
onready var height = get_viewport().size.y


func _ready():
	tween.playback_speed = 5

func appear():
	update_width_height()
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	tween.interpolate_property(self, "offset:x", width+100,width/4.5,Tween.TRANS_BACK,Tween.EASE_IN_OUT)
	
	tween.start()
	
func disappear():
	update_width_height()
	tween.interpolate_property(self, "offset:x", width/4,width+100.5,Tween.TRANS_BACK,Tween.EASE_IN_OUT)

	tween.start()
	
func update_width_height():
	width = get_viewport().size.x
	height = get_viewport().size.y
