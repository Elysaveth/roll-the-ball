extends Node
# Headless smoke test for the run loop: layout snapshot/restore, the time bank
# arithmetic, and the freeze on time-up.
#
#   godot --headless --path . res://tools/smoke_test.tscn
#
# Exits with the number of failed checks, so it doubles as a CI gate.
#
# It backs up and restores user://profile.json and user://saves/ around the run,
# because it deliberately writes junk into both.

const PROP_SCENE: String = "res://entities/props/hielo/hielo.tscn"

var _failures: int = 0
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
	_reset_profile()

	# Wait a frame before touching root: during our own _ready the tree is still
	# adding children and add_child() on it is refused.
	await get_tree().process_frame
	_main = load(GameManager.MAIN_SCENE).instantiate()
	get_tree().root.add_child(_main)
	await get_tree().process_frame

	await _test_level_loads()
	await _test_snapshot_restores_layout()
	await _test_bank_charges_and_refunds()
	await _test_time_up_freezes()
	await _test_level_01_is_a_puzzle()
	await _test_bomb_explodes()


# ----------------------------------------------------------------- tests ----

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
