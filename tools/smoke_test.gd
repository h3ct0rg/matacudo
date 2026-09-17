extends Node
## Development smoke test for the game loop. Run it as the main scene:
##   godot --headless --path <project> --quit-after 6000 res://tools/smoke_test.tscn
##
## Verifies the rules that matter: mosquitoes stay on screen, the run is lost
## when the window fills past 70%, the score is stored under a typed name, and
## the table comes back from the cloud. The entry it uploads is removed again in
## step 5, so a run leaves the real leaderboard clean.

const BASE := "https://chauzancudo-default-rtdb.firebaseio.com/scores"
## Name used only by this test, so its own upload can be identified and removed.
const TEST_NAME := "Zancu_test"

var _game: Node
var _failures := 0
var _http: HTTPRequest


func _ready() -> void:
	_run()


func _run() -> void:
	_http = HTTPRequest.new()
	# The tree is paused by the time the cloud assertions run, so this node must
	# ignore the pause state like the game's own request nodes do.
	_http.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_http)
	await get_tree().process_frame

	# 0. The shipped menu entry scene loads with its pieces.
	var menu: Node = load("res://scenes/menu.tscn").instantiate()
	add_child(menu)
	await get_tree().create_timer(0.2).timeout
	_check(menu.get_node_or_null("Center/Column/StartButton") != null,
		"el menú carga con el botón Comenzar")
	_check(menu.get_node_or_null("Center/Column/Leaderboard/Body/Rows") != null,
		"el menú carga el panel de mejores puntajes")
	menu.queue_free()
	await get_tree().create_timer(0.2).timeout
	_game = load("res://scenes/game.tscn").instantiate()
	add_child(_game)
	await get_tree().create_timer(0.1).timeout

	# 1. A swat awards points and makes the swat sound.
	var mosquito: Node2D = await _spawn_one()
	if mosquito == null:
		_check(false, "no apareció ningún zancudo")
		return _finish()
	var before := GameData.score
	mosquito.call("_swat")
	await get_tree().create_timer(0.2).timeout
	var gained := GameData.score - before
	_check(gained >= 2, "aplastar suma puntos (ganó %d)" % gained)
	_check(Sfx.get_child_count() > 0, "el reproductor de sonido está montado")

	# 2. A mosquito left alive stays on screen.
	var alive: Node2D = await _spawn_one()
	var count_before := _game.get_node("Mosquitoes").get_child_count()
	await get_tree().create_timer(3.0).timeout
	_check(is_instance_valid(alive) and alive.get_parent() != null,
		"un zancudo sin aplastar sigue en pantalla a los 3 segundos")
	_check(_game.get_node("Mosquitoes").get_child_count() >= count_before,
		"la población no disminuye sola (%d -> %d)" % [count_before, _game.get_node("Mosquitoes").get_child_count()])

	# 3. Coverage grows with the population and the loss fires past 70%.
	_clear()
	await get_tree().create_timer(0.5).timeout
	_check(is_equal_approx(float(_game.get("_fill")), 0.0), "sin zancudos la pantalla está al 0%")
	for i in 5:
		_game.call("_on_spawn_timer_timeout")
	await get_tree().create_timer(0.5).timeout
	var fill_five: float = _game.get("_fill")
	var population: int = _game.get_node("Mosquitoes").get_child_count()
	_check(fill_five > 0.03 and fill_five < 0.4,
		"%d zancudos ocupan el %d%% de la pantalla" % [population, roundi(fill_five * 100.0)])

	var guard := 0
	while not bool(_game.get("_finished")) and guard < 200:
		_game.call("_on_spawn_timer_timeout")
		_game.call("_update_fill")
		guard += 1
	_check(bool(_game.get("_finished")),
		"la partida termina al llenarse la pantalla (fill=%d%%)" % roundi(float(_game.get("_fill")) * 100.0))
	_check(float(_game.get("_fill")) > 0.7, "terminó por pasar el 70%% de ocupación")
	_check(_game.get_node("GameOver").visible, "aparece la pantalla de fin de partida")
	var overlay: Control = _game.get_node("GameOver")
	# _fit_overlay applies sizes deferred, so let a couple of frames pass.
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	_check(overlay.size.x > 1000 and overlay.size.y > 600,
		"el panel de fin cubre la ventana (%.0fx%.0f)" % [overlay.size.x, overlay.size.y])
	var panel: Control = _game.get_node("GameOver/Center/Panel")
	var centred := absf(panel.global_position.x - (overlay.size.x - panel.size.x) / 2.0) < 40.0 \
		and absf(panel.global_position.y - (overlay.size.y - panel.size.y) / 2.0) < 40.0
	_check(centred, "el panel de fin queda centrado (%.0f,%.0f)" % [panel.global_position.x, panel.global_position.y])

	# 4. The score is stored under the typed name and comes back from the cloud.
	GameData.score = 7
	var field: LineEdit = _game.get_node("GameOver/Center/Panel/Content/NameEntry/Row/Field")
	var save_button: Button = _game.get_node("GameOver/Center/Panel/Content/NameEntry/Row/Save")
	var name_entry: Control = _game.get_node("GameOver/Center/Panel/Content/NameEntry")
	var leaderboard: Control = _game.get_node("GameOver/Center/Panel/Content/Leaderboard")
	var button_box := _stylebox_of(save_button, "normal")
	_check(save_button.custom_minimum_size.y >= 44,
		"el botón GUARDAR es un botón grande (%d px de alto)" % int(save_button.custom_minimum_size.y))
	_check(button_box != null and button_box.bg_color.a > 0.9,
		"el botón GUARDAR tiene fondo propio (no texto suelto)")
	_check(field.custom_minimum_size.y < save_button.custom_minimum_size.y + 12.0,
		"el campo de nombre está alineado con el botón")

	field.text = TEST_NAME
	_game.call("_on_save_pressed")
	# The name section must disappear once the score is stored.
	var entry_hidden := await _wait_until(func(): return not name_entry.visible, 12.0)
	_check(entry_hidden, "tras guardar desaparece la sección de guardar puntaje")
	await get_tree().process_frame
	await get_tree().process_frame
	var visible_pieces := 0
	for control: Control in [field, save_button, _game.get_node("GameOver/Center/Panel/Content/NameEntry/Prompt")]:
		# is_visible_in_tree, not `visible`: a child keeps visible=true when its
		# parent is hidden, and what matters is whether the player can see it.
		if control.is_visible_in_tree():
			visible_pieces += 1
	_check(visible_pieces == 0, "no queda ningún resto visible de esa sección")
	_check(leaderboard.is_visible_in_tree(), "la lista de mejores puntajes sigue visible")
	await _wait_for_online(12.0)
	_check(GameData.player_name == TEST_NAME, "el nombre se recuerda (\"%s\")" % GameData.player_name)
	_check(GameData.online, "la nube respondió (online=%s, error=\"%s\")" % [str(GameData.online), GameData.last_error])
	var found := false
	for entry in GameData.best_scores:
		if str(entry.get("name", "")) == TEST_NAME:
			found = true
	_check(found, "el puntaje enviado aparece en la tabla (%d entradas)" % GameData.best_scores.size())

	# 5. Remove the entry this test uploaded.
	_check(await _remove_test_entries(), "la entrada de prueba se borró de la nube")
	_finish()


func _spawn_one() -> Node2D:
	_game.call("_on_spawn_timer_timeout")
	for child in _game.get_node("Mosquitoes").get_children():
		if is_instance_valid(child):
			return child
	return null


func _clear() -> void:
	for child in _game.get_node("Mosquitoes").get_children():
		child.queue_free()


## Waits until this test's own entry shows up in the cloud table.
func _wait_for_online(timeout_seconds: float) -> void:
	var waited := 0.0
	while waited < timeout_seconds:
		for entry in GameData.best_scores:
			if str(entry.get("name", "")) == TEST_NAME:
				return
		await get_tree().create_timer(0.2).timeout
		waited += 0.2


## Polls `condition` until it is true or the timeout hits; returns its last value.
func _wait_until(condition: Callable, timeout_seconds: float) -> bool:
	var waited := 0.0
	while waited < timeout_seconds:
		if condition.call():
			return true
		await get_tree().create_timer(0.2).timeout
		waited += 0.2
	return condition.call()


## Reads the stylebox a button uses for a given state, or null when it inherits.
func _stylebox_of(button: Button, state: String) -> StyleBox:
	var box: StyleBox = button.get_theme_stylebox(state)
	return box


## Deletes the entries this test created. It matches on the test name only, so
## real scores uploaded while the test runs are never touched.
func _remove_test_entries() -> bool:
	var parsed: Variant = JSON.parse_string(await _fetch_text(BASE + ".json"))
	if not (parsed is Dictionary):
		return true
	var removed := 0
	for key in (parsed as Dictionary).keys():
		var item: Variant = (parsed as Dictionary)[key]
		if not (item is Dictionary):
			continue
		if str((item as Dictionary).get("name", "")) != TEST_NAME:
			continue
		var code := await _delete("%s/%s.json" % [BASE, key])
		if code >= 200 and code < 300:
			removed += 1
	print("  (entradas de prueba borradas: %d)" % removed)
	return removed > 0


func _fetch_text(url: String) -> String:
	_http.request(url)
	var response: Array = await _http.request_completed
	return (response[3] as PackedByteArray).get_string_from_utf8()


func _delete(url: String) -> int:
	_http.request(url, PackedStringArray(), HTTPClient.METHOD_DELETE)
	var response: Array = await _http.request_completed
	return int(response[1])


func _check(condition: bool, description: String) -> void:
	if condition:
		print("  OK    ", description)
	else:
		_failures += 1
		print("  FALLA ", description)


func _finish() -> void:
	print("SMOKE RESULT: ", "TODO OK" if _failures == 0 else "%d FALLAS" % _failures)
	get_tree().quit(0 if _failures == 0 else 1)
