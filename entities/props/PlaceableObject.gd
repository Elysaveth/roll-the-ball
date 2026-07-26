extends SimulatedBody
class_name PlaceableObject
# Base class for anything the player can place on the canvas.
#
# EDIT mode interactions:
#   left-drag      move the prop
#   right-click    open its context menu (rotate / resize / delete)
#   hold rotate    aim the prop under the cursor with the mouse
#   hold scale     resize the prop under the cursor with the mouse
#
# In every other mode the prop belongs to the physics engine and ignores input.
# Attach a CollisionShape2D as a child.
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

## Exclusive props refuse to be dropped on top of each other, so the player can't
## stack five bombs in one spot to multiply a blast.
##
## The rule is symmetric and only applies between two exclusive props: an
## exclusive prop may still overlap a non-exclusive one. Set this false on pieces
## that are *meant* to be layered — ice planks crossing to form a junction, say.
@export var exclusive_placement: bool = true

@export_group("Breaking")
## Breakable props shatter when hit hard enough, dropping the material the
## workshop's blueprints are crafted from.
@export var breakable: bool = false
## Contact impulse needed to shatter this prop. A wood plank gives way to the ball
## itself; stone should really only yield to an explosion.
@export var break_impulse: float = 900.0
## Material granted on breaking, e.g. "wood_chips". Empty means it drops nothing.
@export var material_id: String = ""
@export var material_amount: int = 1
@export var debris_count: int = 6
@export var debris_colour: Color = Color(0.55, 0.45, 0.36)

## When a reactive prop's behaviour fires. Defined once here so every prop that
## reacts to something — explosives, launchers, rockets — shares one vocabulary and
## a level designer only has to learn it once.
enum TriggerMode {
	BALL_CONTACT, ## Only the ball sets it off. The usual choice.
	ANY_CONTACT,  ## Any loose body does, including other props.
	ON_PLAY,      ## Fires as soon as the attempt starts, after its own delay.
	MANUAL,       ## Nothing sets it off but another prop — chain reactions only.
}

## How far cursor resizing may take a prop. Uniform only — a non-uniform scale on
## a RigidBody2D hands the physics engine a shape it can't represent, and
## collisions stop matching what's drawn.
const MIN_SCALE: float = 0.4
const MAX_SCALE: float = 2.5

## Only one prop may be dragged at a time. Without this, overlapping props both
## receive the same click through physics picking and move together.
static var _active_drag: PlaceableObject = null
## Likewise for the rotate and resize gestures, and for knowing which prop the
## cursor is over — the held-key gestures need a target without a click first.
static var _active_rotate: PlaceableObject = null
static var _active_scale: PlaceableObject = null
static var _hovered: PlaceableObject = null

var _dragging: bool = false
var _drag_offset: Vector2 = Vector2.ZERO
## Where the prop sat before this drag, so an illegal drop can be undone. Null
## for a prop that came straight out of the palette and has no previous home.
var _drag_return_to: Variant = null

var _rotating: bool = false
## Sticky gestures (started from the context menu) run until the player clicks.
## Non-sticky ones (started by holding a key) end when the key comes up.
var _rotate_sticky: bool = false
var _rotate_offset: float = 0.0
var _rotation_before: float = 0.0

var _scaling: bool = false
var _scale_sticky: bool = false
var _scale_grab_distance: float = 1.0
var _scale_at_grab: float = 1.0
var _scale_before: float = 1.0

## This prop's own collision shapes, used to test placement. Gathered once — a
## prop's shapes don't change at runtime.
var _own_shapes: Array[CollisionShape2D] = []
var _broken: bool = false


func _ready() -> void:
	super()
	add_to_group("placeable_objects")
	input_pickable = true
	input_event.connect(_on_input_event)
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	# Gestures must be abandoned when the mode changes, but NOT when the mode is
	# merely applied during construction — a prop spawned from the palette has its
	# drag started immediately after _ready, and cancelling it there would leave
	# the player holding nothing.
	SignalBus.mode_changed.connect(_on_mode_transition)
	_collect_own_shapes()
	if breakable:
		# Contact reporting is the only way to learn how hard something was hit, and
		# it's off by default because it costs solver work on every body.
		contact_monitor = true
		max_contacts_reported = maxi(max_contacts_reported, 4)
	# _process is only needed while a gesture is running; with a canvas full of
	# props, leaving it on for every one of them is pure waste.
	set_process(false)


func _exit_tree() -> void:
	if _active_drag == self:
		_active_drag = null
	if _active_rotate == self:
		_active_rotate = null
	if _active_scale == self:
		_active_scale = null
	if _hovered == self:
		_hovered = null


# ---------------------------------------------------------------- statics ----

## The prop under the cursor, or null. The HUD uses this to know what a held
## rotate/resize key should act on.
static func get_hovered() -> PlaceableObject:
	return _hovered if _hovered != null and is_instance_valid(_hovered) else null


static func get_rotating() -> PlaceableObject:
	return _active_rotate if _active_rotate != null and is_instance_valid(_active_rotate) else null


static func get_scaling() -> PlaceableObject:
	return _active_scale if _active_scale != null and is_instance_valid(_active_scale) else null


static func get_dragging() -> PlaceableObject:
	return _active_drag if _active_drag != null and is_instance_valid(_active_drag) else null


## True while the player is manipulating any prop — the camera checks this so a
## drag-to-pan can't fight a drag-to-move.
static func is_manipulating() -> bool:
	return get_dragging() != null or get_rotating() != null or get_scaling() != null


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


# ----------------------------------------------------- placement validity ----

## Collects the shapes belonging to THIS body, without descending into child
## CollisionObject2Ds — a bomb's blast Trigger is an Area2D with its own shape,
## and that shape describes its reach, not its footprint.
func _collect_own_shapes() -> void:
	_own_shapes.clear()
	_gather_shapes(self)


func _gather_shapes(node: Node) -> void:
	for child in node.get_children():
		if child is CollisionObject2D:
			continue # a separate physics object; its shapes aren't ours
		if child is CollisionShape2D and child.shape != null and not child.disabled:
			_own_shapes.append(child)
		_gather_shapes(child)


## Whether the prop could legally be dropped where it currently sits.
##
## Uses a direct shape query rather than a child Area2D, because an Area2D does
## NOT report frozen RigidBody2D bodies — and every prop is frozen while the
## player is arranging, so an area-based probe silently sees nothing at exactly
## the moment this question is asked. (Verified against 4.7: an area on an
## unfrozen body reports its neighbours, the same area on a frozen one reports an
## empty list, while a direct query finds them either way.)
##
## Both the cursor and the drop itself call this, so what the cursor promises and
## what releasing the button does cannot disagree.
func placement_is_valid() -> bool:
	if not exclusive_placement or not is_inside_tree() or _own_shapes.is_empty():
		return true
	var space: PhysicsDirectSpaceState2D = get_world_2d().direct_space_state
	if space == null:
		return true

	for source in _own_shapes:
		var query: PhysicsShapeQueryParameters2D = PhysicsShapeQueryParameters2D.new()
		query.shape = source.shape
		# Includes this prop's scale, so a resized prop tests its real footprint.
		query.transform = source.global_transform
		query.collide_with_bodies = true
		query.collide_with_areas = false
		query.exclude = [get_rid()]

		for hit in space.intersect_shape(query, 16):
			var other: Object = hit.get("collider")
			if other is PlaceableObject and other.exclusive_placement:
				return false
	return true


# --------------------------------------------------------------- hovering ----

func _on_mouse_entered() -> void:
	_hovered = self


func _on_mouse_exited() -> void:
	if _hovered == self:
		_hovered = null


# ---------------------------------------------------------------- gestures ----

func _on_input_event(_viewport: Viewport, event: InputEvent, _shape_idx: int) -> void:
	if not GameManager.is_edit_mode() or not draggable:
		return
	if not event is InputEventMouseButton or not event.pressed:
		return

	var button: InputEventMouseButton = event
	match button.button_index:
		MOUSE_BUTTON_LEFT:
			# A sticky gesture swallows the next click as "done" rather than
			# letting it start a drag.
			if _finish_sticky_gesture():
				return
			if _active_drag != null:
				return # a prop under the same click already claimed it
			_active_drag = self
			_dragging = true
			_drag_return_to = global_position
			_drag_offset = global_position - get_global_mouse_position()
			_refresh_processing()
		MOUSE_BUTTON_RIGHT:
			# Deleting outright used to happen here. It's now one entry in a menu,
			# so a misplaced right-click can't destroy work.
			SignalBus.prop_context_requested.emit(self)


static func _finish_sticky_gesture() -> bool:
	var rotating: PlaceableObject = get_rotating()
	if rotating != null:
		rotating.end_rotate()
		return true
	var scaling: PlaceableObject = get_scaling()
	if scaling != null:
		scaling.end_scale()
		return true
	return false


func _process(_delta: float) -> void:
	if not GameManager.is_edit_mode():
		return
	if _dragging:
		global_position = get_global_mouse_position() + _drag_offset
	elif _rotating:
		# Absolute aiming: the prop points at the cursor, offset by wherever it
		# was pointing when the gesture began, so it never jumps on frame one.
		rotation = (get_global_mouse_position() - global_position).angle() + _rotate_offset
	elif _scaling:
		# Size tracks how far the cursor is from the prop's centre relative to
		# where it started, so dragging outward grows and inward shrinks.
		var distance: float = maxf(1.0, (get_global_mouse_position() - global_position).length())
		set_uniform_scale(_scale_at_grab * distance / _scale_grab_distance)


func _input(event: InputEvent) -> void:
	# Runs on every prop, so bail out fast for the ones not being manipulated.
	if not _dragging and not _is_sticky():
		return
	if not event is InputEventMouseButton:
		return
	var button: InputEventMouseButton = event

	# Release the drag even when the button comes up outside the prop's shape.
	#
	# This is _input rather than _unhandled_input because a drag that started
	# from the palette often ends with the cursor back over the palette Button,
	# and a Control consumes the mouse-up before unhandled input ever sees it —
	# leaving the prop welded to the cursor forever.
	if _dragging and button.button_index == MOUSE_BUTTON_LEFT and not button.pressed:
		_drop()
		return

	# Confirm a menu-started gesture with a click anywhere.
	if _is_sticky() and button.pressed and button.button_index == MOUSE_BUTTON_LEFT:
		_finish_sticky_gesture()
		get_viewport().set_input_as_handled()


func _is_sticky() -> bool:
	return (_rotating and _rotate_sticky) or (_scaling and _scale_sticky)


func _on_mode_applied(_mode: GameManager.Mode) -> void:
	# Called during construction too, so this must only touch physics state —
	# anything that cancels player input belongs in _on_mode_transition.
	if anchored:
		# Runs after SimulatedBody has already decided freeze for this mode, so
		# this is the last word: anchored props are frozen in every mode.
		freeze = true


## A genuine mode change, as opposed to the mode being applied at startup. Leaving
## a gesture running across PLAY would let the player keep dragging a prop while
## the simulation ran.
func _on_mode_transition(_new_mode: GameManager.Mode) -> void:
	_end_drag()
	end_rotate()
	end_scale()


# -------------------------------------------------------------- dragging ----

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
	# No previous home: an illegal drop cancels the placement outright rather
	# than snapping back to somewhere the prop has never been.
	_drag_return_to = null
	_refresh_processing()


## Resolves the end of a drag: keep the new spot, undo it, or cancel a brand-new
## prop entirely.
func _drop() -> void:
	# Recomputed here rather than trusting the cached value, so the decision is
	# made against the position the prop is actually being left in.
	if placement_is_valid():
		_end_drag()
		SignalBus.object_placed.emit(self)
		return

	if _drag_return_to == null:
		# Straight from the palette onto an illegal spot — nothing to undo, so the
		# placement simply doesn't happen.
		remove_from_canvas()
		return

	global_position = _drag_return_to
	_end_drag()
	SignalBus.object_placed.emit(self)


func _end_drag() -> void:
	if _active_drag == self:
		_active_drag = null
	_dragging = false
	_drag_return_to = null
	_refresh_processing()


# -------------------------------------------------------------- rotating ----

## `sticky` gestures (from the context menu) keep going until the player clicks;
## non-sticky ones (from holding the key) end when the key is released.
func begin_rotate(sticky: bool = false) -> void:
	if not _can_begin_gesture() or _active_rotate == self:
		return
	_end_drag()
	end_scale()

	_active_rotate = self
	_rotating = true
	_rotate_sticky = sticky
	_rotation_before = rotation
	_rotate_offset = rotation - (get_global_mouse_position() - global_position).angle()
	_refresh_processing()


func end_rotate() -> void:
	if not _rotating:
		return
	if _active_rotate == self:
		_active_rotate = null
	_rotating = false
	_rotate_sticky = false
	_refresh_processing()
	SignalBus.object_placed.emit(self)


## Ends a rotation started by holding the key, leaving a menu-started (sticky)
## one alone — that one is the player's to finish with a click.
func end_hold_rotate() -> void:
	if _rotating and not _rotate_sticky:
		end_rotate()


## Abandons the rotation and puts the prop back at the angle it had.
func cancel_rotate() -> void:
	if not _rotating:
		return
	rotation = _rotation_before
	if _active_rotate == self:
		_active_rotate = null
	_rotating = false
	_rotate_sticky = false
	_refresh_processing()


func is_rotating() -> bool:
	return _rotating


# --------------------------------------------------------------- scaling ----

func begin_scale(sticky: bool = false) -> void:
	if not _can_begin_gesture() or _active_scale == self:
		return
	_end_drag()
	end_rotate()

	_active_scale = self
	_scaling = true
	_scale_sticky = sticky
	_scale_before = scale.x
	_scale_at_grab = scale.x
	# Clamped away from zero so a grab exactly on the centre can't divide by it.
	_scale_grab_distance = maxf(1.0, (get_global_mouse_position() - global_position).length())
	_refresh_processing()


func end_scale() -> void:
	if not _scaling:
		return
	if _active_scale == self:
		_active_scale = null
	_scaling = false
	_scale_sticky = false
	_refresh_processing()
	SignalBus.object_placed.emit(self)


func end_hold_scale() -> void:
	if _scaling and not _scale_sticky:
		end_scale()


func cancel_scale() -> void:
	if not _scaling:
		return
	set_uniform_scale(_scale_before)
	if _active_scale == self:
		_active_scale = null
	_scaling = false
	_scale_sticky = false
	_refresh_processing()


func is_scaling() -> bool:
	return _scaling


## Clamped uniform resize. Returns true if the size actually changed.
func set_uniform_scale(value: float) -> bool:
	var wanted: float = clampf(value, MIN_SCALE, MAX_SCALE)
	if is_equal_approx(wanted, scale.x):
		return false
	scale = Vector2(wanted, wanted)
	return true


func can_grow() -> bool:
	return scale.x < MAX_SCALE - 0.001


func can_shrink() -> bool:
	return scale.x > MIN_SCALE + 0.001


# --------------------------------------------------------------- helpers ----

func _can_begin_gesture() -> bool:
	if not draggable or not GameManager.is_edit_mode():
		return false
	# Another prop is mid-gesture; don't let a second one join in.
	return not (get_rotating() != null and get_rotating() != self) \
		and not (get_scaling() != null and get_scaling() != self)


func _refresh_processing() -> void:
	# Only _process is managed here. _physics_process is left alone so subclasses
	# that need it for their own behaviour — an Explosive's fuse — stay in charge of it.
	set_process(_dragging or _rotating or _scaling)


func _cancel_all_gestures() -> void:
	_end_drag()
	cancel_rotate()
	cancel_scale()


# -------------------------------------------------------------- breaking ----

## Subclasses overriding this must call super(state), or the prop stops breaking.
func _integrate_forces(state: PhysicsDirectBodyState2D) -> void:
	# Lets this prop break things IT slams into, as well as being broken.
	super(state)
	if not breakable or _broken or freeze:
		# A frozen (anchored) prop reports no contacts, so it can only be broken by
		# whatever hit it calling try_break() — the ball, or an explosion.
		return
	# `last_impact` is measured by SimulatedBody from the speed this body lost, which
	# get_contact_impulse() fails to report during a collision. Requiring a recent
	# contact keeps a body braked by anything else — a portal, a launcher — from
	# counting as a crash, while still allowing for having already bounced clear.
	if state.get_contact_count() > 0 and get_effective_impact() >= break_impulse:
		try_break(get_effective_impact())


## Attempts to shatter the prop with `force`. Returns whether it actually broke, so
## a blast can tell what it destroyed. Safe to call on anything — non-breakable
## props just say no.
func try_break(force: float) -> bool:
	if not breakable or _broken or force < break_impulse:
		return false
	_shatter()
	return true


func _shatter() -> void:
	_broken = true
	_spawn_debris()
	# Feeds the workshop: blueprints are paid for in materials from broken props.
	SaveManager.record_break(prop_id, material_id, material_amount)
	SignalBus.prop_broken.emit(prop_id, material_id, global_position)
	detach_and_free()


func _spawn_debris() -> void:
	var host: Node = get_parent()
	if host == null or debris_count <= 0:
		return
	# Parented to the container rather than to this prop, which is about to go.
	for i in debris_count:
		var angle: float = randf_range(0.0, TAU)
		var speed: float = randf_range(120.0, 340.0)
		var piece: Debris = Debris.create(
			debris_colour,
			randf_range(5.0, 11.0),
			global_position + Vector2.from_angle(angle) * randf_range(0.0, 24.0),
			Vector2.from_angle(angle) * speed,
			randf_range(-9.0, 9.0)
		)
		host.add_child(piece)


# -------------------------------------------------------------- removal ----

func remove_from_canvas() -> void:
	SignalBus.object_removed.emit(self)
	_cancel_all_gestures()
	detach_and_free()
