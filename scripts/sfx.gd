extends Node
## Autoload: plays the short sound effects. Several players are kept in a pool
## so overlapping swats do not cut each other off.

const POOL_SIZE := 6

var _players: Array[AudioStreamPlayer] = []
var _next := 0


func _ready() -> void:
	# The bus survives a missing audio device, so never bail out here.
	for index in POOL_SIZE:
		var player := AudioStreamPlayer.new()
		player.stream = load("res://assets/audio/squish.wav")
		player.process_mode = Node.PROCESS_MODE_ALWAYS
		add_child(player)
		_players.append(player)


## Plays the swat sound with a little variation so repeats are less robotic.
func play_squish() -> void:
	if _players.is_empty():
		return
	var player := _players[_next]
	_next = (_next + 1) % _players.size()
	player.pitch_scale = randf_range(0.9, 1.15)
	player.play()
