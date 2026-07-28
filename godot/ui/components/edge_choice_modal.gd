extends Window

signal edge_chosen(edge_id: String)
signal skipped


func _ready() -> void:
	visible = false
	title = "New Strategic Edge"
	size = Vector2i(520, 420)
	unresizable = true
	close_requested.connect(_on_close_requested)


func open_with_choices(choices: Array) -> void:
	if choices.is_empty():
		hide()
		return
	_rebuild(choices)
	popup_centered()


func close_modal() -> void:
	hide()


func _rebuild(choices: Array) -> void:
	for child in get_children():
		child.queue_free()

	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 8)

	var sub := Label.new()
	sub.text = "Choose one edge to add to your build:"
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(sub)

	for choice_variant in choices:
		if typeof(choice_variant) != TYPE_DICTIONARY:
			continue
		var edge: Dictionary = choice_variant
		var btn := Button.new()
		btn.text = "%s — %s" % [str(edge.get("name", "")), str(edge.get("effect", ""))]
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		var edge_id: String = str(edge.get("id", ""))
		btn.pressed.connect(func() -> void: _on_edge_pressed(edge_id))
		root.add_child(btn)

	var skip_btn := Button.new()
	skip_btn.text = "Skip"
	skip_btn.pressed.connect(_on_skip_pressed)
	root.add_child(skip_btn)

	add_child(root)


func _on_edge_pressed(edge_id: String) -> void:
	close_modal()
	edge_chosen.emit(edge_id)


func _on_skip_pressed() -> void:
	close_modal()
	skipped.emit()


func _on_close_requested() -> void:
	close_modal()
	skipped.emit()
