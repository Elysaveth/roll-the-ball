extends PlaceableObject
class_name Explosive
# Anything that goes bang. Shared by the bomb, the dynamite and the TNT crate, which
# differ only in the numbers below — one script, three scenes.
#
# Every knob a designer needs is exported, so a new explosive is a new .tscn with
# different values rather than new code:
#
#   trigger_mode    what sets it off (ball, anything, the start of the attempt, or
#                   only a neighbouring blast)
#   arm_delay       for ON_PLAY, how long after the attempt starts it triggers
#   fuse_seconds    trigger -> bang. 0 detonates on contact.
#   blast_radius    how far the blast reaches
#   blast_force     how hard it throws loose bodies
#   break_power     how strongly it counts toward SHATTERING things, separately from
#                   how hard it throws them — a firecracker can shove without breaking
#   chain_reaction  whether it lights other explosives in range
#   shake_strength  how much the screen jolts
#
# Contact is detected with a child Area2D named "Trigger" rather than
# contact_monitor: these are anchored, and a frozen RigidBody2D does not reliably
# report its own contacts.
#
# The fuse counts down in _physics_process gated on PLAY, NOT with a SceneTree timer.
# A tree timer would keep running while the player has the level paused, so a bomb
# could go off in a supposedly frozen world.

@export_group("Trigger")
@export var trigger_mode: TriggerMode = TriggerMode.BALL_CONTACT
## Only used by ON_PLAY. Gives the player a moment to see the level before it blows.
@export var arm_delay: float = 0.4
## Seconds from being triggered to detonating. 0 means on contact.
@export var fuse_seconds: float = 0.35

@export_group("Blast")
@export var explosion_scene: PackedScene
## World units. Bodies inside this get pushed; the push falls off linearly.
@export var blast_radius: float = 220.0
## Impulse at the centre of the blast, in kg·px/s.
@export var blast_force: float = 1400.0
## Multiplies the blast's breaking power without changing how hard it throws.
@export var break_power: float = 1.0
## Whether this blast sets off other explosives it reaches.
@export var chain_reaction: bool = true
@export var shake_strength: float = 12.0

var _fuse_remaining: float = -1.0
var _arm_remaining: float = -1.0
var _spent: bool = false

@onready var _trigger: Area2D = $Trigger


func _ready() -> void:
	super()
	_trigger.body_entered.connect(_on_trigger_body_entered)
	set_physics_process(false)


func _on_trigger_body_entered(body: Node2D) -> void:
	if _spent or not GameManager.is_play_mode():
		return
	match trigger_mode:
		TriggerMode.BALL_CONTACT:
			if body.is_in_group("ball"):
				light_fuse()
		TriggerMode.ANY_CONTACT:
			# Static level geometry shouldn't count, or an explosive resting on the
			# floor would trigger the instant play started.
			if body is RigidBody2D:
				light_fuse()
		TriggerMode.ON_PLAY, TriggerMode.MANUAL:
			pass


## Starts the fuse. Also called by a neighbouring blast, so explosives chain.
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

	if _arm_remaining >= 0.0:
		_arm_remaining -= delta
		if _arm_remaining <= 0.0:
			_arm_remaining = -1.0
			light_fuse()
		return

	if _fuse_remaining >= 0.0:
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
		# Scale the stock burst to roughly match the blast it represents.
		var visual_scale: float = clampf(blast_radius / 220.0, 0.5, 3.0)
		effect.scale *= visual_scale


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
		if chain_reaction and target is Explosive:
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
		_arm_remaining = -1.0
		_spent = false
		set_physics_process(false)
	elif mode == GameManager.Mode.PLAY and trigger_mode == TriggerMode.ON_PLAY and not _spent:
		# Arm now; the countdown itself runs in _physics_process so a pause holds it.
		_arm_remaining = maxf(arm_delay, 0.001)
		set_physics_process(true)


# NOTHING is saved here on purpose, and that's a correction rather than an omission.
#
# fuse_seconds used to be written into the layout save and restored on load. It is a
# DESIGN-TIME value authored per scene, not something the player edits — so once a
# level had been saved, its props carried the old fuse forever and every later
# balance change was silently overridden by the save file. That is why the bomb still
# waited ~0.35s after being retuned to detonate on contact.
#
# Only persist state the PLAYER can change. Transform already rides along in
# LevelLayout; anything a designer sets belongs solely to the .tscn.
