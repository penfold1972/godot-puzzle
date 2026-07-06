extends SceneTree
## Runs the shared rule-parity fixture suite against src/core/rules.gd.
## The same cases run against tools/rules.py (python3 tools/test_rules.py),
## guaranteeing the game and the Python generator agree on the rules.
## Run: godot --headless --path . --script res://tests/test_rules.gd

const RulesScript := preload("res://src/core/rules.gd")

const FIXTURES := "res://tests/fixtures/rules_cases.json"

var failures := 0
var checks := 0


func _initialize() -> void:
	var text := FileAccess.get_file_as_string(FIXTURES)
	var data: Dictionary = JSON.parse_string(text)
	for scenario: Dictionary in data["scenarios"]:
		_run_scenario(scenario)
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


func _to_vec_array(raw: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for pair: Variant in raw:
		out.append(Vector2(float(pair[0]), float(pair[1])))
	return out


func _run_scenario(scenario: Dictionary) -> void:
	var name: String = scenario["name"]
	var board_holes := _to_vec_array(scenario["board_holes"])
	var plates: Array = []
	for raw: Dictionary in scenario["plates"]:
		var xf := Transform2D.IDENTITY
		if raw.has("xform"):
			var x: Array = raw["xform"]
			xf = Transform2D(
				Vector2(float(x[0]), float(x[1])),
				Vector2(float(x[2]), float(x[3])),
				Vector2(float(x[4]), float(x[5])))
		plates.append({
			"id": int(raw["id"]),
			"layer": int(raw["layer"]),
			"points": _to_vec_array(raw["points"]),
			"holes": _to_vec_array(raw["holes"]),
			"xform": xf,
		})
	var screws: Array = []
	for raw: Dictionary in scenario["screws"]:
		var pinned: Array = []
		for pid in raw["plates"]:
			pinned.append(int(pid))
		screws.append({"hole": int(raw["hole"]), "plates": pinned})

	for check: Dictionary in scenario["checks"]:
		var fn: String = check["fn"]
		var label := "%s / %s" % [name, fn]
		match fn:
			"covering":
				var point := Vector2(float(check["point"][0]), float(check["point"][1]))
				var got := RulesScript.covering_plates(point, plates)
				got.sort()
				var expect: Array = []
				for pid in check["expect"]:
					expect.append(int(pid))
				expect.sort()
				_check(got == expect, "%s %s -> %s" % [label, point, got])
			"can_remove":
				var got: bool = RulesScript.can_remove(
					screws[int(check["screw"])], board_holes, plates)
				_check(got == bool(check["expect"]),
					"%s screw %d -> %s" % [label, int(check["screw"]), got])
			"can_place":
				var got: Dictionary = RulesScript.can_place(
					int(check["hole"]), board_holes, plates, screws)
				var pinned: Array = got["pinned"]
				pinned.sort()
				var expect_pinned: Array = []
				for pid in check["expect_pinned"]:
					expect_pinned.append(int(pid))
				expect_pinned.sort()
				var ok: bool = got["ok"] == bool(check["expect_ok"]) \
					and pinned == expect_pinned
				_check(ok, "%s hole %d -> %s" % [label, int(check["hole"]), got])
			_:
				_check(false, "%s unknown check fn" % label)
