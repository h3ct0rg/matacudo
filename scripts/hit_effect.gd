extends Node2D
## The swat mark plus the floating "+N" label spawned where a mosquito died.

@onready var _splat: Sprite2D = $Splat
@onready var _label: Label = $Points


func show_hit(at: Vector2, points: int) -> void:
	position = at
	_label.text = "+%d" % points

	# Spread and rotate every splat so repeats never look stamped.
	_splat.rotation = randf() * TAU
	var target_scale := randf_range(0.62, 0.86)
	_splat.scale = Vector2.ONE * target_scale * 0.35
	_splat.modulate = Color(1.0, 1.0, 1.0, 0.92)

	var splat_tween := create_tween()
	splat_tween.set_parallel(true)
	splat_tween.tween_property(_splat, "scale", Vector2.ONE * target_scale, 0.14) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	splat_tween.tween_property(_splat, "modulate:a", 0.0, 0.95).set_delay(0.2)

	var label_tween := create_tween()
	label_tween.set_parallel(true)
	label_tween.tween_property(_label, "position:y", _label.position.y - 42.0, 0.7) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	label_tween.tween_property(_label, "modulate:a", 0.0, 0.7).set_delay(0.15)

	splat_tween.chain().tween_callback(queue_free)
