extends SceneTree

const TREE_MATERIAL_PATHS := [
	"res://UI/Scenic Background for Menus/scenery_wind/materials/tree_1_a_wind.tres",
	"res://UI/Scenic Background for Menus/scenery_wind/materials/tree_2_a_wind.tres",
	"res://UI/Scenic Background for Menus/scenery_wind/materials/tree_2_d_wind.tres",
	"res://UI/Scenic Background for Menus/scenery_wind/materials/procedural_tree_bark_wind.tres",
	"res://UI/Scenic Background for Menus/scenery_wind/materials/procedural_tree_foliage_wind.tres",
]
const GRASS_MATERIAL_PATHS := [
	"res://UI/Scenic Background for Menus/scenery_wind/materials/grass_a1_wind.tres",
	"res://UI/Scenic Background for Menus/scenery_wind/materials/grass_a2_wind.tres",
]
const WRAPPER_SCENE_PATHS := [
	"res://UI/Scenic Background for Menus/scenery_wind/scenes/tree_1_a_wind.tscn",
	"res://UI/Scenic Background for Menus/scenery_wind/scenes/tree_2_a_wind.tscn",
	"res://UI/Scenic Background for Menus/scenery_wind/scenes/tree_2_d_wind.tscn",
	"res://UI/Scenic Background for Menus/scenery_wind/scenes/grass_a1_wind.tscn",
	"res://UI/Scenic Background for Menus/scenery_wind/scenes/grass_a2_wind.tscn",
	"res://UI/Scenic Background for Menus/scenery/trees/organic_tree_round.tscn",
	"res://UI/Scenic Background for Menus/scenery/trees/organic_tree_open.tscn",
	"res://UI/Scenic Background for Menus/scenery/trees/organic_tree_tall.tscn",
]


func _init() -> void:
	var failures: Array[String] = []
	for path in TREE_MATERIAL_PATHS + GRASS_MATERIAL_PATHS:
		var material := load(path) as ShaderMaterial
		if material == null or material.shader == null:
			failures.append("Could not load shader material: %s" % path)

	for path in WRAPPER_SCENE_PATHS:
		var packed := load(path) as PackedScene
		if packed == null:
			failures.append("Could not load wrapper scene: %s" % path)
			continue
		var instance := packed.instantiate()
		root.add_child(instance)
		# SceneTree _init runs before the first ready notification, so invoke the
		# same deterministic application path directly for this smoke test.
		if instance.has_method("_apply_material"):
			instance.call("_apply_material", instance)
		elif instance.has_method("rebuild"):
			instance.call("rebuild")
		if not _contains_wind_mesh(instance):
			failures.append("No mesh received a wind material: %s" % path)
		instance.free()

	var controller_scene := load("res://UI/Scenic Background for Menus/scenery_wind/scenes/scenery_wind_controller.tscn") as PackedScene
	if controller_scene == null:
		failures.append("Could not load SceneryWindController scene")
	else:
		var controller := controller_scene.instantiate()
		root.add_child(controller)
		controller.set("wind_direction", Vector2(4.0, 3.0))
		controller.set("tree_wind_strength", 0.061)
		controller.set("tree_wind_speed", 0.63)
		controller.set("tree_gust_strength", 0.029)
		controller.call("_apply_wind")
		var materials: Array = controller.get("tree_materials")
		var test_material: ShaderMaterial = materials[0]
		if not is_equal_approx(test_material.get_shader_parameter("wind_strength"), 0.061):
			failures.append("Controller did not propagate tree_wind_strength")
		if not (test_material.get_shader_parameter("wind_direction") as Vector2).is_equal_approx(Vector2(0.8, 0.6)):
			failures.append("Controller did not normalize/propagate wind_direction")
		var procedural_material := load(
			"res://UI/Scenic Background for Menus/scenery_wind/materials/procedural_tree_foliage_wind.tres"
		) as ShaderMaterial
		if procedural_material == null or float(procedural_material.get_shader_parameter("surface_noise_strength")) <= 0.0:
			failures.append("Procedural tree foliage noise breakup is missing")
		elif float(procedural_material.get_shader_parameter("subsurface_strength")) <= 0.0:
			failures.append("Procedural foliage subsurface transmission is missing")
		controller.free()

	if failures.is_empty():
		print("SCENERY_WIND_TEST: PASS")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		print("SCENERY_WIND_TEST: FAIL (", failures.size(), ")")
		quit(1)


func _contains_wind_mesh(node: Node) -> bool:
	if node is MeshInstance3D and (node as MeshInstance3D).material_override is ShaderMaterial:
		return true
	for child in node.get_children():
		if _contains_wind_mesh(child):
			return true
	return false
