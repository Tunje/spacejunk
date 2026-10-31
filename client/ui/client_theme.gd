class_name ClientTheme extends RefCounted
## Shared colours and the overlay theme: off-white, mid grey and safety orange
## with foil-gold accents, on dark translucent panels.

const OFF_WHITE := Color(0.91, 0.90, 0.86)
const MID_GREY := Color(0.48, 0.50, 0.52)
const ORANGE := Color(0.95, 0.42, 0.08)
const GOLD := Color(0.83, 0.65, 0.25)
const PANEL := Color(0.07, 0.08, 0.10, 0.86)
const BUTTON := Color(0.19, 0.21, 0.24)
const BUTTON_HOVER := Color(0.27, 0.29, 0.33)


static func build() -> Theme:
	var built := Theme.new()
	built.default_font_size = 15
	built.set_stylebox("panel", "PanelContainer", _box(PANEL, 8, 10))
	built.set_stylebox("normal", "Button", _box(BUTTON, 4, 6))
	built.set_stylebox("hover", "Button", _box(BUTTON_HOVER, 4, 6))
	built.set_stylebox("pressed", "Button", _box(ORANGE, 4, 6))
	built.set_stylebox("hover_pressed", "Button", _box(ORANGE, 4, 6))
	built.set_stylebox("disabled", "Button", _box(BUTTON.darkened(0.45), 4, 6))
	built.set_color("font_color", "Button", OFF_WHITE)
	built.set_color("font_hover_color", "Button", Color.WHITE)
	built.set_color("font_pressed_color", "Button", Color.BLACK)
	built.set_color("font_hover_pressed_color", "Button", Color.BLACK)
	built.set_color("font_disabled_color", "Button", MID_GREY)
	built.set_color("font_color", "Label", OFF_WHITE)
	for state: String in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		built.set_stylebox(state, "CheckBox", StyleBoxEmpty.new())
	built.set_color("font_pressed_color", "CheckBox", OFF_WHITE)
	built.set_color("font_hover_pressed_color", "CheckBox", Color.WHITE)
	return built


## A panel that hides the scene behind it, for full screens.
static func solid_panel() -> StyleBoxFlat:
	return _box(Color(PANEL, 1.0), 8, 16)


static func _box(colour: Color, radius: int, margin: int) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = colour
	box.set_corner_radius_all(radius)
	box.set_content_margin_all(margin)
	return box
