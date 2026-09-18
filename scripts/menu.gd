extends Control
## Main menu: game title, start button, the best five scores, and the player
## counters (how many are online right now and how many have played in total).

@onready var _leaderboard: PanelContainer = $Center/Column/Leaderboard
@onready var _stats: Label = $Center/Column/Stats


func _ready() -> void:
	get_tree().paused = false
	_leaderboard.refresh()
	# Pull the cloud table in the background; the panel re-renders when it lands.
	GameData.refresh_scores(_leaderboard.refresh)
	$Center/Column/StartButton.pressed.connect(_on_start_pressed)
	$Version.text = "v%s · toca o haz clic en los zancudos" % ProjectSettings.get_setting("application/config/version", "1.0")

	# The counters arrive asynchronously from Firebase and keep moving while the
	# menu is open, so the label is updated by signal and by a slow poll.
	Analytics.stats_changed.connect(_on_stats_changed)
	_on_stats_changed(Analytics.online, Analytics.players)
	var poll := Timer.new()
	poll.wait_time = 15.0
	poll.autostart = true
	add_child(poll)
	poll.timeout.connect(Analytics.refresh)


func _on_stats_changed(online: int, players: int) -> void:
	if online == 0 and players == 0:
		_stats.text = "Conectando con el marcador en línea..."
		return
	var people := "jugador" if players == 1 else "jugadores"
	# Plain text only: the default font has no glyph for bullet or emoji symbols
	# beyond the middle dot, and would draw a placeholder box instead.
	_stats.text = "%d en línea ahora   ·   %d %s en total" % [online, players, people]


func _on_start_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/game.tscn")
