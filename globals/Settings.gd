extends Node
# Autoload singleton — register as "Settings", after SignalBus.
#
# Owns user://settings.cfg and, crucially, APPLIES it at boot. The settings menu
# is only a view over this: a player who picked Spanish last session must get
# Spanish from the title screen onward, not from the moment they happen to reopen
# the options. Same for rebound keys.
#
# Separate from SaveManager on purpose. SaveManager holds game progress, which is
# per-save-file and belongs to the player's run; this holds machine preferences,
# which survive erasing progress and have nothing to do with the game state.

const SETTINGS_PATH: String = "user://settings.cfg"
const KEYBIND_SECTION: String = "keybindings"

## Index order here is the order the settings menu lists them in. English first —
## it is the default language; Spanish is the translation.
const LOCALES: PackedStringArray = ["en", "es"]
## Keys resolved through the translations themselves, so each language names
## itself in the list.
const LOCALE_LABEL_KEYS: PackedStringArray = ["SETTINGS_LANGUAGE_EN", "SETTINGS_LANGUAGE_ES"]
const FPS_OPTIONS: PackedInt32Array = [60, 120, 0] # 0 means uncapped

## Buses come from assets/audio/default_bus_layout.tres. Music and SFX are real
## buses rather than multipliers, so a future mixer or ducking effect has somewhere
## to live.
const BUS_MASTER: String = "Master"
const BUS_MUSIC: String = "Music"
const BUS_SFX: String = "SFX"

## Matches the shader's `mode` uniform in ui/common/colorblind.gdshader.
const COLORBLIND_LABEL_KEYS: PackedStringArray = [
	"SETTINGS_COLORBLIND_OFF",
	"SETTINGS_COLORBLIND_PROTANOPIA",
	"SETTINGS_COLORBLIND_DEUTERANOPIA",
	"SETTINGS_COLORBLIND_TRITANOPIA",
]

## Multiplies the theme's base font size. Applied to the project theme itself, which
## every Control inherits from.
const MIN_TEXT_SCALE: float = 0.8
const MAX_TEXT_SCALE: float = 1.6

var master_volume: float = 1.0
var music_volume: float = 1.0
var sfx_volume: float = 1.0
var fps_index: int = 0
var vsync_enabled: bool = true
var particles_enabled: bool = true
var screen_shake_enabled: bool = true
var locale_index: int = 0
var text_scale: float = 1.0
var colorblind_index: int = 0

## Unlocks every level and prop that exists, for testing and for the other team
## building content. Persisted, because having to re-enable it every launch would
## make it useless to them.
var debug_unlock_all: bool = false

## The project theme, held so text scaling can rewrite its base font size. Captured
## once at boot; every Control inherits from this resource.
var _theme: Theme = null
var _theme_base_font_size: int = 22

var _config: ConfigFile = ConfigFile.new()


func _ready() -> void:
	_config.load(SETTINGS_PATH) # missing file is fine; defaults stand
	_read_values()
	apply_all()
	load_keybindings()
	SignalBus.keybinding_changed.connect(save_keybinding)


func _read_values() -> void:
	master_volume = float(_config.get_value("audio", "master_volume", 1.0))
	music_volume = float(_config.get_value("audio", "music_volume", 1.0))
	sfx_volume = float(_config.get_value("audio", "sfx_volume", 1.0))
	fps_index = int(_config.get_value("display", "fps_index", 0))
	vsync_enabled = bool(_config.get_value("display", "vsync", true))
	particles_enabled = bool(_config.get_value("visuals", "particles", true))
	screen_shake_enabled = bool(_config.get_value("visuals", "screen_shake", true))
	locale_index = int(_config.get_value("accessibility", "language_index", 0))
	text_scale = float(_config.get_value("accessibility", "text_scale", 1.0))
	colorblind_index = int(_config.get_value("accessibility", "colorblind", 0))
	debug_unlock_all = bool(_config.get_value("debug", "unlock_all", false))


func save_settings() -> void:
	_config.set_value("audio", "master_volume", master_volume)
	_config.set_value("audio", "music_volume", music_volume)
	_config.set_value("audio", "sfx_volume", sfx_volume)
	_config.set_value("display", "fps_index", fps_index)
	_config.set_value("display", "vsync", vsync_enabled)
	_config.set_value("visuals", "particles", particles_enabled)
	_config.set_value("visuals", "screen_shake", screen_shake_enabled)
	_config.set_value("accessibility", "language_index", locale_index)
	_config.set_value("accessibility", "text_scale", text_scale)
	_config.set_value("accessibility", "colorblind", colorblind_index)
	_config.set_value("debug", "unlock_all", debug_unlock_all)
	_config.save(SETTINGS_PATH)


func apply_all() -> void:
	_apply_volume()
	_apply_fps()
	_apply_vsync()
	_apply_locale()
	_apply_text_scale()


# ---------------------------------------------------------------- setters ----

func set_master_volume(value: float) -> void:
	master_volume = clampf(value, 0.0, 1.0)
	_apply_volume()
	save_settings()


func set_music_volume(value: float) -> void:
	music_volume = clampf(value, 0.0, 1.0)
	_apply_volume()
	save_settings()


func set_sfx_volume(value: float) -> void:
	sfx_volume = clampf(value, 0.0, 1.0)
	_apply_volume()
	save_settings()


func set_vsync_enabled(enabled: bool) -> void:
	vsync_enabled = enabled
	_apply_vsync()
	save_settings()


func set_particles_enabled(enabled: bool) -> void:
	# Read by Explosive/Rocket before spawning an effect; nothing to apply here.
	particles_enabled = enabled
	save_settings()


func set_screen_shake_enabled(enabled: bool) -> void:
	# Read by CameraController when a shake is requested.
	screen_shake_enabled = enabled
	save_settings()


func set_text_scale(value: float) -> void:
	text_scale = clampf(value, MIN_TEXT_SCALE, MAX_TEXT_SCALE)
	_apply_text_scale()
	save_settings()


func set_colorblind_index(index: int) -> void:
	colorblind_index = clampi(index, 0, COLORBLIND_LABEL_KEYS.size() - 1)
	save_settings()
	SignalBus.colorblind_mode_changed.emit(colorblind_index)


func set_debug_unlock_all(enabled: bool) -> void:
	debug_unlock_all = enabled
	save_settings()
	# Level select and the prop palette both rebuild from this.
	SignalBus.debug_unlock_changed.emit(enabled)


func set_fps_index(index: int) -> void:
	fps_index = clampi(index, 0, FPS_OPTIONS.size() - 1)
	_apply_fps()
	save_settings()


func set_locale_index(index: int) -> void:
	locale_index = clampi(index, 0, LOCALES.size() - 1)
	_apply_locale()
	save_settings()
	SignalBus.locale_changed.emit(LOCALES[locale_index])


func get_locale() -> String:
	return LOCALES[clampi(locale_index, 0, LOCALES.size() - 1)]


# ------------------------------------------------------------- keybindings ----

## Every action the project defines, in declaration order, excluding Godot's
## built-in ui_* set. Read from ProjectSettings rather than hardcoded so the
## Controls tab grows by itself whenever someone adds an action.
##
## Not static: this is only ever reached through the Settings autoload, which is an
## instance, and calling a static function on an instance is a warning. An autoload
## can't declare a matching `class_name` to be called properly as a class either,
## so an instance method is the right shape here.
func get_remappable_actions() -> Array[String]:
	var actions: Array[String] = []
	for property in ProjectSettings.get_property_list():
		var action_name: String = str(property.get("name", ""))
		if not action_name.begins_with("input/"):
			continue
		var action: String = action_name.trim_prefix("input/")
		if action.begins_with("ui_") or action.is_empty():
			continue
		actions.append(action)

	if actions.is_empty():
		# Fallback for any build where the input/* settings aren't enumerable.
		# InputMap is always populated, it just doesn't preserve declaration order.
		for action in InputMap.get_actions():
			var action_name: String = str(action)
			if not action_name.begins_with("ui_"):
				actions.append(action_name)
		actions.sort()
	return actions


func load_keybindings() -> void:
	for action in get_remappable_actions():
		# has_section_key first: ConfigFile.get_value() logs an error for a missing
		# section even when a default is supplied, which is every first launch.
		if not _config.has_section_key(KEYBIND_SECTION, action):
			continue
		var stored: Variant = _config.get_value(KEYBIND_SECTION, action)
		if not stored is Dictionary:
			continue
		var event: InputEvent = _event_from_dict(stored)
		if event == null:
			continue
		if not InputMap.has_action(action):
			continue
		for existing in InputMap.action_get_events(action):
			InputMap.action_erase_event(action, existing)
		InputMap.action_add_event(action, event)


## Connected to SignalBus.keybinding_changed, so a rebind persists without the
## remap widget needing to know this file exists.
func save_keybinding(action: String) -> void:
	var events: Array[InputEvent] = InputMap.action_get_events(action)
	if events.is_empty():
		_config.set_value(KEYBIND_SECTION, action, null)
	else:
		_config.set_value(KEYBIND_SECTION, action, _event_to_dict(events[0]))
	_config.save(SETTINGS_PATH)


## Restores every action to the binding declared in project.godot.
func reset_keybindings() -> void:
	for action in get_remappable_actions():
		_config.set_value(KEYBIND_SECTION, action, null)
		if not InputMap.has_action(action):
			continue
		InputMap.action_erase_events(action)
		for event in ProjectSettings.get_setting("input/" + action, {}).get("events", []):
			InputMap.action_add_event(action, event)
	_config.save(SETTINGS_PATH)
	SignalBus.keybinding_changed.emit("")


## Stored as a plain dict rather than a serialised InputEvent resource, so a
## settings file stays readable and can't execute anything on load.
func _event_to_dict(event: InputEvent) -> Dictionary:
	if event is InputEventKey:
		return {
			"type": "key",
			"physical_keycode": event.physical_keycode,
			"keycode": event.keycode,
		}
	if event is InputEventMouseButton:
		return {"type": "mouse", "button_index": event.button_index}
	return {}


func _event_from_dict(data: Dictionary) -> InputEvent:
	match str(data.get("type", "")):
		"key":
			var key: InputEventKey = InputEventKey.new()
			key.physical_keycode = int(data.get("physical_keycode", 0)) as Key
			key.keycode = int(data.get("keycode", 0)) as Key
			if key.physical_keycode == 0 and key.keycode == 0:
				return null
			return key
		"mouse":
			var button: InputEventMouseButton = InputEventMouseButton.new()
			button.button_index = int(data.get("button_index", 0)) as MouseButton
			if button.button_index == 0:
				return null
			return button
	return null


# ---------------------------------------------------------------- appliers ----

func _apply_volume() -> void:
	_set_bus_volume(BUS_MASTER, master_volume)
	_set_bus_volume(BUS_MUSIC, music_volume)
	_set_bus_volume(BUS_SFX, sfx_volume)


func _set_bus_volume(bus_name: String, linear: float) -> void:
	var bus: int = AudioServer.get_bus_index(bus_name)
	if bus < 0:
		# Music/SFX only exist if the bus layout loaded; don't fail over it.
		return
	# Guard the log: linear_to_db(0) is negative infinity.
	AudioServer.set_bus_volume_db(bus, linear_to_db(linear) if linear > 0.001 else -80.0)


func _apply_vsync() -> void:
	DisplayServer.window_set_vsync_mode(
		DisplayServer.VSYNC_ENABLED if vsync_enabled else DisplayServer.VSYNC_DISABLED
	)


## Scales every piece of text by rewriting the project theme's base font size.
## Controls with an explicit theme_override_font_sizes keep their own size — those
## are the deliberate display sizes like the title, and blowing them up too would
## break the layouts they were chosen for.
func _apply_text_scale() -> void:
	if _theme == null:
		var path: String = str(ProjectSettings.get_setting("gui/theme/custom", ""))
		if path.is_empty():
			return
		_theme = load(path)
		if _theme == null:
			return
		_theme_base_font_size = _theme.default_font_size
	_theme.default_font_size = maxi(8, int(round(_theme_base_font_size * text_scale)))


func _apply_fps() -> void:
	Engine.max_fps = FPS_OPTIONS[clampi(fps_index, 0, FPS_OPTIONS.size() - 1)]


func _apply_locale() -> void:
	TranslationServer.set_locale(get_locale())
