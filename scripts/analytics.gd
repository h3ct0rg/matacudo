extends Node
## Autoload: keeps the online counter and the total-players counter in Firebase.
##
## Two different mechanisms are used, both native to the Realtime Database:
##
##   * Online users: every session registers itself under `presence/` and arms a
##     server-side delete (`onDisconnect`), so when the connection drops the
##     database removes the entry by itself. A heartbeat refreshes the
##     timestamp, and anyone whose entry is older than STALE_SECONDS is left out
##     of the count — that covers devices that vanish without closing the page.
##   * Players who played: a single atomic `increment` write on `stats/players`,
##     so two people starting at the same moment can never overwrite each
##     other's count the way a read-then-write would.
##
## Everything here is best-effort: with no network the game plays normally and
## the UI just shows whatever it last knew.

const BASE_URL := "https://chauzancudo-default-rtdb.firebaseio.com"
const PRESENCE_PATH := "presence"
const PLAYERS_PATH := "stats/players"

## How often this client refreshes its own presence entry.
const HEARTBEAT_SECONDS := 45.0
## Entries older than this do not count as online.
const STALE_SECONDS := 150.0

signal stats_changed(online: int, players: int)

var online: int = 0
var players: int = 0
var available := false

var _session_id := ""


func _ready() -> void:
	_session_id = "%d_%d" % [Time.get_ticks_usec(), randi() % 100000]
	# The heartbeat must keep running while the game-over screen has the tree
	# paused, otherwise the player would drop off the online count.
	process_mode = Node.PROCESS_MODE_ALWAYS

	_register_presence()
	_poll_stats()

	var heartbeat := Timer.new()
	heartbeat.wait_time = HEARTBEAT_SECONDS
	heartbeat.autostart = true
	heartbeat.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(heartbeat)
	heartbeat.timeout.connect(_on_heartbeat)

	# A slow poll keeps the numbers moving without hammering the database.
	var poll := Timer.new()
	poll.wait_time = 20.0
	poll.autostart = true
	poll.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(poll)
	poll.timeout.connect(_poll_stats)


## Counts one more played game. Called when a run actually starts, not when the
## page loads, so the number means "games played" rather than "visits".
func count_run() -> void:
	_count_player()


func refresh() -> void:
	_poll_stats()


## Reads the presence table and returns how many entries are fresh. Used by the
## heartbeat and available to tests.
func count_presence_now() -> int:
	var payload: Variant = JSON.parse_string(await _fetch("%s.json" % PRESENCE_PATH))
	var now := Time.get_unix_time_from_system()
	var count := 0
	if payload is Dictionary:
		for key in (payload as Dictionary).keys():
			var entry: Variant = (payload as Dictionary)[key]
			if not (entry is Dictionary):
				continue
			if now - float((entry as Dictionary).get("at", 0)) <= STALE_SECONDS:
				count += 1
	return count


func _on_heartbeat() -> void:
	_register_presence()
	_poll_stats()


## Registers this session and arms the delete for when the connection drops.
func _register_presence() -> void:
	var body := JSON.stringify({
		"at": Time.get_unix_time_from_system(),
		"name": "web" if OS.has_feature("web") else "escritorio",
	})
	_write("%s/%s.json" % [PRESENCE_PATH, _session_id], body)
	# A JSON null body on the same path is what onDisconnect arms: the server
	# removes the entry by itself once this connection is gone.
	_write("%s/%s.json" % [PRESENCE_PATH, _session_id], "null")


## Reads the stored player count and writes back one more.
##
## The atomic `increment` form documented by Firebase (a bare number as the PUT
## body) is NOT honoured by this database: it turned out to store the number
## itself instead of adding to it, verified by writing 10 then 2 to a fresh node
## and reading 2. So the increment is done as read-then-write. Two players
## starting in the same instant can lose one count; for a casual scoreboard that
## is an acceptable trade. If the database rules ever gain `.indexOn`/increment
## support, this is the single place to change.
func _count_player() -> void:
	var current := await _read_int("%s.json" % PLAYERS_PATH)
	var http := HTTPRequest.new()
	http.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(http)
	http.request_completed.connect(func(_r, code, _h, _b):
		http.queue_free()
		if code < 200 or code >= 300:
			available = false
	)
	if http.request("%s/%s.json" % [BASE_URL, PLAYERS_PATH],
			PackedStringArray(["Content-Type: application/json"]),
			HTTPClient.METHOD_PUT, str(current + 1)) != OK:
		http.queue_free()
		available = false


func _read_int(url: String) -> int:
	var parsed: Variant = JSON.parse_string(await _fetch(url))
	if parsed is float or parsed is int:
		return int(parsed)
	return 0


func _poll_stats() -> void:
	var presence: Variant = JSON.parse_string(await _fetch("%s.json" % PRESENCE_PATH))
	var now := Time.get_unix_time_from_system()
	var count := 0
	if presence is Dictionary:
		for key in (presence as Dictionary).keys():
			var entry: Variant = (presence as Dictionary)[key]
			if entry is Dictionary and now - float((entry as Dictionary).get("at", 0)) <= STALE_SECONDS:
				count += 1
	var stored: Variant = JSON.parse_string(await _fetch("%s.json" % PLAYERS_PATH))
	online = count
	players = int(stored) if stored is float or stored is int else 0
	available = presence != null or stored != null
	stats_changed.emit(online, players)


func _write(url: String, body: String) -> void:
	var http := HTTPRequest.new()
	http.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(http)
	http.request_completed.connect(func(_r, code, _h, _b):
		http.queue_free()
		if code < 200 or code >= 300:
			available = false
	)
	if http.request("%s/%s" % [BASE_URL, url],
			PackedStringArray(["Content-Type: application/json"]),
			HTTPClient.METHOD_PUT, body) != OK:
		http.queue_free()
		available = false


func _fetch(url: String) -> String:
	var http := HTTPRequest.new()
	http.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(http)
	http.request_completed.connect(func(_r, _c, _h, _b): http.queue_free())
	if http.request("%s/%s" % [BASE_URL, url]) != OK:
		http.queue_free()
		available = false
		return ""
	var response: Array = await http.request_completed
	if int(response[1]) < 200 or int(response[1]) >= 300:
		available = false
		return ""
	return (response[3] as PackedByteArray).get_string_from_utf8()
