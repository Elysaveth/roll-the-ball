extends PlaceableObject
class_name Explosive
# Anchored prop that detonates when the ball touches it, shoving everything loose
# nearby away from the blast and shattering anything breakable in range.
#
# Shared by the bomb, the dynamite and the TNT crate — they differ only in exported
# numbers, so there is one script and three scenes.
#
# Detection is a child Area2D ("Trigger") rather than contact_monitor on the body
# itself: anchored props are frozen, and a frozen RigidBody2D does not reliably
# report its own contacts.
#
# The fuse counts down in _physics_process gated on PLAY, NOT with a SceneTree
# timer. A tree timer would keep running while the player has the level paused, so
# a bomb could go off in a supposedly frozen world.

@export_group("Blast")
@export var explosion_scene: PackedScene
## World units. Bodies inside this get pushed; the push falls off linearly.
@export var blast_radius: float = 220.0
## Impulse applied at the centre of the blast, in kg·px/s.
@export var blast_force: float = 1400.0
## Seconds between the ball touching it and the bang. 0 detonates instantly.
@export var fuse_seconds: float = 0.35
## Scales how strongly the blast counts toward breaking things, independently of how
## hard it throws them — a firecracker can shove without shattering.
@export var break_power: float = 1.0
@export var shake_strength: float = 12.0

var _fuse_remaining: float = -1.0
var _spent: bool = false

@onready var _trigger: Area2D = $Trigger


func _ready() -> void:
	super()
	_trigger.body_entered.connect(_on_trigger_body_entered)
	set_physics_process(false)


func _on_trigger_body_entered(body: Node2D) -> void:
	if _spent or not GameManager.is_play_mode():
		return
	if not body.is_in_group("ball"):
		return
	light_fuse()


## Also called by a neighbouring blast, so explosives chain.
func light_fuse() -> void:
	if _spent or _fuse_remaining >= 0.0:
		return
	if fuse_seconds <= 0.0:
		explode()
		return
	_fuse_remaining = fuse_seconds
	set_physics_process(true)


func _physics_process(delta: float) -> void:
	# Gated on PLAY so a pause genuinely stops the fuse.
	if not GameManager.is_play_mode():
		return
	_fuse_remaining -= delta
	if _fuse_remaining <= 0.0:
		explode()


func explode() -> void:
	if _spent:
		return
	_spent = true
	set_physics_process(false)

	var epicentre: Vector2 = global_position
	_spawn_effect(epicentre)
	_apply_blast(epicentre)
	CameraController.request_shake(shake_strength)
	detach_and_free()


func _spawn_effect(at: Vector2) -> void:
	if explosion_scene == null or not Settings.particles_enabled:
		return
	var effect: Node = explosion_scene.instantiate()
	# Parented to the level container, not to this prop — the prop is about to be
	# freed and would take the effect with it.
	var host: Node = get_parent() if get_parent() != null else GameManager.get_placed_objects_container()
	if host == null:
		effect.free()
		return
	host.add_child(effect)
	if effect is Node2D:
		effect.global_position = at


func _apply_blast(epicentre: Vector2) -> void:
	# A one-shot shape query beats keeping a permanent blast Area2D around: the
	# radius is only ever needed for this single frame.
	var space: PhysicsDirectSpaceState2D = get_world_2d().direct_space_state
	var circle: CircleShape2D = CircleShape2D.new()
	circle.radius = blast_radius

	var query: PhysicsShapeQueryParameters2D = PhysicsShapeQueryParameters2D.new()
	query.shape = circle
	query.transform = Transform2D(0.0, epicentre)
	query.collide_with_bodies = true
	query.collide_with_areas = false
	query.exclude = [get_rid()]

	for hit in space.intersect_shape(query, 32):
		var body: Object = hit.get("collider")
		if not body is RigidBody2D:
			continue
		var target: RigidBody2D = body

		var offset: Vector2 = target.global_position - epicentre
		var distance: float = offset.length()
		var direction: Vector2 = offset / distance if distance > 0.01 else Vector2.UP
		var falloff: float = clampf(1.0 - distance / blast_radius, 0.0, 1.0)
		var force: float = blast_force * falloff

		# Breaking comes first: a stone block that shatters shouldn't also be
		# launched, and for an ANCHORED prop this is the only way a blast can affect
		# it at all — frozen bodies refuse impulses.
		if target is PlaceableObject and target.try_break(force * break_power):
			continue
		# Chain reaction: a blast lights any other explosive it reaches.
		if target is Explosive:
			target.light_fuse()
		if target.freeze:
			continue
		target.apply_central_impulse(direction * force)


func _on_mode_applied(mode: GameManager.Mode) -> void:
	super(mode)
	if mode == GameManager.Mode.EDIT:
		# Returning to EDIT rebuilds every prop from the snapshot, so a fresh one is
		# normally what arrives here — reset anyway for the case where it isn't.
		_fuse_remaining = -1.0
		_spent = false
		set_physics_process(false)


func get_save_state() -> Dictionary:
	return {"fuse_seconds": fuse_seconds}


func apply_save_state(state: Dictionary) -> void:
	fuse_seconds = float(state.get("fuse_seconds", fuse_seconds))
