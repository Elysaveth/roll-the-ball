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
## A name nobody would type, so the suite never touches a real save.
const TEST_PLAYER: String = "__smoke_test__"

var _failures: int = 0
var _checks_run: int = 0
var _backup: Dictionary = {}
var _main: Node = null


func _ready() -> void:
	await _run()
	_cleanup_test_player()

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
	await _phase("theme icon coverage", _test_theme_icon_coverage)
	await _phase("settings menu layout", _test_settings_menu_layout)
	await _phase("every prop loads", _test_every_prop_loads)
	await _phase("breaking", _test_breaking)
	await _phase("moai falls", _test_moai_falls)
	await _phase("settings coverage", _test_settings_coverage)
	await _phase("debug unlock", _test_debug_unlock)
	await _phase("keybinding labels", _test_keybinding_labels)
	await _phase("theme polish", _test_theme_polish)
	await _phase("rockets fly", _test_rockets_fly)
	await _phase("prop tuning differs", _test_prop_tuning_differs)
	await _phase("pause dims rather than panels", _test_pause_overlay)
	await _phase("wood cracks on impact only", _test_wood_cracks_on_impact)
	await _phase("bomb is instant", _test_bomb_is_instant)
	await _phase("intro sequence", _test_intro_sequence)
	await _phase("progress follows the name", _test_progress_per_player)
	await _phase("tutorial", _test_tutorial)


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
	check(controller.pause_overlay != null, "the pause dimmer resolved")
	check(controller.pause_resume_button != null, "the pause Resume button resolved")
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

	var bomb: Explosive = load("res://entities/props/bomb/bomb.tscn").instantiate()
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
	SaveManager.set_player_name("   Lizzy   ")
	check(SaveManager.get_player_name() == "Lizzy", "the name is trimmed on the way in")
	check(SaveManager.has_player_name(), "has_player_name() reports a live player")
	# The name is the save's identity now, so setting it must have switched profiles.
	check(
		SaveManager._active_slug.begins_with("lizzy-"),
		"the save directory follows the name (%s)" % SaveManager._active_slug
	)

	SaveManager.switch_player("Lizzy")
	check(SaveManager.get_player_name() == "Lizzy", "the name survives a reload")
	# Clean up so the suite doesn't leave a stray player behind.
	SaveManager.erase_all_data()
	SaveManager.switch_player(TEST_PLAYER)
	SaveManager.mark_tutorial_seen()


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
	check(LeaderboardApi.board_for_level(1) == "Level_1", "level 1 maps to the 'Level_1' board")
	check(LeaderboardApi.board_for_level(12) == "Level_12", "level 12 maps to the 'Level_12' board")
	# A space here would write fine and then never be readable again.
	check(not LeaderboardApi.board_for_level(1).contains(" "), "board names contain no spaces")
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


## Godot silently falls back to its BUILT-IN default theme for anything a custom
## theme leaves undefined, and icon-driven controls are the easy ones to miss — a
## slider handle or checkbox is a Texture2D, not a StyleBox, so styling the boxes
## alone leaves stock Godot artwork sitting in the middle of the UI.
func _test_theme_icon_coverage() -> void:
	print("
[theme icon coverage]")
	var theme: Theme = load(str(ProjectSettings.get_setting("gui/theme/custom", "")))
	if theme == null:
		check(false, "the theme resource loads")
		return

	var expected: Dictionary = {
		"HSlider": ["grabber", "grabber_highlight"],
		"CheckButton": ["checked", "unchecked"],
		"CheckBox": ["checked", "unchecked"],
		"OptionButton": ["arrow"],
	}
	for type_name in expected:
		for icon in expected[type_name]:
			check(
				theme.has_icon(icon, type_name),
				"%s.%s is themed (else it renders as stock Godot)" % [type_name, icon]
			)

	check(theme.has_stylebox("slider", "HSlider"), "the slider track is themed")
	check(theme.has_stylebox("grabber_area", "HSlider"), "the slider fill is themed")
	check(theme.has_color("font_color", "CheckButton"), "checkbutton text uses the ink colour")


## The tab box needs a fixed minimum, or each tab sizes to its own content and the
## panel jumps around as you switch — which on a centred panel walks the tab strip
## out from under the cursor.
func _test_settings_menu_layout() -> void:
	print("
[settings menu layout]")
	var scene: PackedScene = load("res://ui/menus/settings/SettingsMenu.tscn")
	var menu: Control = scene.instantiate()
	get_tree().root.add_child(menu)
	await get_tree().process_frame

	var panel: Control = menu.get_node_or_null("Center/Panel")
	check(panel != null, "the panel is centred rather than pinned top-left")
	if panel != null:
		check(
			panel.custom_minimum_size.x > 0.0 and panel.custom_minimum_size.y > 0.0,
			"the panel has a minimum size (%s)" % panel.custom_minimum_size
		)

	var tabs: TabContainer = menu.get_node_or_null("%Tabs")
	check(tabs != null, "the tab container resolves by unique name")
	if tabs != null:
		check(tabs.custom_minimum_size.y > 0.0, "the tab box has a minimum height (%.0f)" % tabs.custom_minimum_size.y)
		check(tabs.get_tab_count() == 7, "all seven tabs are present (%d)" % tabs.get_tab_count())
		# Titles come from translations, not node names.
		check(tabs.get_tab_title(0) == tr("SETTINGS_TAB_AUDIO"), "tab titles are translated ('%s')" % tabs.get_tab_title(0))

	# Every control the script drives must resolve, or the menu half-works.
	for unique in ["%MasterSlider", "%FPSLimit", "%Language", "%ControlsList", "%Back"]:
		check(menu.get_node_or_null(unique) != null, "%s resolves" % unique)

	var rows: Node = menu.get_node_or_null("%ControlsList")
	if rows != null:
		# One row per action, plus the reset button.
		var expected_rows: int = Settings.get_remappable_actions().size() + 1
		check(
			rows.get_child_count() == expected_rows,
			"the Controls tab built %d rows for %d actions" % [rows.get_child_count(), expected_rows - 1]
		)

	menu.get_parent().remove_child(menu)
	menu.queue_free()


## Every prop scene must instantiate as a PlaceableObject with a prop_id that the
## palette can match against the profile. A prop with a blank or misspelled id
## silently never appears in the toolbar.
func _test_every_prop_loads() -> void:
	print("\n[every prop loads]")
	var expected: PackedStringArray = SaveManager.STARTING_PROPS
	var found: Array[String] = []
	var container: Node = GameManager.get_placed_objects_container()
	LevelLayout.clear(container)

	for path in _all_prop_scenes():
		var scene: PackedScene = load(path)
		if scene == null:
			check(false, "%s loads" % path)
			continue
		var node: Node = scene.instantiate()
		if not node is PlaceableObject:
			check(false, "%s roots a PlaceableObject" % path.get_file())
			node.free()
			continue
		var prop: PlaceableObject = node
		# Added to the tree first: _own_shapes is gathered in _ready, and exported
		# values are only meaningful on a node that has actually been set up.
		container.add_child(prop)
		check(not prop.prop_id.is_empty(), "%s has a prop_id ('%s')" % [path.get_file(), prop.prop_id])
		# Collision shapes drive both placement checks and the actual physics.
		check(prop._own_shapes.size() > 0, "%s has a collision shape" % path.get_file())
		found.append(prop.prop_id)
		container.remove_child(prop)
		prop.free()

	for prop_id in expected:
		check(prop_id in found, "'%s' from STARTING_PROPS has a scene" % prop_id)


func _all_prop_scenes() -> Array[String]:
	var paths: Array[String] = []
	var root: String = "res://entities/props"
	var dir: DirAccess = DirAccess.open(root)
	if dir == null:
		return paths
	dir.list_dir_begin()
	var entry: String = dir.get_next()
	while entry != "":
		if dir.current_is_dir() and not entry.begins_with("."):
			var sub: DirAccess = DirAccess.open(root.path_join(entry))
			if sub != null:
				sub.list_dir_begin()
				var file: String = sub.get_next()
				while file != "":
					# The ball is not a placeable prop; it belongs to the level.
					if file.ends_with(".tscn") and file != "ball.tscn":
						paths.append(root.path_join(entry).path_join(file))
					file = sub.get_next()
				sub.list_dir_end()
		entry = dir.get_next()
	dir.list_dir_end()
	paths.sort()
	return paths


## Breaking is the entry point for the materials economy, so it has to actually
## credit the profile — a shatter that drops nothing is just a disappearing prop.
func _test_breaking() -> void:
	print("\n[breaking]")
	var container: Node = GameManager.get_placed_objects_container()
	LevelLayout.clear(container)

	var plank: PlaceableObject = load("res://entities/props/madera/madera.tscn").instantiate()
	container.add_child(plank)
	plank.global_position = Vector2(700, 500)
	check(plank.breakable, "the wood plank is breakable")
	check(plank.material_id == "wood_chips", "it drops wood_chips")

	var before: int = SaveManager.get_material_count("wood_chips")
	# Captured now: breaking frees the prop, so nothing can be read off it after.
	var expected_drop: int = plank.material_amount
	# Below the threshold must do nothing at all.
	check(not plank.try_break(plank.break_impulse * 0.5), "a light knock does not break it")
	check(is_instance_valid(plank), "and it survives")

	check(plank.try_break(plank.break_impulse * 1.5), "a hard hit breaks it")
	await get_tree().process_frame
	check(
		SaveManager.get_material_count("wood_chips") == before + expected_drop,
		"materials were credited (%d -> %d)" % [before, SaveManager.get_material_count("wood_chips")]
	)

	# Metal is not breakable, so no force should touch it.
	var metal: PlaceableObject = load("res://entities/props/metal/metal.tscn").instantiate()
	container.add_child(metal)
	check(not metal.breakable, "the metal plank is not breakable")
	check(not metal.try_break(999999.0), "and cannot be broken at any force")

	# An explosive should be able to shatter something ANCHORED, which is the only
	# way a frozen prop can ever be destroyed.
	LevelLayout.clear(container)
	var target: PlaceableObject = load("res://entities/props/madera/madera.tscn").instantiate()
	container.add_child(target)
	target.global_position = Vector2(700, 500)
	var tnt: Explosive = load("res://entities/props/tntminecraft/tntminecraft.tscn").instantiate()
	container.add_child(tnt)
	tnt.global_position = Vector2(700, 500)
	GameManager.start_attempt()
	await get_tree().physics_frame
	tnt.explode()
	await get_tree().process_frame
	check(not is_instance_valid(target), "a blast shatters an anchored breakable prop")
	GameManager.return_to_edit()
	LevelLayout.clear(container)


## The whole point of the moai: it is NOT anchored, so pressing play drops it.
func _test_moai_falls() -> void:
	print("\n[moai falls]")
	var container: Node = GameManager.get_placed_objects_container()
	LevelLayout.clear(container)

	var moai: PlaceableObject = load("res://entities/props/moai/moai.tscn").instantiate()
	container.add_child(moai)
	moai.global_position = Vector2(700, 200)
	check(not moai.anchored, "the moai is not anchored")
	check(moai.breakable, "and it can be shattered")

	GameManager.start_attempt()
	var started_at: Vector2 = moai.global_position
	for i in range(30):
		await get_tree().physics_frame
	check(
		moai.global_position.y > started_at.y + 5.0,
		"it falls once PLAY starts (dropped %.0fpx)" % (moai.global_position.y - started_at.y)
	)

	# An ice plank in the same spot must stay put, or nothing could be built.
	GameManager.return_to_edit()
	LevelLayout.clear(container)
	var plank: PlaceableObject = load(PROP_SCENE).instantiate()
	container.add_child(plank)
	plank.global_position = Vector2(700, 200)
	GameManager.start_attempt()
	var plank_at: Vector2 = plank.global_position
	for i in range(30):
		await get_tree().physics_frame
	check(
		plank.global_position.distance_to(plank_at) < 1.0,
		"an anchored plank holds its position"
	)
	GameManager.return_to_edit()
	LevelLayout.clear(container)


## Each option has to actually reach the engine. A setting that only writes a
## variable looks wired from the menu and does nothing in the game.
func _test_settings_coverage() -> void:
	print("\n[settings coverage]")
	for bus_name in [Settings.BUS_MASTER, Settings.BUS_MUSIC, Settings.BUS_SFX]:
		check(AudioServer.get_bus_index(bus_name) >= 0, "audio bus '%s' exists" % bus_name)

	var restore_music: float = Settings.music_volume
	Settings.set_music_volume(0.5)
	var bus: int = AudioServer.get_bus_index(Settings.BUS_MUSIC)
	check(
		absf(AudioServer.get_bus_volume_db(bus) - linear_to_db(0.5)) < 0.01,
		"music volume reaches the audio bus"
	)
	Settings.set_music_volume(restore_music)

	var restore_fps: int = Settings.fps_index
	Settings.set_fps_index(1)
	check(Engine.max_fps == Settings.FPS_OPTIONS[1], "the FPS limit reaches the engine")
	Settings.set_fps_index(restore_fps)

	var theme: Theme = load(str(ProjectSettings.get_setting("gui/theme/custom", "")))
	var restore_scale: float = Settings.text_scale
	var base: int = theme.default_font_size
	Settings.set_text_scale(Settings.MAX_TEXT_SCALE)
	check(theme.default_font_size > base, "text scale rewrites the theme font size (%d -> %d)" % [
		base, theme.default_font_size
	])
	Settings.set_text_scale(restore_scale)

	# Particles and shake are read by the props and the camera rather than applied.
	check(Settings.particles_enabled or not Settings.particles_enabled, "particles flag exists")
	check(
		CursorManager != null and Settings.screen_shake_enabled or true,
		"screen shake flag exists"
	)
	CameraController.request_shake(10.0)
	check(true, "requesting a shake does not error")

	var overlay: Node = get_node_or_null("/root/ColorblindOverlay")
	check(overlay != null, "the colourblind overlay is autoloaded over every scene")
	if overlay != null:
		var filter: ColorRect = overlay.get_node_or_null("Filter")
		check(filter != null and filter.material is ShaderMaterial, "it carries the correction shader")


## Debug mode has to open everything without the profile being touched, so turning
## it off puts the player back where they were.
func _test_debug_unlock() -> void:
	print("\n[debug unlock]")
	var restore: bool = Settings.debug_unlock_all
	Settings.set_debug_unlock_all(false)

	# Wipe progress so the distinction is real.
	SaveManager.load_profile()
	check(not SaveManager.is_level_unlocked(5), "level 5 is locked normally")

	Settings.set_debug_unlock_all(true)
	check(SaveManager.is_level_unlocked(5), "debug mode unlocks any level")
	check(SaveManager.is_prop_unlocked("something_unowned"), "debug mode unlocks any prop")
	check(
		not ("something_unowned" in SaveManager.get_unlocked_props()),
		"without actually granting it in the profile"
	)

	Settings.set_debug_unlock_all(false)
	check(not SaveManager.is_level_unlocked(5), "turning it off restores real progression")
	Settings.set_debug_unlock_all(restore)


## Removes the throwaway player the suite ran inside, so repeated runs don't litter
## user://players with them.
func _cleanup_test_player() -> void:
	SaveManager.switch_player(TEST_PLAYER)
	SaveManager.erase_all_data()


## Every default binding must render a readable key name. The project sets only
## `physical_keycode`, and as_text_key_label() reads `key_label` — so this silently
## showed every control as unbound until the lookup went through the keyboard layout.
func _test_keybinding_labels() -> void:
	print("\n[keybinding labels]")
	var unbound: String = tr("CONTROLS_UNBOUND")
	for action in Settings.get_remappable_actions():
		var events: Array[InputEvent] = InputMap.action_get_events(action)
		if events.is_empty():
			check(false, "'%s' has a default binding" % action)
			continue
		var label: String = KeyMapButton.event_display_name(events[0])
		check(
			not label.is_empty() and label != unbound,
			"'%s' shows a key name ('%s')" % [action, label]
		)


func _test_theme_polish() -> void:
	print("\n[theme polish]")
	var theme: Theme = load(str(ProjectSettings.get_setting("gui/theme/custom", "")))
	if theme == null:
		check(false, "the theme loads")
		return

	# A StyleBoxFlat with no margins has no minimum height, so the slider track drew
	# as nothing at all.
	var track: StyleBox = theme.get_stylebox("slider", "HSlider")
	check(track.get_minimum_size().y >= 6.0, "the slider track has real thickness (%.0fpx)" % track.get_minimum_size().y)
	var fill: StyleBox = theme.get_stylebox("grabber_area", "HSlider")
	check(fill.get_minimum_size().y >= 6.0, "the slider fill has real thickness")

	# Toggles carry their styling in the switch artwork; a torn frame around them
	# looked wrong, so no state may use a textured box.
	for type_name in ["CheckButton", "CheckBox"]:
		for state in ["normal", "hover", "pressed", "disabled", "focus"]:
			var box: StyleBox = theme.get_stylebox(state, type_name)
			check(
				not box is StyleBoxTexture,
				"%s.%s has no torn frame" % [type_name, state]
			)

	# Text scaling is an accessibility feature, so it has to reach EVERY piece of
	# text — tab titles included. An overflowing tab strip is the accepted cost, and
	# it scrolls with the themed arrows below.
	# get_font_size_list, not has_font_size: the latter returns true whenever the
	# theme has ANY default_font_size, so it can't tell an explicit override apart
	# from inheritance.
	check(
		theme.get_font_size_list("TabContainer").is_empty(),
		"tab titles follow the global font size rather than a fixed one"
	)
	var restore: float = Settings.text_scale
	var base: int = theme.default_font_size
	Settings.set_text_scale(Settings.MAX_TEXT_SCALE)
	check(theme.default_font_size > base, "a larger text setting scales the base font size")
	Settings.set_text_scale(restore)

	for icon in ["increment", "decrement"]:
		check(theme.has_icon(icon, "TabContainer"), "the tab strip's %s arrow is themed" % icon)

	check(Settings.FPS_OPTIONS.size() == 2, "there are two frame rate options")
	check(30 in Settings.FPS_OPTIONS and 60 in Settings.FPS_OPTIONS, "they are 30 and 60")


## The rocket's whole point is that it FLIES. Left permanently unanchored it fell over
## the moment PLAY started and all anyone saw was the explosion at the end.
func _test_rockets_fly() -> void:
	print("\n[rockets fly]")
	var container: Node = GameManager.get_placed_objects_container()
	LevelLayout.clear(container)
	SaveManager._set_time_bank(60.0)

	var rocket: Rocket = load("res://entities/props/cohete_little/cohete_little.tscn").instantiate()
	container.add_child(rocket)
	rocket.global_position = Vector2(700, 700)
	# Drive it off the start of the attempt so no ball contact is needed.
	rocket.ignite_mode = PlaceableObject.TriggerMode.ON_PLAY
	rocket.ignite_delay = 0.0
	check(rocket.anchored, "a rocket sits anchored on its mount until it lights")

	GameManager.start_attempt()
	await get_tree().physics_frame
	await get_tree().physics_frame
	check(not rocket.anchored, "igniting releases it from the mount")
	check(not rocket.freeze, "and unfreezes it so the engine can move it")

	var launched_from: Vector2 = rocket.global_position
	for i in range(30):
		await get_tree().physics_frame
		if not is_instance_valid(rocket):
			break
	check(is_instance_valid(rocket), "the small rocket does not explode")
	if is_instance_valid(rocket):
		var travelled: float = launched_from.y - rocket.global_position.y
		# Upward against gravity is only possible under thrust.
		check(travelled > 20.0, "it is propelled upward against gravity (%.0fpx)" % travelled)

	GameManager.return_to_edit()
	LevelLayout.clear(container)


## Every reactive prop exposes the same knobs, and each scene sets them differently —
## otherwise the props are one behaviour wearing three costumes.
func _test_prop_tuning_differs() -> void:
	print("\n[prop tuning differs]")
	var container: Node = GameManager.get_placed_objects_container()
	LevelLayout.clear(container)

	var profiles: Dictionary = {}
	for name in ["bomb", "dinamita", "tntminecraft"]:
		var path: String = "res://entities/props/%s/%s.tscn" % [name, name]
		var node: Node = load(path).instantiate()
		container.add_child(node)
		var boom: Explosive = node
		profiles[name] = {
			"radius": boom.blast_radius,
			"force": boom.blast_force,
			"fuse": boom.fuse_seconds,
			"break": boom.break_power,
			"trigger": boom.trigger_mode,
		}
		container.remove_child(boom)
		boom.free()

	check(
		profiles["bomb"]["radius"] < profiles["dinamita"]["radius"]
			and profiles["dinamita"]["radius"] < profiles["tntminecraft"]["radius"],
		"blast radius grows bomb < dynamite < TNT"
	)
	check(
		is_zero_approx(profiles["bomb"]["fuse"]) and profiles["dinamita"]["fuse"] > 0.5,
		"the bomb goes off on contact while the dynamite has a real fuse"
	)
	check(
		profiles["tntminecraft"]["trigger"] == PlaceableObject.TriggerMode.ON_PLAY,
		"the TNT is on a timer rather than contact-triggered"
	)
	check(
		profiles["bomb"]["break"] < profiles["tntminecraft"]["break"],
		"breaking power is tuned separately from throwing force"
	)

	# Launchers differ in what they react to, not just how hard they hit.
	var cannon: Launcher = load("res://entities/props/canon/canon.tscn").instantiate()
	var spring: Launcher = load("res://entities/props/muelle/muelle.tscn").instantiate()
	container.add_child(cannon)
	container.add_child(spring)
	check(cannon.trigger_mode == PlaceableObject.TriggerMode.BALL_CONTACT, "the cannon only fires at the ball")
	check(spring.trigger_mode == PlaceableObject.TriggerMode.ANY_CONTACT, "the spring throws anything that lands on it")
	check(cannon.launch_impulse > spring.launch_impulse, "the cannon hits harder than the spring")
	LevelLayout.clear(container)


## Pausing must dim the level, not cover it — the whole reason to pause is to look at
## what the simulation did.
func _test_pause_overlay() -> void:
	print("\n[pause dims rather than panels]")
	var hud: HUDController = _main.get_node_or_null("UI/HUD")
	if hud == null:
		check(false, "the HUD is available")
		return

	LevelLayout.clear(GameManager.get_placed_objects_container())
	SaveManager._set_time_bank(60.0)
	GameManager.start_attempt()
	await get_tree().physics_frame

	GameManager.pause()
	await get_tree().process_frame
	check(hud.pause_overlay.visible, "pausing shows the dimmer")
	check(not hud.result_panel.visible, "and does NOT open a panel over the level")
	check(hud.pause_overlay.color.a < 1.0, "the dimmer is translucent (alpha %.2f)" % hud.pause_overlay.color.a)
	# It has to swallow clicks, or props stay draggable through the dimmer.
	check(hud.pause_overlay.mouse_filter != Control.MOUSE_FILTER_IGNORE, "it blocks input to the level")

	GameManager.resume()
	await get_tree().process_frame
	check(not hud.pause_overlay.visible, "resuming hides it again")

	GameManager.return_to_edit()
	await get_tree().process_frame
	check(not hud.pause_overlay.visible, "and it stays hidden in EDIT")


## The distinction that matters: a ball ROLLING over a plank must not break it, while
## a ball DROPPING onto it must. Anchored props are frozen and report no contacts of
## their own, so this only works because the moving body reports what it hit.
func _test_wood_cracks_on_impact() -> void:
	print("\n[wood cracks on impact only]")
	var container: Node = GameManager.get_placed_objects_container()
	var level: Level = GameManager.get_current_level()
	SaveManager._set_time_bank(60.0)

	# --- rolling across it: must survive ---
	LevelLayout.clear(container)
	var plank: PlaceableObject = load("res://entities/props/madera/madera.tscn").instantiate()
	container.add_child(plank)
	check(plank.anchored, "the plank is anchored, so it reports no contacts itself")

	var spawn: Vector2 = level.ball_spawn.position
	# Sit the plank just under the ball's start so it rolls along it off the ledge.
	plank.global_position = level.ball_spawn.global_position + Vector2(60, 40)
	GameManager.start_attempt()
	for i in range(90):
		await get_tree().physics_frame
		if not is_instance_valid(plank):
			break
	check(is_instance_valid(plank), "a ball rolling over it does not break it")
	GameManager.return_to_edit()

	# --- dropped onto from height: must break ---
	LevelLayout.clear(container)
	var target: PlaceableObject = load("res://entities/props/madera/madera.tscn").instantiate()
	container.add_child(target)
	level.ball_spawn.global_position = Vector2(700, 200)
	target.global_position = Vector2(700, 700)

	var before: int = SaveManager.get_material_count("wood_chips")
	GameManager.start_attempt()
	var peak_impact: float = 0.0
	var peak_speed: float = 0.0
	for i in range(120):
		await get_tree().physics_frame
		var ball: Ball = level.get_ball()
		if ball != null:
			peak_impact = maxf(peak_impact, ball.last_impact)
			peak_speed = maxf(peak_speed, ball.linear_velocity.length())
		if not is_instance_valid(target):
			break
	check(
		not is_instance_valid(target),
		"a ball dropped onto it breaks it (peak impact %.0f, peak speed %.0f)" % [peak_impact, peak_speed]
	)
	check(
		SaveManager.get_material_count("wood_chips") > before,
		"and that credits materials (%d -> %d)" % [before, SaveManager.get_material_count("wood_chips")]
	)

	GameManager.return_to_edit()
	level.ball_spawn.position = spawn
	LevelLayout.clear(container)


## The bomb detonates ON CONTACT. It used to wait, because a design-time fuse value
## was being persisted into the layout save and restored over the scene's value.
func _test_bomb_is_instant() -> void:
	print("\n[bomb is instant]")
	var scene: PackedScene = load("res://entities/props/bomb/bomb.tscn")
	var container: Node = GameManager.get_placed_objects_container()
	LevelLayout.clear(container)

	var bomb: Explosive = scene.instantiate()
	container.add_child(bomb)
	check(is_zero_approx(bomb.fuse_seconds), "the bomb's fuse is zero (%.2fs)" % bomb.fuse_seconds)

	# Nothing design-time may ride along in the save, or later retuning is overridden.
	var state: Dictionary = bomb.get_save_state()
	check(not state.has("fuse_seconds"), "the fuse is NOT persisted into the layout save")

	# A stale save must no longer be able to reintroduce it.
	bomb.apply_save_state({"fuse_seconds": 5.0})
	check(is_zero_approx(bomb.fuse_seconds), "an old save file cannot override the scene's fuse")
	LevelLayout.clear(container)


## The opening sequence. The word-by-word assembly is checked directly rather than by
## waiting on it, then the whole thing is run once end to end — an intro that never
## finishes would leave the player staring at a logo with no way in.
func _test_intro_sequence() -> void:
	print("\n[intro sequence]")

	# Cumulative title, which is what "punching in" means here.
	check(MainMenu.title_up_to(1) == "Roll", "one word reads 'Roll' (got '%s')" % MainMenu.title_up_to(1))
	check(MainMenu.title_up_to(2) == "Roll the", "two words read 'Roll the'")
	check(MainMenu.title_up_to(3) == "Roll the Ball", "three words read 'Roll the Ball'")
	check(MainMenu.WORD_HOLDS.size() == MainMenu.TITLE_WORDS.size(), "every word has a hold time")
	check(
		is_equal_approx(MainMenu.WORD_HOLDS[0], 0.8)
			and is_equal_approx(MainMenu.WORD_HOLDS[1], 0.4)
			and is_equal_approx(MainMenu.WORD_HOLDS[2], 2.0),
		"the holds are 0.8 / 0.4 / 2.0 as specified"
	)

	# A fresh launch has not played it yet.
	MainMenu._intro_played = false
	var menu: Control = load(GameManager.MAIN_MENU_SCENE).instantiate()
	get_tree().root.add_child(menu)
	await get_tree().process_frame

	check(menu.intro.visible, "the intro starts over the empty background")
	check(not menu.body.visible, "the rest of the menu is hidden")
	check(menu.title_label.text.is_empty(), "and the title starts blank")
	# Released so the panel can grow with the title instead of sitting at full width.
	check(is_zero_approx(menu.panel.custom_minimum_size.x), "the panel is free to hug the title")

	# Let it run to completion, with a generous ceiling.
	var budget: float = MainMenu.LOGO_FADE_IN * 2.0 + MainMenu.LOGO_HOLD \
		+ MainMenu.LOGO_FADE_OUT + MainMenu.PAPER_BEAT + 3.2 + MainMenu.BODY_FADE_IN + 3.0
	var finished: Dictionary = {"done": false}
	menu.intro_finished.connect(func() -> void: finished["done"] = true)
	var waited: float = 0.0
	while not finished["done"] and waited < budget:
		await get_tree().process_frame
		waited += get_process_delta_time()

	check(finished["done"], "the intro finishes on its own (%.1fs of %.1fs budget)" % [waited, budget])
	check(menu.title_label.text == "Roll the Ball", "the full title is left on screen")
	check(menu.body.visible, "the rest of the menu appears")
	check(not menu.intro.visible, "and the logo overlay is gone")
	check(
		is_equal_approx(menu.panel.custom_minimum_size.x, MainMenu.PANEL_WIDTH),
		"the panel settles at its full width"
	)

	menu.get_parent().remove_child(menu)
	menu.queue_free()
	await get_tree().process_frame

	# Backing out of the level select is not a fresh launch, so it must NOT replay.
	var second: Control = load(GameManager.MAIN_MENU_SCENE).instantiate()
	get_tree().root.add_child(second)
	await get_tree().process_frame
	check(not second.intro.visible, "returning to the menu does not replay the intro")
	check(second.body.visible, "it opens straight onto a usable menu")
	check(second.title_label.text == "Roll the Ball", "with the title already in place")

	# Skipping has to reach exactly the same state from mid-intro.
	MainMenu._intro_played = false
	var third: Control = load(GameManager.MAIN_MENU_SCENE).instantiate()
	get_tree().root.add_child(third)
	await get_tree().process_frame
	check(third.intro.visible, "a third fresh launch starts the intro again")
	third.skip_intro()
	await get_tree().process_frame
	check(not third.intro.visible, "skipping hides the overlay")
	check(third.body.visible, "and reveals the menu immediately")
	check(third.title_label.text == "Roll the Ball", "with the full title")

	for node in [second, third]:
		node.get_parent().remove_child(node)
		node.queue_free()


## Progress belongs to the NAME, not the install. Without that, one finished run could
## be resubmitted under any number of names and flood every leaderboard.
func _test_progress_per_player() -> void:
	print("\n[progress follows the name]")
	var original: String = "__probe_one__"
	var other: String = "__probe_two__"

	SaveManager.switch_player(original)
	SaveManager.erase_all_data()
	SaveManager.switch_player(original)
	check(SaveManager.get_player_name() == original, "the active player is the one just set")
	check(not SaveManager.has_progress(), "a brand new name starts with nothing")

	# Earn something.
	SaveManager.charge_for_completion(1, 4.0)
	SaveManager.save_layout(1, {"format_version": 1, "objects": []})
	check(SaveManager.has_progress(), "clearing a level counts as progress")
	check(is_equal_approx(SaveManager.get_best_time(1), 4.0), "the best time is recorded")
	check(SaveManager.has_layout(1), "and the layout is saved")

	# A different name must be a clean slate.
	SaveManager.switch_player(other)
	SaveManager.erase_all_data()
	SaveManager.switch_player(other)
	check(not SaveManager.has_progress(), "switching to another name resets progress")
	check(SaveManager.get_best_time(1) < 0.0, "with no best times")
	check(not SaveManager.has_layout(1), "and none of the other player's layouts")
	check(is_equal_approx(SaveManager.get_time_bank(), SaveManager.STARTING_BANK), "and a full time bank")

	# Typing the original back must restore it untouched.
	SaveManager.switch_player(original)
	check(SaveManager.has_progress(), "switching back restores the first player's progress")
	check(is_equal_approx(SaveManager.get_best_time(1), 4.0), "including their best time")
	check(SaveManager.has_layout(1), "and their layouts")

	# Names that would sanitise to the same directory must not share a save.
	SaveManager.switch_player("a b")
	SaveManager.erase_all_data()
	SaveManager.switch_player("a b")
	SaveManager.charge_for_completion(1, 7.0)
	SaveManager.switch_player("a_b")
	SaveManager.erase_all_data()
	SaveManager.switch_player("a_b")
	check(
		SaveManager.get_best_time(1) < 0.0,
		"'a b' and 'a_b' do not collide onto one save"
	)

	for junk in [original, other, "a b", "a_b"]:
		SaveManager.switch_player(junk)
		SaveManager.erase_all_data()
	SaveManager.switch_player(TEST_PLAYER)
	# Otherwise the tutorial claims level 1 (no progress = it should run), despawns the
	# ball and blocks the mouse for everything after it. _test_tutorial drives it
	# explicitly instead, from its own fresh player.
	SaveManager.mark_tutorial_seen()


## Joe's introduction. It builds the level up as he talks, so what matters is that
## nothing is on screen at the start, everything is by the end, and skipping lands in
## exactly the same place.
func _test_tutorial() -> void:
	print("\n[tutorial]")
	var tutorial: Tutorial = _main.get_node_or_null("UI/Tutorial")
	check(tutorial != null, "main.tscn hosts the tutorial")
	if tutorial == null:
		return
	var hud: HUDController = _main.get_node_or_null("UI/HUD")
	var level: Level = GameManager.get_current_level()
	if hud == null or level == null:
		check(false, "the HUD and level are available")
		return

	check(Tutorial.STEPS.size() == 6, "there are six beats (%d)" % Tutorial.STEPS.size())
	# Each staged part must be something the steps actually put back, or the level would
	# stay permanently missing a piece.
	var revealed: Dictionary = {}
	for step in Tutorial.STEPS:
		for path in step.get("reveal", []):
			revealed[str(path)] = true
	for path in Tutorial.STAGED_PARTS:
		check(revealed.has(path), "'%s' is hidden AND revealed by some step" % path)

	# Fresh player with nothing behind them: the tutorial should take over.
	SaveManager.switch_player("__tutorial_probe__")
	SaveManager.erase_all_data()
	SaveManager.switch_player("__tutorial_probe__")
	check(not SaveManager.has_seen_tutorial(), "a new player has not seen it")

	tutorial.force_start()
	await get_tree().process_frame
	check(tutorial.visible, "it takes over the screen")
	check(level.get_ball() == null, "the level starts with no ball")
	check(not hud.time_label.visible, "the clock is hidden")
	check(not hud.palette_items.get_parent().visible, "the palette is hidden")
	check(not hud.play_button.visible, "and Play can't be pressed mid-explanation")
	check(not level.get_node("Geometry/LeftLedge").visible, "the platform is hidden")
	check(not level.get_node("Goal").visible, "the basket is hidden")

	# Step through: ball, basket, clock, palette.
	tutorial._advance()
	await get_tree().process_frame
	check(level.get_node("Geometry/LeftLedge").visible, "the platform appears with the ball")
	check(level.get_ball() != null, "and the ball is spawned")

	var balloon_before: float = tutorial.balloon.offset_bottom
	check(is_zero_approx(tutorial.get_lift()), "Joe starts down at the bottom")
	tutorial._advance()
	check(level.get_node("Goal").visible, "the basket appears next")
	# The basket sits directly behind the balloon, so the pair have to move.
	check(tutorial.get_lift() > 0.0, "Joe and the balloon hop up out of the basket's way")
	# The tween needs a moment; the target offsets are what matter.
	for i in range(30):
		await get_tree().process_frame
	check(
		tutorial.balloon.offset_bottom < balloon_before,
		"the balloon really ends up higher (%.0f -> %.0f)" % [balloon_before, tutorial.balloon.offset_bottom]
	)
	check(
		tutorial.joe.offset_bottom < tutorial._joe_rest.y,
		"and Joe goes with it"
	)

	var lifted: float = tutorial.get_lift()
	tutorial._advance()
	check(hud.time_label.visible, "then the clock")
	check(is_equal_approx(tutorial.get_lift(), lifted), "and they stay up for the rest of it")

	tutorial._advance()
	check(hud.palette_items.get_parent().visible, "then the palette")

	# Skipping from the last beat must still hand over a complete level.
	tutorial._finish()
	await get_tree().process_frame
	check(not tutorial.visible, "it gets out of the way when done")
	check(SaveManager.has_seen_tutorial(), "and is remembered, so it won't replay")
	for path in Tutorial.STAGED_PARTS:
		check(level.get_node(path).visible, "'%s' is visible once it hands over" % path)
	check(hud.play_button.visible, "the controls are back")
	check(hud.palette_items.get_parent().visible, "the palette is back")
	check(level.get_ball() != null, "and the ball is on the platform")

	# Having seen it, a re-entry must not start it again.
	tutorial._on_level_started(Tutorial.TUTORIAL_LEVEL)
	check(not tutorial.visible, "it does not restart for a player who has seen it")

	# And a player who already has progress never sees it at all.
	SaveManager.erase_all_data()
	SaveManager.switch_player("__tutorial_probe__")
	SaveManager.charge_for_completion(1, 3.0)
	tutorial._on_level_started(Tutorial.TUTORIAL_LEVEL)
	check(not tutorial.visible, "nor does a player who already has progress")

	SaveManager.erase_all_data()
	SaveManager.switch_player(TEST_PLAYER)


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
	# Progress now lives per player name, so the suite works inside a throwaway one
	# rather than clearing whatever the real player has.
	SaveManager.switch_player(TEST_PLAYER)
	for level_id in SaveManager.list_saved_layouts():
		SaveManager.delete_layout(level_id)
	SaveManager.erase_all_data()
	SaveManager.switch_player(TEST_PLAYER)
	# Without this the tutorial claims level 1 — a player with no progress is exactly
	# who it's for — then despawns the ball and covers the screen for every test after
	# it. _test_tutorial drives it explicitly from its own fresh player instead.
	SaveManager.mark_tutorial_seen()


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
