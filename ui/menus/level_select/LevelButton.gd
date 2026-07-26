extends Button
class_name LevelButton
# One tile in the level select grid. Shows the level number and, once cleared,
# the player's best time on it — which is also what that level currently costs
# them out of the global time bank.


func setup(level_id: int, unlocked: bool, best_time: float) -> void:
	disabled = not unlocked

	if not unlocked:
		text = str(level_id)
		modulate = Color(0.5, 0.5, 0.5, 0.8)
		tooltip_text = tr("SELECT_LOCKED")
		return

	modulate = Color.WHITE
	if best_time < 0.0:
		text = str(level_id)
		tooltip_text = tr("SELECT_NOT_COMPLETED")
	else:
		text = "%d\n%.2fs" % [level_id, best_time]
		tooltip_text = tr("SELECT_RECORD") % ("%.2fs" % best_time)
