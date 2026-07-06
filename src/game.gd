class_name Game
extends Node2D
## Gameplay scene controller: builds the board from level data, routes screw
## taps through the Solver blocking rule, detaches empty plates, detects win.

signal level_cleared

const PlateScript := preload("res://src/entities/plate.gd")
const HudScript := preload("res://src/ui/hud.gd")
const WinOverlayScript := preload("res://src/ui/win_overlay.gd")

const BOARD_OFFSET := Vector2(0, 150)
const WIN_DELAY := 0.7

## Tests inject a level dictionary here before adding the node to the tree;
## when empty, the level comes from GameState.current_level.
var level_data: Dictionary = {}
var level_number: int = 1
var headless_test := false

var _board: Node2D
var _hud: Control
var _overlay: Control
## Live model mirror for Solver: array of {id, layer, points, screws}.
var _model: Array = []
var _plate_nodes := {}
var _screws_left := 0
var _won := false


func _ready() -> void:
	var game_state := get_node_or_null("/root/GameState")
	if level_data.is_empty():
		if game_state != null:
			level_number = game_state.current_level
		level_data = LevelLoader.load_level(level_number)
	elif level_data.has("id") and int(level_data["id"]) > 0:
		level_number = int(level_data["id"])

	_build_background()
	_board = Node2D.new()
	_board.name = "Board"
	_board.position = BOARD_OFFSET
	add_child(_board)
	_build_board()
	if not headless_test:
		_build_ui()


func _build_background() -> void:
	var bg_layer := CanvasLayer.new()
	bg_layer.layer = -1
	var bg := ColorRect.new()
	bg.color = Color("#35506b")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg_layer.add_child(bg)
	add_child(bg_layer)


func _build_board() -> void:
	_model.clear()
	_plate_nodes.clear()
	_screws_left = 0
	for plate_data: Dictionary in level_data.get("plates", []):
		_model.append({
			"id": int(plate_data["id"]),
			"layer": int(plate_data["layer"]),
			"points": plate_data["points"],
			"screws": Array(plate_data["screws"]),
		})
		var plate: Plate = PlateScript.new()
		_board.add_child(plate)
		plate.setup(plate_data)
		_plate_nodes[plate.plate_id] = plate
		for screw in plate.screw_nodes:
			screw.tapped.connect(_on_screw_tapped)
			_screws_left += 1


func _build_ui() -> void:
	var ui_layer := CanvasLayer.new()
	ui_layer.layer = 10
	add_child(ui_layer)

	_hud = HudScript.new()
	_hud.setup(level_number, _screws_left)
	_hud.restart_pressed.connect(_on_restart)
	_hud.menu_pressed.connect(_on_menu)
	ui_layer.add_child(_hud)

	_overlay = WinOverlayScript.new()
	_overlay.next_pressed.connect(_on_next_level)
	_overlay.select_pressed.connect(_on_menu)
	_overlay.visible = false
	ui_layer.add_child(_overlay)


func _on_screw_tapped(screw: Screw) -> void:
	if _won or screw.removed:
		return
	if Solver.is_screw_blocked(_model, screw.plate_id, screw.position):
		screw.play_blocked_feedback()
		return
	_remove_screw_from_model(screw.plate_id, screw.position)
	_screws_left -= 1
	if _hud != null:
		_hud.set_screws(_screws_left)
	var plate_empty := _plate_screws_left(screw.plate_id) == 0
	if plate_empty:
		_remove_plate_from_model(screw.plate_id)
	await screw.unscrew()
	if plate_empty:
		var plate: Plate = _plate_nodes.get(screw.plate_id)
		if plate != null:
			_plate_nodes.erase(screw.plate_id)
			plate.detach()
		if _model.is_empty() and not _won:
			_won = true
			_on_win()


func _remove_screw_from_model(plate_id: int, screw_pos: Vector2) -> void:
	for p: Dictionary in _model:
		if int(p["id"]) == plate_id:
			var screws: Array = p["screws"]
			for i in screws.size():
				if (screws[i] as Vector2).distance_to(screw_pos) < 1.0:
					screws.remove_at(i)
					return


func _plate_screws_left(plate_id: int) -> int:
	for p: Dictionary in _model:
		if int(p["id"]) == plate_id:
			return (p["screws"] as Array).size()
	return 0


func _remove_plate_from_model(plate_id: int) -> void:
	for i in _model.size():
		if int(_model[i]["id"]) == plate_id:
			_model.remove_at(i)
			return


func _on_win() -> void:
	var game_state := get_node_or_null("/root/GameState")
	if game_state != null:
		game_state.mark_completed(level_number)
	level_cleared.emit()
	if _overlay != null:
		await get_tree().create_timer(WIN_DELAY).timeout
		var is_last := level_number >= LevelLoader.level_count()
		_overlay.show_win(level_number, is_last)


func _on_restart() -> void:
	get_tree().reload_current_scene()


func _on_menu() -> void:
	var game_state := get_node_or_null("/root/GameState")
	if game_state != null:
		game_state.goto_level_select()


func _on_next_level() -> void:
	var game_state := get_node_or_null("/root/GameState")
	if game_state != null:
		game_state.start_level(level_number + 1)
