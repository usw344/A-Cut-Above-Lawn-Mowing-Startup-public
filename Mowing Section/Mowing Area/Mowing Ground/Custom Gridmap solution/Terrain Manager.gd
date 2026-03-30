@tool
extends Node3D


		
# Run code once using tool feature
@export var toogle_run:bool = false
@export var toggle_clear:bool = false
@export var low_poly:bool = false

var y_offset = 140 # for testing this will rase the stuff above the terrain for now
var grid_cell_size = 350

## for each indice Ring 1 -> Ring 4. multiply the instance count to reduce the amount made there
var instance_count_adjustment:Array = [2.25, 1.5, 1.25, 0.85, 0.5]
# This is the database for 
# Foliage database
# Outer key   = foliage name
# Outer value = dictionary of settings for that foliage type
var foliage_database: Dictionary = {
	"tree": {
		"high": {
			"mesh": extract_mesh_from_glb("res://Assets/Foilage/trees/SM_Pine_A1.glb"),
			"density": 1.0,
			"instance_count": 4,
			"instance_scale": 2.0,
			"min_scale": 0.9,
			"max_scale": 1.1,
			"y_offset": 0.0
		},
		"low": {
			# Replace later if you choose a different low poly tree
			"mesh": extract_mesh_from_glb("res://Assets/Foilage/Low Poly/Trees/Tree_1_A_Color1.gltf"),
			"density": 1.0,
			"instance_count": 4,
			"instance_scale": 2.0 * LOW_POLY_SCALE_MULTIPLIER,
			"min_scale": 0.9,
			"max_scale": 1.1,
			"y_offset": 0.0
		},
		"collision_radius": 12.0
	},

	"tree2": {
		"high": {
			"mesh": extract_mesh_from_glb("res://Assets/Foilage/trees/SM_Pine_A2.glb"),
			"density": 0.7,
			"instance_count": 4,
			"instance_scale": 1.5,
			"min_scale": 1.0,
			"max_scale": 1.4,
			"y_offset": 0.0
		},
		"low": {
			# Safe placeholder path for now so nothing breaks
			# Replace with your second low poly tree when ready
			"mesh": extract_mesh_from_glb("res://Assets/Foilage/Low Poly/Trees/Tree_2_D_Color1.gltf"),
			"density": 0.7,
			"instance_count": 4,
			"instance_scale": 1.5 * LOW_POLY_SCALE_MULTIPLIER,
			"min_scale": 1.0,
			"max_scale": 1.4,
			"y_offset": 0.0
		},
		"collision_radius": 8.0
	},

	"tree3": {
		"high": {
			# Temporary third variant using an existing working mesh
			# Replace with your real third high poly tree later
			"mesh": extract_mesh_from_glb("res://Assets/Foilage/trees/SM_Pine_A3.glb"),
			"density": 0.8,
			"instance_count": 3,
			"instance_scale": 1.8,
			"min_scale": 0.95,
			"max_scale": 1.25,
			"y_offset": 0.0
		},
		"low": {
			# Temporary third variant using an existing working low poly mesh
			# Replace with your real third low poly tree later
			"mesh": extract_mesh_from_glb("res://Assets/Foilage/Low Poly/Trees/Tree_2_A_Color1.gltf"),
			"density": 0.8,
			"instance_count": 3,
			"instance_scale": 1.8 * LOW_POLY_SCALE_MULTIPLIER,
			"min_scale": 0.95,
			"max_scale": 1.25,
			"y_offset": 0.0
		},
		"collision_radius": 10.0
	},

	"shrub": {
		"high": {
			"mesh": extract_mesh_from_glb("res://Assets/Foilage/Shurbs/SM_Bush_A1.glb"),
			"density": 2.0,
			"instance_count": 30,
			"instance_scale": 1.0,
			"min_scale": 0.6,
			"max_scale": 1.0,
			"y_offset": 0.0
		},
		"low": {
			# Fallback to current mesh until you pick a low poly shrub
			"mesh": extract_mesh_from_glb("res://Assets/Foilage/Shurbs/SM_Bush_A1.glb"),
			"density": 2.0,
			"instance_count": 30,
			"instance_scale": 1.0,
			"min_scale": 0.6,
			"max_scale": 1.0,
			"y_offset": 0.0
		},
		"collision_radius": 5.0
	},

	"grass_lod1": {
		"high": {
			"mesh": extract_mesh_from_glb("res://Assets/Foilage/Shurbs/SM_Grass_A3.glb"),
			"instance_scale": 18.0,
			"min_scale": 0.85,
			"max_scale": 1.15,
			"grid_spacing": 26.0,
			"grid_jitter": 7.0,
			"fill_chance": 0.55,
			"visible_begin": 0.0,
			"visible_end": 900.0
		},
		"low": {
			# Fallback to current mesh until you pick a low poly grass
			"mesh": extract_mesh_from_glb("res://Assets/Foilage/Low Poly/Grass/Grass_2_C_Color1.gltf"),
			"instance_scale": 18.0,
			"min_scale": 0.85,
			"max_scale": 1.15,
			"grid_spacing": 26.0,
			"grid_jitter": 7.0,
			"fill_chance": 0.55,
			"visible_begin": 0.0,
			"visible_end": 900.0
		}
	},

	"grass_lod2": {
		"high": {
			"mesh": extract_mesh_from_glb("res://Assets/Foilage/Shurbs/SM_Grass_A3.glb"),
			"instance_scale": 24.0,
			"min_scale": 0.9,
			"max_scale": 1.2,
			"grid_spacing": 42.0,
			"grid_jitter": 10.0,
			"fill_chance": 0.38,
			"visible_begin": 500.0,
			"visible_end": 1800.0
		},
		"low": {
			# Fallback to current mesh until you pick a low poly grass
			"mesh": extract_mesh_from_glb("res://Assets/Foilage/Low Poly/Grass/Grass_1_A_Color1.gltf"),
			"instance_scale": 24.0,
			"min_scale": 0.9,
			"max_scale": 1.2,
			"grid_spacing": 42.0,
			"grid_jitter": 10.0,
			"fill_chance": 0.38,
			"visible_begin": 500.0,
			"visible_end": 1800.0
		}
	},

	"stone": {
		"high": {
			"mesh": BoxMesh.new(),
			"density": 0.4,
			"instance_count": 8,
			"instance_scale": 1.0,
			"min_scale": 0.7,
			"max_scale": 1.3,
			"y_offset": 0.0
		},
		"low": {
			"mesh": BoxMesh.new(),
			"density": 0.4,
			"instance_count": 8,
			"instance_scale": 1.0,
			"min_scale": 0.7,
			"max_scale": 1.3,
			"y_offset": 0.0
		},
		"collision_radius": 2.0
	},

	"stone2": {
		"high": {
			"mesh": BoxMesh.new(),
			"density": 0.35,
			"instance_count": 6,
			"instance_scale": 1.2,
			"min_scale": 0.8,
			"max_scale": 1.4,
			"y_offset": 0.0
		},
		"low": {
			"mesh": BoxMesh.new(),
			"density": 0.35,
			"instance_count": 6,
			"instance_scale": 1.2,
			"min_scale": 0.8,
			"max_scale": 1.4,
			"y_offset": 0.0
		},
		"collision_radius": 2.5
	}
}

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
	clear_foliage_occupancy()
func test_code():
	clear_grid()
	cache_ground_mesh_data()
	#add_planes_from_coords(grid_coords, grid_cell_size, self
	var grid_coords: Array[Vector2i] = get_outer_grid_coords(3)
	var sorted_coords: Dictionary = split_coords_into_rings(grid_coords)

	var rings_to_generate: int = 3
	## MAIN GENERATION CODE
	for i in rings_to_generate:
		var ring: int = i + 1

		# Skip if this ring is not in the dictionary
		if not sorted_coords.has(ring):
			continue

		for coord in sorted_coords[ring]:
			# ------------------------------------------
			# 1. Grass pass
			# ------------------------------------------
			var grass_type: String = get_grass_type_for_ring(ring)
			if grass_type != "":
				add_grass_multimesh_for_cell(
					coord,
					grass_type,
					grid_cell_size,
					self
				)

			# ------------------------------------------
			# 2. Trees / shrubs pass
			# ------------------------------------------
			#var foliage_to_generate = ["tree", "tree2", "shrub"]
			var foliage_to_generate = ["tree", "tree2", "tree3", "shrub"]
			# Later, when you want stones too:
			# var foliage_to_generate = ["tree", "tree2", "tree3", "shrub", "stone", "stone2"]
			#for type in foliage_to_generate:
				#add_multimesh_for_cell(
					#coord,
					#type,
					#grid_cell_size,
					#foliage_database[type]["mesh"],
					#foliage_database[type]["instance_count"] * instance_count_adjustment[i],
					#foliage_database[type]["instance_scale"],
					#self)
			for type in foliage_to_generate:
				add_multimesh_for_cell(
					coord,
					type,
					grid_cell_size,
					get_foliage_value(type, "mesh"),
					int(get_foliage_value(type, "instance_count") * instance_count_adjustment[i]),
					get_foliage_value(type, "instance_scale"),
					self
				)
	apply_far_grass_overlay($".", global_position)

func _______SETUP__CODE___________():
	pass

func get_outer_grid_coords(n: int) -> Array[Vector2i]:
	'''Returns coordiantes in form ()-1,-1), (0, -1) etc avoding 0,0 
	which is the center of the grid'''
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


const LOW_POLY_SCALE_MULTIPLIER: float = 4.0

func get_active_foliage_variant() -> String:
	if low_poly:
		return "low"
	return "high"


func get_foliage_value(foliage_name: String, key: String):
	# Read from the active variant first.
	# If that variant/key is missing, fall back to the other one.
	# This keeps things from breaking while you gradually add low poly assets.

	if not foliage_database.has(foliage_name):
		push_error("Missing foliage type: " + foliage_name)
		return null

	var foliage_entry: Dictionary = foliage_database[foliage_name]
	var preferred_variant: String = get_active_foliage_variant()
	var fallback_variant: String = "high"

	if preferred_variant == "high":
		fallback_variant = "low"

	if foliage_entry.has(preferred_variant):
		var preferred_data: Dictionary = foliage_entry[preferred_variant]
		if preferred_data.has(key) and preferred_data[key] != null:
			return preferred_data[key]

	if foliage_entry.has(fallback_variant):
		var fallback_data: Dictionary = foliage_entry[fallback_variant]
		if fallback_data.has(key) and fallback_data[key] != null:
			return fallback_data[key]

	# Also allow outer-level keys like collision_radius
	if foliage_entry.has(key):
		return foliage_entry[key]

	push_error("Missing key '%s' for foliage type: %s" % [key, foliage_name])
	return null




func _______FOLIAGE__CODE___________():
	pass

func add_multimesh_for_cell(

	grid_coord: Vector2i,
	foliage_name: String,
	cell_size: float,
	source_mesh: Mesh,
	instance_count: int,
	further_scaling:float,
	parent_node: Node3D
) -> MultiMeshInstance3D:
	'''
	Main Function that adds a multimesh with a given size. This multimesh will contain
	1 type of foliage with collision avoidance done when calcuting its transform for each instance
	'''
	# Create the MultiMesh resource.
	var multimesh: MultiMesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = source_mesh

	# Create the node that renders the MultiMesh.
	var multimesh_instance: MultiMeshInstance3D = MultiMeshInstance3D.new()
	multimesh_instance.name = "%s_%d_%d" % [foliage_name, grid_coord.x, grid_coord.y]
	multimesh_instance.multimesh = multimesh

	# Move this whole chunk to the grid cell.
	multimesh_instance.position = Vector3(
		grid_coord.x * cell_size,
		#y_offset,
		0.0,
		grid_coord.y * cell_size
	)

	# RNG for this cell.
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.randomize()

	# Collect only successful transforms.
	var accepted_transforms: Array[Transform3D] = []

	for i in range(instance_count):
		var result: Dictionary = make_random_cell_transform_with_collision(
			grid_coord,
			foliage_name,
			cell_size,
			source_mesh,
			rng,
			further_scaling,
			20
		)

		if result.get("success", false):
			accepted_transforms.append(result["transform"])

	# Final instance count = accepted placements only.
	multimesh.instance_count = accepted_transforms.size()

	for i in range(accepted_transforms.size()):
		multimesh.set_instance_transform(i, accepted_transforms[i])

	parent_node.add_child(multimesh_instance)
	multimesh_instance.owner = get_tree().edited_scene_root

	return multimesh_instance

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
		var source_mesh: Mesh = BoxMesh.new()
		var instance_count: int = 0
		var current_mesh_further_scaling:float = 5.0
		# Create one MultiMeshInstance3D for this foliage type.
		# This uses your helper from before.
		var multimesh_instance: MultiMeshInstance3D = add_multimesh_for_cell(
			grid_coord,
			"", # update this alter
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



# ============================================================
# Collision data
# key   = grid coord
# value = array of placed foliage entries in that cell
#
# Example:
# foliage_occupancy[Vector2i(1, 0)] = [
# 	{ "name": "tree", "pos": Vector2(10, -20) },
# 	{ "name": "shrub", "pos": Vector2(-30, 15) }
# ]
# ============================================================
var foliage_occupancy: Dictionary = {}

func _______COLLISION__CODE___________():
	pass

func clear_foliage_occupancy() -> void:
	# Call this before rebuilding the forest.
	foliage_occupancy.clear()


func ensure_foliage_cell_exists(grid_coord: Vector2i) -> void:
	# Make sure this cell has an array ready.
	if not foliage_occupancy.has(grid_coord):
		foliage_occupancy[grid_coord] = []

func get_foliage_collision_radius(foliage_name: String) -> float:
	if not foliage_database.has(foliage_name):
		return 0.0

	return foliage_database[foliage_name].get("collision_radius", 0.0)

#func get_foliage_collision_radius(foliage_name: String) -> float:
	## Pull the radius from your foliage database.
	## Add "collision_radius" to each foliage type.
	#if not foliage_database.has(foliage_name):
		#return 0.0
#
	#var foliage_data: Dictionary = foliage_database[foliage_name]
	#return foliage_data.get("collision_radius", 0.0)


func can_place_foliage_at_position(
	grid_coord: Vector2i,
	foliage_name: String,
	local_pos: Vector2
) -> bool:
	# Check whether this new item overlaps any existing item in the same cell.
	ensure_foliage_cell_exists(grid_coord)

	var my_radius: float = get_foliage_collision_radius(foliage_name)
	var placed_items: Array = foliage_occupancy[grid_coord]

	for item in placed_items:
		var other_name: String = item["name"]
		var other_pos: Vector2 = item["pos"]
		var other_radius: float = get_foliage_collision_radius(other_name)

		# Basic circle-vs-circle check in X/Z space.
		if local_pos.distance_to(other_pos) < (my_radius + other_radius):
			return false

	return true


func register_foliage_position(
	grid_coord: Vector2i,
	foliage_name: String,
	local_pos: Vector2
) -> void:
	# Save the accepted placement.
	ensure_foliage_cell_exists(grid_coord)
	# ADD dict entry for the new item
	foliage_occupancy[grid_coord].append({
		"name": foliage_name,
		"pos": local_pos
	})

func make_random_cell_transform_with_collision(
	grid_coord: Vector2i,
	foliage_name: String,
	cell_size: float,
	source_mesh: Mesh,
	rng: RandomNumberGenerator,
	further_scaling: float,
	max_attempts: int = 20
) -> Dictionary:
	for attempt in range(max_attempts):
		# Random local position inside the current cell.
		var local_x: float = rng.randf_range(-cell_size * 0.5, cell_size * 0.5)
		var local_z: float = rng.randf_range(-cell_size * 0.5, cell_size * 0.5)
		var local_pos_2d: Vector2 = Vector2(local_x, local_z)

		# Reject overlap inside this cell.
		if not can_place_foliage_at_position(grid_coord, foliage_name, local_pos_2d):
			continue

		# Build the world-space sample position for this random point.
		var chunk_origin_local: Vector3 = Vector3(
			grid_coord.x * cell_size,
			0.0,
			grid_coord.y * cell_size
		)

		var sample_world: Vector3 = to_global(
			chunk_origin_local + Vector3(local_x, 0.0, local_z)
		)

		# Sample the ground mesh directly.
		var ground_hit: Dictionary = sample_ground_world_position(sample_world.x, sample_world.z)

		# Retry if this point is outside the ground mesh.
		if ground_hit.is_empty():
			continue

		# Random rotation.
		var yaw: float = rng.randf_range(0.0, TAU)

		# Random scale.
		var scale_value: float = rng.randf_range(0.9, 1.1)

		# Build basis.
		var basis: Basis = Basis(Vector3.UP, yaw)
		basis = basis.scaled(Vector3.ONE * scale_value * further_scaling)

		# Convert ground hit back into this generator node's local space.
		var hit_local_to_self: Vector3 = to_local(ground_hit["position"])

		# Convert that into local space relative to the chunk center.
		var local_y: float = hit_local_to_self.y - chunk_origin_local.y

		# Add mesh-bottom offset so the base sits on the terrain.
		var mesh_y_offset: float = get_mesh_y_offset(source_mesh, scale_value * further_scaling)

		var transform: Transform3D = Transform3D(
			basis,
			Vector3(local_x, local_y + mesh_y_offset, local_z)
		)

		# Save accepted placement.
		register_foliage_position(grid_coord, foliage_name, local_pos_2d)

		return {
			"success": true,
			"transform": transform,
			"ground_normal": ground_hit["normal"]
		}

	return {
		"success": false
	}
#func make_random_cell_transform_with_collision(
	#grid_coord: Vector2i,
	#foliage_name: String,
	#cell_size: float,
	#source_mesh: Mesh,
	#rng: RandomNumberGenerator,
	#further_scaling:float,
	#max_attempts: int = 20
#) -> Dictionary:
	#'''
	#Generate a unique transform (in terms of position) for a given instance
	#
	#This function is used inside add_multimesh_for_cell and it ensures that
	#no foliage overlaps.
	#'''
	## Try several random positions until one does not collide.
	#for attempt in range(max_attempts):
		#var local_x: float = rng.randf_range(-cell_size * 0.5, cell_size * 0.5)
		#var local_z: float = rng.randf_range(-cell_size * 0.5, cell_size * 0.5)
		#var local_pos_2d: Vector2 = Vector2(local_x, local_z)
#
		## Retry if this position collides.
		#if not can_place_foliage_at_position(grid_coord, foliage_name, local_pos_2d):
			#continue
#
		## Random rotation.
		#var yaw: float = rng.randf_range(0.0, TAU)
#
		## Random scale.
		#var scale_value: float = rng.randf_range(0.9, 1.1)
#
		## Build basis.
		#var basis: Basis = Basis(Vector3.UP, yaw)
		#basis = basis.scaled(Vector3.ONE * scale_value * further_scaling)
#
		## Lift mesh so it sits above the cell floor.
		#var y_offset: float = get_mesh_y_offset(source_mesh, scale_value * further_scaling)
#
		## Build final transform.
		#var transform: Transform3D = Transform3D(
			#basis,
			#Vector3(local_x, y_offset, local_z)
		#)
#
		## Save accepted placement.
		#register_foliage_position(grid_coord, foliage_name, local_pos_2d)
#
		#return {
			#"success": true,
			#"transform": transform
		#}
#
	## Nothing found after retries.
	#return {
		#"success": false
	#}
# --------------------------------------------------
# Ground sampling data
# This helps ensure that all foliage rests on top of the terrain
# --------------------------------------------------
func _______GROUND__CODE___________():
	pass
var ground_mesh_instance: MeshInstance3D
var ground_triangle_mesh: TriangleMesh = null

func cache_ground_mesh_data() -> void:
	
	##Convert the current ground mesh into a usable triange Mesh
	##This will allow us to sample the height at a given vertex point
	
	# Find the ground mesh node once.
	ground_mesh_instance = $"." as MeshInstance3D

	if ground_mesh_instance == null:
		push_error("ground_mesh_path must point to a MeshInstance3D")
		return

	if ground_mesh_instance.mesh == null:
		push_error("Ground mesh instance has no mesh")
		return

	# Build a TriangleMesh from the visual mesh.
	# No physics collision needed.
	ground_triangle_mesh = ground_mesh_instance.mesh.generate_triangle_mesh()

	if ground_triangle_mesh == null:
		push_error("Could not generate TriangleMesh from ground mesh")

func sample_ground_world_position(world_x: float, world_z: float) -> Dictionary:
	# Safety check.
	if ground_mesh_instance == null or ground_triangle_mesh == null:
		return {}

	# Start far above and far below.
	# These are world positions.
	var world_top: Vector3 = Vector3(world_x, 10000.0, world_z)
	var world_bottom: Vector3 = Vector3(world_x, -10000.0, world_z)

	# Convert into ground-mesh local space.
	# TriangleMesh intersection uses the mesh's local coordinates.
	var local_top: Vector3 = ground_mesh_instance.to_local(world_top)
	var local_bottom: Vector3 = ground_mesh_instance.to_local(world_bottom)

	# Intersect the vertical segment with the ground mesh.
	var hit: Dictionary = ground_triangle_mesh.intersect_segment(local_top, local_bottom)

	if hit.is_empty():
		return {}

	# Convert hit position and normal back to world space.
	var hit_local_position: Vector3 = hit["position"]
	var hit_local_normal: Vector3 = hit["normal"]

	return {
		"position": ground_mesh_instance.to_global(hit_local_position),
		"normal": ground_mesh_instance.global_basis * hit_local_normal
	}


func _______GRASS__CODE___________():
	pass
var grass_lod1_ring_count: int = 1
var grass_lod2_ring_count: int = 1

func get_grass_type_for_ring(ring: int) -> String:
	if ring <= grass_lod1_ring_count:
		return "grass_lod1"

	if ring <= grass_lod1_ring_count + grass_lod2_ring_count:
		return "grass_lod2"

	return ""

func make_grass_grid_transform(
	grid_coord: Vector2i,
	cell_size: float,
	local_x: float,
	local_z: float,
	source_mesh: Mesh,
	scale_min: float,
	scale_max: float,
	further_scaling: float,
	rng: RandomNumberGenerator
) -> Dictionary:
	# World-space chunk origin
	var chunk_origin_local: Vector3 = Vector3(
		grid_coord.x * cell_size,
		0.0,
		grid_coord.y * cell_size
	)

	# World-space sample point for this grass clump
	var sample_world: Vector3 = to_global(
		chunk_origin_local + Vector3(local_x, 0.0, local_z)
	)

	# Ask the ground mesh where the terrain is here
	var ground_hit: Dictionary = sample_ground_world_position(sample_world.x, sample_world.z)
	if ground_hit.is_empty():
		return { "success": false }

	# Random yaw
	var yaw: float = rng.randf_range(0.0, TAU)

	# Random scale
	var scale_value: float = rng.randf_range(scale_min, scale_max)

	# Build basis
	var basis: Basis = Basis(Vector3.UP, yaw)
	basis = basis.scaled(Vector3.ONE * scale_value * further_scaling)

	# Convert hit position into local space for this generator node
	var hit_local_to_self: Vector3 = to_local(ground_hit["position"])

	# Convert into local space relative to this chunk center
	var local_y: float = hit_local_to_self.y - chunk_origin_local.y

	# Lift mesh so it sits on the ground
	var mesh_y_offset: float = get_mesh_y_offset(source_mesh, scale_value * further_scaling)

	return {
		"success": true,
		"transform": Transform3D(
			basis,
			Vector3(local_x, local_y + mesh_y_offset, local_z)
		)
	}


func add_grass_multimesh_for_cell(
	grid_coord: Vector2i,
	grass_type: String,
	cell_size: float,
	parent_node: Node3D
) -> MultiMeshInstance3D:
	if grass_type == "":
		return null

	if not foliage_database.has(grass_type):
		push_error("Missing grass type in foliage_database: " + grass_type)
		return null

	var grass_data: Dictionary = foliage_database[grass_type]

	#var source_mesh: Mesh = grass_data["mesh"]
	#var further_scaling: float = grass_data["instance_scale"]
	#var scale_min: float = grass_data["min_scale"]
	#var scale_max: float = grass_data["max_scale"]
	#var grid_spacing: float = grass_data["grid_spacing"]
	#var grid_jitter: float = grass_data["grid_jitter"]
	#var fill_chance: float = grass_data["fill_chance"]

	var source_mesh: Mesh = get_foliage_value(grass_type, "mesh")
	var further_scaling: float = get_foliage_value(grass_type, "instance_scale")
	var scale_min: float = get_foliage_value(grass_type, "min_scale")
	var scale_max: float = get_foliage_value(grass_type, "max_scale")
	var grid_spacing: float = get_foliage_value(grass_type, "grid_spacing")
	var grid_jitter: float = get_foliage_value(grass_type, "grid_jitter")
	var fill_chance: float = get_foliage_value(grass_type, "fill_chance")

	var multimesh: MultiMesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = source_mesh

	var multimesh_instance: MultiMeshInstance3D = MultiMeshInstance3D.new()
	multimesh_instance.name = "%s_%d_%d" % [grass_type, grid_coord.x, grid_coord.y]
	multimesh_instance.multimesh = multimesh
	multimesh_instance.position = Vector3(
		grid_coord.x * cell_size,
		0.0,
		grid_coord.y * cell_size
	)

	# Optional distance culling / HLOD style visibility
	#multimesh_instance.visibility_range_begin = grass_data.get("visible_begin", 0.0)
	#multimesh_instance.visibility_range_end = grass_data.get("visible_end", 0.0)
	multimesh_instance.visibility_range_begin = get_foliage_value(grass_type, "visible_begin")
	multimesh_instance.visibility_range_end = get_foliage_value(grass_type, "visible_end")
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.randomize()

	var accepted_transforms: Array[Transform3D] = []

	var half_size: float = cell_size * 0.5
	var x_count: int = int(floor(cell_size / grid_spacing))
	var z_count: int = int(floor(cell_size / grid_spacing))

	for gz in range(z_count):
		for gx in range(x_count):
			# Leave some slots empty so the ground still shows through
			if rng.randf() > fill_chance:
				continue

			# Base grid point
			var base_x: float = -half_size + grid_spacing * 0.5 + gx * grid_spacing
			var base_z: float = -half_size + grid_spacing * 0.5 + gz * grid_spacing

			# Mild random jitter
			var local_x: float = base_x + rng.randf_range(-grid_jitter, grid_jitter)
			var local_z: float = base_z + rng.randf_range(-grid_jitter, grid_jitter)

			var result: Dictionary = make_grass_grid_transform(
				grid_coord,
				cell_size,
				local_x,
				local_z,
				source_mesh,
				scale_min,
				scale_max,
				further_scaling,
				rng
			)

			if result.get("success", false):
				accepted_transforms.append(result["transform"])

	multimesh.instance_count = accepted_transforms.size()

	for i in range(accepted_transforms.size()):
		multimesh.set_instance_transform(i, accepted_transforms[i])

	parent_node.add_child(multimesh_instance)
	multimesh_instance.owner = get_tree().edited_scene_root

	return multimesh_instance

func apply_far_grass_overlay(ground_mesh_instance: MeshInstance3D, center_world: Vector3) -> void:
	var shader: Shader = Shader.new()
	shader.code = """
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back;

uniform vec3 center_world = vec3(0.0, 0.0, 0.0);
uniform float cell_size = 350.0;
uniform int lod1_rings = 1;
uniform int lod2_rings = 1;
uniform vec4 grass_tint : source_color = vec4(0.30, 0.55, 0.22, 1.0);
uniform float alpha_strength = 0.20;
uniform float noise_scale = 0.004;

varying vec3 world_pos;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float dx = abs(world_pos.x - center_world.x);
	float dz = abs(world_pos.z - center_world.z);
	float cheby = max(dx, dz);

	float inner_radius = float(lod1_rings + lod2_rings) * cell_size;
	float outer_radius = inner_radius + cell_size * 3.0;

	float ring_mask = smoothstep(inner_radius, outer_radius, cheby);

	float noise_value = hash12(world_pos.xz * noise_scale);
	float patch_mask = smoothstep(0.35, 0.8, noise_value);

	ALBEDO = grass_tint.rgb;
	ALPHA = ring_mask * patch_mask * alpha_strength;
}
"""

	var mat: ShaderMaterial = ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("center_world", center_world)
	mat.set_shader_parameter("cell_size", grid_cell_size)
	mat.set_shader_parameter("lod1_rings", grass_lod1_ring_count)
	mat.set_shader_parameter("lod2_rings", grass_lod2_ring_count)

	ground_mesh_instance.material_overlay = mat

func _______DEBUGGING__CODE___________():
	pass



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
