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
const CHECK_ICON_PX := 16


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
	built.set_stylebox("background", "ProgressBar", _box(Color(0.2, 0.22, 0.26), 3, 0))
	built.set_stylebox("fill", "ProgressBar", _box(OFF_WHITE, 3, 0))
	built.set_icon("unchecked", "CheckBox", _outline_box_icon())
	built.set_color("font_pressed_color", "CheckBox", OFF_WHITE)
	built.set_color("font_hover_pressed_color", "CheckBox", Color.WHITE)
	return built


## A panel that hides the scene behind it, for full screens.
static func solid_panel() -> StyleBoxFlat:
	var box := _box(Color(0.11, 0.12, 0.15), 8, 16)
	box.set_border_width_all(1)
	box.border_color = MID_GREY.darkened(0.2)
	return box


## A button whose order is under way, so it does not read as refused.
static func running_button() -> StyleBoxFlat:
	var box := _box(BUTTON, 4, 6)
	box.set_border_width_all(1)
	box.border_color = ORANGE
	return box


## An empty box that stays visible on dark panels.
static func _outline_box_icon() -> ImageTexture:
	var image := Image.create(CHECK_ICON_PX, CHECK_ICON_PX, false, Image.FORMAT_RGBA8)
	var edge := CHECK_ICON_PX - 1
	for along in range(CHECK_ICON_PX):
		for across: int in [1, 2, edge - 2, edge - 1]:
			if along >= 1 and along < edge:
				image.set_pixel(along, across, MID_GREY.lightened(0.25))
				image.set_pixel(across, along, MID_GREY.lightened(0.25))
	return ImageTexture.create_from_image(image)


static func _box(colour: Color, radius: int, margin: int) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = colour
	box.set_corner_radius_all(radius)
	box.set_content_margin_all(margin)
	return box
