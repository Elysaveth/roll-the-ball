extends SimulatedBody
class_name PlaceableObject
# Base class for anything the player can place on the canvas.
#
# In EDIT mode the body is frozen (SimulatedBody's job) and draggable with the
# left mouse button; right-click removes it. In every other mode it belongs to
# the physics engine and ignores input. Attach a CollisionShape2D as a child.
#
# Requirement: save each prop type as its own root-level scene (.tscn) with this
# script (or a subclass) on the root — LevelLayout records `scene_file_path` to
# know what to re-instantiate.
#
# Subclasses that carry tunable state the player can change (a cañón's aim, a
# palanca's direction) should override get_save_state()/apply_save_state() so
# that state rides along in snapshots and save files.

## Stable identity for progression and the workshop. Must match the id used with
## SaveManager.unlock_prop() — the folder name is a good convention.
@export var prop_id: String = ""
@export var object_name: String = "Object"
## Some props are a level's fixed furniture rather than the player's inventory;
## those opt out of being draggable while still being simulated.
@export var draggable: bool = true

## Anchored props stay frozen once PLAY starts, so they behave as static geometry
## the ball can roll along, bounce off and be redirected by.
##
## This defaults to TRUE on purpose. A ramp that obeys gravity would simply fall
## the moment the player pressed PLAY, which makes "build a path to the goal"
## impossible — the piece has to hold the shape the player gave it. Props that are
## *meant* to tumble, roll or be launched (a loose crate, a ball-like prop) set
## this to false and take part in the simulation fully.
##
## A frozen RigidBody2D with the default FREEZE_MODE_STATIC still collides
## normally, so anchored props are fully solid; they just don't move.
@export var anchored: bool = true

## Only one prop may be dragged at a time. Without this, overlapping props both
## receive the same click through physics picking and move together.
static var _active_drag: PlaceableObject = null

var _dragging: bool = false
var _drag_offset: Vector2 = Vector2.ZERO


func _ready() -> void:
	super()
	add_to_group("placeable_objects")
	input_pickable = true
	input_event.connect(_on_input_event)
	# _process is only needed while actually dragging; with a canvas full of
	# props, leaving it on for every one of them is pure waste.
	set_process(false)


func _exit_tree() -> void:
	if _active_drag == self:
		_active_drag = null


# ------------------------------------------------------------ save state ----

## Override to persist extra per-prop state. Return an empty dict when there is
## none (the default), and keep it JSON-friendly: numbers, strings, bools, and
## arrays/dicts of those.
func get_save_state() -> Dictionary:
	return {}


## Override to restore what get_save_state() produced. Called right after the
## prop's transform is set, so reading position here is safe.
func apply_save_state(_state: Dictionary) -> void:
	pass


# ------------------------------------------------------------- dragging ----

func _on_input_event(_viewport: Viewport, event: InputEvent, _shape_idx: int) -> void:
	if not GameManager.is_edit_mode() or not draggable:
		return
	if not event is InputEventMouseButton or not event.pressed:
		return

	var button: InputEventMouseButton = event
	match button.button_index:
		MOUSE_BUTTON_LEFT:
			if _active_drag != null:
				return # a prop under the same click already claimed it
			_active_drag = self
			_dragging = true
			_drag_offset = global_position - get_global_mouse_position()
			set_process(true)
		MOUSE_BUTTON_RIGHT:
			remove_from_canvas()


func _process(_delta: float) -> void:
	if _dragging and GameManager.is_edit_mode():
		global_position = get_global_mouse_position() + _drag_offset


func _input(event: InputEvent) -> void:
	# Release the drag even when the button comes up outside the prop's shape.
	#
	# This is _input rather than _unhandled_input because a drag that started
	# from the palette often ends with the cursor back over the palette Button,
	# and a Control consumes the mouse-up before unhandled input ever sees it —
	# leaving the prop welded to the cursor forever. The `_dragging` guard keeps
	# this free for every prop that isn't currently being moved.
	if not _dragging or not event is InputEventMouseButton:
		return
	var button: InputEventMouseButton = event
	if button.button_index == MOUSE_BUTTON_LEFT and not button.pressed:
		_end_drag()
		SignalBus.object_placed.emit(self)


func _on_mode_applied(_mode: GameManager.Mode) -> void:
	_end_drag()
	if anchored:
		# Runs after SimulatedBody has already decided freeze for this mode, so
		# this is the last word: anchored props are frozen in every mode.
		freeze = true


## Called by PaletteItem the moment a prop is spawned out of the toolbar, so the
## new prop is already following the cursor and the player's existing mouse-down
## becomes the drag. Beats maintaining a separate preview node that has to be
## kept in sync with the real thing.
func begin_drag_from_palette() -> void:
	if _active_drag != null or not draggable:
		return
	_active_drag = self
	_dragging = true
	_drag_offset = Vector2.ZERO
	set_process(true)


func _end_drag() -> void:
	if _active_drag == self:
		_active_drag = null
	_dragging = false
	set_process(false)


func remove_from_canvas() -> void:
	SignalBus.object_removed.emit(self)
	_end_drag()
	# Detach immediately so a LevelLayout.capture() on this same frame can't see
	# a node that is already on its way out.
	if get_parent() != null:
		get_parent().remove_child(self)
	queue_free()
