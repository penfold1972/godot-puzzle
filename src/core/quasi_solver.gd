class_name QuasiSolver
extends RefCounted
## Quasi-static solvability check for v2 pin-board levels.
## Mirrors tools/quasi_solver.py exactly (same deterministic greedy policy,
## same results -- asserted by test_quasi_solver.gd against the dev levels).
## Motion is ignored: plates stay at rest transforms and are optimistically
## deleted when their last screw leaves. Physics can still deadlock a
## quasi-solvable level at runtime; restart is the accepted recovery.
##
## Greedy policy per move:
##  1. Among removable screws, prefer max plates dropped; tie: lower hole.
##  2. Destination: fewest pinned plates (parking first); tie: lower hole.
##     Origin hole allowed only if the removal dropped a plate.
##  3. Repeated state or no legal move => unsolvable.

const MOVE_LIMIT := 400


## `level` is LevelLoader.parse_level output. Returns {solvable: bool, moves: int}.
static func solve(level: Dictionary) -> Dictionary:
	var board_holes: PackedVector2Array = level["board_holes"]
	var plates: Array = []
	for p: Dictionary in level["plates"]:
		plates.append({
			"id": int(p["id"]), "layer": int(p["layer"]),
			"points": p["points"], "holes": p["holes"],
			"xform": Transform2D.IDENTITY,
		})
	var screws: Array = []
	for s: Dictionary in level["screws"]:
		var pinned: Array = []
		for pid in s["plates"]:
			pinned.append(int(pid))
		pinned.sort()
		screws.append({"hole": int(s["hole"]), "plates": pinned})

	var seen := {}
	var moves := 0

	while not plates.is_empty() and moves < MOVE_LIMIT:
		var key := _state_key(plates, screws)
		if seen.has(key):
			return {"solvable": false, "moves": moves}
		seen[key] = true

		var best_rank: Array = []
		var best_si := -1
		var best_dropped: Array = []
		var best_dest := -1
		var best_dest_pinned: Array = []

		var order: Array = range(screws.size())
		order.sort_custom(func(a: int, b: int) -> bool:
			return int(screws[a]["hole"]) < int(screws[b]["hole"]))
		for si: int in order:
			var screw: Dictionary = screws[si]
			if not Rules.can_remove(screw, board_holes, plates):
				continue
			var rest: Array = screws.duplicate()
			rest.remove_at(si)
			var dropped: Array = []
			for pid in screw["plates"]:
				if _pins(int(pid), rest) == 0:
					dropped.append(int(pid))
			var after: Array = []
			for p: Dictionary in plates:
				if not dropped.has(int(p["id"])):
					after.append(p)
			var drops := dropped.size()

			var dest := -1
			var dest_pinned: Array = []
			var dest_rank: Array = []
			for hi in board_holes.size():
				if hi == int(screw["hole"]) and drops == 0:
					continue  # putting it straight back is a no-op
				var verdict: Dictionary = Rules.can_place(hi, board_holes, after, rest)
				if not verdict["ok"]:
					continue
				var rank: Array = [(verdict["pinned"] as Array).size(), hi]
				if dest_rank.is_empty() or rank < dest_rank:
					dest_rank = rank
					dest = hi
					dest_pinned = (verdict["pinned"] as Array).duplicate()
					dest_pinned.sort()
			if dest == -1:
				continue
			var cand_rank: Array = [-drops, int(screw["hole"])]
			if best_rank.is_empty() or cand_rank < best_rank:
				best_rank = cand_rank
				best_si = si
				best_dropped = dropped
				best_dest = dest
				best_dest_pinned = dest_pinned

		if best_si == -1:
			return {"solvable": false, "moves": moves}

		var still: Array = []
		for p: Dictionary in plates:
			if not best_dropped.has(int(p["id"])):
				still.append(p)
		plates = still
		screws[best_si]["hole"] = best_dest
		screws[best_si]["plates"] = best_dest_pinned
		moves += 1

	return {"solvable": plates.is_empty(), "moves": moves}


static func _pins(plate_id: int, screws: Array) -> int:
	var count := 0
	for s: Dictionary in screws:
		for pid in s["plates"]:
			if int(pid) == plate_id:
				count += 1
				break
	return count


static func _state_key(plates: Array, screws: Array) -> String:
	var alive: Array = []
	for p: Dictionary in plates:
		alive.append(int(p["id"]))
	alive.sort()
	var placed: Array = []
	for s: Dictionary in screws:
		placed.append("%d:%s" % [int(s["hole"]), str(s["plates"])])
	placed.sort()
	return "%s|%s" % [str(alive), str(placed)]
