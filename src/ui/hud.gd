class_name Hud
extends Control
## Top bar during gameplay: level number, remaining screws, restart, menu.

signal restart_pressed
signal menu_pressed

var _screws_label: Label
var _level_number := 1
var _screws := 0


func setup(level_number: int, screws: int) -> void:
	_level_number = level_number
	_screws = screws


func _ready() -> void:
	set_anchors_preset(Control.PRESET_TOP_WIDE)
	custom_minimum_size = Vector2(0, 130)

	var bar := HBoxContainer.new()
	bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	bar.custom_minimum_size = Vector2(0, 130)
	bar.add_theme_constant_override("separation", 14)
	add_child(bar)

	var pad_left := Control.new()
	pad_left.custom_minimum_size = Vector2(10, 0)
	bar.add_child(pad_left)

	var level_label := UiKit.make_label("Level %d" % _level_number, 40)
	level_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.add_child(level_label)

	_screws_label = UiKit.make_label("", 32, Color("#c9d2da"))
	_screws_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_screws_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.add_child(_screws_label)
	set_screws(_screws)

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
	bar.add_child(pad_right)


func set_screws(n: int) -> void:
	_screws = n
	if _screws_label != null:
		_screws_label.text = "Screws: %d" % n
