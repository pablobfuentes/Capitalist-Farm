class_name TurnResolver
extends RefCounted

const _UpgradeSystem := preload("res://core/systems/upgrade_system.gd")
const _LoanSystem := preload("res://core/systems/loan_system.gd")
const _Rules := preload("res://core/systems/run_rules_system.gd")
const _Market := preload("res://core/systems/market_system.gd")
const _Progression := preload("res://core/systems/progression_system.gd")
const _RunStats := preload("res://core/systems/run_stats_system.gd")
const _Debrief := preload("res://core/systems/debrief_system.gd")
const _Security := preload("res://core/systems/security_system.gd")


func advance_turn(state: RunState) -> RunState:
	var next: RunState = RunState.from_dict(state.to_dict())
	var prev_snap: Array = next.synergy_snapshot.duplicate(true)

	var before_snap: Dictionary
	if next.period_snapshot.is_empty():
		before_snap = _Debrief.snapshot_period_state(next)
	else:
		before_snap = next.period_snapshot.duplicate(true)

	var market_event: Dictionary = {}
	if next.is_capital_farm():
		market_event = _Market.maybe_trigger_market_event(next)
		if not market_event.is_empty():
			next.run_log.append("Market event — %s: %s" % [
				str(market_event.get("label", "")),
				str(market_event.get("note", "")),
			])
			_RunStats.track_shock(next, market_event, 2.5 if int(market_event.get("affectedCount", 0)) > 0 else 1.0)
		var season: Dictionary = _Market.farm_season(next)
		if not season.is_empty():
			next.run_log.append("Season — %s: %s" % [str(season.get("label", "")), str(season.get("note", ""))])

	var rates: Dictionary = FinanceSystem.compute_quarterly_run_rates(next, true)
	var profit: int = int(rates.get("profit", 0))
	next.cash += profit
	_LoanSystem.amortize_loans(next)

	var reval_notes: Dictionary = {}
	var alerts: Array = []
	var active_shortages: Array = []
	var external_rev: int = 0
	var sec_value_before: int = _Security.securities_market_value(next)

	if next.is_capital_farm():
		_Market.resolve_market_update(next)
		reval_notes = ValuationSystem.revalue_assets(next)
		for note: String in SynergySystem.apply_over_capacity_penalties(next):
			next.run_log.append("⚠ %s" % note)
		var curr_snap: Array = SynergySystem.capture_synergy_state(next)
		alerts = SynergySystem.strain_alerts(prev_snap, curr_snap)
		for alert_variant in alerts:
			if typeof(alert_variant) != TYPE_DICTIONARY:
				continue
			var alert: Dictionary = alert_variant
			next.run_log.append("⚠ Capacity strain: %s — infrastructure stretched across too many links" % str(alert.get("label", "")))
		next.synergy_snapshot = curr_snap
		var risk: Dictionary = SynergySystem.portfolio_risk_summary(next, rates.get("synergies", []))
		external_rev = int(risk.get("externalRevenueTotal", rates.get("externalRevenueTotal", 0)))
		active_shortages = SynergySystem.detect_supply_shortages(next)

	var sec_value_after: int = _Security.securities_market_value(next)

	var after_snap: Dictionary = _Debrief.snapshot_period_state(next)
	next.period_snapshot = after_snap.duplicate(true)

	var cash_flow: Dictionary = {
		"netCashFlow": profit,
		"revenueTotal": rates.get("revenueTotal", 0),
		"costTotal": rates.get("costTotal", 0),
		"debtService": rates.get("debtService", 0),
	}

	var debrief_opts: Dictionary = {
		"beforeSnap": before_snap,
		"afterSnap": after_snap,
		"revalNotes": reval_notes,
		"strainAlerts": alerts,
		"marketEvent": market_event,
		"shortages": active_shortages,
		"externalRevenue": external_rev,
		"securitiesValueBefore": sec_value_before,
		"securitiesValueAfter": sec_value_after,
	}
	var debrief: Dictionary = _Debrief.build_turn_debrief(next, cash_flow, debrief_opts)
	next.last_advance_report = debrief
	next.pending_turn_debrief = debrief.duplicate(true)

	_Rules.apply_post_cash_flow_checks(next)
	if next.game_over != null:
		next.pending_turn_debrief = {}
		return next

	if next.is_capital_farm():
		var milestone: Dictionary = _Progression.check_milestone(next)
		if not milestone.is_empty():
			next.run_log.append("Milestone reached: %s. %s" % [
				str(milestone.get("name", "")),
				str(milestone.get("pressure", "")),
			])
			var rng := SeededRng.new()
			next.edge_choices_pending = _Progression.pick_milestone_edge_choices(next, rng)

	_Rules.apply_turn_increment(next)
	if CommunityFeatureFlags.is_enabled(CommunityFeatureFlags.FLAG_COMMUNITY_GENERATION, next):
		CommunitySocialRules.apply_turn_decay(next)
		CommunityRenegotiationService.process_turn(next)
		if CommunityFeatureFlags.is_enabled(CommunityFeatureFlags.FLAG_RUMOR_PROPAGATION, next):
			CommunityRumorService.process_turn(next)
		if CommunityFeatureFlags.is_enabled(CommunityFeatureFlags.FLAG_PROMISE_FULFILLMENT, next):
			CommunityPromiseService.process_turn(next)
	_Rules.apply_end_of_turn_victory_checks(next)
	if next.game_over != null:
		next.pending_turn_debrief = {}
	return next
