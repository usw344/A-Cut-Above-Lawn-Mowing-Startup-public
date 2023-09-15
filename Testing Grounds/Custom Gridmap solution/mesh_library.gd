extends Node3D
class_name Mesh_List
## this is a custom representation of a Mesh_List class

# Called when the node enters the scene tree for the first time.
func _ready():
	pass # Replace with function body.

var mesh_storage:Dictionary = {}

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	pass

func get_mesh_by_id(id:int) ->Mesh:
	"""
	Return a Mesh for the given ID.
	
	CONDITION: id given MUST be set. If not this function will print an error statement
	and also add to error log
	"""
	if !mesh_storage.has(id):
		print("No mesh found for given ID: " + str(id))
		return Mesh.new() # empty return 
		
	return mesh_storage.get(id)
	
func set_mesh_with_id(mesh:Mesh, id:int):
	""" Set a mesh for a given ID
	
	"""
	mesh_storage[id] = mesh
