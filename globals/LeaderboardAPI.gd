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
# ONE THING TO CONFIGURE SERVER-SIDE
# ----------------------------------
# Level boards store times, where LOWER is better, and SilentWolf ranks higher
# scores first by default. Set those boards to ascending in the SilentWolf
# dashboard, or the leaderboard will show the slowest runs at the top. Nothing in
# this file can fix that — inverting the number here would make every stored score
# meaningless. The `progress` board wants the default descending order.

## How a board's score column should be rendered. Lives here rather than on the
## leaderboard panel because reaching it through this autoload never depends on
## Godot's global script class cache, which goes stale on any fresh checkout and
## takes every `class_name` reference down with it.
enum ValueFormat {
	SECONDS, ## An attempt time, on a per-level board.
	LEVEL,   ## A level number, on the general progress board.
}

## Board holding the furthest completed level per player.
const BOARD_GENERAL: String = "progress"
const DEFAULT_MAX_SCORES: int = 10

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
	return not api_key.is_empty() and not game_id.is_empty()


static func board_for_level(level_id: int) -> String:
	return "level_%02d" % level_id


# ------------------------------------------------------------ public api ----

func submit_score(player_name: String, score: float, board: String) -> void:
	if player_name.is_empty():
		push_warning("LeaderboardApi: refusing to submit an unnamed score")
		return
	_enqueue({"kind": "save", "board": board, "player": player_name, "score": score})


func fetch_scores(board: String, maximum: int = DEFAULT_MAX_SCORES) -> void:
	_enqueue({"kind": "get", "board": board, "maximum": maximum})


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
			SilentWolf.Scores.save_score(request["player"], request["score"], board)
			var result: Variant = await SilentWolf.Scores.sw_save_score_complete
			if result:
				SignalBus.score_submitted.emit(board, request["player"], request["score"])
			else:
				SignalBus.score_submit_failed.emit(board, "save_score returned no result")
		"get":
			SilentWolf.Scores.get_scores(request["maximum"], board)
			var result: Variant = await SilentWolf.Scores.sw_get_scores_complete
			if not result is Dictionary:
				SignalBus.scores_request_failed.emit(board, "get_scores returned no result")
				return
			var payload: Dictionary = result
			var returned_board: String = str(payload.get("ld_name", board))
			if returned_board != board:
				# Shouldn't happen while requests are serialised, but reporting the
				# board it actually belongs to beats mislabelling someone's scores.
				push_warning("LeaderboardApi: asked for '%s', got '%s'" % [board, returned_board])
			SignalBus.scores_received.emit(returned_board, _normalise_scores(payload.get("scores", [])))


func _fail(request: Dictionary, reason: String) -> void:
	var board: String = request.get("board", "")
	if request.get("kind", "") == "get":
		SignalBus.scores_request_failed.emit(board, reason)
	else:
		SignalBus.score_submit_failed.emit(board, reason)


## Flattens whatever SilentWolf hands back into a plain array of
## {player_name, score} dictionaries, so no screen has to know the payload shape.
func _normalise_scores(raw: Variant) -> Array:
	var out: Array = []
	if not raw is Array:
		return out
	for entry in raw:
		if not entry is Dictionary:
			continue
		out.append({
			"player_name": str(entry.get("player_name", entry.get("name", "?"))),
			"score": float(entry.get("score", 0.0)),
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
