extends KinematicBody

var gravity = Vector3.DOWN *12 #how fast to fall by default
var speed = 10 # how fast to move
var jump_speed = 6 # jump strength

var move = Vector3.ZERO #var to hold movement values (sometimes called velocity)
var jump = false #is player jumping

var camera

func _ready():
	pass # Replace with function body.


"""
	Function to get input. This makes physics_proces() function smaller in terms of code 
	@post: This function modifies the move var
"""
func get_input():
	move.x = 0
	move.z = 0
	if Input.is_action_pressed("move_forward"):
		move.z -= speed
	if Input.is_action_pressed("move_back"):
		move.z += speed
	if Input.is_action_pressed("move_left"):
		move.x -= speed
	if Input.is_action_pressed("move_right"):
		move.x += speed
		
func _physics_process(delta):
	move += gravity * delta
	get_input()
	move = move_and_slide(move, Vector3.UP)
