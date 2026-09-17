extends PanelContainer
## Reusable best-five table: one row per entry with its position, name, points
## and date. `highlight` is the 1-based place the last run reached, so the menu
## and the game-over screen share this one node.

const ROW_SCRIPT := preload("res://scripts/score_row.gd")
const MEDALS := ["1", "2", "3", "4", "5"]


func refresh(highlight: int = 0) -> void:
	for child in $Body/Rows.get_children():
		child.queue_free()
	var entries: Array = GameData.best_scores
	if entries.is_empty():
		var empty := Label.new()
		empty.text = "Todavía no hay puntajes.\n¡Sé el primero en aplastar zancudos!"
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty.add_theme_font_size_override("font_size", 20)
		empty.add_theme_color_override("font_color", Color(0.78, 0.86, 0.92))
		empty.add_theme_constant_override("line_spacing", 4)
		empty.custom_minimum_size = Vector2(0, 52)
		$Body/Rows.add_child(empty)
		return
	for index in entries.size():
		var row := PanelContainer.new()
		row.set_script(ROW_SCRIPT)
		row.custom_minimum_size = Vector2(0, 34)
		row.set("place", index + 1)
		row.set("medal", MEDALS[index])
		row.set("player", str(entries[index].get("name", "???")))
		row.set("points", int(entries[index].get("points", 0)))
		row.set("date_text", _short_date(str(entries[index].get("at", ""))))
		row.set("highlight", highlight == index + 1)
		$Body/Rows.add_child(row)


## Trims "2026-09-17 14:01:53" down to "17/09 14:01" so the row stays narrow.
func _short_date(raw: String) -> String:
	if raw.length() < 16:
		return raw
	var parts := raw.split(" ")
	if parts.size() != 2:
		return raw
	var date_parts := parts[0].split("-")
	if date_parts.size() != 3:
		return raw
	var time := parts[1].substr(0, 5)
	return "%s/%s %s" % [date_parts[2], date_parts[1], time]
