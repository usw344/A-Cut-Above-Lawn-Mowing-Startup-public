extends Camera3D


# Called when the node enters the scene tree for the first time.
func _ready():
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	if Input.is_action_just_pressed("move_right"):
		transform.origin.x += 10
	if Input.is_action_just_pressed("move_left"):
		transform.origin.x -= 10
	if Input.is_action_just_pressed("move_back"):
		transform.origin.z += 10
	if Input.is_action_just_pressed("move_forward"):
		transform.origin.z -= 10
