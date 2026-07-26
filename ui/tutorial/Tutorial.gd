extends CanvasLayer
class_name Tutorial
# Joe's introduction, played the first time a player with nothing behind them opens
# level 1.
#
# It builds the level up as he talks rather than explaining a screen that's already
# full: the ball and its platform appear when he mentions the ball, the basket when he
# mentions the basket, the clock when he mentions time, the palette when he mentions
# dragging props in. When he's done he fades out, the balloon pops, and level 1 is
# simply there, complete and playable.
#
# Self-contained: it decides for itself whether to run by listening for level_started,
# so nothing in GameManager knows the tutorial exists.
#
# The reveal paths below are node names inside levels/level_01. That coupling is
# deliberate and narrow — the tutorial is about level 1 specifically — and a renamed
# node produces a warning rather than a silent no-op.

const TUTORIAL_LEVEL: int = 1

## Everything hidden before the first line. The level starts as bare background.
const STAGED_PARTS: PackedStringArray = [
	"Geometry/LeftLedge",
	"Geometry/Floor",
	"Geometry/BasketFloor",
	"Geometry/BasketWallLeft",
	"Geometry/BasketWallRight",
	"Goal",
]

## What Joe says, and what appears as he says it.
const STEPS: Array = [
	{"text": "TUTORIAL_WELCOME"},
	{"text": "TUTORIAL_BALL", "reveal": ["Geometry/LeftLedge"], "spawn_ball": true},
	{
		"text": "TUTORIAL_BASKET",
		"reveal": ["Geometry/Floor", "Geometry/BasketFloor",
			"Geometry/BasketWallLeft", "Geometry/BasketWallRight", "Goal"],
	},
	{"text": "TUTORIAL_TIME", "show_clock": true},
	{"text": "TUTORIAL_PROPS", "show_palette": true},
	{"text": "TUTORIAL_GOODBYE"},
]

const FADE_IN: float = 0.5
const JOE_FADE_OUT: float = 1.0
const BALLOON_POP: float = 0.22

signal tutorial_finished

@onready var root: Control = $Root
@onready var joe: TextureRect = $Root/Joe
@onready var balloon: PanelContainer = $Root/Balloon
@onready var text_label: Label = $Root/Balloon/Margin/VBox/Text
@onready var continue_label: Label = $Root/Balloon/Margin/VBox/Continue

var _step: int = -1
var _running: bool = false
## True while a transition is playing, so a fast clicker can't skip a reveal.
var _busy: bool = false


func _ready() -> void:
	hide()
	SignalBus.level_started.connect(_on_level_started)


func _on_level_started(level_id: int) -> void:
	if level_id != TUTORIAL_LEVEL:
		return
	# Anyone who has finished anything, or already sat through this, goes straight to
	# playing. `tutorial_seen` matters on its own: without it, failing level 1 twenty
	# times would mean twenty introductions.
	if SaveManager.has_seen_tutorial() or SaveManager.has_progress():
		return
	_begin()


func _begin() -> void:
	var level: Level = GameManager.get_current_level()
	var hud: HUDController = _find_hud()
	if level == null:
		return

	_running = true
	show()
	# Bare background: no level, no ball, no HUD furniture.
	for path in STAGED_PARTS:
		level.set_part_visible(path, false)
	level.despawn_ball()
	if hud != null:
		hud.stage_for_tutorial()

	joe.modulate.a = 0.0
	balloon.modulate.a = 0.0
	balloon.scale = Vector2.ONE
	balloon.pivot_offset = balloon.size * 0.5
	_advance()

	var tween: Tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(joe, "modulate:a", 1.0, FADE_IN)
	tween.tween_property(balloon, "modulate:a", 1.0, FADE_IN)


func _input(event: InputEvent) -> void:
	if not _running:
		return
	if event.is_action_pressed("toggle_pause"):
		# Escape skips the whole thing. Someone replaying on a new name shouldn't be
		# made to sit through it.
		_finish()
		get_viewport().set_input_as_handled()
		return
	if _busy:
		return
	var pressed: bool = (event is InputEventKey and event.pressed and not event.echo) \
		or (event is InputEventMouseButton and event.pressed)
	if pressed:
		_advance()
		get_viewport().set_input_as_handled()


func _advance() -> void:
	_step += 1
	if _step >= STEPS.size():
		_bow_out()
		return

	var step: Dictionary = STEPS[_step]
	text_label.text = tr(str(step.get("text", "")))
	# The last line has nothing to click through to.
	continue_label.visible = _step < STEPS.size() - 1

	var level: Level = GameManager.get_current_level()
	if level != null:
		for path in step.get("reveal", []):
			level.set_part_visible(str(path), true)
		if bool(step.get("spawn_ball", false)):
			level.reset_level()

	var hud: HUDController = _find_hud()
	if hud != null:
		if bool(step.get("show_clock", false)):
			hud.set_clock_visible(true)
		if bool(step.get("show_palette", false)):
			hud.set_palette_visible(true)


## Joe leaves first and the balloon stays until he's gone, then pops.
func _bow_out() -> void:
	_busy = true
	continue_label.hide()

	var leaving: Tween = create_tween()
	leaving.tween_property(joe, "modulate:a", 0.0, JOE_FADE_OUT)
	await leaving.finished

	balloon.pivot_offset = balloon.size * 0.5
	var pop: Tween = create_tween()
	pop.set_parallel(true)
	pop.tween_property(balloon, "scale", Vector2(1.15, 1.15), BALLOON_POP * 0.4)
	pop.tween_property(balloon, "modulate:a", 0.0, BALLOON_POP)
	await pop.finished

	_finish()


## Hands the finished level over. Reached both by playing out and by skipping, so
## everything staged has to be restored here rather than at the end of _bow_out.
func _finish() -> void:
	if not _running:
		return
	_running = false
	_busy = false
	hide()

	var level: Level = GameManager.get_current_level()
	if level != null:
		for path in STAGED_PARTS:
			level.set_part_visible(path, true)
		if level.get_ball() == null:
			level.reset_level()

	var hud: HUDController = _find_hud()
	if hud != null:
		hud.unstage_from_tutorial()

	SaveManager.mark_tutorial_seen()
	tutorial_finished.emit()


func _find_hud() -> HUDController:
	# Reached through the group rather than a path, so main.tscn can be rearranged.
	for node in get_tree().get_nodes_in_group("hud"):
		if node is HUDController:
			return node
	return null


## Exposed for the test suite and for a "replay tutorial" button later.
func force_start() -> void:
	if _running:
		return
	_step = -1
	_begin()
