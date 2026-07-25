extends SceneTree
# Loads every project scene (skipping addons) and reports the ones that fail —
# catches broken ext_resource paths, missing scripts and bad sub_resources that
# a normal run only trips over when it happens to open that screen.
#
#   godot --headless --path . --script res://tools/check_scenes.gd

func _initialize() -> void:
	var paths: Array[String] = []
	_collect("res://", paths)
	paths.sort()

	var failed: int = 0
	for path in paths:
		var scene: PackedScene = ResourceLoader.load(path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE)
		if scene == null or not scene.can_instantiate():
			failed += 1
			print("  FAIL  %s" % path)
		else:
			print("  ok    %s" % path)

	print("\n%d scene(s) checked, %d failed" % [paths.size(), failed])
	quit(failed)


func _collect(dir_path: String, out: Array[String]) -> void:
	if dir_path.begins_with("res://addons") or dir_path.begins_with("res://.godot"):
		return
	var dir: DirAccess = DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry: String = dir.get_next()
	while entry != "":
		var full: String = dir_path.path_join(entry)
		if dir.current_is_dir():
			_collect(full, out)
		elif entry.ends_with(".tscn"):
			out.append(full)
		entry = dir.get_next()
	dir.list_dir_end()
