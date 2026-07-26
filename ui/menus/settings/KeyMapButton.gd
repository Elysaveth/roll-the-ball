extends HBoxContainer
class_name KeyMapButton
# One rebindable control: a label naming the action and a button showing its key.
#
# Instanced by SettingsMenu, once per action, with `mapped_action` set BEFORE it
# enters the tree:
#     var row := key_map_row_scene.instantiate()
#     row.mapped_action = "rotate_prop"
#     controls_list.add_child(row)
#
# Scene layout: an ActionLabel and a Button named "KeyMapButton".

@export var mapped_action: String = ""

var is_remapping: bool = false

@onready var action_label: Label = $ActionLabel
@onready var key_button: Button = $KeyMapButton


func _ready() -> void:
	if mapped_action.is_empty():
		push_warning("KeyMapButton: mapped_action was never set")
		return
	action_label.text = action_display_name(mapped_action)
	key_button.pressed.connect(_on_button_pressed)
	_refresh_label()


## Human-readable name for an action. Prefers a translation keyed
## ACTION_<UPPER_NAME>, falling back to the action name with underscores turned
## into spaces — so an action added by anyone shows up readable without needing a
## translation entry first.
static func action_display_name(action: String) -> String:
	var key: String = "ACTION_" + action.to_upper()
	# TranslationServer.translate() returns a StringName, so it gets wrapped
	# everywhere in this file: mixing the two types in a ternary is a warning, and
	# StringName has no `%` operator for formatting.
	var translated: String = String(TranslationServer.translate(key))
	if translated != key:
		return translated
	return action.replace("_", " ").capitalize()


func _input(event: InputEvent) -> void:
	if not is_remapping:
		return

	# Escape cancels instead of being bound. Without this the player can bind
	# Escape to a gameplay action and lose the way out of every menu.
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_stop_remapping()
		get_viewport().set_input_as_handled()
		return

	# pressed + not echo: ignore key-release and auto-repeat, so only the actual
	# key-down the player intended gets bound.
	if event is InputEventKey and event.pressed and not event.echo:
		_apply_binding(event)
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed:
		# Mouse buttons are legitimate binds for a mouse-driven game.
		_apply_binding(event)
		get_viewport().set_input_as_handled()


func _on_button_pressed() -> void:
	if is_remapping:
		return
	is_remapping = true
	key_button.text = "..."
	SignalBus.remap_started.emit(mapped_action)


func _stop_remapping() -> void:
	is_remapping = false
	_refresh_label()
	SignalBus.remap_ended.emit(mapped_action)


func _apply_binding(event: InputEvent) -> void:
	# Remove this action's existing bindings — it only ever has the one just set.
	for existing in InputMap.action_get_events(mapped_action):
		InputMap.action_erase_event(mapped_action, existing)

	# Steal the key from any other action using it, so one key never drives two
	# actions. Built-in "ui_*" actions are skipped so rebinding a gameplay control
	# can't silently break menu navigation (Tab/Enter/Escape and friends).
	for action in InputMap.get_actions():
		if action.begins_with("ui_") or action == mapped_action:
			continue
		if InputMap.action_has_event(action, event):
			InputMap.action_erase_event(action, event)

	InputMap.action_add_event(mapped_action, event)
	_stop_remapping()
	SignalBus.keybinding_changed.emit(mapped_action)


func _refresh_label() -> void:
	var events: Array[InputEvent] = InputMap.action_get_events(mapped_action)
	if events.is_empty():
		key_button.text = String(TranslationServer.translate("CONTROLS_UNBOUND"))
	else:
		key_button.text = event_display_name(events[0])


## Static, so it goes through TranslationServer rather than tr() — tr() is a Node
## method and calling it from a static function doesn't compile.
static func event_display_name(event: InputEvent) -> String:
	if event is InputEventKey:
		return event.as_text_key_label()
	if event is InputEventMouseButton:
		return String(TranslationServer.translate("CONTROLS_MOUSE_BUTTON")) % event.button_index
	return event.as_text()
