extends SceneTree

const SCENE_PATH := "res://UI/Scenic Background for Menus/scenery/scenes/main_menu_scenery.tscn"


func _init() -> void:
	var failures: Array[String] = []
	var packed := load(SCENE_PATH) as PackedScene
	if packed == null:
		failures.append("Could not load main menu scenery scene")
		_finish(failures)
		return

	var scenery := packed.instantiate()
	root.add_child(scenery)
	scenery.call("_refresh_layout")
	scenery.call("_configure_environment")

	var camera := scenery.get_node_or_null("Camera3D") as Camera3D
	if camera == null or not camera.current:
		failures.append("Production camera is missing or inactive")
	elif camera.position.y > 3.1 or camera.fov < 42.0:
		failures.append("Production camera is no longer using the lower head-on framing")
	if scenery.get_node_or_null("Sky3D/Skydome") == null:
		failures.append("Saved Sky3D hierarchy is incomplete")
	var sky_environment := scenery.get_node_or_null("Sky3D") as WorldEnvironment
	if sky_environment == null or sky_environment.camera_attributes == null:
		failures.append("Saved camera attributes are missing")
	elif (
		not sky_environment.camera_attributes.dof_blur_near_enabled
		or not sky_environment.camera_attributes.dof_blur_far_enabled
	):
		failures.append("Restrained menu depth of field is not enabled")
	if (
		sky_environment != null
		and sky_environment.environment != null
		and sky_environment.environment.resource_path
		!= "res://UI/Scenic Background for Menus/scenery/environments/main_menu_environment.tres"
	):
		failures.append("Menu environment is no longer using the reusable saved resource")
	var repeated_scenery := packed.instantiate()
	var repeated_sky := repeated_scenery.get_node_or_null("Sky3D") as WorldEnvironment
	if (
		sky_environment == null
		or repeated_sky == null
		or repeated_sky.environment != sky_environment.environment
	):
		failures.append("Repeated menu instances no longer share one renderer environment")
	repeated_scenery.free()
	if sky_environment != null and sky_environment.environment != null:
		if not sky_environment.environment.ssao_enabled:
			failures.append("Modern contact-depth pass is not enabled")
		if not sky_environment.environment.fog_enabled:
			failures.append("Atmospheric depth fog is not enabled")
		if not sky_environment.environment.glow_enabled:
			failures.append("Restrained atmospheric glow is not enabled")
		if not sky_environment.environment.volumetric_fog_enabled:
			failures.append("Crepuscular ray volume is not enabled")
		elif sky_environment.environment.volumetric_fog_density <= 0.0:
			failures.append("Crepuscular ray volume has no participating density")
		elif sky_environment.environment.volumetric_fog_anisotropy < 0.5:
			failures.append("Crepuscular ray scattering is no longer forward-directed")
	var sun := scenery.get_node_or_null("Sky3D/SunLight") as DirectionalLight3D
	if sun == null or not sun.shadow_enabled:
		failures.append("Shadow-casting sun for crepuscular rays is missing")
	elif sun.light_volumetric_fog_energy < 20.0:
		failures.append("Sun contribution to crepuscular rays is too low")
	var fill := scenery.get_node_or_null("FillLight") as DirectionalLight3D
	if fill != null and fill.light_volumetric_fog_energy > 0.0:
		failures.append("Fill light is diluting the directional crepuscular rays")
	if scenery.get_node_or_null("SceneryWindController") == null:
		failures.append("Shared scenery wind controller is missing")
	if scenery.get_node_or_null("MenuSafeOverlay/Gradient") == null:
		failures.append("Menu-safe readability overlay is missing")
	var far_mountain := scenery.get_node_or_null("MountainBackdrop/FarRange") as MeshInstance3D
	var mid_mountain := scenery.get_node_or_null("MountainBackdrop/MidRange") as MeshInstance3D
	if far_mountain == null or far_mountain.mesh == null or mid_mountain == null or mid_mountain.mesh == null:
		failures.append("Layered procedural mountain backdrop is incomplete")
	var pollen := scenery.get_node_or_null("AmbientPollen") as GPUParticles3D
	if pollen == null or pollen.amount < 150 or pollen.process_material == null:
		failures.append("Ambient pollen layer is missing or incomplete")
	elif (
		pollen.get_node_or_null("NearPollen") == null
		or (pollen.get_node("NearPollen") as GPUParticles3D).amount < 50
	):
		failures.append("Amplified near-pollen layer is missing or incomplete")
	if scenery.get_node_or_null("StylizedMower") != null:
		failures.append("Retired mower prop is still present in the production scene")
	var trees := scenery.get_node_or_null("Trees")
	if trees == null or trees.get_child_count() < 17:
		failures.append("Production tree layer is incomplete")
	else:
		var shared_wood_meshes := {}
		var shared_foliage_meshes := {}
		for tree in trees.get_children():
			if tree.has_method("rebuild"):
				tree.call("rebuild")
			var wood := tree.get_node_or_null("Wood") as MeshInstance3D
			var foliage := tree.get_node_or_null("Foliage") as MeshInstance3D
			if wood == null or wood.mesh == null or foliage == null or foliage.mesh == null:
				failures.append("Procedural tree geometry is incomplete: %s" % tree.name)
			else:
				shared_wood_meshes[wood.mesh.get_instance_id()] = true
				shared_foliage_meshes[foliage.mesh.get_instance_id()] = true
		if shared_wood_meshes.size() > 3 or shared_foliage_meshes.size() > 3:
			failures.append("Procedural tree variants are no longer sharing cached meshes")
	var dense_grass := scenery.get_node_or_null("DenseGrassField")
	if dense_grass == null:
		failures.append("Dense mowing-game grass field is missing")
	else:
		dense_grass.call("rebuild")
		var dense_a1 := dense_grass.get_node_or_null("GrassA1Field") as MultiMeshInstance3D
		var dense_a2 := dense_grass.get_node_or_null("GrassA2Field") as MultiMeshInstance3D
		if dense_a1 == null or dense_a2 == null:
			failures.append("Dense grass MultiMeshes were not generated")
		elif dense_a1.multimesh.instance_count + dense_a2.multimesh.instance_count < 800:
			failures.append("Dense grass field instance count is below the production target")
	var rocks := scenery.get_node_or_null("Rocks")
	if rocks == null or rocks.get_child_count() < 12:
		failures.append("Noise-deformed rock dressing is incomplete")

	if camera != null:
		scenery.call("reset_camera_drift")
		var resting_position := camera.position
		scenery.call("_process", 5.0)
		if camera.position.distance_to(resting_position) < 0.001:
			failures.append("Ambient camera drift did not update the production camera")
		scenery.call("reset_camera_drift")

	var grounded_count := 0
	var grounded_nodes: Array[Node3D] = []
	_collect_grounded(scenery, grounded_nodes)
	for node in grounded_nodes:
		grounded_count += 1
		var expected_height: float = scenery.call(
			"terrain_height",
			Vector2(node.position.x, node.position.z)
		) + float(node.get_meta("ground_offset", 0.0))
		if not is_equal_approx(node.position.y, expected_height):
			failures.append("Grounding mismatch: %s" % node.name)
	if grounded_count < 35:
		failures.append("Expected layered vegetation/rocks; found only %d grounded anchors" % grounded_count)

	for resource_path in [
		"res://UI/Scenic Background for Menus/scenery/materials/rolling_ground.tres",
		"res://UI/Scenic Background for Menus/scenery/materials/menu_safe_overlay.tres",
		"res://UI/Scenic Background for Menus/scenery/materials/mountain_far.tres",
		"res://UI/Scenic Background for Menus/scenery/materials/mountain_mid.tres",
		"res://UI/Scenic Background for Menus/scenery/materials/procedural_rock_warm.tres",
		"res://UI/Scenic Background for Menus/scenery/materials/procedural_rock_cool.tres",
	]:
		var material := load(resource_path) as ShaderMaterial
		if material == null or material.shader == null:
			failures.append("Could not load saved shader material: %s" % resource_path)
	var ground_material := load("res://UI/Scenic Background for Menus/scenery/materials/rolling_ground.tres") as ShaderMaterial
	if ground_material != null:
		var ground_color: Vector3 = ground_material.get_shader_parameter("high_color")
		if ground_color.x <= ground_color.y:
			failures.append("Ground palette is no longer soil-dominant")

	scenery.free()
	_finish(failures)


func _collect_grounded(node: Node, result: Array[Node3D]) -> void:
	for child in node.get_children():
		if child is Node3D and child.is_in_group("scenery_grounded"):
			result.append(child as Node3D)
		_collect_grounded(child, result)


func _finish(failures: Array[String]) -> void:
	if failures.is_empty():
		print("MAIN_MENU_SCENERY_TEST: PASS")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("MAIN_MENU_SCENERY_TEST: FAIL (", failures.size(), ")")
	quit(1)
