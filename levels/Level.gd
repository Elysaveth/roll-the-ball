extends Node2D
class_name Level
# Attach to the root of every level scene (levels/level_01/level_01.tscn, ...).
#
# Expected children:
#   Geometry   (Node2D)    static walls/floors — StaticBody2D pieces under here
#   BallSpawn  (Marker2D)  where the ball starts each attempt
#   Goal       (Area2D)    with Goal.gd — the basket
#
# A level owns its ball and its static furniture. It knows nothing about modes,
# timers or the bank; GameManager calls reset_level() at the start of every
# attempt and that is the entire contract.

## Which props this level offers in the palette. The HUD reads it to build the
## toolbar, intersected with what the player has actually unlocked.
@export var available_props: Array[PackedScene] = []
@export var ball_scene: PackedScene
@export var display_name: String = ""

@onready var ball_spawn: Marker2D = $BallSpawn

var _ball: Ball = null


## Puts the level's own dynamic contents back on the start line. Called by
## GameManager before each attempt and again when returning to EDIT.
##
## The ball is rebuilt from scratch rather than repositioned: a fresh instance
## can't carry over residual spin, contact caches or a sleeping flag from the
## previous run.
func reset_level() -> void:
	if _ball != null and is_instance_valid(_ball):
		remove_child(_ball)
		_ball.queue_free()
	_ball = null

	if ball_scene == null:
		push_warning("Level '%s': ball_scene is not set — nothing to roll" % name)
		return
	if ball_spawn == null:
		push_error("Level '%s': no BallSpawn child" % name)
		return

	var instance: Node = ball_scene.instantiate()
	if not instance is Ball:
		push_error("Level '%s': ball_scene's root is not a Ball" % name)
		instance.free()
		return

	_ball = instance
	add_child(_ball)
	_ball.global_position = ball_spawn.global_position


## For the camera to follow, or a HUD to point an off-screen indicator at.
func get_ball() -> Ball:
	return _ball if _ball != null and is_instance_valid(_ball) else null
