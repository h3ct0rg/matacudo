extends Node2D
## Main scene: mosquitoes fly over the window and stay there until swatted.
## The run ends when the window is more than 70% covered.
##
## Swat detection lives on each mosquito (Area2D input), so this script owns the
## population, the coverage percentage and the end-of-run flow.

const MOSQUITO_SCENE := preload("res://scenes/mosquito.tscn")
const HIT_EFFECT_SCENE := preload("res://scenes/hit_effect.tscn")
const PRESS_INDICATOR_SCENE := preload("res://scenes/press_indicator.tscn")

## Radius of the swat area, in game units. It must match the CircleShape2D in
## scenes/mosquito.tscn: that shape is what catches the press, and this value is
## what the on-screen indicator draws so the player can see the real area.
const SWAT_RADIUS := 40.0

## Spawn area: inset so mosquitoes never sit under the window frame.
const SPAWN_BOUNDS := Rect2(70, 70, 1140, 580)
## Combo window: consecutive swats inside this many seconds multiply points.
const COMBO_WINDOW := 0.8
## Difficulty ramp: spawn interval goes from START to MIN over RAMP_SECONDS.
const SPAWN_START := 1.05
const SPAWN_MIN := 0.34
const RAMP_SECONDS := 60.0
## Training wheels: the very first seconds spawn slower.
const GRACE_SECONDS := 3.0
## The run is lost once the window is covered beyond this share.
const LOSS_RATIO := 0.7
## Screen share taken up by one mosquito, as a fraction of the playfield.
const SHARE_NORMAL := 0.021
const SHARE_BIG := 0.032

@onready var _mosquitoes: Node2D = $Mosquitoes
@onready var _effects: Node2D = $Effects
@onready var _hud: CanvasLayer = $HUD
@onready var _spawn_timer: Timer = $SpawnTimer
@onready var _game_over: Control = $GameOver
@onready var _final_score: Label = $GameOver/Center/Panel/Content/FinalScore
@onready var _name_input: LineEdit = $GameOver/Center/Panel/Content/NameEntry/Row/Field
@onready var _name_error: Label = $GameOver/Center/Panel/Content/NameEntry/Error
@onready var _leaderboard: PanelContainer = $GameOver/Center/Panel/Content/Leaderboard
@onready var _stats: Label = $GameOver/Center/Panel/Content/Stats

var _elapsed := 0.0
var _combo_hits := 0
var _combo_time_left := 0.0
var _fill := 0.0
var _fill_clock := 0.0
var _finished := false
var _uploading := false
## Positions where the press circle was shown, kept for the development tests.
var _press_marks: Array[Vector2] = []


func _ready() -> void:
	randomize()
	get_tree().paused = false
	GameData.start_run()
	# Each run counts as one more player who played.
	Analytics.count_run()
	Analytics.stats_changed.connect(_on_stats_changed)
	_on_stats_changed(Analytics.online, Analytics.players)
	_hud.set_score(0)
	_hud.set_fill(0.0)
	_hud.set_combo(0, 1)

	_game_over.hide()
	_fit_overlay()
	$GameOver/Center/Panel/Content/NameEntry/Row/Save.pressed.connect(_on_save_pressed)
	$GameOver/Center/Panel/Content/Buttons2/Play.pressed.connect(_on_play_again_pressed)
	$GameOver/Center/Panel/Content/Buttons2/Menu.pressed.connect(_on_menu_pressed)
	_name_input.text = GameData.player_name
	_name_input.text_submitted.connect(func(_value): _on_save_pressed())
	_leaderboard.refresh()

	# The scene file already wires SpawnTimer.timeout, so only the interval is
	# set here: connecting again would raise a duplicate-connection error.
	_spawn_timer.wait_time = SPAWN_START
	_spawn_timer.start()


func _physics_process(delta: float) -> void:
	if _finished:
		return
	_elapsed += delta
	if _combo_time_left > 0.0:
		_combo_time_left -= delta
		if _combo_time_left <= 0.0:
			_combo_hits = 0
			_hud.set_combo(0, 1)

	# Coverage is recomputed on a short cadence rather than per swat, so a
	# population that stops changing (or is cleared) still reports the truth.
	_fill_clock += delta
	if _fill_clock >= 0.15:
		_fill_clock = 0.0
		_update_fill()


func _on_spawn_timer_timeout() -> void:
	if _finished:
		return
	var progress := clampf(_elapsed / RAMP_SECONDS, 0.0, 1.0)
	# Two big ones for every ten mosquitoes: faster, larger, worth more points.
	var big := randf() < 0.2
	var mosquito: Node2D = MOSQUITO_SCENE.instantiate()
	mosquito.position = _spawn_position()
	_mosquitoes.add_child(mosquito)
	mosquito.setup({
		"bounds": SPAWN_BOUNDS,
		"is_big": big,
		"screen_share": SHARE_BIG if big else SHARE_NORMAL,
		"speed": randf_range(190.0, 260.0) + progress * 170.0 + (55.0 if big else 0.0),
	})
	mosquito.swatted.connect(_on_mosquito_swatted)

	if _elapsed < GRACE_SECONDS:
		_spawn_timer.wait_time = 2.0
	else:
		_spawn_timer.wait_time = maxf(SPAWN_MIN, lerpf(SPAWN_START, SPAWN_MIN, progress))


## A quarter of the mosquitoes enter from near an edge; the rest pop up
## anywhere, which keeps the pressure spread over the whole window.
func _spawn_position() -> Vector2:
	var margin := 110.0
	if randf() < 0.25:
		match randi() % 4:
			0:
				return Vector2(randf_range(SPAWN_BOUNDS.position.x, SPAWN_BOUNDS.end.x),
					SPAWN_BOUNDS.position.y + margin * 0.4)
			1:
				return Vector2(randf_range(SPAWN_BOUNDS.position.x, SPAWN_BOUNDS.end.x),
					SPAWN_BOUNDS.end.y - margin * 0.4)
			2:
				return Vector2(SPAWN_BOUNDS.position.x + margin * 0.4,
					randf_range(SPAWN_BOUNDS.position.y, SPAWN_BOUNDS.end.y))
			_:
				return Vector2(SPAWN_BOUNDS.end.x - margin * 0.4,
					randf_range(SPAWN_BOUNDS.position.y, SPAWN_BOUNDS.end.y))
	return Vector2(
		randf_range(SPAWN_BOUNDS.position.x + margin, SPAWN_BOUNDS.end.x - margin),
		randf_range(SPAWN_BOUNDS.position.y + margin, SPAWN_BOUNDS.end.y - margin),
	)


## Shows the swat-area circle wherever the player presses, hit or miss, so the
## real size of the target is visible instead of guessed.
##
## The project emulates touch from the mouse, which means a desktop click arrives
## here twice, once as a mouse button and once as a screen touch. Only the touch
## event is used when touch is available, which keeps it to one circle per press
## on both desktop and mobile.
func _unhandled_input(event: InputEvent) -> void:
	var pressed := false
	if event is InputEventScreenTouch:
		pressed = event.pressed
	elif event is InputEventMouseButton and not _touch_available():
		pressed = event.pressed and event.button_index == MOUSE_BUTTON_LEFT
	if not pressed:
		return
	var at: Vector2 = (event as InputEvent).position
	_show_press_indicator(at)


## True when the platform reports a touchscreen, so mouse events are only the
## emulated twin of a touch and should not be drawn twice.
func _touch_available() -> bool:
	return DisplayServer.is_touchscreen_available()


## Draws the circle under the game layer, then records it for tests.
func _show_press_indicator(at: Vector2) -> void:
	var indicator: Node2D = PRESS_INDICATOR_SCENE.instantiate()
	_effects.add_child(indicator)
	indicator.call("show_press", at, SWAT_RADIUS)
	_press_marks.append(at)


func _on_mosquito_swatted(points: int, at: Vector2) -> void:
	if _finished:
		return
	_combo_hits += 1
	_combo_time_left = COMBO_WINDOW
	var gained := points * _combo_multiplier()
	GameData.score += gained

	var effect := HIT_EFFECT_SCENE.instantiate()
	_effects.add_child(effect)
	effect.show_hit(at, gained)

	_hud.set_score(GameData.score)
	_hud.set_combo(_combo_hits, _combo_multiplier())
	_update_fill()


func _combo_multiplier() -> int:
	return 2 if _combo_hits >= 3 else 1


## Recomputes how much of the window the living mosquitoes take up.
func _update_fill() -> void:
	var total := 0.0
	for child in _mosquitoes.get_children():
		if is_instance_valid(child):
			total += float(child.get("screen_share"))
	_fill = total
	_hud.set_fill(_fill)
	if _fill > LOSS_RATIO:
		_finish()


## The end-of-run overlay hangs off this Node2D, so nothing resolves a full-rect
## layout for it. Sizing it explicitly keeps it filling the window, which is
## what keeps the panel centred instead of stuck in a corner. Sizes are applied
## deferred because a Control overrides a direct `size` write after `_ready()`.
##
## The same pass forces PROCESS_MODE_ALWAYS on the overlay subtree: the game is
## paused when this panel is up, and a control that does not process while
## paused never receives the click.
func _fit_overlay() -> void:
	var screen := get_viewport().get_visible_rect().size
	_set_mode_always(_game_over)
	for node in [_game_over, $GameOver/Center, $GameOver/Dimmer]:
		var control: Control = node
		control.set_deferred("position", Vector2.ZERO)
		control.set_deferred("size", screen)


func _set_mode_always(node: Node) -> void:
	node.process_mode = Node.PROCESS_MODE_ALWAYS
	for child in node.get_children():
		_set_mode_always(child)


func _finish() -> void:
	_finished = true
	_spawn_timer.stop()
	_final_score.text = "PUNTAJE: %d" % GameData.score
	_leaderboard.refresh()
	GameData.refresh_scores(_leaderboard.refresh)
	_fit_overlay()
	_game_over.show()
	get_tree().paused = true
	# Put the cursor straight in the name box so a keyboard player can type.
	_name_input.grab_focus()


## Phase one: store the score under the typed name.
func _on_save_pressed() -> void:
	var typed := _name_input.text.strip_edges()
	if typed.length() < 2:
		_name_error.text = "Escribe tu nombre (mínimo 2 letras)."
		_name_error.show()
		return
	if typed.length() > 16:
		typed = typed.substr(0, 16)
	_name_input.text = typed
	_name_error.hide()
	GameData.remember_name(typed)
	_name_input.editable = false
	var save_button: Button = $GameOver/Center/Panel/Content/NameEntry/Row/Save
	save_button.disabled = true
	var status: Label = $GameOver/Center/Panel/Content/NameEntry/Status
	status.text = "Guardando..."
	status.show()

	_uploading = true
	GameData.submit_score(GameData.score, _on_score_saved)


## Phase two: once the score is safely stored, the whole save section goes away
## and only the leaderboard remains. A failed upload keeps the form on screen so
## the player can try again.
func _on_score_saved(ok: bool = false, message: String = "") -> void:
	if not ok and _uploading:
		# The leaderboard's refresh callback reuses this method as a no-argument
		# signal handler; ignore it while the upload itself is still pending.
		return
	_uploading = false
	var entry: Control = $GameOver/Center/Panel/Content/NameEntry
	if ok:
		entry.hide()
		_leaderboard.refresh.call_deferred(
			GameData.rank_of_run(GameData.score, GameData.player_name))
		return
	entry.show()
	var status: Label = $GameOver/Center/Panel/Content/NameEntry/Status
	status.text = "%s — toca GUARDAR para reintentar." % message
	status.show()
	_name_input.editable = true
	$GameOver/Center/Panel/Content/NameEntry/Row/Save.disabled = false


func _on_play_again_pressed() -> void:
	get_tree().paused = false
	get_tree().reload_current_scene()


func _on_menu_pressed() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/menu.tscn")


## Keeps the counter line on the game-over panel in step with the cloud.
func _on_stats_changed(online: int, players: int) -> void:
	if online == 0 and players == 0:
		_stats.text = ""
		return
	var people := "jugador" if players == 1 else "jugadores"
	# Plain text only: bullets and emoji have no glyph in the default font and
	# would show as a placeholder box.
	_stats.text = "%d en línea ahora  ·  %d %s en total" % [online, players, people]
