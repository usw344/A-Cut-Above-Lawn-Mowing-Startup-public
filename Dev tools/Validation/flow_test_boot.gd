extends Node
## DEVELOPMENT ONLY. Boot shim for the flow test.
##
## The test changes scenes, which frees the current scene. Parenting the runner
## directly to /root keeps it alive across those transitions.

const RUNNER_SCRIPT := preload("res://Dev tools/Validation/flow_test.gd")


func _ready() -> void:
	var runner := Node.new()
	runner.name = "FlowTestRunner"
	runner.set_script(RUNNER_SCRIPT)
	get_tree().root.add_child.call_deferred(runner)
