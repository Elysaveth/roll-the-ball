extends Area2D
class_name Goal
# The basket. Put one in every level scene, named "Goal", with a CollisionShape2D
# child covering the mouth of it.
#
# It only reports the hit; GameManager decides what that costs. No re-arm logic
# is needed because notify_goal_reached() ignores anything outside PLAY mode, and
# the first hit switches the mode to COMPLETED — so a ball rattling around inside
# the basket can't score twice.


func _ready() -> void:
	monitoring = true
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("ball"):
		GameManager.notify_goal_reached()
