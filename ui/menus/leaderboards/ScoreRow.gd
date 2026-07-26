extends HBoxContainer
# One line of a leaderboard. Populated by LeaderboardPanel.

@onready var rank_label: Label = $RankLabel
@onready var name_label: Label = $NameLabel
@onready var score_label: Label = $ScoreLabel


## `value` means different things per board — seconds on a level board, a level
## number on the general one — so the panel says which to render. `format` is one
## of LeaderboardApi.ValueFormat.
func setup(rank: int, player_name: String, value: float, format: int) -> void:
	rank_label.text = "%d." % rank
	name_label.text = player_name
	if format == LeaderboardApi.ValueFormat.LEVEL:
		score_label.text = tr("LB_LEVEL_VALUE") % int(value)
	else:
		score_label.text = "%.2fs" % value
