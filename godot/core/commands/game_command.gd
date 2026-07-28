class_name GameCommand
extends RefCounted

const ADVANCE_TURN := "advance_turn"
const ACQUIRE_BUSINESS := "acquire_business"
const APPLY_UPGRADE := "apply_upgrade"
const SET_SUPPLY_POLICY := "set_supply_policy"
const START_NEGOTIATION := "start_negotiation"
const SEND_NEGOTIATION_MESSAGE := "send_negotiation_message"
const END_NEGOTIATION := "end_negotiation"
const CLOSE_NEGOTIATION_DEAL := "close_negotiation_deal"
const APPEND_NEGOTIATION_PLAYER := "append_negotiation_player"
const INVESTIGATE := "investigate"
const CONFIRM_SUPPLY_SHORTAGE := "confirm_supply_shortage"
const TAKE_LOAN := "take_loan"
const TAKE_BANK_LOAN := "take_bank_loan"
const PAYOFF_LOAN := "payoff_loan"
const ACQUIRE_REAL_ESTATE := "acquire_real_estate"
const SELL_ASSET := "sell_asset"
const DO_LEVEL_UP := "do_level_up"
const CHOOSE_EDGE := "choose_edge"
const SKIP_EDGE := "skip_edge"
const START_URGENT_NEGOTIATION := "start_urgent_negotiation"
const BUY_SECURITY := "buy_security"
const BUY_SECURITY_TICKER := "buy_security_ticker"
const SELL_SECURITY := "sell_security"
const DISMISS_TURN_DEBRIEF := "dismiss_turn_debrief"
const IMPROVE_REAL_ESTATE := "improve_real_estate"


static func advance_turn() -> Dictionary:
	return {"type": ADVANCE_TURN}


static func acquire_business(opportunity_id: String, price: int = -1) -> Dictionary:
	var cmd := {"type": ACQUIRE_BUSINESS, "opportunity_id": opportunity_id}
	if price >= 0:
		cmd["price"] = price
	return cmd


static func set_supply_policy(template_id: String, policy_id: String) -> Dictionary:
	return {
		"type": SET_SUPPLY_POLICY,
		"template_id": template_id,
		"policy_id": policy_id,
	}


static func apply_upgrade(business_id: String, track_id: String) -> Dictionary:
	return {
		"type": APPLY_UPGRADE,
		"business_id": business_id,
		"track_id": track_id,
	}


static func start_negotiation(opportunity_id: String) -> Dictionary:
	return {"type": START_NEGOTIATION, "opportunity_id": opportunity_id}


static func send_negotiation_message(message: String, ai_parsed: Dictionary = {}, skip_player_append: bool = false) -> Dictionary:
	return {
		"type": SEND_NEGOTIATION_MESSAGE,
		"message": message,
		"ai_parsed": ai_parsed,
		"skip_player_append": skip_player_append,
	}


static func append_negotiation_player(message: String) -> Dictionary:
	return {"type": APPEND_NEGOTIATION_PLAYER, "message": message}


static func end_negotiation(walked: bool = true) -> Dictionary:
	return {"type": END_NEGOTIATION, "walked": walked}


static func close_negotiation_deal() -> Dictionary:
	return {"type": CLOSE_NEGOTIATION_DEAL}


static func investigate(opportunity_id: String) -> Dictionary:
	return {"type": INVESTIGATE, "opportunity_id": opportunity_id}


static func confirm_supply_shortage() -> Dictionary:
	return {"type": CONFIRM_SUPPLY_SHORTAGE}


static func take_loan(opportunity_id: String) -> Dictionary:
	return {"type": TAKE_LOAN, "opportunity_id": opportunity_id}


static func take_bank_loan() -> Dictionary:
	return {"type": TAKE_BANK_LOAN}


static func payoff_loan(loan_id: String) -> Dictionary:
	return {"type": PAYOFF_LOAN, "loan_id": loan_id}


static func acquire_real_estate(opportunity_id: String, price: int = -1) -> Dictionary:
	var cmd := {"type": ACQUIRE_REAL_ESTATE, "opportunity_id": opportunity_id}
	if price >= 0:
		cmd["price"] = price
	return cmd


static func sell_asset(asset_kind: String, asset_id: String) -> Dictionary:
	return {
		"type": SELL_ASSET,
		"asset_kind": asset_kind,
		"asset_id": asset_id,
	}


static func do_level_up(opportunity_id: String) -> Dictionary:
	return {"type": DO_LEVEL_UP, "opportunity_id": opportunity_id}


static func choose_edge(edge_id: String) -> Dictionary:
	return {"type": CHOOSE_EDGE, "edge_id": edge_id}


static func skip_edge() -> Dictionary:
	return {"type": SKIP_EDGE}


static func start_urgent_negotiation(problem_id: String) -> Dictionary:
	return {"type": START_URGENT_NEGOTIATION, "problem_id": problem_id}


static func buy_security(opportunity_id: String, quantity: int = 10) -> Dictionary:
	return {"type": BUY_SECURITY, "opportunity_id": opportunity_id, "quantity": quantity}


static func buy_security_ticker(ticker: String, quantity: int = 10) -> Dictionary:
	return {"type": BUY_SECURITY_TICKER, "ticker": ticker, "quantity": quantity}


static func sell_security(ticker: String) -> Dictionary:
	return {"type": SELL_SECURITY, "ticker": ticker}


static func dismiss_turn_debrief() -> Dictionary:
	return {"type": DISMISS_TURN_DEBRIEF}


static func improve_real_estate(asset_id: String, improvement_id: String) -> Dictionary:
	return {
		"type": IMPROVE_REAL_ESTATE,
		"asset_id": asset_id,
		"improvement_id": improvement_id,
	}
