class_name WinOverlay
extends Control
## Full-screen "Level Complete!" overlay with Next Level / Level Select.

const UiKitScript := preload("res://src/ui/ui_kit.gd")

signal next_pressed
signal select_pressed

var _title_label: Label
var _next_btn: Button


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)

	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var panel := UiKitScript.make_panel()
	center.add_child(panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 28)
	panel.add_child(box)

	_title_label = UiKitScript.make_label("Level Complete!", 52, UiKitScript.ACCENT)
	box.add_child(_title_label)

	_next_btn = UiKitScript.make_button("Next Level", Vector2(360, 96))
	_next_btn.pressed.connect(func() -> void: next_pressed.emit())
	box.add_child(_next_btn)

	var select_btn := UiKitScript.make_button("Level Select", Vector2(360, 96))
	select_btn.pressed.connect(func() -> void: select_pressed.emit())
	box.add_child(select_btn)


func show_win(level_number: int, is_last: bool) -> void:
	_title_label.text = "Level %d Complete!" % level_number
	_next_btn.visible = not is_last
	if is_last:
		_title_label.text = "All levels cleared!\nYou beat the game!"
	visible = true
	# Pop-in animation.
	scale = Vector2(0.85, 0.85)
	pivot_offset = size * 0.5
	modulate.a = 0.0
	var tw := create_tween().set_parallel(true)
	tw.tween_property(self, "scale", Vector2.ONE, 0.25) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "modulate:a", 1.0, 0.2)
