extends Control
# Level picker. The grid is built from the level scenes that actually exist on
# disk (GameManager.count_available_levels()) rather than a hardcoded total, so
# adding levels/level_04/level_04.tscn is all it takes to get a fourth tile.
#
# Also the way in to the general leaderboard — the one ranking how far each player
# has got. Per-level boards live in the HUD's result panel instead, since that's
# the moment a time is worth comparing.

const LEVEL_BUTTON: PackedScene = preload("res://ui/menus/level_select/LevelButton.tscn")

@onready var grid: GridContainer = $VBoxContainer/GridContainer
@onready var bank_label: Label = $VBoxContainer/BankLabel
@onready var back_button: Button = $VBoxContainer/Header/BackButton
@onready var leaderboard_button: Button = $VBoxContainer/Header/LeaderboardButton
@onready var leaderboard_overlay: Panel = $LeaderboardOverlay
@onready var leaderboard: PanelContainer = $LeaderboardOverlay/Center/VBox/Leaderboard
@onready var close_button: Button = $LeaderboardOverlay/Center/VBox/CloseButton


func _ready() -> void:
	SignalBus.time_bank_changed.connect(_on_time_bank_changed)
	back_button.pressed.connect(GameManager.go_to_main_menu)
	leaderboard_button.pressed.connect(_on_leaderboard_pressed)
	close_button.pressed.connect(leaderboard_overlay.hide)

	leaderboard_overlay.hide()
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
		# Typed as Button rather than LevelButton on purpose: annotating a global
		# class name here makes this file fail to parse whenever Godot's script
		# class cache is stale, which it is after any fresh checkout.
		var button: Button = LEVEL_BUTTON.instantiate()
		grid.add_child(button)
		button.setup(level_id, SaveManager.is_level_unlocked(level_id), SaveManager.get_best_time(level_id))
		if SaveManager.is_level_unlocked(level_id):
			button.pressed.connect(GameManager.load_level.bind(level_id))


func _refresh_bank() -> void:
	bank_label.text = tr("SELECT_BANK") % [
		SaveManager.get_player_name(),
		"%.2fs" % SaveManager.get_time_bank(),
		"%.2fs" % SaveManager.STARTING_BANK,
	]


func _on_time_bank_changed(_seconds: float) -> void:
	_refresh_bank()
	# Best times move with the bank, so the tiles need redrawing too.
	populate_levels()


func _on_leaderboard_pressed() -> void:
	leaderboard_overlay.show()
	leaderboard.show_board(
		LeaderboardApi.BOARD_GENERAL,
		tr("LB_GENERAL_TITLE"),
		LeaderboardApi.ValueFormat.LEVEL
	)
