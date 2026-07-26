extends Control
# A view over the Settings autoload. It holds no state and writes no files —
# Settings owns user://settings.cfg and applies everything, including at boot, so
# a language chosen last session is already in effect before this screen exists.
#
# The Controls tab is generated at runtime from whatever actions the project
# defines, so adding an action to Project Settings is all it takes to get a
# rebindable row for it — nobody has to touch this scene again.

const KEY_MAP_ROW: PackedScene = preload("res://ui/menus/settings/KeyMapButton.tscn")

@onready var master_slider: HSlider = $PanelContainer/MarginContainer/VBoxContainer/Tabs/Audio/MasterSlider
@onready var fps_option: OptionButton = $PanelContainer/MarginContainer/VBoxContainer/Tabs/Display/FPSLimit
@onready var language_option: OptionButton = $PanelContainer/MarginContainer/VBoxContainer/Tabs/Accessibility/Language
@onready var controls_tab: VBoxContainer = $PanelContainer/MarginContainer/VBoxContainer/Tabs/Controls
@onready var title_label: Label = $PanelContainer/MarginContainer/VBoxContainer/Title
@onready var back_button: Button = $PanelContainer/MarginContainer/VBoxContainer/Back


func _ready() -> void:
	title_label.text = "SETTINGS_TITLE"
	back_button.text = "LB_CLOSE"

	_populate_options()
	_build_controls_tab()

	master_slider.min_value = 0.0
	master_slider.max_value = 1.0
	master_slider.step = 0.01

	master_slider.value_changed.connect(Settings.set_master_volume)
	fps_option.item_selected.connect(Settings.set_fps_index)
	language_option.item_selected.connect(Settings.set_locale_index)
	back_button.pressed.connect(hide)
	# Each language names itself in the dropdown, so the list has to be rebuilt
	# whenever the locale changes.
	SignalBus.locale_changed.connect(_on_locale_changed)

	_show_current_values()


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
	_populate_options()
	_show_current_values()
	# Action names are translated too.
	_build_controls_tab()


## One rebindable row per project-defined action, in the order they're declared in
## Project Settings. The placeholder buttons that used to live in this tab are
## cleared out first, so the scene needs no maintenance as actions come and go.
func _build_controls_tab() -> void:
	for child in controls_tab.get_children():
		controls_tab.remove_child(child)
		child.queue_free()

	var actions: Array[String] = Settings.get_remappable_actions()
	if actions.is_empty():
		var empty: Label = Label.new()
		empty.text = "CONTROLS_NONE"
		controls_tab.add_child(empty)
		return

	for action in actions:
		var row: Node = KEY_MAP_ROW.instantiate()
		# Set before entering the tree: KeyMapButton reads it in _ready.
		row.mapped_action = action
		controls_tab.add_child(row)

	var reset: Button = Button.new()
	reset.text = "CONTROLS_RESET"
	reset.pressed.connect(_on_reset_controls_pressed)
	controls_tab.add_child(reset)


func _on_reset_controls_pressed() -> void:
	Settings.reset_keybindings()
	_build_controls_tab()
