extends HBoxContainer

@onready var name_label = $NameLabel
@onready var score_label = $ScoreLabel

# Called by LeaderboardUI.gd when populating the list
func setup(player_name: String, score: float):
	name_label.text = player_name
	# Assuming lower score is better (like time in seconds). 
	# Adjust formatting based on your game's scoring logic.
	score_label.text = str(score)