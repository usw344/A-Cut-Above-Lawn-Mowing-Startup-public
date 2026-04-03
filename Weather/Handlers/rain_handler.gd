extends Node3D
class_name Rain_Handler
var mower_position: Vector3

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	if mower_position == null:
		print("ERROR: Mower position not set for Rain Handler")
		
func _init(mower_pos:Vector3) -> void:
	mower_position = mower_pos

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass
