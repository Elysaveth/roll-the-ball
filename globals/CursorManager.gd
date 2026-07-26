extends Node
# Autoload singleton — register as "CursorManager", after GameManager.
#
# The single owner of the mouse cursor shape. Nothing else in the project may
# call Input.set_default_cursor_shape().
#
# It is deliberately PULL-based: every frame it asks the interaction systems what
# they're doing and derives one shape from that, rather than having each system
# push a shape when it starts and remember to undo it when it stops. Push-based
# cursors get stuck the moment any path forgets its cleanup — a rotation ended by
# a click, a drag cancelled by a mode change, a prop freed mid-drag — and a stuck
# cursor is invisible in tests but obvious to a player.
#
# Priority is top to bottom in _resolve(): the most specific ongoing action wins.

## Shape while a prop is being aimed. Godot has no rotate cursor; MOVE is the
## closest stock shape. Swap in Input.set_custom_mouse_cursor() art if you draw some.
const SHAPE_ROTATING: Input.CursorShape = Input.CURSOR_MOVE
const SHAPE_RESIZING: Input.CursorShape = Input.CURSOR_FDIAGSIZE
const SHAPE_DROP_OK: Input.CursorShape = Input.CURSOR_CAN_DROP
const SHAPE_DROP_BLOCKED: Input.CursorShape = Input.CURSOR_FORBIDDEN
const SHAPE_PANNING: Input.CursorShape = Input.CURSOR_DRAG
const SHAPE_GRABBABLE: Input.CursorShape = Input.CURSOR_POINTING_HAND
const SHAPE_DEFAULT: Input.CursorShape = Input.CURSOR_ARROW

var _current: Input.CursorShape = Input.CURSOR_ARROW


func _ready() -> void:
	# Menus have no world to interact with, so stop polling while in one.
	SignalBus.level_started.connect(_on_level_started)
	SignalBus.level_exited.connect(_on_level_exited)
	set_process(false)


func _process(_delta: float) -> void:
	_apply(_resolve())


func _on_level_started(_level_id: int) -> void:
	set_process(true)


func _on_level_exited(_level_id: int) -> void:
	set_process(false)
	_apply(SHAPE_DEFAULT)


func _apply(shape: Input.CursorShape) -> void:
	# Input exposes no getter for the current shape, so the last value is cached
	# here to avoid hammering the display server every frame.
	if shape == _current:
		return
	_current = shape
	Input.set_default_cursor_shape(shape)


func _resolve() -> Input.CursorShape:
	# Only EDIT has manipulable props. Panning still works while watching a run,
	# so that check comes first and applies in every mode.
	if CameraController.is_panning():
		return SHAPE_PANNING

	if not GameManager.is_edit_mode():
		return SHAPE_DEFAULT

	if PlaceableObject.get_rotating() != null:
		return SHAPE_ROTATING

	if PlaceableObject.get_scaling() != null:
		return SHAPE_RESIZING

	var dragging: PlaceableObject = PlaceableObject.get_dragging()
	if dragging != null:
		# The same signal the drop itself uses, so what the cursor promises and
		# what releasing the button actually does can't disagree.
		return SHAPE_DROP_OK if dragging.placement_is_valid() else SHAPE_DROP_BLOCKED

	if PlaceableObject.get_hovered() != null:
		return SHAPE_GRABBABLE

	return SHAPE_DEFAULT
