class_name Screw
extends Area2D
## A tappable screw head. Drawn procedurally (no textures): metallic disc
## with a Phillips cross slot that visibly spins while unscrewing.

signal tapped(screw: Screw)

const RADIUS := 20.0
const TOUCH_RADIUS := 27.0
const UNSCREW_TIME := 0.45
const TAP_DEBOUNCE_MS := 150

var plate_id: int = -1
var removed := false
var _shaking := false
var _last_tap_ms := 0


func _ready() -> void:
	input_pickable = true
	z_index = 1
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = TOUCH_RADIUS
	shape.shape = circle
	add_child(shape)


func _draw() -> void:
	# Rim, face, and cross slot. Drawn in local space so node rotation
	# spins the slot during the unscrew animation.
	draw_circle(Vector2.ZERO, RADIUS, Color("#6b7885"))
	draw_circle(Vector2.ZERO, RADIUS - 3.0, Color("#ccd5dd"))
	draw_circle(Vector2(-4, -5), RADIUS - 9.0, Color("#e4eaef"))
	var slot := Color("#4a545e")
	draw_line(Vector2(-12, 0), Vector2(12, 0), slot, 5.0)
	draw_line(Vector2(0, -12), Vector2(0, 12), slot, 5.0)


func _input_event(_viewport: Viewport, event: InputEvent, _shape_idx: int) -> void:
	if removed:
		return
	var pressed := false
	if event is InputEventScreenTouch and event.pressed:
		pressed = true
	elif event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT:
		pressed = true
	if not pressed:
		return
	# With touch emulation a single tap can arrive as both a mouse and a
	# touch event; debounce so it only counts once.
	var now := Time.get_ticks_msec()
	if now - _last_tap_ms < TAP_DEBOUNCE_MS:
		return
	_last_tap_ms = now
	tapped.emit(self)


## Shake + red flash for a blocked screw. Non-blocking.
func play_blocked_feedback() -> void:
	if _shaking or removed:
		return
	_shaking = true
	var start_x := position.x
	var tw := create_tween()
	tw.tween_property(self, "modulate", Color(1.0, 0.45, 0.45), 0.05)
	tw.tween_property(self, "position:x", start_x + 6.0, 0.04)
	tw.tween_property(self, "position:x", start_x - 6.0, 0.07)
	tw.tween_property(self, "position:x", start_x + 3.0, 0.05)
	tw.tween_property(self, "position:x", start_x, 0.04)
	tw.tween_property(self, "modulate", Color.WHITE, 0.1)
	tw.finished.connect(func() -> void: _shaking = false)


## Spin out, lift and fade, then free. Await the returned signal to know
## when the animation finished.
func unscrew() -> Signal:
	removed = true
	input_pickable = false
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(self, "rotation", rotation - 4.0 * PI, UNSCREW_TIME)
	tw.tween_property(self, "scale", Vector2(1.35, 1.35), UNSCREW_TIME)
	tw.tween_property(self, "position:y", position.y - 14.0, UNSCREW_TIME)
	tw.tween_property(self, "modulate:a", 0.0, UNSCREW_TIME * 0.6) \
		.set_delay(UNSCREW_TIME * 0.4)
	tw.set_parallel(false)
	tw.tween_callback(queue_free)
	return tw.finished
