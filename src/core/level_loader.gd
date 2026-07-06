class_name LevelLoader
extends RefCounted
## Loads and validates v2 (pin-board) JSON level definitions from res://levels/.
## Schema:
## { "version": 2, "id": 7, "name": "T-Shirt II", "silhouette": "tshirt",
##   "bounds": [720, 1000],
##   "board_holes": [[x,y], ...],
##   "plates": [{"id":0, "layer":0, "color":"#c25b4e",
##               "points":[[x,y],...], "holes":[[x,y],...]}],
##   "screws": [{"hole": 3, "plates": [0, 2]}] }
## Plates are stored at identity transform, so plate-local coordinates equal
## board coordinates in the file. Empty holes are the board holes no screw
## references; every level must start with at least one.

const LEVELS_DIR := "res://levels/"
const INDEX_PATH := "res://levels/index.json"
const MIN_PLATE_AREA := 2000.0
const SCREW_RADIUS := 22.0
const EDGE_MARGIN := 24.0
const HOLE_SPACING_MIN := 44.0  # 2 x screw radius
const REST_ALIGN_TOLERANCE := 2.0  # at rest, pins must align near-exactly

static var _index_cache: PackedStringArray = PackedStringArray()


static func level_files() -> PackedStringArray:
	if _index_cache.is_empty():
		var text := FileAccess.get_file_as_string(INDEX_PATH)
		if text.is_empty():
			push_error("LevelLoader: missing or empty %s" % INDEX_PATH)
			return PackedStringArray()
		var data: Variant = JSON.parse_string(text)
		if data is Dictionary and data.has("levels"):
			for f: Variant in data["levels"]:
				_index_cache.append(String(f))
	return _index_cache


static func level_count() -> int:
	return level_files().size()


## n is 1-based (level 1 = first entry in index.json).
static func load_level(n: int) -> Dictionary:
	var files := level_files()
	if n < 1 or n > files.size():
		push_error("LevelLoader: level %d out of range (1..%d)" % [n, files.size()])
		return {}
	return load_level_file(LEVELS_DIR + files[n - 1])


static func load_level_file(path: String) -> Dictionary:
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		push_error("LevelLoader: cannot read %s" % path)
		return {}
	var raw: Variant = JSON.parse_string(text)
	if raw == null:
		push_error("LevelLoader: invalid JSON in %s" % path)
		return {}
	return parse_level(raw)


static func parse_level(raw: Variant) -> Dictionary:
	if not (raw is Dictionary):
		return {}
	if int(raw.get("version", 1)) != 2:
		push_error("LevelLoader: unsupported level version %s" % str(raw.get("version")))
		return {}
	var level := {
		"version": 2,
		"id": int(raw.get("id", 0)),
		"name": String(raw.get("name", "")),
		"silhouette": String(raw.get("silhouette", "")),
		"bounds": Vector2(720, 1000),
		"board_holes": _to_vec_array(raw.get("board_holes", [])),
		"plates": [],
		"screws": [],
	}
	var raw_bounds: Variant = raw.get("bounds")
	if raw_bounds is Array and raw_bounds.size() == 2:
		level["bounds"] = Vector2(float(raw_bounds[0]), float(raw_bounds[1]))
	for raw_plate: Variant in raw.get("plates", []):
		if not (raw_plate is Dictionary):
			continue
		level["plates"].append({
			"id": int(raw_plate.get("id", -1)),
			"layer": int(raw_plate.get("layer", 0)),
			"color": Color.from_string(String(raw_plate.get("color", "#8fa3b8")), Color("#8fa3b8")),
			"points": _to_vec_array(raw_plate.get("points", [])),
			"holes": _to_vec_array(raw_plate.get("holes", [])),
		})
	for raw_screw: Variant in raw.get("screws", []):
		if not (raw_screw is Dictionary):
			continue
		var pinned: Array[int] = []
		for pid: Variant in raw_screw.get("plates", []):
			pinned.append(int(pid))
		level["screws"].append({"hole": int(raw_screw.get("hole", -1)), "plates": pinned})
	return level


static func _to_vec_array(raw: Variant) -> PackedVector2Array:
	var out := PackedVector2Array()
	if raw is Array:
		for pair: Variant in raw:
			if pair is Array and pair.size() == 2:
				out.append(Vector2(float(pair[0]), float(pair[1])))
	return out


## Returns a list of human-readable errors; empty means the level is valid.
## Solvability is a separate concern (see quasi_solver.gd).
static func validate(level: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	if level.is_empty():
		errors.append("level is empty or failed to parse")
		return errors
	var plates: Array = level["plates"]
	var board_holes: PackedVector2Array = level["board_holes"]
	var screws: Array = level["screws"]
	if plates.is_empty():
		errors.append("level has no plates")
		return errors
	if board_holes.is_empty():
		errors.append("level has no board holes")
		return errors

	# Board holes must not crowd each other.
	for i in board_holes.size():
		for j in range(i + 1, board_holes.size()):
			if board_holes[i].distance_to(board_holes[j]) < HOLE_SPACING_MIN:
				errors.append("board holes %d and %d closer than %.0f px" % [
					i, j, HOLE_SPACING_MIN])

	var seen_ids := {}
	for plate: Dictionary in plates:
		var pid: int = plate["id"]
		var label := "plate %d" % pid
		if seen_ids.has(pid):
			errors.append("%s: duplicate id" % label)
		seen_ids[pid] = true

		var points: PackedVector2Array = plate["points"]
		if points.size() < 3:
			errors.append("%s: fewer than 3 points" % label)
			continue
		if Geometry2D.triangulate_polygon(points).is_empty():
			errors.append("%s: degenerate or self-intersecting polygon" % label)
			continue
		if Geometry2D.decompose_polygon_in_convex(points).is_empty():
			errors.append("%s: convex decomposition failed" % label)
			continue
		if absf(_signed_area(points)) < MIN_PLATE_AREA:
			errors.append("%s: area below minimum %.0f" % [label, MIN_PLATE_AREA])

		var holes: PackedVector2Array = plate["holes"]
		if holes.is_empty():
			errors.append("%s: has no screw holes" % label)
		for h in holes:
			if not Geometry2D.is_point_in_polygon(h, points):
				errors.append("%s: hole %s outside plate" % [label, h])
			elif _distance_to_edges(h, points) < EDGE_MARGIN:
				errors.append("%s: hole %s too close to plate edge" % [label, h])
		for i in holes.size():
			for j in range(i + 1, holes.size()):
				if holes[i].distance_to(holes[j]) < HOLE_SPACING_MIN:
					errors.append("%s: holes %d and %d closer than %.0f px" % [
						label, i, j, HOLE_SPACING_MIN])

	# Same-layer plates must never overlap: they share a collision layer, so
	# resting penetration would explode the physics.
	for i in plates.size():
		for j in range(i + 1, plates.size()):
			var a: Dictionary = plates[i]
			var b: Dictionary = plates[j]
			if int(a["layer"]) != int(b["layer"]):
				continue
			if not Geometry2D.intersect_polygons(a["points"], b["points"]).is_empty():
				errors.append("plates %d and %d overlap but share layer %d" % [
					a["id"], b["id"], a["layer"]])

	# Screws: valid unique holes; pinned sets consistent with geometry.
	var rest_plates: Array = []
	for plate: Dictionary in plates:
		rest_plates.append({
			"id": plate["id"], "layer": plate["layer"],
			"points": plate["points"], "holes": plate["holes"],
			"xform": Transform2D.IDENTITY,
		})
	var used_holes := {}
	var pinned_per_plate := {}
	for s: Dictionary in screws:
		var hole: int = s["hole"]
		if hole < 0 or hole >= board_holes.size():
			errors.append("screw hole index %d out of range" % hole)
			continue
		if used_holes.has(hole):
			errors.append("board hole %d used by more than one screw" % hole)
		used_holes[hole] = true
		var point := board_holes[hole]
		var covering := Rules.covering_plates(point, rest_plates)
		covering.sort()
		var declared: Array = (s["plates"] as Array).duplicate()
		declared.sort()
		var same := covering.size() == declared.size()
		if same:
			for k in covering.size():
				if int(covering[k]) != int(declared[k]):
					same = false
					break
		if not same:
			errors.append("screw at hole %d declares plates %s but covers %s" % [
				hole, declared, covering])
		for pid in covering:
			var plate := _plate_by_id(int(pid), plates)
			if plate.is_empty():
				continue
			var aligned := false
			for h: Vector2 in plate["holes"]:
				if h.distance_to(point) <= REST_ALIGN_TOLERANCE:
					aligned = true
					break
			if not aligned:
				errors.append("screw at hole %d: plate %d has no aligned hole" % [hole, pid])
			pinned_per_plate[int(pid)] = int(pinned_per_plate.get(int(pid), 0)) + 1

	for plate: Dictionary in plates:
		if int(pinned_per_plate.get(int(plate["id"]), 0)) < 1:
			errors.append("plate %d starts with no screws (would fall instantly)" % plate["id"])

	if screws.size() >= board_holes.size():
		errors.append("no empty board hole at start (%d screws, %d holes)" % [
			screws.size(), board_holes.size()])
	return errors


static func _plate_by_id(pid: int, plates: Array) -> Dictionary:
	for p: Dictionary in plates:
		if int(p["id"]) == pid:
			return p
	return {}


static func _signed_area(points: PackedVector2Array) -> float:
	var area := 0.0
	for i in points.size():
		var a := points[i]
		var b := points[(i + 1) % points.size()]
		area += a.x * b.y - b.x * a.y
	return area * 0.5


static func _distance_to_edges(p: Vector2, points: PackedVector2Array) -> float:
	var best := INF
	for i in points.size():
		var a := points[i]
		var b := points[(i + 1) % points.size()]
		var closest := Geometry2D.get_closest_point_to_segment(p, a, b)
		best = minf(best, p.distance_to(closest))
	return best
