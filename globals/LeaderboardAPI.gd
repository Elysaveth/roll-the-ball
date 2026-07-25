extends Node
# Autoload singleton — register as "LeaderboardAPI", after SignalBus AND after
# the SilentWolf plugin's own "SilentWolf" autoload (Project Settings > Autoload).
#
# PREREQUISITE: install & enable the SilentWolf plugin first
# (AssetLib search "SilentWolf", or https://silentwolf.com/download).
# Enabling it registers its own "SilentWolf" autoload — this script wraps that,
# so the rest of the game only ever talks to SignalBus and never touches
# SilentWolf directly (swap backends later without touching gameplay code).
#
# Verified against SilentWolf's own Godot 4 migration notes as of writing
# (https://silentwolf.com/blog/godot4.html): Godot 4's addon (0.9.x) uses
# `await` instead of `yield`, renamed `persist_score` -> `save_score`, and
# consolidated signals into "..._complete" variants whose payload lands in a
# variable conventionally named sw_result. I could NOT confirm optional extra
# parameters (per-board scores, score metadata) against a live docs page, so
# double-check those against your installed version's docs if you need them.

var api_key: String = ""
var game_id: String = ""
@export var game_version: String = ProjectSettings.get_setting("application/config/version")

func _ready() -> void:
	load_secrets()
	if api_key.is_empty() or game_id.is_empty():
		push_warning("LeaderboardAPI: api_key / game_id not set — leaderboard calls will fail.")
		return
	# Some SilentWolf versions expose a Project Settings panel (added by the
	# plugin) to set these instead of code — if yours does, this call is
	# redundant but harmless; otherwise this is what wires it up.
	SilentWolf.configure({
		"api_key": api_key,
		"game_id": game_id,
		"game_version": game_version,
		"log_level": 1,
	})

func submit_score(player_name: String, score: float) -> void:
	SilentWolf.Scores.save_score(player_name, score)
	var sw_result: Variant = await SilentWolf.Scores.sw_save_score_complete
	# sw_result's exact shape varies by SilentWolf version — print it once to
	# inspect, then tighten this check if you want to branch on specific fields.
	if sw_result:
		SignalBus.score_submitted.emit(player_name, score)
	else:
		SignalBus.score_submit_failed.emit("save_score returned no result")

func fetch_scores() -> void:
	SilentWolf.Scores.get_scores()
	var sw_result: Variant = await SilentWolf.Scores.sw_get_scores_complete
	if sw_result:
		SignalBus.scores_received.emit(sw_result)
	else:
		SignalBus.scores_request_failed.emit("get_scores returned no result")

func load_secrets():
	var config: ConfigFile = ConfigFile.new()
	var err: int = config.load("res://secrets.cfg")

	if err == OK:
		api_key = config.get_value("silent_wolf", "api_key", "")
		game_id = config.get_value("silent_wolf", "game_id", "")
	else:
		# If the file is missing, it will throw an error here.
		# This is helpful so you know if you forgot to create secrets.cfg locally!
		push_error("Could not load secrets.cfg. Ensure the file exists. Error: ", err)