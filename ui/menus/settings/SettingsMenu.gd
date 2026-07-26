extends Control
# A view over the Settings autoload. It holds no state and writes no files —
# Settings owns user://settings.cfg and applies everything, including at boot, so
# a language chosen last session is already in effect before this screen exists.
#
# The Controls tab is generated at runtime from whatever actions the project
# defines, so adding an action to Project Settings is all it takes to get a
# rebindable row for it — nobody has to touch this scene again.
#
# Nodes are reached by unique name (%Name) rather than by path, so rearranging the
# scene's containers doesn't break the script.
#
# NOT YET WIRED, deliberately left as labelled placeholders for whoever picks them
# up: music/SFX volumes (need their own audio buses), VSync, the three Visuals
# toggles, text size and colourblind mode. Master volume, FPS limit, language and
# the whole Controls tab are live.

const KEY_MAP_ROW: PackedScene = preload("res://ui/menus/settings/KeyMapButton.tscn")

## Tab order must match the scene. Titles come from translations rather than node
## names, which is what a TabContainer would otherwise display.
const TAB_TITLE_KEYS: PackedStringArray = [
	"SETTINGS_TAB_AUDIO",
	"SETTINGS_TAB_DISPLAY",
	"SETTINGS_TAB_VISUALS",
	"SETTINGS_TAB_ACCESSIBILITY",
	"SETTINGS_TAB_CONTROLS",
]

@onready var tabs: TabContainer = %Tabs
@onready var master_slider: HSlider = %MasterSlider
@onready var fps_option: OptionButton = %FPSLimit
@onready var language_option: OptionButton = %Language
@onready var controls_list: VBoxContainer = %ControlsList
@onready var back_button: Button = %Back


func _ready() -> void:
	master_slider.min_value = 0.0
	master_slider.max_value = 1.0
	master_slider.step = 0.01

	master_slider.value_changed.connect(Settings.set_master_volume)
	fps_option.item_selected.connect(Settings.set_fps_index)
	language_option.item_selected.connect(Settings.set_locale_index)
	back_button.pressed.connect(hide)
	# Each language names itself in the dropdown, and tab titles and action names
	# are translated too, so all of it is rebuilt when the locale changes.
	SignalBus.locale_changed.connect(_on_locale_changed)

	_refresh_translated_text()
	_build_controls_tab()
	_show_current_values()


func _refresh_translated_text() -> void:
	_populate_options()
	for i in mini(TAB_TITLE_KEYS.size(), tabs.get_tab_count()):
		tabs.set_tab_title(i, tr(TAB_TITLE_KEYS[i]))


func _populate_options() -> void:
	fps_option.clear()
	for i in Settings.FPS_OPTIONS.size():
		var fps: int = Settings.FPS_OPTIONS[i]
		fps_option.add_item(tr("SETTINGS_FPS_UNCAPPED") if fps == 0 else "%d FPS" % fps, i)

	language_option.clear()
	for i in Settings.LOCALE_LABEL_KEYS.size():
		language_option.add_item(tr(Settings.LOCALE_LABEL_KEYS[i]), i)


func _show_current_values() -> void:
	# set_value_no_signal, or this would echo straight back into Settings.
	master_slider.set_value_no_signal(Settings.master_volume)
	fps_option.selected = Settings.fps_index
	language_option.selected = Settings.locale_index


func _on_locale_changed(_locale: String) -> void:
	_refresh_translated_text()
	_show_current_values()
	_build_controls_tab()


## One rebindable row per project-defined action, in the order they're declared in
## Project Settings, so the scene needs no maintenance as actions come and go.
func _build_controls_tab() -> void:
	for child in controls_list.get_children():
		controls_list.remove_child(child)
		child.queue_free()

	var actions: Array[String] = Settings.get_remappable_actions()
	if actions.is_empty():
		var empty: Label = Label.new()
		empty.text = "CONTROLS_NONE"
		controls_list.add_child(empty)
		return

	for action in actions:
		var row: Node = KEY_MAP_ROW.instantiate()
		# Set before entering the tree: KeyMapButton reads it in _ready.
		row.mapped_action = action
		controls_list.add_child(row)

	var reset: Button = Button.new()
	reset.text = tr("CONTROLS_RESET")
	reset.pressed.connect(_on_reset_controls_pressed)
	controls_list.add_child(reset)


func _on_reset_controls_pressed() -> void:
	Settings.reset_keybindings()
	_build_controls_tab()
