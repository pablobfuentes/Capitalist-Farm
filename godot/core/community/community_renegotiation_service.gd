# Turn processing for post-acquisition client renegotiation events (8.3 §7).
class_name CommunityRenegotiationService
extends RefCounted


static func process_turn(state: RunState) -> Array:
	if state == null:
		return []
	CommunityState.ensure_initialized(state)
	if not CommunityFeatureFlags.is_enabled(CommunityFeatureFlags.FLAG_COMMUNITY_GENERATION, state):
		return []

	var fired: Array = []
	var pending: Array = state.community.get("pendingClientRenegotiations", [])
	var remaining: Array = []
	if typeof(pending) != TYPE_ARRAY:
		pending = []

	for event_variant in pending:
		if typeof(event_variant) != TYPE_DICTIONARY:
			continue
		var event: Dictionary = event_variant
		if str(event.get("status", "")) != "pending":
			remaining.append(event)
			continue
		if int(event.get("dueTurn", 999999)) > state.turn:
			remaining.append(event)
			continue
		var activated: Dictionary = _activate_event(state, event)
		if not activated.is_empty():
			fired.append(activated)

	state.community["pendingClientRenegotiations"] = remaining
	_expire_active_renegotiations(state)
	return fired


static func active_for_business(state: RunState, player_business_id: String) -> Array:
	CommunityState.ensure_initialized(state)
	var active: Array = state.community.get("activeClientRenegotiations", [])
	var matched: Array = []
	for event_variant in active:
		if typeof(event_variant) != TYPE_DICTIONARY:
			continue
		var event: Dictionary = event_variant
		if str(event.get("playerBusinessId", "")) == player_business_id:
			matched.append(event.duplicate(true))
	return matched


static func _activate_event(state: RunState, event: Dictionary) -> Dictionary:
	event = event.duplicate(true)
	event["status"] = "active"
	event["activatedTurn"] = state.turn
	event["expiresTurn"] = state.turn + int(event.get("durationTurns", 3))

	var active: Array = state.community.get("activeClientRenegotiations", [])
	if typeof(active) != TYPE_ARRAY:
		active = []
	active.append(event)
	state.community["activeClientRenegotiations"] = active

	_apply_business_pressure(state, event)
	CommunityNotebookService.record_renegotiation_event(state, event)
	CommunityInteractionLedger.append_event(state, {
		"eventType": "client_renegotiation",
		"npcId": str(event.get("counterpartNpcId", "")),
		"businessId": str(event.get("playerBusinessId", "")),
		"payload": event,
		"summary": str(event.get("summary", "Client renegotiation")),
	})

	state.run_log.append("Community — %s" % str(event.get("summary", "Client renegotiation triggered")))
	return event


static func _apply_business_pressure(state: RunState, event: Dictionary) -> void:
	var player_business_id := str(event.get("playerBusinessId", ""))
	for biz: BusinessInstance in state.portfolio.businesses:
		if biz.id != player_business_id:
			continue
		if bool(event.get("terminationRisk", false)):
			biz.client_state = "at_risk"
			biz.client_health = maxi(20, biz.client_health - 15)
		elif bool(event.get("strictCovenants", false)):
			biz.client_state = "review"
			biz.client_health = maxi(25, biz.client_health - 8)
		else:
			biz.client_state = "expansion"
			biz.client_health = mini(100, biz.client_health + 5)
		return


static func _expire_active_renegotiations(state: RunState) -> void:
	var active: Array = state.community.get("activeClientRenegotiations", [])
	if typeof(active) != TYPE_ARRAY or active.is_empty():
		return
	var kept: Array = []
	for event_variant in active:
		if typeof(event_variant) != TYPE_DICTIONARY:
			continue
		var event: Dictionary = event_variant
		if str(event.get("status", "")) == "active" and int(event.get("expiresTurn", 0)) < state.turn:
			event["status"] = "expired"
			_apply_expired_consequences(state, event)
			state.run_log.append(
				"Community — renegotiation with %s expired without resolution"
				% str(event.get("playerBusinessName", "a client"))
			)
			continue
		if str(event.get("status", "")) in ["active", "fulfilled"]:
			kept.append(event)
	state.community["activeClientRenegotiations"] = kept


static func _apply_expired_consequences(state: RunState, event: Dictionary) -> void:
	var npc_id := str(event.get("counterpartNpcId", ""))
	if npc_id.is_empty():
		return
	var social: Dictionary = CommunityState.get_social_state(state, npc_id)
	social["trust"] = maxi(0, int(social.get("trust", 0)) - 8)
	social["resentment"] = mini(100, int(social.get("resentment", 0)) + 10)
	social["personalRelationshipScore"] = clampi(
		int(social.get("personalRelationshipScore", 0)) - 1,
		int(CommunityConfig.personal_relationship_range().get("min", -5)),
		int(CommunityConfig.personal_relationship_range().get("max", 5)),
	)
	social["updatedTurn"] = state.turn
	CommunityState.set_social_state(state, npc_id, social)

	var player_business_id := str(event.get("playerBusinessId", ""))
	for biz: BusinessInstance in state.portfolio.businesses:
		if biz.id != player_business_id:
			continue
		if bool(event.get("terminationRisk", false)):
			biz.client_state = "lost"
			biz.client_health = maxi(0, biz.client_health - 20)
		else:
			biz.client_state = "strained"
			biz.client_health = maxi(0, biz.client_health - 10)
		return
