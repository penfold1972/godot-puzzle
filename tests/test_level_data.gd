extends SceneTree
## Validates EVERY shipped v2 level via LevelLoader.validate and asserts the
## catalog size. (Quasi-static solvability is checked by test_quasi_solver.gd
## once the solver lands; the Python generator also gates on it.)
## Run: godot --headless --path . --script res://tests/test_level_data.gd

const LevelLoaderScript := preload("res://src/core/level_loader.gd")

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

	if failures == 0:
		print("[OK] all %d levels valid" % files.size())
	print("=== RESULT: %s ===" % ("PASS" if failures == 0 else "FAIL"))
	quit(0 if failures == 0 else 1)
