extends Button
class_name PaletteItem
# One prop in the bottom toolbar. Built in code by HUDController rather than
# from a .tscn — it's a Button with an icon and nothing else, and generating it
# keeps the palette in lockstep with whatever the level offers.
#
# Pressing it spawns the REAL prop straight into World/PlacedObjects, already
# attached to the cursor, instead of maintaining a separate preview node that
# would have to be kept visually in sync with the thing it previews. The
# player's existing mouse-down simply becomes the prop's drag; releasing drops
# it (see PlaceableObject.begin_drag_from_palette).

var object_scene: PackedScene = null


func setup(scene: PackedScene, icon_texture: Texture2D, label: String) -> void:
	object_scene = scene
	icon = icon_texture
	expand_icon = true
	tooltip_text = label
	custom_minimum_size = Vector2(96, 96)
	focus_mode = Control.FOCUS_NONE


func _gui_input(event: InputEvent) -> void:
	if object_scene == null or not GameManager.is_edit_mode():
		return
	if not event is InputEventMouseButton:
		return
	var button: InputEventMouseButton = event
	if button.button_index == MOUSE_BUTTON_LEFT and button.pressed:
		_spawn_and_drag()
		accept_event()


func _spawn_and_drag() -> void:
	var container: Node = GameManager.get_placed_objects_container()
	if container == null:
		push_warning("PaletteItem: no PlacedObjects container — is a level loaded?")
		return

	var instance: Node = object_scene.instantiate()
	if not instance is PlaceableObject:
		push_error("PaletteItem: '%s' is not a PlaceableObject" % object_scene.resource_path)
		instance.free()
		return

	var prop: PlaceableObject = instance
	container.add_child(prop)
	prop.global_position = _world_mouse_position()
	prop.begin_drag_from_palette()


func _world_mouse_position() -> Vector2:
	# The HUD is on a CanvasLayer, so its own mouse position is in screen space.
	# The prop lives in the world, so the camera has to do the conversion.
	var camera: Camera2D = get_viewport().get_camera_2d()
	if camera != null:
		return camera.get_global_mouse_position()
	return get_global_mouse_position()
