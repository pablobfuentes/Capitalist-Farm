extends Window

signal confirmed
signal cancelled

const _SupplyPolicy := preload("res://core/systems/supply_policy_system.gd")

var _shortages: Array = []


func _ready() -> void:
	visible = false
	close_requested.connect(_on_cancel)
	%CancelButton.pressed.connect(_on_cancel)
	%ConfirmButton.pressed.connect(_on_confirm)


func open_with_shortages(shortages: Array) -> void:
	if shortages.is_empty():
		hide()
		return
	_shortages = shortages
	_refresh()
	_fit_to_viewport()
	popup_centered()


func _fit_to_viewport() -> void:
	var vp_size: Vector2 = get_viewport().get_visible_rect().size
	max_size = Vector2i(int(vp_size.x - 32), int(vp_size.y - 32))
	var target_w := clampi(int(vp_size.x * 0.68), min_size.x, max_size.x)
	var target_h := clampi(int(vp_size.y * 0.72), min_size.y, max_size.y)
	size = Vector2i(target_w, target_h)


func _refresh() -> void:
	for child in %ShortagesList.get_children():
		child.queue_free()

	for shortage_variant in _shortages:
		if typeof(shortage_variant) != TYPE_DICTIONARY:
			continue
		var shortage: Dictionary = shortage_variant
		_add_shortage_block(shortage)


func _add_shortage_block(shortage: Dictionary) -> void:
	var block := VBoxContainer.new()
	block.add_theme_constant_override("separation", 6)

	var header := Label.new()
	header.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var cap: int = int(shortage.get("capacity", 0))
	var base_cap: Variant = shortage.get("baseCapacity")
	var cap_text := str(cap)
	if base_cap != null and int(base_cap) != cap:
		cap_text = "%d eff. (%s base)" % [cap, str(base_cap)]
	header.text = "%s — %s%% utilized (%s demand vs %s capacity)" % [
		str(shortage.get("name", "Supplier")),
		str(shortage.get("utilizationPct", 0)),
		str(shortage.get("demand", 0)),
		cap_text,
	]
	block.add_child(header)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)

	var template_id := str(shortage.get("templateId", ""))
	var current_policy := _SupplyPolicy.get_policy(Game.state, template_id)
	for pol_variant in _SupplyPolicy.all_policies():
		if typeof(pol_variant) != TYPE_DICTIONARY:
			continue
		var pol: Dictionary = pol_variant
		var policy_id := str(pol.get("id", ""))
		var btn := Button.new()
		btn.set_meta("policy_id", policy_id)
		btn.text = "%s\n%s" % [str(pol.get("label", "")), str(pol.get("summary", ""))]
		if policy_id == current_policy:
			btn.text = "✓ %s" % btn.text
		btn.pressed.connect(_on_policy_selected.bind(template_id, policy_id, grid))
		grid.add_child(btn)

	block.add_child(grid)
	%ShortagesList.add_child(block)


func _on_policy_selected(template_id: String, policy_id: String, _grid: GridContainer) -> void:
	Game.apply_command(GameCommand.set_supply_policy(template_id, policy_id))
	_refresh()


func _on_confirm() -> void:
	var ack: Dictionary = Game.apply_command(GameCommand.confirm_supply_shortage())
	if not bool(ack.get("ok", false)):
		return
	hide()
	confirmed.emit()


func _on_cancel() -> void:
	hide()
	cancelled.emit()
