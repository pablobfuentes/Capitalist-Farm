extends PanelContainer

signal closed
signal improve_business(business_id: String)
signal sell_business(business_id: String)
signal buy_opportunity(opportunity_id: String)
signal investigate_opportunity(opportunity_id: String)
signal negotiate_opportunity(opportunity_id: String)
signal chat_community_business(community_business_id: String, parcel_id: String, district_id: String)

@onready var _title_label: Label = %TitleLabel
@onready var _role_label: Label = %RoleLabel
@onready var _details_label: Label = %DetailsLabel
@onready var _ownership_label: Label = %StubLabel
@onready var _actions_row: HBoxContainer = %ActionsRow
@onready var _close_button: Button = %CloseButton


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_close_button.pressed.connect(_on_close_pressed)


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
	_clear_actions()


func _on_close_pressed() -> void:
	hide_panel()
	closed.emit()


func _apply_view(view: Dictionary) -> void:
	_title_label.text = str(view.get("title", "Parcel"))
	_role_label.text = str(view.get("roleLine", ""))
	_details_label.text = str(view.get("details", ""))
	_ownership_label.text = str(view.get("ownershipLine", ""))
	_ownership_label.add_theme_color_override("font_color", view.get("ownershipColor", Color.WHITE))
	_populate_actions(view.get("actions", {}))
	_sync_details_scroll_width()
	visible = true
	mouse_filter = Control.MOUSE_FILTER_STOP


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
			if action_map.has("canImprove"):
				_add_action_button(
					str(action_map.get("improveLabel", "Improve (1 AP)")),
					func() -> void: improve_business.emit(business_id),
					not bool(action_map.get("canImprove", false)),
				)
			if action_map.has("canSell"):
				_add_action_button(
					str(action_map.get("sellLabel", "Sell (1 AP)")),
					func() -> void: sell_business.emit(business_id),
					not bool(action_map.get("canSell", false)),
				)
		"opportunity":
			var opportunity_id := str(action_map.get("opportunityId", ""))
			if action_map.has("canBuy"):
				_add_action_button(
					str(action_map.get("buyLabel", "Buy Now (1 AP)")),
					func() -> void: buy_opportunity.emit(opportunity_id),
					not bool(action_map.get("canBuy", false)),
				)
			if action_map.has("canInvestigate"):
				_add_action_button(
					"Investigate (1 AP)",
					func() -> void: investigate_opportunity.emit(opportunity_id),
					not bool(action_map.get("canInvestigate", false)),
				)
			if action_map.has("canNegotiate"):
				var label: String = str(action_map.get("negotiateLabel", "Negotiate (1 AP)"))
				_add_action_button(
					label,
					func() -> void: negotiate_opportunity.emit(opportunity_id),
					not bool(action_map.get("canNegotiate", false)),
				)
		"community":
			var community_business_id := str(action_map.get("communityBusinessId", ""))
			var parcel_id := str(action_map.get("parcelId", ""))
			var district_id := str(action_map.get("districtId", ""))
			if action_map.has("canChat"):
				var chat_label := str(action_map.get("chatLabel", "Chat (free)"))
				var can_chat := bool(action_map.get("canChat", false))
				var btn := Button.new()
				btn.text = chat_label
				btn.disabled = not can_chat
				if not can_chat:
					var reason := str(action_map.get("chatDisabledReason", "")).strip_edges()
					if not reason.is_empty():
						btn.tooltip_text = reason
				btn.pressed.connect(func() -> void:
					chat_community_business.emit(community_business_id, parcel_id, district_id)
				)
				_actions_row.add_child(btn)


func _add_action_button(label: String, callback: Callable, disabled: bool = false) -> void:
	var btn := Button.new()
	btn.text = label
	btn.disabled = disabled
	btn.pressed.connect(callback)
	_actions_row.add_child(btn)


func _clear_actions() -> void:
	if _actions_row == null:
		return
	for child in _actions_row.get_children():
		child.queue_free()
