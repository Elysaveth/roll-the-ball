extends Control
# Level picker. The grid is built from the level scenes that actually exist on
# disk (GameManager.count_available_levels()) rather than a hardcoded total, so
# adding levels/level_04/level_04.tscn is all it takes to get a fourth tile.

const LEVEL_BUTTON: PackedScene = preload("res://ui/menus/level_select/LevelButton.tscn")

@onready var grid: GridContainer = $VBoxContainer/GridContainer
@onready var bank_label: Label = $VBoxContainer/BankLabel


func _ready() -> void:
	SignalBus.time_bank_changed.connect(_on_time_bank_changed)
	populate_levels()
	_refresh_bank()


func populate_levels() -> void:
	for child in grid.get_children():
		grid.remove_child(child)
		child.queue_free()

	var total: int = GameManager.count_available_levels()
	if total == 0:
		push_warning("LevelSelect: no level scenes found at %s" % GameManager.LEVEL_PATH_TEMPLATE)
		return

	for level_id in range(1, total + 1):
		var button: LevelButton = LEVEL_BUTTON.instantiate()
		grid.add_child(button)
		button.setup(level_id, SaveManager.is_level_unlocked(level_id), SaveManager.get_best_time(level_id))
		if SaveManager.is_level_unlocked(level_id):
			button.pressed.connect(GameManager.load_level.bind(level_id))


func _refresh_bank() -> void:
	bank_label.text = "Banco de tiempo: %.2fs de %.2fs" % [
		SaveManager.get_time_bank(), SaveManager.STARTING_BANK
	]


func _on_time_bank_changed(_seconds: float) -> void:
	_refresh_bank()
	# Best times move with the bank, so the tiles need redrawing too.
	populate_levels()
