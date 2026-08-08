extends GutTest

## Deterministic supplier/client Issue Pressure (docs/Supplier_Client_Issue_Pressure_Implementation.docx).


func before_all() -> void:
	Content.load_farm_content()
	NegotiationArchetypes.ensure_loaded()


func _farm_state(seed: int = 4242) -> RunState:
	var state: RunState = RunState.create_new(GameMode.MODE_CAPITAL_FARM)
	state.run_seed = seed
	state.supply_shortage_ack_turn = state.turn
	state.cash = 20000
	return state


func _add_business(state: RunState, template_id: String, id: String = "biz-1") -> BusinessInstance:
	var tmpl := Content.get_template(template_id)
	var biz := BusinessInstance.create_from_template(template_id, tmpl.name if tmpl else template_id, 20000, 12000)
	biz.id = id
	biz.acquired_turn = state.turn
	biz.last_care_turn = state.turn
	biz.client_health = 70
	biz.supplier_health = 70
	biz.client_state = "stable"
	biz.supplier_state = "stable"
	biz.cust_conc = 0.2
	state.portfolio.businesses.append(biz)
	UpgradeSystem.ensure_business_upgrades(biz)
	return biz


func _first_rel(state: RunState) -> Dictionary:
	var rels: Array = RelationshipIssuePressureSystem.enumerate_relationships(state)
	assert_gt(rels.size(), 0, "Owned external-linked business should expose relationships")
	return rels[0]


func _rel_state(state: RunState, rel_id: String) -> Dictionary:
	var states := RelationshipIssuePressureSystem.ensure_states(state)
	if not states.has(rel_id) or typeof(states[rel_id]) != TYPE_DICTIONARY:
		states[rel_id] = {
			"relationshipId": rel_id,
			"issuePressure": 0.0,
			"roundsSinceIssue": 0,
			"serviceBuffer": 0.0,
			"lastIssueType": "",
			"recentIssueTypes": [],
			"consecutiveIssues": 0,
			"pendingIssueId": "",
			"lastReviewedRound": 0,
			"lastPressureBreakdown": {},
		}
	return states[rel_id]


func test_pressure_accumulates_stably_without_rng_trigger() -> void:
	var state := _farm_state()
	_add_business(state, "bakery", "bakery-1")
	var rel := _first_rel(state)
	var util := SynergySystem.compute_supplier_utilization(state)
	var a := RelationshipIssuePressureSystem.calculate_pressure_breakdown(state, rel, util)
	var b := RelationshipIssuePressureSystem.calculate_pressure_breakdown(state, rel, util)
	assert_eq(float(a.get("totalGain", 0.0)), float(b.get("totalGain", 0.0)))
	assert_gte(float(a.get("totalGain", 0.0)), 4.0)
	assert_eq(float(a.get("base", 0.0)), 16.0)


func test_mandatory_review_at_five_rounds() -> void:
	var state := _farm_state(9001)
	_add_business(state, "bakery", "bakery-1")
	for _i in 5:
		state.urgent_problems = RelationshipIssuePressureSystem.process_turn(state)
		state.turn += 1
	assert_gt(state.urgent_problems.size(), 0, "Unmanaged relationship must surface by round 5")
	var problem: Dictionary = state.urgent_problems[0]
	assert_true(str(problem.get("type", "")) in ["client", "supplier"])
	assert_false(str(problem.get("issueType", "")).is_empty())
	assert_false(str(problem.get("relationshipId", "")).is_empty())


func test_service_buffer_can_prevent_mandatory_review() -> void:
	var state := _farm_state(9002)
	var biz := _add_business(state, "bakery", "bakery-1")
	biz.upgrades["care"] = 3
	UpgradeSystem.recompute_upgrade_stats(biz)
	var rel := _first_rel(state)
	var st := _rel_state(state, str(rel.get("relationshipId", "")))
	st["serviceBuffer"] = 60.0
	st["issuePressure"] = 40.0
	st["roundsSinceIssue"] = 4
	state.urgent_problems = RelationshipIssuePressureSystem.process_turn(state)
	assert_eq(state.urgent_problems.size(), 0, "Advanced care buffer should prevent the review")
	assert_eq(int(st.get("roundsSinceIssue", -1)), 0)
	assert_lt(float(st.get("issuePressure", 999.0)), 40.0)


func test_highest_score_issue_is_deterministic() -> void:
	var state := _farm_state(77)
	var biz := _add_business(state, "bakery", "bakery-1")
	biz.client_health = 30
	biz.supplier_health = 30
	biz.cust_conc = 0.8
	var rel := _first_rel(state)
	var st := {
		"issuePressure": 110.0,
		"roundsSinceIssue": 5,
		"recentIssueTypes": [],
		"lastIssueType": "",
		"lastPressureBreakdown": RelationshipIssuePressureSystem.calculate_pressure_breakdown(state, rel),
	}
	var a := RelationshipIssuePressureSystem.build_highest_scoring_issue(state, rel, st.duplicate(true))
	var b := RelationshipIssuePressureSystem.build_highest_scoring_issue(state, rel, st.duplicate(true))
	assert_eq(str(a.get("issueType", "")), str(b.get("issueType", "")))
	assert_eq(str(a.get("severity", "")), "concern")
	assert_false(str(a.get("askStatement", "")).is_empty(), "Issue should state a quantified starting ask")
	assert_gt(int((a.get("ask", {}) as Dictionary).get("amountPerTurn", 0)), 0)
	assert_true((a.get("acceptTerms", {}) as Dictionary).has("hardFloorAmount"))
	assert_false(str(a.get("counterpartyTemplateId", "")).is_empty())


func test_resolve_sets_residual_pressure() -> void:
	var state := _farm_state()
	_add_business(state, "bakery", "bakery-1")
	var rel := _first_rel(state)
	var rid := str(rel.get("relationshipId", ""))
	var st := _rel_state(state, rid)
	st["issuePressure"] = 130.0
	st["roundsSinceIssue"] = 6
	st["pendingIssueId"] = "prob-1"
	var problem := {"id": "prob-1", "relationshipId": rid, "type": "client", "businessId": "bakery-1"}
	state.urgent_problems = [problem]
	RelationshipIssuePressureSystem.on_negotiation_resolved(state, problem, true)
	assert_eq(float(st.get("issuePressure", 0.0)), 20.0)
	assert_eq(int(st.get("roundsSinceIssue", -1)), 0)
	assert_eq(str(st.get("pendingIssueId", "x")), "")


func test_relationship_issue_states_roundtrip() -> void:
	var state := _farm_state()
	state.relationship_issue_states = {
		"client|c1|biz": {"issuePressure": 42.0, "roundsSinceIssue": 2, "serviceBuffer": 10.0},
	}
	var reloaded := RunState.from_dict(state.to_dict())
	assert_true(reloaded.relationship_issue_states.has("client|c1|biz"))
	assert_eq(float((reloaded.relationship_issue_states["client|c1|biz"] as Dictionary).get("issuePressure", 0.0)), 42.0)


func test_process_turn_does_not_crash_empty_portfolio() -> void:
	var state := _farm_state()
	var problems := RelationshipIssuePressureSystem.process_turn(state)
	assert_eq(problems.size(), 0)


func test_resolve_applies_settled_amount_to_opex() -> void:
	var state := _farm_state()
	var biz := _add_business(state, "bakery", "bakery-1")
	biz.operating_costs = 10000
	biz.revenue_per_turn = 18000
	var before_cost := biz.operating_costs
	var before_profit := biz.revenue_per_turn - biz.operating_costs
	var problem := {
		"id": "prob-cost",
		"type": "supplier",
		"businessId": biz.id,
		"ask": {"amountPerTurn": 500, "statement": "price hike"},
		"acceptTerms": {"acceptableAmount": 320, "hardFloorAmount": 200},
		"stake": {"amount": 500},
		"relationshipId": "supplier|x|bakery-1",
	}
	state.urgent_problems = [problem]
	state.relationship_issue_states = {
		"supplier|x|bakery-1": {"pendingIssueId": "prob-cost", "issuePressure": 120.0, "roundsSinceIssue": 5},
	}
	UrgentSystem.resolve_relationship_deal(state, problem, {"totalPrice": 320})
	assert_eq(biz.operating_costs, before_cost + 320)
	assert_eq(biz.revenue_per_turn - biz.operating_costs, before_profit - 320)
	assert_eq(state.urgent_problems.size(), 0)


func test_fail_applies_full_ask_to_revenue() -> void:
	var state := _farm_state()
	var biz := _add_business(state, "bakery", "bakery-1")
	biz.revenue_per_turn = 20000
	var problem := {
		"id": "prob-rev",
		"type": "client",
		"businessId": biz.id,
		"ask": {"amountPerTurn": 800},
		"stake": {"amount": 800},
		"relationshipId": "client|x|bakery-1",
	}
	state.urgent_problems = [problem]
	state.relationship_issue_states = {
		"client|x|bakery-1": {"pendingIssueId": "prob-rev", "issuePressure": 140.0, "roundsSinceIssue": 5},
	}
	UrgentSystem.fail_relationship_deal(state, problem, "walked")
	assert_eq(biz.revenue_per_turn, 19200)
	assert_eq(str(biz.client_state), "at_risk")


func test_relationship_ready_to_close_at_near_ask() -> void:
	var v2 := {"acceptableValue": 364}
	var offer := UrgentSystem.parse_relationship_offer("I can do $550/qtr on this.", 587)
	assert_true(UrgentSystem.relationship_ready_to_close(offer, v2, 587))


func test_parse_bare_number_offer_without_dollar_sign() -> void:
	var offer := UrgentSystem.parse_relationship_offer(
		"I can't afford that much, but I can do 880 if you agree",
		920,
	)
	assert_eq(int(offer.get("totalPrice", 0)), 880)
	assert_true(UrgentSystem.relationship_ready_to_close(offer, {"acceptableValue": 750}, 920))


func test_service_guarantee_offer_is_non_monetary() -> void:
	var problem := {
		"issueType": "deliveryGuarantee",
		"type": "client",
	}
	var offer := UrgentSystem.build_relationship_offer(
		"I offer a written guarantee with 10% free volume if I miss a deadline",
		750,
		"offer",
		{},
		{},
		problem,
	)
	assert_true(bool(offer.get("serviceTermsOnly", false)))
	assert_eq(int(offer.get("totalPrice", 0)), 0)
	assert_true(UrgentSystem.relationship_ready_to_close(offer, {}, 750, problem))


func test_hostile_message_does_not_close_or_reuse_cash() -> void:
	var problem := {"issueType": "deliveryGuarantee", "type": "client"}
	var prior := UrgentSystem.parse_relationship_offer("I can do 700 per quarter", 750)
	var neg := {"playerLastOffer": prior}
	var stance := UrgentSystem.relationship_player_stance(
		"That is a bribe — I will rise my prices 35% for you just to cover it",
		{"intent": "offer", "offer": {"totalPrice": 700}},
	)
	assert_eq(stance, "reject")
	var offer := UrgentSystem.build_relationship_offer(
		"That is a bribe — I will rise my prices 35% for you just to cover it",
		750,
		stance,
		{"intent": "offer", "offer": {"totalPrice": 700}},
		neg,
		problem,
	)
	assert_eq(int(offer.get("totalPrice", 0)), 0)
	assert_false(UrgentSystem.relationship_ready_to_close(offer, {"acceptableValue": 700}, 750, problem))


func test_relationship_ready_to_close_at_full_ask() -> void:
	var v2 := {"acceptableValue": 364}
	var offer := UrgentSystem.parse_relationship_offer("I'll pay the full $587/qtr surcharge.", 587)
	assert_true(UrgentSystem.relationship_ready_to_close(offer, v2, 587))
	assert_eq(int(offer.get("totalPrice", 0)), 587)


func test_fail_delivery_issue_applies_supply_strain() -> void:
	var state := _farm_state()
	var biz := _add_business(state, "bakery", "bakery-1")
	var problem := {
		"id": "prob-supply",
		"type": "supplier",
		"issueType": "deliveryFrequency",
		"businessId": biz.id,
		"connectionId": "grain_to_bakery",
		"flow": "Packaged grain",
		"ask": {"amountPerTurn": 500},
		"stake": {"amount": 500},
		"relationshipId": "supplier|grain_to_bakery|bakery-1",
	}
	state.urgent_problems = [problem]
	var key := "grain_to_bakery:bakery-1"
	UrgentSystem.fail_relationship_deal(state, problem, "walked")
	assert_true(state.relationship_supply_strain.has(key))
	var entry: Dictionary = state.relationship_supply_strain[key]
	assert_eq(float(entry.get("fulfillMult", 0.0)), 0.72)
	assert_gt(int(entry.get("expiresTurn", 0)), state.turn)


func test_null_ai_dialogue_uses_fallback_not_literal_null() -> void:
	const NegSystem := preload("res://core/systems/negotiation_system.gd")
	var state := _farm_state()
	state.negotiation = {"counterparty": {"speciesId": "hen", "npcName": "Test NPC"}}
	var reply := NegSystem._resolve_relationship_seller_dialogue(
		{"dialogue": null, "intent": "question"},
		"counter",
		state,
		{},
		false,
	)
	assert_false(reply.is_empty())
	assert_false(reply.to_lower().contains("null"))
