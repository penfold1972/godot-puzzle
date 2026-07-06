class_name Screw
extends Area2D
## A tappable screw head. Drawn procedurally (no textures): metallic disc
## with a Phillips cross slot that visibly spins when (un)screwed.
## v2: screws never leave the board -- they move between board holes.
## States: SET (in a hole) and IN_HAND (lifted, hovering over origin hole,
## waiting for a destination tap; physics is frozen meanwhile).

signal tapped(screw: Screw)

enum State { SET, IN_HAND }

const RADIUS := 20.0
const TOUCH_RADIUS := 27.0
const TURN_TIME := 0.4
const HOP_TIME := 0.25
const TAP_DEBOUNCE_MS := 150

var hole_index: int = -1
var state: int = State.SET
var busy := false
var _shaking := false
var _last_tap_ms := 0
var _pulse: Tween


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
	# spins the slot during animations.
	draw_circle(Vector2.ZERO, RADIUS, Color("#6b7885"))
	draw_circle(Vector2.ZERO, RADIUS - 3.0, Color("#ccd5dd"))
	draw_circle(Vector2(-4, -5), RADIUS - 9.0, Color("#e4eaef"))
	var slot := Color("#4a545e")
	draw_line(Vector2(-12, 0), Vector2(12, 0), slot, 5.0)
	draw_line(Vector2(0, -12), Vector2(0, 12), slot, 5.0)


func _input_event(_viewport: Viewport, event: InputEvent, _shape_idx: int) -> void:
	if busy:
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
	if _shaking or busy:
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


## Spin out of the hole and hover in hand above it. Await the returned
## signal to know when the lift finished.
func lift_out() -> Signal:
	busy = true
	state = State.IN_HAND
	z_index = 100
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(self, "rotation", rotation - 4.0 * PI, TURN_TIME)
	tw.tween_property(self, "scale", Vector2(1.3, 1.3), TURN_TIME)
	tw.tween_property(self, "position:y", position.y - 18.0, TURN_TIME)
	tw.set_parallel(false)
	tw.tween_callback(_start_pulse)
	tw.tween_callback(func() -> void: busy = false)
	return tw.finished


## Hop to a hole position and screw in. Await the returned signal.
func screw_in(target: Vector2, target_hole_index: int) -> Signal:
	busy = true
	_stop_pulse()
	hole_index = target_hole_index
	var tw := create_tween()
	tw.tween_property(self, "position", target + Vector2(0, -18), HOP_TIME) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.set_parallel(true)
	tw.tween_property(self, "rotation", rotation + 4.0 * PI, TURN_TIME)
	tw.tween_property(self, "scale", Vector2.ONE, TURN_TIME)
	tw.tween_property(self, "position", target, TURN_TIME)
	tw.set_parallel(false)
	tw.tween_callback(func() -> void:
		state = State.SET
		z_index = 1
		busy = false)
	return tw.finished


func _start_pulse() -> void:
	_stop_pulse()
	_pulse = create_tween().set_loops()
	_pulse.tween_property(self, "modulate", Color(1.25, 1.2, 0.9), 0.4)
	_pulse.tween_property(self, "modulate", Color.WHITE, 0.4)


func _stop_pulse() -> void:
	if _pulse != null and _pulse.is_valid():
		_pulse.kill()
	_pulse = null
	modulate = Color.WHITE
