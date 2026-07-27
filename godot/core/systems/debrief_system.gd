class_name DebriefSystem
extends RefCounted

const _LoanSystem := preload("res://core/systems/loan_system.gd")


static func snapshot_period_state(state: RunState) -> Dictionary:
	var run: Dictionary = FinanceSystem.compute_quarterly_run_rates(state, false)
	var cost_total: int = int(run.get("costTotal", 0))
	var debt_service: int = int(run.get("debtService", 0))
	return {
		"turn": state.turn,
		"cash": state.cash,
		"netWorth": FinanceSystem.net_worth(state),
		"debt": _LoanSystem.total_debt(state),
		"revenue": int(run.get("revenueTotal", 0)),
		"costs": cost_total,
		"debtService": debt_service,
		"costsPlusDebt": cost_total + debt_service,
		"profit": int(run.get("profit", 0)),
	}


static func build_supply_chain_debrief_line(state: RunState, opts: Dictionary) -> String:
	if not state.is_capital_farm():
		return ""
	var parts: PackedStringArray = []
	var strain_alerts: Array = opts.get("strainAlerts", [])
	if not strain_alerts.is_empty():
		var labels: PackedStringArray = []
		for alert_variant in strain_alerts:
			if typeof(alert_variant) == TYPE_DICTIONARY:
				labels.append(str((alert_variant as Dictionary).get("label", "")))
		if not labels.is_empty():
			parts.append("Strained links: %s" % ", ".join(labels))
	var shortages: Array = opts.get("shortages", [])
	if not shortages.is_empty():
		var names: PackedStringArray = []
		for shortage_variant in shortages:
			if typeof(shortage_variant) == TYPE_DICTIONARY:
				names.append(str((shortage_variant as Dictionary).get("name", "")))
		if not names.is_empty():
			parts.append("Over capacity: %s — allocation policy in effect" % ", ".join(names))
	var stats: Dictionary = state.run_stats if typeof(state.run_stats) == TYPE_DICTIONARY else {}
	var policy_change: Variant = stats.get("lastPolicyChange", stats.get("last_policy_change"))
	if typeof(policy_change) == TYPE_DICTIONARY:
		var pc: Dictionary = policy_change
		if int(pc.get("turn", -1)) == state.turn:
			parts.append("Policy: %s → %s" % [str(pc.get("asset", "")), str(pc.get("label", ""))])
	if shortages.is_empty():
		var hot: PackedStringArray = []
		for util_variant in SynergySystem.compute_supplier_utilization(state).values():
			if typeof(util_variant) != TYPE_DICTIONARY:
				continue
			var util: Dictionary = util_variant
			var pct: int = int(util.get("utilizationPct", 0))
			if pct >= 85 and not bool(util.get("overCapacity", false)):
				hot.append("%s %d%%" % [str(util.get("name", "")), pct])
		if not hot.is_empty():
			parts.append("Running hot: %s" % ", ".join(hot))
	return " · ".join(parts)


static func build_turn_debrief(state: RunState, cash_flow: Dictionary, opts: Dictionary = {}) -> Dictionary:
	var before: Dictionary = opts.get("beforeSnap", snapshot_period_state(state))
	var after: Dictionary = opts.get("afterSnap", snapshot_period_state(state))
	if typeof(before) != TYPE_DICTIONARY:
		before = snapshot_period_state(state)
	if typeof(after) != TYPE_DICTIONARY:
		after = snapshot_period_state(state)

	var cash_before: int = int(before.get("cash", 0))
	var cash_after: int = int(after.get("cash", 0))
	var nw_before: int = int(before.get("netWorth", 0))
	var nw_after: int = int(after.get("netWorth", 0))
	var debt_before: int = int(before.get("debt", 0))
	var debt_after: int = int(after.get("debt", 0))
	var revenue_before: int = int(before.get("revenue", 0))
	var revenue_after: int = int(after.get("revenue", 0))
	var costs_debt_before: int = int(before.get("costsPlusDebt", 0))
	var costs_debt_after: int = int(after.get("costsPlusDebt", 0))
	var profit_run_before: int = int(before.get("profit", 0))
	var profit_run_after: int = int(after.get("profit", 0))
	var net_cash_flow: int = int(cash_flow.get("netCashFlow", 0))

	var highlights: Array = []
	var reval_notes: Dictionary = opts.get("revalNotes", {})
	if typeof(reval_notes) == TYPE_DICTIONARY:
		var reval_count: int = int(reval_notes.get("count", 0))
		if reval_count > 0:
			highlights.append("Rent up 3%% on %d propert%s" % [
				reval_count,
				"y" if reval_count == 1 else "ies",
			])
			var avg_app: float = float(reval_notes.get("avgAppreciation", 0.0))
			if avg_app > 0.0:
				highlights.append("Property values +%s avg" % MathUtil.fmt_pct(avg_app))

	var syn_count: int = SynergySystem.compute_synergies(state).size()
	if syn_count > 0:
		highlights.append("%d active chain link%s" % [syn_count, "" if syn_count == 1 else "s"])

	var strain_alerts: Array = opts.get("strainAlerts", [])
	if not strain_alerts.is_empty():
		highlights.append("%d link%s under capacity strain" % [
			strain_alerts.size(),
			"" if strain_alerts.size() == 1 else "s",
		])

	var shortages: Array = opts.get("shortages", [])
	if not shortages.is_empty():
		var names: PackedStringArray = []
		for shortage_variant in shortages:
			if typeof(shortage_variant) == TYPE_DICTIONARY:
				names.append(str((shortage_variant as Dictionary).get("name", "")))
		if not names.is_empty():
			highlights.append("Supply shortage: %s — review allocation policy" % ", ".join(names))

	var external_revenue: int = int(opts.get("externalRevenue", 0))
	if external_revenue > 0:
		highlights.append("External/export contracts: %s/qtr from spare capacity" % MathUtil.fmt_money(external_revenue))

	var market_event: Dictionary = opts.get("marketEvent", {})
	if typeof(market_event) == TYPE_DICTIONARY and not market_event.is_empty():
		highlights.append("Market: %s" % str(market_event.get("label", "")))

	var sec_before: int = int(opts.get("securitiesValueBefore", 0))
	var sec_after: int = int(opts.get("securitiesValueAfter", 0))
	var sec_delta: int = sec_after - sec_before
	if sec_before > 0 or sec_after > 0:
		if absi(sec_delta) >= 200:
			var sign := "+" if sec_delta >= 0 else ""
			highlights.append("Securities mark-to-market: %s%s this quarter" % [sign, MathUtil.fmt_money(sec_delta)])

	var debt_service: int = int(cash_flow.get("debtService", 0))
	if debt_service > 0:
		var loan_count: int = state.loans.size()
		highlights.append(
			"Debt service: %s/qtr across %d loan%s" % [
				MathUtil.fmt_money(debt_service),
				loan_count,
				"" if loan_count == 1 else "s",
			]
		)

	for loan_variant in LoanSystem.loans_taken_this_turn(state):
		if typeof(loan_variant) != TYPE_DICTIONARY:
			continue
		var loan: Dictionary = loan_variant
		highlights.append(
			"New credit line: %s — %s at %s/qtr, %s/qtr for %d quarters (%s total)" % [
				str(loan.get("label", "Bank line")),
				MathUtil.fmt_money(int(loan.get("principal", 0))),
				MathUtil.fmt_pct(float(loan.get("rate", 0.0))),
				MathUtil.fmt_money(int(loan.get("paymentPerTurn", 0))),
				int(loan.get("turnsRemaining", 0)),
				MathUtil.fmt_money(int(loan.get("paymentPerTurn", 0)) * int(loan.get("turnsRemaining", 0))),
			]
		)

	var supply_chain_line: String = build_supply_chain_debrief_line(state, opts)
	var summary: String
	if net_cash_flow >= 0:
		summary = "This quarter added %s to cash after operations and debt service." % MathUtil.fmt_money(net_cash_flow)
	else:
		summary = "This quarter drained %s from cash — watch liquidity." % MathUtil.fmt_money(absi(net_cash_flow))

	if profit_run_after > profit_run_before + 100:
		summary += " Ongoing run-rate profit rose from %s to %s/qtr." % [
			MathUtil.fmt_money(profit_run_before),
			MathUtil.fmt_money(profit_run_after),
		]
	elif profit_run_after < profit_run_before - 100:
		summary += " Ongoing run-rate profit fell from %s to %s/qtr — debt or costs may be catching up." % [
			MathUtil.fmt_money(profit_run_before),
			MathUtil.fmt_money(profit_run_after),
		]

	var nw_delta: int = nw_after - nw_before
	if nw_delta > 500:
		summary = "Net worth grew %s this turn. %s" % [MathUtil.fmt_money(nw_delta), summary]
	elif nw_delta < -500:
		summary = "Net worth fell %s this turn. %s" % [MathUtil.fmt_money(absi(nw_delta)), summary]
	if not supply_chain_line.is_empty():
		summary += " %s." % supply_chain_line

	return {
		"turnClosed": state.turn,
		"netCashFlow": net_cash_flow,
		"profitQuarterClosed": net_cash_flow,
		"revenueTotal": int(cash_flow.get("revenueTotal", 0)),
		"costTotal": int(cash_flow.get("costTotal", 0)),
		"debtService": int(cash_flow.get("debtService", 0)),
		"profit": net_cash_flow,
		"synergyCount": syn_count,
		"externalRevenue": external_revenue,
		"revenueBefore": revenue_before,
		"revenueAfter": revenue_after,
		"revenueDelta": revenue_after - revenue_before,
		"costsDebtBefore": costs_debt_before,
		"costsDebtAfter": costs_debt_after,
		"costsDebtDelta": costs_debt_after - costs_debt_before,
		"profitRunBefore": profit_run_before,
		"profitRunAfter": profit_run_after,
		"profitRunDelta": profit_run_after - profit_run_before,
		"nwBefore": nw_before,
		"nwAfter": nw_after,
		"nwDelta": nw_delta,
		"cashBefore": cash_before,
		"cashAfter": cash_after,
		"cashDelta": cash_after - cash_before,
		"debtBefore": debt_before,
		"debtAfter": debt_after,
		"debtDelta": debt_after - debt_before,
		"highlights": highlights,
		"summary": summary,
		"supplyChainLine": supply_chain_line,
		"marketEvent": market_event if typeof(market_event) == TYPE_DICTIONARY else {},
		"strainAlertCount": strain_alerts.size(),
		"revalCount": int(reval_notes.get("count", 0)) if typeof(reval_notes) == TYPE_DICTIONARY else 0,
	}


static func delta_class(delta: int, invert: bool = false) -> String:
	if absi(delta) < 1:
		return "neutral"
	var good: bool = delta < 0 if invert else delta > 0
	return "up" if good else "down"


static func delta_text(delta: int) -> String:
	if absi(delta) < 1:
		return "—"
	return "%s%s" % ["+" if delta >= 0 else "", MathUtil.fmt_money(delta)]
