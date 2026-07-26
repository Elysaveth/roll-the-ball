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

var master_volume: float = 1.0
var fps_index: int = 0
var locale_index: int = 0

var _config: ConfigFile = ConfigFile.new()


func _ready() -> void:
	_config.load(SETTINGS_PATH) # missing file is fine; defaults stand
	_read_values()
	apply_all()
	load_keybindings()
	SignalBus.keybinding_changed.connect(save_keybinding)


func _read_values() -> void:
	master_volume = float(_config.get_value("audio", "master_volume", 1.0))
	fps_index = int(_config.get_value("display", "fps_index", 0))
	locale_index = int(_config.get_value("accessibility", "language_index", 0))


func save_settings() -> void:
	_config.set_value("audio", "master_volume", master_volume)
	_config.set_value("display", "fps_index", fps_index)
	_config.set_value("accessibility", "language_index", locale_index)
	_config.save(SETTINGS_PATH)


func apply_all() -> void:
	_apply_volume()
	_apply_fps()
	_apply_locale()


# ---------------------------------------------------------------- setters ----

func set_master_volume(value: float) -> void:
	master_volume = clampf(value, 0.0, 1.0)
	_apply_volume()
	save_settings()


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
	var bus: int = AudioServer.get_bus_index("Master")
	if bus < 0:
		return
	# Guard the log: linear_to_db(0) is negative infinity.
	var db: float = linear_to_db(master_volume) if master_volume > 0.001 else -80.0
	AudioServer.set_bus_volume_db(bus, db)


func _apply_fps() -> void:
	Engine.max_fps = FPS_OPTIONS[clampi(fps_index, 0, FPS_OPTIONS.size() - 1)]


func _apply_locale() -> void:
	TranslationServer.set_locale(get_locale())
