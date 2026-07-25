extends Camera2D
# Attach to the Camera2D in your World scene.
# Drag with `pan_button` (default: middle mouse) to move around the canvas.
# Scroll wheel to zoom in/out.

@export var pan_button: MouseButton = MOUSE_BUTTON_MIDDLE
@export var zoom_speed: float = 0.1
@export var min_zoom: float = 0.3
@export var max_zoom: float = 3.0

var _dragging: bool = false
var _drag_start_mouse: Vector2
var _drag_start_position: Vector2

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		_handle_mouse_button(event)
	elif event is InputEventMouseMotion and _dragging:
		_handle_mouse_motion(event)

func _handle_mouse_button(event: InputEventMouseButton) -> void:
	if event.button_index == pan_button:
		if event.pressed:
			_dragging = true
			_drag_start_mouse = get_viewport().get_mouse_position()
			_drag_start_position = position
		else:
			_dragging = false
	elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_UP:
		_zoom_camera(-zoom_speed)
	elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		_zoom_camera(zoom_speed)

func _handle_mouse_motion(event: InputEventMouseMotion) -> void:
	var mouse_delta: Vector2 = get_viewport().get_mouse_position() - _drag_start_mouse
	# Scale by zoom so panning feels consistent at any zoom level.
	position = _drag_start_position - mouse_delta * zoom

func _zoom_camera(amount: float) -> void:
	var new_zoom: float = clamp(zoom.x + amount, min_zoom, max_zoom)
	zoom = Vector2(new_zoom, new_zoom)
