extends RefCounted
class_name LevelLayout
# The single definition of "what the player arranged on the canvas".
#
# Both paths through the game use this same format, which is the whole point:
# - GameManager takes an in-memory capture() the instant PLAY is pressed, and
#   apply()s it back when the player returns to EDIT. That is what makes props
#   snap back to where they were left instead of where physics threw them.
# - SaveManager JSON-serializes the exact same dict to disk.
#
# Capture is scoped to a container node rather than the "placeable_objects"
# group on purpose: while the player is mid-drag out of the palette, PaletteItem
# parents its preview under the viewport root, and that preview is already in
# the group. Scoping to World/PlacedObjects means a half-finished drag can never
# leak into a snapshot or a save file.
#
# Requirement: every placeable prop must be its own root-level .tscn with
# PlaceableObject.gd (or a subclass) on the root — capture() records
# `scene_file_path` and apply() re-instantiates from it.

const FORMAT_VERSION: int = 1


static func capture(container: Node) -> Dictionary:
	var objects: Array = []
	if container == null:
		push_error("LevelLayout.capture: container was null")
		return _empty()

	for child in container.get_children():
		if not child is PlaceableObject:
			continue
		if child.scene_file_path.is_empty():
			push_warning("LevelLayout.capture: skipping '%s' — not an instanced scene, so it can't be restored" % child.name)
			continue

		var entry: Dictionary = {
			"scene_path": child.scene_file_path,
			"position": [child.global_position.x, child.global_position.y],
			"rotation": child.rotation,
			"scale": [child.scale.x, child.scale.y],
		}
		# Props with their own tunables (a cañón's aim, a palanca's direction)
		# override get_save_state() to ride along here.
		var state: Dictionary = child.get_save_state()
		if not state.is_empty():
			entry["state"] = state
		objects.append(entry)

	return {
		"format_version": FORMAT_VERSION,
		"objects": objects,
	}


## Clears `container` and rebuilds it from `data`. Returns the new nodes.
static func apply(data: Dictionary, container: Node) -> Array[PlaceableObject]:
	var spawned: Array[PlaceableObject] = []
	if container == null:
		push_error("LevelLayout.apply: container was null")
		return spawned

	clear(container)

	for entry in data.get("objects", []):
		var scene_path: String = entry.get("scene_path", "")
		if scene_path.is_empty() or not ResourceLoader.exists(scene_path):
			push_warning("LevelLayout.apply: missing prop scene '%s' — skipping" % scene_path)
			continue

		var scene: PackedScene = load(scene_path)
		if scene == null:
			continue
		var instance: Node = scene.instantiate()
		if not instance is PlaceableObject:
			push_warning("LevelLayout.apply: '%s' is not a PlaceableObject — skipping" % scene_path)
			instance.free()
			continue

		var prop: PlaceableObject = instance
		container.add_child(prop)
		# Transforms are set after add_child so global_position resolves against
		# the container's own transform.
		var pos: Array = entry.get("position", [0.0, 0.0])
		prop.global_position = Vector2(pos[0], pos[1])
		prop.rotation = entry.get("rotation", 0.0)
		var scl: Array = entry.get("scale", [1.0, 1.0])
		prop.scale = Vector2(scl[0], scl[1])
		prop.apply_save_state(entry.get("state", {}))

		spawned.append(prop)

	return spawned


static func clear(container: Node) -> void:
	if container == null:
		return
	for child in container.get_children():
		if child is PlaceableObject:
			container.remove_child(child)
			child.queue_free()


static func is_empty(data: Dictionary) -> bool:
	return data.get("objects", []).is_empty()


static func _empty() -> Dictionary:
	return {"format_version": FORMAT_VERSION, "objects": []}