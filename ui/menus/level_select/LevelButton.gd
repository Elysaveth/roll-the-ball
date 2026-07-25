extends Button

# You can expand this later to show stars or score data
func setup_visuals(is_unlocked: bool):
	disabled = !is_unlocked
	if disabled:
		modulate = Color(0.5, 0.5, 0.5, 0.8) # Darken if locked
	else:
		modulate = Color(1, 1, 1, 1)