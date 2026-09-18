extends Node
## Development capture: presses twice inside a running game — once on a mosquito
## and once on empty glass — and photographs the swat circle while it is still on
## screen, so its size and look can be judged.
##
## Writes user://swat_circle.png.

var _game: Node


func _ready() -> void:
	await _run()


func _run() -> void:
	await get_tree().process_frame
	_game = load("res://scenes/game.tscn").instantiate()
	add_child(_game)
	await get_tree().create_timer(0.4).timeout

	# A mosquito held still, so the circle lands where the picture expects it.
	var mosquito: Node2D = _spawn_one()
	mosquito.set_physics_process(false)
	mosquito.global_position = Vector2(380, 300)

	# Second, empty spot.
	_press(Vector2(760, 420))
	await get_tree().process_frame
	# First press: on the mosquito, a moment earlier so it has faded a little and
	# both stages of the animation are visible at once.
	_press(mosquito.global_position)
	await get_tree().create_timer(0.12).timeout
	await RenderingServer.frame_post_draw

	var image := get_viewport().get_texture().get_image()
	image.save_png("user://swat_circle.png")
	print("captura -> user://swat_circle.png")
	print("círculos dibujados: ", (_game.get("_press_marks") as Array).size())
	get_tree().quit()


func _spawn_one() -> Node2D:
	_game.call("_on_spawn_timer_timeout")
	for child in _game.get_node("Mosquitoes").get_children():
		if is_instance_valid(child):
			return child
	return null


func _press(at: Vector2) -> void:
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
		event.pressed = pressed
		event.position = at
		event.global_position = at
		Input.parse_input_event(event)
