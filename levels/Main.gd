extends Node2D
class_name Main
# Root of the gameplay scene (levels/main.tscn).
#
# Deliberately thin. Main is what knows the scene layout, so its only job is
# telling GameManager where the two containers are and then getting out of the
# way — every rule about modes, timing and saving lives in the autoloads.
#
# Scene tree:
# Main (Node2D, this script)
# ├── World (Node2D)
# │   ├── Camera2D          (systems/camera_system/CameraController.gd)
# │   ├── Level (Node2D)    -- the current level scene is instanced in here
# │   └── PlacedObjects (Node2D)
# │                         -- props the player drops; the only thing captured
# │                            into a layout snapshot or a save file
# └── UI
#     └── HUD (CanvasLayer, ui/hud/HUDController.gd)
#
# Autoloads required (Project Settings > Autoload), in this order:
# SignalBus -> GameManager -> SaveManager -> SilentWolf (plugin) -> LeaderboardApi

@onready var world: Node2D = $World
@onready var level_container: Node2D = $World/Level
@onready var placed_objects: Node2D = $World/PlacedObjects


func _ready() -> void:
	GameManager.register_world(level_container, placed_objects)
	GameManager.notify_world_ready()
