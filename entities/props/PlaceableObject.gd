extends RigidBody2D
class_name PlaceableObject
# Base class for anything the player can place on the canvas.
# In EDIT mode: physics is frozen and the object can be dragged with the mouse.
# In PLAY mode: physics is unfrozen and the object obeys the physics engine.
# Attach a CollisionShape2D as a child. Save this object type as its own
# root-level scene (.tscn) — SaveManager relies on `scene_file_path` to know
# what to re-instantiate when a level loads.

@export var object_name: String = "Object"

var _dragging: bool = false
var _drag_offset: Vector2 = Vector2.ZERO

func _ready() -> void:
	add_to_group("placeable_objects") # so SaveManager can find every placed object
	input_pickable = true
	input_event.connect(_on_input_event)
	SignalBus.mode_changed.connect(_on_mode_changed)
	_apply_mode(GameManager.current_mode)

func _apply_mode(mode: GameManager.Mode) -> void:
	if mode == GameManager.Mode.EDIT:
		freeze = true
		linear_velocity = Vector2.ZERO
		angular_velocity = 0.0
	else:
		freeze = false

func _on_mode_changed(new_mode: GameManager.Mode) -> void:
	_apply_mode(new_mode)
	_dragging = false

func _on_input_event(_viewport: Viewport, event: InputEvent, _shape_idx: int) -> void:
	if not GameManager.is_edit_mode():
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_dragging = true
			_drag_offset = global_position - get_global_mouse_position()

func _process(_delta: float) -> void:
	if _dragging and GameManager.is_edit_mode():
		global_position = get_global_mouse_position() + _drag_offset

func _unhandled_input(event: InputEvent) -> void:
	# Release the drag even if the mouse button is released outside the shape.
	if _dragging and event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
			_dragging = false
			SignalBus.object_placed.emit(self)
