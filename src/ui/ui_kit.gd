class_name UiKit
extends RefCounted
## Shared procedural UI styling (no asset files). Touch targets >= 88 px.

const ACCENT := Color("#e8a33d")
const PANEL_BG := Color("#243447")
const TEXT := Color("#e9eef3")


static func make_button(label: String, min_size := Vector2(220, 88)) -> Button:
	var btn := Button.new()
	btn.text = label
	btn.custom_minimum_size = min_size
	btn.add_theme_font_size_override("font_size", 34)
	btn.add_theme_color_override("font_color", TEXT)
	btn.add_theme_color_override("font_hover_color", Color.WHITE)

	var normal := StyleBoxFlat.new()
	normal.bg_color = Color("#3d5a80")
	normal.set_corner_radius_all(16)
	normal.set_content_margin_all(16)
	btn.add_theme_stylebox_override("normal", normal)

	var hover := normal.duplicate()
	hover.bg_color = Color("#4a6b96")
	btn.add_theme_stylebox_override("hover", hover)

	var pressed := normal.duplicate()
	pressed.bg_color = Color("#2c4763")
	btn.add_theme_stylebox_override("pressed", pressed)

	var disabled := normal.duplicate()
	disabled.bg_color = Color("#2a3646")
	btn.add_theme_stylebox_override("disabled", disabled)
	btn.add_theme_color_override("font_disabled_color", Color("#6b7885"))
	return btn


static func make_label(text: String, size: int, color := TEXT) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return label


static func make_panel() -> PanelContainer:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = PANEL_BG
	style.set_corner_radius_all(24)
	style.set_content_margin_all(40)
	panel.add_theme_stylebox_override("panel", style)
	return panel
