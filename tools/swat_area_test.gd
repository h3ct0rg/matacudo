extends Node
## Development test for the swat area and its on-screen indicator.
##
##   godot --path <project>          (windowed: the indicator needs a viewport)
##
## Verifies that the collision shape and the advertised radius agree, that a
## press near the edge of the circle still swats, that a press beyond it does
## not, and that the indicator appears exactly once per press — the project
## emulates touch from the mouse, so a careless handler would draw two circles
## for one desktop click.

var _game: Node
var _failures := 0
var _marks_at_click := 0


func _ready() -> void:
	await _run()
	print("SWAT AREA TEST: ", "TODO OK" if _failures == 0 else "%d FALLAS" % _failures)
	get_tree().quit(0 if _failures == 0 else 1)


func _run() -> void:
	await get_tree().process_frame
	_game = load("res://scenes/game.tscn").instantiate()
	add_child(_game)
	await get_tree().create_timer(0.3).timeout

	# --- the shape and the advertised radius must match -------------------
	var scene: PackedScene = load("res://scenes/mosquito.tscn")
	var probe: Area2D = scene.instantiate()
	add_child(probe)
	var circle: CircleShape2D = (probe.get_node("CollisionShape2D") as CollisionShape2D).shape
	var advertised: float = _game.get("SWAT_RADIUS")
	_check(is_equal_approx(circle.radius, advertised),
		"el radio de la forma (%.0f) coincide con el anunciado (%.0f)" % [circle.radius, advertised])
	_check(circle.radius > 26.0,
		"el área creció respecto al valor anterior de 26 (ahora %.0f = %.1fx)" % [circle.radius, circle.radius / 26.0])
	probe.queue_free()

	# --- the indicator appears once per click ----------------------------
	_clear()
	await get_tree().create_timer(0.4).timeout
	var count_before: int = (_game.get("_press_marks") as Array).size()
	_click(Vector2(300, 200))
	await get_tree().create_timer(0.15).timeout
	var marks: Array = _game.get("_press_marks")
	_marks_at_click = marks.size() - count_before
	_check(_marks_at_click == 1,
		"un clic muestra exactamente un círculo (mostró %d)" % _marks_at_click)
	if _marks_at_click >= 1:
		var at: Vector2 = marks[marks.size() - 1]
		_check(at.distance_to(Vector2(300, 200)) < 2.0,
			"el círculo aparece donde se hizo clic (%.0f,%.0f)" % [at.x, at.y])

	# --- a press at the edge of the circle still swats -------------------
	var mosquito: Node2D = await _spawn_one()
	mosquito.set_physics_process(false)
	var center: Vector2 = mosquito.global_position
	var before := GameData.score
	_click(center + Vector2(advertised - 4.0, 0.0))
	await get_tree().create_timer(0.25).timeout
	_check(GameData.score > before,
		"un clic dentro del círculo aplasta (a %.0f unidades del centro)" % (advertised - 4.0))

	# --- and one clearly outside it does not -----------------------------
	var second: Node2D = await _spawn_one()
	second.set_physics_process(false)
	var before_outside := GameData.score
	_click(second.global_position + Vector2(advertised + 30.0, 0.0))
	await get_tree().create_timer(0.25).timeout
	_check(GameData.score == before_outside,
		"un clic bien fuera del círculo NO aplasta (a %.0f unidades)" % (advertised + 30.0))

	# --- the circle also appears when the press hits nothing --------------
	count_before = (_game.get("_press_marks") as Array).size()
	_click(Vector2(1000, 600))
	await get_tree().create_timer(0.15).timeout
	_check((_game.get("_press_marks") as Array).size() > count_before,
		"el círculo aparece también cuando el clic no acierta")


func _spawn_one() -> Node2D:
	_game.call("_on_spawn_timer_timeout")
	for child in _game.get_node("Mosquitoes").get_children():
		if is_instance_valid(child):
			return child
	return null


func _clear() -> void:
	for child in _game.get_node("Mosquitoes").get_children():
		child.queue_free()


## Sends a real press+release through the engine's input pipeline.
func _click(at: Vector2) -> void:
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
		event.pressed = pressed
		event.position = at
		event.global_position = at
		Input.parse_input_event(event)
		await get_tree().process_frame


func _check(condition: bool, description: String) -> void:
	if condition:
		print("  OK    ", description)
	else:
		_failures += 1
		print("  FALLA ", description)
