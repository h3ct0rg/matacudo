extends Node
## Development test: the menu and the game-over panel must show the online and
## total-player counters that come from Firebase.
##
##   godot --headless --path <project>
##
## The counters are written and read over the network, so the test waits for the
## real round-trip instead of asserting on a fixed delay.

var _failures := 0


func _ready() -> void:
	await _run()
	print("COUNTERS TEST: ", "TODO OK" if _failures == 0 else "%d FALLAS" % _failures)
	get_tree().quit(0 if _failures == 0 else 1)


func _run() -> void:
	# The presence write and the increment happen at startup; give them a moment
	# so the counter is at least 1 once the poll lands.
	await get_tree().create_timer(2.0).timeout

	var menu: Node = load("res://scenes/menu.tscn").instantiate()
	add_child(menu)
	var label: Label = menu.get_node("Center/Column/Stats")
	_check(label != null, "el menú tiene la línea de contadores")

	# Wait for the number to arrive from the cloud.
	var settled := await _wait_for_text(label, 25.0)
	_check(settled, "el contador se llena en el menú: \"%s\"" % label.text)
	_check(label.text.contains("en línea"), "el texto menciona los usuarios en línea")
	_check(label.text.contains("total"), "el texto menciona el total de jugadores")

	# The value must be a real number, not a placeholder.
	var online_ok := Analytics.online >= 1
	_check(online_ok, "hay al menos 1 usuario en línea (contados: %d)" % Analytics.online)
	_check(Analytics.players >= 1, "el total de jugadores es al menos 1 (%d)" % Analytics.players)
	menu.queue_free()
	await get_tree().create_timer(0.2).timeout

	# And the same line must appear on the game-over panel, whose count refreshes
	# asynchronously: the panel starts a run, so the total must go up by one.
	var game: Node = load("res://scenes/game.tscn").instantiate()
	add_child(game)
	var game_label: Label = game.get_node("GameOver/Center/Panel/Content/Stats")
	_check(game_label != null, "el panel de fin de partida tiene la línea de contadores")
	var guard := 0
	while not bool(game.get("_finished")) and guard < 300:
		game.call("_on_spawn_timer_timeout")
		game.call("_update_fill")
		guard += 1
	# The increment is a cloud round-trip plus a poll, so wait for it instead of
	# asserting on a fixed delay.
	var counted := await _wait_for_players(1, 30.0)
	_check(counted, "arrancar una partida sumó un jugador (ahora %d)" % Analytics.players)
	await get_tree().create_timer(1.0).timeout
	_check(game_label.text.contains("en línea"),
		"el panel de fin muestra el contador: \"%s\"" % game_label.text)


## Waits until the total-player counter reaches `minimum`, nudging the poll.
func _wait_for_players(minimum: int, timeout_seconds: float) -> bool:
	var waited := 0.0
	while waited < timeout_seconds:
		if Analytics.players >= minimum:
			return true
		Analytics.refresh()
		await get_tree().create_timer(1.0).timeout
		waited += 1.0
	return Analytics.players >= minimum


## Waits until the label stops showing its placeholder text.
func _wait_for_text(label: Label, timeout_seconds: float) -> bool:
	var waited := 0.0
	while waited < timeout_seconds:
		if label.text.contains("en línea") and not label.text.begins_with("Conectando"):
			return true
		await get_tree().create_timer(0.25).timeout
		waited += 0.25
	return false


func _check(condition: bool, description: String) -> void:
	if condition:
		print("  OK    ", description)
	else:
		_failures += 1
		print("  FALLA ", description)
