extends Control
class_name Performance_Monitor


var player: CharacterBody3D = null

var number_of_chunks_stored: int = 0
var number_of_chunks_rendered: int = 0
var number_of_chunks_with_collision: int = 0
var number_of_chunks_in_rendering_queue: int = 0

var string_form_of_chunks_data: String = ""

# Called when the node enters the scene tree for the first time.
func _ready():
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	$CanvasLayer/FPS.text = "FPS: " + str(Performance.get_monitor(Performance.TIME_FPS))
	$CanvasLayer/Memory.text = "Memory: " + str(Performance.get_monitor(Performance.MEMORY_STATIC)/(1000000))

	if player != null:
		$"CanvasLayer/Player Speed".text = "Speed: " + str(player.get_speed())
		$"CanvasLayer/Gravity".text = "Gravity: " + str(player.get_gravity())
		$CanvasLayer/Grid_Coord.text = "x: " + str(round(player.global_position.x/750)) + " y: " + str(round(player.global_position.z/750))

	$"CanvasLayer/Chunk Data".text = string_form_of_chunks_data

func set_player(p:CharacterBody3D):
	player = p
