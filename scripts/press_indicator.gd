extends Node2D
## The pressing feedback: a soft circle that marks, for a moment, exactly the
## area a tap or click counts as a hit. Drawing it at the real swipe radius is
## the point — it teaches where the game is forgiving, which is not something the
## player can guess when the circle is larger than the mosquito.

## Seconds the circle takes to expand and fade out.
const DURATION := 0.28
## Ring thickness just after the press.
const START_WIDTH := 8.0
## Fill and ring are dark amber on purpose: the playfield is a pale window, and a
## light ring washes out against it.
const FILL := Color(0.55, 0.30, 0.0, 0.30)
const RING := Color(0.85, 0.42, 0.05, 1.0)
const RING_DARK := Color(0.25, 0.10, 0.0, 0.55)

var _radius := 40.0
var _progress := 0.0
var _fade: Tween


func show_press(at: Vector2, radius: float) -> void:
	position = at
	if not is_equal_approx(radius, _radius):
		_radius = radius
		queue_redraw()
	# Retrigger cleanly: a fast second tap restarts the animation instead of
	# stacking a second circle on top of the first.
	if _fade != null and _fade.is_valid():
		_fade.kill()
	_fade = create_tween()
	_fade.tween_method(_set_progress, 0.0, 1.0, DURATION) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_fade.tween_callback(queue_free)


func _set_progress(value: float) -> void:
	_progress = value
	queue_redraw()


func _draw() -> void:
	# Contracts slightly as it fades, which reads as a stomp rather than a wave.
	var shrink := 1.0 + _progress * 0.12
	var faded := 1.0 - _progress
	var radius := _radius * shrink
	draw_circle(Vector2.ZERO, radius, Color(FILL.r, FILL.g, FILL.b, FILL.a * faded))
	# A dark outer edge keeps the ring readable over the glass and the frame.
	draw_arc(Vector2.ZERO, radius + 1.5, 0.0, TAU, 64,
		Color(RING_DARK.r, RING_DARK.g, RING_DARK.b, RING_DARK.a * faded),
		maxf(1.0, (START_WIDTH + 3.0) * faded), true)
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 64,
		Color(RING.r, RING.g, RING.b, RING.a * faded),
		maxf(1.0, START_WIDTH * faded), true)
