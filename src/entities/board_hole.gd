class_name BoardHole
extends Area2D
## A screw hole in the backboard. Drawn as a dark recess; highlights while a
## screw is in hand and this hole is a legal destination.

signal tapped(hole: BoardHole)

const RADIUS := 14.0
const TOUCH_RADIUS := 27.0
const TAP_DEBOUNCE_MS := 150

var hole_index: int = -1
var highlighted := false:
	set(value):
		highlighted = value
		queue_redraw()

var _last_tap_ms := 0


func _ready() -> void:
	input_pickable = true
	z_index = -5  # behind all plates; plates draw over covered holes
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = TOUCH_RADIUS
	shape.shape = circle
	add_child(shape)


func _draw() -> void:
	draw_circle(Vector2.ZERO, RADIUS, Color("#1e2c3a"))
	draw_circle(Vector2.ZERO, RADIUS - 4.0, Color("#141f2a"))
	if highlighted:
		draw_arc(Vector2.ZERO, RADIUS + 6.0, 0.0, TAU, 32, Color("#e8a33d"), 4.0)


func _input_event(_viewport: Viewport, event: InputEvent, _shape_idx: int) -> void:
	var pressed := false
	if event is InputEventScreenTouch and event.pressed:
		pressed = true
	elif event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT:
		pressed = true
	if not pressed:
		return
	var now := Time.get_ticks_msec()
	if now - _last_tap_ms < TAP_DEBOUNCE_MS:
		return
	_last_tap_ms = now
	tapped.emit(self)


## Brief shake for an invalid destination tap.
func play_invalid_feedback() -> void:
	var start_x := position.x
	var tw := create_tween()
	tw.tween_property(self, "position:x", start_x + 5.0, 0.04)
	tw.tween_property(self, "position:x", start_x - 5.0, 0.07)
	tw.tween_property(self, "position:x", start_x, 0.04)
