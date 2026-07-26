extends Camera2D
class_name CameraController
# Attach to the Camera2D in main.tscn's World.
#
# Panning:
#   middle-drag            always pans
#   left-drag empty space  pans too, so the obvious gesture works — suppressed
#                          when the cursor is over a prop, which belongs to that
#                          prop's own drag
#   camera_* actions       keyboard panning (arrow keys by default, rebindable
#                          from the Controls tab)
#
# Zooming: mouse wheel, anchored on the cursor so the world point under the
# pointer stays put instead of the view lurching toward the screen centre.

@export var pan_button: MouseButton = MOUSE_BUTTON_MIDDLE
## Screen pixels per second for keyboard panning, kept constant regardless of zoom.
@export var keyboard_pan_speed: float = 1200.0
@export var zoom_step: float = 0.1
@export var min_zoom: float = 0.3
@export var max_zoom: float = 3.0

@export_group("Shake")
## Pixels of shake at full strength, and how fast it dies away.
@export var shake_decay: float = 40.0

## Static so CursorManager can ask whether the view is being dragged without
## holding a reference to whichever camera is currently in the tree.
static var _panning: bool = false
## Pending shake, posted by whatever exploded. Static for the same reason: an
## explosive shouldn't have to find the camera to make the screen jolt.
static var _shake_request: float = 0.0

var _shake: float = 0.0


## Asks for a jolt of `strength` pixels. Louder requests win; they don't stack, so a
## chain of explosions can't shake the view off the screen.
static func request_shake(strength: float) -> void:
	_shake_request = maxf(_shake_request, strength)

var _dragging: bool = false
var _drag_start_mouse: Vector2
var _drag_start_position: Vector2


static func is_panning() -> bool:
	return _panning


func _exit_tree() -> void:
	if _dragging:
		_panning = false


func _process(delta: float) -> void:
	_update_shake(delta)

	var direction: Vector2 = Input.get_vector("camera_left", "camera_right", "camera_up", "camera_down")
	if direction == Vector2.ZERO:
		return
	# Divided by zoom so a keypress always slides the view the same number of
	# screen pixels, whether zoomed right in or right out.
	position += direction * keyboard_pan_speed * delta / zoom.x


## Shake rides on `offset`, never on `position` — position is what panning owns, and
## mixing the two would leave the view permanently nudged after every explosion.
func _update_shake(delta: float) -> void:
	if _shake_request > 0.0:
		if Settings.screen_shake_enabled:
			_shake = maxf(_shake, _shake_request)
		_shake_request = 0.0

	if _shake <= 0.0:
		if offset != Vector2.ZERO:
			offset = Vector2.ZERO
		return

	_shake = move_toward(_shake, 0.0, shake_decay * delta)
	offset = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * _shake


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		_handle_mouse_button(event)
	elif event is InputEventMouseMotion and _dragging:
		_handle_mouse_motion()


func _handle_mouse_button(event: InputEventMouseButton) -> void:
	match event.button_index:
		MOUSE_BUTTON_WHEEL_UP:
			if event.pressed:
				_zoom_at_cursor(zoom_step) # wheel up zooms IN, as everywhere else
		MOUSE_BUTTON_WHEEL_DOWN:
			if event.pressed:
				_zoom_at_cursor(-zoom_step)
		_:
			if event.button_index == pan_button:
				_set_dragging(event.pressed)
			elif event.button_index == MOUSE_BUTTON_LEFT:
				_set_dragging(event.pressed and _left_drag_is_free())


## Whether a left-press should pan rather than belong to a prop.
##
## It can't ask PlaceableObject.is_manipulating(): physics picking is processed
## during the physics step, so a prop's input_event has NOT run yet when this
## event reaches _unhandled_input. Hover state is the reliable signal, because it
## was established on an earlier tick and the cursor is by definition stationary
## at the moment of a click.
func _left_drag_is_free() -> bool:
	return PlaceableObject.get_hovered() == null and not PlaceableObject.is_manipulating()


func _set_dragging(active: bool) -> void:
	_dragging = active
	_panning = active
	if active:
		_drag_start_mouse = get_viewport().get_mouse_position()
		_drag_start_position = position


func _handle_mouse_motion() -> void:
	var screen_delta: Vector2 = get_viewport().get_mouse_position() - _drag_start_mouse
	# Screen pixels convert to world units by DIVIDING by zoom (zoom > 1 is zoomed
	# in, so the same drag covers less world). The previous version multiplied,
	# which inverted the feel at every zoom level except 1.
	position = _drag_start_position - screen_delta / zoom.x


func _zoom_at_cursor(amount: float) -> void:
	var old_zoom: float = zoom.x
	var new_zoom: float = clampf(old_zoom + amount, min_zoom, max_zoom)
	if is_equal_approx(new_zoom, old_zoom):
		return

	# Worked out from the transform rather than read back from
	# get_global_mouse_position(), which won't reflect the new zoom until the
	# camera's transform is recomputed next frame.
	var offset_from_centre: Vector2 = get_viewport().get_mouse_position() - get_viewport_rect().size * 0.5
	var world_under_cursor: Vector2 = position + offset_from_centre / old_zoom

	zoom = Vector2(new_zoom, new_zoom)
	position = world_under_cursor - offset_from_centre / new_zoom
