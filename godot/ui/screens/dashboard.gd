extends Control

const _Rival := preload("res://core/systems/rival_system.gd")
const _SupplyPolicy := preload("res://core/systems/supply_policy_system.gd")
const _LoanSystem := preload("res://core/systems/loan_system.gd")
const _RealEstate := preload("res://core/systems/real_estate_system.gd")

@onready var turn_label: Label = %TurnLabel
@onready var cash_label: Label = %CashLabel
@onready var nw_label: Label = %NetWorthLabel
@onready var debt_label: Label = %DebtLabel
@onready var ap_label: Label = %ActionPointsLabel
@onready var reputation_label: Label = %ReputationLabel
@onready var portfolio_list: VBoxContainer = %PortfolioList
@onready var opportunities_list: VBoxContainer = %OpportunitiesList
@onready var supply_chain_list: VBoxContainer = %SupplyChainList
@onready var debrief_toggle: Button = %DebriefToggle
@onready var debrief_body: VBoxContainer = %DebriefBody
@onready var debrief_label: Label = %DebriefLabel
@onready var debrief_summary: Label = %DebriefSummary
@onready var advance_button: Button = %AdvanceButton

var _improve_panel: Window = null
var _negotiation_panel: Window = null
var _shortage_modal: Window = null
var _edge_modal: Window = null
var _supply_chain_view: Window = null
var _field_guide: Window = null
var _turn_debrief_modal: Window = null
var _re_improve_panel: Window = null


func _ready() -> void:
	if not Game.has_active_run():
		Game.go_to_main_menu()
		return

	_improve_panel = preload("res://ui/screens/improve_panel.tscn").instantiate()
	add_child(_improve_panel)
	_improve_panel.closed.connect(_refresh)

	_negotiation_panel = preload("res://ui/screens/negotiation_panel.tscn").instantiate()
	add_child(_negotiation_panel)
	_negotiation_panel.closed.connect(_refresh)

	_shortage_modal = preload("res://ui/screens/supply_shortage_modal.tscn").instantiate()
	add_child(_shortage_modal)
	_shortage_modal.confirmed.connect(_on_shortage_confirmed)
	_shortage_modal.cancelled.connect(_on_shortage_cancelled)

	_supply_chain_view = preload("res://ui/screens/supply_chain_view.tscn").instantiate()
	add_child(_supply_chain_view)
	_field_guide = preload("res://ui/screens/field_guide_modal.tscn").instantiate()
	add_child(_field_guide)

	_turn_debrief_modal = preload("res://ui/screens/turn_debrief_modal.tscn").instantiate()
	add_child(_turn_debrief_modal)
	_turn_debrief_modal.continued.connect(_on_turn_debrief_continued)

	_re_improve_panel = preload("res://ui/screens/real_estate_improve_panel.tscn").instantiate()
	add_child(_re_improve_panel)
	_re_improve_panel.closed.connect(_refresh)

	debrief_toggle.pressed.connect(_on_debrief_toggle_pressed)

	EventBus.turn_advanced.connect(_on_state_changed)
	EventBus.command_applied.connect(_on_state_changed)
	EventBus.asset_acquired.connect(_on_state_changed)
	_refresh()


func _on_state_changed(_a = null, _b = null) -> void:
	_refresh()


func _refresh() -> void:
	var s: RunState = Game.state
	if s == null:
		return

	turn_label.text = "Turn %d / %d" % [s.turn, s.max_turns]
	cash_label.text = "Cash: %s" % MathUtil.fmt_money(s.cash)
	nw_label.text = "Net worth: %s" % MathUtil.fmt_money(Game.net_worth())
	debt_label.text = "Debt: %s" % MathUtil.fmt_money(_LoanSystem.total_debt(s))
	var max_ap: int = ActionPointsSystem.max_action_points(s)
	ap_label.text = "AP: %d / %d" % [s.action_points, max_ap]
	reputation_label.text = "Rep: %d" % s.reputation

	if s.game_over != null:
		Game.go_to_run_report()
		return

	if not s.last_advance_report.is_empty():
		_update_debrief_card(s)
	else:
		debrief_toggle.visible = false
		debrief_body.visible = true
		debrief_label.text = "Acquire your first business, then advance the turn."
		debrief_summary.text = ""

	_populate_portfolio(s)
	_populate_opportunities(s)
	_populate_supply_chain(s)
	_maybe_show_edge_choices(s)
	_maybe_show_turn_debrief(s)
	advance_button.disabled = s.game_over != null


func _update_debrief_card(s: RunState) -> void:
	var r: Dictionary = s.last_advance_report
	debrief_toggle.visible = true
	var nw_delta: int = int(r.get("nwDelta", 0))
	var cash_flow: int = int(r.get("netCashFlow", r.get("profit", 0)))
	var turn_closed: int = int(r.get("turnClosed", maxi(1, s.turn - 1)))
	var nw_sign := "+" if nw_delta >= 0 else ""
	debrief_toggle.text = "%s Turn %d — %s cash flow · %s%s NW" % [
		"▼" if s.debrief_expanded else "▶",
		turn_closed,
		MathUtil.fmt_money(cash_flow),
		nw_sign,
		MathUtil.fmt_money(nw_delta),
	]
	debrief_body.visible = s.debrief_expanded
	var ext_line := ""
	var ext_rev: int = int(r.get("externalRevenue", 0))
	if ext_rev > 0:
		ext_line = " · External %s/qtr" % MathUtil.fmt_money(ext_rev)
	debrief_label.text = "Rev %s · Cost %s · Profit %s · Links %s%s" % [
		MathUtil.fmt_money(int(r.get("revenueTotal", 0))),
		MathUtil.fmt_money(int(r.get("costTotal", 0))),
		MathUtil.fmt_money(int(r.get("profit", r.get("profitQuarterClosed", 0)))),
		str(r.get("synergyCount", 0)),
		ext_line,
	]
	var summary: String = str(r.get("summary", ""))
	debrief_summary.text = summary
	debrief_summary.visible = not summary.is_empty()


func _on_debrief_toggle_pressed() -> void:
	var s: RunState = Game.state
	if s == null:
		return
	s.debrief_expanded = not s.debrief_expanded
	_update_debrief_card(s)


func _maybe_show_turn_debrief(s: RunState) -> void:
	if s.pending_turn_debrief.is_empty() or s.game_over != null:
		return
	if _turn_debrief_modal.visible:
		return
	_turn_debrief_modal.open_with_report(s.pending_turn_debrief)


func _on_turn_debrief_continued() -> void:
	Game.apply_command(GameCommand.dismiss_turn_debrief())
	_refresh()


func _populate_portfolio(s: RunState) -> void:
	for child in portfolio_list.get_children():
		child.queue_free()

	var has_businesses := not s.portfolio.businesses.is_empty()
	var has_loans := not s.loans.is_empty()
	var has_securities := not s.portfolio.securities.is_empty()
	var has_re := not s.portfolio.real_estate.is_empty()

	if not has_businesses and not has_loans and not has_securities and not has_re:
		var empty := Label.new()
		empty.text = "No businesses yet."
		portfolio_list.add_child(empty)
		return

	if has_businesses:
		if UpgradeSystem.is_active(s):
			UpgradeSystem.ensure_portfolio_upgrades(s)

		for biz: BusinessInstance in s.portfolio.businesses:
			var tmpl := Content.get_template(biz.template_id)
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 8)

			var info := Label.new()
			info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			var layer_text := tmpl.layer_label if tmpl else biz.layer
			var ap_text := UpgradeSystem.autopilot_display(biz) if UpgradeSystem.is_active(s) else ("★".repeat(tmpl.autopilot if tmpl else 3) + "☆".repeat(2))
			var lever_bits: Array[String] = []
			if UpgradeSystem.is_active(s):
				for track_id: String in ["hire", "marketing", "automation", "care"]:
					var tier: int = int(biz.upgrades.get(track_id, 0))
					if tier > 0:
						lever_bits.append("%s %s" % [track_id.substr(0, 1).to_upper(), UpgradeSystem.render_tier_pips(tier, 3)])
			var levers := " · ".join(lever_bits)
			info.text = "%s\n[%s] %s · AP %s\nRev %s / Cost %s%s" % [
				biz.name,
				layer_text,
				tmpl.name if tmpl else biz.template_id,
				ap_text,
				MathUtil.fmt_money(biz.revenue_per_turn),
				MathUtil.fmt_money(biz.operating_costs),
				("\n" + levers) if levers != "" else "",
			]
			row.add_child(info)

			if UpgradeSystem.is_active(s):
				var improve := Button.new()
				improve.text = "Improve (1 AP)"
				improve.disabled = s.action_points < 1
				improve.pressed.connect(_on_improve_pressed.bind(biz.id))
				row.add_child(improve)

			var sell := Button.new()
			sell.text = "Sell (1 AP)"
			sell.disabled = s.action_points < 1
			sell.pressed.connect(_on_sell_pressed.bind("business", biz.id))
			row.add_child(sell)

			portfolio_list.add_child(row)

	for raw_variant in s.portfolio.real_estate:
		if typeof(raw_variant) != TYPE_DICTIONARY:
			continue
		var asset: Dictionary = raw_variant
		var template_id: String = str(asset.get("templateId", asset.get("template_id", "")))
		var tmpl := Content.get_template(template_id)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var info := Label.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		var link_count: int = _RealEstate.downstream_link_count(s, template_id)
		var link_line := ""
		if Content.is_infrastructure_template(template_id):
			link_line = " · Serves %d downstream link(s)" % link_count
		info.text = "%s\n[%s] %s · Rent %s / Opex %s · Val %s%s" % [
			str(asset.get("name", "Property")),
			tmpl.layer_label if tmpl else "Infrastructure",
			tmpl.name if tmpl else template_id,
			MathUtil.fmt_money(int(asset.get("rentPerTurn", asset.get("rent_per_turn", 0)))),
			MathUtil.fmt_money(int(asset.get("operatingExpenses", asset.get("operating_expenses", 0)))),
			MathUtil.fmt_money(int(asset.get("valuation", asset.get("markedValue", 0)))),
			link_line,
		]
		row.add_child(info)
		if not _RealEstate.improvements_for_asset(s, asset).is_empty():
			var improve_re := Button.new()
			improve_re.text = "Improve (1 AP)"
			improve_re.disabled = s.action_points < 1
			improve_re.pressed.connect(_on_improve_re_pressed.bind(str(asset.get("id", ""))))
			row.add_child(improve_re)
		var sell_re := Button.new()
		sell_re.text = "Sell (1 AP)"
		sell_re.disabled = s.action_points < 1
		sell_re.pressed.connect(_on_sell_pressed.bind("realestate", str(asset.get("id", ""))))
		row.add_child(sell_re)
		portfolio_list.add_child(row)

	for raw_variant in s.portfolio.securities:
		if typeof(raw_variant) != TYPE_DICTIONARY:
			continue
		var holding: Dictionary = raw_variant
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var info := Label.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		info.text = SecuritySystem.format_holding_summary(holding)
		row.add_child(info)
		var sell := Button.new()
		sell.text = "Sell"
		var ticker: String = str(holding.get("ticker", ""))
		sell.pressed.connect(_on_sell_security_pressed.bind(ticker))
		row.add_child(sell)
		portfolio_list.add_child(row)

	if has_loans:
		if has_businesses:
			var heading := Label.new()
			heading.text = "Loans"
			portfolio_list.add_child(heading)

		for loan_variant in s.loans:
			if typeof(loan_variant) != TYPE_DICTIONARY:
				continue
			var loan: Dictionary = loan_variant
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 8)

			var info := Label.new()
			info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			info.text = _LoanSystem.format_portfolio_line(loan)
			row.add_child(info)

			var payoff := Button.new()
			payoff.text = "Pay Off Early"
			var loan_id: String = str(loan.get("id", ""))
			payoff.disabled = s.cash < int(loan.get("principal", 0))
			payoff.pressed.connect(_on_payoff_loan_pressed.bind(loan_id))
			row.add_child(payoff)

			portfolio_list.add_child(row)


func _populate_urgent_problems(s: RunState) -> void:
	if s.urgent_problems.is_empty():
		return
	var heading := Label.new()
	heading.text = "⚠ Urgent relationship issues"
	heading.add_theme_color_override("font_color", Color(0.9, 0.65, 0.45))
	opportunities_list.add_child(heading)
	for prob_variant in s.urgent_problems:
		if typeof(prob_variant) != TYPE_DICTIONARY:
			continue
		var prob: Dictionary = prob_variant
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var info := Label.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		info.text = str(prob.get("text", "Relationship issue"))
		row.add_child(info)
		var negotiate := Button.new()
		negotiate.text = "Negotiate (1 AP)"
		var prob_id: String = str(prob.get("id", ""))
		negotiate.disabled = s.action_points < 1 or (not s.negotiation.is_empty() and bool(s.negotiation.get("active", false)))
		negotiate.pressed.connect(_on_urgent_negotiate_pressed.bind(prob_id))
		row.add_child(negotiate)
		opportunities_list.add_child(row)


func _populate_opportunities(s: RunState) -> void:
	for child in opportunities_list.get_children():
		child.queue_free()

	_populate_urgent_problems(s)

	if s.opportunities.is_empty() and s.urgent_problems.is_empty():
		var empty := Label.new()
		empty.text = "No listings this turn."
		opportunities_list.add_child(empty)
		return

	for opp_variant in s.opportunities:
		if typeof(opp_variant) != TYPE_DICTIONARY:
			continue
		var opp: Dictionary = opp_variant
		if str(opp.get("assetType", "")) == "loan":
			_add_loan_opportunity_row(s, opp)
			continue
		if str(opp.get("assetType", "")) == "security":
			_add_security_opportunity_row(s, opp)
			continue
		if str(opp.get("assetType", "")) == "realestate":
			_add_real_estate_opportunity_row(s, opp)
			continue
		if str(opp.get("assetType", "")) == "levelup":
			_add_level_up_opportunity_row(s, opp)
			continue
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)

		var info := Label.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		var tmpl := Content.get_template(str(opp.get("templateId", "")))
		var layer_text := tmpl.layer_label if tmpl else str(opp.get("layer", ""))
		var prefix := ""
		if bool(opp.get("chainHintDeal", false)):
			prefix = "⛓ Chain link — "
		if bool(opp.get("rivalContest", false)):
			prefix = "⚔ %s is contesting — " % _Rival.RIVAL_NAME
		var intel_tag := ""
		if bool(opp.get("diligenceDone", false)):
			var preview_raw: Variant = opp.get("v2Preview")
			if preview_raw is Dictionary and not (preview_raw as Dictionary).is_empty():
				var preview: Dictionary = preview_raw as Dictionary
				intel_tag = " · 🔎 %.0f%% disc · floor %s" % [
					float(preview.get("openingDiscountPct", 0.0)) * 100.0,
					MathUtil.fmt_money(int(preview.get("hardFloor", 0))),
				]
			else:
				intel_tag = " · 🔎 Intel ready"
		var expiry_tag := " · %d qtr left" % int(opp.get("expiresIn", 0)) if int(opp.get("expiresIn", 0)) > 0 else ""
		info.text = "%s%s (%s)\n%s · Ask %s · Profit %s/qtr%s%s" % [
			prefix,
			str(opp.get("name", "Listing")),
			layer_text,
			str(opp.get("blurb", "")).substr(0, 80),
			MathUtil.fmt_money(int(opp.get("price", 0))),
			MathUtil.fmt_money(int(opp.get("revenue", 0)) - int(opp.get("cost", 0))),
			expiry_tag,
			intel_tag,
		]
		row.add_child(info)

		var buy := Button.new()
		buy.text = "Buy Now (1 AP)"
		var opp_id: String = str(opp.get("id", ""))
		var price: int = int(opp.get("price", 0))
		var is_contest: bool = bool(opp.get("rivalContest", false))
		buy.disabled = s.action_points < 1 or is_contest or s.cash < price
		buy.pressed.connect(_on_buy_pressed.bind(opp_id))
		row.add_child(buy)

		var investigate := Button.new()
		investigate.text = "Investigate (1 AP)"
		investigate.disabled = s.action_points < 1 or bool(opp.get("diligenceDone", false))
		investigate.pressed.connect(_on_investigate_pressed.bind(opp_id))
		row.add_child(investigate)

		var negotiate := Button.new()
		negotiate.text = "Contest (1 AP)" if is_contest else "Negotiate (1 AP)"
		negotiate.disabled = s.action_points < 1
		negotiate.pressed.connect(_on_negotiate_pressed.bind(opp_id))
		row.add_child(negotiate)

		opportunities_list.add_child(row)


func _add_level_up_opportunity_row(s: RunState, opp: Dictionary) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var info := Label.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var expiry_tag := " · %d qtr left" % int(opp.get("expiresIn", 0)) if int(opp.get("expiresIn", 0)) > 0 else ""
	info.text = "⬆ %s\n%s · Invest %s%s" % [
		str(opp.get("name", "Level up")),
		str(opp.get("blurb", "")).substr(0, 80),
		MathUtil.fmt_money(int(opp.get("price", 0))),
		expiry_tag,
	]
	row.add_child(info)
	var opp_id: String = str(opp.get("id", ""))
	if bool(opp.get("requiresNegotiation", false)):
		var negotiate := Button.new()
		negotiate.text = "Negotiate (1 AP)"
		negotiate.disabled = s.action_points < 1
		negotiate.pressed.connect(_on_negotiate_pressed.bind(opp_id))
		row.add_child(negotiate)
	else:
		var invest := Button.new()
		invest.text = "Invest (1 AP)"
		invest.disabled = s.action_points < 1 or s.cash < int(opp.get("price", 0))
		invest.pressed.connect(_on_level_up_pressed.bind(opp_id))
		row.add_child(invest)
	opportunities_list.add_child(row)


func _on_level_up_pressed(opportunity_id: String) -> void:
	var result: Dictionary = Game.apply_command(GameCommand.do_level_up(opportunity_id))
	if not bool(result.get("ok", false)):
		debrief_label.text = "Level-up failed: %s" % str(result.get("error", "unknown"))
	else:
		debrief_label.text = "Level-up completed."


func _on_urgent_negotiate_pressed(problem_id: String) -> void:
	var result: Dictionary = Game.apply_command(GameCommand.start_urgent_negotiation(problem_id))
	if not bool(result.get("ok", false)):
		debrief_label.text = "Urgent negotiation failed: %s" % str(result.get("error", "unknown"))
	else:
		_negotiation_panel.open_active()


func _maybe_show_edge_choices(s: RunState) -> void:
	if s.edge_choices_pending.is_empty() or s.game_over != null:
		if _edge_modal != null and is_instance_valid(_edge_modal):
			_edge_modal.queue_free()
			_edge_modal = null
		return
	if _edge_modal != null and is_instance_valid(_edge_modal):
		return
	_edge_modal = Window.new()
	_edge_modal.title = "New Strategic Edge"
	_edge_modal.size = Vector2i(520, 420)
	_edge_modal.unresizable = true
	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 8)
	var sub := Label.new()
	sub.text = "Choose one edge to add to your build:"
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(sub)
	for choice_variant in s.edge_choices_pending:
		if typeof(choice_variant) != TYPE_DICTIONARY:
			continue
		var edge: Dictionary = choice_variant
		var btn := Button.new()
		btn.text = "%s — %s" % [str(edge.get("name", "")), str(edge.get("effect", ""))]
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		var edge_id: String = str(edge.get("id", ""))
		btn.pressed.connect(_on_edge_chosen.bind(edge_id))
		root.add_child(btn)
	var skip := Button.new()
	skip.text = "Skip"
	skip.pressed.connect(_on_edge_skipped)
	root.add_child(skip)
	_edge_modal.add_child(root)
	add_child(_edge_modal)
	_edge_modal.popup_centered()


func _on_edge_chosen(edge_id: String) -> void:
	var result: Dictionary = Game.apply_command(GameCommand.choose_edge(edge_id))
	if bool(result.get("ok", false)):
		debrief_label.text = "Strategic edge acquired."
	if _edge_modal != null and is_instance_valid(_edge_modal):
		_edge_modal.queue_free()
		_edge_modal = null
	_refresh()


func _on_edge_skipped() -> void:
	Game.apply_command(GameCommand.skip_edge())
	if _edge_modal != null and is_instance_valid(_edge_modal):
		_edge_modal.queue_free()
		_edge_modal = null
	_refresh()


func _add_real_estate_opportunity_row(s: RunState, opp: Dictionary) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var info := Label.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var prefix := "⛓ Chain link — " if bool(opp.get("chainHintDeal", false)) else ""
	var expiry_tag := " · %d qtr left" % int(opp.get("expiresIn", 0)) if int(opp.get("expiresIn", 0)) > 0 else ""
	info.text = "%s%s (Infrastructure)\n%s · Ask %s · Rent %s/qtr%s" % [
		prefix,
		str(opp.get("name", "Property")),
		str(opp.get("blurb", "")).substr(0, 80),
		MathUtil.fmt_money(int(opp.get("price", 0))),
		MathUtil.fmt_money(int(opp.get("rent", 0))),
		expiry_tag,
	]
	row.add_child(info)
	var buy := Button.new()
	buy.text = "Buy Now (1 AP)"
	var opp_id: String = str(opp.get("id", ""))
	var price: int = int(opp.get("price", 0))
	buy.disabled = s.action_points < 1 or s.cash < price
	buy.pressed.connect(_on_buy_re_pressed.bind(opp_id))
	row.add_child(buy)
	opportunities_list.add_child(row)


func _on_buy_re_pressed(opportunity_id: String) -> void:
	var result: Dictionary = Game.apply_command(GameCommand.acquire_real_estate(opportunity_id))
	if not bool(result.get("ok", false)):
		debrief_label.text = "Purchase failed: %s" % str(result.get("error", "unknown"))


func _on_sell_pressed(asset_kind: String, asset_id: String) -> void:
	var result: Dictionary = Game.apply_command(GameCommand.sell_asset(asset_kind, asset_id))
	if not bool(result.get("ok", false)):
		debrief_label.text = "Sell failed: %s" % str(result.get("error", "unknown"))
	else:
		debrief_label.text = "Sold for %s." % MathUtil.fmt_money(int(result.get("proceeds", 0)))


func _add_security_opportunity_row(s: RunState, opp: Dictionary) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var info := Label.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var price: int = int(opp.get("price", 0))
	var cost: int = price * SecuritySystem.MIN_SHARE_LOT
	var momentum: String = str(opp.get("momentum", "neutral"))
	var momentum_tag := ""
	match momentum:
		"positive":
			momentum_tag = " · Sector momentum ▲"
		"negative":
			momentum_tag = " · Sector momentum ▼"
	var expiry_tag := " · %d qtr left" % int(opp.get("expiresIn", 0)) if int(opp.get("expiresIn", 0)) > 0 else ""
	info.text = "%s (%s)\nPrice %s/share · Lot %d shares = %s · %s sector%s%s\n%s" % [
		str(opp.get("name", "Security")),
		str(opp.get("ticker", "")),
		MathUtil.fmt_money(price),
		SecuritySystem.MIN_SHARE_LOT,
		MathUtil.fmt_money(cost),
		str(opp.get("sector", "")),
		momentum_tag,
		expiry_tag,
		str(opp.get("blurb", "")),
	]
	row.add_child(info)
	var buy := Button.new()
	buy.text = "Buy 10 shares (1 AP)"
	var opp_id: String = str(opp.get("id", ""))
	buy.disabled = s.action_points < 1 or s.cash < cost
	buy.pressed.connect(_on_buy_security_pressed.bind(opp_id))
	row.add_child(buy)
	opportunities_list.add_child(row)


func _on_buy_security_pressed(opportunity_id: String) -> void:
	var result: Dictionary = Game.apply_command(GameCommand.buy_security(opportunity_id, 10))
	if not bool(result.get("ok", false)):
		debrief_label.text = "Security purchase failed: %s" % str(result.get("error", "unknown"))
	else:
		debrief_label.text = "Bought %d shares of %s." % [int(result.get("shares", 0)), str(result.get("ticker", ""))]


func _on_sell_security_pressed(ticker: String) -> void:
	var result: Dictionary = Game.apply_command(GameCommand.sell_security(ticker))
	if not bool(result.get("ok", false)):
		debrief_label.text = "Sell failed: %s" % str(result.get("error", "unknown"))
	else:
		debrief_label.text = "Sold for %s." % MathUtil.fmt_money(int(result.get("proceeds", 0)))


func _on_supply_chain_pressed() -> void:
	_supply_chain_view.open_view()


func _on_field_guide_pressed() -> void:
	_field_guide.open_guide()


func _add_loan_opportunity_row(s: RunState, opp: Dictionary) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)

	var info := Label.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.text = _LoanSystem.format_opportunity_line(opp)
	row.add_child(info)

	var accept := Button.new()
	accept.text = "Accept (1 AP)"
	var opp_id: String = str(opp.get("id", ""))
	accept.disabled = s.action_points < 1
	accept.pressed.connect(_on_take_loan_pressed.bind(opp_id))
	row.add_child(accept)

	opportunities_list.add_child(row)


func _on_take_loan_pressed(opportunity_id: String) -> void:
	var result: Dictionary = Game.apply_command(GameCommand.take_loan(opportunity_id))
	if not bool(result.get("ok", false)):
		debrief_label.text = "Loan failed: %s" % str(result.get("error", "unknown"))
	else:
		debrief_label.text = "Line of credit accepted — cash increased, debt service starts next quarter."


func _on_payoff_loan_pressed(loan_id: String) -> void:
	var result: Dictionary = Game.apply_command(GameCommand.payoff_loan(loan_id))
	if not bool(result.get("ok", false)):
		debrief_label.text = "Payoff failed: %s" % str(result.get("error", "unknown"))
	else:
		debrief_label.text = "Loan paid off early."


func _populate_supply_chain(s: RunState) -> void:
	for child in supply_chain_list.get_children():
		child.queue_free()

	var shortages: Array = SynergySystem.detect_supply_shortages(s) if s.is_capital_farm() else []
	if not shortages.is_empty() and s.supply_shortage_ack_turn != s.turn:
		var banner := Label.new()
		banner.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		banner.add_theme_color_override("font_color", Color(0.85, 0.55, 0.45))
		var names: PackedStringArray = []
		for sh_variant in shortages:
			if typeof(sh_variant) == TYPE_DICTIONARY:
				names.append(str((sh_variant as Dictionary).get("name", "Supplier")))
		banner.text = "⚠ Supply shortage on %s — set allocation policy before advancing (0 AP)." % ", ".join(names)
		supply_chain_list.add_child(banner)

	if not s.is_capital_farm() or s.portfolio.businesses.is_empty():
		var empty := Label.new()
		empty.text = "Own two linked businesses to see internal supply links."
		supply_chain_list.add_child(empty)
		return

	var synergies: Array = SynergySystem.compute_synergies(s)
	if synergies.is_empty():
		var none := Label.new()
		none.text = "No active internal links yet — acquire suppliers and customers in your chain."
		supply_chain_list.add_child(none)
		return

	for syn_variant in synergies:
		if typeof(syn_variant) != TYPE_DICTIONARY:
			continue
		var syn: Dictionary = syn_variant
		var row := Label.new()
		row.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		var fulfill: float = float(syn.get("fulfillRatio", 1.0))
		var strained: bool = bool(syn.get("capacityStrained", false))
		var status := "OK" if fulfill >= 0.99 and not strained else ("STRAINED" if strained else "PARTIAL")
		row.text = "%s\n  Cost −%.0f%% · Fulfill %.0f%% · %s · Policy: %s" % [
			str(syn.get("label", "")),
			float(syn.get("costReduction", 0.0)) * 100.0,
			fulfill * 100.0,
			status,
			_SupplyPolicy.policy_label(_SupplyPolicy.get_policy(s, str(syn.get("supplierTemplateId", "")))),
		]
		supply_chain_list.add_child(row)


func _on_improve_pressed(business_id: String) -> void:
	_improve_panel.open_for_business(business_id)


func _on_improve_re_pressed(asset_id: String) -> void:
	_re_improve_panel.open_for_asset(asset_id)


func _on_buy_pressed(opportunity_id: String) -> void:
	var result: Dictionary = Game.apply_command(GameCommand.acquire_business(opportunity_id))
	if not bool(result.get("ok", false)):
		debrief_label.text = "Purchase failed: %s" % str(result.get("error", "unknown"))


func _on_negotiate_pressed(opportunity_id: String) -> void:
	_negotiation_panel.open_for_opportunity(opportunity_id)


func _on_investigate_pressed(opportunity_id: String) -> void:
	var result: Dictionary = Game.apply_command(GameCommand.investigate(opportunity_id))
	if not bool(result.get("ok", false)):
		debrief_label.text = "Investigate failed: %s" % str(result.get("error", "unknown"))
	else:
		var opp: Variant = result.get("opportunity")
		if opp is Dictionary and (opp as Dictionary).has("v2Preview"):
			var preview: Dictionary = (opp as Dictionary)["v2Preview"]
			var kw: Array = preview.get("keywords", [])
			var kw_hint := ""
			if kw.size() > 0:
				kw_hint = " Try: \"%s\"." % str(kw[0])
			debrief_label.text = "Diligence complete — %.1f%% opening discount, floor %s, target ~%s.%s" % [
				float(preview.get("openingDiscountPct", 0.0)) * 100.0,
				MathUtil.fmt_money(int(preview.get("hardFloor", 0))),
				MathUtil.fmt_money(int(preview.get("openingAcceptable", 0))),
				kw_hint,
			]
		else:
			debrief_label.text = "Diligence complete — negotiation intel unlocked."


func _on_advance_pressed() -> void:
	var result: Dictionary = Game.apply_command(GameCommand.advance_turn())
	if bool(result.get("requires_supply_policy", false)):
		debrief_label.text = str(result.get("error", "Set allocation policy first."))
		_shortage_modal.open_with_shortages(result.get("shortages", []))
		return
	if not bool(result.get("ok", false)):
		debrief_label.text = "Turn failed: %s" % str(result.get("error", "unknown"))
	elif Game.state != null and Game.state.game_over != null:
		Game.go_to_run_report()


func _on_shortage_confirmed() -> void:
	_refresh()
	var result: Dictionary = Game.apply_command(GameCommand.advance_turn())
	if bool(result.get("requires_supply_policy", false)):
		debrief_label.text = str(result.get("error", "Set allocation policy first."))
		_shortage_modal.open_with_shortages(result.get("shortages", []))
	elif not bool(result.get("ok", false)):
		debrief_label.text = "Turn failed: %s" % str(result.get("error", "unknown"))
	elif Game.state != null and Game.state.game_over != null:
		Game.go_to_run_report()
	else:
		debrief_label.text = "Turn advanced."


func _on_shortage_cancelled() -> void:
	debrief_label.text = "Advance cancelled — resolve supply allocation first."


func _on_save_pressed() -> void:
	if Game.save_to_file():
		debrief_label.text = "Game saved."
	else:
		debrief_label.text = "Save failed."


func _on_menu_pressed() -> void:
	Game.go_to_main_menu()
