extends PlaceableObject
class_name Rocket
# A rocket that sits where the player put it, lights, and then FLIES — carrying or
# shoving whatever it runs into.
#
# It stays anchored while idle and unanchors the moment it ignites. That ordering is
# the whole prop: left permanently unanchored it simply fell over the instant PLAY
# started, usually well before the ball could reach it, so all anyone ever saw was
# the explosion at the end of the burn.
#
# Thrust is a continuous force re-applied every physics step, not a single impulse.
# That's what makes it accelerate and lets the ball ride it.
#
# Exported knobs, so a new rocket is a new .tscn rather than new code:
#   ignite_mode / ignite_delay   what lights it, and how long after
#   thrust / burn_seconds        how hard and how long it pushes
#   thrust_direction            which way, in local space, so rotating it aims it
#   wobble_torque               spin while burning, for an unruly rocket
#   explode_on_burnout          whether it detonates when the fuel runs out
#   explode_on_impact           whether hitting something hard sets it off early
#   explosion_radius / _force   the blast, if it has one

@export_group("Ignition")
@export var ignite_mode: TriggerMode = TriggerMode.ON_PLAY
## Only used by ON_PLAY. Without a delay the rocket is gone before the player looks.
@export var ignite_delay: float = 0.35

@export_group("Thrust")
## Thrust as a MULTIPLE OF THE ROCKET'S OWN WEIGHT, not an absolute force.
##
## 1.0 exactly cancels gravity and the rocket hovers; 2.0 climbs as hard as gravity
## pulls down. Anything below 1.0 cannot leave the ground.
##
## Deliberately relative: an absolute force has to be re-tuned for every prop
## whenever project gravity changes, and it silently stops working when it does —
## the first version of this used absolute force and the rockets just sank.
@export var thrust_gravities: float = 2.2
@export var burn_seconds: float = 1.2
## Thrust direction in LOCAL space, so rotating the prop aims it.
@export var thrust_direction: Vector2 = Vector2.UP
## Spin applied while burning. 0 flies straight.
@export var wobble_torque: float = 0.0

@export_group("Detonation")
@export var explosion_scene: PackedScene
@export var explode_on_burnout: bool = false
## Detonates early if it slams into something at least this hard.
@export var explode_on_impact: bool = false
@export var impact_impulse: float = 700.0
@export var explosion_radius: float = 240.0
@export var explosion_force: float = 1600.0
@export var shake_strength: float = 8.0

var _burning: bool = false
var _burn_remaining: float = 0.0
var _ignite_remaining: float = -1.0
var _spent: bool = false

@onready var _trigger: Area2D = $Trigger


func _ready() -> void:
	super()
	_trigger.body_entered.connect(_on_trigger_body_entered)
	if explode_on_impact:
		contact_monitor = true
		max_contacts_reported = maxi(max_contacts_reported, 4)
	set_physics_process(false)


func _on_trigger_body_entered(body: Node2D) -> void:
	if _burning or _spent or not GameManager.is_play_mode():
		return
	match ignite_mode:
		TriggerMode.BALL_CONTACT:
			if body.is_in_group("ball"):
				ignite()
		TriggerMode.ANY_CONTACT:
			if body is RigidBody2D:
				ignite()
		TriggerMode.ON_PLAY, TriggerMode.MANUAL:
			pass

## Lights the motor. Also callable by another prop, for a staged launch.
func ignite() -> void:
	if _burning or _spent:
		return
	_burning = true
	_burn_remaining = burn_seconds
	# Released from its mount so it can actually leave the ground. SimulatedBody
	# only re-freezes on a mode change, so this sticks for the rest of the attempt.
	anchored = false
	freeze = false
	sleeping = false
	set_physics_process(true)


func _physics_process(delta: float) -> void:
	if not GameManager.is_play_mode():
		return

	if _ignite_remaining >= 0.0:
		_ignite_remaining -= delta
		if _ignite_remaining <= 0.0:
			_ignite_remaining = -1.0
			ignite()
		return

	if not _burning:
		return

	_burn_remaining -= delta
	if _burn_remaining <= 0.0:
		_burning = false
		set_physics_process(false)
		if explode_on_burnout:
			detonate()
		return

	# Continuous force, re-applied each step — apply_central_force only lasts for the
	# step it's called in.
	apply_central_force(thrust_direction.rotated(rotation).normalized() * get_thrust_force())
	if not is_zero_approx(wobble_torque):
		apply_torque(wobble_torque)


## Thrust converted to real force at the gravity this level actually runs at.
func get_thrust_force() -> float:
	var gravity: float = float(ProjectSettings.get_setting("physics/2d/default_gravity", 980.0))
	return mass * gravity * maxf(gravity_scale, 0.0) * thrust_gravities


func _integrate_forces(state: PhysicsDirectBodyState2D) -> void:
	# Keeps the breaking and impact measurement in the base classes working.
	super(state)
	if not explode_on_impact or _spent or not _burning:
		return
	# `last_impact` (mass × speed lost) rather than get_contact_impulse(), which
	# reports zero right through a collision here — see SimulatedBody.
	if last_impact >= impact_impulse and state.get_contact_count() > 0:
		# Deferred: this runs inside the physics step with the space locked, and
		# detonating queries the space and frees nodes.
		detonate.call_deferred()


func detonate() -> void:
	if _spent:
		return
	_spent = true
	_burning = false
	set_physics_process(false)

	if explosion_scene != null and Settings.particles_enabled:
		var host: Node = get_parent()
		if host != null:
			var effect: Node = explosion_scene.instantiate()
			host.add_child(effect)
			if effect is Node2D:
				effect.global_position = global_position

	if explosion_radius > 0.0:
		_apply_blast()
	CameraController.request_shake(shake_strength)
	detach_and_free()


func _apply_blast() -> void:
	var space: PhysicsDirectSpaceState2D = get_world_2d().direct_space_state
	var circle: CircleShape2D = CircleShape2D.new()
	circle.radius = explosion_radius
	var query: PhysicsShapeQueryParameters2D = PhysicsShapeQueryParameters2D.new()
	query.shape = circle
	query.transform = Transform2D(0.0, global_position)
	query.collide_with_areas = false
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
		if target is Explosive:
			target.light_fuse()
		if not target.freeze:
			target.apply_central_impulse(offset.normalized() * force)


func _on_mode_applied(mode: GameManager.Mode) -> void:
	super(mode)
	if mode == GameManager.Mode.EDIT:
		_burning = false
		_burn_remaining = 0.0
		_ignite_remaining = -1.0
		_spent = false
		# Back on its mount, ready to be placed again.
		anchored = true
		set_physics_process(false)
	elif mode == GameManager.Mode.PLAY and ignite_mode == TriggerMode.ON_PLAY and not _spent:
		_ignite_remaining = maxf(ignite_delay, 0.001)
		set_physics_process(true)
