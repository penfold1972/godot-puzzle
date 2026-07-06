class_name PlateBody
extends RigidBody2D
## A metal plate as a physics body. Support states (driven by game.gd):
##   >=2 screws -> frozen STATIC (immovable, still collides)
##   exactly 1  -> unfrozen + a PinJoint2D at the screw (swings under gravity)
##   0 screws   -> unfrozen, no joints, falls with CCD; frees itself off screen
## Plates only collide with plates on the SAME layer (visual depth = physical
## depth), so braces swing over base pieces but tiling neighbours jam each
## other -- and resting same-layer overlap is forbidden by the validator.
##
## The polygon/hole coordinates in level data are board coordinates; the body
## spawns at identity, so local == board space at rest.

signal fell_off(plate: PlateBody)

const KILL_Y := 2000.0
const OUTLINE_WIDTH := 4.0
const HOLE_RING_RADIUS := 13.0

var plate_id: int = -1
var layer: int = 0
var points := PackedVector2Array()
var holes := PackedVector2Array()
var fill_color := Color("#8fa3b8")
var _centroid := Vector2.ZERO
var _reported_fall := false


func setup(data: Dictionary) -> void:
	plate_id = int(data["id"])
	layer = int(data["layer"])
	points = data["points"]
	holes = data["holes"]
	fill_color = data["color"]
	z_index = layer

	var bit: int = clampi(layer, 0, 19)
	collision_layer = 1 << bit
	collision_mask = 1 << bit

	for p in points:
		_centroid += p
	_centroid /= points.size()

	# Start immobile; game.gd applies the real support state after building.
	lock_rotation = false
	freeze_mode = RigidBody2D.FREEZE_MODE_STATIC
	freeze = true
	angular_damp = 2.5
	linear_damp = 0.2
	mass = clampf(absf(_area()) / 15000.0, 0.5, 8.0)

	for convex in Geometry2D.decompose_polygon_in_convex(points):
		var shape := CollisionPolygon2D.new()
		shape.polygon = convex
		add_child(shape)

	var visual := Polygon2D.new()
	visual.polygon = points
	visual.color = fill_color
	add_child(visual)

	var outline := Line2D.new()
	var pts := points.duplicate()
	pts.append(pts[0])
	outline.points = pts
	outline.width = OUTLINE_WIDTH
	outline.default_color = fill_color.darkened(0.45)
	outline.joint_mode = Line2D.LINE_JOINT_ROUND
	add_child(outline)

	# Screw-hole dimples drawn ABOVE the fill polygon (a plain _draw on the
	# body would render underneath the Polygon2D child). They move/rotate
	# with the plate, matching the hole positions Rules evaluates through
	# the transform.
	var dimples := Node2D.new()
	dimples.draw.connect(func() -> void:
		for h in holes:
			dimples.draw_circle(h, HOLE_RING_RADIUS, fill_color.darkened(0.55))
			dimples.draw_circle(h, HOLE_RING_RADIUS - 4.0, fill_color.darkened(0.3)))
	add_child(dimples)
	dimples.queue_redraw()


## Support state setters -- all deferred: physics state must never be
## mutated during a physics callback.
func make_static() -> void:
	set_deferred("freeze_mode", RigidBody2D.FREEZE_MODE_STATIC)
	set_deferred("freeze", true)


func make_dynamic() -> void:
	# Used for both swinging (game adds a joint) and free fall.
	continuous_cd = RigidBody2D.CCD_MODE_CAST_SHAPE
	set_deferred("freeze", false)


## Kinematic hold for the in-hand world freeze: keeps the exact pose.
func hold_kinematic() -> void:
	set_deferred("freeze_mode", RigidBody2D.FREEZE_MODE_KINEMATIC)
	set_deferred("freeze", true)


func current_local_snapshot() -> Dictionary:
	## Snapshot for Rules queries in board space.
	return {
		"id": plate_id,
		"layer": layer,
		"points": points,
		"holes": holes,
		"xform": transform,
	}


func _physics_process(_delta: float) -> void:
	if _reported_fall:
		return
	if (global_transform * _centroid).y > KILL_Y:
		_reported_fall = true
		fell_off.emit(self)
		queue_free()


func _area() -> float:
	var area := 0.0
	for i in points.size():
		var a := points[i]
		var b := points[(i + 1) % points.size()]
		area += a.x * b.y - b.x * a.y
	return area * 0.5
