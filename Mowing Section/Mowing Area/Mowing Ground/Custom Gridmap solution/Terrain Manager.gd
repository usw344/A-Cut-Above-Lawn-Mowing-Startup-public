@tool
extends Node3D


		
# Run code once using tool feature
@export var toogle_run:bool = false
@export var toggle_clear:bool = false

var y_offset = 200 # for testing this will rase the stuff above the terrain for now
var grid_cell_size = 350

func _ready() -> void:
	pass
func _process(delta: float) -> void:
	if toogle_run == true:
		toogle_run = false
		test_code()
	if toggle_clear == true:
		toggle_clear = false
		clear_grid()
		
func clear_grid():
	for i in get_children():
		if i.name == "Central Mesh":
			continue
		else:
			i.queue_free()

func test_code():
	print("runnng code")
	clear_grid()
	var grid_coords:Array[Vector2i] = get_outer_grid_coords(3)
	
	add_planes_from_coords(grid_coords, grid_cell_size, self)
	var testing_mesh: Mesh = extract_mesh_from_glb("res://Assets/Foilage/trees/SM_Pine_A1.glb")
	## get the coords sorted by distance from center. 
	## 1 is closest to center and then on
	var sorted_coords:Dictionary = split_coords_into_rings(grid_coords)
	for coord in sorted_coords[1]:
		add_multimesh_for_cell(
		coord,
		grid_cell_size,
		testing_mesh,
		6,
		5.0,
		self
	)
	
	var coord_to_test: Vector2i = Vector2i(0,-1)
	#add_multimesh_for_cell(
		#coord_to_test,
		#grid_cell_size,
		#testing_mesh,
		#6,
		#5.0,
		#self
	#)

func get_outer_grid_coords(n: int) -> Array[Vector2i]:
	var coords: Array[Vector2i] = []
	for z in range(-n, n + 1):
		for x in range(-n, n + 1):
			if x == 0 and z == 0:
				continue
			coords.append(Vector2i(x, z))
	return coords

func split_coords_into_rings(coords: Array[Vector2i]) -> Dictionary:
	'''To control which ring around the center has which parameters 
	(Example closest ring might be densent and furthest only needs af few trees)
	'''
	# Result format:
	# {
	#   1: [Vector2i(...), Vector2i(...)],
	#   2: [Vector2i(...), Vector2i(...)],
	#   3: [Vector2i(...), Vector2i(...)]
	# }
	var rings: Dictionary = {}

	for coord in coords:
		# Skip center if it somehow got passed in
		if coord == Vector2i.ZERO:
			continue

		# Ring is the largest distance from center on either axis
		var ring: int = max(abs(coord.x), abs(coord.y))

		# If this ring does not exist yet, create an empty array for it
		if not rings.has(ring):
			rings[ring] = []

		# Add this coord to the correct ring
		rings[ring].append(coord)

	return rings


func add_multimesh_for_cell(
	grid_coord: Vector2i,
	cell_size: float,
	source_mesh: Mesh,
	instance_count: int,
	instance_scaling: float,
	parent_node: Node3D) -> MultiMeshInstance3D:
	# Create the MultiMesh resource.
	# This holds the mesh and all per-instance transforms.
	var multimesh: MultiMesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = source_mesh
	multimesh.instance_count = instance_count

	# Create the scene node that will render the MultiMesh.
	var multimesh_instance: MultiMeshInstance3D = MultiMeshInstance3D.new()
	multimesh_instance.name = "MM_%d_%d" % [grid_coord.x, grid_coord.y]
	multimesh_instance.multimesh = multimesh

	# Put this whole chunk at the grid cell location.
	# Example:
	# grid_coord (1, -1) with cell_size 300 becomes (300, 0, -300)
	multimesh_instance.position = Vector3(
		grid_coord.x * cell_size,
		y_offset,
		grid_coord.y * cell_size
	)

	# Random generator for scattering instances inside the cell.
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.randomize()

	# Fill the MultiMesh with random transforms.
	for i in range(instance_count):
		var transform: Transform3D = make_random_cell_transform(
		cell_size,
		source_mesh,
		rng,
		instance_scaling)
		# Store this transform into the MultiMesh.
		multimesh.set_instance_transform(i, transform)

	# Add the finished node to the scene.
	parent_node.add_child(multimesh_instance)
	multimesh_instance.owner = get_tree().edited_scene_root
	return multimesh_instance

func make_random_cell_transform(cell_size: float, 
	source_mesh:Mesh,
	rng: RandomNumberGenerator,
	further_scaling:float) -> Transform3D:
	# Pick a random position inside the local square of the cell.
	# These are local offsets because the MultiMeshInstance3D itself
	# will already be placed at the grid cell location.
	var local_x: float = rng.randf_range(-cell_size * 0.5, cell_size * 0.5)
	var local_z: float = rng.randf_range(-cell_size * 0.5, cell_size * 0.5)

	# Random Y rotation so instances do not all face the same way.
	var yaw: float = rng.randf_range(0.0, TAU)

	# Small random scale variation.
	var scale_value: float = rng.randf_range(0.9, 1.1)

	# Build the transform.
	# Later, this is the part you can expand to include terrain tilt.
	var basis: Basis = Basis(Vector3.UP, yaw)
	
	basis = basis.scaled(Vector3.ONE * scale_value * further_scaling)
	var y_value_to_offset = get_mesh_y_offset(source_mesh, scale_value * further_scaling)
	return Transform3D(
		basis,
		Vector3(local_x, y_value_to_offset, local_z)
	)

func make_foliage_multimeshes_for_cell(
	grid_coord: Vector2i,
	n: int, # this is the number of foliage types
	foliage_types: Array[String],
	parent_node: Node3D) -> Dictionary:
	'''
	For each type of foliage (rocks, grass different types of trees) makes 
	a multimesh object. 
	Gives output as a dictionary key = type valye = multimeshinstance3d
	'''
	# This will store:
	# key   = foliage name
	# value = MultiMeshInstance3D returned by add_multimesh_for_cell()
	var result: Dictionary = {}

	# Safety check:
	# If n is bigger than the number of foliage names we were given,
	# only loop over what actually exists.
	var count_to_make: int = min(n, foliage_types.size())

	for i in range(count_to_make):
		# Get the current foliage name from the list.
		var foliage_name: String = foliage_types[i]

		# --------------------------------------------------
		# TODO: Fill these in later with your real values.
		# For now these are placeholders so the function
		# structure is complete and easy to read.
		# --------------------------------------------------
		var cell_size: float = 0.0
		var source_mesh: Mesh = null
		var instance_count: int = 0
		var current_mesh_further_scaling:float = 5.0
		# Create one MultiMeshInstance3D for this foliage type.
		# This uses your helper from before.
		var multimesh_instance: MultiMeshInstance3D = add_multimesh_for_cell(
			grid_coord,
			cell_size,
			source_mesh,
			instance_count,
			current_mesh_further_scaling,
			parent_node
		)

		# Store it in the dictionary using the foliage name as the key.
		result[foliage_name] = multimesh_instance

	return result

func get_mesh_y_offset(source_mesh: Mesh, scale_value: float) -> float:
	'''Might not need this function later when using trees and stuff
	but for now this centeres the instances on top of the surface'''
	var aabb: AABB = source_mesh.get_aabb()
	return -aabb.position.y * scale_value

func extract_mesh_from_glb(glb_path: String) -> Mesh:
	'''
	Helper Function to extract Mesh objects from a given glb object
	This function makes it way easier than doing this by hand
	'''
	# Load the imported GLB resource.
	var resource: Resource = load(glb_path)
	if resource == null:
		push_error("Could not load GLB at path: " + glb_path)
		return null

	# Imported GLB scenes are usually PackedScene resources.
	if resource is PackedScene:
		var scene_instance: Node = (resource as PackedScene).instantiate()
		var found_mesh: Mesh = _find_first_mesh_in_node(scene_instance)
		scene_instance.free()
		return found_mesh

	# In case the path somehow points directly to a Mesh resource.
	if resource is Mesh:
		return resource as Mesh

	push_error("Resource at path is not a PackedScene or Mesh: " + glb_path)
	return null


func _find_first_mesh_in_node(node: Node) -> Mesh:
	'''
	Helper function to get the first MeshInstance3D in a given scene
	'''
	# If this node is a MeshInstance3D and has a mesh, return it.
	if node is MeshInstance3D:
		var mesh_instance: MeshInstance3D = node as MeshInstance3D
		if mesh_instance.mesh != null:
			return mesh_instance.mesh

	# Otherwise, search children recursively.
	for child in node.get_children():
		var found_mesh: Mesh = _find_first_mesh_in_node(child)
		if found_mesh != null:
			return found_mesh

	return null






##-------------- Debugging Stuff
var assigned_color_indices: Dictionary = {}

func add_planes_from_coords(coords: Array[Vector2i], plane_size: float, parent_node: Node3D) -> void:
	''' Good for debugging to see where the chunks are being drawn. '''
	for coord in coords:
		var container_node:Node3D = Node3D.new()
		var plane_mesh: PlaneMesh = PlaneMesh.new()
		plane_mesh.size = Vector2(plane_size, plane_size)

		var plane_instance: MeshInstance3D = MeshInstance3D.new()
		plane_instance.mesh = plane_mesh

		# coord.x controls left/right
		# coord.y controls forward/back
		plane_instance.position = Vector3(
			coord.x * plane_size,
			y_offset,
			coord.y * plane_size
		)
		plane_instance.material_override = make_plane_material(coord)
		parent_node.add_child(plane_instance)

		plane_instance.owner = get_tree().edited_scene_root

func make_plane_material(coord: Vector2i) -> StandardMaterial3D:
	var palette: Array[Color] = [
		Color(0.85, 0.30, 0.30, 1.0),
		Color(0.30, 0.75, 0.35, 1.0),
		Color(0.30, 0.50, 0.90, 1.0),
		Color(0.90, 0.75, 0.25, 1.0)
	]

	var blocked_indices: Array[int] = []

	# Only need to check already-created neighbors if you are
	# generating left-to-right, top-to-bottom.
	var left_coord: Vector2i = coord + Vector2i(-1, 0)
	var up_coord: Vector2i = coord + Vector2i(0, -1)

	if assigned_color_indices.has(left_coord):
		blocked_indices.append(assigned_color_indices[left_coord])

	if assigned_color_indices.has(up_coord):
		blocked_indices.append(assigned_color_indices[up_coord])

	var available_indices: Array[int] = []
	for i in range(palette.size()):
		if not blocked_indices.has(i):
			available_indices.append(i)

	# Deterministic random based on coord
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = hash(str(coord.x) + "," + str(coord.y))

	var chosen_index: int = available_indices[rng.randi_range(0, available_indices.size() - 1)]
	assigned_color_indices[coord] = chosen_index

	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = palette[chosen_index]

	return material
