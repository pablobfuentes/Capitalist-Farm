# Engine-verified NPC promises from community chat (8.3 Phase 7 / §11.3).
class_name CommunityPromiseService
extends RefCounted

const _SupplyPolicy := preload("res://core/systems/supply_policy_system.gd")

const STATUS_PROPOSED := "proposed"
const STATUS_ACCEPTED := "accepted"
const STATUS_FULFILLED := "fulfilled"
const STATUS_BROKEN := "broken"
const STATUS_EXPIRED := "expired"
const STATUS_CANCELED := "canceled"

const ACTIVE_STATUSES := [STATUS_ACCEPTED]


static func record_from_chat_proposal(
	state: RunState,
	npc_id: String,
	proposal: Dictionary,
	session: Dictionary = {},
) -> Dictionary:
	if not _enabled(state) or proposal.is_empty() or npc_id.is_empty():
		return {"ok": false, "error": "disabled_or_invalid"}

	var promise_type := str(proposal.get("type", ""))
	if not CommunityConfig.is_valid_promise_type(promise_type):
		return {"ok": false, "error": "invalid_promise_type"}

	var cfg: Dictionary = CommunitySocialEffects.promise_fulfillment_config()
	var duration := int(proposal.get("duration_turns", cfg.get("defaultDurationTurns", 3)))
	if duration <= 0:
		duration = int(cfg.get("defaultDurationTurns", 3))

	var deadline_turn: int = int(proposal.get("deadline_turn", 0))
	if deadline_turn <= 0:
		deadline_turn = state.turn + duration

	var promise_id := CommunityState.next_promise_id(state)
	var subject_id := _resolve_subject_id(proposal)
	var record := {
		"id": promise_id,
		"type": promise_type,
		"fulfillmentKey": CommunityConfig.promise_fulfillment_key(promise_type),
		"status": STATUS_ACCEPTED,
		"npcId": npc_id,
		"subjectId": subject_id,
		"proposedTurn": state.turn,
		"acceptedTurn": state.turn,
		"deadlineTurn": deadline_turn,
		"durationTurns": duration,
		"expiresTurn": deadline_turn + int(cfg.get("defaultDeadlineGraceTurns", 0)),
		"policyId": str(proposal.get("policy_id", "")),
		"templateId": str(proposal.get("template_id", "")),
		"capacityPercent": float(proposal.get("capacity_percent", 0.0)),
		"factId": str(proposal.get("fact_id", subject_id)),
		"baseline": _capture_baseline(state, npc_id, proposal),
		"progressTurns": 0,
		"sourceSessionId": str(session.get("sessionId", "")),
		"lastCheckedTurn": state.turn,
		"outcomeTurn": null,
		"outcomeNote": "",
	}

	var promises: Array = _promises(state)
	promises.append(record)
	state.community["promises"] = promises

	CommunityInteractionLedger.append_event(state, {
		"eventType": "promise_accepted",
		"npcId": npc_id,
		"conversationSessionId": str(session.get("sessionId", "")),
		"payload": record,
		"summary": "Promise accepted: %s" % promise_type,
	})
	CommunityNotebookService.record_promise_event(state, record, "accepted")
	state.run_log.append("Community — Promise recorded with %s (%s)." % [
		CommunityGenerator.get_npc(state, npc_id).get("displayName", npc_id),
		promise_type,
	])
	return {"ok": true, "promise": record.duplicate(true)}


static func process_turn(state: RunState) -> Array:
	if not _enabled(state):
		return []

	var outcomes: Array = []
	var promises: Array = _promises(state)
	for index in promises.size():
		var promise_variant = promises[index]
		if typeof(promise_variant) != TYPE_DICTIONARY:
			continue
		var promise: Dictionary = promise_variant
		var status := str(promise.get("status", ""))
		if status not in ACTIVE_STATUSES:
			continue

		promise["lastCheckedTurn"] = state.turn
		var evaluation: Dictionary = _evaluate_promise(state, promise)
		promise["progressTurns"] = int(promise.get("progressTurns", 0)) + 1

		if bool(evaluation.get("fulfilled", false)):
			promise = _set_outcome(state, promise, STATUS_FULFILLED, str(evaluation.get("note", "")))
			outcomes.append(promise.duplicate(true))
		elif bool(evaluation.get("broken", false)):
			promise = _set_outcome(state, promise, STATUS_BROKEN, str(evaluation.get("note", "")))
			outcomes.append(promise.duplicate(true))
		elif _past_deadline(state, promise):
			promise = _set_outcome(state, promise, STATUS_EXPIRED, "Deadline passed without fulfillment")
			outcomes.append(promise.duplicate(true))
		promises[index] = promise

	state.community["promises"] = promises
	return outcomes


static func active_promises_for_npc(state: RunState, npc_id: String) -> Array:
	var matched: Array = []
	for promise_variant in _promises(state):
		if typeof(promise_variant) != TYPE_DICTIONARY:
			continue
		var promise: Dictionary = promise_variant
		if str(promise.get("npcId", "")) != npc_id:
			continue
		if str(promise.get("status", "")) in ACTIVE_STATUSES:
			matched.append(promise.duplicate(true))
	return matched


static func record_payment_toward_npc(state: RunState, npc_id: String, amount: int = 0) -> Array:
	if not _enabled(state):
		return []
	var fulfilled: Array = []
	for index in _promises(state).size():
		var promise: Dictionary = _promises(state)[index]
		if str(promise.get("status", "")) != STATUS_ACCEPTED:
			continue
		if str(promise.get("fulfillmentKey", "")) != "cash_payment_by_turn":
			continue
		if str(promise.get("npcId", "")) != npc_id:
			continue
		if amount > 0 and amount < int(promise.get("baseline", {}).get("amountDue", 0)):
			continue
		promise = _set_outcome(state, promise, STATUS_FULFILLED, "Payment recorded")
		_promises(state)[index] = promise
		fulfilled.append(promise.duplicate(true))
	state.community["promises"] = _promises(state)
	return fulfilled


static func mark_renegotiation_engaged(state: RunState, player_business_id: String) -> Array:
	if not _enabled(state):
		return []
	var fulfilled: Array = []
	var promises: Array = _promises(state)
	for index in promises.size():
		var promise: Dictionary = promises[index]
		if str(promise.get("status", "")) != STATUS_ACCEPTED:
			continue
		if str(promise.get("fulfillmentKey", "")) != "renegotiation_engaged":
			continue
		if str(promise.get("subjectId", "")) != player_business_id:
			continue
		promise = _set_outcome(state, promise, STATUS_FULFILLED, "Renegotiation engaged")
		promises[index] = promise
		fulfilled.append(promise.duplicate(true))
	state.community["promises"] = promises
	return fulfilled


static func _enabled(state: RunState) -> bool:
	return CommunityFeatureFlags.is_enabled(CommunityFeatureFlags.FLAG_COMMUNITY_GENERATION, state) \
		and CommunityFeatureFlags.is_enabled(CommunityFeatureFlags.FLAG_PROMISE_FULFILLMENT, state)


static func _promises(state: RunState) -> Array:
	CommunityState.ensure_initialized(state)
	var promises: Array = state.community.get("promises", [])
	if typeof(promises) != TYPE_ARRAY:
		promises = []
		state.community["promises"] = promises
	return promises


static func _resolve_subject_id(proposal: Dictionary) -> String:
	var subject := str(proposal.get("subject_id", ""))
	if not subject.is_empty():
		return subject
	var fact_id := str(proposal.get("fact_id", ""))
	if not fact_id.is_empty():
		return fact_id
	var template_id := str(proposal.get("template_id", ""))
	if not template_id.is_empty():
		return template_id
	return ""


static func _capture_baseline(state: RunState, npc_id: String, proposal: Dictionary) -> Dictionary:
	var baseline: Dictionary = {"capturedTurn": state.turn}
	var player_business := _linked_player_business(state, npc_id)
	if player_business != null:
		baseline["playerBusinessId"] = player_business.id
		baseline["operatingCosts"] = player_business.operating_costs
		baseline["level"] = player_business.level
		baseline["revenuePerTurn"] = player_business.revenue_per_turn
		baseline["supplierHealth"] = player_business.supplier_health
		baseline["clientHealth"] = player_business.client_health
		baseline["clientState"] = player_business.client_state
		baseline["supplierState"] = player_business.supplier_state
		baseline["supplyPolicy"] = _SupplyPolicy.get_policy(state, player_business.template_id)

	var contract := _contract_for_subject(state, proposal, player_business)
	if not contract.is_empty():
		baseline["contractId"] = str(contract.get("id", ""))
		baseline["reliability"] = float(contract.get("reliability", 0.7))
		baseline["dependence"] = float(contract.get("dependence", 0.5))

	var template_id := str(proposal.get("template_id", ""))
	if template_id.is_empty() and player_business != null:
		template_id = player_business.template_id
	if not template_id.is_empty():
		baseline["templateId"] = template_id
		baseline["supplyPolicy"] = _SupplyPolicy.get_policy(state, template_id)

	baseline["amountDue"] = int(proposal.get("amount_due", 0))
	return baseline


static func _evaluate_promise(state: RunState, promise: Dictionary) -> Dictionary:
	var key := str(promise.get("fulfillmentKey", ""))
	match key:
		"notebook_fact_confirmed":
			return _eval_notebook_fact(state, promise)
		"cash_payment_by_turn":
			return _eval_pending_until_deadline(state, promise)
		"supply_policy_match":
			return _eval_supply_policy(state, promise, false)
		"exclusive_supply_policy":
			return _eval_supply_policy(state, promise, true)
		"headcount_unchanged":
			return _eval_headcount_unchanged(state, promise)
		"capacity_allocation_soft":
			return _eval_capacity_commitment(state, promise, false)
		"capacity_allocation_strict":
			return _eval_capacity_commitment(state, promise, true)
		"supply_strain_below":
			return _eval_delivery_reliability(state, promise)
		"price_unchanged":
			return _eval_price_unchanged(state, promise)
		"renegotiation_engaged":
			return _eval_pending_until_deadline(state, promise)
		_:
			return {"fulfilled": false, "broken": false, "note": "Unknown fulfillment key"}


static func _eval_notebook_fact(state: RunState, promise: Dictionary) -> Dictionary:
	var fact_id := str(promise.get("factId", promise.get("subjectId", "")))
	if fact_id.is_empty():
		return {"fulfilled": false, "broken": true, "note": "Missing fact id"}

	var player_facts: Dictionary = state.community.get("playerFactKnowledge", {})
	var record: Dictionary = player_facts.get(fact_id, {})
	if typeof(record) != TYPE_DICTIONARY or record.is_empty():
		if state.turn >= int(promise.get("deadlineTurn", state.turn)):
			return {"fulfilled": false, "broken": true, "note": "Fact not discovered by deadline"}
		return {"fulfilled": false, "broken": false, "note": "Awaiting discovery"}

	var confirmation := str(record.get("confirmationState", "rumored"))
	if confirmation in ["supported", "confirmed"]:
		return {"fulfilled": true, "broken": false, "note": "Fact recorded in notebook"}
	if float(record.get("confidence", 0.0)) >= 0.65:
		return {"fulfilled": true, "broken": false, "note": "Fact recorded with sufficient confidence"}
	if state.turn >= int(promise.get("deadlineTurn", state.turn)):
		return {"fulfilled": false, "broken": true, "note": "Fact discovery too weak by deadline"}
	return {"fulfilled": false, "broken": false, "note": "Awaiting stronger confirmation"}


static func _eval_pending_until_deadline(state: RunState, promise: Dictionary) -> Dictionary:
	if _past_deadline(state, promise):
		return {"fulfilled": false, "broken": true, "note": "Deadline passed"}
	return {"fulfilled": false, "broken": false, "note": "Awaiting deadline fulfillment hook"}


static func _past_deadline(state: RunState, promise: Dictionary) -> bool:
	return state.turn > int(promise.get("expiresTurn", promise.get("deadlineTurn", state.turn)))


static func _eval_supply_policy(state: RunState, promise: Dictionary, exclusive: bool) -> Dictionary:
	var cfg: Dictionary = CommunitySocialEffects.promise_fulfillment_config()
	var template_id := str(promise.get("templateId", promise.get("baseline", {}).get("templateId", "")))
	if template_id.is_empty():
		return {"fulfilled": false, "broken": true, "note": "Missing template for supply policy promise"}

	var required_policy := str(promise.get("policyId", ""))
	if required_policy.is_empty():
		var allowed: Array = cfg.get("exclusivePolicies" if exclusive else "localSupplierPolicies", [])
		var current := _SupplyPolicy.get_policy(state, template_id)
		if current in allowed:
			if int(promise.get("progressTurns", 0)) + 1 >= int(promise.get("durationTurns", 1)):
				return {"fulfilled": true, "broken": false, "note": "Policy maintained for duration"}
			return {"fulfilled": false, "broken": false, "note": "Policy holding"}
		if int(promise.get("progressTurns", 0)) > 0:
			return {"fulfilled": false, "broken": true, "note": "Policy diverged from commitment"}
		return {"fulfilled": false, "broken": false, "note": "Awaiting compliant policy"}

	if _SupplyPolicy.get_policy(state, template_id) == required_policy:
		if int(promise.get("progressTurns", 0)) + 1 >= int(promise.get("durationTurns", 1)):
			return {"fulfilled": true, "broken": false, "note": "Required policy maintained"}
		return {"fulfilled": false, "broken": false, "note": "Required policy holding"}
	if int(promise.get("progressTurns", 0)) > 0:
		return {"fulfilled": false, "broken": true, "note": "Required policy broken"}
	return {"fulfilled": false, "broken": false, "note": "Awaiting required policy"}


static func _eval_headcount_unchanged(state: RunState, promise: Dictionary) -> Dictionary:
	var cfg: Dictionary = CommunitySocialEffects.promise_fulfillment_config()
	var baseline: Dictionary = promise.get("baseline", {})
	var player_business := _business_by_id(state, str(baseline.get("playerBusinessId", "")))
	if player_business == null:
		player_business = _linked_player_business(state, str(promise.get("npcId", "")))
	if player_business == null:
		return {"fulfilled": false, "broken": false, "note": "No linked player business yet"}

	var tolerance := float(cfg.get("headcountTolerancePct", 0.08))
	var base_cost := maxi(1, int(baseline.get("operatingCosts", player_business.operating_costs)))
	var delta := absf(float(player_business.operating_costs - base_cost)) / float(base_cost)
	var level_changed := int(baseline.get("level", player_business.level)) != player_business.level
	if level_changed or delta > tolerance:
		return {"fulfilled": false, "broken": true, "note": "Headcount or labor footprint changed"}

	if int(promise.get("progressTurns", 0)) + 1 >= int(promise.get("durationTurns", 1)):
		return {"fulfilled": true, "broken": false, "note": "Headcount stable for duration"}
	return {"fulfilled": false, "broken": false, "note": "Headcount stable so far"}


static func _eval_capacity_commitment(state: RunState, promise: Dictionary, strict: bool) -> Dictionary:
	var cfg: Dictionary = CommunitySocialEffects.promise_fulfillment_config()
	var baseline: Dictionary = promise.get("baseline", {})
	var contract := _contract_by_id(state, str(baseline.get("contractId", promise.get("subjectId", ""))))
	if contract.is_empty():
		contract = _contract_for_subject(state, promise, _linked_player_business(state, str(promise.get("npcId", ""))))
	if contract.is_empty():
		return {"fulfilled": false, "broken": false, "note": "No linked contract yet"}

	var base_reliability := float(baseline.get("reliability", contract.get("reliability", 0.7)))
	var current_reliability := float(contract.get("reliability", base_reliability))
	var floor := float(cfg.get("capacityStrictReliabilityFloor" if strict else "capacitySoftReliabilityFloor", 0.85))
	var required_pct := float(promise.get("capacityPercent", 0.0))
	if required_pct > 0.0:
		floor = maxf(floor, required_pct / 100.0)

	if current_reliability < base_reliability * floor:
		return {"fulfilled": false, "broken": true, "note": "Capacity/reliability below commitment"}

	if int(promise.get("progressTurns", 0)) + 1 >= int(promise.get("durationTurns", 1)):
		return {"fulfilled": true, "broken": false, "note": "Capacity commitment met"}
	return {"fulfilled": false, "broken": false, "note": "Capacity commitment holding"}


static func _eval_delivery_reliability(state: RunState, promise: Dictionary) -> Dictionary:
	var cfg: Dictionary = CommunitySocialEffects.promise_fulfillment_config()
	var min_health := int(cfg.get("deliveryReliabilityMinHealth", 65))
	var player_business := _business_by_id(state, str(promise.get("baseline", {}).get("playerBusinessId", "")))
	if player_business == null:
		player_business = _linked_player_business(state, str(promise.get("npcId", "")))
	if player_business == null:
		return {"fulfilled": false, "broken": false, "note": "No linked player business yet"}

	if player_business.supplier_health < min_health or player_business.supplier_state == "at_risk":
		return {"fulfilled": false, "broken": true, "note": "Supplier reliability strained"}

	if int(promise.get("progressTurns", 0)) + 1 >= int(promise.get("durationTurns", 1)):
		return {"fulfilled": true, "broken": false, "note": "Delivery reliability maintained"}
	return {"fulfilled": false, "broken": false, "note": "Delivery reliability holding"}


static func _eval_price_unchanged(state: RunState, promise: Dictionary) -> Dictionary:
	var baseline: Dictionary = promise.get("baseline", {})
	var player_business := _business_by_id(state, str(baseline.get("playerBusinessId", "")))
	if player_business == null:
		player_business = _linked_player_business(state, str(promise.get("npcId", "")))
	if player_business == null:
		return {"fulfilled": false, "broken": false, "note": "No linked player business yet"}

	var base_revenue := int(baseline.get("revenuePerTurn", player_business.revenue_per_turn))
	if player_business.revenue_per_turn != base_revenue:
		return {"fulfilled": false, "broken": true, "note": "Offer price / revenue changed"}

	if int(promise.get("progressTurns", 0)) + 1 >= int(promise.get("durationTurns", 1)):
		return {"fulfilled": true, "broken": false, "note": "Price held for duration"}
	return {"fulfilled": false, "broken": false, "note": "Price holding"}


static func _set_outcome(state: RunState, promise: Dictionary, status: String, note: String) -> Dictionary:
	promise = promise.duplicate(true)
	promise["status"] = status
	promise["outcomeTurn"] = state.turn
	promise["outcomeNote"] = note
	_apply_consequences(state, str(promise.get("npcId", "")), status)
	CommunityNotebookService.record_promise_event(state, promise, status)
	CommunityInteractionLedger.append_event(state, {
		"eventType": "promise_%s" % status,
		"npcId": str(promise.get("npcId", "")),
		"payload": promise,
		"summary": "Promise %s: %s" % [status, str(promise.get("type", ""))],
	})
	state.run_log.append("Community — Promise %s with %s (%s)." % [
		status,
		CommunityGenerator.get_npc(state, str(promise.get("npcId", ""))).get("displayName", promise.get("npcId", "")),
		str(promise.get("type", "")),
	])
	return promise


static func _apply_consequences(state: RunState, npc_id: String, status: String) -> void:
	var cfg: Dictionary = CommunitySocialEffects.promise_fulfillment_config()
	var consequences: Dictionary = cfg.get("consequences", {})
	var key := "fulfilled"
	match status:
		STATUS_FULFILLED:
			key = "fulfilled"
		STATUS_BROKEN:
			key = "broken"
		STATUS_EXPIRED:
			key = "expired"
		_:
			return

	var deltas: Dictionary = consequences.get(key, {})
	if typeof(deltas) != TYPE_DICTIONARY or deltas.is_empty():
		return

	var social := CommunityState.get_social_state(state, npc_id)
	var dim_range: Dictionary = CommunitySocialEffects.dimension_range()
	var dim_min := int(dim_range.get("min", -100))
	var dim_max := int(dim_range.get("max", 100))
	for dim_key in deltas.keys():
		var dim := str(dim_key)
		if not social.has(dim):
			continue
		social[dim] = clampi(int(social.get(dim, 0)) + int(deltas[dim]), dim_min, dim_max)
	social["updatedTurn"] = state.turn
	social["personalRelationshipScore"] = CommunitySocialRules.summarize_personal_relationship(social)
	CommunityState.set_social_state(state, npc_id, social)


static func _linked_player_business(state: RunState, npc_id: String) -> BusinessInstance:
	var npc: Dictionary = CommunityGenerator.get_npc(state, npc_id)
	var community_business_id := str(npc.get("primaryBusinessId", ""))
	if community_business_id.is_empty():
		return null
	var links: Dictionary = state.community.get("playerBusinessLinks", {})
	for player_business_id_variant in links.keys():
		var link: Dictionary = links[player_business_id_variant]
		if str(link.get("communityBusinessId", "")) == community_business_id:
			return _business_by_id(state, str(player_business_id_variant))
	return null


static func _business_by_id(state: RunState, business_id: String) -> BusinessInstance:
	if business_id.is_empty():
		return null
	for biz: BusinessInstance in state.portfolio.businesses:
		if biz.id == business_id:
			return biz
	return null


static func _contract_by_id(state: RunState, contract_id: String) -> Dictionary:
	if contract_id.is_empty():
		return {}
	for contract_variant in state.community.get("playerSupplyContracts", []):
		if typeof(contract_variant) != TYPE_DICTIONARY:
			continue
		var contract: Dictionary = contract_variant
		if str(contract.get("id", "")) == contract_id:
			return contract.duplicate(true)
	return {}


static func _contract_for_subject(
	state: RunState,
	proposal: Dictionary,
	player_business: BusinessInstance,
) -> Dictionary:
	var subject := _resolve_subject_id(proposal)
	if subject.is_empty():
		return {}
	for contract_variant in state.community.get("playerSupplyContracts", []):
		if typeof(contract_variant) != TYPE_DICTIONARY:
			continue
		var contract: Dictionary = contract_variant
		if str(contract.get("id", "")) == subject:
			return contract.duplicate(true)
		if player_business != null and str(contract.get("playerBusinessId", "")) == player_business.id:
			if str(contract.get("counterpartBusinessId", "")) == subject \
					or str(contract.get("counterpartNpcId", "")) == subject:
				return contract.duplicate(true)
	return {}
