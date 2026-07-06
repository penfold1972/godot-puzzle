class_name Hud
extends Control
## Top bar during gameplay: level number, remaining screws, restart, menu.

signal restart_pressed
signal menu_pressed

var _moves_label: Label
var _level_number := 1
var _moves := 0


func setup(level_number: int, moves: int) -> void:
	_level_number = level_number
	_moves = moves


func _ready() -> void:
	set_anchors_preset(Control.PRESET_TOP_WIDE)
	custom_minimum_size = Vector2(0, 130)
	offset_bottom = 130
	# Let taps pass through everywhere except the actual buttons, so the
	# HUD strip never swallows input meant for screws near the top edge.
	mouse_filter = Control.MOUSE_FILTER_PASS

	var bar := HBoxContainer.new()
	bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	bar.custom_minimum_size = Vector2(0, 130)
	bar.add_theme_constant_override("separation", 14)
	bar.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(bar)

	var pad_left := Control.new()
	pad_left.custom_minimum_size = Vector2(10, 0)
	pad_left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(pad_left)

	var level_label := UiKit.make_label("Level %d" % _level_number, 40)
	level_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.add_child(level_label)

	_moves_label = UiKit.make_label("", 32, Color("#c9d2da"))
	_moves_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_moves_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.add_child(_moves_label)
	set_moves(_moves)

	var restart_btn := UiKit.make_button("↻", Vector2(96, 96))
	restart_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	restart_btn.pressed.connect(func() -> void: restart_pressed.emit())
	bar.add_child(restart_btn)

	var menu_btn := UiKit.make_button("≡", Vector2(96, 96))
	menu_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	menu_btn.pressed.connect(func() -> void: menu_pressed.emit())
	bar.add_child(menu_btn)

	var pad_right := Control.new()
	pad_right.custom_minimum_size = Vector2(10, 0)
	pad_right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(pad_right)


func set_moves(n: int) -> void:
	_moves = n
	if _moves_label != null:
		_moves_label.text = "Moves: %d" % n
