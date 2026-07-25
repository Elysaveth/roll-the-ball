extends Node
# Autoload singleton — register as "SaveManager", after SignalBus.
#
# Pure persistence. It holds no opinion about game rules and never reads the
# scene tree — GameManager hands it data, it writes bytes. Two separate things
# live here, and keeping them separate matters:
#
#   PROFILE  (user://profile.json)      one per player. The global time bank,
#                                       per-level best times, how far they've
#                                       unlocked, which props they own.
#   LAYOUTS  (user://saves/level_N.json) one per level. Where the player left
#                                       their props, in LevelLayout format.
#
# The profile is kept in memory after load and written on every mutation — it's
# a few hundred bytes and mutations are rare (finishing a level, unlocking a
# prop), so there is no reason to batch them. Layouts are bigger and change
# while dragging, so GameManager decides when those hit disk (on PLAY, and on
# leaving the level) rather than on a timer. See GameManager for why.

const SAVE_DIR: String = "user://saves/"
const PROFILE_PATH: String = "user://profile.json"

## The whole game is played out of this one budget, in seconds.
const STARTING_BANK: float = 60.0

const PROFILE_VERSION: int = 1

var _profile: Dictionary = {}


func _ready() -> void:
	if not DirAccess.dir_exists_absolute(SAVE_DIR):
		DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	load_profile()


# ---------------------------------------------------------------- profile ----

func load_profile() -> void:
	_profile = _default_profile()
	var parsed: Variant = _read_json(PROFILE_PATH)
	if parsed is Dictionary:
		# Merge rather than replace, so a profile written by an older build that
		# lacks newer keys still boots with sane defaults for them.
		for key in parsed:
			_profile[key] = parsed[key]
	SignalBus.profile_loaded.emit()


func save_profile() -> bool:
	if _write_json(PROFILE_PATH, _profile):
		return true
	SignalBus.profile_save_failed.emit()
	return false


## What a brand-new player starts with. Currently every implemented prop, so the
## game is playable end to end — trim this down as the unlock curve gets
## designed, and hand the rest out through unlock_prop() / the workshop.
const STARTING_PROPS: Array[String] = ["hielo", "moai", "pinball", "bomb"]


func _default_profile() -> Dictionary:
	return {
		"profile_version": PROFILE_VERSION,
		"time_bank": STARTING_BANK,
		"highest_unlocked_level": 1,
		"best_times": {},        # keys are level ids AS STRINGS — see _best_times()
		"unlocked_props": STARTING_PROPS.duplicate(),
		"materials": {},         # material id -> count, for blueprint crafting later
		"broken_counts": {},     # what the player has destroyed, feeds materials
	}


# ------------------------------------------------------------- time bank ----

func get_time_bank() -> float:
	return float(_profile.get("time_bank", STARTING_BANK))


## Charges (or refunds) the bank for completing `level_id` in `attempt_time`
## seconds, and records the new best time. Returns the signed change to the
## bank: negative when seconds were spent, positive when the player beat their
## old time and got seconds back, zero when they finished but didn't improve.
##
## The rule: you pay for a level exactly once, at your best time. Beat that time
## and the difference comes back. Fail an attempt and you pay nothing at all —
## GameManager only calls this on an actual goal hit.
func charge_for_completion(level_id: int, attempt_time: float) -> float:
	var previous: float = get_best_time(level_id)
	var delta: float = 0.0

	if previous < 0.0:
		delta = -attempt_time                    # first clear: spend
	elif attempt_time < previous:
		delta = previous - attempt_time          # improved: refund the difference
	# else: already paid for this level at a better time, nothing changes hands

	if previous < 0.0 or attempt_time < previous:
		_best_times()[str(level_id)] = attempt_time

	if not is_zero_approx(delta):
		_set_time_bank(get_time_bank() + delta)

	save_profile()
	return delta


func _set_time_bank(seconds: float) -> void:
	# Refunds can never exceed what was spent, so the bank can't naturally climb
	# past its starting value — clamped anyway so a bad save can't inflate it.
	var clamped: float = clampf(seconds, 0.0, STARTING_BANK)
	if is_equal_approx(clamped, get_time_bank()):
		return
	_profile["time_bank"] = clamped
	SignalBus.time_bank_changed.emit(clamped)
	if is_zero_approx(clamped):
		SignalBus.bank_exhausted.emit()


## Escape hatch for a future "reset run" / new game+ button.
func reset_time_bank() -> void:
	_set_time_bank(STARTING_BANK)
	save_profile()


# ----------------------------------------------------------- best times ----

## Returns the player's best time for `level_id`, or -1.0 if never completed.
func get_best_time(level_id: int) -> float:
	return float(_best_times().get(str(level_id), -1.0))


func has_completed(level_id: int) -> bool:
	return get_best_time(level_id) >= 0.0


func _best_times() -> Dictionary:
	# JSON has no integer keys, so level ids round-trip as strings. Everything
	# goes through here so that conversion lives in exactly one place.
	if not _profile.get("best_times") is Dictionary:
		_profile["best_times"] = {}
	return _profile["best_times"]


# ---------------------------------------------------------- progression ----

func get_highest_unlocked_level() -> int:
	return int(_profile.get("highest_unlocked_level", 1))


func is_level_unlocked(level_id: int) -> bool:
	return level_id <= get_highest_unlocked_level()


func unlock_level(level_id: int) -> void:
	if level_id <= get_highest_unlocked_level():
		return
	_profile["highest_unlocked_level"] = level_id
	save_profile()
	SignalBus.level_unlocked.emit(level_id)


func get_unlocked_props() -> Array:
	return _profile.get("unlocked_props", [])


func is_prop_unlocked(prop_id: String) -> bool:
	return prop_id in get_unlocked_props()


func unlock_prop(prop_id: String) -> void:
	if is_prop_unlocked(prop_id):
		return
	get_unlocked_props().append(prop_id)
	save_profile()
	SignalBus.prop_unlocked.emit(prop_id)


# ------------------------------------------------------------- materials ----
# Groundwork for the workshop's blueprint crafting. Nothing calls these yet;
# props will report their own destruction through record_break() when breakable
# props land.

func record_break(prop_id: String, material_id: String = "", amount: int = 1) -> void:
	var breaks: Dictionary = _profile.get("broken_counts", {})
	breaks[prop_id] = int(breaks.get(prop_id, 0)) + 1
	_profile["broken_counts"] = breaks
	if not material_id.is_empty():
		add_material(material_id, amount)
	else:
		save_profile()


func add_material(material_id: String, amount: int = 1) -> void:
	var mats: Dictionary = _profile.get("materials", {})
	mats[material_id] = int(mats.get(material_id, 0)) + amount
	_profile["materials"] = mats
	save_profile()


func get_material_count(material_id: String) -> int:
	return int(_profile.get("materials", {}).get(material_id, 0))


func spend_materials(costs: Dictionary) -> bool:
	for material_id in costs:
		if get_material_count(material_id) < int(costs[material_id]):
			return false
	var mats: Dictionary = _profile.get("materials", {})
	for material_id in costs:
		mats[material_id] = int(mats[material_id]) - int(costs[material_id])
	_profile["materials"] = mats
	save_profile()
	return true


# --------------------------------------------------------------- layouts ----

## `layout` must be a dict produced by LevelLayout.capture().
func save_layout(level_id: int, layout: Dictionary) -> bool:
	var payload: Dictionary = layout.duplicate(true)
	payload["level_id"] = level_id
	payload["saved_at"] = Time.get_datetime_string_from_system()

	if _write_json(_layout_path(level_id), payload):
		SignalBus.layout_saved.emit(level_id)
		return true
	SignalBus.layout_save_failed.emit(level_id)
	return false


## Returns a LevelLayout-format dict, or an empty one if there's no save yet.
## A fresh level with nothing placed is not an error, so callers can apply the
## result unconditionally.
func load_layout(level_id: int) -> Dictionary:
	var path: String = _layout_path(level_id)
	if not FileAccess.file_exists(path):
		SignalBus.layout_load_failed.emit(level_id)
		return {"format_version": LevelLayout.FORMAT_VERSION, "objects": []}

	var parsed: Variant = _read_json(path)
	if not parsed is Dictionary:
		push_error("SaveManager: layout for level %d is corrupted" % level_id)
		SignalBus.layout_load_failed.emit(level_id)
		return {"format_version": LevelLayout.FORMAT_VERSION, "objects": []}

	SignalBus.layout_loaded.emit(level_id)
	return parsed


func has_layout(level_id: int) -> bool:
	return FileAccess.file_exists(_layout_path(level_id))


func delete_layout(level_id: int) -> void:
	var path: String = _layout_path(level_id)
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
		SignalBus.layout_deleted.emit(level_id)


func list_saved_layouts() -> Array[int]:
	var ids: Array[int] = []
	var dir: DirAccess = DirAccess.open(SAVE_DIR)
	if dir == null:
		return ids
	dir.list_dir_begin()
	var file_name: String = dir.get_next()
	while file_name != "":
		if file_name.begins_with("level_") and file_name.ends_with(".json"):
			var id_text: String = file_name.trim_prefix("level_").trim_suffix(".json")
			if id_text.is_valid_int():
				ids.append(int(id_text))
		file_name = dir.get_next()
	dir.list_dir_end()
	ids.sort()
	return ids


## Wipes everything — profile and every layout. For a "delete save data" button.
func erase_all_data() -> void:
	for level_id in list_saved_layouts():
		delete_layout(level_id)
	if FileAccess.file_exists(PROFILE_PATH):
		DirAccess.remove_absolute(PROFILE_PATH)
	load_profile()


func _layout_path(level_id: int) -> String:
	return "%slevel_%d.json" % [SAVE_DIR, level_id]


# ------------------------------------------------------------------- io ----

func _write_json(path: String, data: Dictionary) -> bool:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("SaveManager: couldn't write '%s' (%s)" % [
			path, error_string(FileAccess.get_open_error())
		])
		return false
	file.store_string(JSON.stringify(data, "\t"))
	file.close()
	return true


func _read_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("SaveManager: couldn't read '%s' (%s)" % [
			path, error_string(FileAccess.get_open_error())
		])
		return null
	var content: String = file.get_as_text()
	file.close()
	return JSON.parse_string(content)