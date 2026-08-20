extends SceneTree
## DEVELOPMENT ONLY. Finds Z-fighting BEFORE it is rendered. Walks a scene,
## computes every MeshInstance3D's world AABB, and reports pairs that share a
## face PLANE -- same axis, same side, same coordinate -- while overlapping on
## the other two axes. That is the exact geometric condition for two opaque
## surfaces to tie in the depth buffer.
##
##   godot --headless --path . --script "res://Dev tools/Validation/coplanar_probe.gd" ##       -- "--coplanar-scene=res://<scene>.tscn"
##
## Two things to know when reading the output:
##
## - `ymin` pairs are almost always boxes SITTING on the same ground plane.
##   Those faces point down and are never drawn; ignore them.
## - An AABB face is only a real surface for an axis-aligned box. Trees, bushes,
##   cars and rotated props report bounding planes that no geometry lies in.
##   Confirm anything organic or rotated against `Town Probe`, which measures
##   the artefact in pixels instead of inferring it.

const DEFAULT_TARGET := "res://Main Area/ACA_BusinessTown/BusinessTown.tscn"
const EPS := 0.004
const MIN_OVERLAP := 0.04
const AXES := ["x", "y", "z"]

var _items: Array = []


func _target() -> String:
	for arg in OS.get_cmdline_user_args() + OS.get_cmdline_args():
		if arg.begins_with("--coplanar-scene="):
			return arg.trim_prefix("--coplanar-scene=")
	return DEFAULT_TARGET


func _initialize() -> void:
	var target := _target()
	var ps: PackedScene = load(target)
	if ps == null:
		printerr("[COPLANAR] cannot load %s" % target)
		quit(1)
		return
	var root: Node = ps.instantiate()
	_walk(root, Transform3D.IDENTITY, "")
	print("[COPLANAR] %d mesh instances in %s" % [_items.size(), target])

	var hits := 0
	for i in range(_items.size()):
		for j in range(i + 1, _items.size()):
			var a: Dictionary = _items[i]
			var b: Dictionary = _items[j]
			var aa: AABB = a.aabb
			var ba: AABB = b.aabb
			for axis in 3:
				var o1: int = (axis + 1) % 3
				var o2: int = (axis + 2) % 3
				var ov1: float = minf(aa.end[o1], ba.end[o1]) - maxf(aa.position[o1], ba.position[o1])
				var ov2: float = minf(aa.end[o2], ba.end[o2]) - maxf(aa.position[o2], ba.position[o2])
				if ov1 < MIN_OVERLAP or ov2 < MIN_OVERLAP:
					continue
				# The two boxes must actually meet on this axis, not merely
				# share a plane while sitting far apart on it.
				if minf(aa.end[axis], ba.end[axis]) - maxf(aa.position[axis], ba.position[axis]) < -EPS:
					continue
				for side in [["min", aa.position[axis], ba.position[axis]],
						["max", aa.end[axis], ba.end[axis]]]:
					if absf(float(side[1]) - float(side[2])) > EPS:
						continue
					hits += 1
					print("[COPLANAR %s%s = %.4f | overlap %.2f x %.2f]\n    %s\n    %s"
						% [AXES[axis], side[0], float(side[1]), ov1, ov2, a.path, b.path])
	print("[COPLANAR] %d coplanar face pairs" % hits)
	root.free()
	quit(0)


func _walk(n: Node, parent_xform: Transform3D, path: String) -> void:
	var xform := parent_xform
	if n is Node3D:
		xform = parent_xform * (n as Node3D).transform
	var here := path + "/" + n.name
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		if mi.mesh != null and mi.visible:
			_items.append({"path": here, "aabb": xform * mi.mesh.get_aabb()})
	for c in n.get_children():
		_walk(c, xform, here)
