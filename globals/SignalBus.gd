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

# -- Game state --
signal mode_changed(new_mode) # GameManager.Mode — left untyped to avoid a cross-file enum typing edge case

# -- Placed object lifecycle --
signal object_placed(obj: Node2D)
signal object_removed(obj: Node2D)

# -- Save / load (see globals/saveManager.gd) --
signal level_saved(level_name: String)
signal level_save_failed(level_name: String)
signal level_loaded(level_name: String)
signal level_load_failed(level_name: String)
signal level_deleted(level_name: String)

# -- Leaderboard (see globals/leaderboardAPI.gd) --
signal score_submitted(player_name: String, score: float)
signal score_submit_failed(error: String)
signal scores_received(scores: Variant)
signal scores_request_failed(error: String)
