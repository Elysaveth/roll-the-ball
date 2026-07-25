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


func _apply_mode(mode: GameManager.Mode) -> void:
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
