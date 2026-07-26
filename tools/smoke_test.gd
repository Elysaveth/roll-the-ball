extends Node
# Headless smoke test for the run loop: layout snapshot/restore, the time bank
# arithmetic, and the freeze on time-up.
#
#   godot --headless --path . res://tools/smoke_test.tscn
#
# Exits with the number of failed checks, so it doubles as a CI gate.
#
# It backs up and restores user://profile.json and user://saves/ around the run,
# because it deliberately writes junk into both, and forces LeaderboardApi offline
# so it can never publish to the live leaderboards.
#
# A SCRIPT ERROR anywhere in the output means coverage was lost even if the summary
# says everything passed — _phase() catches a section that produced no checks at
# all, but not one that aborted halfway. Grep for it.

const PROP_SCENE: String = "res://entities/props/hielo/hielo.tscn"

var _failures: int = 0
var _checks_run: int = 0
var _backup: Dictionary = {}
var _main: Node = null


func _ready() -> void:
	_backup_user_data()
	await _run()
	_restore_user_data()

	print("")
	if _failures == 0:
		print("ALL CHECKS PASSED")
	else:
		print("%d CHECK(S) FAILED" % _failures)
	get_tree().quit(_failures)


func _run() -> void:
	# Before anything else: this suite drives goal_reached repeatedly, and
	# LeaderboardApi publishes on that. Without this, a test run would spray junk
	# times onto the live boards.
	LeaderboardApi.offline = true
	_reset_profile()

	# Wait a frame before touching root: during our own _ready the tree is still
	# adding children and add_child() on it is refused.
	await get_tree().process_frame
	_main = load(GameManager.MAIN_SCENE).instantiate()
	get_tree().root.add_child(_main)
	await get_tree().process_frame

	await _phase("input actions", _test_input_actions_exist)
	await _phase("HUD is wired", _test_hud_is_wired)
	await _phase("level loads", _test_level_loads)
	await _phase("snapshot restores layout", _test_snapshot_restores_layout)
	await _phase("bank charges and refunds", _test_bank_charges_and_refunds)
	await _phase("time up freezes", _test_time_up_freezes)
	await _phase("level 01 is a puzzle", _test_level_01_is_a_puzzle)
	await _phase("bomb explodes", _test_bomb_explodes)
	await _phase("goal through physics", _test_goal_through_physics)
	await _phase("transforms round trip", _test_transforms_round_trip)
	await _phase("scale clamping", _test_scale_clamping)
	await _phase("player name", _test_player_name)
	await _phase("translations", _test_translations)
	await _phase("exclusive placement", _test_exclusive_placement)
	await _phase("cursor resolution", _test_cursor_resolution)
	await _phase("leaderboard encoding", _test_leaderboard_encoding)
	await _phase("remappable actions", _test_remappable_actions)
	await _phase("theme and backgrounds", _test_theme_and_backgrounds)


## Runs one section and guards against silent coverage loss.
##
## A GDScript runtime error — a typo'd method, a null deref — aborts only the
## function it happens in and hands control back here. The section then contributes
## no checks, so without this the suite would happily print ALL CHECKS PASSED while
## having skipped a whole area. Any SCRIPT ERROR in the output means the same thing;
## treat one as a failure even when the summary looks clean.
func _phase(label: String, section: Callable) -> void:
	var before: int = _checks_run
	await section.call()
	if _checks_run == before:
		_failures += 1
		print("  FAIL  section '%s' ran no checks — it aborted early (look for SCRIPT ERROR above)" % label)


# ----------------------------------------------------------------- tests ----

## Every action the code calls by name has to exist in the InputMap, or the
## feature is simply dead at runtime — a missing binding is not a crash, and
## headless runs never press a key, so nothing else here would notice.
func _test_input_actions_exist() -> void:
	print("\n[input actions]")
	for action in ["toggle_play", "toggle_pause", "rotate_prop", "scale_prop",
			"camera_up", "camera_down", "camera_left", "camera_right"]:
		var exists: bool = InputMap.has_action(action)
		var bound: bool = exists and not InputMap.action_get_events(action).is_empty()
		check(exists, "action '%s' is defined" % action)
		check(bound, "action '%s' has a default binding" % action)


## A parse error in HUDController silently detaches the script — the scene still
## loads, the game still runs, and nothing in the world tests notices. So check
## the HUD is really live, and that its @onready paths resolved against hud.tscn.
func _test_hud_is_wired() -> void:
	print("\n[HUD is wired]")
	var hud: Node = _main.get_node_or_null("UI/HUD")
	check(hud != null, "main.tscn has UI/HUD")
	check(hud is HUDController, "HUDController is attached (a parse error would drop it)")
	if not hud is HUDController:
		return

	var controller: HUDController = hud
	check(controller.play_button != null, "PlayButton resolved")
	check(controller.time_label != null, "TimeLabel resolved")
	check(controller.palette_items != null, "PaletteItems resolved")
	check(controller.prop_menu != null, "PropMenu resolved")
	check(controller.result_panel != null, "ResultPanel resolved")
	check(controller.leaderboard != null, "the embedded leaderboard panel resolved")
	# Typed loosely to dodge the class cache, so confirm its script is really on.
	check(
		controller.leaderboard != null and controller.leaderboard.has_method("show_board"),
		"the leaderboard panel's script is attached"
	)


func _test_level_loads() -> void:
	print("\n[level loads]")
	check(GameManager.current_level_id == 1, "level 1 is current")
	check(GameManager.is_edit_mode(), "starts in EDIT")

	var level: Level = GameManager.get_current_level()
	check(level != null, "a Level is in the tree")
	if level == null:
		return
	check(level.get_ball() != null, "the ball was spawned")
	check(level.get_ball().freeze, "the ball is frozen in EDIT")


func _test_snapshot_restores_layout() -> void:
	print("\n[snapshot restores layout]")
	var container: Node = GameManager.get_placed_objects_container()
	if container == null:
		check(false, "PlacedObjects container exists")
		return

	var placed_at: Vector2 = Vector2(700, 600)
	var prop: PlaceableObject = load(PROP_SCENE).instantiate()
	container.add_child(prop)
	prop.global_position = placed_at
	await get_tree().physics_frame

	GameManager.start_attempt()
	check(GameManager.is_play_mode(), "PLAY started")
	check(SaveManager.has_layout(1), "layout was written to disk on PLAY")

	# Stand in for physics flinging the prop across the level.
	var live: PlaceableObject = _first_prop(container)
	if live != null:
		live.global_position = Vector2(-4000, 9000)

	GameManager.return_to_edit()
	await get_tree().process_frame

	var restored: PlaceableObject = _first_prop(container)
	check(restored != null, "the prop survived the round trip")
	if restored != null:
		check(
			restored.global_position.distance_to(placed_at) < 1.0,
			"the prop is back where it was left (got %s, wanted %s)" % [restored.global_position, placed_at]
		)


func _test_bank_charges_and_refunds() -> void:
	print("\n[bank charges and refunds]")
	check(is_equal_approx(SaveManager.get_time_bank(), 60.0), "bank starts at 60s")

	_finish_attempt_in(5.0)
	check(is_equal_approx(SaveManager.get_time_bank(), 55.0), "first clear at 5s spends 5s (bank 55)")
	check(is_equal_approx(SaveManager.get_best_time(1), 5.0), "best time recorded as 5s")
	check(GameManager.current_mode == GameManager.Mode.COMPLETED, "mode is COMPLETED")

	GameManager.return_to_edit()
	_finish_attempt_in(3.0)
	check(is_equal_approx(SaveManager.get_time_bank(), 57.0), "improving to 3s refunds 2s (bank 57)")
	check(is_equal_approx(SaveManager.get_best_time(1), 3.0), "best time improved to 3s")

	GameManager.return_to_edit()
	_finish_attempt_in(9.0)
	check(is_equal_approx(SaveManager.get_time_bank(), 57.0), "a slower clear costs nothing (bank still 57)")
	check(is_equal_approx(SaveManager.get_best_time(1), 3.0), "best time unchanged at 3s")

	GameManager.return_to_edit()


func _test_time_up_freezes() -> void:
	print("\n[time up freezes]")
	SaveManager._set_time_bank(0.5)
	GameManager.start_attempt()
	check(GameManager.is_play_mode(), "attempt started with 0.5s in the bank")

	# 0.5s of fixed 60Hz steps, plus a margin.
	for i in range(40):
		await get_tree().physics_frame
		if GameManager.current_mode == GameManager.Mode.TIME_UP:
			break

	check(GameManager.current_mode == GameManager.Mode.TIME_UP, "hitting zero switches to TIME_UP")
	check(GameManager.get_time_remaining() <= 0.0, "the clock never renders negative")

	# PhysicsServer2D has no is_active() getter, so prove the freeze the way the
	# player experiences it: a mid-air ball must not travel while observing.
	var ball: Ball = GameManager.get_current_level().get_ball()
	var frozen_at: Vector2 = ball.global_position
	for i in range(15):
		await get_tree().physics_frame
	check(
		ball.global_position.distance_to(frozen_at) < 0.01,
		"the ball does not move while frozen (drifted %.3fpx)" % ball.global_position.distance_to(frozen_at)
	)

	GameManager.return_to_edit()
	# An abandoned attempt must not have cost anything.
	check(is_equal_approx(SaveManager.get_time_bank(), 0.5), "running out of time charged nothing")

	# ...and the simulation has to come back to life for the next attempt.
	SaveManager._set_time_bank(10.0)
	GameManager.start_attempt()
	var restarted: Ball = GameManager.get_current_level().get_ball()
	var started_at: Vector2 = restarted.global_position
	for i in range(20):
		await get_tree().physics_frame
	check(
		restarted.global_position.distance_to(started_at) > 1.0,
		"physics runs again on the next attempt (moved %.1fpx)" % restarted.global_position.distance_to(started_at)
	)
	GameManager.return_to_edit()


## Guards the level design itself, not the code: with nothing placed, the ball
## has to leave the starting ledge under its own weight and fall short of the
## basket. If it sits still the ramp is too flat; if it arrives on its own the
## level is not a puzzle. Both are easy to cause by nudging the geometry.
func _test_level_01_is_a_puzzle() -> void:
	print("\n[level 01 is a puzzle]")
	LevelLayout.clear(GameManager.get_placed_objects_container())
	SaveManager._set_time_bank(60.0)

	GameManager.start_attempt()
	var ball: Ball = GameManager.get_current_level().get_ball()
	var start: Vector2 = ball.global_position

	for i in range(180): # 3 seconds at 60Hz
		await get_tree().physics_frame

	var travelled: float = ball.global_position.x - start.x
	check(travelled > 150.0, "the ball rolls right off the tilted ledge (moved %.0fpx)" % travelled)
	check(ball.global_position.y > 700.0, "the ball drops into the gap (y = %.0f)" % ball.global_position.y)
	check(
		GameManager.current_mode != GameManager.Mode.COMPLETED,
		"the ball cannot reach the goal unaided — there is a puzzle to solve"
	)
	GameManager.return_to_edit()


## Exercises the blast path end to end: the shape query finds loose bodies, the
## impulse is applied away from the epicentre, the effect outlives the bomb, and
## the bomb takes itself off the canvas.
func _test_bomb_explodes() -> void:
	print("\n[bomb explodes]")
	var container: Node = GameManager.get_placed_objects_container()
	LevelLayout.clear(container)
	SaveManager._set_time_bank(60.0)

	var bomb: Bomb = load("res://entities/props/bomb/bomb.tscn").instantiate()
	container.add_child(bomb)

	GameManager.start_attempt()
	await get_tree().physics_frame

	var ball: Ball = GameManager.get_current_level().get_ball()
	# Sit the bomb just below the ball so the blast should throw it upward.
	bomb.global_position = ball.global_position + Vector2(0, 60)
	await get_tree().physics_frame

	var before: Vector2 = ball.linear_velocity
	bomb.explode()
	await get_tree().physics_frame

	check(
		ball.linear_velocity.y < before.y - 100.0,
		"the blast throws the ball upward (vy %.0f -> %.0f)" % [before.y, ball.linear_velocity.y]
	)
	check(_first_prop(container) == null, "the bomb removes itself from the canvas")

	var effect_found: bool = false
	for child in container.get_children():
		if child is Explosion:
			effect_found = true
			break
	check(effect_found, "the explosion effect outlives the bomb that spawned it")

	GameManager.return_to_edit()


## Scores by actually rolling the ball into the Goal, rather than calling
## notify_goal_reached() by hand like the bank tests do.
##
## This is the path that used to spam "Can't change this state while flushing
## queries": Goal.body_entered fires with the physics space locked, and switching
## mode makes every body write `freeze`. Watch the run's stderr for that string —
## reaching COMPLETED here is only half the check.
func _test_goal_through_physics() -> void:
	print("\n[goal reached through physics]")
	LevelLayout.clear(GameManager.get_placed_objects_container())
	SaveManager._set_time_bank(60.0)

	var level: Level = GameManager.get_current_level()
	var goal: Node2D = level.get_node_or_null("Goal")
	if goal == null:
		check(false, "level 01 has a Goal node")
		return

	# Cheat by moving the spawn marker rather than teleporting the ball. Level
	# .reset_level() positions the ball while it is still frozen, which is the
	# only reliable moment to place a RigidBody2D — once it's live the physics
	# server owns its transform and overwrites any direct assignment.
	var original_spawn: Vector2 = level.ball_spawn.position
	level.ball_spawn.global_position = goal.global_position + Vector2(0, -140)

	GameManager.start_attempt()
	await get_tree().physics_frame
	var ball: Ball = level.get_ball()

	for i in range(240):
		await get_tree().physics_frame
		if GameManager.current_mode == GameManager.Mode.COMPLETED:
			break

	var area: Area2D = goal
	check(
		GameManager.current_mode == GameManager.Mode.COMPLETED,
		"a real Goal overlap scores (ball %s, goal %s, monitoring=%s, overlaps=%d)" % [
			ball.global_position, goal.global_position, area.monitoring,
			area.get_overlapping_bodies().size()
		]
	)
	level.ball_spawn.position = original_spawn
	GameManager.return_to_edit()
	check(GameManager.is_edit_mode(), "and the level goes back to EDIT afterwards")


## Rotation and scale are part of the arrangement, so they have to survive the
## snapshot round trip exactly like position does.
func _test_transforms_round_trip() -> void:
	print("\n[rotation and scale round trip]")
	var container: Node = GameManager.get_placed_objects_container()
	LevelLayout.clear(container)

	var prop: PlaceableObject = load(PROP_SCENE).instantiate()
	container.add_child(prop)
	prop.global_position = Vector2(700, 600)
	prop.rotation = 0.7
	prop.set_uniform_scale(1.25)
	var wanted_rotation: float = prop.rotation
	var wanted_scale: float = prop.scale.x

	GameManager.start_attempt()
	# Scramble the live prop the way an explosion would.
	var live: PlaceableObject = _first_prop(container)
	live.rotation = -2.5
	live.scale = Vector2(0.9, 0.9)

	GameManager.return_to_edit()
	await get_tree().process_frame

	var restored: PlaceableObject = _first_prop(container)
	check(restored != null, "the prop survived the round trip")
	if restored == null:
		return
	check(
		is_equal_approx(restored.rotation, wanted_rotation),
		"rotation restored (%.3f, wanted %.3f)" % [restored.rotation, wanted_rotation]
	)
	check(
		is_equal_approx(restored.scale.x, wanted_scale),
		"scale restored (%.3f, wanted %.3f)" % [restored.scale.x, wanted_scale]
	)


func _test_scale_clamping() -> void:
	print("\n[scale clamping]")
	var container: Node = GameManager.get_placed_objects_container()
	LevelLayout.clear(container)

	var prop: PlaceableObject = load(PROP_SCENE).instantiate()
	container.add_child(prop)

	prop.set_uniform_scale(99.0)
	check(prop.scale.x <= PlaceableObject.MAX_SCALE + 0.001, "resizing stops at MAX_SCALE (%.2f)" % prop.scale.x)
	check(not prop.can_grow(), "can_grow() reports the ceiling")
	check(is_equal_approx(prop.scale.x, prop.scale.y), "scale stays uniform")

	prop.set_uniform_scale(0.001)
	check(prop.scale.x >= PlaceableObject.MIN_SCALE - 0.001, "resizing stops at MIN_SCALE (%.2f)" % prop.scale.x)
	check(not prop.can_shrink(), "can_shrink() reports the floor")

	LevelLayout.clear(container)


func _test_player_name() -> void:
	print("\n[player name]")
	check(not SaveManager.has_player_name(), "a fresh profile has no name yet")
	SaveManager.set_player_name("   Lizzy   ")
	check(SaveManager.get_player_name() == "Lizzy", "the name is trimmed on the way in")
	check(SaveManager.has_player_name(), "has_player_name() flips once set")

	SaveManager.load_profile()
	check(SaveManager.get_player_name() == "Lizzy", "the name survives a profile reload")


## Guards the localisation wiring. A missing translation resource doesn't crash —
## tr() just hands the key straight back — so the UI silently renders
## "MENU_PLAY" instead of "Play" and only a human notices.
func _test_translations() -> void:
	print("\n[translations]")
	var locales: PackedStringArray = TranslationServer.get_loaded_locales()
	check("en" in locales, "English is loaded (locales: %s)" % str(locales))
	check("es" in locales, "Spanish is loaded")

	var probes: Array[String] = ["MENU_PLAY", "HUD_EDIT", "RESULT_COMPLETED", "PROP_RESIZE", "LB_EMPTY"]
	TranslationServer.set_locale("en")
	for key in probes:
		check(tr(key) != key, "'%s' resolves in English -> '%s'" % [key, tr(key)])
	TranslationServer.set_locale("es")
	check(tr("MENU_PLAY") == "Jugar", "Spanish translation applies (MENU_PLAY -> '%s')" % tr("MENU_PLAY"))

	# English is the default, so leave it that way for anything downstream.
	TranslationServer.set_locale("en")
	check(Settings.LOCALES[0] == "en", "English is the first/default locale option")


## Exclusive props must refuse to sit on top of each other, and the refusal has to
## survive the drop — not just tint the cursor.
func _test_exclusive_placement() -> void:
	print("\n[exclusive placement]")
	var container: Node = GameManager.get_placed_objects_container()
	LevelLayout.clear(container)

	var bomb_scene: PackedScene = load("res://entities/props/bomb/bomb.tscn")
	var first: PlaceableObject = bomb_scene.instantiate()
	container.add_child(first)
	first.global_position = Vector2(700, 500)

	var second: PlaceableObject = bomb_scene.instantiate()
	container.add_child(second)
	second.global_position = Vector2(700, 500) # right on top of the first
	check(second.exclusive_placement, "bombs are exclusive by default")

	# The probe's overlap list is populated by the physics server, so it needs a tick.
	await get_tree().physics_frame
	await get_tree().physics_frame
	check(not second.placement_is_valid(), "stacked bombs report an invalid placement")

	second.global_position = Vector2(1300, 500)
	await get_tree().physics_frame
	await get_tree().physics_frame
	check(second.placement_is_valid(), "moving clear of the other bomb makes it valid again")

	# Ice planks are meant to be layered, so they must NOT block each other.
	LevelLayout.clear(container)
	var plank_a: PlaceableObject = load(PROP_SCENE).instantiate()
	var plank_b: PlaceableObject = load(PROP_SCENE).instantiate()
	container.add_child(plank_a)
	container.add_child(plank_b)
	plank_a.global_position = Vector2(700, 500)
	plank_b.global_position = Vector2(700, 500)
	await get_tree().physics_frame
	await get_tree().physics_frame
	check(not plank_a.exclusive_placement, "ice planks opt out of exclusivity")
	check(plank_b.placement_is_valid(), "overlapping planks are allowed")

	LevelLayout.clear(container)


## The cursor is derived from interaction state, so it can be checked without a
## real mouse: drive the state and read the resolved shape.
##
## Note the dragged prop follows the cursor, and headless reports the cursor at the
## viewport origin — so positions are taken FROM the prop rather than assigned to
## it, and the blocker is moved to meet it.
func _test_cursor_resolution() -> void:
	print("
[cursor resolution]")
	var container: Node = GameManager.get_placed_objects_container()
	LevelLayout.clear(container)
	await get_tree().physics_frame
	await get_tree().physics_frame

	check(
		CursorManager._resolve() == CursorManager.SHAPE_DEFAULT,
		"idle in EDIT resolves to the default arrow"
	)

	var bomb_scene: PackedScene = load("res://entities/props/bomb/bomb.tscn")
	var moving: PlaceableObject = bomb_scene.instantiate()
	container.add_child(moving)
	moving.begin_drag_from_palette()
	await get_tree().physics_frame
	await get_tree().physics_frame
	check(PlaceableObject.get_dragging() == moving, "the drag survived construction")
	check(CursorManager._resolve() == CursorManager.SHAPE_DROP_OK, "dragging over free space shows can-drop")

	# Put a second exclusive prop exactly where the dragged one now sits.
	var blocker: PlaceableObject = bomb_scene.instantiate()
	container.add_child(blocker)
	blocker.global_position = moving.global_position
	await get_tree().physics_frame
	await get_tree().physics_frame
	check(
		CursorManager._resolve() == CursorManager.SHAPE_DROP_BLOCKED,
		"dragging onto another exclusive prop shows forbidden"
	)

	# Dropping there is refused too, not just discouraged: a prop straight from the
	# palette has nowhere to return to, so the placement is cancelled outright.
	moving._drop()
	await get_tree().process_frame
	check(not is_instance_valid(moving), "an illegal drop from the palette cancels the placement")

	# The blocker is sitting under the cursor, which is what grabbable means.
	check(CursorManager._resolve() == CursorManager.SHAPE_GRABBABLE, "a prop under the cursor shows grabbable")

	blocker.begin_rotate(true)
	check(CursorManager._resolve() == CursorManager.SHAPE_ROTATING, "rotating shows the rotate shape")
	blocker.cancel_rotate()

	blocker.begin_scale(true)
	check(CursorManager._resolve() == CursorManager.SHAPE_RESIZING, "resizing shows the resize shape")
	blocker.cancel_scale()

	check(
		PlaceableObject.get_rotating() == null
			and PlaceableObject.get_scaling() == null
			and PlaceableObject.get_dragging() == null,
		"all gesture state is cleared after cancelling"
	)
	LevelLayout.clear(container)


## The inversion that works around SilentWolf ranking descending only. If encode
## and decode ever drift apart, every displayed time becomes silently wrong — no
## crash, just nonsense on the board.
func _test_leaderboard_encoding() -> void:
	print("
[leaderboard encoding]")
	check(LeaderboardApi.board_for_level(1) == "Level 1", "level 1 maps to the 'Level 1' board")
	check(LeaderboardApi.board_for_level(12) == "Level 12", "level 12 maps to the 'Level 12' board")
	check(LeaderboardApi.BOARD_GENERAL == "main", "the furthest-level board is SilentWolf's default 'main'")
	check(not LeaderboardApi.is_configured(), "the suite runs offline so it can't publish junk scores")

	var board: String = LeaderboardApi.board_for_level(1)
	for seconds in [0.0, 3.25, 12.5, 59.99]:
		var wire: float = LeaderboardApi._encode(board, seconds)
		var back: float = LeaderboardApi._decode(board, wire)
		check(is_equal_approx(back, seconds), "%.2fs survives encode/decode (wire %.2f)" % [seconds, wire])

	# Faster must store HIGHER, or descending ranking puts the slowest on top.
	check(
		LeaderboardApi._encode(board, 3.0) > LeaderboardApi._encode(board, 9.0),
		"a faster time stores as a higher score"
	)
	# The general board holds level numbers, where higher already means better.
	check(
		is_equal_approx(LeaderboardApi._encode(LeaderboardApi.BOARD_GENERAL, 7.0), 7.0),
		"the general board is stored unmodified"
	)


## The Controls tab builds itself from this list, so an empty one means the tab is
## silently blank.
func _test_remappable_actions() -> void:
	print("
[remappable actions]")
	var actions: Array[String] = Settings.get_remappable_actions()
	check(not actions.is_empty(), "actions were discovered (%d found)" % actions.size())
	for expected in ["toggle_play", "rotate_prop", "scale_prop", "camera_left"]:
		check(expected in actions, "'%s' is listed" % expected)
	var has_builtin: bool = false
	for action in actions:
		if action.begins_with("ui_"):
			has_builtin = true
	check(not has_builtin, "Godot's built-in ui_* actions are excluded")
	# Falls back to a prettified name, so this must never return the raw key.
	var label: String = KeyMapButton.action_display_name("rotate_prop")
	check(label != "ACTION_ROTATE_PROP" and not label.is_empty(), "action names resolve to '%s'" % label)


func _test_theme_and_backgrounds() -> void:
	print("
[theme and backgrounds]")
	var theme_path: String = str(ProjectSettings.get_setting("gui/theme/custom", ""))
	check(theme_path != "", "a project-wide default theme is registered")
	var theme: Theme = load(theme_path) if theme_path != "" else null
	check(theme != null, "the theme resource loads")
	if theme != null:
		check(theme.has_stylebox("normal", "Button"), "Button has a themed normal stylebox")
		check(theme.has_stylebox("panel", "PanelContainer"), "PanelContainer is themed")
		check(theme.has_stylebox("panel", "PopupMenu"), "PopupMenu is themed")
		check(theme.has_color("font_color", "Label"), "Label ink colour is themed")
		var box: StyleBox = theme.get_stylebox("normal", "Button")
		check(box is StyleBoxTexture, "buttons use the torn-paper texture box")
		if box is StyleBoxTexture:
			var textured: StyleBoxTexture = box
			check(textured.texture != null, "the jagged texture is attached")
			# Stretching would smear the teeth into streaks on wide controls.
			check(
				textured.axis_stretch_horizontal == StyleBoxTexture.AXIS_STRETCH_MODE_TILE,
				"the torn edge tiles instead of stretching"
			)

	# The level background lives on a CanvasLayer behind the world.
	var paper: Node = _main.get_node_or_null("Background/Paper")
	check(paper is TextureRect and paper.texture != null, "levels have a paper background")
	var layer: Node = _main.get_node_or_null("Background")
	check(layer is CanvasLayer and layer.layer < 0, "it sits behind the world (layer %s)" % [
		layer.layer if layer is CanvasLayer else "n/a"
	])


# ---------------------------------------------------------------- helpers ----

func _finish_attempt_in(seconds: float) -> void:
	GameManager.start_attempt()
	GameManager.attempt_elapsed = seconds
	GameManager.notify_goal_reached()


func _first_prop(container: Node) -> PlaceableObject:
	for child in container.get_children():
		if child is PlaceableObject:
			return child
	return null


func check(condition: bool, message: String) -> void:
	_checks_run += 1
	if condition:
		print("  ok    %s" % message)
	else:
		_failures += 1
		print("  FAIL  %s" % message)


func _reset_profile() -> void:
	for level_id in SaveManager.list_saved_layouts():
		SaveManager.delete_layout(level_id)
	if FileAccess.file_exists(SaveManager.PROFILE_PATH):
		DirAccess.remove_absolute(SaveManager.PROFILE_PATH)
	SaveManager.load_profile()


func _backup_user_data() -> void:
	_backup.clear()
	for path in _user_files():
		var file: FileAccess = FileAccess.open(path, FileAccess.READ)
		if file != null:
			_backup[path] = file.get_as_text()
			file.close()


func _restore_user_data() -> void:
	for path in _user_files():
		if not _backup.has(path) and FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	for path in _backup:
		var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
		if file != null:
			file.store_string(_backup[path])
			file.close()


func _user_files() -> Array[String]:
	var paths: Array[String] = [SaveManager.PROFILE_PATH]
	var dir: DirAccess = DirAccess.open(SaveManager.SAVE_DIR)
	if dir != null:
		dir.list_dir_begin()
		var file_name: String = dir.get_next()
		while file_name != "":
			if file_name.ends_with(".json"):
				paths.append(SaveManager.SAVE_DIR + file_name)
			file_name = dir.get_next()
		dir.list_dir_end()
	return paths
