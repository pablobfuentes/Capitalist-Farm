extends PanelContainer

signal closed
signal improve_business(business_id: String)
signal sell_business(business_id: String)
signal buy_opportunity(opportunity_id: String)
signal investigate_opportunity(opportunity_id: String)
signal negotiate_opportunity(opportunity_id: String)
signal negotiate_urgency(problem_id: String)
signal chat_community_business(community_business_id: String, parcel_id: String, district_id: String)

@onready var _title_label: Label = %TitleLabel
@onready var _role_label: Label = %RoleLabel
@onready var _details_label: Label = %DetailsLabel
@onready var _ownership_label: Label = %StubLabel
@onready var _actions_row: HBoxContainer = %ActionsRow
@onready var _close_button: Button = %CloseButton
var _shown_key := ""


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_close_button.pressed.connect(_on_close_pressed)
	var details_scroll: ScrollContainer = %DetailsScroll
	if details_scroll != null:
		FeedbackBus.wire_scroll(details_scroll)
	# Keep a little transparency, but opaque enough that map detail doesn't wash out text.
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
	_clear_actions()


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
	_populate_actions(view.get("actions", {}))
	_sync_details_scroll_width()
	visible = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	# Never animate position on this anchored panel — it fights TOP_RIGHT offsets and clips off-screen.
	if should_fade:
		FeedbackBus.panel_fade_in(self)


func _sync_details_scroll_width() -> void:
	var scroll: ScrollContainer = %DetailsScroll
	if scroll == null or _details_label == null:
		return
	await get_tree().process_frame
	var scroll_w := maxi(int(scroll.size.x) - 8, 200)
	_details_label.custom_minimum_size.x = scroll_w


func _populate_actions(actions: Variant) -> void:
	_clear_actions()
	if typeof(actions) != TYPE_DICTIONARY:
		return
	var action_map: Dictionary = actions
	if action_map.is_empty():
		return

	var kind: String = str(action_map.get("kind", ""))
	match kind:
		"business":
			var business_id := str(action_map.get("businessId", ""))
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
			if action_map.has("canImprove"):
				_add_action_button(
					str(action_map.get("improveLabel", "Improve (−1 AP)")),
					func() -> void: improve_business.emit(business_id),
					not bool(action_map.get("canImprove", false)),
					{"apCost": 1, "blockedReason": "Need 1 AP"},
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


func _add_action_button(label: String, callback: Callable, disabled: bool = false, meta: Dictionary = {}) -> void:
	# Keep the control hoverable even when the action is blocked so AP/cash previews work.
	# Disabled Godot buttons do not receive mouse enter / tooltips.
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
