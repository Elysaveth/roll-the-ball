extends SimulatedBody
class_name Ball
# The ball the whole game is about. It is NOT a PlaceableObject — the player
# never positions it. Each level owns one and spawns it at its BallSpawn marker,
# so it lives in the level scene rather than in World/PlacedObjects and is never
# captured into a layout snapshot.
#
# Level.reset_level() throws the old ball away and instantiates a fresh one for
# every attempt, which is the cheapest way to guarantee no stale physics state
# (residual spin, contact caches, sleeping flags) survives into the next run.


func _ready() -> void:
	super()
	add_to_group("ball") # how Goal recognises what hit it
