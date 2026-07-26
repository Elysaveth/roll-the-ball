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
@onready var edit_button: Button = $Root/ResultPanel/VBox/Buttons/EditButton
@onready var next_button: Button = $Root/ResultPanel/VBox/Buttons/NextButton
@onready var select_button: Button = $Root/ResultPanel/VBox/Buttons/SelectButton

## Pausing dims the whole screen instead of opening a panel — the point of pausing is
## to LOOK at the level, so anything that covers it is working against the player.
## Only the three ways out sit on top of the dimmer.
@onready var pause_overlay: ColorRect = $Root/PauseOverlay
@onready var pause_back_button: Button = $Root/PauseOverlay/Center/Buttons/PauseBackButton
@onready var pause_edit_button: Button = $Root/PauseOverlay/Center/Buttons/PauseEditButton
@onready var pause_resume_button: Button = $Root/PauseOverlay/Center/Buttons/PauseResumeButton

## Which prop the open context menu belongs to.
var _menu_target: PlaceableObject = null
## While staged, _refresh_controls must not put the palette back — the tutorial owns
## what is visible until it hands over.
var _tutorial_staged: bool = false
## Set while Joe's follow-up is playing: the result panel is built but withheld until
## he's finished, and the pause dimmer is shown as a demonstration rather than because
## the game is actually paused.
var _result_held: bool = false
var _pause_demo: bool = false


func _ready() -> void:
	# The tutorial finds the HUD through this group rather than a node path, so
	# main.tscn can be rearranged without breaking it.
	add_to_group("hud")
	back_button.pressed.connect(GameManager.return_to_level_select)
	play_button.pressed.connect(GameManager.toggle_play)
	pause_button.pressed.connect(GameManager.toggle_pause)
	edit_button.pressed.connect(GameManager.return_to_edit)
	pause_back_button.pressed.connect(GameManager.return_to_level_select)
	pause_edit_button.pressed.connect(GameManager.return_to_edit)
	pause_resume_button.pressed.connect(GameManager.resume)
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
	pause_overlay.hide()
	# A level may already be loaded by the time the HUD is ready, depending on
	# which _ready runs first, so don't wait for the signal to catch up.
	if GameManager.get_current_level() != null:
		_build_palette()
	_refresh_controls()
	_refresh_best_label()


func _process(_delta: float) -> void:
	time_label.text = format_seconds(GameManager.get_time_remaining())


# --------------------------------------------------------------- tutorial ----
# The tutorial reveals the HUD a piece at a time as Joe explains it, so it needs to be
# able to take pieces away first. Kept as explicit named calls rather than letting the
# tutorial reach into node paths, so rearranging hud.tscn can't break it.

## Hides everything the tutorial introduces. Called before the first line is spoken.
func stage_for_tutorial() -> void:
	_tutorial_staged = true
	set_clock_visible(false)
	set_palette_visible(false)
	set_controls_visible(false)


## Puts everything back, whether the tutorial finished or was skipped.
func unstage_from_tutorial() -> void:
	_tutorial_staged = false
	set_clock_visible(true)
	set_palette_visible(true)
	set_controls_visible(true)
	_refresh_controls()


func set_clock_visible(shown: bool) -> void:
	time_label.visible = shown
	best_label.visible = shown


func set_palette_visible(shown: bool) -> void:
	palette_items.get_parent().visible = shown


## The Play/Pause/Back row. Hidden during the tutorial so the level can't be started
## halfway through the explanation.
func set_controls_visible(shown: bool) -> void:
	back_button.visible = shown
	play_button.visible = shown
	pause_button.visible = shown


## Keeps the finished result panel off screen while Joe talks over the top of it.
## There is no arrangement in which he and a full-height panel both fit.
func hold_result_panel() -> void:
	_result_held = true
	result_panel.hide()


func release_result_panel() -> void:
	if not _result_held:
		return
	_result_held = false
	result_panel.show()


## Shows the pause dimmer WITHOUT pausing anything, purely to point at the buttons on
## it. Kept separate from the real pause state so _refresh_controls can't fight it.
func show_pause_demo(shown: bool) -> void:
	_pause_demo = shown
	pause_overlay.visible = shown or GameManager.current_mode == GameManager.Mode.PAUSED


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

	# An empty available_props means "whatever the player owns", which is the sane
	# default: a level only needs to fill it in when it deliberately RESTRICTS the
	# choice. Otherwise every new prop would have to be added to every level by hand.
	var offered: Array[PackedScene] = level.available_props
	if offered.is_empty():
		offered = PropUnlocks.unlocked_scenes()

	for scene in offered:
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
		# Animated props are just as common as static ones now, and only looking for a
		# Sprite2D left them with a blank slot in the toolbar.
		if child is AnimatedSprite2D:
			icon_texture = _animation_frame_texture(child, prop.palette_icon_frame)
			if icon_texture != null:
				break

	if icon_texture == null:
		push_warning("HUDController: '%s' has no artwork for the palette" % prop.prop_id)

	var info: Dictionary = {
		"prop_id": prop.prop_id,
		"label": prop.object_name,
		"icon": icon_texture,
	}
	prop.free()
	return info


## One frame out of an AnimatedSprite2D, for use as a toolbar icon.
##
## Falls back to the sprite's own frame when the prop doesn't nominate one, and to the
## first animation when the authored one is missing — a prop with a blank icon is easy
## to miss, so every route here ends in a picture if one exists at all.
func _animation_frame_texture(sprite: AnimatedSprite2D, wanted_frame: int) -> Texture2D:
	var frames: SpriteFrames = sprite.sprite_frames
	if frames == null:
		return null

	var animation: StringName = sprite.animation
	if not frames.has_animation(animation):
		var names: PackedStringArray = frames.get_animation_names()
		if names.is_empty():
			return null
		animation = names[0]

	var count: int = frames.get_frame_count(animation)
	if count <= 0:
		return null
	var index: int = wanted_frame if wanted_frame >= 0 else sprite.frame
	return frames.get_frame_texture(animation, clampi(index, 0, count - 1))


# ----------------------------------------------------------------- state ----

func _on_level_started(_level_id: int) -> void:
	_result_held = false
	_pause_demo = false
	pause_overlay.hide()
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
	# Props are only draggable in EDIT, so offering the palette elsewhere lies. The
	# tutorial overrides this while it's explaining what the palette is for.
	palette_items.get_parent().visible = mode == GameManager.Mode.EDIT and not _tutorial_staged

	# Paused is the dimmer, not a panel. The tutorial can also raise it as a demo.
	pause_overlay.visible = mode == GameManager.Mode.PAUSED or _pause_demo
	if mode == GameManager.Mode.PAUSED:
		result_panel.hide()
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

	# On the very first clear the only way onward is the next level. Offering a route
	# to the level list before Joe has explained what it's for teaches nothing, and he
	# is about to explain it.
	var first_clear: bool = SaveManager.needs_first_clear_outro(level_id, bank_delta) \
		and not get_tree().get_nodes_in_group("tutorial").is_empty()
	if first_clear:
		# Withheld here rather than by the tutorial, because this handler runs first —
		# letting it show would flash the panel for a frame before Joe hid it again.
		hold_result_panel()
	_show_panel(
		tr("RESULT_COMPLETED"), "\n".join(lines),
		not first_clear, GameManager.level_exists(level_id + 1), not first_clear
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
	_show_panel(tr("RESULT_TIME_UP"), tr("RESULT_TIME_UP_DETAIL"), true, false)


func _show_panel(title: String, detail: String, show_edit: bool, show_next: bool,
		show_select: bool = true) -> void:
	result_title.text = title
	result_detail.text = detail
	result_detail.visible = not detail.is_empty()
	edit_button.visible = show_edit
	next_button.visible = show_next
	select_button.visible = show_select
	# Only a completed level has a board worth showing; _on_goal_reached reveals it.
	leaderboard.hide()
	if not _result_held:
		result_panel.show()


func _on_next_pressed() -> void:
	GameManager.load_level(GameManager.current_level_id + 1)


static func format_seconds(seconds: float) -> String:
	return "%.2fs" % seconds
