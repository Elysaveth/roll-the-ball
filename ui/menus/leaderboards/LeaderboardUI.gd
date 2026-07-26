extends PanelContainer
class_name LeaderboardPanel
# A reusable leaderboard view. Embedded in the HUD's result panel to show the
# current level's board when the ball lands, and shown standalone from the level
# select for the general progress board.
#
# Everything arrives through SignalBus, filtered on the board name — there is one
# board per level plus `progress`, and they all report through the same signal.
#
# Goes through LeaderboardApi rather than touching SilentWolf directly, which is
# the whole point of that wrapper.

const SCORE_ROW: PackedScene = preload("res://ui/menus/leaderboards/ScoreRow.tscn")

@onready var title_label: Label = $VBox/TitleLabel
@onready var status_label: Label = $VBox/StatusLabel
@onready var score_list: VBoxContainer = $VBox/ScrollContainer/ScoreList

var _board: String = ""
## One of LeaderboardApi.ValueFormat.
var _format: int = LeaderboardApi.ValueFormat.SECONDS


func _ready() -> void:
	SignalBus.scores_received.connect(_on_scores_received)
	SignalBus.scores_request_failed.connect(_on_scores_request_failed)


## Points the panel at a board and kicks off a fetch. Safe to call repeatedly —
## a second call just replaces what's displayed.
func show_board(board: String, title: String, format: int = LeaderboardApi.ValueFormat.SECONDS) -> void:
	_board = board
	_format = format
	title_label.text = title
	_clear_rows()

	if not LeaderboardApi.is_configured():
		_set_status("LB_OFFLINE")
		return

	_set_status("LB_LOADING")
	LeaderboardApi.fetch_scores(_board)


func _clear_rows() -> void:
	for child in score_list.get_children():
		score_list.remove_child(child)
		child.queue_free()


func _set_status(key: String, args: Array = []) -> void:
	status_label.text = tr(key) % args if not args.is_empty() else tr(key)
	status_label.show()


func _on_scores_received(board: String, scores: Array) -> void:
	if board != _board:
		return # another panel's request
	_clear_rows()

	if scores.is_empty():
		_set_status("LB_EMPTY")
		return
	status_label.hide()

	var rank: int = 1
	for entry in scores:
		var row: Node = SCORE_ROW.instantiate()
		score_list.add_child(row)
		row.setup(rank, str(entry.get("player_name", "?")), float(entry.get("score", 0.0)), _format)
		rank += 1


func _on_scores_request_failed(board: String, error: String) -> void:
	if board != _board:
		return
	_clear_rows()
	_set_status("LB_ERROR", [error])
