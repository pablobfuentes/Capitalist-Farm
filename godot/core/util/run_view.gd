class_name RunView
extends RefCounted

const _LoanSystem := preload("res://core/systems/loan_system.gd")
const _RealEstate := preload("res://core/systems/real_estate_system.gd")
const _SupplyPolicy := preload("res://core/systems/supply_policy_system.gd")
const _Rival := preload("res://core/systems/rival_system.gd")
const _Ownership := preload("res://core/systems/parcel_ownership_system.gd")

const SUPPLY_SEGMENT_COLORS: Array[Color] = [
	Color(0.42, 0.72, 0.52, 1.0),
	Color(0.48, 0.62, 0.88, 1.0),
	Color(0.88, 0.58, 0.38, 1.0),
	Color(0.76, 0.50, 0.78, 1.0),
	Color(0.48, 0.80, 0.78, 1.0),
	Color(0.86, 0.74, 0.38, 1.0),
	Color(0.62, 0.52, 0.86, 1.0),
	Color(0.68, 0.68, 0.68, 1.0),
]
const SUPPLY_SPARE_COLOR := Color(0.26, 0.28, 0.26, 0.55)
const SUPPLY_EXTERNAL_COLOR := Color(0.55, 0.58, 0.62, 0.45)
const DISTRICT_EXTERNAL_LABEL := "Other markets"
## When a supplier has few district clients, reserve capacity for off-district demand.
const DISTRICT_CRUTCH_EXTERNAL: Dictionary = {1: 0.60, 2: 0.35}


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


const UPGRADE_INFO_TOOLTIPS: Dictionary = {
	"hire": (
		"Adds staff and production capacity. Each tier increases capacity by 8%, "
		+ "letting the business serve more volume when demand is available. "
		+ "Higher capacity improves revenue on capacity-bound businesses."
	),
	"marketing": (
		"Invests in promotion and customer reach. Each tier raises the demand multiplier by 8%, "
		+ "driving more revenue—especially for customer-facing businesses. "
		+ "Less effective when upstream supply cannot keep up."
	),
	"automation": (
		"Streamlines operations and cuts waste. Each tier reduces operating costs by about 6% "
		+ "(compounding), showing up as a lower opex multiplier and higher quarterly profit."
	),
	"care": (
		"Strengthens supplier and client relationships. Each tier reduces crisis severity by 20% "
		+ "and immediately improves client and supplier health (+8 each on upgrade). "
		+ "Fewer urgent problems and smoother negotiations over time."
	),
	"manager": (
		"Hires a manager to run day-to-day operations. Adds +1 autopilot (fewer urgent events), "
		+ "boosts all levers by 3%, and grants 2 extra quarters before neglect penalties. "
		+ "The manager also slowly improves hire, marketing, and automation over time. "
		+ "One per business level."
	),
}


static func business_improvements_view(state: RunState, biz: BusinessInstance) -> Dictionary:
	if biz == null or not UpgradeSystem.is_active(state):
		return {"visible": false, "rows": [], "levelUp": {}}
	UpgradeSystem.ensure_business_upgrades(biz)
	var rows: Array = []
	for track_id: String in ["hire", "marketing", "automation", "care", "manager"]:
		rows.append(_improvement_row(state, biz, track_id))
	return {
		"visible": true,
		"rows": rows,
		"levelUp": LevelUpSystem.improve_panel_view(state, biz),
	}


static func _improvement_row(state: RunState, biz: BusinessInstance, track_id: String) -> Dictionary:
	var track: Dictionary = UpgradeSystem.TRACKS.get(track_id, {})
	var category: String = str(track.get("name", track_id))
	var max_tier: int = int(track.get("max_tier", 3))
	var tmpl := Content.get_template(biz.template_id)
	var preview: Dictionary = UpgradeSystem.compute_upgrade_preview(state, biz.id, track_id)
	var cost: int = int(preview.get("cost", 0))
	var can_preview: bool = bool(preview.get("canApply", false))
	var blocked_reason := str(preview.get("reason", "")).strip_edges()

	if track_id == "marketing" and tmpl != null and not tmpl.marketing_eligible:
		return {
			"trackId": track_id,
			"category": category,
			"levelText": "—",
			"statName": "Demand",
			"currentValue": "N/A",
			"improvedValue": "—",
			"profitHint": "",
			"infoTooltip": UPGRADE_INFO_TOOLTIPS.get(track_id, ""),
			"canApply": false,
			"cost": 0,
			"blockedReason": "Infrastructure asset — use Hire or Automation instead.",
			"buttonText": "—",
		}

	if track_id == "manager" and bool(biz.upgrades.get("manager", false)):
		return {
			"trackId": track_id,
			"category": category,
			"levelText": "Hired",
			"statName": "Autopilot",
			"currentValue": UpgradeSystem.autopilot_display(biz),
			"improvedValue": "—",
			"profitHint": "",
			"infoTooltip": UPGRADE_INFO_TOOLTIPS.get(track_id, ""),
			"canApply": false,
			"cost": 0,
			"blockedReason": "Manager already in place this level.",
			"buttonText": "—",
		}

	var tier: int = 0 if track_id == "manager" else int(biz.upgrades.get(track_id, 0))
	var level_text := "—" if track_id == "manager" else "%d / %d" % [tier, max_tier]
	var stat_values := _improvement_stat_values(biz, preview, track_id, can_preview)
	var profit_hint := ""
	if track_id == "automation" and can_preview:
		var delta: int = int(preview.get("profitDelta", 0))
		if delta != 0:
			var sign := "+" if delta >= 0 else ""
			profit_hint = "%s%s/qtr profit" % [sign, MathUtil.fmt_money(delta)]

	var can_apply := can_preview and state.action_points >= 1 and state.cash >= cost
	if can_preview and state.action_points < 1:
		blocked_reason = "Need 1 AP"
	elif can_preview and state.cash < cost:
		blocked_reason = "Insufficient cash"

	return {
		"trackId": track_id,
		"category": category,
		"levelText": level_text,
		"statName": stat_values.get("statName", ""),
		"currentValue": stat_values.get("currentValue", "—"),
		"improvedValue": stat_values.get("improvedValue", "—"),
		"profitHint": profit_hint,
		"infoTooltip": UPGRADE_INFO_TOOLTIPS.get(track_id, ""),
		"canApply": can_apply,
		"cost": cost,
		"blockedReason": blocked_reason,
		"buttonText": "1 AP + %s" % MathUtil.fmt_money(cost) if can_preview else "—",
	}


static func _improvement_stat_values(
	biz: BusinessInstance,
	preview: Dictionary,
	track_id: String,
	can_preview: bool,
) -> Dictionary:
	match track_id:
		"hire":
			var before: Variant = preview.get("capacityBefore")
			if before == null:
				before = UpgradeSystem.capacity_units_for_business(Game.state, biz)
			var current := "—"
			if before != null:
				current = "%d units" % int(before)
			elif biz.upgrade_stats.has("capacityMult"):
				current = "×%.2f" % float(biz.upgrade_stats.get("capacityMult", 1.0))
			var improved := "—"
			if can_preview:
				var after: Variant = preview.get("capacityAfter")
				if after != null:
					improved = "%d units" % int(after)
				else:
					improved = "×%.2f" % (
						float(biz.upgrade_stats.get("capacityMult", 1.0)) + UpgradeSystem.HIRE_PER_TIER
					)
			return {"statName": "Capacity", "currentValue": current, "improvedValue": improved}
		"marketing":
			var current_m := "×%.2f" % float(
				preview.get("demandMultBefore", biz.upgrade_stats.get("demandMult", 1.0))
			)
			var improved_m := "—"
			if can_preview:
				improved_m = "×%.2f" % float(preview.get("demandMultAfter", 1.0))
			return {"statName": "Demand", "currentValue": current_m, "improvedValue": improved_m}
		"automation":
			var current_o := "×%.2f" % float(
				preview.get("opexMultBefore", biz.upgrade_stats.get("opexMult", 1.0))
			)
			var improved_o := "—"
			if can_preview:
				improved_o = "×%.2f" % float(preview.get("opexMultAfter", 1.0))
			return {"statName": "Operating costs", "currentValue": current_o, "improvedValue": improved_o}
		"care":
			var current_c := "×%.2f" % float(
				preview.get("careCrisisMultBefore", biz.upgrade_stats.get("careCrisisMult", 1.0))
			)
			var improved_c := "—"
			if can_preview:
				improved_c = "×%.2f" % float(preview.get("careCrisisMultAfter", 1.0))
			return {"statName": "Crisis impact", "currentValue": current_c, "improvedValue": improved_c}
		"manager":
			var ap_before: int = int(
				preview.get("autopilotBefore", biz.upgrade_stats.get("effectiveAutopilot", 3))
			)
			var current_ap := "★".repeat(ap_before) + "☆".repeat(maxi(0, 5 - ap_before))
			var improved_ap := "—"
			if can_preview:
				var ap_after: int = int(preview.get("autopilotAfter", ap_before))
				improved_ap = "★".repeat(ap_after) + "☆".repeat(maxi(0, 5 - ap_after))
			return {"statName": "Autopilot", "currentValue": current_ap, "improvedValue": improved_ap}
	return {"statName": "", "currentValue": "—", "improvedValue": "—"}


## District supply/demand balance for the parcel business panel.
static func business_supply_balance_view(
	state: RunState,
	biz: BusinessInstance,
	district: Dictionary,
	entry: Dictionary,
) -> Dictionary:
	if state == null or biz == null or not state.is_capital_farm():
		return {"visible": false}

	var district_id := str(district.get("id", ""))
	var graph: Dictionary = SupplyChainGraphService.build_for_district(state, district_id, district)
	var parcel_id := str(entry.get("id", ""))
	var node_id := SupplyChainGraphService.find_node_id_for_parcel(graph, parcel_id)
	if node_id.is_empty():
		node_id = SupplyChainGraphService.find_node_id_for_business(graph, biz.id)

	var synergies: Array = SynergySystem.compute_synergies(state)
	var clients: Array = []
	var suppliers: Array = []
	if not node_id.is_empty():
		clients = _district_client_rows(state, graph, node_id, biz, synergies)
		suppliers = _district_supplier_rows(state, graph, node_id, biz, synergies)

	var capacity_section: Dictionary = {}
	var display_clients: Array = clients
	if SynergySystem.is_allocatable_supplier(biz.template_id):
		capacity_section = _capacity_bar_view(state, biz, clients)
		display_clients = capacity_section.get("displayClients", clients)

	return {
		"visible": not display_clients.is_empty() or not suppliers.is_empty() or not capacity_section.is_empty(),
		"capacity": capacity_section,
		"clients": display_clients,
		"suppliers": suppliers,
	}


static func _capacity_bar_view(state: RunState, biz: BusinessInstance, clients: Array) -> Dictionary:
	var cap_variant: Variant = SynergySystem.effective_capacity(state, biz.template_id)
	if cap_variant == null:
		return {}
	var cap: float = float(cap_variant)
	if cap <= 0.0:
		return {}

	var balanced: Dictionary = _balance_district_client_capacity(clients, cap)
	var display_clients: Array = balanced.get("clients", [])
	var external_frac: float = float(balanced.get("externalFrac", 0.0))
	var external_units: float = float(balanced.get("externalUnits", 0.0))

	var total_allocated: float = 0.0
	for row_variant in display_clients:
		if typeof(row_variant) != TYPE_DICTIONARY:
			continue
		total_allocated += float((row_variant as Dictionary).get("allocatedUnits", 0.0))

	var segments: Array = []
	for row_variant in display_clients:
		if typeof(row_variant) != TYPE_DICTIONARY:
			continue
		var row: Dictionary = row_variant
		var units: float = float(row.get("capacityUnits", 0.0))
		if units <= 0.0:
			continue
		var width_frac: float = units / cap
		if width_frac <= 0.001:
			continue
		segments.append({
			"colorIndex": int(row.get("colorIndex", 0)),
			"color": row.get("color", SUPPLY_SEGMENT_COLORS[0]),
			"label": str(row.get("name", "")),
			"widthFrac": width_frac,
			"units": int(round(units)),
			"style": "client",
		})

	if external_units > 0.5:
		segments.append({
			"colorIndex": -1,
			"color": SUPPLY_EXTERNAL_COLOR,
			"label": DISTRICT_EXTERNAL_LABEL,
			"widthFrac": external_units / cap,
			"units": int(round(external_units)),
			"style": "external",
		})

	var filled_frac: float = 0.0
	for seg_variant in segments:
		filled_frac += float((seg_variant as Dictionary).get("widthFrac", 0.0))
	var spare_frac: float = maxf(0.0, 1.0 - filled_frac)
	if spare_frac > 0.02:
		segments.append({
			"colorIndex": -2,
			"color": SUPPLY_SPARE_COLOR,
			"label": "Spare",
			"widthFrac": spare_frac,
			"units": int(round(cap * spare_frac)),
			"style": "spare",
		})

	var balance_line := ""
	if external_frac > 0.01:
		balance_line = "District clients %d%% · Other markets %d%%" % [
			int(round((1.0 - external_frac) * 100.0)),
			int(round(external_frac * 100.0)),
		]
	elif spare_frac > 0.02:
		balance_line = "%d spare" % int(round(cap * spare_frac))
	else:
		balance_line = "Fully allocated"

	return {
		"capacity": int(round(cap)),
		"totalDemand": int(round(cap - cap * spare_frac)),
		"totalAllocated": int(round(total_allocated)),
		"overCapacity": false,
		"balanceLine": balance_line,
		"segments": segments,
		"displayClients": display_clients,
	}


static func _balance_district_client_capacity(clients: Array, cap: float) -> Dictionary:
	if clients.is_empty() or cap <= 0.0:
		return {"clients": [], "externalFrac": 0.0, "externalUnits": 0.0}

	var client_count := clients.size()
	var external_frac: float = float(DISTRICT_CRUTCH_EXTERNAL.get(client_count, 0.0))
	var district_frac: float = 1.0 - external_frac

	var total_weight: float = 0.0
	for row_variant in clients:
		if typeof(row_variant) != TYPE_DICTIONARY:
			continue
		total_weight += float((row_variant as Dictionary).get("demandWeight", 0.0))

	var balanced: Array = []
	for row_variant in clients:
		if typeof(row_variant) != TYPE_DICTIONARY:
			continue
		var row: Dictionary = (row_variant as Dictionary).duplicate(true)
		var weight: float = float(row.get("demandWeight", 0.0))
		var share: float = (weight / total_weight) if total_weight > 0.0 else (1.0 / float(client_count))
		var units: float = 0.0
		if external_frac > 0.0:
			units = cap * district_frac * share
		elif total_weight > cap:
			units = cap * weight / total_weight
		else:
			units = weight
		row["capacityUnits"] = units
		row["capacityPct"] = int(round(units / cap * 100.0))
		balanced.append(row)

	balanced.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(b.get("capacityPct", 0)) < int(a.get("capacityPct", 0))
	)

	return {
		"clients": balanced,
		"externalFrac": external_frac,
		"externalUnits": cap * external_frac,
	}


static func _district_client_rows(
	state: RunState,
	graph: Dictionary,
	node_id: String,
	biz: BusinessInstance,
	synergies: Array,
) -> Array:
	var rows: Array = []
	var edges: Array = graph.get("edges", [])
	var nodes: Dictionary = graph.get("nodes", {})
	var color_idx := 0

	var edge_rows: Array = []
	for edge_variant in edges:
		if typeof(edge_variant) != TYPE_DICTIONARY:
			continue
		var edge: Dictionary = edge_variant
		if str(edge.get("sourceId", "")) != node_id:
			continue
		var target: Dictionary = nodes.get(str(edge.get("targetId", "")), {})
		if target.is_empty():
			continue
		var conn_id := str(edge.get("catalogId", ""))
		var weight: float = float(SynergySystem.connection_demand_weight(state, conn_id))
		edge_rows.append({"edge": edge, "target": target, "connId": conn_id, "weight": weight})

	if edge_rows.is_empty():
		return rows

	var total_weight: float = 0.0
	for item_variant in edge_rows:
		total_weight += float((item_variant as Dictionary).get("weight", 0.0))

	for item_variant in edge_rows:
		var item: Dictionary = item_variant
		var target: Dictionary = item.get("target", {})
		var conn_id := str(item.get("connId", ""))
		var weight: float = float(item.get("weight", 0.0))
		var edge: Dictionary = item.get("edge", {})
		var owned := bool(target.get("playerOwned", false))
		var customer_id := str(target.get("businessId", ""))
		var name := str(target.get("displayName", ""))
		if name.is_empty():
			var tmpl := Content.get_template(str(target.get("templateId", "")))
			name = tmpl.name if tmpl else str(target.get("templateId", ""))

		var syn: Dictionary = {}
		if owned and not customer_id.is_empty():
			syn = SynergySystem.find_synergy_for_link(synergies, biz.id, customer_id, conn_id)

		var fulfill: float = float(syn.get("fulfillRatio", 0.0)) if not syn.is_empty() else 0.0
		var allocated: float = weight * fulfill if owned and not syn.is_empty() else 0.0

		var color: Color = SUPPLY_SEGMENT_COLORS[color_idx % SUPPLY_SEGMENT_COLORS.size()]
		var row_color_idx := color_idx
		color_idx += 1

		rows.append({
			"colorIndex": row_color_idx,
			"color": color,
			"name": name,
			"flow": str(edge.get("flow", "")),
			"demandWeight": weight,
			"allocatedUnits": allocated,
			"fulfillPct": int(round(fulfill * 100.0)) if owned and not syn.is_empty() else null,
			"playerOwned": owned,
		})

	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(b.get("demandWeight", 0.0)) < float(a.get("demandWeight", 0.0))
	)
	return rows


static func _district_supplier_rows(
	state: RunState,
	graph: Dictionary,
	node_id: String,
	biz: BusinessInstance,
	synergies: Array,
) -> Array:
	var rows: Array = []
	var edges: Array = graph.get("edges", [])
	var nodes: Dictionary = graph.get("nodes", {})
	var color_idx := 0

	var edge_rows: Array = []
	for edge_variant in edges:
		if typeof(edge_variant) != TYPE_DICTIONARY:
			continue
		var edge: Dictionary = edge_variant
		if str(edge.get("targetId", "")) != node_id:
			continue
		var source: Dictionary = nodes.get(str(edge.get("sourceId", "")), {})
		if source.is_empty():
			continue
		var conn_id := str(edge.get("catalogId", ""))
		var weight: float = float(SynergySystem.connection_demand_weight(state, conn_id))
		edge_rows.append({"edge": edge, "source": source, "connId": conn_id, "weight": weight})

	if edge_rows.is_empty():
		return rows

	var total_weight: float = 0.0
	for item_variant in edge_rows:
		total_weight += float((item_variant as Dictionary).get("weight", 0.0))

	for item_variant in edge_rows:
		var item: Dictionary = item_variant
		var source: Dictionary = item.get("source", {})
		var conn_id := str(item.get("connId", ""))
		var weight: float = float(item.get("weight", 0.0))
		var edge: Dictionary = item.get("edge", {})
		var owned := bool(source.get("playerOwned", false))
		var supplier_id := str(source.get("businessId", ""))
		var name := str(source.get("displayName", ""))
		if name.is_empty():
			var tmpl := Content.get_template(str(source.get("templateId", "")))
			name = tmpl.name if tmpl else str(source.get("templateId", ""))

		var syn: Dictionary = {}
		if owned and not supplier_id.is_empty():
			syn = SynergySystem.find_synergy_for_link(synergies, supplier_id, biz.id, conn_id)

		var fulfill: float = float(syn.get("fulfillRatio", 0.0)) if not syn.is_empty() else 0.0
		var share_pct: int = int(round(weight / total_weight * 100.0)) if total_weight > 0.0 else 0

		var color: Color = SUPPLY_EXTERNAL_COLOR if not owned else SUPPLY_SEGMENT_COLORS[color_idx % SUPPLY_SEGMENT_COLORS.size()]
		if owned:
			color_idx += 1

		rows.append({
			"colorIndex": color_idx - 1 if owned else -1,
			"color": color,
			"name": name,
			"flow": str(edge.get("flow", "")),
			"sharePct": share_pct,
			"fulfillPct": int(round(fulfill * 100.0)) if owned and not syn.is_empty() else null,
			"kind": "owned" if owned else "external",
			"leverageLine": _supplier_leverage_line(owned, fulfill, syn),
		})

	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(b.get("sharePct", 0)) < int(a.get("sharePct", 0))
	)
	return rows


static func _client_leverage_line(owned: bool, fulfill: float, syn: Dictionary) -> String:
	if not owned:
		return "External baseline — negotiate to contract"
	if fulfill >= 0.95:
		return "Fully supplied — buyer has leverage"
	if fulfill >= 0.50:
		return "Partial supply — balanced leverage"
	if fulfill > 0.0:
		return "Constrained — you control allocation"
	if syn.is_empty():
		return "Owned — no active link yet"
	return "No supply allocated"


static func _supplier_leverage_line(owned: bool, fulfill: float, syn: Dictionary) -> String:
	if not owned:
		return "External baseline — negotiate terms"
	if fulfill >= 0.95:
		return "Reliable supply — supplier has leverage"
	if fulfill >= 0.50:
		return "Partial fill — moderate dependency"
	if fulfill > 0.0:
		return "Strained supplier — your leverage"
	if syn.is_empty():
		return "Owned — awaiting supply link"
	return "No inbound supply"


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
	lines.append("Autopilot %s" % ap_text)

	if UpgradeSystem.is_active(state):
		var level_line := LevelUpSystem.progress_label(biz)
		if not level_line.is_empty():
			lines.append(level_line)
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


static func portfolio_card_data(state: RunState, biz: BusinessInstance) -> Dictionary:
	if UpgradeSystem.is_active(state):
		UpgradeSystem.ensure_business_upgrades(biz)
	var tmpl := Content.get_template(biz.template_id)
	var layer_text := tmpl.layer_label if tmpl else biz.layer
	var type_label := tmpl.name if tmpl else biz.template_id
	var current_value: int = PortfolioSystem.business_market_value(state, biz)
	var paid: int = biz.purchase_price
	var pct_delta := 0.0
	if paid > 0:
		pct_delta = (float(current_value - paid) / float(paid)) * 100.0
	return {
		"id": biz.id,
		"name": biz.name,
		"typeLabel": type_label,
		"layerLabel": layer_text,
		"level": biz.level,
		"currentValue": current_value,
		"pctDelta": pct_delta,
		"profitPerTurn": biz.revenue_per_turn - biz.operating_costs,
		"revenuePerTurn": biz.revenue_per_turn,
		"costPerTurn": biz.operating_costs,
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
		lines.append("Requirement met — click the district on the map to enter.")
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
	var community_business_id := str(resolved.get("community_business_id", ""))
	var biz := _find_business(state, business_id) if business_id != "" else null

	var details_lines: PackedStringArray = []
	var actions: Dictionary = {}

	if biz != null:
		details_lines = business_parcel_details(state, biz)
		var urgency: Dictionary = RelationshipIssuePressureSystem.pending_problem_for_business(state, business_id)
		if not urgency.is_empty():
			var urgency_lines := urgent_problem_detail_lines(urgency)
			if not urgency_lines.is_empty():
				details_lines = urgency_lines + PackedStringArray([""]) + details_lines
		var sell_proceeds: int = PortfolioSystem.estimate_business_sell_proceeds(state, biz)
		var negotiating: bool = not state.negotiation.is_empty() and bool(state.negotiation.get("active", false))
		actions = {
			"kind": "business",
			"businessId": business_id,
			"canSell": state.action_points >= 1,
			"sellLabel": "Sell · ~%s (1 AP)" % MathUtil.fmt_money(sell_proceeds),
		}
		if biz != null and UpgradeSystem.is_active(state):
			actions["improvements"] = business_improvements_view(state, biz)
		if not urgency.is_empty():
			actions["urgencyProblemId"] = str(urgency.get("id", ""))
			actions["canNegotiateUrgency"] = state.action_points >= 1 and not negotiating
			actions["negotiateUrgencyLabel"] = "Negotiate terms (1 AP)"
			actions["negotiateUrgencyBlockedReason"] = (
				"Negotiation already in progress" if negotiating else "Need 1 AP"
			)
	elif opportunity_id != "":
		var opp: Dictionary = OpportunitySystem.find_opportunity(state, opportunity_id)
		if not opp.is_empty():
			var opp_row: Dictionary = opportunity_row(state, opp)
			details_lines = _opportunity_parcel_details(state, opp, opp_row)
			var price: int = int(opp.get("price", 0))
			actions = {
				"kind": "opportunity",
				"opportunityId": opportunity_id,
				"price": price,
				"canBuy": bool(opp_row.get("canBuy", false)),
				"buyBlockedReason": str(opp_row.get("buyBlockedReason", "")),
				"canInvestigate": bool(opp_row.get("canInvestigate", false)),
				"canNegotiate": bool(opp_row.get("canNegotiate", false)),
				"negotiateLabel": str(opp_row.get("negotiateLabel", "Negotiate (−1 AP)")),
				"buyLabel": str(opp_row.get("buyLabel", "Buy Now (−1 AP)")),
			}
	elif community_business_id != "":
		var community_business: Dictionary = CommunityGenerator.get_business(state, community_business_id)
		if not community_business.is_empty():
			details_lines = _community_parcel_details(state, community_business)
			var chat_gate: Dictionary = CommunityChatRuntime.can_open_chat(state, community_business)
			var npc_id := str(community_business.get("ownerNpcId", ""))
			actions = {
				"kind": "community",
				"communityBusinessId": community_business_id,
				"npcId": npc_id,
				"parcelId": str(entry.get("id", "")),
				"districtId": str(district.get("id", "")),
				"canChat": bool(chat_gate.get("allowed", false)),
				"chatLabel": "Chat (free)",
				"chatDisabledReason": str(chat_gate.get("message", "")),
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
		var urgency_hdr: Dictionary = RelationshipIssuePressureSystem.pending_problem_for_business(state, business_id)
		if not urgency_hdr.is_empty():
			var side := str(urgency_hdr.get("type", ""))
			var side_label := "client" if side == "client" else ("supplier" if side == "supplier" else "relationship")
			role_line = "⚠ Urgent %s issue — negotiate terms" % side_label
	elif community_business_id != "":
		var community_business: Dictionary = CommunityGenerator.get_business(state, community_business_id)
		if not community_business.is_empty():
			title = str(community_business.get("displayName", title))
			var npc: Dictionary = CommunityGenerator.get_npc(
				state,
				str(community_business.get("ownerNpcId", "")),
			)
			var npc_name := str(npc.get("displayName", resolved.get("operator_name", "")))
			role_line = "Community visit · %s" % npc_name if not npc_name.is_empty() else "Community visit"
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
		"supplyBalance": business_supply_balance_view(state, biz, district, entry) if biz != null else {},
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


static func _community_parcel_details(state: RunState, business: Dictionary) -> PackedStringArray:
	var lines: PackedStringArray = []
	var template_id := str(business.get("templateId", ""))
	if not template_id.is_empty():
		var tmpl := Content.get_template(template_id)
		if tmpl != null:
			lines.append("Template: %s" % tmpl.name)
			lines.append("Layer: %s" % tmpl.layer_label)
		else:
			lines.append("Template: %s" % template_id)
	var npc: Dictionary = CommunityGenerator.get_npc(state, str(business.get("ownerNpcId", "")))
	if not npc.is_empty():
		var species := str(npc.get("speciesId", "")).capitalize()
		if not species.is_empty():
			lines.append("Owner: %s (%s)" % [str(npc.get("displayName", "")), species])
	var sale_state := str(business.get("saleState", "not_for_sale"))
	if sale_state == "not_for_sale":
		lines.append("Status: Not for sale — social visit available")
	elif sale_state == "under_negotiation":
		lines.append("Status: In active negotiation")
	elif sale_state == "available":
		lines.append("Status: Listed for acquisition")
	return lines


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


static func urgent_problem_detail_lines(prob: Dictionary) -> PackedStringArray:
	var lines: PackedStringArray = []
	var side := str(prob.get("type", ""))
	var severity := str(prob.get("severity", "concern")).capitalize()
	var side_label := "Client concern" if side == "client" else ("Supplier concern" if side == "supplier" else "Relationship concern")
	lines.append("⚠ %s — %s" % [severity, side_label])
	var cp_biz := str(prob.get("counterpartyBusinessName", "")).strip_edges()
	var flow := str(prob.get("flow", "")).strip_edges()
	if not cp_biz.is_empty():
		lines.append("From: %s%s" % [cp_biz, (" · %s" % flow) if not flow.is_empty() else ""])
	var issue_label := RelationshipIssuePressureSystem.issue_type_label(str(prob.get("issueType", "")))
	if not issue_label.is_empty():
		lines.append("Issue: %s" % issue_label)
	var ask := str(prob.get("askStatement", "")).strip_edges()
	if ask.is_empty():
		var ask_dict: Dictionary = prob.get("ask", {}) if typeof(prob.get("ask", {})) == TYPE_DICTIONARY else {}
		ask = str(ask_dict.get("statement", "")).strip_edges()
	if not ask.is_empty():
		lines.append("Their ask: %s" % ask)
	var reason := str(prob.get("reasonLine", "")).strip_edges()
	if not reason.is_empty():
		lines.append("Why: %s" % reason)
	lines.append(RelationshipIssuePressureSystem.stake_consequence_line(prob))
	return lines


static func urgent_problem_row(state: RunState, prob: Dictionary) -> Dictionary:
	var negotiating: bool = not state.negotiation.is_empty() and bool(state.negotiation.get("active", false))
	var side := str(prob.get("type", ""))
	var side_label := "Client" if side == "client" else ("Supplier" if side == "supplier" else "Relationship")
	var issue_label := RelationshipIssuePressureSystem.issue_type_label(str(prob.get("issueType", "")))
	var stake_line := RelationshipIssuePressureSystem.stake_consequence_line(prob)
	var summary := "%s · %s — %s" % [side_label, issue_label, stake_line]
	return {
		"id": str(prob.get("id", "")),
		"kind": "urgent",
		"summary": summary,
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
	var can_buy := state.action_points >= 1 and not is_contest and state.cash >= price
	var buy_block := ""
	if is_contest:
		buy_block = "Rival contest — negotiate instead"
	elif state.action_points < 1:
		buy_block = "Need 1 AP"
	elif state.cash < price:
		buy_block = "Need %s cash (have %s)" % [MathUtil.fmt_money(price), MathUtil.fmt_money(state.cash)]
	var buy_label := "Buy · %s (−1 AP)" % MathUtil.fmt_money(price) if price > 0 else "Buy Now (−1 AP)"
	if not can_buy and not buy_block.is_empty():
		buy_label = "Buy · %s — %s" % [MathUtil.fmt_money(price), buy_block]
	return {
		"kind": "business_opp",
		"id": str(opp.get("id", "")),
		"summary": summary,
		"detailLine": detail_line,
		"intelLine": intel_line,
		"canBuy": can_buy,
		"buyBlockedReason": buy_block,
		"canInvestigate": state.action_points >= 1 and not bool(opp.get("diligenceDone", false)),
		"canNegotiate": state.action_points >= 1,
		"negotiateLabel": "Contest (−1 AP)" if is_contest else "Negotiate (−1 AP)",
		"buyLabel": buy_label,
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
