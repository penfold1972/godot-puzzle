class_name Game
extends Node2D
## v2 gameplay controller: pin-board peg-solitaire.
## Two-tap move: tap a screw (lifts "in hand", world freezes) then tap a
## destination hole (screw pins every aligned covering plate, world resumes).
## Tapping the in-hand screw again cancels back into its origin hole.
## Plates: >=2 screws frozen static, 1 screw swings on a PinJoint2D,
## 0 screws falls. Win when every plate has fallen off screen.

signal level_cleared

const PlateBodyScript := preload("res://src/entities/plate_body.gd")
const BoardHoleScript := preload("res://src/entities/board_hole.gd")
const ScrewScript := preload("res://src/entities/screw.gd")
const LevelLoaderScript := preload("res://src/core/level_loader.gd")
const RulesScript := preload("res://src/core/rules.gd")
const HudScript := preload("res://src/ui/hud.gd")
const WinOverlayScript := preload("res://src/ui/win_overlay.gd")

const BOARD_OFFSET := Vector2(0, 150)
const WIN_DELAY := 0.7

enum State { IDLE, IN_HAND, WON }

## Tests inject a parsed level dictionary here before adding the node to the
## tree; when empty, the level comes from GameState.current_level.
var level_data: Dictionary = {}
var level_number: int = 1
var headless_test := false

var _state: int = State.IDLE
var _board: Node2D
var _anchor: StaticBody2D
var _joints_root: Node2D
var _hud: Control
var _overlay: Control

var _board_holes := PackedVector2Array()
var _hole_nodes: Array = []          # BoardHole, index == hole index
var _plate_nodes := {}               # plate_id -> PlateBody
var _screw_models: Array = []        # {hole:int, plates:Array[int], node:Screw}
var _joints := {}                    # plate_id -> PinJoint2D
var _frozen_velocities := {}         # PlateBody -> {lv, av}
var _hand: Dictionary = {}           # {model, origin_hole, origin_pinned}
var _moves := 0


func _ready() -> void:
	var game_state := get_node_or_null("/root/GameState")
	if level_data.is_empty():
		if game_state != null:
			level_number = game_state.current_level
		level_data = LevelLoaderScript.load_level(level_number)
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
	# Apply the real support states once everything exists.
	for plate: PlateBodyScript in _plate_nodes.values():
		_apply_support(plate)


func _build_background() -> void:
	var bg_layer := CanvasLayer.new()
	bg_layer.layer = -1
	var bg := ColorRect.new()
	bg.color = Color("#35506b")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	# CRITICAL: a Control's default mouse_filter is STOP, which marks every
	# click/touch as handled during GUI processing -- and only UNhandled
	# input reaches the 2D physics picking that delivers taps to the
	# screws and holes. The background must never intercept input.
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg_layer.add_child(bg)
	add_child(bg_layer)


func _build_board() -> void:
	_board_holes = level_data["board_holes"]

	# Backboard panel behind the holes and plates.
	var bounds: Vector2 = level_data.get("bounds", Vector2(720, 1000))
	var panel := Polygon2D.new()
	panel.polygon = PackedVector2Array([
		Vector2(8, 8), Vector2(bounds.x - 8, 8),
		Vector2(bounds.x - 8, bounds.y - 8), Vector2(8, bounds.y - 8)])
	panel.color = Color("#2b415a")
	panel.z_index = -10
	_board.add_child(panel)

	_anchor = StaticBody2D.new()
	_anchor.name = "Anchor"
	_board.add_child(_anchor)
	_joints_root = Node2D.new()
	_joints_root.name = "Joints"
	_board.add_child(_joints_root)

	_hole_nodes.clear()
	for i in _board_holes.size():
		var hole: BoardHoleScript = BoardHoleScript.new()
		hole.hole_index = i
		hole.position = _board_holes[i]
		hole.tapped.connect(_on_hole_tapped)
		_board.add_child(hole)
		_hole_nodes.append(hole)

	_plate_nodes.clear()
	var plates: Array = level_data["plates"]
	for plate_data: Dictionary in plates:
		var plate: PlateBodyScript = PlateBodyScript.new()
		_board.add_child(plate)
		plate.setup(plate_data)
		plate.fell_off.connect(_on_plate_fell)
		_plate_nodes[plate.plate_id] = plate

	_screw_models.clear()
	for screw_data: Dictionary in level_data["screws"]:
		var screw: ScrewScript = ScrewScript.new()
		screw.hole_index = int(screw_data["hole"])
		screw.position = _board_holes[screw.hole_index]
		screw.tapped.connect(_on_screw_tapped)
		_board.add_child(screw)
		var pinned: Array[int] = []
		for pid in screw_data["plates"]:
			pinned.append(int(pid))
		_screw_models.append({"hole": screw.hole_index, "plates": pinned, "node": screw})


func _build_ui() -> void:
	var ui_layer := CanvasLayer.new()
	ui_layer.layer = 10
	add_child(ui_layer)

	_hud = HudScript.new()
	_hud.setup(level_number, 0)
	_hud.restart_pressed.connect(_on_restart)
	_hud.menu_pressed.connect(_on_menu)
	ui_layer.add_child(_hud)

	_overlay = WinOverlayScript.new()
	_overlay.next_pressed.connect(_on_next_level)
	_overlay.select_pressed.connect(_on_menu)
	_overlay.visible = false
	ui_layer.add_child(_overlay)


# ------------------------------------------------------------ rule helpers

func _plate_snapshots() -> Array:
	var out: Array = []
	for plate: PlateBodyScript in _plate_nodes.values():
		out.append(plate.current_local_snapshot())
	return out


func _pins_of(plate_id: int) -> Array:
	var out: Array = []
	for s: Dictionary in _screw_models:
		for pid in s["plates"]:
			if int(pid) == plate_id:
				out.append(s)
				break
	return out


func _model_of(screw: ScrewScript) -> Dictionary:
	for s: Dictionary in _screw_models:
		if s["node"] == screw:
			return s
	return {}


# ------------------------------------------------------ physics management

func _apply_support(plate: PlateBodyScript) -> void:
	_remove_joint(plate.plate_id)
	var pins := _pins_of(plate.plate_id)
	if pins.size() >= 2:
		plate.make_static()
	elif pins.size() == 1:
		plate.make_dynamic()
		_add_joint(plate, _board_holes[int(pins[0]["hole"])])
	else:
		plate.make_dynamic()


func _add_joint(plate: PlateBodyScript, world_pos: Vector2) -> void:
	var joint := PinJoint2D.new()
	joint.position = world_pos
	_joints_root.add_child(joint)
	joint.node_a = joint.get_path_to(_anchor)
	joint.node_b = joint.get_path_to(plate)
	_joints[plate.plate_id] = joint


func _remove_joint(plate_id: int) -> void:
	if _joints.has(plate_id):
		var joint: PinJoint2D = _joints[plate_id]
		if is_instance_valid(joint):
			joint.queue_free()
		_joints.erase(plate_id)


## Hold every currently movable plate in place while a screw is in hand.
func _freeze_world() -> void:
	_frozen_velocities.clear()
	for plate: PlateBodyScript in _plate_nodes.values():
		if _pins_of(plate.plate_id).size() <= 1:
			_frozen_velocities[plate] = {
				"lv": plate.linear_velocity, "av": plate.angular_velocity}
			plate.hold_kinematic()


## Re-apply true support states and give moving plates their momentum back.
func _unfreeze_world() -> void:
	for plate: PlateBodyScript in _plate_nodes.values():
		_apply_support(plate)
	for plate: Variant in _frozen_velocities:
		if is_instance_valid(plate) and _pins_of(plate.plate_id).size() <= 1:
			plate.set_deferred("linear_velocity", _frozen_velocities[plate]["lv"])
			plate.set_deferred("angular_velocity", _frozen_velocities[plate]["av"])
	_frozen_velocities.clear()


# ------------------------------------------------------------- interaction

func _on_screw_tapped(screw: ScrewScript) -> void:
	if _state == State.WON:
		return
	if _state == State.IN_HAND:
		if not _hand.is_empty() and _hand["model"]["node"] == screw:
			await _cancel_hand()
		return
	var model := _model_of(screw)
	if model.is_empty():
		return
	if not RulesScript.can_remove(model, _board_holes, _plate_snapshots()):
		screw.play_blocked_feedback()
		return
	_state = State.IN_HAND
	_freeze_world()
	_screw_models.erase(model)
	_hand = {
		"model": model,
		"origin_hole": int(model["hole"]),
		"origin_pinned": (model["plates"] as Array).duplicate(),
	}
	await screw.lift_out()
	_update_hole_highlights()


func _on_hole_tapped(hole: BoardHoleScript) -> void:
	if _state != State.IN_HAND or _hand.is_empty():
		return
	var screw: ScrewScript = _hand["model"]["node"]
	if screw.busy:
		return
	var verdict: Dictionary = RulesScript.can_place(
		hole.hole_index, _board_holes, _plate_snapshots(), _screw_models)
	if not verdict["ok"]:
		hole.play_invalid_feedback()
		return
	var is_cancel: bool = hole.hole_index == _hand["origin_hole"]
	var model: Dictionary = _hand["model"]
	var pinned: Array[int] = []
	for pid in verdict["pinned"]:
		pinned.append(int(pid))
	model["hole"] = hole.hole_index
	model["plates"] = pinned
	_screw_models.append(model)
	if not is_cancel:
		_moves += 1
		if _hud != null:
			_hud.set_moves(_moves)
	_clear_hole_highlights()
	_hand = {}
	await screw.screw_in(_board_holes[hole.hole_index], hole.hole_index)
	_state = State.IDLE
	_unfreeze_world()


func _cancel_hand() -> void:
	var model: Dictionary = _hand["model"]
	var origin: int = _hand["origin_hole"]
	model["hole"] = origin
	model["plates"] = _hand["origin_pinned"]
	_screw_models.append(model)
	_hand = {}
	_clear_hole_highlights()
	var screw: ScrewScript = model["node"]
	await screw.screw_in(_board_holes[origin], origin)
	_state = State.IDLE
	_unfreeze_world()


func _update_hole_highlights() -> void:
	var snapshots := _plate_snapshots()
	for hole: BoardHoleScript in _hole_nodes:
		var verdict: Dictionary = RulesScript.can_place(
			hole.hole_index, _board_holes, snapshots, _screw_models)
		hole.highlighted = verdict["ok"]


func _clear_hole_highlights() -> void:
	for hole: BoardHoleScript in _hole_nodes:
		hole.highlighted = false


# ------------------------------------------------------------------ ending

func _on_plate_fell(plate: PlateBodyScript) -> void:
	_remove_joint(plate.plate_id)
	_plate_nodes.erase(plate.plate_id)
	if _plate_nodes.is_empty() and _state != State.WON:
		_state = State.WON
		_on_win()


func _on_win() -> void:
	var game_state := get_node_or_null("/root/GameState")
	if game_state != null:
		game_state.mark_completed(level_number)
	level_cleared.emit()
	if _overlay != null:
		await get_tree().create_timer(WIN_DELAY).timeout
		var is_last := level_number >= LevelLoaderScript.level_count()
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
