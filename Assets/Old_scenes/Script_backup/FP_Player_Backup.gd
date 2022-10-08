extends KinematicBody


onready var camera = $Pivot/Camera
onready var hud_model = $HUD
onready var xyz_speed_position_display

var gravity = -30
var max_speed = 10

var mouse_sensitivity = 0.002 

var jump = false
var jump_strength = 10

var velocity = Vector3()

#to see if the mode is currentlly paused
var pause = false

func _ready():
	 #prepare variables from the model
	xyz_speed_position_display = hud_model.get_label("position_label")
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func get_input():	
	var input_dir = Vector3()
	if Input.is_action_pressed("move_forward"):
		input_dir += -global_transform.basis.z
	if Input.is_action_pressed("move_back"):
		input_dir += global_transform.basis.z
	if Input.is_action_pressed("move_left"):
		input_dir += -global_transform.basis.x
	if Input.is_action_pressed("move_right"):
		input_dir += global_transform.basis.x	
	if Input.is_action_pressed("jump"):
		if transform.origin.round().y < 2:
			jump = true
	
	input_dir = input_dir.normalized()
	
	
	
	return input_dir
	
func _unhandled_input(event):
	if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		
		rotate_y(-event.relative.x * mouse_sensitivity)
		$Pivot.rotate_x(-event.relative.y * mouse_sensitivity)
		$Pivot.rotation.x = clamp($Pivot.rotation.x, -1.2, 1.2)


func _physics_process(delta):
	velocity.y += gravity * delta
	var desired_velocity = get_input() * max_speed
	var current_pos = transform.origin.round()
	velocity.x = desired_velocity.x
	velocity.z = desired_velocity.z
	
	if jump:	
		jump = false
		if current_pos.y < 8:
			velocity.y = 0
			velocity.y += jump_strength
		
		
	

	var xPos = "X: "+ str(current_pos.x)
	var yPos = "Y: "+ str(current_pos.y)
	var zPos = "Y: "+ str(current_pos.z)
	
	xyz_speed_position_display.text = xPos + "\n" + yPos + "\n" + zPos + "\n" + "Speed: " + str(max_speed) 
	
	
	velocity = move_and_slide(velocity,Vector3.UP,true)
