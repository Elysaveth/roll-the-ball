extends Control

const LEVEL_BUTTON: PackedScene = preload("res://ui/menus/level_select/LevelButton.tscn")
@onready var grid: GridContainer = $VBoxContainer/GridContainer

var total_levels: int = 20

func _ready():
	populate_levels()

func populate_levels():
	# Assume SaveManager tracks the highest level beaten (e.g., 5)
	var highest_unlocked = SaveManager.get_highest_unlocked_level()

	for i in range(1, total_levels + 1):
		var btn: Node = LEVEL_BUTTON.instantiate()
		btn.text = str(i)

		if i <= highest_unlocked:
			btn.setup_visuals(true)
			btn.pressed.connect(func(): _load_level(i))
		else:
			btn.disabled = true # Locked visual state

		grid.add_child(btn)

func _load_level(level_id: int):
	# Tell the GameManager to load the level and transition scenes
	GameManager.load_level(level_id)