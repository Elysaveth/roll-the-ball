extends SceneTree
# Generates the game's UI theme: a torn-paper 9-patch texture plus the Theme
# resource that uses it. Re-runnable — tweak the palette here and rebuild.
#
#   godot --headless --path . --script res://tools/build_theme.gd   # writes the PNG
#   godot --headless --path . --import                              # imports it
#   godot --headless --path . --script res://tools/build_theme.gd   # writes the Theme
#
# Two passes because a freshly written PNG can't be load()ed as a Texture2D until
# Godot's importer has seen it. The script detects which pass it's on.
#
#
# PALETTE
# -------
# Sampled from the two chosen backgrounds (tools/sample_palette.gd), so the UI
# sits on the paper rather than fighting it:
#   Paper Texture6 (menus)  centre #e8dbc9, stained edges #e2c9af, darkest #bc9a7f
#   Paper Texture7 (levels) centre #d2cbbb
# The ink and accent tones are chosen to harmonise with those, not sampled.
#
#
# WHY ONE TEXTURE AND NOT SEVEN
# -----------------------------
# The texture is drawn in greyscale — white interior, dark rim — and each state
# tints it with StyleBoxTexture.modulate_color. So hover/pressed/disabled all
# reuse one image, the rim stays proportionally darker than whatever fill it's
# given, and changing a colour never means redrawing art.

const TEXTURE_PATH: String = "res://assets/themes/jagged_panel.png"
const THEME_PATH: String = "res://assets/themes/main_theme.tres"

# -- Palette ------------------------------------------------------------------
const PAPER_LIGHT := Color("f4eee2") # brightest paper — panels, button faces
const PAPER := Color("e8dbc9")       # menu paper centre
const PAPER_EDGE := Color("e2c9af")  # stained edge tone — hover, highlights
const SEPIA := Color("bc9a7f")       # deepest paper tone — pressed
const INK := Color("3a2f26")         # text
const INK_SOFT := Color("6b5a4a")    # secondary and disabled text
const ACCENT := Color("a6472e")      # oxidised red — focus, selection
const ACCENT_WARN := Color("b5722c") # warnings, "name required"

# -- Torn edge geometry -------------------------------------------------------
## The middle strips of a 9-patch TILE rather than stretch, so the jag keeps its
## scale on a button and on a full-screen panel alike. That only works if the jag
## is periodic and the strip length is a whole number of periods:
## SIZE - 2*MARGIN must be divisible by PERIOD.
const SIZE: int = 96
const MARGIN: int = 24
const PERIOD: int = 12
const AMPLITUDE: int = 7
const RIM: int = 4

const FILL := Color(1.0, 1.0, 1.0, 1.0)
## Kept dark so that tinting by a light fill still yields a legible outline.
const RIM_TONE := Color(0.30, 0.28, 0.26, 1.0)


func _initialize() -> void:
	if not ResourceLoader.exists(TEXTURE_PATH):
		_write_texture()
		print("\nWrote %s — now run --import, then this script again." % TEXTURE_PATH)
		quit()
		return
	_write_theme()
	quit()


# ------------------------------------------------------------------ texture ----

func _write_texture() -> void:
	var image: Image = Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))

	for y in SIZE:
		for x in SIZE:
			var left: int = _jag(y)
			var right: int = SIZE - 1 - _jag(y + PERIOD / 2)
			var top: int = _jag(x)
			var bottom: int = SIZE - 1 - _jag(x + PERIOD / 2)

			if x < left or x > right or y < top or y > bottom:
				continue # torn away
			var on_rim: bool = x < left + RIM or x > right - RIM or y < top + RIM or y > bottom - RIM
			image.set_pixel(x, y, RIM_TONE if on_rim else FILL)

	var error: int = image.save_png(TEXTURE_PATH)
	if error != OK:
		push_error("build_theme: couldn't write %s (%s)" % [TEXTURE_PATH, error_string(error)])


## Triangle wave: 0 at the period boundaries, AMPLITUDE in the middle. Continuous
## across boundaries, which is what makes the edge strips tile seamlessly.
func _jag(t: int) -> int:
	var phase: int = posmod(t, PERIOD)
	var half: int = PERIOD / 2
	var ramp: float = float(phase) / float(half) if phase < half else float(PERIOD - phase) / float(half)
	return int(round(AMPLITUDE * ramp))


# -------------------------------------------------------------------- theme ----

func _write_theme() -> void:
	var texture: Texture2D = load(TEXTURE_PATH)
	if texture == null:
		push_error("build_theme: %s failed to load as a texture" % TEXTURE_PATH)
		return

	var theme: Theme = Theme.new()
	theme.default_font_size = 22

	_style_buttons(theme, texture, "Button")
	_style_buttons(theme, texture, "OptionButton")
	_style_panels(theme, texture)
	_style_popup(theme, texture)
	_style_line_edit(theme, texture)
	_style_labels(theme)
	_style_tabs(theme, texture)
	_style_slider(theme)
	_style_scrollbars(theme)

	var error: int = ResourceSaver.save(theme, THEME_PATH)
	if error != OK:
		push_error("build_theme: couldn't save %s (%s)" % [THEME_PATH, error_string(error)])
		return
	print("Wrote %s" % THEME_PATH)


## A torn-paper box tinted to `tint`, with `padding` of interior breathing room.
func _box(texture: Texture2D, tint: Color, padding: int = 12) -> StyleBoxTexture:
	var box: StyleBoxTexture = StyleBoxTexture.new()
	box.texture = texture
	box.set_texture_margin_all(MARGIN)
	# TILE, not STRETCH: stretching would smear the teeth into streaks on any
	# control wider or taller than the source texture.
	box.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_TILE
	box.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_TILE
	box.modulate_color = tint
	# Content starts inside the torn rim, so text never sits on a tooth.
	box.set_content_margin_all(padding)
	return box


func _flat(fill: Color, radius: int = 0) -> StyleBoxFlat:
	var box: StyleBoxFlat = StyleBoxFlat.new()
	box.bg_color = fill
	box.set_corner_radius_all(radius)
	return box


func _style_buttons(theme: Theme, texture: Texture2D, type_name: String) -> void:
	theme.set_stylebox("normal", type_name, _box(texture, PAPER_LIGHT))
	theme.set_stylebox("hover", type_name, _box(texture, PAPER_EDGE))
	theme.set_stylebox("pressed", type_name, _box(texture, SEPIA))
	theme.set_stylebox("disabled", type_name, _box(texture, PAPER.darkened(0.05)))

	var focus: StyleBoxTexture = _box(texture, ACCENT)
	theme.set_stylebox("focus", type_name, focus)

	theme.set_color("font_color", type_name, INK)
	theme.set_color("font_hover_color", type_name, INK)
	theme.set_color("font_pressed_color", type_name, PAPER_LIGHT)
	theme.set_color("font_focus_color", type_name, PAPER_LIGHT)
	theme.set_color("font_disabled_color", type_name, Color(INK_SOFT, 0.45))
	theme.set_font_size("font_size", type_name, 24)


func _style_panels(theme: Theme, texture: Texture2D) -> void:
	theme.set_stylebox("panel", "PanelContainer", _box(texture, PAPER_LIGHT, 20))
	theme.set_stylebox("panel", "Panel", _box(texture, PAPER_LIGHT, 20))


func _style_popup(theme: Theme, texture: Texture2D) -> void:
	theme.set_stylebox("panel", "PopupMenu", _box(texture, PAPER_LIGHT, 10))
	# The hover highlight sits INSIDE the torn frame, so a plain fill is right —
	# a second set of teeth in there would just look noisy.
	theme.set_stylebox("hover", "PopupMenu", _flat(PAPER_EDGE, 2))
	theme.set_stylebox("separator", "PopupMenu", _flat(Color(INK_SOFT, 0.35)))
	theme.set_color("font_color", "PopupMenu", INK)
	theme.set_color("font_hover_color", "PopupMenu", INK)
	theme.set_color("font_disabled_color", "PopupMenu", Color(INK_SOFT, 0.45))
	theme.set_color("font_separator_color", "PopupMenu", INK_SOFT)
	theme.set_font_size("font_size", "PopupMenu", 22)
	theme.set_constant("v_separation", "PopupMenu", 8)


func _style_line_edit(theme: Theme, texture: Texture2D) -> void:
	theme.set_stylebox("normal", "LineEdit", _box(texture, PAPER, 14))
	theme.set_stylebox("focus", "LineEdit", _box(texture, PAPER_LIGHT, 14))
	theme.set_color("font_color", "LineEdit", INK)
	theme.set_color("font_placeholder_color", "LineEdit", Color(INK_SOFT, 0.6))
	theme.set_color("caret_color", "LineEdit", ACCENT)
	theme.set_color("selection_color", "LineEdit", Color(ACCENT, 0.3))


func _style_labels(theme: Theme) -> void:
	theme.set_color("font_color", "Label", INK)
	# Paper is light, so a dark outline would muddy the text; a pale shadow keeps
	# labels readable over the stained corners of the menu background instead.
	theme.set_color("font_shadow_color", "Label", Color(PAPER_LIGHT, 0.0))


func _style_tabs(theme: Theme, texture: Texture2D) -> void:
	theme.set_stylebox("panel", "TabContainer", _box(texture, PAPER_LIGHT, 16))
	theme.set_stylebox("tab_selected", "TabContainer", _box(texture, PAPER_LIGHT, 10))
	theme.set_stylebox("tab_unselected", "TabContainer", _box(texture, SEPIA, 10))
	theme.set_stylebox("tab_hovered", "TabContainer", _box(texture, PAPER_EDGE, 10))
	theme.set_color("font_selected_color", "TabContainer", INK)
	theme.set_color("font_unselected_color", "TabContainer", Color(PAPER_LIGHT, 0.85))
	theme.set_color("font_hovered_color", "TabContainer", INK)


func _style_slider(theme: Theme) -> void:
	# Sliders are thin; torn edges at that scale read as noise, so these stay flat.
	theme.set_stylebox("slider", "HSlider", _flat(Color(INK_SOFT, 0.3), 3))
	theme.set_stylebox("grabber_area", "HSlider", _flat(ACCENT, 3))
	theme.set_stylebox("grabber_area_highlight", "HSlider", _flat(ACCENT.lightened(0.15), 3))


func _style_scrollbars(theme: Theme) -> void:
	for type_name in ["VScrollBar", "HScrollBar"]:
		theme.set_stylebox("scroll", type_name, _flat(Color(INK_SOFT, 0.18), 3))
		theme.set_stylebox("grabber", type_name, _flat(Color(INK_SOFT, 0.55), 3))
		theme.set_stylebox("grabber_highlight", type_name, _flat(Color(INK, 0.7), 3))
		theme.set_stylebox("grabber_pressed", type_name, _flat(ACCENT, 3))
