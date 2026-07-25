extends AnimatedSprite2D
class_name Explosion
# Fire-and-forget blast visual. Spawn it, position it, forget it — it frees
# itself when the animation ends. The SpriteFrames animation must have `loop`
# turned OFF or animation_finished never fires and these pile up forever.

@export var animation_name: StringName = &"explosion"


func _ready() -> void:
	animation_finished.connect(queue_free)
	play(animation_name)
