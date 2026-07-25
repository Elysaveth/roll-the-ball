extends CanvasLayer
class_name HUDController
# In-game overlay: the clock, the Play/Pause/Back controls, the prop palette,
# and the panel that appears whenever the simulation stops.
#
# It renders state and forwards intent — every decision belongs to GameManager.
# The one thing it polls rather than listens for is the countdown, because that
# changes every frame and a signal per frame would be silly.

const PANEL_TITLE_COMPLETED: String = "¡A la cesta!"
const PANEL_TITLE_TIME_UP: String = "Se acabó el tiempo"
const PANEL_TITLE_PAUSED: String = "En pausa"

@onready var back_button: Button = $Root/TopBar/BackButton
@onready var play_button: Button = $Root/TopBar/PlayButton
@onready var pause_button: Button = $Root/TopBar/PauseButton
@onready var time_label: Label = $Root/TopBar/TimeLabel
@onready var best_label: Label = $Root/TopBar/BestLabel

@onready var palette_items: HBoxContainer = $Root/Palette/PaletteItems

@onready var result_panel: PanelContainer = $Root/ResultPanel
@onready var result_title: Label = $Root/ResultPanel/VBox/ResultTitle
@onready var result_detail: Label = $Root/ResultPanel/VBox/ResultDetail
@onready var resume_button: Button = $Root/ResultPanel/VBox/Buttons/ResumeButton
@onready var edit_button: Button = $Root/ResultPanel/VBox/Buttons/EditButton
@onready var next_button: Button = $Root/ResultPanel/VBox/Buttons/NextButton
@onready var select_button: Button = $Root/ResultPanel/VBox/Buttons/SelectButton


func _ready() -> void:
	back_button.pressed.connect(GameManager.return_to_level_select)
	play_button.pressed.connect(GameManager.toggle_play)
	pause_button.pressed.connect(GameManager.toggle_pause)
	resume_button.pressed.connect(GameManager.resume)
	edit_button.pressed.connect(GameManager.return_to_edit)
	select_button.pressed.connect(GameManager.return_to_level_select)
	next_button.pressed.connect(_on_next_pressed)

	SignalBus.mode_changed.connect(_on_mode_changed)
	SignalBus.level_started.connect(_on_level_started)
	SignalBus.goal_reached.connect(_on_goal_reached)
	SignalBus.time_ran_out.connect(_on_time_ran_out)
	SignalBus.time_bank_changed.connect(_on_time_bank_changed)

	result_panel.hide()
	# A level may already be loaded by the time the HUD is ready, depending on
	# which _ready runs first, so don't wait for the signal to catch up.
	if GameManager.get_current_level() != null:
		_build_palette()
	_refresh_controls()
	_refresh_best_label()


func _process(_delta: float) -> void:
	time_label.text = format_seconds(GameManager.get_time_remaining())


func _unhandled_input(event: InputEvent) -> void:
	# Keyboard shortcuts for the two buttons that matter. Defined as named
	# actions in Project Settings so the Controls tab can rebind them.
	if event.is_action_pressed("toggle_play"):
		GameManager.toggle_play()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("toggle_pause"):
		GameManager.toggle_pause()
		get_viewport().set_input_as_handled()


# ---------------------------------------------------------------- palette ----

func _build_palette(hard_refresh: bool = true) -> void:
	if hard_refresh:
		for child in palette_items.get_children():
			palette_items.remove_child(child)
			child.queue_free()

	var level: Level = GameManager.get_current_level()
	if level == null:
		return

	for scene in level.available_props:
		if scene == null:
			continue
		var info: Dictionary = _inspect_prop(scene)
		if info.is_empty():
			continue
		# The level says what it offers; the profile says what the player owns.
		# The palette is the intersection — that's the whole unlock mechanic.
		if not SaveManager.is_prop_unlocked(info["prop_id"]):
			continue

		var item: PaletteItem = PaletteItem.new()
		palette_items.add_child(item)
		item.setup(scene, info["icon"], info["label"])


## Instantiates a prop just long enough to read its identity and artwork, then
## throws it away. Only runs once per prop per level load.
func _inspect_prop(scene: PackedScene) -> Dictionary:
	var instance: Node = scene.instantiate()
	if not instance is PlaceableObject:
		instance.free()
		return {}

	var prop: PlaceableObject = instance
	var icon_texture: Texture2D = null
	for child in prop.get_children():
		if child is Sprite2D and child.texture != null:
			icon_texture = child.texture
			break

	var info: Dictionary = {
		"prop_id": prop.prop_id,
		"label": prop.object_name,
		"icon": icon_texture,
	}
	prop.free()
	return info


# ----------------------------------------------------------------- state ----

func _on_level_started(_level_id: int) -> void:
	_build_palette()
	_refresh_controls()
	_refresh_best_label()
	result_panel.hide()


func _on_mode_changed(_new_mode: GameManager.Mode) -> void:
	_refresh_controls()


func _refresh_controls() -> void:
	var mode: GameManager.Mode = GameManager.current_mode
	play_button.text = "Play" if mode == GameManager.Mode.EDIT else "Editar"
	# Only a running simulation can be paused.
	pause_button.disabled = not (mode == GameManager.Mode.PLAY or mode == GameManager.Mode.PAUSED)
	pause_button.text = "Reanudar" if mode == GameManager.Mode.PAUSED else "Pausa"
	# Props are only draggable in EDIT, so offering the palette elsewhere lies.
	palette_items.get_parent().visible = mode == GameManager.Mode.EDIT

	if mode == GameManager.Mode.PAUSED:
		_show_panel(PANEL_TITLE_PAUSED, "", true, true, false)
	elif mode == GameManager.Mode.EDIT or mode == GameManager.Mode.PLAY:
		result_panel.hide()


func _refresh_best_label() -> void:
	var best: float = SaveManager.get_best_time(GameManager.current_level_id)
	if best < 0.0:
		best_label.text = "Sin récord  ·  Banco %s" % format_seconds(SaveManager.get_time_bank())
	else:
		best_label.text = "Récord %s  ·  Banco %s" % [
			format_seconds(best), format_seconds(SaveManager.get_time_bank())
		]


func _on_time_bank_changed(_seconds: float) -> void:
	_refresh_best_label()


# --------------------------------------------------------------- outcomes ----

func _on_goal_reached(level_id: int, attempt_time: float, bank_delta: float) -> void:
	var detail: String = "Tiempo: %s" % format_seconds(attempt_time)
	if bank_delta > 0.0:
		detail += "\nHas recuperado %s para el banco." % format_seconds(bank_delta)
	elif bank_delta < 0.0:
		detail += "\nHas gastado %s del banco." % format_seconds(-bank_delta)
	else:
		detail += "\nNo has mejorado tu récord: el banco no cambia."
	detail += "\nBanco restante: %s" % format_seconds(SaveManager.get_time_bank())

	_show_panel(PANEL_TITLE_COMPLETED, detail, false, true, GameManager.level_exists(level_id + 1))
	_refresh_best_label()


func _on_time_ran_out(_level_id: int) -> void:
	_show_panel(
		PANEL_TITLE_TIME_UP,
		"El banco está a cero. Observa cómo ha quedado el nivel y vuelve a editarlo.",
		false, true, false
	)


func _show_panel(title: String, detail: String, show_resume: bool, show_edit: bool, show_next: bool) -> void:
	result_title.text = title
	result_detail.text = detail
	result_detail.visible = not detail.is_empty()
	resume_button.visible = show_resume
	edit_button.visible = show_edit
	next_button.visible = show_next
	result_panel.show()


func _on_next_pressed() -> void:
	GameManager.load_level(GameManager.current_level_id + 1)


static func format_seconds(seconds: float) -> String:
	return "%.2fs" % seconds
