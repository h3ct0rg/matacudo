extends CanvasLayer
## Heads-up display: score on the left, how full the window is on the right.
## Owned by the game scene, which calls the update methods.

const WARNING_RATIO := 0.55
const DANGER_RATIO := 0.8

@onready var _score_value: Label = $Root/Bar/Score/Row/Value
@onready var _combo: Label = $Root/Bar/Score/Combo
@onready var _fill_value: Label = $Root/Bar/Fill/Row/Value
@onready var _meter: ProgressBar = $Root/Bar/Fill/Meter


func _ready() -> void:
	set_score(0)
	set_fill(0.0)
	set_combo(0, 1)


func set_score(value: int) -> void:
	_score_value.text = str(value)


## `ratio` is the share of the window covered by mosquitoes, 0..1.
func set_fill(ratio: float) -> void:
	var percent := clampf(ratio, 0.0, 1.0)
	_meter.value = percent * 100.0
	_fill_value.text = "%d%%" % roundi(percent * 100.0)
	if percent >= DANGER_RATIO:
		_fill_value.add_theme_color_override("font_color", Color(1, 0.42, 0.34))
	elif percent >= WARNING_RATIO:
		_fill_value.add_theme_color_override("font_color", Color(1, 0.82, 0.4))
	else:
		_fill_value.add_theme_color_override("font_color", Color(0.7, 1, 0.72))


func set_combo(hits: int, multiplier: int) -> void:
	if hits < 2:
		_combo.text = ""
		_combo.modulate.a = 0.0
		return
	_combo.text = "¡x%d!  %d seguidos" % [multiplier, hits]
	_combo.modulate.a = 1.0
