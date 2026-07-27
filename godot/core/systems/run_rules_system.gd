class_name RunRulesSystem
extends RefCounted

const WIN_NET_WORTH := 10_000_000


static func available_credit(state: RunState) -> int:
	var cfg: Dictionary = GameMode.config(state.mode)
	var mult: float = 1.6 if bool(cfg.get("tier_scale_on", false)) else 1.0
	return int(float(state.reputation) * 1500.0 * mult)


static func is_insolvent(state: RunState) -> bool:
	if state.cash >= 0:
		return false
	return absi(state.cash) > available_credit(state)


static func apply_post_cash_flow_checks(state: RunState) -> void:
	if is_insolvent(state):
		state.game_over = {"result": "loss", "reason": "insolvency"}


static func apply_turn_increment(state: RunState) -> void:
	state.turn += 1
	ActionPointsSystem.reset_for_turn(state)


static func apply_end_of_turn_victory_checks(state: RunState) -> void:
	if state.game_over != null:
		return
	var nw: int = FinanceSystem.net_worth(state)
	if state.turn > state.max_turns:
		state.game_over = {
			"result": "win" if nw >= WIN_NET_WORTH else "timeout",
			"reason": "turn_limit",
		}
	elif nw >= WIN_NET_WORTH:
		state.game_over = {"result": "win", "reason": "target_reached"}
