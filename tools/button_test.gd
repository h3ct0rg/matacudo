extends Node
## Development test: clicks the two end-of-run buttons with injected input while
## the tree is paused, and judges the result by what actually changed (a new
## game instance, or a different scene) instead of by local instrumentation.
##
## A first version captured a flag in a lambda; GDScript lambdas capture by
## value, so the flag never flipped and the test failed even when the buttons
## worked. Judging observable outcomes avoids that trap entirely.

var _failures := 0
## Handlers record by appending: an Array is captured by reference in a lambda,
## unlike the boolean the first version of this test tried to flip.
var _fired: Array[String] = []


func _ready() -> void:
	_start.call_deferred()


func _start() -> void:
	# Re-home this harness outside the scene slot, so `reload_current_scene`
	# and `change_scene_to_file` behave exactly as in the shipped game. The tree
	# is captured first: leaving the tree clears get_tree().
	var tree := get_tree()
	var root: Window = tree.root
	root.remove_child(self)
	await tree.process_frame
	root.add_child(self)
	# Re-hook every time the scene changes, so the buttons under test always
	# report what they receive.
	tree.node_added.connect(_hook)
	_run()


func _hook(node: Node) -> void:
	if node is Button and not node.pressed.is_connected(_mark):
		node.pressed.connect(_mark.bind(node.name))


func _mark(which: String) -> void:
	_fired.append(which)


## Attaches the recorder to one button. `_fired` is an Array on purpose: a
## GDScript lambda captures a local by value, so a boolean flag would never flip.
func _watch(button: Button) -> void:
	if not button.pressed.is_connected(_mark):
		button.pressed.connect(_mark.bind(button.name))


func _run() -> void:
	await get_tree().process_frame

	# 1. JUGAR OTRA VEZ must start a fresh run.
	get_tree().change_scene_to_file("res://scenes/game.tscn")
	await get_tree().create_timer(0.5).timeout
	var game: Node = get_tree().current_scene
	_check(game != null and game.name == "Game", "la escena actual es la partida")
	await _force_game_over(game)

	var play: Button = game.get_node("GameOver/Center/Panel/Content/Buttons2/Play")
	_check(_tree_paused(), "el árbol está pausado al terminar la partida")
	_check(play.is_visible_in_tree(), "el botón JUGAR OTRA VEZ está visible")
	_watch(play)
	await _click(play)
	await get_tree().create_timer(1.2).timeout
	_check(_fired.has("Play"), "el clic llegó al botón JUGAR OTRA VEZ")
	var after_play: Node = get_tree().current_scene
	_check(after_play != null and after_play.name == "Game",
		"JUGAR OTRA VEZ deja la partida cargada (actual: %s)" % _scene_name())
	_check(after_play != game, "es una partida nueva, no la misma instancia")
	_check(not _tree_paused(), "el árbol se despausa al reiniciar")

	# 2. MENÚ must go back to the menu.
	await _force_game_over(after_play)
	var menu_button: Button = after_play.get_node("GameOver/Center/Panel/Content/Buttons2/Menu")
	_check(menu_button.is_visible_in_tree(), "el botón MENÚ está visible")
	_watch(menu_button)
	await _click(menu_button)
	await get_tree().create_timer(1.2).timeout
	_check(_fired.has("Menu"), "el clic llegó al botón MENÚ")
	_check(_scene_name() == "Menu", "MENÚ vuelve al menú (actual: %s)" % _scene_name())
	_check(not _tree_paused(), "el árbol se despausa al volver al menú")

	# 3. And the menu's own button still works afterwards.
	var start: Button = get_tree().current_scene.get_node_or_null("Center/Column/StartButton")
	_check(start != null, "el menú cargó su botón COMENZAR")
	if start != null:
		await _click(start)
		await get_tree().create_timer(1.2).timeout
		_check(_scene_name() == "Game", "COMENZAR sigue funcionando (actual: %s)" % _scene_name())
	_finish()


## Fills the window until the run ends, then lets the overlay settle.
func _force_game_over(game: Node) -> void:
	var guard := 0
	while game != null and not bool(game.get("_finished")) and guard < 300:
		game.call("_on_spawn_timer_timeout")
		game.call("_update_fill")
		guard += 1
	await get_tree().create_timer(0.6).timeout
	await get_tree().process_frame
	await get_tree().process_frame


## Clicks the control the way a mouse does: pointer motion onto it, then a press
## and a release through the engine's own input pipeline.
func _click(control: Control) -> void:
	var at: Vector2 = control.get_global_rect().get_center()
	var move := InputEventMouseMotion.new()
	move.position = at
	move.global_position = at
	Input.parse_input_event(move)
	await get_tree().process_frame
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
		event.pressed = pressed
		event.position = at
		event.global_position = at
		Input.parse_input_event(event)
		await get_tree().process_frame


func _tree_paused() -> bool:
	return get_tree().paused


func _scene_name() -> String:
	var scene: Node = get_tree().current_scene
	return scene.name if scene != null else "<null>"


func _check(condition: bool, description: String) -> void:
	if condition:
		print("  OK    ", description)
	else:
		_failures += 1
		print("  FALLA ", description)


func _finish() -> void:
	print("BUTTONS RESULT: ", "TODO OK" if _failures == 0 else "%d FALLAS" % _failures)
	get_tree().quit(0 if _failures == 0 else 1)
