class_name ActionPointsSystem
extends RefCounted


static func max_action_points(state: RunState) -> int:
	if state.is_capital_farm() and state.turn == 1:
		return 3
	return 2


static func reset_for_turn(state: RunState) -> void:
	state.action_points = max_action_points(state)


static func require(state: RunState, amount: int = 1) -> Dictionary:
	if state.action_points < amount:
		return {"ok": false, "error": "Need %d AP" % amount}
	return {"ok": true}


static func spend(state: RunState, amount: int = 1) -> Dictionary:
	var check: Dictionary = require(state, amount)
	if not bool(check.get("ok", false)):
		return check
	state.action_points -= amount
	return {"ok": true}
