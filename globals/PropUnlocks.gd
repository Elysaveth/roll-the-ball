extends Node
# Autoload singleton — register as "PropUnlocks", after SignalBus.
#
# THE one place that says which props exist and when the player gets them. To add a
# prop: build its .tscn, then add one line below. To move it earlier or later in the
# game: change one number. Nothing else needs touching — the palette, the profile and
# the tests all read this table.
#
#   "prop_id": {"level": N, "scene": "res://..."}
#
# `level` is the level the prop becomes available ON, so a prop at level 1 is something
# a brand new player already has. A prop is kept forever once reached, which is what Joe
# promises after the first clear.
#
# Reaching a level is what grants its props — SaveManager.is_prop_unlocked() compares
# against the highest level unlocked. Blueprints crafted in the workshop go through
# SaveManager.unlock_prop() instead and are stored in the profile, so a prop can arrive
# either way and neither route can revoke the other.

## Everything is in the player's hands by level 5. Two or three arrive per level, in
## rough order of how much thinking they demand, so each of the first five levels has
## something new to show off.
const PROPS: Dictionary = {
	# --- 1: starting kit — enough to bridge a gap, which is all level 1 asks --
	"hielo": {"level": 1, "scene": "res://entities/props/hielo/hielo.tscn"},
	"madera": {"level": 1, "scene": "res://entities/props/madera/madera.tscn"},

	# --- 2: weight, durability and a gentle bounce ---------------------------
	"metal": {"level": 2, "scene": "res://entities/props/metal/metal.tscn"},
	"moai": {"level": 2, "scene": "res://entities/props/moai/moai.tscn"},
	"muelle": {"level": 2, "scene": "res://entities/props/muelle/muelle.tscn"},

	# --- 3: redirection, and the first thing that goes bang ------------------
	"pinball": {"level": 3, "scene": "res://entities/props/pinball/pinball.tscn"},
	"canon": {"level": 3, "scene": "res://entities/props/canon/canon.tscn"},
	"bomb": {"level": 3, "scene": "res://entities/props/bomb/bomb.tscn"},

	# --- 4: bigger blasts and self-propulsion --------------------------------
	"dinamita": {"level": 4, "scene": "res://entities/props/dinamita/dinamita.tscn"},
	"cohete_little": {"level": 4, "scene": "res://entities/props/cohete_little/cohete_little.tscn"},
	"tntminecraft": {"level": 4, "scene": "res://entities/props/tntminecraft/tntminecraft.tscn"},

	# --- 5: the clever stuff. Portals arrive together — one half is useless ---
	"cohete_big": {"level": 5, "scene": "res://entities/props/cohete_big/cohete_big.tscn"},
	"portal_in": {"level": 5, "scene": "res://entities/props/portal_in/portal_in.tscn"},
	"portal_out": {"level": 5, "scene": "res://entities/props/portal_out/portal_out.tscn"},
}


func all_prop_ids() -> Array[String]:
	var ids: Array[String] = []
	for prop_id in PROPS:
		ids.append(str(prop_id))
	return ids


## The level `prop_id` becomes available on. Unknown props report level 1 rather than
## being unreachable, so a prop someone forgot to list still shows up instead of
## silently vanishing from the game.
func unlock_level_for(prop_id: String) -> int:
	if not PROPS.has(prop_id):
		push_warning("PropUnlocks: '%s' is not listed; treating it as a starting prop" % prop_id)
		return 1
	return int(PROPS[prop_id].get("level", 1))


func scene_path_for(prop_id: String) -> String:
	if not PROPS.has(prop_id):
		return ""
	return str(PROPS[prop_id].get("scene", ""))


## Everything a player who has reached `level_id` owns, in unlock order so the palette
## reads as a progression rather than a jumble.
func props_unlocked_at(level_id: int) -> Array[String]:
	var ids: Array[String] = []
	for prop_id in PROPS:
		if unlock_level_for(prop_id) <= level_id:
			ids.append(str(prop_id))
	ids.sort_custom(_by_unlock_order)
	return ids


## Just the props that arrive ON this level — the hook for a "new prop!" flourish, and
## what Joe means by "some levels hand you a new object".
func props_introduced_at(level_id: int) -> Array[String]:
	var ids: Array[String] = []
	for prop_id in PROPS:
		if unlock_level_for(prop_id) == level_id:
			ids.append(str(prop_id))
	ids.sort()
	return ids


## Loadable scenes for everything the current player owns. Used by the palette when a
## level doesn't restrict what it offers.
##
## Every prop is considered and SaveManager decides — it must NOT pre-filter by level.
## Doing that made the level curve the outer limit, so debug mode and workshop
## blueprints, which both grant props outside the curve, could never widen the palette
## past whatever level the player had reached.
func unlocked_scenes() -> Array[PackedScene]:
	var scenes: Array[PackedScene] = []
	var ordered: Array[String] = all_prop_ids()
	ordered.sort_custom(_by_unlock_order)
	for prop_id in ordered:
		if not SaveManager.is_prop_unlocked(prop_id):
			continue
		var path: String = scene_path_for(prop_id)
		if path.is_empty() or not ResourceLoader.exists(path):
			push_warning("PropUnlocks: '%s' has no loadable scene at '%s'" % [prop_id, path])
			continue
		scenes.append(load(path))
	return scenes


func _by_unlock_order(a: String, b: String) -> bool:
	var level_a: int = unlock_level_for(a)
	var level_b: int = unlock_level_for(b)
	if level_a == level_b:
		return a < b
	return level_a < level_b
