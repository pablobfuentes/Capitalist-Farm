extends PanelContainer

signal closed
signal sell_business(business_id: String)
signal buy_opportunity(opportunity_id: String)
signal investigate_opportunity(opportunity_id: String)
signal negotiate_opportunity(opportunity_id: String)
signal negotiate_urgency(problem_id: String)
signal chat_community_business(community_business_id: String, parcel_id: String, district_id: String)
signal upgrade_track(business_id: String, track_id: String)
signal level_up(opportunity_id: String)
signal negotiate_level_up(opportunity_id: String)

const _COL_CATEGORY := 66
const _COL_LEVEL := 22
const _COL_STAT := 58
const _COL_CURRENT := 40
const _COL_IMPROVED := 40
const _COL_INFO := 18
const _COL_ACTION := 68
const _IMPROVE_COLS := 7
const _PANEL_CONTENT_WIDTH := 336
const _INFO_BUBBLE_MAX_WIDTH := 140
const _INFO_BUBBLE_MAX_HEIGHT := 120
const _INFO_BUBBLE_PADDING := 6

@onready var _title_label: Label = %TitleLabel
@onready var _role_label: Label = %RoleLabel
@onready var _details_label: Label = %DetailsLabel
@onready var _supply_balance_section: VBoxContainer = %SupplyBalanceSection
@onready var _improvements_section: VBoxContainer = %ImprovementsSection
@onready var _level_up_section: VBoxContainer = %LevelUpSection
@onready var _ownership_label: Label = %StubLabel
@onready var _actions_row: HBoxContainer = %ActionsRow
@onready var _close_button: Button = %CloseButton

var _shown_key := ""
var _current_business_id := ""
var _pending_level_up_opp_id := ""
var _info_bubble: PanelContainer = null
var _info_bubble_hide_timer: Timer = null
var _tooltip_layer: CanvasLayer = null


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_close_button.pressed.connect(_on_close_pressed)
	var details_scroll: ScrollContainer = %DetailsScroll
	if details_scroll != null:
		FeedbackBus.wire_scroll(details_scroll)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.14, 0.12, 0.94)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(4)
	style.border_color = Color(0.42, 0.48, 0.38, 0.85)
	style.set_border_width_all(1)
	add_theme_stylebox_override("panel", style)


func show_parcel(entry: Dictionary, district: Dictionary) -> void:
	var view: Dictionary = RunView.parcel_panel(Game.state, entry, district)
	if view.is_empty():
		hide_panel()
		return
	_apply_view(view)


func show_locked_district(district_name: String, requirement: int, net_worth: int, can_unlock: bool) -> void:
	_apply_view(RunView.locked_district_panel(district_name, requirement, net_worth, can_unlock))


func hide_panel() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_shown_key = ""
	_current_business_id = ""
	_pending_level_up_opp_id = ""
	_clear_actions()
	_clear_improvements()
	_clear_level_up()
	_clear_supply_balance()
	_hide_info_bubble()


func _on_close_pressed() -> void:
	hide_panel()
	closed.emit()


func _apply_view(view: Dictionary) -> void:
	var key := "%s|%s" % [str(view.get("title", "")), str(view.get("roleLine", ""))]
	var should_fade := not visible or key != _shown_key
	_shown_key = key
	_title_label.text = str(view.get("title", "Parcel"))
	_role_label.text = str(view.get("roleLine", ""))
	_details_label.text = str(view.get("details", ""))
	_ownership_label.text = str(view.get("ownershipLine", ""))
	_ownership_label.add_theme_color_override("font_color", view.get("ownershipColor", Color.WHITE))
	_populate_supply_balance(view.get("supplyBalance", {}))
	_populate_actions(view.get("actions", {}))
	visible = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	modulate.a = 1.0
	call_deferred("_sync_details_scroll_width")
	if should_fade:
		FeedbackBus.panel_fade_in(self)


func _sync_details_scroll_width() -> void:
	var scroll: ScrollContainer = %DetailsScroll
	var details_vbox: VBoxContainer = scroll.get_node_or_null("DetailsVBox") if scroll != null else null
	if scroll == null or details_vbox == null:
		return
	var scroll_w := _content_width()
	details_vbox.custom_minimum_size.x = scroll_w
	_details_label.custom_minimum_size.x = scroll_w
	if scroll is Control:
		(scroll as Control).clip_contents = true
	_apply_section_widths()


func _content_width() -> int:
	return _PANEL_CONTENT_WIDTH


func _apply_section_widths() -> void:
	for section in [_supply_balance_section, _improvements_section]:
		if section == null:
			continue
		section.size_flags_horizontal = Control.SIZE_EXPAND_FILL


func _populate_supply_balance(view: Variant) -> void:
	_clear_supply_balance()
	if typeof(view) != TYPE_DICTIONARY or not bool((view as Dictionary).get("visible", false)):
		return

	var data: Dictionary = view
	var capacity: Dictionary = data.get("capacity", {})
	var clients: Array = data.get("clients", [])
	var suppliers: Array = data.get("suppliers", [])
	if capacity.is_empty() and clients.is_empty() and suppliers.is_empty():
		return

	_supply_balance_section.show()

	if not capacity.is_empty():
		_supply_balance_section.add_child(_build_capacity_chart(capacity))

	if not clients.is_empty():
		var client_rows: Array = []
		for row_variant in clients:
			if typeof(row_variant) != TYPE_DICTIONARY:
				continue
			client_rows.append(_build_client_row(row_variant as Dictionary))
		_supply_balance_section.add_child(_make_collapsible_section("District clients", client_rows, true))

	if not suppliers.is_empty():
		var supplier_rows: Array = []
		for row_variant in suppliers:
			if typeof(row_variant) != TYPE_DICTIONARY:
				continue
			supplier_rows.append(_build_supplier_row(row_variant as Dictionary))
		_supply_balance_section.add_child(_make_collapsible_section("District suppliers", supplier_rows, false))


func _build_capacity_chart(capacity: Dictionary) -> VBoxContainer:
	var block := VBoxContainer.new()
	block.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	block.add_theme_constant_override("separation", 4)

	var cap_total: int = int(capacity.get("capacity", 0))
	var cap_header := Label.new()
	cap_header.text = "Capacity · %d units" % cap_total
	cap_header.add_theme_font_size_override("font_size", 12)
	cap_header.add_theme_color_override("font_color", Color(0.82, 0.86, 0.76, 1))
	block.add_child(cap_header)

	block.add_child(_build_capacity_bar(capacity.get("segments", []), cap_total))

	var balance_line := str(capacity.get("balanceLine", "")).strip_edges()
	if not balance_line.is_empty():
		var balance := Label.new()
		balance.text = balance_line
		balance.add_theme_font_size_override("font_size", 10)
		balance.add_theme_color_override(
			"font_color",
			Color(0.92, 0.55, 0.48, 1) if bool(capacity.get("overCapacity", false)) else Color(0.62, 0.66, 0.58, 1)
		)
		balance.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		block.add_child(balance)

	return block


func _make_collapsible_section(title: String, body_nodes: Array, expanded: bool) -> VBoxContainer:
	var section := VBoxContainer.new()
	section.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	section.add_theme_constant_override("separation", 2)

	var open_state: Array = [expanded]
	var header := Button.new()
	header.focus_mode = Control.FOCUS_NONE
	header.alignment = HORIZONTAL_ALIGNMENT_LEFT
	header.flat = true
	header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_theme_font_size_override("font_size", 12)
	header.add_theme_color_override("font_color", Color(0.78, 0.82, 0.72, 1))

	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 4)
	body.visible = expanded
	for node in body_nodes:
		if node is Control:
			body.add_child(node)

	var refresh_header := func() -> void:
		header.text = ("▾ %s" % title) if open_state[0] else ("▸ %s" % title)

	refresh_header.call()
	header.pressed.connect(func() -> void:
		open_state[0] = not open_state[0]
		body.visible = open_state[0]
		refresh_header.call()
		FeedbackBus.click()
	)
	FeedbackBus.wire_button(header)

	section.add_child(header)
	section.add_child(body)
	return section


func _build_capacity_bar(segments: Array, cap_total: int) -> Control:
	var wrap := Control.new()
	wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wrap.custom_minimum_size = Vector2(0, 24)

	var track := ColorRect.new()
	track.color = Color(0.16, 0.18, 0.16, 0.95)
	track.set_anchors_preset(Control.PRESET_FULL_RECT)
	wrap.add_child(track)

	var bar := HBoxContainer.new()
	bar.set_anchors_preset(Control.PRESET_FULL_RECT)
	bar.offset_left = 1
	bar.offset_top = 2
	bar.offset_right = -1
	bar.offset_bottom = -2
	bar.add_theme_constant_override("separation", 1)
	bar.clip_contents = true

	for seg_variant in segments:
		if typeof(seg_variant) != TYPE_DICTIONARY:
			continue
		var seg: Dictionary = seg_variant
		var frac: float = maxf(0.0, float(seg.get("widthFrac", 0.0)))
		if frac <= 0.001:
			continue

		var seg_wrap := Control.new()
		seg_wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		seg_wrap.size_flags_stretch_ratio = frac
		seg_wrap.custom_minimum_size.x = 0
		seg_wrap.clip_contents = true

		var seg_rect := ColorRect.new()
		seg_rect.color = seg.get("color", RunView.SUPPLY_SPARE_COLOR)
		seg_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
		seg_wrap.add_child(seg_rect)

		if frac >= 0.10:
			var units: int = int(seg.get("units", 0))
			var center := CenterContainer.new()
			center.set_anchors_preset(Control.PRESET_FULL_RECT)
			center.mouse_filter = Control.MOUSE_FILTER_IGNORE
			var unit_lbl := Label.new()
			unit_lbl.text = str(units)
			unit_lbl.add_theme_font_size_override("font_size", 10)
			unit_lbl.add_theme_color_override("font_color", Color(0.95, 0.95, 0.90, 0.95))
			unit_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			center.add_child(unit_lbl)
			seg_wrap.add_child(center)

		var style_note := ""
		match str(seg.get("style", "")):
			"external":
				style_note = " (off-district)"
			"spare":
				style_note = " (unallocated)"
		seg_wrap.tooltip_text = "%s · %d units%s" % [
			str(seg.get("label", "")),
			int(seg.get("units", 0)),
			style_note,
		]
		bar.add_child(seg_wrap)

	wrap.add_child(bar)

	if cap_total > 0:
		var cap_lbl := Label.new()
		cap_lbl.text = str(cap_total)
		cap_lbl.add_theme_font_size_override("font_size", 9)
		cap_lbl.add_theme_color_override("font_color", Color(0.55, 0.58, 0.52, 1))
		cap_lbl.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
		cap_lbl.offset_top = -14
		cap_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		wrap.add_child(cap_lbl)

	return wrap


func _build_client_row(row: Dictionary) -> Control:
	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.add_theme_constant_override("separation", 0)

	var name_row := HBoxContainer.new()
	name_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_row.add_theme_constant_override("separation", 4)
	name_row.add_child(_legend_dot(row.get("color", RunView.SUPPLY_SEGMENT_COLORS[0])))

	var name_label := Label.new()
	var flow := str(row.get("flow", "")).strip_edges()
	var flow_bit := " · %s" % flow if not flow.is_empty() else ""
	var capacity_pct: int = int(row.get("capacityPct", 0))
	name_label.text = "%s%s · %d%% of capacity" % [str(row.get("name", "")), flow_bit, capacity_pct]
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_label.add_theme_font_size_override("font_size", 12)
	name_row.add_child(name_label)
	text.add_child(name_row)

	var fulfill_variant: Variant = row.get("fulfillPct")
	if fulfill_variant != null:
		var allocated: float = float(row.get("allocatedUnits", 0.0))
		var detail := Label.new()
		var detail_bits: PackedStringArray = ["%d%% supplied" % int(fulfill_variant)]
		if allocated > 0.0:
			detail_bits.append("%d units" % int(round(allocated)))
		detail.text = " · ".join(detail_bits)
		detail.add_theme_font_size_override("font_size", 10)
		detail.add_theme_color_override("font_color", Color(0.62, 0.68, 0.60, 1))
		text.add_child(detail)

	return text


func _build_supplier_row(row: Dictionary) -> Control:
	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.add_theme_constant_override("separation", 0)

	var name_label := Label.new()
	var flow := str(row.get("flow", "")).strip_edges()
	var flow_bit := " · %s" % flow if not flow.is_empty() else ""
	name_label.text = "%s%s · %d%% of supply mix" % [str(row.get("name", "")), flow_bit, int(row.get("sharePct", 0))]
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_label.add_theme_font_size_override("font_size", 12)
	text.add_child(name_label)

	var fulfill_variant: Variant = row.get("fulfillPct")
	if fulfill_variant != null:
		var detail := Label.new()
		detail.text = "%d%% fill" % int(fulfill_variant)
		detail.add_theme_font_size_override("font_size", 10)
		detail.add_theme_color_override("font_color", Color(0.62, 0.68, 0.60, 1))
		text.add_child(detail)

	return text


func _legend_dot(color: Color) -> ColorRect:
	var dot := ColorRect.new()
	dot.custom_minimum_size = Vector2(6, 6)
	dot.color = color
	return dot


func _clear_supply_balance() -> void:
	if _supply_balance_section == null:
		return
	_supply_balance_section.hide()
	for child in _supply_balance_section.get_children():
		child.queue_free()


func _populate_actions(actions: Variant) -> void:
	_clear_actions()
	_clear_improvements()
	_clear_level_up()
	_current_business_id = ""
	if typeof(actions) != TYPE_DICTIONARY:
		return
	var action_map: Dictionary = actions
	if action_map.is_empty():
		return

	var kind: String = str(action_map.get("kind", ""))
	match kind:
		"business":
			var business_id := str(action_map.get("businessId", ""))
			_current_business_id = business_id
			if action_map.has("improvements"):
				_populate_improvements(action_map.get("improvements", {}), business_id)
			if action_map.has("canNegotiateUrgency"):
				var problem_id := str(action_map.get("urgencyProblemId", ""))
				_add_action_button(
					str(action_map.get("negotiateUrgencyLabel", "Negotiate terms (1 AP)")),
					func() -> void: negotiate_urgency.emit(problem_id),
					not bool(action_map.get("canNegotiateUrgency", false)),
					{
						"apCost": 1,
						"blockedReason": str(action_map.get("negotiateUrgencyBlockedReason", "Need 1 AP")),
					},
				)
			if action_map.has("canSell"):
				_add_action_button(
					str(action_map.get("sellLabel", "Sell (−1 AP)")),
					func() -> void: sell_business.emit(business_id),
					not bool(action_map.get("canSell", false)),
					{"apCost": 1, "blockedReason": "Need 1 AP"},
				)
		"opportunity":
			var opportunity_id := str(action_map.get("opportunityId", ""))
			if action_map.has("canBuy"):
				_add_action_button(
					str(action_map.get("buyLabel", "Buy Now (−1 AP)")),
					func() -> void: buy_opportunity.emit(opportunity_id),
					not bool(action_map.get("canBuy", false)),
					{
						"apCost": 1,
						"cashNeed": int(action_map.get("price", 0)),
						"affordTint": true,
						"blockedReason": str(action_map.get("buyBlockedReason", "")),
					},
				)
			if action_map.has("canInvestigate"):
				_add_action_button(
					"Investigate (−1 AP)",
					func() -> void: investigate_opportunity.emit(opportunity_id),
					not bool(action_map.get("canInvestigate", false)),
					{"apCost": 1, "blockedReason": "Need 1 AP or already investigated"},
				)
			if action_map.has("canNegotiate"):
				var label: String = str(action_map.get("negotiateLabel", "Negotiate (−1 AP)"))
				_add_action_button(
					label,
					func() -> void: negotiate_opportunity.emit(opportunity_id),
					not bool(action_map.get("canNegotiate", false)),
					{"apCost": 1, "blockedReason": "Need 1 AP"},
				)
		"community":
			var community_business_id := str(action_map.get("communityBusinessId", ""))
			var parcel_id := str(action_map.get("parcelId", ""))
			var district_id := str(action_map.get("districtId", ""))
			if action_map.has("canChat"):
				var chat_label := str(action_map.get("chatLabel", "Chat (free)"))
				var can_chat := bool(action_map.get("canChat", false))
				_add_action_button(
					chat_label,
					func() -> void: chat_community_business.emit(community_business_id, parcel_id, district_id),
					not can_chat,
					{"blockedReason": str(action_map.get("chatDisabledReason", "Chat unavailable"))},
				)


func _populate_improvements(view: Variant, business_id: String) -> void:
	if typeof(view) != TYPE_DICTIONARY or not bool((view as Dictionary).get("visible", false)):
		return
	var rows: Array = (view as Dictionary).get("rows", [])
	if rows.is_empty():
		return

	_improvements_section.show()
	var grid := GridContainer.new()
	grid.columns = _IMPROVE_COLS
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 6)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_improvements_section.add_child(grid)

	_add_improve_header_cells(grid)
	for row_data_variant in rows:
		if typeof(row_data_variant) != TYPE_DICTIONARY:
			continue
		_add_improvement_cells(grid, row_data_variant as Dictionary, business_id)

	_populate_level_up((view as Dictionary).get("levelUp", {}))


func _add_improve_header_cells(grid: GridContainer) -> void:
	grid.add_child(_table_header_label("Category", _COL_CATEGORY))
	grid.add_child(_table_header_label("Lvl", _COL_LEVEL))
	grid.add_child(_table_header_label("Stat", _COL_STAT))
	grid.add_child(_table_header_label("Now", _COL_CURRENT))
	grid.add_child(_table_header_label("Next", _COL_IMPROVED))
	grid.add_child(_table_header_label("ⓘ", _COL_INFO))
	grid.add_child(_table_header_label("Act", _COL_ACTION))


func _add_improvement_cells(grid: GridContainer, row_data: Dictionary, business_id: String) -> void:
	grid.add_child(_table_cell_label(str(row_data.get("category", "")), _COL_CATEGORY))
	grid.add_child(_table_cell_label(str(row_data.get("levelText", "")), _COL_LEVEL))
	grid.add_child(_table_cell_label(str(row_data.get("statName", "")), _COL_STAT))
	grid.add_child(_table_cell_label(str(row_data.get("currentValue", "")), _COL_CURRENT))

	var improved_cell := VBoxContainer.new()
	improved_cell.custom_minimum_size.x = _COL_IMPROVED
	improved_cell.size_flags_horizontal = Control.SIZE_FILL
	improved_cell.add_theme_constant_override("separation", 0)
	improved_cell.add_child(_table_cell_label(str(row_data.get("improvedValue", "")), _COL_IMPROVED))
	var profit_hint := str(row_data.get("profitHint", "")).strip_edges()
	if not profit_hint.is_empty():
		var hint := Label.new()
		hint.text = profit_hint
		hint.custom_minimum_size.x = _COL_IMPROVED
		hint.clip_text = true
		hint.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		hint.add_theme_font_size_override("font_size", 9)
		hint.add_theme_color_override("font_color", Color(0.62, 0.72, 0.58, 1))
		improved_cell.add_child(hint)
	grid.add_child(improved_cell)

	var info_btn := Button.new()
	info_btn.text = "ⓘ"
	info_btn.custom_minimum_size = Vector2(_COL_INFO, 22)
	info_btn.focus_mode = Control.FOCUS_NONE
	var tip_text := str(row_data.get("infoTooltip", "")).strip_edges()
	info_btn.mouse_filter = Control.MOUSE_FILTER_STOP
	info_btn.mouse_entered.connect(func() -> void: _show_info_bubble(info_btn, tip_text))
	info_btn.mouse_exited.connect(_schedule_hide_info_bubble)
	FeedbackBus.wire_button(info_btn)
	grid.add_child(info_btn)

	var track_id := str(row_data.get("trackId", ""))
	var can_apply := bool(row_data.get("canApply", false))
	var blocked_reason := str(row_data.get("blockedReason", "")).strip_edges()
	var cost := int(row_data.get("cost", 0))
	var apply_btn := Button.new()
	apply_btn.text = str(row_data.get("buttonText", "—"))
	apply_btn.custom_minimum_size = Vector2(_COL_ACTION, 0)
	apply_btn.size_flags_horizontal = Control.SIZE_FILL
	apply_btn.add_theme_font_size_override("font_size", 11)
	apply_btn.disabled = false
	if not can_apply:
		apply_btn.modulate = Color(0.75, 0.72, 0.68, 0.85)
	apply_btn.pressed.connect(func() -> void:
		if not can_apply:
			FeedbackBus.deny(apply_btn)
			if not blocked_reason.is_empty():
				FeedbackBus.show_chip(blocked_reason, apply_btn, 1.8)
			return
		upgrade_track.emit(business_id, track_id)
	)
	FeedbackBus.wire_button(apply_btn)
	var tip_bits: PackedStringArray = ["−1 AP"]
	if cost > 0:
		tip_bits.append("needs %s cash" % MathUtil.fmt_money(cost))
	if not can_apply and not blocked_reason.is_empty():
		tip_bits.append(blocked_reason)
	apply_btn.tooltip_text = " · ".join(tip_bits)
	apply_btn.mouse_entered.connect(func() -> void:
		if can_apply:
			FeedbackBus.float_text_near(apply_btn, "−1 AP", Color(0.95, 0.82, 0.35, 1.0))
		elif not blocked_reason.is_empty():
			FeedbackBus.float_text_near(apply_btn, blocked_reason, Color(0.92, 0.9, 0.82, 1.0))
	)
	grid.add_child(apply_btn)


func _table_header_label(text: String, min_w: int) -> Label:
	var label := Label.new()
	label.text = text
	label.custom_minimum_size = Vector2(min_w, 0)
	label.size_flags_horizontal = Control.SIZE_FILL
	label.clip_text = true
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.add_theme_font_size_override("font_size", 10)
	label.add_theme_color_override("font_color", Color(0.62, 0.66, 0.58, 1))
	return label


func _table_cell_label(text: String, min_w: int) -> Label:
	var label := Label.new()
	label.text = text
	label.custom_minimum_size = Vector2(min_w, 0)
	label.size_flags_horizontal = Control.SIZE_FILL
	label.clip_text = false
	label.autowrap_mode = TextServer.AUTOWRAP_OFF
	label.add_theme_font_size_override("font_size", 11)
	return label


func _ensure_tooltip_layer() -> CanvasLayer:
	if _tooltip_layer != null and is_instance_valid(_tooltip_layer):
		return _tooltip_layer
	_tooltip_layer = CanvasLayer.new()
	_tooltip_layer.layer = 30
	add_child(_tooltip_layer)
	return _tooltip_layer


func _show_info_bubble(anchor: Control, text: String) -> void:
	_cancel_hide_info_bubble()
	if text.is_empty() or anchor == null:
		return
	_hide_info_bubble()

	var layer := _ensure_tooltip_layer()
	_info_bubble = PanelContainer.new()
	_info_bubble.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.10, 0.13, 0.11, 0.96)
	style.set_corner_radius_all(6)
	style.content_margin_left = _INFO_BUBBLE_PADDING
	style.content_margin_right = _INFO_BUBBLE_PADDING
	style.content_margin_top = _INFO_BUBBLE_PADDING
	style.content_margin_bottom = _INFO_BUBBLE_PADDING
	style.border_color = Color(0.52, 0.58, 0.48, 0.85)
	style.set_border_width_all(1)
	_info_bubble.add_theme_stylebox_override("panel", style)

	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	var font_size := 10
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", Color(0.90, 0.92, 0.86, 1))

	var wrap_w := float(_INFO_BUBBLE_MAX_WIDTH)
	var text_size := Vector2(wrap_w, float(font_size + 4))
	var font := label.get_theme_font("font")
	if font != null:
		text_size = font.get_multiline_string_size(
			text, HORIZONTAL_ALIGNMENT_LEFT, wrap_w, font_size
		)
	text_size.x = wrap_w
	text_size.y = clampf(text_size.y, float(font_size + 4), float(_INFO_BUBBLE_MAX_HEIGHT))
	label.custom_minimum_size = text_size
	label.size = text_size
	_info_bubble.add_child(label)
	layer.add_child(_info_bubble)

	var h_pad := float(_INFO_BUBBLE_PADDING) * 2.0 + 2.0
	var v_pad := float(_INFO_BUBBLE_PADDING) * 2.0 + 2.0
	var bubble_size := text_size + Vector2(h_pad, v_pad)
	_info_bubble.custom_minimum_size = bubble_size
	_info_bubble.size = bubble_size

	await get_tree().process_frame
	if _info_bubble == null or not is_instance_valid(_info_bubble):
		return

	var panel_rect := get_global_rect()
	var anchor_rect := anchor.get_global_rect()
	var gx := anchor_rect.position.x - bubble_size.x - 8.0
	var gy := anchor_rect.position.y + anchor_rect.size.y * 0.5 - bubble_size.y * 0.5
	gx = clampf(gx, panel_rect.position.x + 4.0, panel_rect.end.x - bubble_size.x - 4.0)
	gy = clampf(gy, panel_rect.position.y + 4.0, panel_rect.end.y - bubble_size.y - 4.0)
	_info_bubble.global_position = Vector2(gx, gy)
	_info_bubble.modulate.a = 0.0
	var tween := create_tween()
	tween.tween_property(_info_bubble, "modulate:a", 1.0, 0.12)


func _schedule_hide_info_bubble() -> void:
	if _info_bubble_hide_timer == null:
		_info_bubble_hide_timer = Timer.new()
		_info_bubble_hide_timer.one_shot = true
		_info_bubble_hide_timer.wait_time = 0.05
		add_child(_info_bubble_hide_timer)
		_info_bubble_hide_timer.timeout.connect(_hide_info_bubble)
	_info_bubble_hide_timer.start()


func _cancel_hide_info_bubble() -> void:
	if _info_bubble_hide_timer != null:
		_info_bubble_hide_timer.stop()


func _hide_info_bubble() -> void:
	if _info_bubble != null and is_instance_valid(_info_bubble):
		_info_bubble.queue_free()
	_info_bubble = null


func _populate_level_up(view: Variant) -> void:
	_clear_level_up()
	if typeof(view) != TYPE_DICTIONARY:
		return
	var level_view: Dictionary = view
	if not bool(level_view.get("visible", false)) or not bool(level_view.get("ready", false)):
		return

	_level_up_section.show()
	_pending_level_up_opp_id = str(level_view.get("opportunityId", ""))

	var title := Label.new()
	title.text = "Level %d ready — %s" % [
		int(level_view.get("targetLevel", 1)),
		str(level_view.get("title", "Level up")),
	]
	title.add_theme_font_size_override("font_size", 13)
	title.add_theme_color_override("font_color", Color(0.92, 0.82, 0.45, 1))
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_level_up_section.add_child(title)

	var blurb := Label.new()
	blurb.text = str(level_view.get("blurb", ""))
	blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	blurb.add_theme_font_size_override("font_size", 12)
	_level_up_section.add_child(blurb)

	var reward := Label.new()
	reward.text = str(level_view.get("rewardLine", ""))
	reward.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	reward.add_theme_font_size_override("font_size", 12)
	reward.add_theme_color_override("font_color", Color(0.72, 0.88, 0.72, 1))
	_level_up_section.add_child(reward)

	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 8)
	var price: int = int(level_view.get("price", 0))
	if bool(level_view.get("requiresNegotiation", false)):
		var negotiate_btn := Button.new()
		negotiate_btn.text = "Negotiate · 1 AP"
		var can_negotiate := bool(level_view.get("canNegotiate", false))
		if not can_negotiate:
			negotiate_btn.modulate = Color(0.75, 0.72, 0.68, 0.85)
		negotiate_btn.pressed.connect(func() -> void:
			if not can_negotiate:
				FeedbackBus.deny(negotiate_btn)
				FeedbackBus.show_chip("Need 1 AP", negotiate_btn, 1.8)
				return
			negotiate_level_up.emit(_pending_level_up_opp_id)
		)
		FeedbackBus.wire_button(negotiate_btn)
		actions.add_child(negotiate_btn)
	else:
		var invest_btn := Button.new()
		invest_btn.text = "1 AP + %s" % MathUtil.fmt_money(price)
		var can_invest := bool(level_view.get("canInvest", false))
		if not can_invest:
			invest_btn.modulate = Color(0.75, 0.72, 0.68, 0.85)
		invest_btn.pressed.connect(func() -> void:
			if not can_invest:
				FeedbackBus.deny(invest_btn)
				var reason := "Need 1 AP" if Game.state.action_points < 1 else "Insufficient cash"
				FeedbackBus.show_chip(reason, invest_btn, 1.8)
				return
			level_up.emit(_pending_level_up_opp_id)
		)
		FeedbackBus.wire_button(invest_btn)
		actions.add_child(invest_btn)
	_level_up_section.add_child(actions)


func _clear_improvements() -> void:
	if _improvements_section == null:
		return
	_improvements_section.hide()
	for child in _improvements_section.get_children():
		child.queue_free()


func _clear_level_up() -> void:
	if _level_up_section == null:
		return
	_level_up_section.hide()
	_pending_level_up_opp_id = ""
	for child in _level_up_section.get_children():
		child.queue_free()


func _add_action_button(label: String, callback: Callable, disabled: bool = false, meta: Dictionary = {}) -> void:
	var btn := Button.new()
	btn.text = label
	btn.disabled = false
	var blocked := disabled
	var blocked_reason := str(meta.get("blockedReason", "Unavailable")).strip_edges()
	if blocked:
		btn.modulate = Color(0.75, 0.72, 0.68, 0.85)
	btn.pressed.connect(func() -> void:
		if blocked:
			FeedbackBus.deny(btn)
			if not blocked_reason.is_empty():
				FeedbackBus.show_chip(blocked_reason, btn, 1.8)
			return
		callback.call()
	)
	FeedbackBus.wire_button(btn)

	var ap_cost := int(meta.get("apCost", 0))
	var cash_need := int(meta.get("cashNeed", 0))
	if bool(meta.get("affordTint", false)) and not blocked:
		var cash := Game.state.cash if Game.state != null else 0
		btn.modulate = FeedbackBus.affordability_color(cash, cash_need)

	var tip_bits: PackedStringArray = []
	if ap_cost > 0:
		tip_bits.append("−%d AP" % ap_cost)
	if cash_need > 0:
		tip_bits.append("needs %s cash" % MathUtil.fmt_money(cash_need))
	if blocked and not blocked_reason.is_empty():
		tip_bits.append(blocked_reason)
	var tip := " · ".join(tip_bits)
	btn.tooltip_text = tip

	btn.mouse_entered.connect(func() -> void:
		if ap_cost > 0:
			FeedbackBus.float_text_near(btn, "−%d AP" % ap_cost, Color(0.95, 0.82, 0.35, 1.0))
		elif not tip.is_empty():
			FeedbackBus.float_text_near(btn, tip, Color(0.92, 0.9, 0.82, 1.0))
	)
	_actions_row.add_child(btn)


func _clear_actions() -> void:
	if _actions_row == null:
		return
	for child in _actions_row.get_children():
		child.queue_free()
