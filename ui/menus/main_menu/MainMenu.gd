extends Control
class_name MainMenu
# Boot scene, and the game's opening sequence.
#
# Two jobs:
#   1. Play the intro — studio logo, then the title punching in a word at a time.
#   2. Make sure a player name exists before anything else happens, because a
#      leaderboard entry without a name is worthless.
#
#
# THE INTRO
# ---------
#   empty paper background
#   -> scrim + "Tres Games" logo fade in, hold, fade out
#   -> bare paper again, panel hugging an empty title
#   -> "Roll" ... "Roll the" ... "Roll the Ball", the panel widening to fit
#   -> the rest of the menu appears
#
# It runs ONCE per launch (see _intro_played). Coming back from the level select is
# not a fresh start, and sitting through the studio logo every time you back out of a
# menu would be maddening. Any key or click skips it.
#
# The white team name sits on a dark scrim rather than straight on the paper: white on
# cream is barely legible. Set SCRIM_ALPHA to 0.0 for white-on-paper instead.

## The title, punched in one word at a time. Kept as literal words rather than a
## translation key: it is the game's name, and the animation depends on knowing where
## the word boundaries are.
const TITLE_WORDS: PackedStringArray = ["Roll", "the", "Ball"]
## How long each partial title holds before the next word lands.
const WORD_HOLDS: PackedFloat32Array = [0.8, 0.4, 2.0]

const LOGO_FADE_IN: float = 1.2
const LOGO_HOLD: float = 1.0
const LOGO_FADE_OUT: float = 1.0
## Beat of bare paper between the logo leaving and the title starting.
const PAPER_BEAT: float = 0.4
const BODY_FADE_IN: float = 0.5
const SCRIM_ALPHA: float = 0.88

## Width the panel settles at. During the title animation the panel is allowed to
## shrink to its contents so it visibly grows with each word.
const PANEL_WIDTH: float = 620.0

const MAX_NAME_LENGTH: int = 20

## Fires when the menu is fully usable, whether the intro played out or was skipped.
signal intro_finished

## Static, so it survives the scene being reloaded when the player backs out of the
## level select. Reset on a fresh launch because statics don't persist across runs.
static var _intro_played: bool = false

@onready var panel: PanelContainer = %Panel
@onready var title_label: Label = %Title
@onready var body: VBoxContainer = %Body
@onready var name_field: LineEdit = %NameField
@onready var hint_label: Label = %HintLabel
@onready var play_button: Button = %PlayButton
@onready var settings_button: Button = %SettingsButton
@onready var quit_button: Button = %QuitButton
@onready var settings_menu: Control = $SettingsMenu

@onready var intro: Control = %Intro
@onready var scrim: ColorRect = %Scrim
@onready var logo_box: CenterContainer = %LogoBox

var _intro_running: bool = false


func _ready() -> void:
	name_field.max_length = MAX_NAME_LENGTH
	name_field.text = SaveManager.get_player_name()
	name_field.text_changed.connect(_on_name_changed)
	name_field.text_submitted.connect(_on_name_submitted)
	play_button.pressed.connect(_start)
	settings_button.pressed.connect(settings_menu.show)
	quit_button.pressed.connect(_on_quit_pressed)
	settings_menu.hide()
	_refresh()

	if _intro_played:
		_finish_intro()
	else:
		_intro_played = true
		_play_intro()


func _input(event: InputEvent) -> void:
	if not _intro_running:
		return
	# Any deliberate press skips ahead. Mouse motion doesn't count, or nudging the
	# mouse would rob the player of the opening.
	var pressed: bool = (event is InputEventKey and event.pressed and not event.echo) \
		or (event is InputEventMouseButton and event.pressed)
	if pressed:
		skip_intro()
		get_viewport().set_input_as_handled()


# ------------------------------------------------------------------- intro ----

func _play_intro() -> void:
	_intro_running = true

	# Empty paper to begin with: no panel, no logo.
	intro.show()
	scrim.color.a = 0.0
	logo_box.modulate.a = 0.0
	panel.hide()
	body.hide()
	title_label.text = ""
	# Released so the panel can hug the title and visibly grow with each word.
	panel.custom_minimum_size.x = 0.0

	await _fade(scrim, "color:a", SCRIM_ALPHA, LOGO_FADE_IN)
	if not _intro_running:
		return
	await _fade(logo_box, "modulate:a", 1.0, LOGO_FADE_IN)
	if not _intro_running:
		return
	await _wait(LOGO_HOLD)
	if not _intro_running:
		return

	# Logo and scrim leave together, so the paper is bare underneath.
	await _fade_both_out()
	if not _intro_running:
		return
	intro.hide()
	await _wait(PAPER_BEAT)
	if not _intro_running:
		return

	# The title punches in. The panel appears with it, sized to whatever is showing.
	panel.show()
	for i in TITLE_WORDS.size():
		title_label.text = title_up_to(i + 1)
		await _wait(WORD_HOLDS[i] if i < WORD_HOLDS.size() else 0.5)
		if not _intro_running:
			return

	_finish_intro()
	# The body arriving snaps the panel to full size; ease it in so it doesn't jolt.
	body.modulate.a = 0.0
	await _fade(body, "modulate:a", 1.0, BODY_FADE_IN)


## Cumulative title after `count` words: "Roll", "Roll the", "Roll the Ball".
static func title_up_to(count: int) -> String:
	var words: PackedStringArray = []
	for i in mini(count, TITLE_WORDS.size()):
		words.append(TITLE_WORDS[i])
	return " ".join(words)


## Jumps straight to a usable menu. Safe to call at any point, including mid-intro.
func skip_intro() -> void:
	_intro_running = false
	_finish_intro()


func _finish_intro() -> void:
	_intro_running = false
	intro.hide()
	panel.show()
	panel.custom_minimum_size.x = PANEL_WIDTH
	body.show()
	body.modulate.a = 1.0
	title_label.text = title_up_to(TITLE_WORDS.size())
	name_field.grab_focus()
	name_field.caret_column = name_field.text.length()
	_refresh()
	intro_finished.emit()


func _fade(node: CanvasItem, property: String, to: float, duration: float) -> void:
	var tween: Tween = create_tween()
	tween.tween_property(node, property, to, duration)
	await tween.finished


func _fade_both_out() -> void:
	var tween: Tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(logo_box, "modulate:a", 0.0, LOGO_FADE_OUT)
	tween.tween_property(scrim, "color:a", 0.0, LOGO_FADE_OUT)
	await tween.finished


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


# -------------------------------------------------------------------- menu ----

func _on_name_changed(_new_text: String) -> void:
	_refresh()


func _on_name_submitted(_new_text: String) -> void:
	# Enter starts the game, but only if the name would actually be accepted.
	if not play_button.disabled:
		_start()


func _refresh() -> void:
	var is_valid: bool = not name_field.text.strip_edges().is_empty()
	play_button.disabled = not is_valid
	hint_label.visible = not is_valid


func _start() -> void:
	# Switches the active save. A different name is a different player with its own
	# progress, so this may load an entirely different profile — see SaveManager.
	SaveManager.set_player_name(name_field.text)
	if SaveManager.has_progress():
		GameManager.go_to_level_select()
	else:
		# A player with nothing behind them goes straight into level 1, where Joe's
		# introduction is waiting. A level select showing one unlocked tile teaches
		# them nothing.
		GameManager.load_level(1)


func _on_quit_pressed() -> void:
	get_tree().quit()
