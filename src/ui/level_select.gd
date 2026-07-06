extends Control
## Level select: scrollable 5-column grid of level buttons with lock state.

const COLUMNS := 5


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)

	var bg := ColorRect.new()
	bg.color = Color("#35506b")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var layout := VBoxContainer.new()
	layout.set_anchors_preset(Control.PRESET_FULL_RECT)
	layout.add_theme_constant_override("separation", 20)
	layout.offset_left = 24
	layout.offset_right = -24
	layout.offset_top = 24
	layout.offset_bottom = -24
	add_child(layout)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 20)
	layout.add_child(header)

	var back_btn := UiKit.make_button("<", Vector2(96, 96))
	back_btn.pressed.connect(_on_back)
	header.add_child(back_btn)

	var heading := UiKit.make_label("Select Level", 48)
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(heading)

	var header_pad := Control.new()
	header_pad.custom_minimum_size = Vector2(96, 0)
	header.add_child(header_pad)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	layout.add_child(scroll)

	var grid := GridContainer.new()
	grid.columns = COLUMNS
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 18)
	grid.add_theme_constant_override("v_separation", 18)
	scroll.add_child(grid)

	var game_state := get_node_or_null("/root/GameState")
	var unlocked: int = 1 if game_state == null else game_state.unlocked_up_to
	var count := LevelLoader.level_count()
	for n in range(1, count + 1):
		var btn := UiKit.make_button(str(n), Vector2(112, 112))
		if n > unlocked:
			btn.disabled = true
			btn.text = "🔒"
		else:
			var level_n := n
			btn.pressed.connect(func() -> void: _on_level(level_n))
		grid.add_child(btn)


func _on_level(n: int) -> void:
	var game_state := get_node_or_null("/root/GameState")
	if game_state != null:
		game_state.start_level(n)


func _on_back() -> void:
	var game_state := get_node_or_null("/root/GameState")
	if game_state != null:
		game_state.goto_title()
