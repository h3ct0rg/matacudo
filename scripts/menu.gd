extends Control
## Main menu: game title, start button and the best five scores.

@onready var _leaderboard: PanelContainer = $Center/Column/Leaderboard


func _ready() -> void:
	get_tree().paused = false
	_leaderboard.refresh()
	# Pull the cloud table in the background; the panel re-renders when it lands.
	GameData.refresh_scores(_leaderboard.refresh)
	$Center/Column/StartButton.pressed.connect(_on_start_pressed)
	$Version.text = "v%s · toca o haz clic en los zancudos" % ProjectSettings.get_setting("application/config/version", "1.0")


func _on_start_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/game.tscn")
