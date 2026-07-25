extends Node
# Autoload singleton — register as "SignalBus", FIRST in Project Settings > Autoload
# (GameManager, SaveManager and LeaderboardAPI all emit through it, so it must exist
# before they do).
#
# Design rule of thumb:
# - Need to KNOW the current state right now?  -> ask the owning singleton directly
#   (e.g. GameManager.current_mode, GameManager.is_edit_mode()).
# - Need to REACT when something changes?      -> connect to a signal here instead.
# This keeps every listener decoupled from whoever raised the event — a
# PlaceableObject, a HUD button, or a menu screen can all listen the same way
# without holding a reference to GameManager/SaveManager/LeaderboardAPI.
#
# Deliberately NOT a signal: the live attempt countdown. It changes every frame,
# so the HUD reads GameManager.get_time_remaining() in _process instead of us
# emitting 60 signals a second.

# -- Run state --
signal mode_changed(new_mode) # GameManager.Mode — left untyped to avoid a cross-file enum typing edge case
signal level_started(level_id: int)          # a level scene finished loading and EDIT mode began
signal level_exited(level_id: int)           # player left the level (back to level select)
signal attempt_started(level_id: int)        # PLAY pressed; the clock is now running
signal attempt_aborted(level_id: int)        # back to EDIT without reaching the goal — costs nothing
signal goal_reached(level_id: int, attempt_time: float, bank_delta: float)
signal time_ran_out(level_id: int)           # countdown hit 0; physics frozen, observation only

# -- Time bank (the single global 60s budget) --
signal time_bank_changed(seconds_remaining: float)
signal bank_exhausted()                      # bank hit 0 — no seconds left to spend on any attempt

# -- Progression --
signal level_unlocked(level_id: int)
signal prop_unlocked(prop_id: String)
signal profile_loaded()

# -- Placed object lifecycle --
signal object_placed(obj: Node2D)
signal object_removed(obj: Node2D)

# -- Save / load (see globals/SaveManager.gd) --
signal layout_saved(level_id: int)
signal layout_save_failed(level_id: int)
signal layout_loaded(level_id: int)
signal layout_load_failed(level_id: int)
signal layout_deleted(level_id: int)
signal profile_save_failed()

# -- Leaderboard (see globals/LeaderboardAPI.gd) --
signal score_submitted(player_name: String, score: float)
signal score_submit_failed(error: String)
signal scores_received(scores: Variant)
signal scores_request_failed(error: String)

# -- Keybinding remap (see ui/menus/settings/KeyMapButton.gd) --
signal remap_started(action_name: String)  # SettingsMenu shows its "press any key" overlay
signal remap_ended(action_name: String)    # SettingsMenu hides it again