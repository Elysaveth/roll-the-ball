extends Node
# Autoload singleton with list of signals — register as "SignalBus" before anything else
#
# Design:
# - To KNOW the current state		-> ask the owning singleton directly.
# - To REACT when something changes	-> connect to a signal here.
# This keeps every listener decoupled from whoever raised the event
#
# Exceptions: 
# - Active attempt countdown 		-> It changes every frame so it would overload with signals


# -- Run state --
@warning_ignore("unused_signal")
signal mode_changed(new_mode) 				# GameManager.Mode
@warning_ignore("unused_signal")
signal level_started(level_id: int)         # a level scene finished loading and EDIT mode began
@warning_ignore("unused_signal")
signal level_exited(level_id: int)
@warning_ignore("unused_signal")
signal attempt_started(level_id: int)       # PLAY pressed; clock is now running
@warning_ignore("unused_signal")
signal attempt_aborted(level_id: int)       # back to EDIT without reaching the goal
@warning_ignore("unused_signal")
signal goal_reached(level_id: int, attempt_time: float, bank_delta: float)
@warning_ignore("unused_signal")
signal time_ran_out(level_id: int)          # countdown hit 0; physics frozen

# -- Time bank --
@warning_ignore("unused_signal")
signal time_bank_changed(seconds_remaining: float)
@warning_ignore("unused_signal")
signal bank_exhausted()

# -- Player identity --
@warning_ignore("unused_signal")
signal player_name_changed(player_name: String)

# -- Preferences (see globals/Settings.gd) --
## Screens that build text in code rather than from a translation key in their
## .tscn need to rebuild it when this fires; Godot re-translates Control.text
@warning_ignore("unused_signal")
signal locale_changed(locale: String)

# -- Progression --
@warning_ignore("unused_signal")
signal level_unlocked(level_id: int)
@warning_ignore("unused_signal")
signal prop_unlocked(prop_id: String)
@warning_ignore("unused_signal")
signal profile_loaded()         			 # reload local user information

# -- Placed object lifecycle --
@warning_ignore("unused_signal")
signal object_placed(obj: Node2D)
@warning_ignore("unused_signal")
signal object_removed(obj: Node2D)
## Right-clicking a prop asks for its context menu. The HUD owns the menu.
## Left as Node2D so this file never depends on the global class cache.
@warning_ignore("unused_signal")
signal prop_context_requested(prop: Node2D)

# -- Save / load (see globals/SaveManager.gd) --
@warning_ignore("unused_signal")
signal layout_saved(level_id: int)
@warning_ignore("unused_signal")
signal layout_save_failed(level_id: int)
@warning_ignore("unused_signal")
signal layout_loaded(level_id: int)
@warning_ignore("unused_signal")
signal layout_load_failed(level_id: int)
@warning_ignore("unused_signal")
signal layout_deleted(level_id: int)
@warning_ignore("unused_signal")
signal profile_save_failed()

# -- Leaderboard (see globals/LeaderboardAPI.gd) --
# Every one of these carries the board it refers to, because there are many —
# one per level plus the general progress board — and SilentWolf reports them all
# through the same completion signal. Listeners must filter on `board`.
@warning_ignore("unused_signal")
signal score_submitted(board: String, player_name: String, score: float)
@warning_ignore("unused_signal")
signal score_submit_failed(board: String, error: String)
@warning_ignore("unused_signal")
signal scores_received(board: String, scores: Array)
@warning_ignore("unused_signal")
signal scores_request_failed(board: String, error: String)

# -- Keybinding remap (see ui/menus/settings/KeyMapButton.gd) --
@warning_ignore("unused_signal")
signal remap_started(action_name: String)  # SettingsMenu shows its "press any key" overlay
@warning_ignore("unused_signal")
signal remap_ended(action_name: String)    # SettingsMenu hides it again
@warning_ignore("unused_signal")
signal keybinding_changed(action_name: String) # a bind was actually replaced; persist it