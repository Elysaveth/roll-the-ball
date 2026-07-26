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
# Everything on this screen is live. Motion blur was removed rather than left as a
# dead switch — see the note in globals/Settings.gd.

const KEY_MAP_ROW: PackedScene = preload("res://ui/menus/settings/KeyMapButton.tscn")

## Tab order must match the scene. Titles come from translations rather than node
## names, which is what a TabContainer would otherwise display.
const TAB_TITLE_KEYS: PackedStringArray = [
	"SETTINGS_TAB_AUDIO",
	"SETTINGS_TAB_DISPLAY",
	"SETTINGS_TAB_LANGUAGE",
	"SETTINGS_TAB_VISUALS",
	"SETTINGS_TAB_ACCESSIBILITY",
	"SETTINGS_TAB_CONTROLS",
	"SETTINGS_TAB_DEBUG",
]

@onready var tabs: TabContainer = %Tabs
@onready var master_slider: HSlider = %MasterSlider
@onready var music_slider: HSlider = %MusicSlider
@onready var sfx_slider: HSlider = %SFXSlider
@onready var fps_option: OptionButton = %FPSLimit
@onready var vsync_toggle: CheckButton = %VSync
@onready var particles_toggle: CheckButton = %ParticlesToggle
@onready var shake_toggle: CheckButton = %ScreenShakeToggle
@onready var language_option: OptionButton = %Language
@onready var text_size_slider: HSlider = %TextSize
@onready var colorblind_option: OptionButton = %ColorblindMode
@onready var debug_unlock_toggle: CheckButton = %DebugUnlockAll
@onready var controls_list: VBoxContainer = %ControlsList
@onready var back_button: Button = %Back


func _ready() -> void:
	for slider in [master_slider, music_slider, sfx_slider]:
		slider.min_value = 0.0
		slider.max_value = 1.0
		slider.step = 0.01
	text_size_slider.min_value = Settings.MIN_TEXT_SCALE
	text_size_slider.max_value = Settings.MAX_TEXT_SCALE
	text_size_slider.step = 0.05

	master_slider.value_changed.connect(Settings.set_master_volume)
	music_slider.value_changed.connect(Settings.set_music_volume)
	sfx_slider.value_changed.connect(Settings.set_sfx_volume)
	fps_option.item_selected.connect(Settings.set_fps_index)
	vsync_toggle.toggled.connect(Settings.set_vsync_enabled)
	particles_toggle.toggled.connect(Settings.set_particles_enabled)
	shake_toggle.toggled.connect(Settings.set_screen_shake_enabled)
	language_option.item_selected.connect(Settings.set_locale_index)
	text_size_slider.value_changed.connect(Settings.set_text_scale)
	colorblind_option.item_selected.connect(Settings.set_colorblind_index)
	debug_unlock_toggle.toggled.connect(Settings.set_debug_unlock_all)
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

	colorblind_option.clear()
	for i in Settings.COLORBLIND_LABEL_KEYS.size():
		colorblind_option.add_item(tr(Settings.COLORBLIND_LABEL_KEYS[i]), i)


func _show_current_values() -> void:
	# set_value_no_signal / set_pressed_no_signal, or these would echo straight back
	# into Settings and re-save on every open.
	master_slider.set_value_no_signal(Settings.master_volume)
	music_slider.set_value_no_signal(Settings.music_volume)
	sfx_slider.set_value_no_signal(Settings.sfx_volume)
	text_size_slider.set_value_no_signal(Settings.text_scale)
	vsync_toggle.set_pressed_no_signal(Settings.vsync_enabled)
	particles_toggle.set_pressed_no_signal(Settings.particles_enabled)
	shake_toggle.set_pressed_no_signal(Settings.screen_shake_enabled)
	debug_unlock_toggle.set_pressed_no_signal(Settings.debug_unlock_all)
	fps_option.selected = Settings.fps_index
	language_option.selected = Settings.locale_index
	colorblind_option.selected = Settings.colorblind_index


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
