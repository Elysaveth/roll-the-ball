extends Node

@export var mapped_action: String = ""
var is_remapping: bool = false

func _ready():
	pass

func _input(event):
	if is_remapping and event is InputEventKey:
		_apply_binding(event)
		is_remapping = false

func _on_button_pressed(action_name):
	mapped_action = action_name
	is_remapping = true
# Update UI to indicate waiting for input

func _apply_binding(event):
	# Remove existing binding for this action
	
	var events: Array[InputEvent] = InputMap.action_get_events(mapped_action)
	for event_to_remove in events:
		InputMap.action_erase_event(mapped_action, event_to_remove)

	# Remove conflicting bindings (if new key is used by another action)
	for action in InputMap.get_actions():
		if InputMap.action_has_event(action, event):
			InputMap.action_erase_event(action, event)

	# Add new binding
	InputMap.action_add_event(mapped_action, event)
	_update_ui_label(event)
	
func _update_ui_label(event):
	$KeyMapButton.text = event.as_text_key_label()