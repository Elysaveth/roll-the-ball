extends CanvasLayer
class_name HUDController
# In-game overlay: the clock, the Play/Pause/Back controls, the prop palette, the
# per-prop context menu, and the panel that appears whenever the simulation stops.
#
# It renders state and forwards intent — every decision belongs to GameManager.
# Two things it polls rather than listens for: the countdown (changes every frame,
# a signal per frame would be silly).
#
# It does NOT touch the mouse cursor. CursorManager owns that, derived from
# interaction state each frame — see globals/CursorManager.gd for why.
#
# All user-visible text goes through tr() or is a translation key sitting in
# hud.tscn, which Godot translates automatically for Control.text.

## Entries in the per-prop context menu.
enum PropAction { ROTATE, RESIZE, DELETE }

@onready var back_button: Button = $Root/TopBar/BackButton
@onready var play_button: Button = $Root/TopBar/PlayButton
@onready var pause_button: Button = $Root/TopBar/PauseButton
@onready var time_label: Label = $Root/TopBar/TimeLabel
@onready var best_label: Label = $Root/TopBar/BestLabel

@onready var palette_items: HBoxContainer = $Root/Palette/PaletteItems
@onready var prop_menu: PopupMenu = $Root/PropMenu

@onready var result_panel: PanelContainer = $Root/ResultPanel
@onready var result_title: Label = $Root/ResultPanel/VBox/ResultTitle
@onready var result_detail: Label = $Root/ResultPanel/VBox/ResultDetail
@onready var leaderboard: PanelContainer = $Root/ResultPanel/VBox/Leaderboard
@onready var resume_button: Button = $Root/ResultPanel/VBox/Buttons/ResumeButton
@onready var edit_button: Button = $Root/ResultPanel/VBox/Buttons/EditButton
@onready var next_button: Button = $Root/ResultPanel/VBox/Buttons/NextButton
@onready var select_button: Button = $Root/ResultPanel/VBox/Buttons/SelectButton

## Which prop the open context menu belongs to.
var _menu_target: PlaceableObject = null


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
	SignalBus.prop_context_requested.connect(_on_prop_context_requested)
	# Debug mode changes which props are offered, so the palette has to be rebuilt.
	SignalBus.debug_unlock_changed.connect(func(_enabled: bool) -> void: _build_palette())
	prop_menu.id_pressed.connect(_on_prop_menu_id_pressed)

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
	# Keyboard shortcuts. All named actions, so the Controls tab can rebind them.
	if event.is_action_pressed("rotate_prop"):
		_begin_hold_gesture(PropAction.ROTATE)
		get_viewport().set_input_as_handled()
	elif event.is_action_released("rotate_prop"):
		var rotating: PlaceableObject = PlaceableObject.get_rotating()
		if rotating != null:
			rotating.end_hold_rotate()
	elif event.is_action_pressed("scale_prop"):
		_begin_hold_gesture(PropAction.RESIZE)
		get_viewport().set_input_as_handled()
	elif event.is_action_released("scale_prop"):
		var scaling: PlaceableObject = PlaceableObject.get_scaling()
		if scaling != null:
			scaling.end_hold_scale()
	elif event.is_action_pressed("toggle_pause"):
		_on_cancel_pressed()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("toggle_play"):
		GameManager.toggle_play()
		get_viewport().set_input_as_handled()


# ----------------------------------------------------------- prop editing ----

## Holding a gesture key acts on whatever prop is relevant: the one already in a
## gesture, else the one being dragged, else the one under the cursor.
func _begin_hold_gesture(action: PropAction) -> void:
	if not GameManager.is_edit_mode():
		return
	var target: PlaceableObject = PlaceableObject.get_rotating()
	if target == null:
		target = PlaceableObject.get_scaling()
	if target == null:
		target = PlaceableObject.get_dragging()
	if target == null:
		target = PlaceableObject.get_hovered()
	if target == null:
		return

	if action == PropAction.ROTATE:
		target.begin_rotate(false)
	else:
		target.begin_scale(false)


## Escape means "abandon the gesture in progress" while one is running, and only
## falls through to pausing the simulation when there isn't one.
func _on_cancel_pressed() -> void:
	var rotating: PlaceableObject = PlaceableObject.get_rotating()
	if rotating != null:
		rotating.cancel_rotate()
		return
	var scaling: PlaceableObject = PlaceableObject.get_scaling()
	if scaling != null:
		scaling.cancel_scale()
		return
	GameManager.toggle_pause()


func _on_prop_context_requested(prop: Node2D) -> void:
	if not GameManager.is_edit_mode() or not prop is PlaceableObject:
		return

	prop_menu.clear()
	prop_menu.add_item(tr("PROP_ROTATE"), PropAction.ROTATE)
	prop_menu.add_item(tr("PROP_RESIZE"), PropAction.RESIZE)
	prop_menu.add_separator()
	prop_menu.add_item(tr("PROP_DELETE"), PropAction.DELETE)

	# Remembered rather than read back on activation: the cursor will have moved
	# to the menu entry by the time the player picks something.
	_menu_target = prop
	prop_menu.reset_size()
	# Viewport-relative, which is what an embedded subwindow expects.
	prop_menu.position = Vector2i(get_viewport().get_mouse_position())
	prop_menu.popup()


func _on_prop_menu_id_pressed(id: int) -> void:
	if _menu_target == null or not is_instance_valid(_menu_target):
		return
	var target: PlaceableObject = _menu_target
	_menu_target = null

	match id:
		# Sticky: the player is no longer holding a key, so these run until they
		# click to confirm (or press Escape to abandon).
		PropAction.ROTATE:
			target.begin_rotate(true)
		PropAction.RESIZE:
			target.begin_scale(true)
		PropAction.DELETE:
			target.remove_from_canvas()


# ---------------------------------------------------------------- palette ----

func _build_palette() -> void:
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
	play_button.text = tr("HUD_PLAY") if mode == GameManager.Mode.EDIT else tr("HUD_EDIT")
	# Only a running simulation can be paused.
	pause_button.disabled = not (mode == GameManager.Mode.PLAY or mode == GameManager.Mode.PAUSED)
	pause_button.text = tr("HUD_RESUME") if mode == GameManager.Mode.PAUSED else tr("HUD_PAUSE")
	# Props are only draggable in EDIT, so offering the palette elsewhere lies.
	palette_items.get_parent().visible = mode == GameManager.Mode.EDIT

	if mode == GameManager.Mode.PAUSED:
		_show_panel(tr("RESULT_PAUSED"), "", true, true, false)
	elif mode == GameManager.Mode.EDIT or mode == GameManager.Mode.PLAY:
		result_panel.hide()


func _refresh_best_label() -> void:
	var best: float = SaveManager.get_best_time(GameManager.current_level_id)
	var bank: String = format_seconds(SaveManager.get_time_bank())
	if best < 0.0:
		best_label.text = tr("HUD_NO_RECORD") % bank
	else:
		best_label.text = tr("HUD_RECORD") % [format_seconds(best), bank]


func _on_time_bank_changed(_seconds: float) -> void:
	_refresh_best_label()


# --------------------------------------------------------------- outcomes ----

func _on_goal_reached(level_id: int, attempt_time: float, bank_delta: float) -> void:
	var lines: Array[String] = [tr("RESULT_TIME") % format_seconds(attempt_time)]
	if bank_delta > 0.0:
		lines.append(tr("RESULT_REFUND") % format_seconds(bank_delta))
	elif bank_delta < 0.0:
		lines.append(tr("RESULT_SPENT") % format_seconds(-bank_delta))
	else:
		lines.append(tr("RESULT_NO_IMPROVEMENT"))
	lines.append(tr("RESULT_BANK_LEFT") % format_seconds(SaveManager.get_time_bank()))

	_show_panel(
		tr("RESULT_COMPLETED"), "\n".join(lines),
		false, true, GameManager.level_exists(level_id + 1)
	)
	# The whole point of landing the ball: see where it puts you against everyone
	# else on this level.
	leaderboard.show()
	leaderboard.show_board(
 		LeaderboardApi.board_for_level(level_id),
		tr("LB_LEVEL_TITLE") % level_id,
		LeaderboardApi.ValueFormat.SECONDS
	)
	_refresh_best_label()


func _on_time_ran_out(_level_id: int) -> void:
	_show_panel(tr("RESULT_TIME_UP"), tr("RESULT_TIME_UP_DETAIL"), false, true, false)


func _show_panel(title: String, detail: String, show_resume: bool, show_edit: bool, show_next: bool) -> void:
	result_title.text = title
	result_detail.text = detail
	result_detail.visible = not detail.is_empty()
	resume_button.visible = show_resume
	edit_button.visible = show_edit
	next_button.visible = show_next
	# Only a completed level has a board worth showing; _on_goal_reached reveals it.
	leaderboard.hide()
	result_panel.show()


func _on_next_pressed() -> void:
	GameManager.load_level(GameManager.current_level_id + 1)


static func format_seconds(seconds: float) -> String:
	return "%.2fs" % seconds
