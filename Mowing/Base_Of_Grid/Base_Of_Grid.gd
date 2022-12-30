extends StaticBody

var floor_width = 20
var floor_length = 20
var x = 0
var y = 0
var z = 0

onready var collision_shape =  $CollisionShape
onready var mesh_instance = $MeshInstance

func _ready():
	pass
	
	

func update_ground_variables():
	$CollisionShape.shape.extents.x = floor_length/2
	$CollisionShape.shape.extents.z = floor_length/2
	
	$MeshInstance.mesh.size.x = floor_width
	$MeshInstance.mesh.size.z = floor_length
	
	##This blocks updates the  x,y,z to what is listed in the instance
	self.transform.origin.x = x
	self.transform.origin.y = y
	self.transform.origin.z = z


func set_length(length):
	floor_length = length
	

func get_length():
	return floor_length

func set_width(width):
	floor_width = width
	
	
func get_width():
	return floor_width

"""
	Function to set the location of this object
"""
func set_location(location):
	z = location.x
	y = location.y 
	z = location.z
	
	
