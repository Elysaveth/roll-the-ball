extends Control

const SETTINGS_PATH: String = "user://settings.cfg"
var config: ConfigFile = ConfigFile.new()

@onready var master_slider: HSlider = $PanelContainer/MarginContainer/VBoxContainer/Tabs/Audio/MasterSlider
@onready var fps_option: OptionButton = $PanelContainer/MarginContainer/VBoxContainer/Tabs/Display/FPSLimit
@onready var language_option: OptionButton = $PanelContainer/MarginContainer/VBoxContainer/Tabs/Accessibility/Language

func _ready():
	# 1. Populate Dropdowns
	fps_option.add_item("60 FPS", 60)
	fps_option.add_item("120 FPS", 120)
	fps_option.add_item("Uncapped", 0)

	language_option.add_item("English", 0)
	language_option.add_item("Español", 1)

	# 2. Connect Signals
	master_slider.value_changed.connect(_on_master_audio_changed)
	fps_option.item_selected.connect(_on_fps_selected)
	language_option.item_selected.connect(_on_language_selected)
	$PanelContainer/MarginContainer/VBoxContainer/CloseButton.pressed.connect(_on_close_button_pressed)

	# 3. Load Saved Settings (or create defaults)
	load_settings()

func load_settings():
	var err: int = config.load(SETTINGS_PATH)
	if err == OK:
		# File exists, load values (with fallback defaults if a key is missing)
		var master_vol = config.get_value("audio", "master_volume", 1.0)
		var fps_idx = config.get_value("display", "fps_index", 0)
		var lang_idx = config.get_value("accessibility", "language_index", 0)

		# Update UI Elements without triggering their signals recursively
		master_slider.set_value_no_signal(master_vol)
		fps_option.selected = fps_idx
		language_option.selected = lang_idx

		# Apply the values to the game engine directly
		apply_audio(master_vol)
		apply_fps(fps_idx)
		apply_language(lang_idx)
	else:
		# First time opening the game: save current UI defaults to file
		save_settings()

func save_settings():
	config.set_value("audio", "master_volume", master_slider.value)
	config.set_value("display", "fps_index", fps_option.selected)
	config.set_value("accessibility", "language_index", language_option.selected)
	config.save(SETTINGS_PATH)

# --- Signal Callbacks (Triggered by Player Input) ---

func _on_master_audio_changed(value: float):
	apply_audio(value)
	save_settings()

func _on_fps_selected(index: int):
	apply_fps(index)
	save_settings()

func _on_language_selected(index: int):
	apply_language(index)
	save_settings()

func _on_close_button_pressed():
	hide()

# --- Engine Application Logic ---

func apply_audio(value: float):
	var bus_idx: int = AudioServer.get_bus_index("Master")
	# Prevent taking log of 0 if slider goes all the way down
	var db: float = linear_to_db(value) if value > 0.001 else -80.0
	AudioServer.set_bus_volume_db(bus_idx, db)

func apply_fps(index: int):
	var target_fps: int = fps_option.get_item_id(index)
	Engine.max_fps = target_fps

func apply_language(index: int):
	match index:
		0: TranslationServer.set_locale("en")
		1: TranslationServer.set_locale("es")