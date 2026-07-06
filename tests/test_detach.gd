extends SceneTree
## Scene-level test: builds a real board (including background and HUD) from
## an inline 2-plate level and taps screws by pushing REAL touch events
## through the viewport -- exercising GUI mouse filters and 2D physics
## picking, then checks blocking, unscrew, plate detachment and the win
## signal. Regression guard for the background-ColorRect-swallows-input bug.
## Run: godot --headless --path . --script res://tests/test_detach.gd

const GameScript := preload("res://src/game.gd")

const BOARD_OFFSET := Vector2(0, 150)

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


## Push a touch tap through the viewport like a real finger/click would
## arrive, then give physics picking time to route it to the Area2D.
func _tap(level_pos: Vector2) -> void:
	var touch := InputEventScreenTouch.new()
	touch.index = 0
	touch.pressed = true
	touch.position = level_pos + BOARD_OFFSET
	root.push_input(touch)
	var release := InputEventScreenTouch.new()
	release.index = 0
	release.pressed = false
	release.position = touch.position
	root.push_input(release)
	for i in 4:
		await physics_frame


func _run() -> void:
	await process_frame
	root.physics_object_picking = true

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
	# Full scene including background ColorRect and HUD: input must survive
	# the whole GUI stack to reach the screws.
	game.headless_test = false
	root.add_child(game)
	await process_frame

	_check(game._plate_nodes.size() == 2, "board built with 2 plates")
	_check(game._screws_left == 2, "board built with 2 screws")

	var bottom_plate: Polygon2D = game._plate_nodes.get(0)
	var bottom_screw: Area2D = bottom_plate.screw_nodes[0]

	# 1. Tapping the covered screw (through the input pipeline) must reach
	#    the screw but not remove it.
	await _tap(Vector2(300, 470))
	_check(game._screws_left == 2, "blocked screw was not removed")
	_check(not bottom_screw.removed, "blocked screw still on its plate")

	# 2. Tap the free top screw: it unscrews, its plate detaches.
	game.level_cleared.connect(func() -> void: cleared = true)
	await _tap(Vector2(330, 430))
	_check(game._screws_left == 1,
		"tap through viewport reached the free screw (input-pipeline regression)")
	var falling: RigidBody2D = null
	for i in 120:  # unscrew animation runs ~0.45 s before the detach
		await physics_frame
		falling = _find_falling(game)
		if falling != null:
			break
	_check(falling != null, "detached plate became a RigidBody2D")
	_check(game._plate_nodes.size() == 1, "top plate left the board")

	# 3. The falling body frees itself once it drops off screen.
	var freed := false
	for i in 900:
		await physics_frame
		if not is_instance_valid(falling):
			freed = true
			break
	_check(freed, "falling plate freed itself below the screen")

	# 4. The bottom screw is now unblocked; removing it clears the level.
	await _tap(Vector2(300, 470))
	_check(game._screws_left == 0, "bottom screw removed after unblocking")
	for i in 120:
		if cleared:
			break
		await physics_frame
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
