extends HBoxContainer

@onready var name_label: Label = $NameLabel
@onready var score_label: Label = $ScoreLabel


## Called by LeaderboardUI.gd when populating the list. `score` is a time in
## seconds, so lower is better.
func setup(player_name: String, score: float) -> void:
	name_label.text = player_name
	score_label.text = "%.2fs" % score
