extends SceneTree

const FIELD_PATH := "res://scenery/scenes/dense_grass_field.tscn"


func _init() -> void:
	var failures: Array[String] = []
	var total_instances := 0
	var cut_instances := 0
	var packed := load(FIELD_PATH) as PackedScene
	if packed == null:
		failures.append("Could not load dense grass field scene")
		_finish(failures, total_instances, cut_instances)
		return

	var field := packed.instantiate()
	root.add_child(field)
	field.call("rebuild")
	var field_a1 := field.get_node_or_null("GrassA1Field") as MultiMeshInstance3D
	var field_a2 := field.get_node_or_null("GrassA2Field") as MultiMeshInstance3D
	if field_a1 == null or field_a2 == null:
		failures.append("One or both generated MultiMesh fields are missing")
	else:
		total_instances = field_a1.multimesh.instance_count + field_a2.multimesh.instance_count
		if total_instances < 800:
			failures.append("Dense field generated only %d instances" % total_instances)
		if not field_a1.material_override is ShaderMaterial or not field_a2.material_override is ShaderMaterial:
			failures.append("Dense fields are missing saved wind materials")
		if (
			field_a1.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			or field_a2.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		):
			failures.append("Dense alpha-cut grass shadows were re-enabled and may stall the scene")
		if field_a1.multimesh.mesh == null or field_a2.multimesh.mesh == null:
			failures.append("Dense fields did not resolve the supplied grass meshes")

		cut_instances = int(field.get("generated_cut_count"))
		if cut_instances == 0:
			failures.append("Mown lane did not generate any short-cut grass")

	field.free()
	_finish(failures, total_instances, cut_instances)


func _finish(failures: Array[String], total_instances: int, cut_instances: int) -> void:
	if failures.is_empty():
		print(
			"DENSE_GRASS_FIELD_TEST: PASS (",
			total_instances,
			" clumps, ",
			cut_instances,
			" cut-lane clumps)"
		)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("DENSE_GRASS_FIELD_TEST: FAIL (", failures.size(), ")")
	quit(1)
