class_name Plate
extends Polygon2D
## A metal plate: filled polygon + darker outline, holding Screw children.
## Coordinates in level data are absolute board coordinates; the plate node
## itself sits at the board origin, so children use the same coordinates.

const FallingPlateScript := preload("res://src/entities/falling_plate.gd")
const ScrewScript := preload("res://src/entities/screw.gd")

var plate_id: int = -1
var layer: int = 0
var screw_nodes: Array[Screw] = []


func setup(data: Dictionary) -> void:
	plate_id = int(data["id"])
	layer = int(data["layer"])
	z_index = layer
	polygon = data["points"]
	color = data["color"]

	var outline := Line2D.new()
	var pts: PackedVector2Array = (data["points"] as PackedVector2Array).duplicate()
	pts.append(pts[0])
	outline.points = pts
	outline.width = 4.0
	outline.default_color = (data["color"] as Color).darkened(0.45)
	outline.joint_mode = Line2D.LINE_JOINT_ROUND
	outline.closed = false
	add_child(outline)

	for screw_pos: Vector2 in data["screws"]:
		var screw: Screw = ScrewScript.new()
		screw.position = screw_pos
		screw.plate_id = plate_id
		add_child(screw)
		screw_nodes.append(screw)


## Replace this plate with a physics body that falls off screen, then free.
func detach() -> void:
	var body: RigidBody2D = FallingPlateScript.create_from(polygon, color, z_index)
	get_parent().add_child(body)
	queue_free()
