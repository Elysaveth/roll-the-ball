extends Node
# Autoload singleton — register as "GameManager", after SignalBus.
# Owns the EDIT/PLAY state. Query it directly for current state; it broadcasts
# changes through SignalBus so it doesn't need to know who's listening.

enum Mode { EDIT, PLAY }

var current_mode: Mode = Mode.EDIT

func toggle_play() -> void:
	set_mode(Mode.PLAY if current_mode == Mode.EDIT else Mode.EDIT)

func set_mode(mode: Mode) -> void:
	if mode == current_mode:
		return
	current_mode = mode
	SignalBus.mode_changed.emit(current_mode)

func is_edit_mode() -> bool:
	return current_mode == Mode.EDIT

func is_play_mode() -> bool:
	return current_mode == Mode.PLAY
