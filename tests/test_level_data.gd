extends SceneTree
## Validates EVERY shipped level: schema rules (LevelLoader.validate) plus
## solvability (Solver.is_solvable), and asserts there are at least 48.
## Run: godot --headless --path . --script res://tests/test_level_data.gd

const LevelLoaderScript := preload("res://src/core/level_loader.gd")
const SolverScript := preload("res://src/core/solver.gd")

const REQUIRED_LEVEL_COUNT := 48


func _initialize() -> void:
	var failures := 0
	var files: PackedStringArray = LevelLoaderScript.level_files()
	print("Found %d levels in index.json" % files.size())
	if files.size() < REQUIRED_LEVEL_COUNT:
		print("[FAIL] need at least %d levels, found %d" % [REQUIRED_LEVEL_COUNT, files.size()])
		failures += 1

	for i in files.size():
		var path: String = LevelLoaderScript.LEVELS_DIR + files[i]
		var level: Dictionary = LevelLoaderScript.load_level_file(path)
		var errors: Array[String] = LevelLoaderScript.validate(level)
		if not errors.is_empty():
			failures += 1
			print("[FAIL] level %d (%s):" % [i + 1, files[i]])
			for e in errors:
				print("       - ", e)
			continue
		var stats: Dictionary = SolverScript.solve_stats(level)
		if not stats["solvable"]:
			failures += 1
			print("[FAIL] level %d (%s): NOT SOLVABLE" % [i + 1, files[i]])
			continue

	if failures == 0:
		print("[OK] all %d levels valid and solvable" % files.size())
	print("=== RESULT: %s ===" % ("PASS" if failures == 0 else "FAIL"))
	quit(0 if failures == 0 else 1)
