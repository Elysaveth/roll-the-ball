extends Node2D
class_name Debris
# A shard thrown off when a prop breaks. Purely decorative.
#
# Deliberately NOT a physics body. Debris exists to sell the break, and real
# bodies would block the ball, wake the solver and change the outcome of a run —
# a puzzle whose solution depends on where the splinters landed is not a puzzle.
# So it integrates its own velocity and collides with nothing.
#
# Built entirely from create(), so breaking needs no extra scene file and a prop
# can tint its own debris.

## Motion only advances during PLAY. Without this the shards would keep drifting
## while the level is paused or frozen for observation, which is exactly the state
## where the player is looking closely.
const GRAVITY: float = 900.0

var velocity: Vector2 = Vector2.ZERO
var spin: float = 0.0
var lifetime: float = 1.2

var _age: float = 0.0


static func create(colour: Color, size: float, from: Vector2, impulse: Vector2, spin_rate: float) -> Debris:
	var piece: Debris = Debris.new()
	piece.velocity = impulse
	piece.spin = spin_rate
	piece.position = from
	piece.rotation = randf_range(0.0, TAU)

	# A rough triangular shard — cheaper than a texture slice and it reads fine at
	# the size these appear.
	var shape: Polygon2D = Polygon2D.new()
	shape.color = colour
	shape.polygon = PackedVector2Array([
		Vector2(-size, size * 0.6),
		Vector2(0.0, -size),
		Vector2(size, size * 0.8),
	])
	piece.add_child(shape)
	return piece


func _process(delta: float) -> void:
	if not GameManager.is_play_mode():
		return

	_age += delta
	if _age >= lifetime:
		queue_free()
		return

	velocity.y += GRAVITY * delta
	position += velocity * delta
	rotation += spin * delta
	# Fades over the back half of its life so shards don't just blink out.
	modulate.a = clampf(1.0 - (_age / lifetime - 0.5) * 2.0, 0.0, 1.0)
