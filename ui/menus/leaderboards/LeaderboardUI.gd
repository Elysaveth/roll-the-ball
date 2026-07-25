extends Control

const SCORE_ROW: PackedScene = preload("res://ui/menus/leaderboards/ScoreRow.tscn")
@onready var score_list: VBoxContainer = $Panel/VBoxContainer/ScrollContainer/ScoreList
@onready var loading_label = $Panel/VBoxContainer/LoadingLabel

func _ready():
	refresh_leaderboard()

func refresh_leaderboard():
	loading_label.show()
	# Clear old entries
	for child in score_list.get_children():
		child.queue_free()

	# Call SilentWolf (Assuming main leaderboard)
	var sw_result = await SilentWolf.Scores.get_scores(10).sw_get_scores_complete

	loading_label.hide()

	if sw_result.scores.size() > 0:
		for score_data in sw_result.scores:
			var row: Node = SCORE_ROW.instantiate()
			# Assuming ScoreRow has a setup function to assign name and score labels
			row.setup(score_data.player_name, score_data.score)
			score_list.add_child(row)
	else:
		loading_label.text = "No scores yet!"
		loading_label.show()