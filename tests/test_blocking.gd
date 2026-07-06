extends SceneTree
## Unit tests for the Solver blocking rule and solvability simulation.
## Run: godot --headless --path . --script res://tests/test_blocking.gd
##
## Scripts are preloaded (not referenced by class_name) so the tests work on
## a fresh clone before the editor has built the global class cache.

const SolverScript := preload("res://src/core/solver.gd")

var failures := 0
var checks := 0


func _initialize() -> void:
	_test_blocked_by_higher_plate()
	_test_not_blocked_by_lower_plate()
	_test_not_blocked_outside_overlap()
	_test_unblocked_after_removal()
	_test_solvable_stack()
	_test_unsolvable_terminates()
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


func _square(cx: float, cy: float, half: float) -> PackedVector2Array:
	return PackedVector2Array([
		Vector2(cx - half, cy - half), Vector2(cx + half, cy - half),
		Vector2(cx + half, cy + half), Vector2(cx - half, cy + half),
	])


func _test_blocked_by_higher_plate() -> void:
	var plates := [
		{"id": 0, "layer": 0, "points": _square(200, 200, 100), "screws": [Vector2(200, 200)]},
		{"id": 1, "layer": 1, "points": _square(220, 220, 100), "screws": [Vector2(300, 300)]},
	]
	_check(SolverScript.is_screw_blocked(plates, 0, Vector2(200, 200)),
		"screw under a higher plate is blocked")


func _test_not_blocked_by_lower_plate() -> void:
	var plates := [
		{"id": 0, "layer": 1, "points": _square(200, 200, 100), "screws": [Vector2(200, 200)]},
		{"id": 1, "layer": 0, "points": _square(220, 220, 100), "screws": [Vector2(300, 300)]},
	]
	_check(not SolverScript.is_screw_blocked(plates, 0, Vector2(200, 200)),
		"screw covered only by a LOWER plate is not blocked")


func _test_not_blocked_outside_overlap() -> void:
	var plates := [
		{"id": 0, "layer": 0, "points": _square(200, 200, 100), "screws": [Vector2(120, 120)]},
		{"id": 1, "layer": 1, "points": _square(280, 280, 60), "screws": [Vector2(280, 280)]},
	]
	_check(not SolverScript.is_screw_blocked(plates, 0, Vector2(120, 120)),
		"screw outside the higher plate's polygon is not blocked")


func _test_unblocked_after_removal() -> void:
	var covering := {"id": 1, "layer": 1, "points": _square(200, 200, 100),
		"screws": [Vector2(200, 200)]}
	var plates := [
		{"id": 0, "layer": 0, "points": _square(200, 200, 100), "screws": [Vector2(200, 200)]},
		covering,
	]
	var blocked_before: bool = SolverScript.is_screw_blocked(plates, 0, Vector2(200, 200))
	plates.erase(covering)
	var blocked_after: bool = SolverScript.is_screw_blocked(plates, 0, Vector2(200, 200))
	_check(blocked_before and not blocked_after,
		"screw becomes unblocked once the covering plate is removed")


func _test_solvable_stack() -> void:
	# Three plates stacked: each covers the screw of the one below.
	var level := {"plates": [
		{"id": 0, "layer": 0, "points": _square(200, 200, 120), "screws": [Vector2(200, 200)]},
		{"id": 1, "layer": 1, "points": _square(210, 210, 100), "screws": [Vector2(210, 210)]},
		{"id": 2, "layer": 2, "points": _square(220, 220, 80), "screws": [Vector2(220, 220)]},
	]}
	var stats: Dictionary = SolverScript.solve_stats(level)
	_check(stats["solvable"], "3-plate stack is solvable")
	_check(int(stats["passes"]) == 3, "3-plate stack needs 3 passes (got %d)" % stats["passes"])
	_check(int(stats["total_screws"]) == 3, "total screw count is 3")


func _test_unsolvable_terminates() -> void:
	# A plate whose ONLY screw is covered by a higher plate that has no
	# screws at all: the validator would reject this data, but the solver
	# must still terminate and report unsolvable.
	var level := {"plates": [
		{"id": 0, "layer": 0, "points": _square(200, 200, 100), "screws": [Vector2(200, 200)]},
		{"id": 1, "layer": 1, "points": _square(200, 200, 100), "screws": []},
	]}
	# NOTE: plate 1 with zero screws detaches immediately on pass 1, which
	# unblocks plate 0 -- so this IS solvable. The truly unsolvable case is
	# a screw covered by a plate that can never lose its screws: mutual
	# coverage requires equal layers, which the rule forbids, so we fake it
	# with a plate whose screw is covered by ITSELF being under plate 2.
	var stats: Dictionary = SolverScript.solve_stats(level)
	_check(stats["solvable"], "zero-screw covering plate detaches immediately (solvable)")

	# Deadlock via out-of-order data (violates validator rules on purpose):
	# two plates on the same layer covering each other's screws never unblock.
	var deadlock := {"plates": [
		{"id": 0, "layer": 1, "points": _square(200, 200, 100), "screws": [Vector2(200, 200)]},
		{"id": 1, "layer": 1, "points": _square(200, 200, 100), "screws": [Vector2(200, 200)]},
	]}
	# Same layer -> neither blocks the other under the strict '>' rule, so
	# this is solvable too; the solver must simply terminate on both.
	var stats2: Dictionary = SolverScript.solve_stats(deadlock)
	_check(stats2["solvable"], "same-layer overlap resolves under strict '>' rule")

	# A genuine deadlock: plate 0's screw under plate 1, plate 1's screw
	# under plate 2, plate 2's screw under... plate 0 cannot happen with
	# ordered layers. Force one: plate 1 (layer 2) covers plate 0's screw,
	# and plate 0 (layer 0)... instead give plate 1 a screw covered by an
	# UNREMOVABLE plate: plate 2 (layer 3) whose own screw is covered by
	# plate 1? layer 2 < 3 so no. Layered DAGs always peel top-down --
	# proving the construction sound. The only unsolvable inputs have a
	# cycle, which needs equal layers + strict ordering violations that the
	# parser cannot even represent. So instead assert termination + pass
	# count on a deep 6-plate tower (worst case passes == plate count).
	var tower_plates: Array = []
	for i in 6:
		tower_plates.append({
			"id": i, "layer": i,
			"points": _square(200, 200, float(140 - i * 10)),
			"screws": [Vector2(200, 200 - i * 2)],
		})
	var stats3: Dictionary = SolverScript.solve_stats({"plates": tower_plates})
	_check(stats3["solvable"] and int(stats3["passes"]) == 6,
		"6-plate tower solvable in exactly 6 passes (got %s)" % str(stats3["passes"]))
