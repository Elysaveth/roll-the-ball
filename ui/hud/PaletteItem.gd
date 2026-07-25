extends Control
class_name PaletteItem
# Attach to a Control (e.g. a TextureButton/Panel) in your object palette/toolbar,
# under ui/hud/. Dragging this item spawns an instance of `object_scene` and drops
# it into `spawn_parent_path` (the World/PlacedObjects container) at the mouse's
# world position.

@export var object_scene: PackedScene
@export var spawn_parent_path: NodePath

var _preview: Node2D = null
var _dragging: bool = false

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_start_drag()
		else:
			_end_drag()

func _start_drag() -> void:
	if object_scene == null or GameManager.is_play_mode():
		return
	_dragging = true
	_preview = object_scene.instantiate()
	get_tree().root.add_child(_preview)

func _process(_delta: float) -> void:
	if _dragging and _preview:
		_preview.global_position = _get_world_mouse_position()

func _end_drag() -> void:
	if _dragging and _preview:
		var spawn_parent: Node = get_node_or_null(spawn_parent_path)
		if spawn_parent:
			_preview.get_parent().remove_child(_preview)
			spawn_parent.add_child(_preview)
			_preview.global_position = _get_world_mouse_position()
			SignalBus.object_placed.emit(_preview)
		else:
			_preview.queue_free()
	_dragging = false
	_preview = null

func _get_world_mouse_position() -> Vector2:
	var viewport: Viewport = get_viewport()
	var camera: Camera2D = viewport.get_camera_2d()
	if camera:
		return camera.get_global_mouse_position()
	return viewport.get_mouse_position()
