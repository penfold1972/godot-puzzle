extends Control
## Title screen: game name, Play, Quit (desktop only).


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)

	var bg := ColorRect.new()
	bg.color = Color("#35506b")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 40)
	center.add_child(box)

	var title := UiKit.make_label("SCREW\nPUZZLE", 96, UiKit.ACCENT)
	box.add_child(title)

	var subtitle := UiKit.make_label("Unscrew everything. Drop every plate.", 28, Color("#c9d2da"))
	box.add_child(subtitle)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 30)
	box.add_child(spacer)

	var play_btn := UiKit.make_button("Play", Vector2(360, 110))
	play_btn.pressed.connect(_on_play)
	box.add_child(play_btn)

	var quit_btn := UiKit.make_button("Quit", Vector2(360, 96))
	quit_btn.pressed.connect(func() -> void: get_tree().quit())
	quit_btn.visible = not OS.has_feature("mobile")
	box.add_child(quit_btn)


func _on_play() -> void:
	var game_state := get_node_or_null("/root/GameState")
	if game_state != null:
		game_state.goto_level_select()
