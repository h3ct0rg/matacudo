extends Area2D
## One mosquito: flies inside the window forever until the player swats it.
## Nothing removes it on its own — a mosquito left alive keeps taking up screen
## space, which is what eventually fills the window and ends the run.

signal swatted(points: int, position: Vector2)

## Playfield the mosquito is steered inside, in world coordinates.
var bounds := Rect2(60, 60, 1160, 600)
## Pixels per second at spawn.
var speed := 240.0
## Screen share this mosquito takes up, as a fraction of the playfield (0..1).
var screen_share := 0.021
## Whether it counts as a big one (bigger, faster, worth more).
var is_big := false

var _velocity := Vector2.ZERO
var _wobble_phase := 0.0
var _turn_timer := 0.0
var _age := 0.0
var _done := false

@onready var _sprite: AnimatedSprite2D = $Sprite


func setup(cfg: Dictionary) -> void:
	speed = cfg.get("speed", speed)
	bounds = cfg.get("bounds", bounds)
	is_big = cfg.get("is_big", false)
	screen_share = cfg.get("screen_share", screen_share)


func _ready() -> void:
	_wobble_phase = randf() * TAU
	_turn_timer = randf_range(0.25, 0.8)
	if is_big:
		_sprite.scale = Vector2(1.35, 1.35)
		# The big one reads as the tougher target, so tint it warmer.
		_sprite.modulate = Color(1.12, 0.94, 0.82)
	_pick_direction()
	_sprite.play("fly")


## How long this mosquito has been alive, in seconds.
func age() -> float:
	return _age


## Points for killing it right now: fast swats pay more, so the player is
## pushed to swat early instead of letting the window fill up.
func points_now() -> int:
	var bonus := int(round(maxf(0.0, 1.0 - _age / 10.0)))
	return (3 if is_big else 2) + bonus


func _physics_process(delta: float) -> void:
	if _done:
		return
	_age += delta

	_turn_timer -= delta
	if _turn_timer <= 0.0:
		_pick_direction()
		_turn_timer = randf_range(0.3, 0.9)

	# Wobble the heading so the flight path is not a straight line.
	var angle := _velocity.angle() + sin(_wobble_phase + _age * 5.0) * 0.55 * delta * 3.0
	_velocity = Vector2.from_angle(angle) * speed
	position += _velocity * delta

	# Bounce off the playfield edges instead of leaving the window.
	if position.x < bounds.position.x and _velocity.x < 0.0:
		_velocity.x = absf(_velocity.x)
	elif position.x > bounds.end.x and _velocity.x > 0.0:
		_velocity.x = -absf(_velocity.x)
	if position.y < bounds.position.y and _velocity.y < 0.0:
		_velocity.y = absf(_velocity.y)
	elif position.y > bounds.end.y and _velocity.y > 0.0:
		_velocity.y = -absf(_velocity.y)
	position = position.clamp(bounds.position, bounds.end)

	_update_facing()


## Keeps the insect the right way up: it turns to face its heading while
## travelling up, and is mirrored (never hung upside down) when heading down.
func _update_facing() -> void:
	var heading := _velocity.angle() + PI / 2.0
	if absf(heading) > PI / 2.0:
		rotation = heading + PI
		_sprite.flip_v = true
	else:
		rotation = heading
		_sprite.flip_v = false
	_sprite.rotation = sin(_age * 7.0) * 0.1


func _pick_direction() -> void:
	_velocity = Vector2.from_angle(randf() * TAU) * speed


## Touch on mobile and mouse click on desktop both arrive here, because the
## project maps pointer events to emulated mouse input.
func _input_event(_viewport: Node, event: InputEvent, _shape_index: int) -> void:
	if _done:
		return
	var pressed := false
	if event is InputEventScreenTouch:
		pressed = event.pressed
	elif event is InputEventMouseButton:
		pressed = event.pressed and event.button_index == MOUSE_BUTTON_LEFT
	if not pressed:
		return
	_swat()


## Public so tests and the game can resolve a swat without an input event.
func _swat() -> void:
	if _done:
		return
	_done = true
	set_deferred("monitoring", false)
	Sfx.play_squish()
	swatted.emit(points_now(), position)

	# Squash out of existence even while the tree is paused by the game-over
	# overlay: the tween must keep processing.
	var tween := create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.set_parallel(true)
	tween.tween_property(_sprite, "scale", _sprite.scale * Vector2(1.5, 0.45), 0.16)
	tween.tween_property(_sprite, "modulate:a", 0.0, 0.16)
	tween.chain().tween_callback(queue_free)
