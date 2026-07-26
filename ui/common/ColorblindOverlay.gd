extends CanvasLayer
# Autoload scene — registered as "ColorblindOverlay".
#
# A full-screen shader pass sitting above everything, so the correction applies to
# the level, the HUD and every menu without any of them knowing about it. An
# autoload scene rather than a node per screen: an accessibility filter that only
# covers some screens is worse than none.
#
# Fully transparent and non-interactive when the mode is off, and the ColorRect is
# hidden outright so an unused filter costs nothing.

@onready var rect: ColorRect = $Filter


func _ready() -> void:
	# Above every other layer, including the HUD (which uses the default 0) and the
	# level background (-100).
	layer = 128
	SignalBus.colorblind_mode_changed.connect(_apply)
	_apply(Settings.colorblind_index)


func _apply(mode: int) -> void:
	rect.visible = mode > 0
	if not rect.visible:
		return
	var material: ShaderMaterial = rect.material
	if material != null:
		material.set_shader_parameter("mode", mode)
