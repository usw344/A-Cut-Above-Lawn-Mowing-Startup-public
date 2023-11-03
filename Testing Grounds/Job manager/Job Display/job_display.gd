extends Node3D


# Called when the node enters the scene tree for the first time.
func _ready():
	pass # Replace with function body.

var offer:Job_Offer

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	pass

func set_job_offer(o:Job_Offer) ->void:
	offer = o
func get_job_offer() -> Job_Offer:
	return offer
