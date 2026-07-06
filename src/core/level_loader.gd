class_name LevelLoader
extends RefCounted
## Loads JSON level definitions from res://levels/ and validates them.
## The same validation runs in the headless test suite, so every shipped
## level is checked against the rules below.

const LEVELS_DIR := "res://levels/"
const INDEX_PATH := "res://levels/index.json"
const MIN_PLATE_AREA := 2000.0
const SCREW_RADIUS := 22.0
const EDGE_MARGIN := 24.0
const MIN_SCREWS_PER_PLATE := 1
const MAX_SCREWS_PER_PLATE := 4

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


## Converts raw JSON into a typed structure:
## { id: int, name: String, bounds: Vector2,
##   plates: [ { id: int, layer: int, color: Color,
##               points: PackedVector2Array, screws: PackedVector2Array } ] }
static func parse_level(raw: Variant) -> Dictionary:
	if not (raw is Dictionary):
		return {}
	var level := {
		"id": int(raw.get("id", 0)),
		"name": String(raw.get("name", "")),
		"bounds": Vector2(720, 1000),
		"plates": [],
	}
	var raw_bounds: Variant = raw.get("bounds")
	if raw_bounds is Array and raw_bounds.size() == 2:
		level["bounds"] = Vector2(float(raw_bounds[0]), float(raw_bounds[1]))
	for raw_plate: Variant in raw.get("plates", []):
		if not (raw_plate is Dictionary):
			continue
		var plate := {
			"id": int(raw_plate.get("id", -1)),
			"layer": int(raw_plate.get("layer", 0)),
			"color": Color.from_string(String(raw_plate.get("color", "#8fa3b8")), Color("#8fa3b8")),
			"points": _to_vec_array(raw_plate.get("points", [])),
			"screws": _to_vec_array(raw_plate.get("screws", [])),
		}
		level["plates"].append(plate)
	return level


static func _to_vec_array(raw: Variant) -> PackedVector2Array:
	var out := PackedVector2Array()
	if raw is Array:
		for pair: Variant in raw:
			if pair is Array and pair.size() == 2:
				out.append(Vector2(float(pair[0]), float(pair[1])))
	return out


## Returns a list of human-readable errors; empty means the level is valid.
## Does NOT include solvability -- call Solver.is_solvable separately.
static func validate(level: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	if level.is_empty():
		errors.append("level is empty or failed to parse")
		return errors
	var plates: Array = level["plates"]
	if plates.is_empty():
		errors.append("level has no plates")
		return errors

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
		if absf(_signed_area(points)) < MIN_PLATE_AREA:
			errors.append("%s: area below minimum %.0f" % [label, MIN_PLATE_AREA])

		var screws: PackedVector2Array = plate["screws"]
		if screws.size() < MIN_SCREWS_PER_PLATE or screws.size() > MAX_SCREWS_PER_PLATE:
			errors.append("%s: has %d screws (allowed %d..%d)" % [
				label, screws.size(), MIN_SCREWS_PER_PLATE, MAX_SCREWS_PER_PLATE])
		for s in screws:
			if not Geometry2D.is_point_in_polygon(s, points):
				errors.append("%s: screw %s outside plate" % [label, s])
			elif _distance_to_edges(s, points) < EDGE_MARGIN:
				errors.append("%s: screw %s too close to plate edge" % [label, s])

	# Overlapping plates must sit on different layers, otherwise the
	# blocking rule is ambiguous.
	for i in plates.size():
		for j in range(i + 1, plates.size()):
			var a: Dictionary = plates[i]
			var b: Dictionary = plates[j]
			if int(a["layer"]) != int(b["layer"]):
				continue
			if not Geometry2D.intersect_polygons(a["points"], b["points"]).is_empty():
				errors.append("plates %d and %d overlap but share layer %d" % [
					a["id"], b["id"], a["layer"]])
	return errors


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
