class_name Solver
extends RefCounted
## Pure game-rule logic, shared by the running game, the test suite and
## (mirrored in Python by tools/generate_levels.py) the level generator.
##
## Rule: a screw is blocked while any REMAINING plate on a HIGHER layer
## covers its position. A plate detaches when it has no screws left.


## `plates` is an array of dicts with keys: id, layer, points, screws.
## Only plates still on the board should be in the array.
static func is_screw_blocked(plates: Array, plate_id: int, screw_pos: Vector2) -> bool:
	var my_layer := 0
	var found := false
	for p: Dictionary in plates:
		if int(p["id"]) == plate_id:
			my_layer = int(p["layer"])
			found = true
			break
	if not found:
		return false
	for p: Dictionary in plates:
		if int(p["id"]) == plate_id:
			continue
		if int(p["layer"]) > my_layer and Geometry2D.is_point_in_polygon(screw_pos, p["points"]):
			return true
	return false


static func is_solvable(level: Dictionary) -> bool:
	return solve_stats(level)["solvable"]


## Simulates optimal play: each pass removes every currently-unblocked screw,
## then removes screw-less plates. Returns:
##   solvable: bool  -- board can be emptied
##   passes: int     -- number of passes needed (difficulty proxy)
##   total_screws: int
static func solve_stats(level: Dictionary) -> Dictionary:
	var remaining: Array = []
	var total_screws := 0
	for p: Dictionary in level.get("plates", []):
		var screws: Array = Array(p["screws"])
		total_screws += screws.size()
		remaining.append({
			"id": int(p["id"]),
			"layer": int(p["layer"]),
			"points": p["points"],
			"screws": screws,
		})

	var passes := 0
	while not remaining.is_empty():
		passes += 1
		var removed_any := false
		# Remove every screw that is unblocked at the START of this pass.
		for p: Dictionary in remaining:
			var kept: Array = []
			for s: Vector2 in p["screws"]:
				if is_screw_blocked(remaining, int(p["id"]), s):
					kept.append(s)
				else:
					removed_any = true
			p["screws"] = kept
		# Detach plates that ran out of screws.
		var still: Array = []
		for p: Dictionary in remaining:
			if (p["screws"] as Array).is_empty():
				removed_any = true
			else:
				still.append(p)
		remaining = still
		if not removed_any:
			return {"solvable": false, "passes": passes, "total_screws": total_screws}
	return {"solvable": true, "passes": passes, "total_screws": total_screws}
