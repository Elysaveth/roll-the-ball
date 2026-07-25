extends SceneTree
# Throwaway tool: reports the opaque bounding box of each prop texture so the
# prop scenes can be given correct sprite regions and collision shapes.
# Run: godot --headless --path . --script res://tools/measure_art.gd

func _initialize() -> void:
	var paths: Array[String] = []
	_collect("res://entities", paths)
	paths.sort()
	for path in paths:
		var image: Image = Image.load_from_file(path)
		if image == null:
			print("%s -> FAILED TO LOAD" % path)
			continue
		var used: Rect2i = image.get_used_rect()
		print("%-52s full=%dx%d  used=%d,%d %dx%d" % [
			path.trim_prefix("res://entities/"),
			image.get_width(), image.get_height(),
			used.position.x, used.position.y, used.size.x, used.size.y,
		])
	quit()

func _collect(dir_path: String, out: Array[String]) -> void:
	var dir: DirAccess = DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var name: String = dir.get_next()
	while name != "":
		var full: String = dir_path.path_join(name)
		if dir.current_is_dir():
			_collect(full, out)
		elif name.ends_with(".png"):
			out.append(full)
		name = dir.get_next()
	dir.list_dir_end()
