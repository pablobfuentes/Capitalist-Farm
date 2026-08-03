class_name RunStatsSystem
extends RefCounted


static func ensure(state: RunState) -> Dictionary:
	if typeof(state.run_stats) != TYPE_DICTIONARY:
		state.run_stats = _default_stats()
		return state.run_stats
	var defaults := _default_stats()
	for key in defaults.keys():
		if not state.run_stats.has(key):
			state.run_stats[key] = defaults[key]
	return state.run_stats


static func snapshot_turn(state: RunState, rates: Dictionary) -> void:
	ensure(state)
	var debt := 0
	for loan_variant in state.loans:
		if typeof(loan_variant) == TYPE_DICTIONARY:
			debt += int((loan_variant as Dictionary).get("principal", 0))
	var revenue: int = int(rates.get("revenueTotal", 0))
	var costs: int = int(rates.get("costTotal", 0))
	var debt_service: int = int(rates.get("debtService", 0))
	var profit: int = int(rates.get("profit", revenue - costs - debt_service))
	state.turn_history.append({
		"turn": state.turn,
		"cash": state.cash,
		"netWorth": FinanceSystem.net_worth(state),
		"debt": debt,
		"revenue": revenue,
		"costs": costs,
		"profit": profit,
	})
	if state.turn_history.size() > 40:
		state.turn_history = state.turn_history.slice(state.turn_history.size() - 40)


static func record_baseline(state: RunState) -> void:
	if not state.turn_history.is_empty():
		return
	var debt := 0
	for loan_variant in state.loans:
		if typeof(loan_variant) == TYPE_DICTIONARY:
			debt += int((loan_variant as Dictionary).get("principal", 0))
	state.turn_history.append({
		"turn": 0,
		"cash": state.cash,
		"netWorth": FinanceSystem.net_worth(state),
		"debt": debt,
		"revenue": 0,
		"costs": 0,
		"profit": 0,
	})


static func track_shock(state: RunState, event: Dictionary, severity: float = 1.0) -> void:
	if event.is_empty():
		return
	var stats: Dictionary = ensure(state)
	var shocks: Array = stats.get("shocks", [])
	shocks.append({
		"turn": state.turn,
		"label": str(event.get("label", "")),
		"note": str(event.get("note", "")),
		"severity": severity,
	})
	stats["shocks"] = shocks


static func track_deal(state: RunState, name: String, quality: int, savings: int, kind: String) -> void:
	var stats: Dictionary = ensure(state)
	var deals: Array = stats.get("deals", [])
	deals.append({
		"turn": state.turn,
		"name": name,
		"quality": quality,
		"savings": savings,
		"kind": kind,
	})
	stats["deals"] = deals


## Record a closed acquisition for mastery juice. Returns first-of-type / combo flags.
static func note_acquisition(state: RunState, template_id: String, name: String = "", quality: int = 0, savings: int = 0, kind: String = "acquisition") -> Dictionary:
	var stats: Dictionary = ensure(state)
	track_deal(state, name if not name.is_empty() else template_id, quality, savings, kind)
	var deals_closed := int(stats.get("dealsClosedCount", 0)) + 1
	stats["dealsClosedCount"] = deals_closed
	var templates: Dictionary = stats.get("templatesAcquired", {})
	if typeof(templates) != TYPE_DICTIONARY:
		templates = {}
	var tid := template_id.strip_edges()
	var first_of_type := false
	if not tid.is_empty() and not bool(templates.get(tid, false)):
		templates[tid] = true
		stats["templatesAcquired"] = templates
		first_of_type = true
	else:
		stats["templatesAcquired"] = templates
	return {
		"dealsClosedCount": deals_closed,
		"firstOfType": first_of_type,
		"combo": deals_closed,
		"templateId": tid,
	}


## Update profitable-turn streak from quarter-closed profit. Returns current streak (0 if reset).
static func note_profit_quarter(state: RunState, profit: int) -> int:
	var stats: Dictionary = ensure(state)
	var streak := int(stats.get("profitStreak", 0))
	if profit > 0:
		streak += 1
	else:
		streak = 0
	stats["profitStreak"] = streak
	return streak


## One-shot Trusted seal when score first reaches threshold. Returns true if seal should play.
static func try_trusted_seal(state: RunState, npc_id: String, score: int, threshold: int = 4) -> bool:
	if npc_id.is_empty() or score < threshold:
		return false
	var stats: Dictionary = ensure(state)
	var seals: Dictionary = stats.get("trustedSeals", {})
	if typeof(seals) != TYPE_DICTIONARY:
		seals = {}
	if bool(seals.get(npc_id, false)):
		return false
	seals[npc_id] = true
	stats["trustedSeals"] = seals
	return true


static func build_report_extras(state: RunState) -> Dictionary:
	var stats: Dictionary = ensure(state)
	var deals: Array = stats.get("deals", [])
	var shocks: Array = stats.get("shocks", [])
	var best_deal: Dictionary = {}
	var worst_shock: Dictionary = {}
	for deal_variant in deals:
		if typeof(deal_variant) != TYPE_DICTIONARY:
			continue
		var deal: Dictionary = deal_variant
		if best_deal.is_empty() or int(deal.get("quality", 0)) > int(best_deal.get("quality", 0)):
			best_deal = deal
	for shock_variant in shocks:
		if typeof(shock_variant) != TYPE_DICTIONARY:
			continue
		var shock: Dictionary = shock_variant
		if worst_shock.is_empty() or float(shock.get("severity", 0)) > float(worst_shock.get("severity", 0)):
			worst_shock = shock
	var dominant: String = "Diversified portfolio"
	if state.is_capital_farm() and not state.portfolio.businesses.is_empty():
		var synergies: Array = SynergySystem.compute_synergies(state)
		if not synergies.is_empty():
			var best_syn: Dictionary = synergies[0]
			for syn_variant in synergies:
				if typeof(syn_variant) == TYPE_DICTIONARY:
					var syn: Dictionary = syn_variant
					if int(syn.get("estimatedCostSaving", 0)) > int(best_syn.get("estimatedCostSaving", 0)):
						best_syn = syn
			dominant = str(best_syn.get("label", dominant))
	var chain_stats: Dictionary = {}
	if state.is_capital_farm():
		var risk: Dictionary = SynergySystem.portfolio_risk_summary(state)
		chain_stats = {
			"externalRevenueTotal": int(risk.get("externalRevenueTotal", 0)),
			"activeLinks": SynergySystem.compute_synergies(state).size(),
		}
	return {
		"dominant": dominant,
		"bestDeal": best_deal,
		"worstShock": worst_shock,
		"wildcard": stats.get("wildcard", null),
		"chainStats": chain_stats if not chain_stats.is_empty() else null,
		"deals": deals,
		"shocks": shocks,
	}


static func export_json(state: RunState) -> String:
	var payload: Dictionary = {
		"mode": state.mode,
		"turn": state.turn,
		"maxTurns": state.max_turns,
		"netWorth": FinanceSystem.net_worth(state),
		"cash": state.cash,
		"reputation": state.reputation,
		"gameOver": state.game_over,
		"strategicEdges": state.strategic_edges,
		"turnHistory": state.turn_history,
		"runStats": ensure(state),
		"portfolio": state.portfolio.to_dict(),
	}
	return JSON.stringify(payload, "\t")


static func _default_stats() -> Dictionary:
	return {
		"deals": [],
		"shocks": [],
		"policyChanges": [],
		"utilizationSamples": [],
		"dealsClosedCount": 0,
		"templatesAcquired": {},
		"profitStreak": 0,
		"trustedSeals": {},
		"supplyChainCompleteAck": {},
	}
