extends SceneTree
## Scene-level test of the v2 pin-board flow using REAL touch events pushed
## through the viewport (GUI mouse filters + physics picking included):
## lift a screw -> world freezes and poses hold; cancel restores; park a
## screw -> the single-screw plate swings; unpin fully -> the plate falls
## off screen and the level clears.
## Run: godot --headless --path . --script res://tests/test_scene_v2.gd

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


func _tap(board_pos: Vector2) -> void:
	var touch := InputEventScreenTouch.new()
	touch.index = 0
	touch.pressed = true
	touch.position = board_pos + BOARD_OFFSET
	root.push_input(touch)
	var release := InputEventScreenTouch.new()
	release.index = 0
	release.pressed = false
	release.position = touch.position
	root.push_input(release)
	for i in 4:
		await physics_frame


func _wait_until(predicate: Callable, max_frames: int) -> bool:
	for i in max_frames:
		if predicate.call():
			return true
		await physics_frame
	return predicate.call()


## The in-hand screw ignores taps while its lift/screw-in tween runs; wait
## for it to settle before sending the next tap.
func _wait_hand_ready(game: Node2D) -> void:
	await _wait_until(func() -> bool:
		return not game._hand.is_empty() \
			and not (game._hand["model"]["node"] as Area2D).busy, 120)


func _run() -> void:
	await process_frame
	root.physics_object_picking = true

	# One plate pinned by two screws, plus two empty parking-rail holes.
	var level := {
		"version": 2,
		"id": 999,
		"name": "scene-fixture",
		"silhouette": "dev",
		"bounds": Vector2(720, 1000),
		"board_holes": PackedVector2Array([
			Vector2(260, 500), Vector2(440, 500),
			Vector2(300, 150), Vector2(450, 150)]),
		"plates": [{
			"id": 0, "layer": 0, "color": Color("#98a8b8"),
			"points": PackedVector2Array([
				Vector2(200, 400), Vector2(500, 400),
				Vector2(500, 600), Vector2(200, 600)]),
			"holes": PackedVector2Array([Vector2(260, 500), Vector2(440, 500)]),
		}],
		"screws": [
			{"hole": 0, "plates": [0] as Array[int]},
			{"hole": 1, "plates": [0] as Array[int]},
		],
	}

	var game: Node2D = GameScript.new()
	game.level_data = level
	game.headless_test = true
	root.add_child(game)
	game.level_cleared.connect(func() -> void: cleared = true)
	await process_frame
	await physics_frame

	_check(game._plate_nodes.size() == 1, "board built with 1 plate")
	_check(game._screw_models.size() == 2, "board built with 2 screws")
	_check(game._hole_nodes.size() == 4, "board built with 4 holes")

	var plate: RigidBody2D = game._plate_nodes[0]
	_check(plate.freeze, "2-screw plate starts frozen static")
	var rest_xform: Transform2D = plate.transform

	# --- 1. Lift screw 0: state IN_HAND, world holds still.
	await _tap(Vector2(260, 500))
	var lifted: bool = await _wait_until(
		func() -> bool: return game._state == GameScript.State.IN_HAND, 60)
	_check(lifted, "tapping a screw enters IN_HAND (input pipeline works)")
	await physics_frame
	await physics_frame
	var pose_before: Transform2D = plate.transform
	for i in 10:
		await physics_frame
	_check(plate.transform.origin.distance_to(pose_before.origin) < 0.01
		and absf(plate.rotation - pose_before.get_rotation()) < 0.001,
		"world frozen while screw in hand (pose holds for 10 frames)")

	# --- 2. Cancel by tapping the in-hand screw again.
	await _wait_hand_ready(game)
	await _tap(Vector2(260, 500 - 18))  # in-hand screws hover slightly above
	var idle_again: bool = await _wait_until(
		func() -> bool: return game._state == GameScript.State.IDLE, 120)
	_check(idle_again, "tapping the in-hand screw cancels back to IDLE")
	_check(game._screw_models.size() == 2, "cancel restored the screw model")
	_check(game._moves == 0, "cancel does not count as a move")

	# --- 3. Move screw 0 to the parking rail: plate swings on its last screw.
	await _tap(Vector2(260, 500))
	await _wait_until(func() -> bool: return game._state == GameScript.State.IN_HAND, 60)
	await _wait_hand_ready(game)
	await _tap(Vector2(300, 150))
	var placed: bool = await _wait_until(
		func() -> bool: return game._state == GameScript.State.IDLE, 120)
	_check(placed, "screw parked on the rail")
	_check(game._moves == 1, "parking counted as a move")
	var swung: bool = await _wait_until(
		func() -> bool: return absf(plate.rotation) > 0.02, 240)
	_check(swung, "1-screw plate swings under gravity (rotation %.3f)" % plate.rotation)

	# --- 4. Move the last screw: the plate falls off screen; level clears.
	await _tap(Vector2(440, 500))
	await _wait_until(func() -> bool: return game._state == GameScript.State.IN_HAND, 60)
	await _wait_hand_ready(game)
	await _tap(Vector2(450, 150))
	await _wait_until(func() -> bool: return game._state != GameScript.State.IN_HAND, 120)
	var fell: bool = await _wait_until(func() -> bool: return cleared, 900)
	_check(fell, "unpinned plate fell off screen and level_cleared fired")
	_check(game._state == GameScript.State.WON, "game reached WON state")
	_check(game._moves == 2, "two real moves recorded")

	print("=== RESULT: %s (%d/%d checks passed) ===" % [
		"PASS" if failures == 0 else "FAIL", checks - failures, checks])
	quit(0 if failures == 0 else 1)
