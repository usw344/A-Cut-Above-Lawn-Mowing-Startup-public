extends SceneTree
## DEVELOPMENT ONLY. Headless validation: parses every .gd and loads every .tscn
## under res://, reporting failures. Run with:
##   godot --headless --path <project> --script "res://Dev tools/Validation/validate_all.gd"

const SKIP_DIRS: Array[String] = [
	"res://.godot",
	"res://Milestone Backups",
]

var _script_fail := 0
var _scene_fail := 0
var _script_ok := 0
var _scene_ok := 0


func _initialize() -> void:
	var scripts: Array[String] = []
	var scenes: Array[String] = []
	_scan("res://", scripts, scenes)

	print("[VALIDATE] %d scripts, %d scenes" % [scripts.size(), scenes.size()])

	for p in scripts:
		var res := ResourceLoader.load(p, "Script", ResourceLoader.CACHE_MODE_REUSE)
		if res == null:
			print("[SCRIPT FAIL] ", p)
			_script_fail += 1
		else:
			_script_ok += 1

	for p in scenes:
		var res := ResourceLoader.load(p, "PackedScene", ResourceLoader.CACHE_MODE_REUSE)
		if res == null:
			print("[SCENE FAIL] ", p)
			_scene_fail += 1
		else:
			_scene_ok += 1

	print("[VALIDATE] scripts ok=%d fail=%d | scenes ok=%d fail=%d"
		% [_script_ok, _script_fail, _scene_ok, _scene_fail])
	quit(1 if (_script_fail + _scene_fail) > 0 else 0)


func _scan(dir_path: String, scripts: Array[String], scenes: Array[String]) -> void:
	for skip in SKIP_DIRS:
		if dir_path.begins_with(skip):
			return
	var d := DirAccess.open(dir_path)
	if d == null:
		return
	d.list_dir_begin()
	var name := d.get_next()
	while name != "":
		if name.begins_with("."):
			name = d.get_next()
			continue
		var full := dir_path.path_join(name) if dir_path != "res://" else "res://" + name
		if d.current_is_dir():
			_scan(full, scripts, scenes)
		elif name.ends_with(".gd"):
			scripts.append(full)
		elif name.ends_with(".tscn"):
			scenes.append(full)
		name = d.get_next()
	d.list_dir_end()
