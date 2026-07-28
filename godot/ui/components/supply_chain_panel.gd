extends VBoxContainer


func refresh(state: RunState) -> void:
	for child in get_children():
		child.queue_free()

	var view: Dictionary = RunView.supply_chain_view(state)
	var banner: String = str(view.get("shortageBanner", ""))
	if not banner.is_empty():
		var banner_label := Label.new()
		banner_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		banner_label.add_theme_color_override("font_color", Color(0.85, 0.55, 0.45))
		banner_label.text = banner
		add_child(banner_label)

	var rows: Array = view.get("rows", [])
	var empty_message: String = str(view.get("emptyMessage", ""))
	if rows.is_empty() and not empty_message.is_empty():
		var empty := Label.new()
		empty.text = empty_message
		add_child(empty)
		return

	for row_text_variant in rows:
		var row := Label.new()
		row.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		row.text = str(row_text_variant)
		add_child(row)
