extends SceneTree
## Tests the quasi-static solver on micro fixtures and asserts parity with
## the Python twin's results on the shipped dev levels (moves counts baked
## from tools/quasi_solver.py output).
## Run: godot --headless --path . --script res://tests/test_quasi_solver.gd

const LevelLoaderScript := preload("res://src/core/level_loader.gd")
const QuasiSolverScript := preload("res://src/core/quasi_solver.gd")

var failures := 0
var checks := 0


func _initialize() -> void:
	_test_trivial_solvable()
	_test_no_destination_unsolvable()
	_test_order_forced()
	_test_dev_levels_match_python()
	print("=== RESULT: %s (%d/%d checks passed) ===" % [
		"PASS" if failures == 0 else "FAIL", checks - failures, checks])
	quit(0 if failures == 0 else 1)


func _check(cond: bool, what: String) -> void:
	checks += 1
	if cond:
		print("[OK] ", what)
	else:
		failures += 1
		print("[FAIL] ", what)


func _rect(x0: float, y0: float, x1: float, y1: float) -> PackedVector2Array:
	return PackedVector2Array([
		Vector2(x0, y0), Vector2(x1, y0), Vector2(x1, y1), Vector2(x0, y1)])


func _test_trivial_solvable() -> void:
	# One plate, one screw, one parking hole: remove, drop, park.
	var level := {
		"board_holes": PackedVector2Array([Vector2(300, 500), Vector2(300, 150)]),
		"plates": [{"id": 0, "layer": 0,
			"points": _rect(200, 400, 400, 600),
			"holes": PackedVector2Array([Vector2(300, 500)])}],
		"screws": [{"hole": 0, "plates": [0]}],
	}
	var result: Dictionary = QuasiSolverScript.solve(level)
	_check(result["solvable"] and int(result["moves"]) == 1,
		"single pinned plate solves in 1 move (got %s)" % str(result))


func _test_no_destination_unsolvable() -> void:
	# One plate on two screws, no empty holes: any removal leaves the screw
	# with nowhere to go (origin is a no-op), so the level is stuck.
	var level := {
		"board_holes": PackedVector2Array([Vector2(260, 500), Vector2(440, 500)]),
		"plates": [{"id": 0, "layer": 0,
			"points": _rect(200, 400, 500, 600),
			"holes": PackedVector2Array([Vector2(260, 500), Vector2(440, 500)])}],
		"screws": [{"hole": 0, "plates": [0]}, {"hole": 1, "plates": [0]}],
	}
	var result: Dictionary = QuasiSolverScript.solve(level)
	_check(not result["solvable"],
		"no empty hole means unsolvable (got %s)" % str(result))


func _test_order_forced() -> void:
	# A brace (layer 1) covers the base plate's only screw: the brace must
	# come off first.
	var level := {
		"board_holes": PackedVector2Array([
			Vector2(300, 500), Vector2(380, 480), Vector2(300, 150)]),
		"plates": [
			{"id": 0, "layer": 0,
				"points": _rect(200, 400, 460, 600),
				"holes": PackedVector2Array([Vector2(300, 500)])},
			{"id": 1, "layer": 1,
				"points": _rect(250, 430, 440, 560),
				"holes": PackedVector2Array([Vector2(380, 480)])},
		],
		"screws": [{"hole": 0, "plates": [0]}, {"hole": 1, "plates": [1]}],
	}
	var snapshot_plates: Array = []
	for p: Dictionary in level["plates"]:
		var copy: Dictionary = p.duplicate()
		copy["xform"] = Transform2D.IDENTITY
		snapshot_plates.append(copy)
	_check(not Rules.can_remove(level["screws"][0], level["board_holes"], snapshot_plates),
		"base screw is blocked while the brace covers it")
	var result: Dictionary = QuasiSolverScript.solve(level)
	_check(result["solvable"] and int(result["moves"]) == 2,
		"brace-then-base order solves in 2 moves (got %s)" % str(result))


func _test_dev_levels_match_python() -> void:
	# Expected values produced by: python3 tools/quasi_solver.py
	var expected := {"level_001.json": 3, "level_002.json": 4}
	var files: PackedStringArray = LevelLoaderScript.level_files()
	for i in files.size():
		var fname: String = files[i]
		if not expected.has(fname):
			continue
		var level: Dictionary = LevelLoaderScript.load_level_file(
			LevelLoaderScript.LEVELS_DIR + fname)
		var result: Dictionary = QuasiSolverScript.solve(level)
		_check(result["solvable"] and int(result["moves"]) == int(expected[fname]),
			"%s: solvable in %d moves matching Python (got %s)" % [
				fname, expected[fname], str(result)])
