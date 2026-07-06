class_name Rules
extends RefCounted
## v2 game rules: pure, stateless queries over a board snapshot.
## Mirrored 1:1 in tools/rules.py (kept in sync via tests/fixtures/rules_cases.json).
##
## Snapshot shapes:
##   plate: {id:int, layer:int, points:PackedVector2Array (local),
##           holes:PackedVector2Array (local), xform:Transform2D}
##   screw: {hole:int (board hole index), plates:Array[int] (pinned ids)}
## Plate geometry is tested against CURRENT transforms, so the same code works
## for resting, swung, and frozen plates.

const PLACE_TOLERANCE := 10.0


## IDs of plates whose current polygon covers a board-space point.
static func covering_plates(point: Vector2, plates: Array) -> Array[int]:
	var out: Array[int] = []
	for p: Dictionary in plates:
		var xf: Transform2D = p["xform"]
		var local := xf.affine_inverse() * point
		if Geometry2D.is_point_in_polygon(local, p["points"]):
			out.append(int(p["id"]))
	return out


## A screw can be unscrewed unless a plate it does NOT pin lies over its hole
## on a higher layer than everything it pins. A parked screw (pins nothing)
## is blocked by ANY covering plate.
static func can_remove(screw: Dictionary, board_holes: PackedVector2Array, plates: Array) -> bool:
	var point := board_holes[int(screw["hole"])]
	var pinned: Array = screw["plates"]
	var covering := covering_plates(point, plates)
	if pinned.is_empty():
		return covering.is_empty()
	var max_pinned_layer := -2147483648
	for p: Dictionary in plates:
		if _id_in(int(p["id"]), pinned):
			max_pinned_layer = maxi(max_pinned_layer, int(p["layer"]))
	for cid in covering:
		if _id_in(cid, pinned):
			continue
		var p := _plate_by_id(cid, plates)
		if not p.is_empty() and int(p["layer"]) > max_pinned_layer:
			return false
	return true


## A screw can go into `hole_index` if the hole is empty and EVERY plate
## covering that point has one of its own holes aligned with it (within
## tolerance). The placed screw pins all covering plates; if nothing covers
## the hole the screw just parks there.
## Returns {ok: bool, pinned: Array[int]}.
static func can_place(hole_index: int, board_holes: PackedVector2Array, plates: Array,
		screws: Array, tolerance := PLACE_TOLERANCE) -> Dictionary:
	for s: Dictionary in screws:
		if int(s["hole"]) == hole_index:
			return {"ok": false, "pinned": []}
	var point := board_holes[hole_index]
	var covering := covering_plates(point, plates)
	for cid in covering:
		var p := _plate_by_id(cid, plates)
		var xf: Transform2D = p["xform"]
		var aligned := false
		for h: Vector2 in p["holes"]:
			if (xf * h).distance_to(point) <= tolerance:
				aligned = true
				break
		if not aligned:
			return {"ok": false, "pinned": []}
	return {"ok": true, "pinned": covering}


static func _plate_by_id(pid: int, plates: Array) -> Dictionary:
	for p: Dictionary in plates:
		if int(p["id"]) == pid:
			return p
	return {}


static func _id_in(pid: int, ids: Array) -> bool:
	for x in ids:
		if int(x) == pid:
			return true
	return false
