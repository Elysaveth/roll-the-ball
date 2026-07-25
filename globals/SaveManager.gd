extends Node
# Autoload singleton — register as "SaveManager", after SignalBus.
# Saves/loads a level's object layout to user://saves/<level_name>.json.
#
# Decoupled from scene structure on both ends:
# - SAVING reads every node in the "placeable_objects" group. PlaceableObject.gd
#   adds itself to this group automatically in _ready(), so nothing else has to
#   track what's on the canvas.
# - LOADING spawns into an explicit `spawn_parent` argument, or — if you don't
#   pass one — the first node found in the "spawn_root" group (Main.gd adds
#   World/PlacedObjects to that group for you).
#
# Requirement: each placeable object type must be its own root-level scene
# (.tscn) with PlaceableObject.gd (or a subclass) on the root — saving relies
# on `scene_file_path` to know which scene to re-instantiate on load.

const SAVE_DIR: String = "user://saves/"

func _ready() -> void:
	if not DirAccess.dir_exists_absolute(SAVE_DIR):
		DirAccess.make_dir_recursive_absolute(SAVE_DIR)

func save_level(level_name: String) -> bool:
	var objects_data: Array = []
	for obj in get_tree().get_nodes_in_group("placeable_objects"):
		if obj is Node2D and not obj.scene_file_path.is_empty():
			objects_data.append({
				"scene_path": obj.scene_file_path,
				"position": [obj.global_position.x, obj.global_position.y],
				"rotation": obj.rotation,
				"scale": [obj.scale.x, obj.scale.y],
			})

	var save_data: Dictionary = {
		"level_name": level_name,
		"saved_at": Time.get_datetime_string_from_system(),
		"objects": objects_data,
	}

	var file: FileAccess = FileAccess.open(_save_path(level_name), FileAccess.WRITE)
	if file == null:
		push_error("SaveManager: couldn't write save for '%s' (%s)" % [
			level_name, error_string(FileAccess.get_open_error())
		])
		SignalBus.level_save_failed.emit(level_name)
		return false

	file.store_string(JSON.stringify(save_data, "\t"))
	file.close()
	SignalBus.level_saved.emit(level_name)
	return true

func load_level(level_name: String, spawn_parent: Node = null) -> bool:
	var path: String = _save_path(level_name)
	if not FileAccess.file_exists(path):
		push_warning("SaveManager: no save found for '%s'" % level_name)
		SignalBus.level_load_failed.emit(level_name)
		return false

	if spawn_parent == null:
		spawn_parent = _find_spawn_parent()
	if spawn_parent == null:
		push_error("SaveManager: no spawn parent available to load '%s' into" % level_name)
		SignalBus.level_load_failed.emit(level_name)
		return false

	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	var content: String = file.get_as_text()
	file.close()

	var parsed: Variant = JSON.parse_string(content)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("SaveManager: save file for '%s' is corrupted" % level_name)
		SignalBus.level_load_failed.emit(level_name)
		return false

	clear_placed_objects()

	for obj_data in parsed.get("objects", []):
		var scene_path: String = obj_data.get("scene_path", "")
		if scene_path.is_empty():
			continue
		var scene: PackedScene = load(scene_path)
		if scene == null:
			continue

		var instance: Node2D = scene.instantiate()
		spawn_parent.add_child(instance)

		var pos: Array = obj_data.get("position", [0.0, 0.0])
		instance.global_position = Vector2(pos[0], pos[1])
		instance.rotation = obj_data.get("rotation", 0.0)
		var scl: Array = obj_data.get("scale", [1.0, 1.0])
		instance.scale = Vector2(scl[0], scl[1])

	SignalBus.level_loaded.emit(level_name)
	return true

func clear_placed_objects() -> void:
	for obj in get_tree().get_nodes_in_group("placeable_objects"):
		obj.queue_free()

func list_saved_levels() -> Array[String]:
	var levels: Array[String] = []
	var dir: DirAccess = DirAccess.open(SAVE_DIR)
	if dir == null:
		return levels
	dir.list_dir_begin()
	var file_name: String = dir.get_next()
	while file_name != "":
		if file_name.ends_with(".json"):
			levels.append(file_name.trim_suffix(".json"))
		file_name = dir.get_next()
	dir.list_dir_end()
	return levels

func delete_level(level_name: String) -> void:
	var path: String = _save_path(level_name)
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
		SignalBus.level_deleted.emit(level_name)

func _save_path(level_name: String) -> String:
	return SAVE_DIR + level_name + ".json"

func _find_spawn_parent() -> Node:
	var candidates: Array = get_tree().get_nodes_in_group("spawn_root")
	return candidates[0] if not candidates.is_empty() else null
