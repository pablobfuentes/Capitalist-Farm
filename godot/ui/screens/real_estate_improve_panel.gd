extends Window

signal closed

const _RealEstate := preload("res://core/systems/real_estate_system.gd")

var _asset_id: String = ""


func _ready() -> void:
	visible = false
	close_requested.connect(_on_close)
	%CloseButton.pressed.connect(_on_close)


func open_for_asset(asset_id: String) -> void:
	_asset_id = asset_id
	_refresh()
	popup_centered_ratio(0.55)


func _on_close() -> void:
	hide()
	closed.emit()


func _refresh() -> void:
	var state: RunState = Game.state
	if state == null:
		return
	var asset: Dictionary = _RealEstate.find_asset(state, _asset_id)
	if asset.is_empty():
		return

	var template_id: String = str(asset.get("templateId", asset.get("template_id", "")))
	var tmpl := Content.get_template(template_id)
	%PropertyName.text = str(asset.get("name", "Property"))
	%MetaLabel.text = "%s · Val %s · Rent %s/qtr · Serves %d downstream link(s)" % [
		tmpl.layer_label if tmpl else "Infrastructure",
		MathUtil.fmt_money(int(asset.get("valuation", asset.get("markedValue", 0)))),
		MathUtil.fmt_money(int(asset.get("rentPerTurn", asset.get("rent_per_turn", 0)))),
		_RealEstate.downstream_link_count(state, template_id),
	]

	for child in %ImprovementsList.get_children():
		child.queue_free()

	var improvements: Array = _RealEstate.improvements_for_asset(state, asset)
	if improvements.is_empty():
		var empty := Label.new()
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		empty.text = "All available improvements have been applied."
		%ImprovementsList.add_child(empty)
		return

	for imp_variant in improvements:
		if typeof(imp_variant) != TYPE_DICTIONARY:
			continue
		var imp: Dictionary = imp_variant
		_add_improvement_row(state, asset, imp)


func _add_improvement_row(state: RunState, asset: Dictionary, imp: Dictionary) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)

	var info := Label.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var cost: int = _RealEstate.improve_cost(asset, imp)
	info.text = "%s — %s" % [
		str(imp.get("name", "")),
		str(imp.get("note", "")),
	]
	row.add_child(info)

	var apply_btn := Button.new()
	apply_btn.text = "1AP + %s" % MathUtil.fmt_money(cost)
	var imp_id: String = str(imp.get("id", ""))
	apply_btn.disabled = state.action_points < 1 or state.cash < cost
	apply_btn.pressed.connect(_on_apply_pressed.bind(imp_id))
	row.add_child(apply_btn)
	%ImprovementsList.add_child(row)


func _on_apply_pressed(improvement_id: String) -> void:
	var result: Dictionary = Game.apply_command(GameCommand.improve_real_estate(_asset_id, improvement_id))
	if bool(result.get("ok", false)):
		_refresh()
	else:
		%MetaLabel.text = "Failed: %s" % str(result.get("error", "unknown"))
