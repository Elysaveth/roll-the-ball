extends Node2D
class_name Main
# Attach to the root node of your main gameplay scene.
#
# Expected scene tree:
# Main (Node2D, this script)
# ├── World (Node2D)
# │   ├── Camera2D (CameraController.gd)
# │   └── PlacedObjects (Node2D)              -- objects get parented here;
# │                                              auto-added to "spawn_root" below
# └── UI
#     ├── hud/ (CanvasLayer, HUDController.gd)  -- Play/Stop button, palette
#     │   ├── PlayButton (Button)
#     │   └── Palette (Control)
#     │       └── ...PaletteItem children (ui/hud/PaletteItem.gd)
#     └── menus/ (your MainMenu / PauseMenu / LevelSelect / Leaderboard screens)
#         -- not covered by these base scripts; wire them up to SignalBus
#            (level_saved, level_loaded, scores_received, ...) as needed.
#
# Autoloads required (Project Settings > Autoload), in this order:
# SignalBus -> GameManager -> SaveManager -> SilentWolf (from the plugin) -> LeaderboardAPI

@onready var world: Node2D = $World
@onready var placed_objects: Node2D = $World/PlacedObjects

func _ready() -> void:
	placed_objects.add_to_group("spawn_root") # lets SaveManager.load_level() find it without a direct reference
	GameManager.set_mode(GameManager.Mode.EDIT)
