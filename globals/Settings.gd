extends Node
# Autoload singleton — register as "Settings", after SignalBus.
#
# Owns user://settings.cfg and, crucially, APPLIES it at boot. The settings menu
# is only a view over this: a player who picked Spanish last session must get
# Spanish from the title screen onward, not from the moment they happen to reopen
# the options.
#
# Separate from SaveManager on purpose. SaveManager holds game progress, which is
# per-save-file and belongs to the player's run; this holds machine preferences,
# which survive erasing progress and have nothing to do with the game state.

const SETTINGS_PATH: String = "user://settings.cfg"

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
	load_settings()


func load_settings() -> void:
	if _config.load(SETTINGS_PATH) == OK:
		master_volume = float(_config.get_value("audio", "master_volume", 1.0))
		fps_index = int(_config.get_value("display", "fps_index", 0))
		locale_index = int(_config.get_value("accessibility", "language_index", 0))
	apply_all()


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
