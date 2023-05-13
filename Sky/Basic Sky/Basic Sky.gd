@tool
extends WorldEnvironment


@export_range(-360,360) var pos = 0.0

var cycle_duration = 720 # x minutes * 60 seconds
var elapsed_time = 180 # correspond to noon cycle_duration/4

@export var in_editor_viewing_overide:bool = false





func _process(delta):
	
	if in_editor_viewing_overide:
		$Sun_and_Moon.rotation_degrees.x = pos
	else:
		elapsed_time += delta
		var cycle_progress = elapsed_time / cycle_duration
		var angle = -360 * cycle_progress # -360 is sunrise, 0 is noon, 360 is suwnset

		# Set the directional light's rotation
		$Sun_and_Moon.rotation_degrees.x = angle

