extends HBoxContainer
class_name KeyMapButton
# Instanced once per control by SettingsMenu's "Controls" tab. Set `mapped_action`
# right after instancing, before adding it to the tree:
#   var row := key_map_button_scene.instantiate()
#   row.mapped_action = "jump"
#   controls_list.add_child(row)
#
# Assumes the scene root (this script) is a row container (e.g. HBoxContainer:
# a Label for the action name + a Button showing/editing the current key) and
# that the editable Button child is named "KeyMapButton" — adjust the $KeyMapButton
# paths below if your scene is laid out differently.

@export var mapped_action: String = ""

var is_remapping: bool = false

func _ready() -> void:
	if mapped_action.is_empty():
		push_warning("KeyMapButton: mapped_action was never set")
		return
	_refresh_label()
	$KeyMapButton.pressed.connect(_on_button_pressed)

func _input(event: InputEvent) -> void:
	if not is_remapping:
		return
	# pressed + not echo: ignore key-release events and auto-repeat, so we only
	# ever bind the actual key-down the player intended.
	if event is InputEventKey and event.pressed and not event.echo:
		_apply_binding(event)
		is_remapping = false
		get_viewport().set_input_as_handled()

func _on_button_pressed() -> void:
	if is_remapping:
		return
	is_remapping = true
	$KeyMapButton.text = "..."
	SignalBus.remap_started.emit(mapped_action)

func _apply_binding(event: InputEvent) -> void:
	# Remove this action's existing bindings — it should only ever have the one just set.
	for existing_event in InputMap.action_get_events(mapped_action):
		InputMap.action_erase_event(mapped_action, existing_event)

	# Steal the key from any other action currently using it, so one key never maps
	# to two actions at once. Built-in "ui_*" actions are skipped so remapping a
	# gameplay control can't silently break menu navigation (Tab/Enter/Escape, etc.)
	# — drop this guard if you actually want gameplay binds able to override those.
	for action in InputMap.get_actions():
		if action.begins_with("ui_"):
			continue
		if InputMap.action_has_event(action, event):
			InputMap.action_erase_event(action, event)

	InputMap.action_add_event(mapped_action, event)
	_refresh_label(event)
	SignalBus.remap_ended.emit(mapped_action)

func _refresh_label(event: InputEvent = null) -> void:
	if event == null:
		var events: Array[InputEvent] = InputMap.action_get_events(mapped_action)
		event = events[0] if not events.is_empty() else null
	$KeyMapButton.text = event.as_text_key_label() if event else "Unbound"

# Optional: reserve Escape to cancel instead of binding it, a common convention
# in settings menus. Not included above since it silently changes the "any key"
# contract — add it yourself if you want it:
#   if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
#       is_remapping = false
#       _refresh_label()
#       SignalBus.remap_ended.emit(mapped_action)
#       get_viewport().set_input_as_handled()
#       return
