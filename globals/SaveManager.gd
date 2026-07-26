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

# PROGRESS IS PER PLAYER NAME
# ---------------------------
# Everything a player has earned lives under user://players/<slug>/, so changing the
# name in the main menu switches to a different save entirely: a new name starts from
# nothing, and typing the old one back restores it untouched.
#
# That is a leaderboard-integrity requirement, not a convenience. With one shared
# profile, somebody could clear the game once and then submit that same finished run
# under any number of names, filling every board with a single afternoon's work.
#
# LAYOUTS are per player too. They are progress — the arrangement that produced a
# best time — so a fresh name must not inherit the previous one's solved levels.

const PLAYERS_DIR: String = "user://players/"
## Remembers who was playing so the menu can prefill the field next launch.
const LAST_PLAYER_PATH: String = "user://last_player.cfg"

## Pre-per-player locations, migrated once on first run of this build.
const LEGACY_SAVE_DIR: String = "user://saves/"
const LEGACY_PROFILE_PATH: String = "user://profile.json"

## The whole game is played out of this one budget, in seconds.
const STARTING_BANK: float = 60.0

## The level the tutorial and its follow-up belong to.
const FIRST_LEVEL: int = 1

const PROFILE_VERSION: int = 2

var _profile: Dictionary = {}
## Empty until a name has been entered. Nothing is written to disk before then.
var _active_name: String = ""
var _active_slug: String = ""


func _ready() -> void:
	_migrate_legacy_save()
	var last: String = _read_last_player()
	if last.is_empty():
		# No player yet: defaults in memory so the menus have something to show.
		_profile = _default_profile()
	else:
		switch_player(last)


# --------------------------------------------------------------- identity ----

## Loads the profile belonging to `player_name`, creating it if this is a new name.
## Idempotent, so re-entering the same name is free.
func switch_player(player_name: String) -> void:
	var trimmed: String = player_name.strip_edges()
	if trimmed == _active_name and not _profile.is_empty():
		return

	_active_name = trimmed
	_active_slug = _slug_for(trimmed) if not trimmed.is_empty() else ""
	if not _active_slug.is_empty():
		DirAccess.make_dir_recursive_absolute(_player_saves_dir())
	load_profile()
	if not trimmed.is_empty():
		_profile["player_name"] = trimmed
		_write_last_player(trimmed)
		save_profile()
	SignalBus.player_name_changed.emit(trimmed)


## Filesystem-safe directory name for a player.
##
## A readable prefix plus a hash of the exact name. The prefix alone would collide —
## "A b" and "A_b" sanitise identically, and two players would silently share one
## save — while the hash alone would make user:// unreadable to a human.
## Case matters, because the leaderboard treats "Liz" and "liz" as different players.
func _slug_for(player_name: String) -> String:
	var safe: String = ""
	for character in player_name.to_lower():
		if (character >= "a" and character <= "z") or (character >= "0" and character <= "9"):
			safe += character
		else:
			safe += "_"
	safe = safe.substr(0, 24)
	if safe.is_empty():
		safe = "player"
	return "%s-%s" % [safe, player_name.sha256_text().substr(0, 8)]


func _player_dir() -> String:
	return PLAYERS_DIR + _active_slug + "/"


func _player_saves_dir() -> String:
	return _player_dir() + "saves/"


func _profile_path() -> String:
	return _player_dir() + "profile.json"


func _read_last_player() -> String:
	var config: ConfigFile = ConfigFile.new()
	if config.load(LAST_PLAYER_PATH) != OK:
		return ""
	return str(config.get_value("player", "name", ""))


func _write_last_player(player_name: String) -> void:
	var config: ConfigFile = ConfigFile.new()
	config.set_value("player", "name", player_name)
	config.save(LAST_PLAYER_PATH)


## Moves a pre-per-player save into the new layout, once, so nobody loses progress
## to the restructure. Keyed on the name that profile already carried.
func _migrate_legacy_save() -> void:
	if not FileAccess.file_exists(LEGACY_PROFILE_PATH):
		return
	var parsed: Variant = _read_json(LEGACY_PROFILE_PATH)
	if not parsed is Dictionary:
		DirAccess.remove_absolute(LEGACY_PROFILE_PATH)
		return

	var legacy: Dictionary = parsed
	var owner_name: String = str(legacy.get("player_name", "")).strip_edges()
	if owner_name.is_empty():
		# Anonymous progress can't be attributed to anyone, so there is nothing to
		# migrate it into.
		DirAccess.remove_absolute(LEGACY_PROFILE_PATH)
		return

	var slug: String = _slug_for(owner_name)
	var destination: String = PLAYERS_DIR + slug + "/"
	DirAccess.make_dir_recursive_absolute(destination + "saves/")
	if not FileAccess.file_exists(destination + "profile.json"):
		_write_json(destination + "profile.json", legacy)

	var dir: DirAccess = DirAccess.open(LEGACY_SAVE_DIR)
	if dir != null:
		dir.list_dir_begin()
		var file_name: String = dir.get_next()
		while file_name != "":
			if file_name.ends_with(".json"):
				var from: String = LEGACY_SAVE_DIR + file_name
				var to: String = destination + "saves/" + file_name
				if not FileAccess.file_exists(to):
					DirAccess.copy_absolute(from, to)
				DirAccess.remove_absolute(from)
			file_name = dir.get_next()
		dir.list_dir_end()

	DirAccess.remove_absolute(LEGACY_PROFILE_PATH)
	_write_last_player(owner_name)
	print("SaveManager: migrated legacy progress for '%s'" % owner_name)


# ---------------------------------------------------------------- profile ----

func load_profile() -> void:
	_profile = _default_profile()
	if _active_slug.is_empty():
		SignalBus.profile_loaded.emit()
		return
	var parsed: Variant = _read_json(_profile_path())
	if parsed is Dictionary:
		# Merge rather than replace, so a profile written by an older build that
		# lacks newer keys still boots with sane defaults for them.
		for key in parsed:
			_profile[key] = parsed[key]
	SignalBus.profile_loaded.emit()


func save_profile() -> bool:
	# Nothing is written until a player has identified themselves; there is no
	# anonymous save to write to.
	if _active_slug.is_empty():
		return false
	if _write_json(_profile_path(), _profile):
		return true
	SignalBus.profile_save_failed.emit()
	return false


func _default_profile() -> Dictionary:
	return {
		"profile_version": PROFILE_VERSION,
		"player_name": "",       # required before playing; used for leaderboards
		"time_bank": STARTING_BANK,
		"highest_unlocked_level": 1,
		"best_times": {},        # keys are level ids AS STRINGS — see _best_times()
		# Only props granted OUTSIDE the level progression live here — workshop
		# blueprints. What a level hands out is derived from PropUnlocks, so the
		# unlock curve can be retuned without rewriting anybody's save.
		"unlocked_props": [],
		"materials": {},         # material id -> count, for blueprint crafting later
		"broken_counts": {},     # what the player has destroyed, feeds materials
		"tutorial_seen": false,  # so it doesn't replay after every failed attempt
		"outro_seen": false,     # Joe's follow-up, shown once on the first clear
	}


# ----------------------------------------------------------- player name ----
# Collected by the main menu before the player can start, because a score with
# no name attached is useless to a leaderboard.

func get_player_name() -> String:
	return _active_name


func has_player_name() -> bool:
	return not _active_name.is_empty()


## Switching the name switches the whole save. Progress is not edited or cleared —
## it stays where it is under the old name and comes back if that name is typed again.
func set_player_name(value: String) -> void:
	switch_player(value)


## Whether this player has finished anything yet. Used to decide if they need the
## tutorial and whether Play goes straight into level 1.
func has_progress() -> bool:
	return get_furthest_completed_level() > 0


func has_seen_tutorial() -> bool:
	return bool(_profile.get("tutorial_seen", false))


func mark_tutorial_seen() -> void:
	if has_seen_tutorial():
		return
	_profile["tutorial_seen"] = true
	save_profile()


func has_seen_outro() -> bool:
	return bool(_profile.get("outro_seen", false))


func mark_outro_seen() -> void:
	if has_seen_outro():
		return
	_profile["outro_seen"] = true
	save_profile()


## Whether this completion should bring Joe back for his follow-up: the first time the
## opening level is cleared, once ever.
##
## A negative bank_delta is what "first clear" means — the bank is only ever charged on
## a level the player had not finished before (see charge_for_completion).
##
## Lives here rather than in the tutorial so the HUD can ask the same question without
## depending on a class name, which is exactly the sort of thing Godot's script class
## cache drops after a fresh checkout.
func needs_first_clear_outro(level_id: int, bank_delta: float) -> bool:
	return level_id == FIRST_LEVEL and bank_delta < 0.0 and not has_seen_outro()


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


## Highest level id the player has actually finished — what the general
## leaderboard ranks on. 0 when they haven't cleared anything yet.
func get_furthest_completed_level() -> int:
	var furthest: int = 0
	for key in _best_times():
		var level_id: int = int(key)
		if level_id > furthest:
			furthest = level_id
	return furthest


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
	# Debug mode opens everything that exists, so the content team can jump to any
	# level without grinding to it. Checked here rather than at each call site so
	# nothing can forget it.
	if Settings.debug_unlock_all:
		return true
	return level_id <= get_highest_unlocked_level()


func unlock_level(level_id: int) -> void:
	if level_id <= get_highest_unlocked_level():
		return
	_profile["highest_unlocked_level"] = level_id
	save_profile()
	SignalBus.level_unlocked.emit(level_id)


func get_unlocked_props() -> Array:
	return _profile.get("unlocked_props", [])


## A prop is owned once its unlock level has been reached, or once a blueprint has
## granted it outright. Two independent routes, and neither can revoke the other —
## which is what makes "you keep anything you unlock" true.
func is_prop_unlocked(prop_id: String) -> bool:
	if Settings.debug_unlock_all:
		return true
	if prop_id in get_unlocked_props():
		return true
	return PropUnlocks.unlock_level_for(prop_id) <= get_highest_unlocked_level()


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
	if _active_slug.is_empty():
		return false
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
	if _active_slug.is_empty():
		return false
	return FileAccess.file_exists(_layout_path(level_id))


func delete_layout(level_id: int) -> void:
	var path: String = _layout_path(level_id)
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
		SignalBus.layout_deleted.emit(level_id)


func list_saved_layouts() -> Array[int]:
	var ids: Array[int] = []
	if _active_slug.is_empty():
		return ids
	var dir: DirAccess = DirAccess.open(_player_saves_dir())
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
	if not _active_slug.is_empty() and FileAccess.file_exists(_profile_path()):
		DirAccess.remove_absolute(_profile_path())
	load_profile()


func _layout_path(level_id: int) -> String:
	return "%slevel_%d.json" % [_player_saves_dir(), level_id]


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