extends RigidBody2D
class_name SimulatedBody
# Shared base for every rigid body that takes part in a level's simulation —
# the ball and all placeable props.
#
# Its whole job is keeping the body in step with GameManager's mode: frozen and
# inert while the player arranges things in EDIT, handed over to the physics
# engine from PLAY onward.
#
# Note it does NOT freeze in the observation modes (PAUSED / TIME_UP /
# COMPLETED). Those stop the physics server instead, which preserves every
# velocity; freezing here would zero them out and a resumed pause would drop
# everything from a standstill. See the header of globals/GameManager.gd.
#
# Subclasses overriding _ready() must call super().


func _ready() -> void:
	SignalBus.mode_changed.connect(_on_mode_changed)
	_apply_mode(GameManager.current_mode)


func _on_mode_changed(new_mode: GameManager.Mode) -> void:
	_apply_mode(new_mode)


## Mode changes can originate inside a physics callback — a Goal's body_entered,
## a bomb trigger's area overlap — and the physics space is locked for the whole
## of those. Writing `freeze` or a velocity then is refused outright by the
## engine ("Can't change this state while flushing queries"), so anything that
## touches physics state gets bounced to the deferred queue whenever we're inside
## a physics frame. One guard here covers every subclass, because
## _on_mode_applied() is called from the deferred side too.
func _apply_mode(mode: GameManager.Mode) -> void:
	if Engine.is_in_physics_frame():
		_apply_mode_now.call_deferred(mode)
	else:
		_apply_mode_now(mode)


func _apply_mode_now(mode: GameManager.Mode) -> void:
	if mode == GameManager.Mode.EDIT:
		freeze = true
		linear_velocity = Vector2.ZERO
		angular_velocity = 0.0
		sleeping = false
		# Cleared with the velocity, or the speed it had when the attempt ended would
		# read as a colossal impact on the first step of the next one.
		_last_speed = 0.0
		last_impact = 0.0
	else:
		freeze = false
	_on_mode_applied(mode)


## Override for behaviour that should react to a mode change — arming a fuse,
## resetting an internal timer, restarting an animation.
func _on_mode_applied(_mode: GameManager.Mode) -> void:
	pass


## How hard this body was hit on the most recent physics step, as mass × speed lost.
## Read by PlaceableObject to decide whether it should shatter.
var last_impact: float = 0.0

var _last_speed: float = 0.0


## Measures impacts and reports them to whatever was hit.
##
## This has to live on the MOVING body. An anchored prop is frozen, and a frozen
## RigidBody2D reports no contacts at all — so a wood plank could never notice the
## ball landing on it, and planks were unbreakable in practice. The ball (and any
## loose prop) instead tells what it hits how hard, and the target decides whether
## that was enough.
##
## Strength is derived from the SPEED LOST, not from get_contact_impulse(). The
## impulse accessor reports zero throughout the actual collision in this setup and
## only becomes non-zero once the body has settled — verified by dropping a ball on a
## plank with the threshold at 0.001, which broke ~55 frames after the impact rather
## than on it. Speed lost is exact and needs no solver cooperation.
##
## It also happens to be the right physical quantity: a ball ROLLING across a plank
## keeps its speed, so it loses nothing and breaks nothing, while a ball DROPPING onto
## one loses almost all of it at once. That distinction is the whole feature.
##
## Subclasses overriding _integrate_forces must call super(state).
func _integrate_forces(state: PhysicsDirectBodyState2D) -> void:
	var speed_now: float = state.linear_velocity.length()
	# Gravity accelerates the body, so a falling body's speed only ever rises and
	# can't register a false impact.
	last_impact = maxf(0.0, _last_speed - speed_now) * mass
	_last_speed = speed_now

	if freeze or last_impact <= 0.0:
		return
	for i in state.get_contact_count():
		var other: Object = state.get_contact_collider_object(i)
		if other is PlaceableObject:
			other.try_break(last_impact)


## Takes this body off the canvas immediately and frees it.
##
## Detaching before the queued free matters: a LevelLayout.capture() later in the
## same frame must not see a node that is already on its way out. Same physics
## lock applies, so the reparent is deferred when we're mid-step — harmless,
## because captures only ever happen in EDIT or at the start of an attempt.
func detach_and_free() -> void:
	var parent: Node = get_parent()
	if parent != null:
		if Engine.is_in_physics_frame():
			parent.remove_child.call_deferred(self)
		else:
			parent.remove_child(self)
	queue_free()
