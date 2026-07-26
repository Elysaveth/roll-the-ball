extends Control
# Boot scene. Its one job is making sure a player name exists before anything
# else happens, because a leaderboard entry without a name is worthless.
#
# The name is persisted to the profile, so a returning player sees theirs
# prefilled and can change it here rather than being asked again.

const MAX_NAME_LENGTH: int = 20

@onready var name_field: LineEdit = $Center/Panel/VBox/NameField
@onready var hint_label: Label = $Center/Panel/VBox/HintLabel
@onready var play_button: Button = $Center/Panel/VBox/PlayButton
@onready var settings_button: Button = $Center/Panel/VBox/SettingsButton
@onready var quit_button: Button = $Center/Panel/VBox/QuitButton
@onready var settings_menu: Control = $SettingsMenu


func _ready() -> void:
	name_field.max_length = MAX_NAME_LENGTH
	name_field.text = SaveManager.get_player_name()
	name_field.text_changed.connect(_on_name_changed)
	name_field.text_submitted.connect(_on_name_submitted)
	play_button.pressed.connect(_start)
	settings_button.pressed.connect(settings_menu.show)
	quit_button.pressed.connect(_on_quit_pressed)
	settings_menu.hide()

	name_field.grab_focus()
	name_field.caret_column = name_field.text.length()
	_refresh()


func _on_name_changed(_new_text: String) -> void:
	_refresh()


func _on_name_submitted(_new_text: String) -> void:
	# Enter starts the game, but only if the name would actually be accepted.
	if not play_button.disabled:
		_start()


func _refresh() -> void:
	var is_valid: bool = not name_field.text.strip_edges().is_empty()
	play_button.disabled = not is_valid
	hint_label.visible = not is_valid


func _start() -> void:
	SaveManager.set_player_name(name_field.text)
	GameManager.go_to_level_select()


func _on_quit_pressed() -> void:
	get_tree().quit()
