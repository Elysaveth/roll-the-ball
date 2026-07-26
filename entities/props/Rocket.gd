extends PlaceableObject
class_name Rocket
# A rocket that lights when the ball touches it and then flies, carrying or shoving
# whatever it runs into. Unlike the launchers this is NOT anchored — the point is
# that the rocket itself moves.
#
# Thrust is a continuous force applied every physics step while burning, rather
# than a single impulse, which is what makes it accelerate and lets the ball ride it.

@export_group("Thrust")
## Force per second while burning, in kg·px/s².
@export var thrust: float = 3200.0
@export var burn_seconds: float = 1.2
## Thrust direction in LOCAL space, so rotating the prop aims it.
@export var thrust_direction: Vector2 = Vector2.UP
## Spins up to this while burning, so a rocket doesn't fly perfectly straight.
@export var wobble_torque: float = 0.0
## Explodes when the burn ends, if set.
@export var explosion_scene: PackedScene
@export var explosion_radius: float = 0.0
@export var explosion_force: float = 0.0

var _burning: bool = false
var _burn_remaining: float = 0.0

@onready var _trigger: Area2D = $Trigger


func _ready() -> void:
	super()
	# Rockets fly, so being anchored would defeat the entire prop. Enforced here
	# rather than trusted to the .tscn, since it's a correctness requirement.
	anchored = false
	_trigger.body_entered.connect(_on_trigger_body_entered)
	set_physics_process(false)


func _on_trigger_body_entered(body: Node2D) -> void:
	if _burning or not GameManager.is_play_mode():
		return
	if body.is_in_group("ball"):
		ignite()


func ignite() -> void:
	if _burning:
		return
	_burning = true
	_burn_remaining = burn_seconds
	set_physics_process(true)


func _physics_process(delta: float) -> void:
	if not GameManager.is_play_mode():
		return

	_burn_remaining -= delta
	if _burn_remaining <= 0.0:
		_burning = false
		set_physics_process(false)
		_burn_out()
		return

	# Continuous force, re-applied each step — apply_central_force only lasts for
	# the step it's called in.
	apply_central_force(thrust_direction.rotated(rotation).normalized() * thrust)
	if not is_zero_approx(wobble_torque):
		apply_torque(wobble_torque)


## Some rockets go bang at the end of the burn; the small one just runs out.
func _burn_out() -> void:
	if explosion_radius <= 0.0:
		return
	var host: Node = get_parent()
	if explosion_scene != null and host != null and Settings.particles_enabled:
		var effect: Node = explosion_scene.instantiate()
		host.add_child(effect)
		if effect is Node2D:
			effect.global_position = global_position

	var space: PhysicsDirectSpaceState2D = get_world_2d().direct_space_state
	var circle: CircleShape2D = CircleShape2D.new()
	circle.radius = explosion_radius
	var query: PhysicsShapeQueryParameters2D = PhysicsShapeQueryParameters2D.new()
	query.shape = circle
	query.transform = Transform2D(0.0, global_position)
	query.exclude = [get_rid()]

	for hit in space.intersect_shape(query, 24):
		var body: Object = hit.get("collider")
		if not body is RigidBody2D:
			continue
		var target: RigidBody2D = body
		var offset: Vector2 = target.global_position - global_position
		var falloff: float = clampf(1.0 - offset.length() / explosion_radius, 0.0, 1.0)
		var force: float = explosion_force * falloff
		if target is PlaceableObject and target.try_break(force):
			continue
		if not target.freeze:
			target.apply_central_impulse(offset.normalized() * force)

	CameraController.request_shake(8.0)
	detach_and_free()


func _on_mode_applied(mode: GameManager.Mode) -> void:
	super(mode)
	if mode == GameManager.Mode.EDIT:
		_burning = false
		_burn_remaining = 0.0
		set_physics_process(false)
