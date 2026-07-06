class_name FallingPlate
extends RigidBody2D
## Visual+physics stand-in spawned when a plate loses its last screw.
## Falls with gravity and a little spin, frees itself below the screen.

const KILL_Y := 2000.0


static func create_from(points: PackedVector2Array, fill: Color, plate_z: int) -> FallingPlate:
	var body := FallingPlate.new()
	# Recenter on the polygon centroid so the spin looks natural.
	var centroid := Vector2.ZERO
	for p in points:
		centroid += p
	centroid /= points.size()
	var local_points := PackedVector2Array()
	for p in points:
		local_points.append(p - centroid)

	body.position = centroid
	body.z_index = plate_z
	body.gravity_scale = 2.0
	body.angular_velocity = randf_range(-3.0, 3.0)
	body.linear_velocity = Vector2(randf_range(-60.0, 60.0), randf_range(-120.0, -40.0))

	var col := CollisionPolygon2D.new()
	col.polygon = local_points
	body.add_child(col)

	var visual := Polygon2D.new()
	visual.polygon = local_points
	visual.color = fill
	body.add_child(visual)

	var outline := Line2D.new()
	var pts := local_points.duplicate()
	pts.append(pts[0])
	outline.points = pts
	outline.width = 4.0
	outline.default_color = fill.darkened(0.45)
	outline.joint_mode = Line2D.LINE_JOINT_ROUND
	body.add_child(outline)
	return body


func _physics_process(_delta: float) -> void:
	if global_position.y > KILL_Y:
		queue_free()
