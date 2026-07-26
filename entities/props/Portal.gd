extends PlaceableObject
class_name Portal
# Paired teleporter. An entry portal moves the ball to the exit portal; the exit
# does nothing on its own, so there is no risk of the pair bouncing the ball back
# and forth forever.
#
# Pairing is by group rather than by an exported reference, because both halves are
# separate props the player places independently and neither can hold a NodePath to
# something that doesn't exist yet.
#
# Teleporting is done through PhysicsServer2D rather than by assigning
# global_position. The physics server owns an active RigidBody2D's transform and
# overwrites a direct assignment on the next step — the body would simply snap back.

const GROUP_ENTRY: String = "portal_entry"
const GROUP_EXIT: String = "portal_exit"

@export_group("Portal")
## Exits receive; entries send. One prop scene each.
@export var is_exit: bool = false
## Where the ball appears relative to the exit, in the exit's local space. Pushed
## clear of the exit's own trigger so it can't immediately re-enter.
@export var exit_offset: Vector2 = Vector2(0.0, -70.0)
## Keeps the ball's speed, rotated into the exit's frame — so a portal redirects
## momentum instead of dumping the ball at a standstill.
@export var preserve_velocity: bool = true
## Extra speed granted on exit, for portals that should also give a kick.
@export var exit_boost: float = 0.0
## Blocks an immediate second jump, which would otherwise happen when portals are
## placed close together.
@export var cooldown_seconds: float = 0.35

var _cooldown: float = 0.0

@onready var _trigger: Area2D = $Trigger


func _ready() -> void:
	super()
	add_to_group(GROUP_EXIT if is_exit else GROUP_ENTRY)
	_trigger.body_entered.connect(_on_trigger_body_entered)
	set_physics_process(false)


func _on_trigger_body_entered(body: Node2D) -> void:
	if is_exit or _cooldown > 0.0 or not GameManager.is_play_mode():
		return
	if not body is RigidBody2D or not body.is_in_group("ball"):
		return
	_teleport(body)


func _teleport(body: RigidBody2D) -> void:
	var exit: Portal = _find_exit()
	if exit == null:
		# A lone entry portal is a dead end rather than an error — the player may
		# simply not have placed the other half yet.
		return

	var destination: Vector2 = exit.to_global(exit_offset)
	var speed: float = body.linear_velocity.length()

	# The documented way to move a live rigid body. Assigning global_position here
	# would be silently undone by the solver.
	PhysicsServer2D.body_set_state(
		body.get_rid(),
		PhysicsServer2D.BODY_STATE_TRANSFORM,
		Transform2D(body.rotation, destination)
	)

	var out_direction: Vector2 = exit_offset.normalized().rotated(exit.rotation)
	if out_direction == Vector2.ZERO:
		out_direction = Vector2.UP.rotated(exit.rotation)
	var new_speed: float = (speed if preserve_velocity else 0.0) + exit_boost
	PhysicsServer2D.body_set_state(
		body.get_rid(),
		PhysicsServer2D.BODY_STATE_LINEAR_VELOCITY,
		out_direction * new_speed
	)

	_cooldown = cooldown_seconds
	exit._cooldown = cooldown_seconds
	set_physics_process(true)
	exit.set_physics_process(true)


## Nearest exit, so a level can hold several pairs and the closest one wins.
func _find_exit() -> Portal:
	var best: Portal = null
	var best_distance: float = INF
	for node in get_tree().get_nodes_in_group(GROUP_EXIT):
		if not node is Portal or node == self:
			continue
		var candidate: Portal = node
		var distance: float = global_position.distance_squared_to(candidate.global_position)
		if distance < best_distance:
			best_distance = distance
			best = candidate
	return best


func _physics_process(delta: float) -> void:
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
