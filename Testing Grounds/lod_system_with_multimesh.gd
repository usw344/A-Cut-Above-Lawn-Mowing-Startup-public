extends Node3D


var width:int = 1500
var length:int = 1500

var grass_cell_size:int = int(width/16)

var mesh_scene = preload("res://Assets/Grass with LOD/objects/Mowed Grass High LOD.glb") # find the unmowed version
var mesh:Mesh
func _ready():
	var mesh_scene_instance = mesh_scene.instantiate()
	mesh = mesh_scene_instance.get_node("Mowed Grass High LOD2").mesh
	
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	pass
	
func generate_multimesh():
	var multi_meshinstance:MultiMeshInstance3D = $MultiMeshInstance3D
	var multi_mesh:MultiMesh = MultiMesh.new()
	
	var points_to_render:Array = get_positions()
	
	multi_mesh.set_mesh(mesh)
	multi_mesh.set_transform_format(MultiMesh.TRANSFORM_3D)
	multi_mesh.set_instance_count(500)

	for i in range(multi_mesh.instance_count):
		# get the point and translate it over to chunk space
		var point:Vector2 = translate_to_chunk(points_to_render[i])
		
		# set the information of this instance
		var scale_factor:float = randf_range(12.5,20.0)
		var basis_vector = Basis()*scale_factor
#		basis_vector = basis_vector.rotated(Vector3(0,0,1),randf_range(12.5,90.0))
#		basis_vector = basis_vector.rotated(Vector3(0,1,0),90)
		var transform_vector = Transform3D(basis_vector, Vector3(point.x, 0, point.y))
		
#		transform_vector = transform_vector.scaled(Vector3(scale_factor,scale_factor,scale_factor))
		
		
		multi_mesh.set_instance_transform(i, transform_vector)

	
	multi_meshinstance.multimesh = multi_mesh

func get_positions() ->Array:
	return []

func translate_to_chunk(coord:Vector2):
	pass
