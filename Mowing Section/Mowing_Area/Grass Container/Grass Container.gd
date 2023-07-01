extends Node3D
#class_name Grass_Container

enum mowed_status {MOWED,UNMOWED}
enum lod_status {LOW, HIGH}

var current_mowed_status:mowed_status
var current_lod_status:lod_status

var location_rounded:Vector3 = Vector3(430,25,500)

var is_mowed:bool = false

# Called when the node enters the scene tree for the first time.
func _ready():
#	flip_collision()
	print(get_child_count())
	$"Unmowed Grass Low LOD".position = location_rounded


func _init(location:Vector3):
	"""
	Location must initally be unrounded to be able to set the location correctly
	
	data object for the job is passed by reference
	"""
	location_rounded = location
	
	
	
	
func set_location(location:Vector3):
	location_rounded = location

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	pass

func make_low_LOD():
	pass
	
func flip_lod():
	pass

func flip_mowed_status():
	if current_mowed_status == mowed_status.UNMOWED: # currently unmowed
		# flip the status
		current_mowed_status = mowed_status.MOWED
		
		# this may be performance heavy
		hide_all()
		
		# if this LOD is high 
		if current_lod_status == lod_status.HIGH:
			$"Mowed Grass High LOD".show()
		else: # low lod
			$"Mowed Grass LOW LOD".show()
		
	else: # currently mowed
		if current_lod_status == lod_status.HIGH:
			$"Unmowed Grass High LOD".show()
		else: # low lod
			$"Unmowed Grass Low LOD".show()
	

func flip_collision():
	if $"Unmowed Grass High LOD/CollisionShape3D".disabled == true:
		$"Unmowed Grass High LOD/CollisionShape3D".disabled = false
	else:
		$"Unmowed Grass High LOD/CollisionShape3D".disabled = true


func hide_all():
	$"Mowed Grass High LOD".hide()
	$"Mowed Grass LOW LOD".hide()
	
	$"Unmowed Grass High LOD".hide()
	$"Unmowed Grass Low LOD".hide()
