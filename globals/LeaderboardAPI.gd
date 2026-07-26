extends Node
# Autoload singleton — register as "LeaderboardApi", after SignalBus AND after
# the SilentWolf plugin's own "SilentWolf" autoload.
#
# Wraps SilentWolf so the rest of the game only ever talks to SignalBus, and the
# backend can be swapped without touching a single screen.
#
#
# BOARDS
# ------
# One board per level (`level_01`, `level_02`, ...) holding attempt times, plus a
# single `progress` board holding the furthest level each player has completed.
#
# Submission happens here rather than in GameManager: this file listens for
# SignalBus.goal_reached and decides what is worth uploading, which keeps the run
# loop ignorant of leaderboards entirely.
#
#
# WHY REQUESTS ARE QUEUED
# -----------------------
# SilentWolf reports every fetch through the same `sw_get_scores_complete` signal
# on the same node. Fire two fetches at once and whichever finishes first
# satisfies both awaits, so the second caller reads the wrong board's scores. One
# request in flight at a time removes the race; the payload's `ld_name` is still
# checked as a belt-and-braces measure.
#
#
# WHY TIMES ARE STORED INVERTED
# -----------------------------
# SilentWolf only ranks descending, and on a level board a LOWER time is better.
# So a time goes up as TIME_SCORE_BASE minus the time, which makes the fastest run
# the highest number and puts it on top.
#
# The inversion is confined to this file: submit_score() takes real seconds and
# scores come back out as real seconds, so no screen ever sees a wire value. If
# SilentWolf gains ascending boards later, deleting _encode/_decode and the
# _is_time_board() check is the whole migration — though note that scores already
# stored would need rewriting, since the base is baked into them.

## How a board's score column should be rendered. Lives here rather than on the
## leaderboard panel because reaching it through this autoload never depends on
## Godot's global script class cache, which goes stale on any fresh checkout and
## takes every `class_name` reference down with it.
enum ValueFormat {
	SECONDS, ## An attempt time, on a per-level board.
	LEVEL,   ## A level number, on the general progress board.
}

## Board holding the furthest completed level per player. This is SilentWolf's
## default board name — what save_score() writes to when given no board.
const BOARD_GENERAL: String = "main"
## Level board names, matching what exists in the SilentWolf dashboard.
const BOARD_LEVEL_TEMPLATE: String = "Level %d"
## Must exceed any achievable time. The entire bank is 60s, so this is ample.
const TIME_SCORE_BASE: float = 1000.0
const DEFAULT_MAX_SCORES: int = 10
## Seconds to wait for SilentWolf before giving up on a request.
##
## Not optional. SilentWolf emits its completion signal from INSIDE its
## `if status_check:` branch, so a non-2xx response, a rate limit or unparseable
## JSON means the signal never fires at all. Awaiting it unguarded would leave
## `_busy` true forever and no leaderboard request would ever run again.
const REQUEST_TIMEOUT: float = 12.0

## Set true to keep the game entirely off the network. The headless test suite uses
## it so a test run can't publish junk scores to the live boards, and it's the hook
## for an offline mode.
var offline: bool = false

var api_key: String = ""
var game_id: String = ""
var game_version: String = ProjectSettings.get_setting("application/config/version", "0.1")

var _queue: Array[Dictionary] = []
var _busy: bool = false


func _ready() -> void:
	load_secrets()
	SignalBus.goal_reached.connect(_on_goal_reached)

	if not is_configured():
		push_warning("LeaderboardApi: api_key / game_id not set — leaderboards disabled.")
		return
	SilentWolf.configure({
		"api_key": api_key,
		"game_id": game_id,
		"game_version": game_version,
		"log_level": 1,
	})


## False when there are no credentials, so screens can say "not configured"
## instead of spinning on a request that will never succeed.
func is_configured() -> bool:
	return not offline and not api_key.is_empty() and not game_id.is_empty()


## These are instance methods rather than static because they're only ever reached
## through the LeaderboardApi autoload, and calling a static function on an
## instance is a warning. An autoload can't declare a matching `class_name` to be
## addressed as a class either, so instance methods are the right shape.
func board_for_level(level_id: int) -> String:
	return BOARD_LEVEL_TEMPLATE % level_id


## True for boards whose scores are times and therefore stored inverted.
func _is_time_board(board: String) -> bool:
	return board != BOARD_GENERAL


## Real seconds -> the number actually stored. Clamped at zero so a freak time
## beyond the base can't wrap into a leading score.
func _encode(board: String, value: float) -> float:
	if not _is_time_board(board):
		return value
	return maxf(0.0, TIME_SCORE_BASE - value)


## The stored number -> real seconds. Deliberately the same arithmetic as
## _encode, so the pair can't drift apart.
func _decode(board: String, value: float) -> float:
	if not _is_time_board(board):
		return value
	return maxf(0.0, TIME_SCORE_BASE - value)


# ------------------------------------------------------------ public api ----

## `score` is always the real-world value — seconds for a level board, a level
## number for the general one. Inversion for storage happens in _run().
func submit_score(player_name: String, score: float, board: String) -> void:
	if player_name.is_empty():
		push_warning("LeaderboardApi: refusing to submit an unnamed score")
		return
	_enqueue({"kind": "save", "board": board, "player": player_name, "score": score})


func fetch_scores(board: String, maximum: int = DEFAULT_MAX_SCORES) -> void:
	_enqueue({"kind": "get", "board": board, "maximum": maximum})


## Removes a single entry. `score_id` comes from the `score_id` field of a fetched
## score — see tools/leaderboard_admin.gd, which pairs a fetch with this.
func delete_score(score_id: String, board: String) -> void:
	if score_id.is_empty():
		push_warning("LeaderboardApi: delete_score needs a score_id")
		return
	_enqueue({"kind": "delete", "board": board, "score_id": score_id})


## Empties a whole board. Destructive and irreversible — there is no undo on the
## SilentWolf side, so nothing in the game calls this; it exists for the admin tool.
func wipe_board(board: String) -> void:
	_enqueue({"kind": "wipe", "board": board})


# ------------------------------------------------------- auto submission ----

func _on_goal_reached(level_id: int, attempt_time: float, bank_delta: float) -> void:
	if not is_configured():
		return
	var player_name: String = SaveManager.get_player_name()
	if player_name.is_empty():
		return

	# A delta of zero means the player finished but didn't beat their record, so
	# there is nothing new to publish.
	if not is_zero_approx(bank_delta):
		submit_score(player_name, attempt_time, board_for_level(level_id))

	# The progress board only changes when a level is cleared for the first time.
	if bank_delta < 0.0:
		submit_score(player_name, float(SaveManager.get_furthest_completed_level()), BOARD_GENERAL)


# ----------------------------------------------------------------- queue ----

func _enqueue(request: Dictionary) -> void:
	if not is_configured():
		_fail(request, "not configured")
		return
	_queue.append(request)
	_pump()


func _pump() -> void:
	if _busy or _queue.is_empty():
		return
	_busy = true
	var request: Dictionary = _queue.pop_front()
	await _run(request)
	_busy = false
	# Tail call after the await, so the queue drains one request at a time.
	_pump()


func _run(request: Dictionary) -> void:
	var board: String = request["board"]
	match request["kind"]:
		"save":
			SilentWolf.Scores.save_score(request["player"], _encode(board, request["score"]), board)
			var result: Variant = await _await_or_timeout(SilentWolf.Scores.sw_save_score_complete)
			if result:
				# Reports the real value, not what went over the wire.
				SignalBus.score_submitted.emit(board, request["player"], request["score"])
			else:
				SignalBus.score_submit_failed.emit(board, "save_score returned no result")
		"get":
			SilentWolf.Scores.get_scores(request["maximum"], board)
			var result: Variant = await _await_or_timeout(SilentWolf.Scores.sw_get_scores_complete)
			if not result is Dictionary:
				SignalBus.scores_request_failed.emit(board, "get_scores returned no result")
				return
			var payload: Dictionary = result
			var returned_board: String = str(payload.get("ld_name", board))
			if returned_board != board:
				# Shouldn't happen while requests are serialised, but reporting the
				# board it actually belongs to beats mislabelling someone's scores.
				push_warning("LeaderboardApi: asked for '%s', got '%s'" % [board, returned_board])
			SignalBus.scores_received.emit(
				returned_board, _normalise_scores(payload.get("scores", []), returned_board)
			)
		"delete":
			SilentWolf.Scores.delete_score(request["score_id"], board)
			var result: Variant = await _await_or_timeout(SilentWolf.Scores.sw_delete_score_complete)
			if result:
				SignalBus.score_deleted.emit(board, request["score_id"])
			else:
				SignalBus.score_submit_failed.emit(board, "delete_score returned no result")
		"wipe":
			SilentWolf.Scores.wipe_leaderboard(board)
			var result: Variant = await _await_or_timeout(SilentWolf.Scores.sw_wipe_leaderboard_complete)
			if result:
				SignalBus.board_wiped.emit(board)
			else:
				SignalBus.score_submit_failed.emit(board, "wipe_leaderboard returned no result")


## Awaits `sig`, giving up after REQUEST_TIMEOUT and returning null.
##
## Needed because SilentWolf simply doesn't emit on a failed response — see
## REQUEST_TIMEOUT. Returning null makes the caller report a failure and, more
## importantly, lets _pump() release `_busy` so later requests still work.
func _await_or_timeout(sig: Signal) -> Variant:
	var state: Dictionary = {"done": false, "value": null}
	# Defaulted parameter so this fits the signal whether it carries a payload or
	# not — SilentWolf declares these with no parameters but emits one argument.
	var on_complete: Callable = func(value: Variant = null) -> void:
		state["value"] = value
		state["done"] = true
	sig.connect(on_complete, CONNECT_ONE_SHOT)

	var elapsed: float = 0.0
	while not state["done"] and elapsed < REQUEST_TIMEOUT:
		await get_tree().process_frame
		elapsed += get_process_delta_time()

	if not state["done"]:
		if sig.is_connected(on_complete):
			sig.disconnect(on_complete)
		push_warning("LeaderboardApi: request timed out after %.0fs" % REQUEST_TIMEOUT)
		return null
	return state["value"]


func _fail(request: Dictionary, reason: String) -> void:
	var board: String = request.get("board", "")
	if request.get("kind", "") == "get":
		SignalBus.scores_request_failed.emit(board, reason)
	else:
		SignalBus.score_submit_failed.emit(board, reason)


## Flattens whatever SilentWolf hands back into a plain array of
## {player_name, score} dictionaries, so no screen has to know the payload shape —
## and un-inverts times on the way, so `score` is always a real-world value.
func _normalise_scores(raw: Variant, board: String) -> Array:
	var out: Array = []
	if not raw is Array:
		return out
	for entry in raw:
		if not entry is Dictionary:
			continue
		out.append({
			"player_name": str(entry.get("player_name", entry.get("name", "?"))),
			"score": _decode(board, float(entry.get("score", 0.0))),
			# Carried through so an entry can be deleted later; the UI ignores it.
			"score_id": str(entry.get("score_id", "")),
		})
	return out


func load_secrets() -> void:
	var config: ConfigFile = ConfigFile.new()
	if config.load("res://secrets.cfg") != OK:
		# Expected on a fresh clone — secrets.cfg is gitignored. is_configured()
		# keeps everything else graceful, so this is a warning, not an error.
		push_warning("LeaderboardApi: no res://secrets.cfg, leaderboards will be disabled.")
		return
	api_key = config.get_value("silent_wolf", "api_key", "")
	game_id = config.get_value("silent_wolf", "game_id", "")
