class_name CommandProcessor
extends RefCounted

const _UpgradeSystem := preload("res://core/systems/upgrade_system.gd")
const _NegotiationSystem := preload("res://core/systems/negotiation_system.gd")
const _Diligence := preload("res://core/systems/diligence_system.gd")
const _SupplyPolicy := preload("res://core/systems/supply_policy_system.gd")
const _LoanSystem := preload("res://core/systems/loan_system.gd")
const _Urgent := preload("res://core/systems/urgent_system.gd")
const _LevelUp := preload("res://core/systems/level_up_system.gd")
const _Progression := preload("res://core/systems/progression_system.gd")
const _Security := preload("res://core/systems/security_system.gd")
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
		GameCommand.TAKE_BANK_LOAN:
			return BankSystem.take_loan(state)
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
		GameCommand.BUY_SECURITY_TICKER:
			return BankSystem.buy_shares(state, str(command.get("ticker", "")), int(command.get("quantity", 10)))
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
	return TurnPipeline.advance_turn(state)


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
	var result: Dictionary = _UpgradeSystem.apply_upgrade_command(state, business_id, track_id)
	if bool(result.get("ok", false)):
		_LevelUp.ensure_opportunity_for_business(state, business_id)
	return result
