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
	else:
		freeze = false
	_on_mode_applied(mode)


## Override for behaviour that should react to a mode change — arming a fuse,
## resetting an internal timer, restarting an animation.
func _on_mode_applied(_mode: GameManager.Mode) -> void:
	pass


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
