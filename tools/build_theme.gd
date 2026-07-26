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

## Icons Godot expects as Texture2D rather than StyleBox. Anything left undefined
## silently falls back to Godot's built-in default theme, which is how the sliders
## and checkboxes ended up looking nothing like the rest of the UI.
const GRABBER_PATH: String = "res://assets/themes/grabber.png"
const CHECK_ON_PATH: String = "res://assets/themes/check_on.png"
const CHECK_OFF_PATH: String = "res://assets/themes/check_off.png"
const TOGGLE_ON_PATH: String = "res://assets/themes/toggle_on.png"
const TOGGLE_OFF_PATH: String = "res://assets/themes/toggle_off.png"
const ARROW_PATH: String = "res://assets/themes/arrow_down.png"
const ARROW_LEFT_PATH: String = "res://assets/themes/arrow_left.png"
const ARROW_RIGHT_PATH: String = "res://assets/themes/arrow_right.png"

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
	var missing: Array[String] = []
	for path in [TEXTURE_PATH, GRABBER_PATH, CHECK_ON_PATH, CHECK_OFF_PATH,
			TOGGLE_ON_PATH, TOGGLE_OFF_PATH, ARROW_PATH,
			ARROW_LEFT_PATH, ARROW_RIGHT_PATH]:
		if not ResourceLoader.exists(path):
			missing.append(path)

	if not missing.is_empty():
		_write_texture()
		_write_icons()
		print("\nWrote %d image(s) — now run --import, then this script again." % missing.size())
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


## The small fixed-size icons Godot wants as textures. Drawn in the ink tone
## directly (not greyscale) — unlike the 9-patch these are never restyled per
## state, so there's nothing to gain from tinting them at runtime.
func _write_icons() -> void:
	_save(_make_grabber(28), GRABBER_PATH)
	_save(_make_check_box(30, false), CHECK_OFF_PATH)
	_save(_make_check_box(30, true), CHECK_ON_PATH)
	_save(_make_toggle(56, 28, false), TOGGLE_OFF_PATH)
	_save(_make_toggle(56, 28, true), TOGGLE_ON_PATH)
	_save(_make_arrow(24), ARROW_PATH)
	_save(_make_side_arrow(24, false), ARROW_LEFT_PATH)
	_save(_make_side_arrow(24, true), ARROW_RIGHT_PATH)


func _save(image: Image, path: String) -> void:
	var error: int = image.save_png(path)
	if error != OK:
		push_error("build_theme: couldn't write %s (%s)" % [path, error_string(error)])


func _blank(width: int, height: int) -> Image:
	var image: Image = Image.create(width, height, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	return image


## Slider handle: an ink diamond, which reads at small sizes better than a circle
## and echoes the angular edges of the panels.
func _make_grabber(size: int) -> Image:
	var image: Image = _blank(size, size)
	var half: float = size * 0.5
	for y in size:
		for x in size:
			var d: float = absf(x + 0.5 - half) / half + absf(y + 0.5 - half) / half
			if d <= 0.72:
				image.set_pixel(x, y, INK)
			elif d <= 1.0:
				image.set_pixel(x, y, ACCENT)
	return image


## Checkbox: a hand-drawn-looking square with a tick when checked.
func _make_check_box(size: int, checked: bool) -> Image:
	var image: Image = _blank(size, size)
	var thickness: int = 3
	for y in size:
		for x in size:
			var on_frame: bool = x < thickness or y < thickness \
				or x >= size - thickness or y >= size - thickness
			if on_frame:
				image.set_pixel(x, y, INK)
			else:
				image.set_pixel(x, y, PAPER_LIGHT)

	if checked:
		# Two strokes forming a tick, drawn thick enough to survive downscaling.
		_stroke(image, Vector2(size * 0.24, size * 0.52), Vector2(size * 0.44, size * 0.72), 3, ACCENT)
		_stroke(image, Vector2(size * 0.44, size * 0.72), Vector2(size * 0.78, size * 0.26), 3, ACCENT)
	return image


## CheckButton's on/off switch: a pill with the knob at one end.
func _make_toggle(width: int, height: int, on: bool) -> Image:
	var image: Image = _blank(width, height)
	var radius: float = height * 0.5
	for y in height:
		for x in width:
			# Distance to the pill's spine, so the ends round off.
			var cx: float = clampf(x + 0.5, radius, width - radius)
			var d: float = Vector2(x + 0.5 - cx, y + 0.5 - radius).length()
			if d > radius - 0.5:
				continue
			image.set_pixel(x, y, INK if d > radius - 3.0 else (PAPER_EDGE if on else PAPER_LIGHT))

	var knob_x: float = width - radius if on else radius
	for y in height:
		for x in width:
			var d: float = Vector2(x + 0.5 - knob_x, y + 0.5 - radius).length()
			if d <= radius - 4.0:
				image.set_pixel(x, y, ACCENT if on else INK_SOFT)
	return image


## OptionButton's dropdown arrow.
func _make_arrow(size: int) -> Image:
	var image: Image = _blank(size, size)
	var rows: int = size / 2
	for row in rows:
		var span: int = rows - row
		var centre: int = size / 2
		for x in range(centre - span, centre + span):
			if x >= 0 and x < size:
				image.set_pixel(x, row + size / 4, INK)
	return image


## Left/right chevrons for the tab strip, which grows scroll arrows once the tabs
## overflow. Left unthemed these are stock Godot grey and stand out badly.
func _make_side_arrow(size: int, pointing_right: bool) -> Image:
	var image: Image = _blank(size, size)
	var columns: int = size / 2
	for column in columns:
		var span: int = columns - column
		var centre: int = size / 2
		var x: int = (size / 4) + column if pointing_right else (size - 1) - (size / 4) - column
		for y in range(centre - span, centre + span):
			if y >= 0 and y < size and x >= 0 and x < size:
				image.set_pixel(x, y, INK)
	return image


## Thick line between two points, for the tick mark.
func _stroke(image: Image, from: Vector2, to: Vector2, thickness: int, colour: Color) -> void:
	var steps: int = int(from.distance_to(to)) * 2
	for i in range(steps + 1):
		var point: Vector2 = from.lerp(to, float(i) / float(maxi(steps, 1)))
		for dy in range(-thickness, thickness + 1):
			for dx in range(-thickness, thickness + 1):
				if Vector2(dx, dy).length() > thickness:
					continue
				var px: int = int(point.x) + dx
				var py: int = int(point.y) + dy
				if px >= 0 and py >= 0 and px < image.get_width() and py < image.get_height():
					image.set_pixel(px, py, colour)


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
	_style_toggles(theme)
	_style_option_button_icons(theme)

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

	# Tab titles deliberately do NOT get a fixed font size, so they follow
	# default_font_size like everything else. Text scaling is an accessibility
	# feature: it has to affect ALL text, and a tab strip that overflows at large
	# sizes is the accepted cost — the strip scrolls, and its arrows are themed below.

	# Once the tabs do overflow, the strip grows scroll arrows. Unthemed they are
	# stock Godot grey.
	var left: Texture2D = load(ARROW_LEFT_PATH)
	var right: Texture2D = load(ARROW_RIGHT_PATH)
	for type_name in ["TabContainer", "TabBar"]:
		theme.set_icon("decrement", type_name, left)
		theme.set_icon("increment", type_name, right)
		theme.set_icon("decrement_highlight", type_name, left)
		theme.set_icon("increment_highlight", type_name, right)


func _style_slider(theme: Theme) -> void:
	var grabber: Texture2D = load(GRABBER_PATH)
	for type_name in ["HSlider", "VSlider"]:
		# Sliders are thin; torn edges at that scale read as noise, so the track and
		# fill stay flat.
		#
		# The track height comes from the stylebox's MINIMUM size, and a StyleBoxFlat
		# with no margins has none — which is why the line was invisible. Content
		# margins give it real thickness, and the tone is solid rather than a faint
		# tint so it reads against light paper.
		var track: StyleBoxFlat = _flat(Color(INK_SOFT, 0.75), 4)
		track.content_margin_top = 5.0
		track.content_margin_bottom = 5.0
		theme.set_stylebox("slider", type_name, track)

		var fill: StyleBoxFlat = _flat(ACCENT, 4)
		fill.content_margin_top = 5.0
		fill.content_margin_bottom = 5.0
		theme.set_stylebox("grabber_area", type_name, fill)

		var fill_hot: StyleBoxFlat = _flat(ACCENT.lightened(0.15), 4)
		fill_hot.content_margin_top = 5.0
		fill_hot.content_margin_bottom = 5.0
		theme.set_stylebox("grabber_area_highlight", type_name, fill_hot)

		# The handle is an ICON, not a stylebox — leaving it undefined is what made
		# the sliders look like stock Godot next to everything else.
		theme.set_icon("grabber", type_name, grabber)
		theme.set_icon("grabber_highlight", type_name, grabber)
		theme.set_icon("grabber_disabled", type_name, grabber)
		theme.set_constant("center_grabber", type_name, 1)


## CheckButton and CheckBox are icon-driven too. Same story as the slider handle:
## anything not defined here comes from Godot's built-in theme and looks foreign.
func _style_toggles(theme: Theme) -> void:
	var toggle_on: Texture2D = load(TOGGLE_ON_PATH)
	var toggle_off: Texture2D = load(TOGGLE_OFF_PATH)
	var check_on: Texture2D = load(CHECK_ON_PATH)
	var check_off: Texture2D = load(CHECK_OFF_PATH)

	for type_name in ["CheckButton", "CheckBox"]:
		var on: Texture2D = toggle_on if type_name == "CheckButton" else check_on
		var off: Texture2D = toggle_off if type_name == "CheckButton" else check_off
		theme.set_icon("checked", type_name, on)
		theme.set_icon("unchecked", type_name, off)
		theme.set_icon("checked_disabled", type_name, on)
		theme.set_icon("unchecked_disabled", type_name, off)
		# Radio variants share the artwork; nothing in the game uses them yet, but
		# leaving them undefined would mix two visual languages in one row.
		theme.set_icon("radio_checked", type_name, on)
		theme.set_icon("radio_unchecked", type_name, off)
		theme.set_icon("radio_checked_disabled", type_name, on)
		theme.set_icon("radio_unchecked_disabled", type_name, off)

		# No torn frame on toggles in ANY state. The switch artwork already carries
		# the styling, and wrapping a jagged outline around it looked wrong — the
		# frame belongs to things that are cards (buttons, panels), not to a row of
		# checkboxes sitting directly on the paper.
		for state in ["normal", "hover", "pressed", "disabled", "focus"]:
			theme.set_stylebox(state, type_name, _flat(Color(0, 0, 0, 0)))
		theme.set_color("font_color", type_name, INK)
		theme.set_color("font_hover_color", type_name, INK)
		theme.set_color("font_pressed_color", type_name, INK)
		theme.set_color("font_disabled_color", type_name, Color(INK_SOFT, 0.45))
		theme.set_constant("h_separation", type_name, 12)


func _style_option_button_icons(theme: Theme) -> void:
	# The dropdown chevron is an icon; the stock one is a different grey entirely.
	theme.set_icon("arrow", "OptionButton", load(ARROW_PATH))
	theme.set_constant("arrow_margin", "OptionButton", 8)


func _style_scrollbars(theme: Theme) -> void:
	var left: Texture2D = load(ARROW_LEFT_PATH)
	var right: Texture2D = load(ARROW_RIGHT_PATH)
	var down: Texture2D = load(ARROW_PATH)
	for type_name in ["VScrollBar", "HScrollBar"]:
		theme.set_icon("decrement", type_name, left if type_name == "HScrollBar" else down)
		theme.set_icon("increment", type_name, right if type_name == "HScrollBar" else down)
		theme.set_stylebox("scroll", type_name, _flat(Color(INK_SOFT, 0.18), 3))
		theme.set_stylebox("grabber", type_name, _flat(Color(INK_SOFT, 0.55), 3))
		theme.set_stylebox("grabber_highlight", type_name, _flat(Color(INK, 0.7), 3))
		theme.set_stylebox("grabber_pressed", type_name, _flat(ACCENT, 3))
