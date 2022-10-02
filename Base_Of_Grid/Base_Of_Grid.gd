extends StaticBody

export var floor_width = 20
export var floor_height = 20
export var x = 0
export var y = 0
export var z = 0

onready var collision_shape =  $CollisionShape
onready var mesh_instance = $MeshInstance
func _ready():
	collision_shape.shape.extents.x = floor_height/2
	collision_shape.shape.extents.z = floor_height/2
	
	mesh_instance.mesh.size.x = floor_width
	mesh_instance.mesh.size.z = floor_height
	
	
	self.transform.origin.x = x
	self.transform.origin.y = y
	self.transform.origin.z = z
	
	
	
