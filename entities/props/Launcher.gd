extends PlaceableObject
class_name Launcher
# Anchored prop that kicks whatever touches it in the direction it faces. Shared by
# the cañón (one hard shove) and the muelle spring (softer, repeatable), which
# differ only in exported numbers and artwork.
#
# Like the explosives, contact is detected with a child Area2D named "Trigger"
# rather than contact_monitor: these are anchored, and a frozen RigidBody2D does not
# reliably report its own contacts.

@export_group("Launch")
## What the launcher reacts to. BALL_CONTACT is a cannon aimed at the ball;
## ANY_CONTACT is a spring pad that throws whatever lands on it.
@export var trigger_mode: TriggerMode = TriggerMode.BALL_CONTACT
## Impulse applied to whatever enters the trigger, in kg·px/s.
@export var launch_impulse: float = 1600.0
## Direction of the kick in the prop's LOCAL space, so rotating the prop aims it.
## Up means "out of the top of the artwork". Ignored when `radial` is on.
@export var launch_direction: Vector2 = Vector2.UP
## Kick outward from the prop's centre instead of in a fixed direction — a pinball
## bumper repels whatever hits it, whichever side it came from, and there is no sensible
## way to aim one.
@export var radial: bool = false
## Stops a body resting in the trigger from being kicked every single frame.
@export var cooldown_seconds: float = 0.3
## Optional AnimatedSprite2D child animation to play on firing.
@export var fire_animation: StringName = &""

var _cooldown: float = 0.0

@onready var _trigger: Area2D = $Trigger


func _ready() -> void:
	super()
	_trigger.body_entered.connect(_on_trigger_body_entered)
	set_physics_process(false)


func _on_trigger_body_entered(body: Node2D) -> void:
	if not GameManager.is_play_mode() or _cooldown > 0.0:
		return
	if not body is RigidBody2D:
		return
	# A frozen body is scenery as far as the physics engine is concerned — there is
	# nothing to launch.
	if body.freeze:
		return
	match trigger_mode:
		TriggerMode.BALL_CONTACT:
			if not body.is_in_group("ball"):
				return
		TriggerMode.ON_PLAY, TriggerMode.MANUAL:
			return # a launcher with no contact trigger only fires via launch()
		TriggerMode.ANY_CONTACT:
			pass
	launch(body)


func launch(body: RigidBody2D) -> void:
	var direction: Vector2 = launch_direction.rotated(rotation).normalized()
	if radial:
		var away: Vector2 = body.global_position - global_position
		# Straight up if the body is somehow exactly centred, rather than a zero kick.
		direction = away.normalized() if away.length() > 0.01 else Vector2.UP

	# The incoming speed is cancelled first, so the kick is the same whether the ball
	# crept in or slammed in. A bumper that just adds to whatever arrived would send a
	# fast ball into orbit and barely nudge a slow one.
	var incoming: float = body.linear_velocity.dot(direction)
	if incoming < 0.0:
		body.apply_central_impulse(-direction * incoming * body.mass)
	body.apply_central_impulse(direction * launch_impulse)
	_cooldown = cooldown_seconds
	set_physics_process(true)
	_play_fire_animation()


func _play_fire_animation() -> void:
	if fire_animation.is_empty():
		return
	for child in get_children():
		if child is AnimatedSprite2D and child.sprite_frames != null \
				and child.sprite_frames.has_animation(fire_animation):
			child.play(fire_animation)
			return


func _physics_process(delta: float) -> void:
	# Gated on PLAY so a pause genuinely holds the cooldown.
	if not GameManager.is_play_mode():
		return
	_cooldown -= delta
	if _cooldown <= 0.0:
		_cooldown = 0.0
		set_physics_process(false)


func _on_mode_applied(mode: GameManager.Mode) -> void:
	super(mode)
	if mode == GameManager.Mode.EDIT:
		_cooldown = 0.0
		set_physics_process(false)
