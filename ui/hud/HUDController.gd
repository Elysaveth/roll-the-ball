extends CanvasLayer
class_name HUDController
# Attach to the CanvasLayer holding your in-game HUD — lives under ui/hud/
# alongside PaletteItem.gd, since both are gameplay overlays rather than
# standalone menu screens (those live under ui/menus/ and aren't covered by
# these base scripts — have them listen to SignalBus too, e.g. level_saved,
# level_loaded, scores_received, wherever they need to react).
# Expects a child Button named "PlayButton".

@onready var play_button: Button = $PlayButton

func _ready() -> void:
	play_button.pressed.connect(_on_play_button_pressed)
	SignalBus.mode_changed.connect(_on_mode_changed)
	_update_button_text(GameManager.current_mode)

func _on_play_button_pressed() -> void:
	GameManager.toggle_play()

func _on_mode_changed(new_mode: GameManager.Mode) -> void:
	_update_button_text(new_mode)

func _update_button_text(mode: GameManager.Mode) -> void:
	play_button.text = "Play" if mode == GameManager.Mode.EDIT else "Stop"
