extends Node
# Leaderboard maintenance from the command line. Talks to the live SilentWolf
# boards, so it needs res://secrets.cfg.
#
#   List every board (default):
#     godot --headless --path . res://tools/leaderboard_admin.tscn
#
#   Delete every entry belonging to a player, on all known boards:
#     godot --headless --path . res://tools/leaderboard_admin.tscn -- --delete-player=Lizzy
#
#   Delete one entry:
#     godot --headless --path . res://tools/leaderboard_admin.tscn -- --delete-id=<score_id> --board="Level 1"
#
#   Empty a board completely (no undo):
#     godot --headless --path . res://tools/leaderboard_admin.tscn -- --wipe-board="Level 1"
#
# Deletions print what they are about to remove and require --yes, so a mistyped
# player name can't quietly empty a board.

const FETCH_LIMIT: int = 100
## Every request can only fail by timing out (SilentWolf doesn't signal on error),
## so scanning many absent boards is slow. Default to the levels that actually
## exist; --levels=N widens the scan for boards created ahead of their level.
const DEFAULT_TIMEOUT: float = 15.0

var _levels_to_scan: int = 0

var _delete_player: String = ""
var _delete_id: String = ""
var _wipe_board: String = ""
var _board_filter: String = ""
var _confirmed: bool = false


func _ready() -> void:
	_parse_args()
	# The admin tool is the one place that SHOULD reach the network, so undo the
	# safety the test suite relies on in case a stale value is around.
	LeaderboardApi.offline = false

	if not LeaderboardApi.is_configured():
		print("Leaderboards are not configured — res://secrets.cfg is missing or empty.")
		get_tree().quit(1)
		return

	if not _wipe_board.is_empty():
		await _do_wipe()
	elif not _delete_id.is_empty():
		await _do_delete_one()
	elif not _delete_player.is_empty():
		await _do_delete_player()
	else:
		await _do_list()

	get_tree().quit()


func _parse_args() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--delete-player="):
			_delete_player = arg.split("=", true, 1)[1]
		elif arg.begins_with("--delete-id="):
			_delete_id = arg.split("=", true, 1)[1]
		elif arg.begins_with("--wipe-board="):
			_wipe_board = arg.split("=", true, 1)[1]
		elif arg.begins_with("--board="):
			_board_filter = arg.split("=", true, 1)[1]
		elif arg.begins_with("--levels="):
			_levels_to_scan = int(arg.split("=", true, 1)[1])
		elif arg == "--yes":
			_confirmed = true
	if _levels_to_scan <= 0:
		_levels_to_scan = maxi(1, GameManager.count_available_levels())


func _boards() -> Array[String]:
	if not _board_filter.is_empty():
		return [_board_filter]
	var boards: Array[String] = [LeaderboardApi.BOARD_GENERAL]
	for level_id in range(1, _levels_to_scan + 1):
		boards.append(LeaderboardApi.board_for_level(level_id))
	return boards


# ------------------------------------------------------------------ actions ----

func _do_list() -> void:
	var total: int = 0
	for board in _boards():
		var scores: Array = await _fetch(board)
		if scores.is_empty():
			continue
		total += scores.size()
		print("\n%s  (%d entr%s)" % [board, scores.size(), "y" if scores.size() == 1 else "ies"])
		for entry in scores:
			print("  %-24s %-12s id=%s" % [
				entry["player_name"], _format_value(board, entry["score"]), entry["score_id"]
			])
	if total == 0:
		print("\nNo scores found on any scanned board. Nothing to clean up.")
	else:
		print("\n%d entr%s total." % [total, "y" if total == 1 else "ies"])


func _do_delete_player() -> void:
	var doomed: Array = []
	for board in _boards():
		for entry in await _fetch(board):
			if entry["player_name"] == _delete_player:
				doomed.append({"board": board, "entry": entry})

	if doomed.is_empty():
		print("No entries found for player '%s'." % _delete_player)
		return

	print("Would delete %d entr%s for '%s':" % [
		doomed.size(), "y" if doomed.size() == 1 else "ies", _delete_player
	])
	for item in doomed:
		print("  %-14s %-12s id=%s" % [
			item["board"], _format_value(item["board"], item["entry"]["score"]), item["entry"]["score_id"]
		])

	if not _confirmed:
		print("\nRe-run with --yes to actually delete these.")
		return

	for item in doomed:
		LeaderboardApi.delete_score(item["entry"]["score_id"], item["board"])
		var ok: bool = await _await_deletion()
		print("%s %s from %s" % ["Deleted" if ok else "FAILED to delete",
			item["entry"]["score_id"], item["board"]])


func _do_delete_one() -> void:
	var board: String = _board_filter if not _board_filter.is_empty() else LeaderboardApi.BOARD_GENERAL
	if not _confirmed:
		print("Would delete id=%s from %s. Re-run with --yes." % [_delete_id, board])
		return
	LeaderboardApi.delete_score(_delete_id, board)
	var ok: bool = await _await_deletion()
	print("%s %s from %s" % ["Deleted" if ok else "FAILED to delete", _delete_id, board])


func _do_wipe() -> void:
	if not _confirmed:
		var scores: Array = await _fetch(_wipe_board)
		print("Would ERASE all %d entr%s from '%s'. Re-run with --yes." % [
			scores.size(), "y" if scores.size() == 1 else "ies", _wipe_board
		])
		return
	LeaderboardApi.wipe_board(_wipe_board)
	var state: Dictionary = {"done": false}
	var on_ok: Callable = func(_b: String) -> void: state["done"] = true
	SignalBus.board_wiped.connect(on_ok)
	await _until(state, DEFAULT_TIMEOUT)
	SignalBus.board_wiped.disconnect(on_ok)
	print("%s '%s'." % ["Wiped" if state["done"] else "FAILED to wipe", _wipe_board])


# ------------------------------------------------------------------ helpers ----

## Fetches one board, tolerating the empty/absent case — a board that was never
## created in the dashboard reports a failure (or nothing at all), which is not
## worth shouting about here.
##
## Awaiting scores_received alone would hang forever on a board that doesn't exist,
## so both outcomes are watched and the wait is bounded.
func _fetch(board: String) -> Array:
	var state: Dictionary = {"done": false, "scores": []}
	var on_ok: Callable = func(b: String, scores: Array) -> void:
		if b == board and not state["done"]:
			state["scores"] = scores
			state["done"] = true
	var on_fail: Callable = func(b: String, _error: String) -> void:
		if b == board and not state["done"]:
			state["done"] = true

	SignalBus.scores_received.connect(on_ok)
	SignalBus.scores_request_failed.connect(on_fail)
	LeaderboardApi.fetch_scores(board, FETCH_LIMIT)
	await _until(state, DEFAULT_TIMEOUT)
	SignalBus.scores_received.disconnect(on_ok)
	SignalBus.scores_request_failed.disconnect(on_fail)
	return state["scores"]


## Waits until state["done"] or the timeout elapses.
func _until(state: Dictionary, timeout: float) -> void:
	var waited: float = 0.0
	while not state["done"] and waited < timeout:
		await get_tree().process_frame
		waited += get_process_delta_time()


## Deletions have the same problem as fetches: only a success is signalled.
func _await_deletion() -> bool:
	var state: Dictionary = {"done": false, "ok": false}
	var on_ok: Callable = func(_b: String, _id: String) -> void:
		state["ok"] = true
		state["done"] = true
	var on_fail: Callable = func(_b: String, _error: String) -> void:
		state["done"] = true
	SignalBus.score_deleted.connect(on_ok)
	SignalBus.score_submit_failed.connect(on_fail)
	await _until(state, DEFAULT_TIMEOUT)
	SignalBus.score_deleted.disconnect(on_ok)
	SignalBus.score_submit_failed.disconnect(on_fail)
	return state["ok"]


func _format_value(board: String, value: float) -> String:
	if board == LeaderboardApi.BOARD_GENERAL:
		return "level %d" % int(value)
	return "%.2fs" % value
