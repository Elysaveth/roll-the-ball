extends Control
# Goes through LeaderboardApi + SignalBus rather than touching SilentWolf
# directly. That's the point of the wrapper in globals/LeaderboardAPI.gd: the
# backend can be swapped without any screen having to change.
#
# (The previous version awaited `SilentWolf.Scores.get_scores(10).sw_get_scores_complete`,
# which awaits a property on a return value rather than a signal on the object,
# and would never have resolved.)

const SCORE_ROW: PackedScene = preload("res://ui/menus/leaderboards/ScoreRow.tscn")

@onready var score_list: VBoxContainer = $Panel/VBoxContainer/ScrollContainer/ScoreList
@onready var loading_label: Label = $Panel/VBoxContainer/LoadingLabel


func _ready() -> void:
	SignalBus.scores_received.connect(_on_scores_received)
	SignalBus.scores_request_failed.connect(_on_scores_request_failed)
	refresh_leaderboard()


func refresh_leaderboard() -> void:
	loading_label.text = "Cargando..."
	loading_label.show()
	for child in score_list.get_children():
		score_list.remove_child(child)
		child.queue_free()
	LeaderboardApi.fetch_scores()


func _on_scores_received(result: Variant) -> void:
	loading_label.hide()

	var scores: Array = []
	# SilentWolf hands back a dictionary with a "scores" array; guard anyway,
	# since the exact payload shape varies between plugin versions.
	if result is Dictionary and result.get("scores") is Array:
		scores = result["scores"]
	elif result is Array:
		scores = result

	if scores.is_empty():
		loading_label.text = "Todavía no hay puntuaciones"
		loading_label.show()
		return

	for score_data in scores:
		var row: Node = SCORE_ROW.instantiate()
		score_list.add_child(row)
		row.setup(
			str(score_data.get("player_name", "?")),
			float(score_data.get("score", 0.0))
		)


func _on_scores_request_failed(error: String) -> void:
	loading_label.text = "No se pudo cargar la tabla (%s)" % error
	loading_label.show()
