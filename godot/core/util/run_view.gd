class_name RunView
extends RefCounted

const _LoanSystem := preload("res://core/systems/loan_system.gd")
const _RealEstate := preload("res://core/systems/real_estate_system.gd")
const _SupplyPolicy := preload("res://core/systems/supply_policy_system.gd")
const _Rival := preload("res://core/systems/rival_system.gd")
const _Ownership := preload("res://core/systems/parcel_ownership_system.gd")


static func header_stats(state: RunState) -> Dictionary:
	return {
		"turn": state.turn,
		"maxTurns": state.max_turns,
		"cash": state.cash,
		"netWorth": FinanceSystem.net_worth(state),
		"debt": _LoanSystem.total_debt(state),
		"actionPoints": state.action_points,
		"maxActionPoints": ActionPointsSystem.max_action_points(state),
		"reputation": state.reputation,
	}


static func business_row(state: RunState, biz: BusinessInstance) -> Dictionary:
	var data: Dictionary = business_display(state, biz)
	return {
		"id": biz.id,
		"kind": "business",
		"summary": str(data.get("summary", "")),
		"canImprove": bool(data.get("canImprove", false)),
		"canSell": state.action_points >= 1,
		"improveLabel": str(data.get("improveLabel", "Improve (1 AP)")),
		"sellLabel": str(data.get("sellLabel", "Sell (1 AP)")),
	}


static func business_value_growth_line(biz: BusinessInstance, current_value: int) -> String:
	var paid: int = biz.purchase_price
	if paid <= 0:
		return ""
	var pct: float = (float(current_value - paid) / float(paid)) * 100.0
	var sign := "+" if pct >= 0 else ""
	return "%s%.0f%% vs purchase" % [sign, pct]


static func business_upgrade_pips_line(biz: BusinessInstance) -> String:
	var lever_bits: Array[String] = []
	for track_id: String in ["hire", "marketing", "automation", "care"]:
		var tier: int = int(biz.upgrades.get(track_id, 0))
		lever_bits.append(
			"%s %s" % [track_id.substr(0, 1).to_upper(), UpgradeSystem.render_tier_pips(tier, 3)]
		)
	return " · ".join(lever_bits)


## Compact body text for the parcel panel (title/role carry name, layer, location).
static func business_parcel_details(state: RunState, biz: BusinessInstance) -> PackedStringArray:
	if UpgradeSystem.is_active(state):
		UpgradeSystem.ensure_portfolio_upgrades(state)

	var lines: PackedStringArray = []
	var current_value: int = PortfolioSystem.business_market_value(state, biz)
	var growth := business_value_growth_line(biz, current_value)
	var val_line := "Val %s" % MathUtil.fmt_money(current_value)
	if not growth.is_empty():
		val_line += " (%s)" % growth
	lines.append(val_line)

	var profit: int = biz.revenue_per_turn - biz.operating_costs
	lines.append(
		"Profit %s/qtr · Rev %s / Cost %s" % [
			MathUtil.fmt_money(profit),
			MathUtil.fmt_money(biz.revenue_per_turn),
			MathUtil.fmt_money(biz.operating_costs),
		]
	)

	var tmpl := Content.get_template(biz.template_id)
	var ap_text := UpgradeSystem.autopilot_display(biz) if UpgradeSystem.is_active(state) else (
		"★".repeat(tmpl.autopilot if tmpl else 3) + "☆".repeat(2)
	)
	lines.append("AP %s" % ap_text)

	if UpgradeSystem.is_active(state):
		var level_line := LevelUpSystem.progress_label(biz)
		if not level_line.is_empty():
			lines.append(level_line)
		var levers := business_upgrade_pips_line(biz)
		if not levers.is_empty():
			lines.append(levers)
	return lines


## Shared business formatting for portfolio rows and other list views.
static func business_display(state: RunState, biz: BusinessInstance) -> Dictionary:
	if UpgradeSystem.is_active(state):
		UpgradeSystem.ensure_portfolio_upgrades(state)

	var tmpl := Content.get_template(biz.template_id)
	var layer_text := tmpl.layer_label if tmpl else biz.layer
	var ap_text := UpgradeSystem.autopilot_display(biz) if UpgradeSystem.is_active(state) else (
		"★".repeat(tmpl.autopilot if tmpl else 3) + "☆".repeat(2)
	)
	var profit: int = biz.revenue_per_turn - biz.operating_costs
	var current_value: int = PortfolioSystem.business_market_value(state, biz)
	var growth := business_value_growth_line(biz, current_value)
	var sell_proceeds: int = PortfolioSystem.estimate_business_sell_proceeds(state, biz)

	var val_part := "Val %s" % MathUtil.fmt_money(current_value)
	if not growth.is_empty():
		val_part += " (%s)" % growth

	var line1 := "%s · Level %d · %s" % [biz.name, biz.level, layer_text]
	var line2 := "%s · Profit %s/qtr · AP %s" % [val_part, MathUtil.fmt_money(profit), ap_text]
	var extra_lines: PackedStringArray = []
	if UpgradeSystem.is_active(state):
		var level_line := LevelUpSystem.progress_label(biz)
		if not level_line.is_empty():
			extra_lines.append(level_line)
		var levers := business_upgrade_pips_line(biz)
		if not levers.is_empty():
			extra_lines.append(levers)

	var summary := line1 + "\n" + line2
	if not extra_lines.is_empty():
		summary += "\n" + "\n".join(extra_lines)

	return {
		"id": biz.id,
		"summary": summary,
		"canImprove": UpgradeSystem.is_active(state),
		"layerLabel": layer_text,
		"templateName": tmpl.name if tmpl else biz.template_id,
		"profitPerTurn": profit,
		"currentValue": current_value,
		"growthLine": growth,
		"sellProceeds": sell_proceeds,
		"improveLabel": "Improve (1 AP)",
		"sellLabel": "Sell · ~%s (1 AP)" % MathUtil.fmt_money(sell_proceeds),
	}


static func parcel_role_label(role: String) -> String:
	match role:
		"core":
			return "Core business · Level 1 pad"
		"specialization":
			return "Specialization duplicate"
		"competitive":
			return "Competitive / rival slot"
		"premium":
			return "Premium opportunity"
		"development":
			return "Vacant · development lot"
		"civic":
			return "Civic / landmark"
		"plaza":
			return "District plaza"
		"bank":
			return "Bank branch · loans & funds"
		_:
			return role.capitalize()


static func ownership_color(owner_state: String) -> Color:
	match owner_state:
		_Ownership.OWNER_PLAYER:
			return Color(0.62, 0.92, 0.68, 1.0)
		_Ownership.OWNER_OPPORTUNITY:
			return Color(0.98, 0.84, 0.42, 1.0)
		_Ownership.OWNER_CONTESTED:
			return Color(0.98, 0.62, 0.48, 1.0)
		_Ownership.OWNER_VACANT:
			return Color(0.78, 0.82, 0.88, 1.0)
		_Ownership.OWNER_CIVIC:
			return Color(0.72, 0.80, 0.98, 1.0)
		_Ownership.OWNER_BANK:
			return Color(0.82, 0.92, 0.62, 1.0)
		_:
			return Color(0.82, 0.78, 0.72, 1.0)


static func locked_district_panel(
	district_name: String,
	requirement: int,
	net_worth: int,
	can_unlock: bool,
) -> Dictionary:
	var lines: PackedStringArray = []
	lines.append("Reach net worth %s to unlock." % MathUtil.fmt_money(requirement))
	lines.append("Your net worth: %s" % MathUtil.fmt_money(net_worth))
	if can_unlock:
		lines.append("Requirement met — district unlocks on next map refresh.")
	else:
		lines.append("Keep growing portfolio value to access this district.")
	return {
		"title": district_name,
		"roleLine": "District locked",
		"details": "\n".join(lines),
		"ownershipLine": "Locked · progress by net worth",
		"ownershipColor": Color(0.78, 0.82, 0.88, 1.0),
		"actions": {},
	}


static func owned_parcel_role_label(biz: BusinessInstance, district: Dictionary, entry: Dictionary) -> String:
	var tmpl := Content.get_template(biz.template_id)
	var layer_text := tmpl.layer_label if tmpl else biz.layer
	if layer_text.is_empty():
		layer_text = biz.template_id
	return "Level %d · %s · %s (%d, %d)" % [
		biz.level,
		layer_text,
		str(district.get("name", "Unknown")),
		int(entry.get("parcel_x", 0)),
		int(entry.get("parcel_y", 0)),
	]


static func opportunity_parcel_role_label(_state: RunState, opp: Dictionary, owner_state: String, district: Dictionary, entry: Dictionary) -> String:
	var tmpl := Content.get_template(str(opp.get("templateId", "")))
	var layer_text := tmpl.layer_label if tmpl else str(opp.get("layer", ""))
	var prefix := "Contested acquisition" if owner_state == _Ownership.OWNER_CONTESTED else "Acquisition opportunity"
	var location := "%s (%d, %d)" % [
		str(district.get("name", "Unknown")),
		int(entry.get("parcel_x", 0)),
		int(entry.get("parcel_y", 0)),
	]
	if layer_text.is_empty():
		return "%s · %s" % [prefix, location]
	return "%s · %s · %s" % [prefix, layer_text, location]


## View model for the 2D parcel business panel.
static func parcel_panel(state: RunState, entry: Dictionary, district: Dictionary) -> Dictionary:
	if typeof(entry) != TYPE_DICTIONARY or entry.is_empty():
		return {}
	if BankSystem.is_bank_parcel(entry):
		return BankSystem.bank_panel(state, entry, district)

	var resolved: Dictionary = _Ownership.resolve(state, entry, district)
	var owner_state := str(resolved.get("state", _Ownership.OWNER_NPC))
	var business_id := str(resolved.get("business_id", ""))
	var opportunity_id := str(resolved.get("opportunity_id", ""))
	var biz := _find_business(state, business_id) if business_id != "" else null

	var details_lines: PackedStringArray = []
	var actions: Dictionary = {}

	if biz != null:
		details_lines = business_parcel_details(state, biz)
		var sell_proceeds: int = PortfolioSystem.estimate_business_sell_proceeds(state, biz)
		actions = {
			"kind": "business",
			"businessId": business_id,
			"canImprove": UpgradeSystem.is_active(state) and state.action_points >= 1,
			"canSell": state.action_points >= 1,
			"improveLabel": "Improve (1 AP)",
			"sellLabel": "Sell · ~%s (1 AP)" % MathUtil.fmt_money(sell_proceeds),
		}
	elif opportunity_id != "":
		var opp: Dictionary = OpportunitySystem.find_opportunity(state, opportunity_id)
		if not opp.is_empty():
			var opp_row: Dictionary = opportunity_row(state, opp)
			details_lines = _opportunity_parcel_details(state, opp, opp_row)
			var price: int = int(opp.get("price", 0))
			actions = {
				"kind": "opportunity",
				"opportunityId": opportunity_id,
				"canBuy": bool(opp_row.get("canBuy", false)),
				"canInvestigate": bool(opp_row.get("canInvestigate", false)),
				"canNegotiate": bool(opp_row.get("canNegotiate", false)),
				"negotiateLabel": str(opp_row.get("negotiateLabel", "Negotiate (1 AP)")),
				"buyLabel": "Buy · %s (1 AP)" % MathUtil.fmt_money(price) if price > 0 else "Buy Now (1 AP)",
			}
	else:
		details_lines.append(
			"%s · Parcel (%d, %d)" % [
				str(district.get("name", "Unknown")),
				int(entry.get("parcel_x", 0)),
				int(entry.get("parcel_y", 0)),
			]
		)
		_append_template_lines(details_lines, entry)

	var ownership_line := ""
	if owner_state != _Ownership.OWNER_PLAYER:
		var ownership_lines: PackedStringArray = []
		ownership_lines.append(
			"%s · %s" % [_Ownership.ownership_label(owner_state), str(resolved.get("headline", ""))]
		)
		if business_id == "" and opportunity_id == "":
			var detail := str(resolved.get("detail", ""))
			if not detail.is_empty():
				ownership_lines.append(detail)
		ownership_line = "\n".join(ownership_lines)

	var title := str(entry.get("label", "Parcel"))
	var role_line := parcel_role_label(str(entry.get("role", "")))
	if biz != null:
		title = biz.name
		role_line = owned_parcel_role_label(biz, district, entry)
	elif opportunity_id != "":
		var opp: Dictionary = OpportunitySystem.find_opportunity(state, opportunity_id)
		if not opp.is_empty():
			title = str(opp.get("name", title))
			role_line = opportunity_parcel_role_label(state, opp, owner_state, district, entry)

	return {
		"title": title,
		"roleLine": role_line,
		"details": "\n".join(details_lines),
		"ownershipLine": ownership_line,
		"ownershipColor": ownership_color(owner_state),
		"ownerState": owner_state,
		"actions": actions,
	}


static func _append_template_lines(lines: PackedStringArray, entry: Dictionary) -> void:
	var template_id := str(entry.get("template_id", ""))
	if template_id.is_empty():
		lines.append("Template: —")
		return
	var tmpl := Content.get_template(template_id)
	if tmpl != null:
		lines.append("Template: %s" % tmpl.name)
		lines.append("Layer: %s" % tmpl.layer_label)
	else:
		lines.append("Template: %s" % template_id)


static func _find_business(state: RunState, business_id: String) -> BusinessInstance:
	if state == null:
		return null
	for biz: BusinessInstance in state.portfolio.businesses:
		if biz.id == business_id:
			return biz
	return null


static func real_estate_row(state: RunState, asset: Dictionary) -> Dictionary:
	var template_id: String = str(asset.get("templateId", asset.get("template_id", "")))
	var tmpl := Content.get_template(template_id)
	var link_count: int = _RealEstate.downstream_link_count(state, template_id)
	var link_line := ""
	if Content.is_infrastructure_template(template_id):
		link_line = " · Serves %d link(s)" % link_count
	var valuation: int = PortfolioSystem.real_estate_market_value(asset)
	var sell_proceeds: int = PortfolioSystem.estimate_real_estate_sell_proceeds(asset)
	var summary := "%s · %s\nRent %s / Opex %s · Val %s%s" % [
		str(asset.get("name", "Property")),
		tmpl.layer_label if tmpl else "Infrastructure",
		MathUtil.fmt_money(int(asset.get("rentPerTurn", asset.get("rent_per_turn", 0)))),
		MathUtil.fmt_money(int(asset.get("operatingExpenses", asset.get("operating_expenses", 0)))),
		MathUtil.fmt_money(valuation),
		link_line,
	]
	return {
		"id": str(asset.get("id", "")),
		"kind": "realestate",
		"summary": summary,
		"canImprove": not _RealEstate.improvements_for_asset(state, asset).is_empty(),
		"canSell": state.action_points >= 1,
		"sellLabel": "Sell · ~%s (1 AP)" % MathUtil.fmt_money(sell_proceeds),
	}


static func security_row(_state: RunState, holding: Dictionary) -> Dictionary:
	return {
		"ticker": str(holding.get("ticker", "")),
		"kind": "security",
		"summary": SecuritySystem.format_holding_summary(holding),
		"canSell": true,
	}


static func loan_row(state: RunState, loan: Dictionary) -> Dictionary:
	return {
		"id": str(loan.get("id", "")),
		"kind": "loan",
		"summary": _LoanSystem.format_portfolio_line(loan),
		"canPayoff": state.cash >= int(loan.get("principal", 0)),
	}


static func urgent_problem_row(state: RunState, prob: Dictionary) -> Dictionary:
	var negotiating: bool = not state.negotiation.is_empty() and bool(state.negotiation.get("active", false))
	return {
		"id": str(prob.get("id", "")),
		"kind": "urgent",
		"summary": str(prob.get("text", "Relationship issue")),
		"canNegotiate": state.action_points >= 1 and not negotiating,
	}


static func opportunity_row(state: RunState, opp: Dictionary) -> Dictionary:
	var asset_type: String = str(opp.get("assetType", ""))
	match asset_type:
		"loan":
			return {
				"kind": "loan_opp",
				"id": str(opp.get("id", "")),
				"summary": _LoanSystem.format_opportunity_line(opp),
				"canAccept": state.action_points >= 1,
			}
		"security":
			return _security_opportunity_row(state, opp)
		"realestate":
			return _real_estate_opportunity_row(state, opp)
		"levelup":
			return _level_up_opportunity_row(state, opp)
		_:
			return _business_opportunity_row(state, opp)


static func supply_chain_view(state: RunState) -> Dictionary:
	var rows: Array = []
	var shortages: Array = SynergySystem.detect_supply_shortages(state) if state.is_capital_farm() else []
	var shortage_banner := ""
	if not shortages.is_empty() and state.supply_shortage_ack_turn != state.turn:
		var names: PackedStringArray = []
		for sh_variant in shortages:
			if typeof(sh_variant) == TYPE_DICTIONARY:
				names.append(str((sh_variant as Dictionary).get("name", "Supplier")))
		shortage_banner = "⚠ Supply shortage on %s — set allocation policy before advancing (0 AP)." % ", ".join(names)

	if not state.is_capital_farm() or state.portfolio.businesses.is_empty():
		return {
			"shortageBanner": shortage_banner,
			"rows": rows,
			"emptyMessage": "Own two linked businesses to see internal supply links.",
		}

	var synergies: Array = SynergySystem.compute_synergies(state)
	if synergies.is_empty():
		return {
			"shortageBanner": shortage_banner,
			"rows": rows,
			"emptyMessage": "No active internal links yet — acquire suppliers and customers in your chain.",
		}

	for syn_variant in synergies:
		if typeof(syn_variant) != TYPE_DICTIONARY:
			continue
		var syn: Dictionary = syn_variant
		var fulfill: float = float(syn.get("fulfillRatio", 1.0))
		var strained: bool = bool(syn.get("capacityStrained", false))
		var status := "OK" if fulfill >= 0.99 and not strained else ("STRAINED" if strained else "PARTIAL")
		rows.append("%s\n  Cost −%.0f%% · Fulfill %.0f%% · %s · Policy: %s" % [
			str(syn.get("label", "")),
			float(syn.get("costReduction", 0.0)) * 100.0,
			fulfill * 100.0,
			status,
			_SupplyPolicy.policy_label(_SupplyPolicy.get_policy(state, str(syn.get("supplierTemplateId", "")))),
		])

	return {"shortageBanner": shortage_banner, "rows": rows, "emptyMessage": ""}


static func debrief_card(state: RunState) -> Dictionary:
	var r: Dictionary = state.last_advance_report
	if r.is_empty():
		return {}
	var nw_delta: int = int(r.get("nwDelta", 0))
	var cash_flow: int = int(r.get("netCashFlow", r.get("profit", 0)))
	var turn_closed: int = int(r.get("turnClosed", maxi(1, state.turn - 1)))
	var ext_line := ""
	var ext_rev: int = int(r.get("externalRevenue", 0))
	if ext_rev > 0:
		ext_line = " · External %s/qtr" % MathUtil.fmt_money(ext_rev)
	return {
		"toggleText": "%s Turn %d — %s cash flow · %s%s NW" % [
			"▼" if state.debrief_expanded else "▶",
			turn_closed,
			MathUtil.fmt_money(cash_flow),
			"+" if nw_delta >= 0 else "",
			MathUtil.fmt_money(nw_delta),
		],
		"detailLine": "Rev %s · Cost %s · Profit %s · Links %s%s" % [
			MathUtil.fmt_money(int(r.get("revenueTotal", 0))),
			MathUtil.fmt_money(int(r.get("costTotal", 0))),
			MathUtil.fmt_money(int(r.get("profit", r.get("profitQuarterClosed", 0)))),
			str(r.get("synergyCount", 0)),
			ext_line,
		],
		"summary": str(r.get("summary", "")),
		"expanded": state.debrief_expanded,
	}


static func _opportunity_parcel_details(_state: RunState, opp: Dictionary, opp_row: Dictionary) -> PackedStringArray:
	var lines: PackedStringArray = []
	var asset_type: String = str(opp.get("assetType", ""))
	match asset_type:
		"realestate":
			var expiry_tag := " · %d qtr left" % int(opp.get("expiresIn", 0)) if int(opp.get("expiresIn", 0)) > 0 else ""
			lines.append(
				"Ask %s · Rent %s/qtr%s" % [
					MathUtil.fmt_money(int(opp.get("price", 0))),
					MathUtil.fmt_money(int(opp.get("rent", 0))),
					expiry_tag,
				]
			)
		"security":
			var price: int = int(opp.get("price", 0))
			var cost: int = price * SecuritySystem.MIN_SHARE_LOT
			var expiry_tag := " · %d qtr left" % int(opp.get("expiresIn", 0)) if int(opp.get("expiresIn", 0)) > 0 else ""
			lines.append(
				"%s/share · Lot %d = %s%s" % [
					MathUtil.fmt_money(price),
					SecuritySystem.MIN_SHARE_LOT,
					MathUtil.fmt_money(cost),
					expiry_tag,
				]
			)
		"levelup":
			var tmpl: Dictionary = opp.get("levelUpTemplate", {})
			var expiry_tag := " · %d qtr left" % int(opp.get("expiresIn", 0)) if int(opp.get("expiresIn", 0)) > 0 else ""
			lines.append(
				"Invest %s · Rev ×%.2f · Cost ×%.2f%s" % [
					MathUtil.fmt_money(int(opp.get("price", 0))),
					float(tmpl.get("revenueMult", 1.0)),
					float(tmpl.get("costMult", 1.0)),
					expiry_tag,
				]
			)
		_:
			lines.append(str(opp_row.get("detailLine", "")))

	var intel_line := str(opp_row.get("intelLine", ""))
	if not intel_line.is_empty():
		var detail_text := str(lines[lines.size() - 1]) if not lines.is_empty() else ""
		if detail_text.is_empty() or not detail_text.contains(intel_line):
			lines.append(intel_line)

	var blurb := str(opp.get("blurb", "")).strip_edges()
	if not blurb.is_empty():
		lines.append(blurb.substr(0, 100))
	return lines


static func _business_opportunity_row(state: RunState, opp: Dictionary) -> Dictionary:
	var tmpl := Content.get_template(str(opp.get("templateId", "")))
	var layer_text := tmpl.layer_label if tmpl else str(opp.get("layer", ""))
	var prefix := ""
	if bool(opp.get("chainHintDeal", false)):
		prefix = "⛓ "
	if bool(opp.get("rivalContest", false)):
		prefix = "⚔ %s contesting · " % _Rival.RIVAL_NAME
	var intel_line := ""
	if bool(opp.get("diligenceDone", false)):
		var preview_raw: Variant = opp.get("v2Preview")
		if preview_raw is Dictionary and not (preview_raw as Dictionary).is_empty():
			var preview: Dictionary = preview_raw as Dictionary
			intel_line = "🔎 %.0f%% disc · floor %s" % [
				float(preview.get("openingDiscountPct", 0.0)) * 100.0,
				MathUtil.fmt_money(int(preview.get("hardFloor", 0))),
			]
		else:
			intel_line = "🔎 Intel ready"
	var expiry_tag := " · %d qtr left" % int(opp.get("expiresIn", 0)) if int(opp.get("expiresIn", 0)) > 0 else ""
	var is_contest: bool = bool(opp.get("rivalContest", false))
	var price: int = int(opp.get("price", 0))
	var profit: int = int(opp.get("revenue", 0)) - int(opp.get("cost", 0))
	var detail_line := "Ask %s · Profit %s/qtr%s" % [
		MathUtil.fmt_money(price),
		MathUtil.fmt_money(profit),
		expiry_tag,
	]
	if not intel_line.is_empty():
		detail_line += " · %s" % intel_line
	var blurb := str(opp.get("blurb", "")).strip_edges()
	var summary := "%s%s · %s\n%s" % [
		prefix,
		str(opp.get("name", "Listing")),
		layer_text,
		detail_line,
	]
	if not blurb.is_empty():
		summary += "\n" + blurb.substr(0, 80)
	return {
		"kind": "business_opp",
		"id": str(opp.get("id", "")),
		"summary": summary,
		"detailLine": detail_line,
		"intelLine": intel_line,
		"canBuy": state.action_points >= 1 and not is_contest and state.cash >= price,
		"canInvestigate": state.action_points >= 1 and not bool(opp.get("diligenceDone", false)),
		"canNegotiate": state.action_points >= 1,
		"negotiateLabel": "Contest (1 AP)" if is_contest else "Negotiate (1 AP)",
		"buyLabel": "Buy · %s (1 AP)" % MathUtil.fmt_money(price) if price > 0 else "Buy Now (1 AP)",
	}


static func _real_estate_opportunity_row(state: RunState, opp: Dictionary) -> Dictionary:
	var prefix := "⛓ " if bool(opp.get("chainHintDeal", false)) else ""
	var expiry_tag := " · %d qtr left" % int(opp.get("expiresIn", 0)) if int(opp.get("expiresIn", 0)) > 0 else ""
	var price: int = int(opp.get("price", 0))
	var detail_line := "Ask %s · Rent %s/qtr%s" % [
		MathUtil.fmt_money(price),
		MathUtil.fmt_money(int(opp.get("rent", 0))),
		expiry_tag,
	]
	var blurb := str(opp.get("blurb", "")).strip_edges()
	var summary := "%s%s · Infrastructure\n%s" % [
		prefix,
		str(opp.get("name", "Property")),
		detail_line,
	]
	if not blurb.is_empty():
		summary += "\n" + blurb.substr(0, 80)
	return {
		"kind": "realestate_opp",
		"id": str(opp.get("id", "")),
		"summary": summary,
		"detailLine": detail_line,
		"canBuy": state.action_points >= 1 and state.cash >= price,
		"buyLabel": "Buy · %s (1 AP)" % MathUtil.fmt_money(price) if price > 0 else "Buy Now (1 AP)",
	}


static func _security_opportunity_row(state: RunState, opp: Dictionary) -> Dictionary:
	var price: int = int(opp.get("price", 0))
	var cost: int = price * SecuritySystem.MIN_SHARE_LOT
	var momentum: String = str(opp.get("momentum", "neutral"))
	var momentum_tag := ""
	match momentum:
		"positive":
			momentum_tag = " · ▲ momentum"
		"negative":
			momentum_tag = " · ▼ momentum"
	var expiry_tag := " · %d qtr left" % int(opp.get("expiresIn", 0)) if int(opp.get("expiresIn", 0)) > 0 else ""
	var detail_line := "%s/share · Lot %d = %s · %s%s" % [
		MathUtil.fmt_money(price),
		SecuritySystem.MIN_SHARE_LOT,
		MathUtil.fmt_money(cost),
		str(opp.get("sector", "")),
		momentum_tag + expiry_tag,
	]
	var blurb := str(opp.get("blurb", "")).strip_edges()
	var summary := "%s (%s)\n%s" % [
		str(opp.get("name", "Security")),
		str(opp.get("ticker", "")),
		detail_line,
	]
	if not blurb.is_empty():
		summary += "\n" + blurb.substr(0, 80)
	return {
		"kind": "security_opp",
		"id": str(opp.get("id", "")),
		"summary": summary,
		"detailLine": detail_line,
		"canBuy": state.action_points >= 1 and state.cash >= cost,
		"buyLabel": "Buy · %s (1 AP)" % MathUtil.fmt_money(cost) if cost > 0 else "Buy 10 shares (1 AP)",
	}


static func _level_up_opportunity_row(state: RunState, opp: Dictionary) -> Dictionary:
	var expiry_tag := " · %d qtr left" % int(opp.get("expiresIn", 0)) if int(opp.get("expiresIn", 0)) > 0 else ""
	var tmpl: Dictionary = opp.get("levelUpTemplate", {})
	var rev_mult: float = float(tmpl.get("revenueMult", 1.0))
	var cost_mult: float = float(tmpl.get("costMult", 1.0))
	var target_level: int = int(opp.get("targetLevel", 0))
	var level_tag := " → L%d" % target_level if target_level > 0 else ""
	var price: int = int(opp.get("price", 0))
	var detail_line := "Invest %s · Rev ×%.2f · Cost ×%.2f%s" % [
		MathUtil.fmt_money(price),
		rev_mult,
		cost_mult,
		expiry_tag,
	]
	var blurb := str(opp.get("blurb", "")).strip_edges()
	var summary := "⬆ %s%s\n%s" % [
		str(opp.get("name", "Level up")),
		level_tag,
		detail_line,
	]
	if not blurb.is_empty():
		summary += "\n" + blurb.substr(0, 80)
	return {
		"kind": "levelup_opp",
		"id": str(opp.get("id", "")),
		"summary": summary,
		"detailLine": detail_line,
		"requiresNegotiation": bool(opp.get("requiresNegotiation", false)),
		"canInvest": state.action_points >= 1 and state.cash >= price,
		"canNegotiate": state.action_points >= 1,
		"price": price,
	}
