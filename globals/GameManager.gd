extends Node
# Autoload singleton — register as "GameManager", after SaveManager.
#
# Owns everything about the *current run*: which level is loaded, what mode it's
# in, how much of the time bank this attempt has burned, and the authoritative
# copy of the layout the player arranged. Query it directly for state; it
# broadcasts changes through SignalBus so it never needs to know its listeners.
#
#
# THE TIME BANK
# -------------
# There is one 60-second budget for the entire game (SaveManager.STARTING_BANK).
# The countdown the player sees during an attempt IS that bank draining:
#
#     displayed = bank_remaining - attempt_elapsed
#
# Reaching zero freezes physics, because charging that attempt would overdraw.
# Crucially, a failed attempt costs NOTHING — abandon it, return to EDIT, and the
# bank is untouched. The bank is only charged when the ball actually reaches the
# goal, and only ever for the player's *best* time on that level: clear a level
# you'd already beaten, in less time, and the difference is refunded (see
# SaveManager.charge_for_completion). Retries have to be free, or a run would be
# unrecoverable within a couple of minutes.
#
#
# WHY THE LAYOUT IS SNAPSHOTTED
# -----------------------------
# `_layout_snapshot` is taken the instant PLAY is pressed and re-applied whenever
# the player comes back to EDIT. Without it, returning to edit would leave props
# wherever the explosion flung them — because those props ARE the physics bodies.
# The snapshot is the arrangement; the bodies are a simulation of it.
#
# That same dict is what SaveManager writes to disk, and it is written on
# transitions only — entering PLAY, and leaving the level — never on a timer.
# During EDIT nothing changes unless the player drags something, so a periodic
# autosave would either rewrite identical bytes or catch a transform mid-drag.
#
#
# WHY PhysicsServer2D IS TOGGLED
# ------------------------------
# The observation modes (PAUSED / TIME_UP / COMPLETED) stop the 2D physics server
# outright instead of freezing each body. That preserves every velocity exactly,
# so resuming from a pause continues the simulation rather than dropping
# everything from a standstill, and it's one call instead of walking the tree.
#
# It is deliberately NOT used for EDIT: mouse picking on CollisionObject2D — how
# PlaceableObject receives `input_event` in order to be dragged — runs through
# the physics server. Switch it off in EDIT and props stop being clickable, so
# EDIT freezes bodies individually instead.

enum Mode {
	EDIT,       ## Arranging props. Bodies frozen individually, draggable.
	PLAY,       ## Simulating. The clock is running.
	PAUSED,     ## Player-requested freeze. Resumable, velocities intact.
	TIME_UP,    ## Countdown hit zero. Observation only; the way out is EDIT.
	COMPLETED,  ## Ball reached the goal. Bank already charged.
}

## Level scenes live at res://levels/level_01/level_01.tscn, and so on.
const LEVEL_PATH_TEMPLATE: String = "res://levels/level_%02d/level_%02d.tscn"
const MAIN_SCENE: String = "res://levels/main.tscn"
const LEVEL_SELECT_SCENE: String = "res://ui/menus/level_select/LevelSelect.tscn"

var current_mode: Mode = Mode.EDIT
## 0 means "no level loaded" (in a menu).
var current_level_id: int = 0
## Seconds burned by the attempt in progress. Only meaningful from PLAY onward.
var attempt_elapsed: float = 0.0

var _layout_snapshot: Dictionary = {}
var _level_container: Node = null
var _placed_objects: Node = null
var _current_level: Level = null
## Set by load_level() before the scene swap; consumed by notify_world_ready().
var _pending_level_id: int = 0


# ------------------------------------------------------------ level flow ----

## Called by Main._ready() once its containers exist. Main is what knows the
## scene layout, so it registers the two nodes rather than us hunting for them.
func register_world(level_container: Node, placed_objects: Node) -> void:
	_level_container = level_container
	_placed_objects = placed_objects


## Called by Main._ready() after register_world(). Kicks off whichever level
## load_level() queued up before the scene swap.
func notify_world_ready() -> void:
	if _pending_level_id > 0:
		_enter_level(_pending_level_id)
		_pending_level_id = 0
	elif current_level_id > 0:
		_enter_level(current_level_id)
	elif level_exists(1):
		# Running main.tscn straight from the editor (F6) with no level queued.
		# Falling back to level 1 makes the gameplay scene testable on its own.
		_enter_level(1)


## Entry point from the level select screen. Swaps to main.tscn if we aren't
## already there; Main._ready() then calls notify_world_ready() to finish the job.
func load_level(level_id: int) -> void:
	if not level_exists(level_id):
		push_error("GameManager: no scene for level %d at '%s'" % [level_id, level_scene_path(level_id)])
		return
	if not SaveManager.is_level_unlocked(level_id):
		push_warning("GameManager: level %d is still locked" % level_id)
		return

	_pending_level_id = level_id
	if _placed_objects != null and is_inside_tree():
		# Already inside main.tscn — reuse it instead of reloading the scene.
		notify_world_ready()
	else:
		get_tree().change_scene_to_file(MAIN_SCENE)


func _enter_level(level_id: int) -> void:
	if _level_container == null or _placed_objects == null:
		push_error("GameManager: register_world() was never called — can't enter a level")
		return

	_unload_current_level()
	current_level_id = level_id

	var scene: PackedScene = load(level_scene_path(level_id))
	if scene == null:
		push_error("GameManager: failed to load level %d" % level_id)
		return
	var instance: Node = scene.instantiate()
	if not instance is Level:
		push_error("GameManager: level %d's root is not a Level (see levels/Level.gd)" % level_id)
		instance.free()
		return
	_current_level = instance
	_level_container.add_child(_current_level)

	# Restore whatever the player had arranged here last time. A level they've
	# never opened simply comes back with an empty layout, which is not an error.
	var saved: Dictionary = SaveManager.load_layout(level_id)
	LevelLayout.apply(saved, _placed_objects)
	# Re-capture rather than trusting the file, so the in-memory snapshot always
	# reflects what actually made it into the tree (a prop whose scene has since
	# been deleted is dropped by apply() and must not linger in the snapshot).
	_layout_snapshot = LevelLayout.capture(_placed_objects)

	attempt_elapsed = 0.0
	_set_mode(Mode.EDIT)
	_reset_level()
	SignalBus.level_started.emit(level_id)


func return_to_level_select() -> void:
	if current_level_id > 0:
		_persist_layout()
		SignalBus.level_exited.emit(current_level_id)

	_unload_current_level()
	current_level_id = 0
	attempt_elapsed = 0.0
	_layout_snapshot = {}
	_level_container = null
	_placed_objects = null
	# Back to EDIT before the scene swap so the physics server is guaranteed
	# active again — leaving it off would silently freeze the next level.
	_set_mode(Mode.EDIT)
	get_tree().change_scene_to_file(LEVEL_SELECT_SCENE)


func restart_level() -> void:
	if current_level_id > 0:
		_enter_level(current_level_id)


func _unload_current_level() -> void:
	if _current_level != null and is_instance_valid(_current_level):
		_current_level.get_parent().remove_child(_current_level)
		_current_level.queue_free()
	_current_level = null
	if _placed_objects != null:
		LevelLayout.clear(_placed_objects)


## Asks the level to put its own dynamic contents back at the start line — the
## ball, mainly. Level.reset_level() does the work; we don't know what a ball is.
func _reset_level() -> void:
	if _current_level != null and is_instance_valid(_current_level):
		_current_level.reset_level()


## The Level node currently in the tree, or null in a menu. The HUD reads
## `available_props` off it to build the palette.
func get_current_level() -> Level:
	return _current_level if _current_level != null and is_instance_valid(_current_level) else null


## Where newly placed props belong (World/PlacedObjects). PaletteItem spawns into
## this rather than carrying its own NodePath to it.
func get_placed_objects_container() -> Node:
	return _placed_objects


# ---------------------------------------------------------- mode changes ----

## PLAY pressed. Snapshots the layout, persists it, and starts the clock.
func start_attempt() -> void:
	if current_mode != Mode.EDIT:
		return
	if current_level_id == 0:
		push_warning("GameManager: start_attempt() with no level loaded")
		return
	if SaveManager.get_time_bank() <= 0.0:
		# Nothing left to spend, so there is no attempt to be had.
		SignalBus.bank_exhausted.emit()
		return

	_layout_snapshot = LevelLayout.capture(_placed_objects)
	SaveManager.save_layout(current_level_id, _layout_snapshot)

	attempt_elapsed = 0.0
	_reset_level()
	_set_mode(Mode.PLAY)
	SignalBus.attempt_started.emit(current_level_id)


## The way back from every non-EDIT mode. Restores the snapshot, so props land
## exactly where the player left them rather than where physics left them.
func return_to_edit() -> void:
	if current_mode == Mode.EDIT:
		return
	var was_completed: bool = current_mode == Mode.COMPLETED

	_set_mode(Mode.EDIT)
	LevelLayout.apply(_layout_snapshot, _placed_objects)
	attempt_elapsed = 0.0
	_reset_level()

	if not was_completed:
		SignalBus.attempt_aborted.emit(current_level_id)


func pause() -> void:
	if current_mode == Mode.PLAY:
		_set_mode(Mode.PAUSED)


func resume() -> void:
	if current_mode == Mode.PAUSED:
		_set_mode(Mode.PLAY)


func toggle_pause() -> void:
	match current_mode:
		Mode.PLAY: pause()
		Mode.PAUSED: resume()
		_: pass # EDIT / TIME_UP / COMPLETED have nothing to pause


## Convenience for a single Play/Stop button.
func toggle_play() -> void:
	if current_mode == Mode.EDIT:
		start_attempt()
	else:
		return_to_edit()


## Called by the level's Goal area when the ball arrives.
func notify_goal_reached() -> void:
	if current_mode != Mode.PLAY:
		return

	var attempt_time: float = attempt_elapsed
	_set_mode(Mode.COMPLETED)

	# Charging happens here and nowhere else: only a real goal hit costs seconds.
	var bank_delta: float = SaveManager.charge_for_completion(current_level_id, attempt_time)
	if level_exists(current_level_id + 1):
		SaveManager.unlock_level(current_level_id + 1)

	SignalBus.goal_reached.emit(current_level_id, attempt_time, bank_delta)


func _set_mode(mode: Mode) -> void:
	if mode == current_mode:
		return
	current_mode = mode
	# Derived from the mode every single time, so the two can never desync.
	PhysicsServer2D.set_active(mode == Mode.EDIT or mode == Mode.PLAY)
	SignalBus.mode_changed.emit(current_mode)


# --------------------------------------------------------------- clock ----

func _physics_process(delta: float) -> void:
	# Fixed-step so the cost of an attempt doesn't depend on frame rate.
	if current_mode != Mode.PLAY:
		return

	attempt_elapsed += delta
	if get_time_remaining() > 0.0:
		return

	# Pin the clock exactly at the bank so the HUD can't render a negative.
	attempt_elapsed = SaveManager.get_time_bank()
	_set_mode(Mode.TIME_UP)
	SignalBus.time_ran_out.emit(current_level_id)


## What the HUD shows: the global bank minus what this attempt has burned.
func get_time_remaining() -> float:
	return maxf(0.0, SaveManager.get_time_bank() - attempt_elapsed)


# -------------------------------------------------------------- queries ----

func is_edit_mode() -> bool:
	return current_mode == Mode.EDIT


func is_play_mode() -> bool:
	return current_mode == Mode.PLAY


## True in every mode where the simulation is stopped mid-flight for the player
## to look at it. Props are not draggable here — only EDIT allows that.
func is_observing() -> bool:
	return current_mode in [Mode.PAUSED, Mode.TIME_UP, Mode.COMPLETED]


func level_scene_path(level_id: int) -> String:
	return LEVEL_PATH_TEMPLATE % [level_id, level_id]


func level_exists(level_id: int) -> bool:
	return level_id > 0 and ResourceLoader.exists(level_scene_path(level_id))


## Highest level id with a scene on disk. Lets the level select build its grid
## from what actually exists instead of a hardcoded count.
func count_available_levels() -> int:
	var count: int = 0
	while level_exists(count + 1):
		count += 1
	return count


# ------------------------------------------------------------ shutdown ----

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		# Cheap insurance: don't lose an arrangement because they alt-F4'd out of
		# EDIT instead of pressing PLAY or BACK.
		_persist_layout()


func _persist_layout() -> void:
	if current_level_id == 0:
		return
	# In EDIT the tree is the truth. Once an attempt has started the bodies have
	# moved, so the snapshot is the truth — writing live transforms then would
	# overwrite the player's arrangement with wherever physics threw it.
	var layout: Dictionary = _layout_snapshot
	if current_mode == Mode.EDIT and _placed_objects != null:
		layout = LevelLayout.capture(_placed_objects)
		_layout_snapshot = layout
	if not layout.is_empty():
		SaveManager.save_layout(current_level_id, layout)
