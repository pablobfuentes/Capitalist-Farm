class_name CommandProcessor
extends RefCounted

const _UpgradeSystem := preload("res://core/systems/upgrade_system.gd")
const _NegotiationSystem := preload("res://core/systems/negotiation_system.gd")
const _Rival := preload("res://core/systems/rival_system.gd")
const _Diligence := preload("res://core/systems/diligence_system.gd")
const _SupplyPolicy := preload("res://core/systems/supply_policy_system.gd")
const _LoanSystem := preload("res://core/systems/loan_system.gd")
const _Urgent := preload("res://core/systems/urgent_system.gd")
const _LevelUp := preload("res://core/systems/level_up_system.gd")
const _Progression := preload("res://core/systems/progression_system.gd")
const _Market := preload("res://core/systems/market_system.gd")
const _Security := preload("res://core/systems/security_system.gd")
const _RunStats := preload("res://core/systems/run_stats_system.gd")
const _RealEstate := preload("res://core/systems/real_estate_system.gd")

static func apply(state: RunState, command: Dictionary) -> Dictionary:
	var command_type: String = str(command.get("type", ""))
	match command_type:
		GameCommand.ADVANCE_TURN:
			return _advance_turn(state)
		GameCommand.ACQUIRE_BUSINESS:
			return _acquire_business(state, command)
		GameCommand.SET_SUPPLY_POLICY:
			return _set_supply_policy(state, command)
		GameCommand.APPLY_UPGRADE:
			return _apply_upgrade(state, command)
		GameCommand.START_NEGOTIATION:
			return _NegotiationSystem.start_negotiation(state, str(command.get("opportunity_id", "")))
		GameCommand.APPEND_NEGOTIATION_PLAYER:
			return _NegotiationSystem.append_player_message(state, str(command.get("message", "")))
		GameCommand.SEND_NEGOTIATION_MESSAGE:
			var ai_parsed: Dictionary = command.get("ai_parsed", {})
			if typeof(ai_parsed) != TYPE_DICTIONARY:
				ai_parsed = {}
			return _NegotiationSystem.send_message(
				state,
				str(command.get("message", "")),
				ai_parsed,
				bool(command.get("skip_player_append", false)),
			)
		GameCommand.END_NEGOTIATION:
			return _NegotiationSystem.end_negotiation(state, bool(command.get("walked", true)))
		GameCommand.CLOSE_NEGOTIATION_DEAL:
			return _NegotiationSystem.close_deal(state)
		GameCommand.INVESTIGATE:
			return _Diligence.investigate_opportunity(state, str(command.get("opportunity_id", "")))
		GameCommand.CONFIRM_SUPPLY_SHORTAGE:
			return _confirm_supply_shortage(state)
		GameCommand.TAKE_LOAN:
			return _LoanSystem.take_loan(state, str(command.get("opportunity_id", "")))
		GameCommand.PAYOFF_LOAN:
			return _LoanSystem.payoff_loan(state, str(command.get("loan_id", "")))
		GameCommand.ACQUIRE_REAL_ESTATE:
			return _acquire_real_estate(state, command)
		GameCommand.SELL_ASSET:
			return PortfolioSystem.sell_asset(state, str(command.get("asset_kind", "")), str(command.get("asset_id", "")))
		GameCommand.DO_LEVEL_UP:
			return _LevelUp.do_level_up(state, str(command.get("opportunity_id", "")))
		GameCommand.CHOOSE_EDGE:
			return _Progression.choose_edge(state, str(command.get("edge_id", "")))
		GameCommand.SKIP_EDGE:
			return _Progression.skip_edge_choice(state)
		GameCommand.START_URGENT_NEGOTIATION:
			return _Urgent.start_urgent_negotiation(state, str(command.get("problem_id", "")))
		GameCommand.BUY_SECURITY:
			return _Security.buy_security(state, str(command.get("opportunity_id", "")), int(command.get("quantity", 10)))
		GameCommand.SELL_SECURITY:
			return _Security.sell_security(state, str(command.get("ticker", "")))
		GameCommand.DISMISS_TURN_DEBRIEF:
			return _dismiss_turn_debrief(state)
		GameCommand.IMPROVE_REAL_ESTATE:
			return _RealEstate.apply_improvement(
				state,
				str(command.get("asset_id", "")),
				str(command.get("improvement_id", "")),
			)
		_:
			return {"ok": false, "error": "Unknown command: %s" % command_type}


static func _advance_turn(state: RunState) -> Dictionary:
	if not state.negotiation.is_empty() and bool(state.negotiation.get("active", false)):
		return {"ok": false, "error": "Close the current negotiation before advancing turn"}

	if state.is_capital_farm():
		var shortages: Array = SynergySystem.detect_supply_shortages(state)
		if not shortages.is_empty() and state.supply_shortage_ack_turn != state.turn:
			return {
				"ok": false,
				"error": "Supply capacity shortage — set allocation policy before advancing",
				"requires_supply_policy": true,
				"shortages": shortages,
			}

	_Rival.resolve_uncontested_contests(state)

	if state.is_capital_farm():
		_Urgent.apply_unresolved_rep_penalty(state)

	var resolver := TurnResolver.new()
	var next: RunState = resolver.advance_turn(state)
	if next.game_over == null:
		OpportunitySystem.advance_opportunities(next)
		_Rival.apply_contest_to_turn(next)
		if next.is_capital_farm():
			_Urgent.update_relationship_health(next)
			for neglect_note: Dictionary in SynergySystem.apply_neglect_pressure(next):
				next.run_log.append("%s: neglected %d turns — %s" % [
					str(neglect_note.get("name", "Business")),
					int(neglect_note.get("turns", 0)),
					str(neglect_note.get("label", "relationship health slipping")),
				])
			_UpgradeSystem.apply_manager_passive_drift(next)
			next.urgent_problems = _Urgent.generate_urgent_problems(next)
		_RunStats.snapshot_turn(next, next.last_advance_report)
	next.supply_shortage_ack_turn = -1
	return {"ok": true, "state": next}


static func _acquire_business(state: RunState, command: Dictionary) -> Dictionary:
	var opp_id: String = str(command.get("opportunity_id", ""))
	var price_override: int = int(command.get("price", -1))
	var result: Dictionary = AcquisitionSystem.acquire_business(state, opp_id, price_override)
	if not bool(result.get("ok", false)):
		return result
	return {"ok": true, "state": state, "business": result.get("business")}


static func _acquire_real_estate(state: RunState, command: Dictionary) -> Dictionary:
	var opp_id: String = str(command.get("opportunity_id", ""))
	var price_override: int = int(command.get("price", -1))
	var result: Dictionary = AcquisitionSystem.acquire_real_estate(state, opp_id, price_override)
	if not bool(result.get("ok", false)):
		return result
	return {"ok": true, "state": state, "realEstate": result.get("realEstate")}


static func _set_supply_policy(state: RunState, command: Dictionary) -> Dictionary:
	var template_id: String = str(command.get("template_id", ""))
	var policy_id: String = str(command.get("policy_id", ""))
	if template_id == "" or policy_id == "":
		return {"ok": false, "error": "Missing template_id or policy_id"}
	if not _SupplyPolicy.POLICIES.has(policy_id):
		return {"ok": false, "error": "Unknown policy: %s" % policy_id}
	_SupplyPolicy.set_policy(state, template_id, policy_id)
	return {"ok": true, "state": state}


static func _dismiss_turn_debrief(state: RunState) -> Dictionary:
	state.pending_turn_debrief = {}
	return {"ok": true, "state": state}


static func _confirm_supply_shortage(state: RunState) -> Dictionary:
	var shortages: Array = SynergySystem.detect_supply_shortages(state)
	if shortages.is_empty():
		return {"ok": false, "error": "No supply shortage to confirm"}
	_SupplyPolicy.confirm_shortage_ack(state)
	return {"ok": true, "state": state}


static func _apply_upgrade(state: RunState, command: Dictionary) -> Dictionary:
	var business_id: String = str(command.get("business_id", ""))
	var track_id: String = str(command.get("track_id", ""))
	return _UpgradeSystem.apply_upgrade_command(state, business_id, track_id)
