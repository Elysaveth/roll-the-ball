extends Control
# A view over the Settings autoload. It holds no state and writes no files —
# Settings owns user://settings.cfg and applies everything, including at boot, so
# a language chosen last session is already in effect before this screen exists.
#
# The Controls tab is still the placeholder buttons from the original scene.
# Wiring it up means replacing them with KeyMapButton instances (one per action:
# camera_up/down/left/right, toggle_play, toggle_pause, rotate_prop, scale_prop);
# KeyMapButton.gd is ready for that and takes a `mapped_action` before being
# added to the tree.

@onready var master_slider: HSlider = $PanelContainer/MarginContainer/VBoxContainer/Tabs/Audio/MasterSlider
@onready var fps_option: OptionButton = $PanelContainer/MarginContainer/VBoxContainer/Tabs/Display/FPSLimit
@onready var language_option: OptionButton = $PanelContainer/MarginContainer/VBoxContainer/Tabs/Accessibility/Language
@onready var title_label: Label = $PanelContainer/MarginContainer/VBoxContainer/Title
@onready var back_button: Button = $PanelContainer/MarginContainer/VBoxContainer/Back


func _ready() -> void:
	title_label.text = "SETTINGS_TITLE"
	back_button.text = "LB_CLOSE"

	_populate_options()

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
