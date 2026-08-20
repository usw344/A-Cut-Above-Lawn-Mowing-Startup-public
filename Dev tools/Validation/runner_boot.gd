extends Node
## DEVELOPMENT ONLY. Generic boot shim for the validation runners.
##
## These runners drive scene changes, and a scene change frees the current
## scene. Parenting the runner directly to /root keeps it alive across the
## transitions it is testing.

## Script to run. Set per boot scene.
@export var runner_script: Script
@export var runner_name: String = "ValidationRunner"


func _ready() -> void:
	if runner_script == null:
		# Usually means the runner script failed to parse, so its ext_resource
		# never loaded. Quit loudly instead of sitting here doing nothing - an
		# idle process looks exactly like a hung test.
		push_error("Runner Boot: runner_script is null (did the script fail to parse?).")
		get_tree().quit(1)
		return
	var runner := Node.new()
	runner.name = runner_name
	runner.set_script(runner_script)
	get_tree().root.add_child.call_deferred(runner)
