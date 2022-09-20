extends KinematicBody
##
onready var camera = $Pivot/Camera
onready var hud_model = $HUD
onready var xyz_speed_position_display

var gravity = -30
var max_speed = 10

var mouse_sensitivity = 0.002 

var jump = false
var jump_strength = 10

var velocity = Vector3()
signal this_is_test


#to see if the mode is currentlly paused
var pause = false

func _ready():
	 #prepare variables from the model
	xyz_speed_position_display = hud_model.get_label("position_label")
	
	#this is the placeholder for start position. TO DO: Make this relative rather then hardcoded
	go_to(-5,0,50)
	
	
	
"""
"""
func get_input():	
	var input_dir = Vector3()
	if Input.is_action_pressed("move_forward"):
		input_dir += -global_transform.basis.x
	if Input.is_action_pressed("move_back"):
		input_dir += global_transform.basis.x
	if Input.is_action_pressed("move_left"):
		input_dir += global_transform.basis.z
	if Input.is_action_pressed("move_right"):
		input_dir += -global_transform.basis.z	
	if Input.is_action_pressed("jump"):
		jump = true
	
	input_dir = input_dir.normalized()
	
	
	
	return input_dir

func _input(event):
	if Input.is_action_just_released("pause"):
		pause = !pause
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		
	
func _unhandled_input(event):
	if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		
		rotate_y(-event.relative.x * mouse_sensitivity)
		


"""
	Function to update the HUD. 
"""
func update_pos_speed_info():
	var current_pos = transform.origin.round()
	var xPos = "X: "+ str(current_pos.x)
	var yPos = "Y: "+ str(current_pos.y)
	var zPos = "Z: "+ str(current_pos.z)
		
	xyz_speed_position_display.text = xPos + "\n" + yPos + "\n" + zPos + "\n" + "Speed: " + str(max_speed)
	 
	
	
"""
	Main loop for this script
"""
func _physics_process(delta):

	if pause:
		max_speed = hud_model.get_current_speed(max_speed)
	else:
		velocity.y += gravity * delta
		var desired_velocity = get_input() * max_speed

		velocity.x = desired_velocity.x
		velocity.z = desired_velocity.z
		
		if jump:	
			jump = false
			velocity.y = 0
			velocity.y += jump_strength
		velocity = move_and_slide(velocity,Vector3.UP,true)
		for i in get_slide_count():
			var collision = get_slide_collision(i)
			
			##TO DO: change this_is_test to something more descriptive
			emit_signal("this_is_test",collision)
	
	update_pos_speed_info()
	

func go_to(x, y, z):
	self.transform.origin.x = x
	self.transform.origin.z = z
	self.transform.origin.y = y


func _on_Ground_list_current_cell_ident(cell_item_ident):
	hud_model.get_label("cell_item_ident").text = "Current collision with non -1: " + str(cell_item_ident)
