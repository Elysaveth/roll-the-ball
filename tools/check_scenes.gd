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
			continue

		# can_instantiate() is NOT enough on its own: a scene whose ext_resource points
		# at a moved or deleted file still loads and still reports true, having quietly
		# dropped the reference. That is exactly how a level ended up with no ball
		# scene while this tool called it fine.
		var missing: Array[String] = _missing_dependencies(path)
		if missing.is_empty():
			print("  ok    %s" % path)
		else:
			failed += 1
			print("  FAIL  %s -> missing %s" % [path, ", ".join(missing)])

	print("\n%d scene(s) checked, %d failed" % [paths.size(), failed])
	quit(failed)


## Every res:// path a scene depends on that no longer resolves.
##
## get_dependencies() returns entries shaped like "uid://abc::PackedScene::res://real/path"
## — the useful part is whichever component is an actual res:// path.
func _missing_dependencies(path: String) -> Array[String]:
	var missing: Array[String] = []
	for entry in ResourceLoader.get_dependencies(path):
		var dependency: String = ""
		for part in str(entry).split("::"):
			if part.begins_with("res://"):
				dependency = part
		if dependency.is_empty() or ResourceLoader.exists(dependency):
			continue
		missing.append(dependency)
	return missing


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
