extends SceneTree
## Scene-level test: builds a real board from an inline 2-plate level,
## taps screws through the game controller, and checks blocking feedback,
## unscrew animation, plate detachment physics and the win signal.
## Run: godot --headless --path . --script res://tests/test_detach.gd

const GameScript := preload("res://src/game.gd")

var failures := 0
var checks := 0
var cleared := false


func _initialize() -> void:
	_run()


func _check(cond: bool, what: String) -> void:
	checks += 1
	if cond:
		print("[OK] ", what)
	else:
		failures += 1
		print("[FAIL] ", what)


func _run() -> void:
	await process_frame

	# Bottom plate (id 0) has one screw covered by the top plate (id 1).
	var level := {
		"id": 999,
		"name": "detach-fixture",
		"bounds": Vector2(720, 1000),
		"plates": [
			{
				"id": 0, "layer": 0, "color": Color("#8fa3b8"),
				"points": PackedVector2Array([
					Vector2(100, 300), Vector2(500, 300),
					Vector2(500, 640), Vector2(100, 640)]),
				"screws": PackedVector2Array([Vector2(300, 470)]),
			},
			{
				"id": 1, "layer": 1, "color": Color("#b8a37f"),
				"points": PackedVector2Array([
					Vector2(200, 380), Vector2(460, 380),
					Vector2(460, 560), Vector2(200, 560)]),
				"screws": PackedVector2Array([Vector2(330, 430)]),
			},
		],
	}

	var game: Node2D = GameScript.new()
	game.level_data = level
	game.headless_test = true
	root.add_child(game)
	await process_frame

	_check(game._plate_nodes.size() == 2, "board built with 2 plates")
	_check(game._screws_left == 2, "board built with 2 screws")

	var bottom_plate: Polygon2D = game._plate_nodes.get(0)
	var top_plate: Polygon2D = game._plate_nodes.get(1)
	var bottom_screw: Area2D = bottom_plate.screw_nodes[0]
	var top_screw: Area2D = top_plate.screw_nodes[0]

	# 1. Tapping the covered screw must do nothing to the model.
	await game._on_screw_tapped(bottom_screw)
	_check(game._screws_left == 2, "blocked screw was not removed")
	_check(not bottom_screw.removed, "blocked screw still on its plate")

	# 2. Tap the free top screw: it unscrews, its plate detaches.
	game.level_cleared.connect(func() -> void: cleared = true)
	await game._on_screw_tapped(top_screw)
	_check(game._screws_left == 1, "top screw removed from model")
	_check(game._plate_nodes.size() == 1, "top plate left the board")
	await process_frame
	var falling := _find_falling(game)
	_check(falling != null, "detached plate became a RigidBody2D")

	# 3. The falling body frees itself once it drops off screen.
	var freed := false
	for i in 900:
		await physics_frame
		if not is_instance_valid(falling):
			freed = true
			break
	_check(freed, "falling plate freed itself below the screen")

	# 4. The bottom screw is now unblocked; removing it clears the level.
	await game._on_screw_tapped(bottom_screw)
	_check(game._screws_left == 0, "bottom screw removed after unblocking")
	_check(cleared, "level_cleared signal emitted")
	_check(game._won, "game reached the won state")

	print("=== RESULT: %s (%d/%d checks passed) ===" % [
		"PASS" if failures == 0 else "FAIL", checks - failures, checks])
	quit(0 if failures == 0 else 1)


func _find_falling(game: Node2D) -> RigidBody2D:
	for child in game._board.get_children():
		if child is RigidBody2D:
			return child
	return null
