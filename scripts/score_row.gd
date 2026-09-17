extends PanelContainer
## One row of the best-five table. Built from code because the contents depend
## on the stored data.

var place := 1
var medal := ""
var player := ""
var points := 0
var date_text := ""
var highlight := false


func _ready() -> void:
	if highlight:
		var box := StyleBoxFlat.new()
		box.bg_color = Color(1.0, 0.85, 0.35, 0.22)
		box.set_corner_radius_all(8)
		box.content_margin_left = 10.0
		box.content_margin_right = 10.0
		add_theme_stylebox_override("panel", box)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	add_child(row)

	var place_label := _make_label("%d." % place, 18, Color(0.70, 0.80, 0.88))
	place_label.custom_minimum_size = Vector2(28, 0)
	row.add_child(place_label)

	var medal_label := _make_label(medal, 19, Color(1.0, 0.88, 0.45))
	medal_label.custom_minimum_size = Vector2(26, 0)
	medal_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	row.add_child(medal_label)

	var name_label := _make_label(player, 19, Color(1, 1, 1))
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_label.clip_text = true
	row.add_child(name_label)

	var points_label := _make_label("%d pts" % points, 19, Color(1, 0.92, 0.5))
	points_label.custom_minimum_size = Vector2(86, 0)
	points_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(points_label)

	var date_label := _make_label(date_text, 12, Color(0.68, 0.76, 0.84))
	date_label.custom_minimum_size = Vector2(84, 0)
	date_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	date_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(date_label)


func _make_label(text_value: String, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text_value
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return label
