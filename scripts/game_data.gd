extends Node
## Autoload: the current run plus the cloud leaderboard table.
##
## Scores live in a Firebase Realtime Database. The board has no `.indexOn`
## rule for `points`, so an ordered server-side query is rejected: the table is
## fetched whole and sorted here instead, with only the best MAX_ENTRIES kept.
## The in-memory table always exists, so the UI renders even with no network.

const MAX_ENTRIES := 5
const BASE_URL := "https://chauzancudo-default-rtdb.firebaseio.com"
const SCORES_PATH := "scores"
const SETTINGS_PATH := "user://settings.cfg"

## Points the current run has earned.
var score: int = 0
## Best entries, highest first: [{name, points, at}].
var best_scores: Array[Dictionary] = []
## Player name, remembered between runs.
var player_name: String = ""
## False while a cloud request is in flight.
var online: bool = true
## Last transport error, surfaced in the UI when it happens.
var last_error: String = ""


func _ready() -> void:
	load_settings()
	refresh_scores()


func start_run() -> void:
	score = 0


func remember_name(value: String) -> void:
	player_name = value.strip_edges()
	save_settings()


## Uploads one score, then reloads the table.
## `on_done` receives (ok: bool, message: String).
func submit_score(points: int, on_done: Callable) -> void:
	var payload := JSON.stringify({
		"name": player_name,
		"points": points,
		"at": Time.get_datetime_string_from_system(false, true),
	})
	var http := HTTPRequest.new()
	# Scoring happens while the tree is paused, so the request node must keep
	# processing regardless of pause state or the upload never completes.
	http.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(http)
	http.request_completed.connect(func(_result, code, _headers, _body):
		http.queue_free()
		if code < 200 or code >= 300:
			last_error = "No se pudo guardar (HTTP %d)" % code
			on_done.call(false, last_error)
			return
		last_error = ""
		refresh_scores(func(): on_done.call(true, ""))
	)
	var error := http.request(
		"%s/%s.json" % [BASE_URL, SCORES_PATH],
		PackedStringArray(["Content-Type: application/json"]),
		HTTPClient.METHOD_POST,
		payload,
	)
	if error != OK:
		http.queue_free()
		last_error = "Sin conexión (error %d)" % error
		on_done.call(false, last_error)


## Loads the table into `best_scores`. `on_done` is optional.
func refresh_scores(on_done: Callable = Callable()) -> void:
	var http := HTTPRequest.new()
	# The game-over screen refreshes the table while paused, so this node must
	# ignore the pause state too.
	http.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(http)
	http.request_completed.connect(func(_result, code, _headers, body):
		http.queue_free()
		if code < 200 or code >= 300:
			online = false
			last_error = "No se pudo leer la tabla (HTTP %d)" % code
			_finish_refresh(on_done)
			return
		online = true
		last_error = ""
		_apply_body(body)
		_finish_refresh(on_done)
	)
	var error := http.request("%s/%s.json" % [BASE_URL, SCORES_PATH])
	if error != OK:
		http.queue_free()
		online = false
		last_error = "Sin conexión (error %d)" % error
		_finish_refresh(on_done)


func _finish_refresh(on_done: Callable) -> void:
	if on_done.is_valid():
		on_done.call()


func _apply_body(body: PackedByteArray) -> void:
	var parsed = JSON.parse_string(body.get_string_from_utf8())
	var entries: Array[Dictionary] = []
	if parsed is Dictionary:
		for key in parsed.keys():
			var item = parsed[key]
			if item is Dictionary:
				entries.append({
					"name": str(item.get("name", "???")),
					"points": int(item.get("points", 0)),
					"at": str(item.get("at", "")),
				})
	# Only the best MAX_ENTRIES survive, highest first.
	entries.sort_custom(func(a, b): return int(a["points"]) > int(b["points"]))
	best_scores = entries.slice(0, MAX_ENTRIES)


## Where the current run sits in `best_scores`, 1-based, or 0 when it is not in
## the table. Used to highlight the row the player just added.
func rank_of_run(points: int, name: String) -> int:
	for index in best_scores.size():
		var entry: Dictionary = best_scores[index]
		if str(entry.get("name", "")) == name and int(entry.get("points", 0)) == points:
			return index + 1
	return 0


func load_settings() -> void:
	var config := ConfigFile.new()
	if config.load(SETTINGS_PATH) == OK:
		player_name = str(config.get_value("player", "name", ""))


func save_settings() -> void:
	var config := ConfigFile.new()
	config.set_value("player", "name", player_name)
	config.save(SETTINGS_PATH)
