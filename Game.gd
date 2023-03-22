extends Node3D

@onready var model = $model

# Called when the node enters the scene tree for the first time.
func _ready():
	$Mower.set_model(model)


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	pass
