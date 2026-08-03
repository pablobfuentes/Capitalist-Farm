class_name UrgentSystem
extends RefCounted

const _UpgradeSystem := preload("res://core/systems/upgrade_system.gd")
const _Archetypes := preload("res://core/content/negotiation_archetypes.gd")
const _NpcSpecies := preload("res://core/systems/npc_species_system.gd")
const _Negotiation := preload("res://core/systems/negotiation_system.gd")
const _V2 := preload("res://core/systems/negotiation_v2_engine.gd")
const _V2Data := preload("res://core/systems/negotiation_v2_data.gd")
const _OfferParser := preload("res://core/systems/negotiation_offer_parser.gd")

const CLIENT_ARCHETYPES: Array[String] = ["skeptical_buyer", "relationship_owner"]
const SUPPLIER_ARCHETYPES: Array[String] = ["aggressive_banker", "proud_founder"]

const SERVICE_TERM_ISSUES: Array[String] = [
	"deliveryGuarantee", "qualityCommitment", "volumeCommitment", "contractSecurity", "higherVolume",
]


static func apply_unresolved_rep_penalty(state: RunState) -> void:
	## Ignored urgents: full ask hits the P&L, then reputation sting.
	if state.urgent_problems.is_empty():
		return
	var pending: Array = state.urgent_problems.duplicate(true)
	var n := pending.size()
	for prob_variant in pending:
		if typeof(prob_variant) != TYPE_DICTIONARY:
			continue
		fail_relationship_deal(state, prob_variant as Dictionary, "ignored")
	var rep_loss: int = n * 2
	state.reputation = maxi(0, state.reputation - rep_loss)
	state.run_log.append("%d urgent issue(s) left unresolved — full stakes applied, reputation −%d." % [n, rep_loss])


static func update_relationship_health(state: RunState) -> void:
	if not state.is_capital_farm():
		return
	var rng := SeededRng.new()
	rng.set_rng_seed(state.run_seed + state.turn * 6151)
	var demand_adj := 0
	match str(state.market_state.get("consumerDemand", "stable")):
		"weak": demand_adj = -4
		"strong": demand_adj = 3
	var inflation_adj := -1
	match str(state.market_state.get("inflation", "moderate")):
		"high": inflation_adj = -4
		"low": inflation_adj = 2
	var conf_adj := 0
	match str(state.market_state.get("businessConfidence", "neutral")):
		"contraction": conf_adj = -3
		"expansion": conf_adj = 2

	for biz: BusinessInstance in state.portfolio.businesses:
		if biz.client_state == "":
			biz.client_state = "stable"
		if biz.supplier_state == "":
			biz.supplier_state = "stable"
		var cust_drag: float = -biz.cust_conc * 12.0
		biz.client_health = int(MathUtil.clamp(
			float(biz.client_health) + float(demand_adj) + cust_drag + rng.randf_range(-2.0, 3.0),
			0.0, 100.0,
		))
		biz.supplier_health = int(MathUtil.clamp(
			float(biz.supplier_health) + float(inflation_adj) + float(conf_adj) + rng.randf_range(-2.0, 3.0),
			0.0, 100.0,
		))
		if biz.client_cooldown > 0:
			biz.client_cooldown -= 1
		if biz.supplier_cooldown > 0:
			biz.supplier_cooldown -= 1


static func generate_urgent_problems(state: RunState) -> Array:
	## Legacy RNG path retained for reference; turn pipeline uses RelationshipIssuePressureSystem.
	if not state.is_capital_farm():
		return []
	return []


static func start_urgent_negotiation(state: RunState, problem_id: String) -> Dictionary:
	if not state.negotiation.is_empty() and bool(state.negotiation.get("active", false)):
		return {"ok": false, "error": "Negotiation already in progress"}
	var problem: Dictionary = find_problem(state, problem_id)
	if problem.is_empty():
		return {"ok": false, "error": "Urgent problem not found"}
	var ap: Dictionary = ActionPointsSystem.require(state, 1)
	if not bool(ap.get("ok", false)):
		return ap
	ActionPointsSystem.spend(state, 1)

	var side := str(problem.get("type", "supplier"))
	var biz := _UpgradeSystem.find_business(state, str(problem.get("businessId", "")))
	var business_name := str(problem.get("businessName", ""))
	if business_name.is_empty() and biz != null:
		business_name = biz.name
	if business_name.is_empty():
		business_name = "Your business"

	var cp: Dictionary = (problem.get("counterparty", {}) as Dictionary).duplicate(true)
	if cp.is_empty():
		var rng := SeededRng.new(state.run_seed + problem_id.hash())
		var pool: Array = CLIENT_ARCHETYPES if side == "client" else SUPPLIER_ARCHETYPES
		cp = build_counterparty(pool, business_name, rng)
	cp["role"] = side
	# Ensure community NPC binding (supply-chain counterparty).
	var faux_opp := {
		"templateId": str(problem.get("counterpartyTemplateId", cp.get("templateId", ""))),
		"districtId": state.active_district_id,
		"id": str(problem.get("id", "")),
	}
	CommunityNegotiationBridge.enrich_counterparty(state, cp, faux_opp)
	if str(cp.get("npcName", "")).is_empty():
		cp["npcName"] = str(problem.get("npcName", cp.get("orgName", "Contact")))

	var ask: Dictionary = problem.get("ask", {}) if typeof(problem.get("ask", {})) == TYPE_DICTIONARY else {}
	var accept: Dictionary = problem.get("acceptTerms", {}) if typeof(problem.get("acceptTerms", {})) == TYPE_DICTIONARY else {}
	var ask_amount := int(ask.get("amountPerTurn", (problem.get("stake", {}) as Dictionary).get("amount", 0)))
	if ask_amount <= 0:
		ask_amount = 100
	var ask_statement := str(problem.get("askStatement", ask.get("statement", ""))).strip_edges()
	if ask_statement.is_empty():
		ask_statement = str(problem.get("text", "We need to revise terms."))

	if not cp.has("businessSituation"):
		cp["businessSituation"] = str(problem.get("situationId", ask.get("situationId", "stable_position")))
	if not cp.has("leverageScore"):
		cp["leverageScore"] = 0.55 if str(problem.get("severity", "")) != "concern" else 0.45
	if not cp.has("relationshipMemory"):
		cp["relationshipMemory"] = {
			"trust": cp.get("trust", 0.5),
			"promisesKept": 0,
			"promisesBroken": 0,
			"grievances": [],
		}
	cp["preferredTerms"] = accept.get("preferredTerms", cp.get("preferredTerms", []))
	cp["hiddenInfo"] = str(cp.get("hiddenInfo", "their costs shifted"))
	cp["reservationPrice"] = int(accept.get("acceptableAmount", int(round(float(ask_amount) * 0.62))))
	cp["redLine"] = int(accept.get("hardFloorAmount", int(round(float(ask_amount) * 0.4))))

	var faux_listing := {
		"id": str(problem.get("id", "")),
		"name": business_name,
		"price": ask_amount,
		"templateId": str(problem.get("counterpartyTemplateId", "")),
		"assetType": "relationship",
		"urgencyTag": "cash_pressure" if str(problem.get("severity", "")) == "crisis" else "",
	}
	var v2_profile: Dictionary = _V2.initialize_profile(
		ask_amount,
		cp,
		state,
		faux_listing,
		_V2.profile_seed(state, ask_amount, str(problem.get("id", ""))),
	)
	# Override floors from hidden accept terms (set from the start).
	if not accept.is_empty():
		v2_profile["hardFloor"] = int(accept.get("hardFloorAmount", v2_profile.get("hardFloor", 0)))
		v2_profile["askPrice"] = ask_amount
		# Recalc economics with forced floor while keeping ask.
		v2_profile = _force_relationship_economics(v2_profile, ask_amount, accept)
	v2_profile = CommunityNegotiationBridge.apply_profile_fields(state, cp, v2_profile)
	var personal_adj := int(v2_profile.get("personalRelationshipGaugeAdj", 0))
	var gauge_start := clampi(
		_V2Data.GAUGE_BASE
		+ int(v2_profile.get("reputationGaugeAdj", 0))
		+ int(v2_profile.get("memoryGaugeAdj", 0))
		+ int(v2_profile.get("leverageGaugeAdj", 0))
		+ personal_adj,
		0,
		100,
	)
	v2_profile["gaugeStart"] = gauge_start
	v2_profile["gauge"] = gauge_start
	v2_profile["previousGauge"] = gauge_start
	v2_profile["situationLabel"] = _relationship_situation_label(problem)

	var cp_biz := str(problem.get("counterpartyBusinessName", cp.get("orgName", "Counterparty")))
	var role_label := "Client" if side == "client" else "Supplier"
	var opening := ask_statement
	var reason := str(problem.get("reasonLine", "")).strip_edges()
	if not reason.is_empty() and opening.find(reason) == -1:
		opening = "%s (%s)" % [ask_statement, reason.trim_suffix(".")]

	state.negotiation = {
		"active": true,
		"kind": "relationship",
		"problemId": problem_id,
		"round": 0,
		"maxRounds": 5,
		"intelUnlocked": true,
		"counterparty": cp,
		"v2": v2_profile,
		"context": {
			"price": ask_amount,
			"name": business_name,
			"assetType": "relationship",
			"problem": problem,
			"askStatement": ask_statement,
			"relationshipRole": role_label,
			"counterpartyBusinessName": cp_biz,
			"flow": str(problem.get("flow", cp.get("flow", ""))),
			"issueType": str(problem.get("issueType", "")),
		},
		"acceptTerms": accept,
		"messages": [{
			"role": "seller",
			"speaker": str(cp.get("npcName", "Contact")),
			"text": opening,
		}],
		"readyToClose": false,
		"pendingOffer": null,
		"playerLastOffer": null,
		"playerLastOfferText": "",
		"lastDecision": "",
		"lastUtility": 0.0,
		"economicStatusHint": "Starting ask on the table",
		"aiStatus": "checking",
		"aiModel": "",
		"aiOfflineNoted": false,
		"debugLog": [],
	}
	state.run_log.append("Opened urgent negotiation — %s vs %s" % [business_name, cp_biz])
	return {"ok": true, "state": state, "negotiation": state.negotiation}


static func _force_relationship_economics(profile: Dictionary, ask_amount: int, accept: Dictionary) -> Dictionary:
	var hard_floor := int(accept.get("hardFloorAmount", int(round(float(ask_amount) * 0.4))))
	var acceptable := int(accept.get("acceptableAmount", int(round(float(ask_amount) * 0.62))))
	hard_floor = clampi(hard_floor, 1, ask_amount)
	acceptable = clampi(acceptable, hard_floor, ask_amount)
	profile["askPrice"] = ask_amount
	profile["hardFloor"] = hard_floor
	profile["acceptableValue"] = acceptable
	profile["unlockedDiscount"] = clampf(1.0 - float(acceptable) / maxf(1.0, float(ask_amount)), 0.0, 0.5)
	return profile


static func _relationship_situation_label(problem: Dictionary) -> String:
	var side := str(problem.get("type", ""))
	var issue := RelationshipIssuePressureSystem.issue_type_label(str(problem.get("issueType", "")))
	var flow := str(problem.get("flow", "supply"))
	var role := "Client" if side == "client" else "Supplier"
	return "%s · %s (%s)" % [role, issue, flow]


static func resolve_settled_amount(state: RunState, problem: Dictionary, offer: Dictionary = {}) -> int:
	## $/qtr impact that sticks after negotiation (player-granted share of the ask).
	if typeof(offer) == TYPE_DICTIONARY and bool(offer.get("serviceTermsOnly", false)):
		return 0
	var ask_amt := _ask_amount(problem)
	var settled := 0
	if typeof(offer) == TYPE_DICTIONARY:
		settled = int(offer.get("totalPrice", 0))
	if settled <= 0 and state != null and typeof(state.negotiation.get("pendingOffer")) == TYPE_DICTIONARY:
		var pending: Dictionary = state.negotiation.get("pendingOffer")
		if bool(pending.get("serviceTermsOnly", false)):
			return 0
		settled = int(pending.get("totalPrice", 0))
	return clampi(settled, 0, maxi(ask_amt, settled))


static func _ask_amount(problem: Dictionary) -> int:
	var ask: Dictionary = problem.get("ask", {}) if typeof(problem.get("ask", {})) == TYPE_DICTIONARY else {}
	var amount := int(ask.get("amountPerTurn", 0))
	if amount <= 0:
		var stake: Dictionary = problem.get("stake", {}) if typeof(problem.get("stake", {})) == TYPE_DICTIONARY else {}
		amount = int(stake.get("amount", 0))
	return maxi(0, amount)


static func relationship_ready_to_close(
	offer: Dictionary,
	v2_result: Dictionary,
	ask_amount: int,
	problem: Dictionary = {},
) -> bool:
	## Urgent negotiations close on economics or matching service terms — not gauge patience.
	if not problem.is_empty() and bool(offer.get("serviceTermsOnly", false)):
		return relationship_service_terms_satisfied(offer, problem)
	var total := int(offer.get("totalPrice", 0))
	if total <= 0:
		return false
	var acceptable := int(v2_result.get("acceptableValue", 0))
	if acceptable <= 0 and ask_amount > 0:
		var accept: Dictionary = {}
		acceptable = int(round(float(ask_amount) * 0.55))
	# Met their settlement floor, met the opening ask, or essentially met it.
	if total >= acceptable:
		return true
	if ask_amount > 0 and total >= ask_amount:
		return true
	if ask_amount > 0 and float(total) >= float(ask_amount) * 0.93:
		return true
	return false


static func finalize_relationship_offer(offer: Dictionary, v2_result: Dictionary, ask_amount: int) -> Dictionary:
	var out := offer.duplicate(true) if typeof(offer) == TYPE_DICTIONARY else {}
	var total := int(out.get("totalPrice", 0))
	if total <= 0:
		return out
	var acceptable := int(v2_result.get("acceptableValue", 0))
	if total < acceptable and acceptable > 0:
		out["totalPrice"] = acceptable
		out["cashAtClosing"] = acceptable
	elif ask_amount > 0 and total >= int(round(float(ask_amount) * 0.93)):
		out["totalPrice"] = total
		out["cashAtClosing"] = total
	return out


static func _issue_has_supply_strain(issue_type: String) -> bool:
	return issue_type in [
		"deliveryFrequency", "volumeCommitment", "deliveryGuarantee", "higherVolume",
	]


static func _apply_supply_consequence(
	state: RunState,
	problem: Dictionary,
	full_failure: bool,
	settled_per_turn: int,
) -> void:
	var issue_type := str(problem.get("issueType", ""))
	if not _issue_has_supply_strain(issue_type):
		return
	var side := str(problem.get("type", ""))
	var conn_id := str(problem.get("connectionId", ""))
	var biz_id := str(problem.get("businessId", ""))
	if conn_id.is_empty() or biz_id.is_empty():
		return
	var ask_amt := _ask_amount(problem)
	var flow := str(problem.get("flow", "supply"))
	if full_failure:
		var mult := 0.72
		if issue_type in ["volumeCommitment", "higherVolume"]:
			mult = 0.65
		SynergySystem.apply_relationship_supply_strain(
			state, conn_id, biz_id, mult, 4,
			"%s cut %s deliveries after failed negotiation" % [side, flow],
		)
		state.run_log.append(
			"Supply strain: %s fulfillment on %s cut to %.0f%% for 4 turns." % [
				flow, str(problem.get("businessName", "business")),
				mult * 100.0,
			]
		)
	elif side == "supplier" and ask_amt > 0 and settled_per_turn >= int(round(float(ask_amt) * 0.85)):
		# Paid most of a surcharge ask — keep supply flowing (cost-only outcome).
		pass
	elif settled_per_turn > 0 and ask_amt > 0 and float(settled_per_turn) / float(ask_amt) < 0.7:
		SynergySystem.apply_relationship_supply_strain(
			state, conn_id, biz_id, 0.82, 2,
			"thin settlement on %s terms" % flow,
		)


static func apply_relationship_pnl(
	state: RunState,
	problem: Dictionary,
	settled_per_turn: int,
	full_failure: bool,
) -> Dictionary:
	## Permanently integrate the $/qtr outcome into business revenue or opex.
	var biz := _UpgradeSystem.find_business(state, str(problem.get("businessId", "")))
	if biz == null:
		return {"ok": false, "error": "business_not_found", "deltaRevenue": 0, "deltaCosts": 0}
	var side := str(problem.get("type", ""))
	var ask_amt := _ask_amount(problem)
	var amount := settled_per_turn
	if full_failure:
		amount = ask_amt if ask_amt > 0 else settled_per_turn
	amount = maxi(0, amount)

	var before_rev := biz.revenue_per_turn
	var before_cost := biz.operating_costs
	var delta_rev := 0
	var delta_cost := 0

	if side == "client":
		# Client concessions cut revenue (discount, lost volume, exclusivity cost).
		biz.revenue_per_turn = maxi(0, biz.revenue_per_turn - amount)
		delta_rev = biz.revenue_per_turn - before_rev
		if full_failure:
			biz.client_state = "at_risk"
			biz.client_health = maxi(0, biz.client_health - 8)
			biz.client_cooldown = 2
		else:
			biz.client_state = "stable"
			biz.client_health = mini(100, biz.client_health + 25)
			biz.client_cooldown = 3
	elif side == "supplier":
		# Supplier concessions raise operating costs (price hike, surcharges, cost share).
		biz.operating_costs += amount
		delta_cost = biz.operating_costs - before_cost
		if full_failure:
			biz.supplier_state = "at_risk"
			biz.supplier_health = maxi(0, biz.supplier_health - 8)
			biz.supplier_cooldown = 2
		else:
			biz.supplier_state = "stable"
			biz.supplier_health = mini(100, biz.supplier_health + 25)
			biz.supplier_cooldown = 3
	elif side == "lender":
		var loan_id: String = str(problem.get("loanId", ""))
		for loan_variant in state.loans:
			if typeof(loan_variant) == TYPE_DICTIONARY and str((loan_variant as Dictionary).get("id", "")) == loan_id:
				var loan: Dictionary = loan_variant
				var bump := amount if amount > 0 else int(round(float(loan.get("paymentPerTurn", 0)) * 0.02))
				loan["paymentPerTurn"] = int(loan.get("paymentPerTurn", 0)) + bump
				delta_cost = bump
				break

	_UpgradeSystem.mark_business_care(biz, state.turn)
	biz.marked_value = _UpgradeSystem.estimate_valuation(biz, state)
	_apply_supply_consequence(state, problem, full_failure, amount)

	var profit_before := before_rev - before_cost
	var profit_after := biz.revenue_per_turn - biz.operating_costs
	return {
		"ok": true,
		"businessId": biz.id,
		"businessName": biz.name,
		"side": side,
		"amountPerTurn": amount,
		"deltaRevenue": delta_rev,
		"deltaCosts": delta_cost,
		"profitBefore": profit_before,
		"profitAfter": profit_after,
		"fullFailure": full_failure,
	}


static func resolve_relationship_deal(state: RunState, problem: Dictionary, offer: Dictionary = {}) -> void:
	var settled := resolve_settled_amount(state, problem, offer)
	var pnl: Dictionary = apply_relationship_pnl(state, problem, settled, false)
	var service_only := typeof(offer) == TYPE_DICTIONARY and bool(offer.get("serviceTermsOnly", false))
	if service_only:
		var rid := str(problem.get("relationshipId", ""))
		var states := RelationshipIssuePressureSystem.ensure_states(state)
		if not rid.is_empty() and states.has(rid):
			var st: Dictionary = states[rid]
			st["serviceBuffer"] = float(st.get("serviceBuffer", 0.0)) + 20.0
			states[rid] = st
	var rep_gain: int = 5 if state.has_strategic_edge("relationship_capital") else 4
	state.reputation += rep_gain
	var prob_id: String = str(problem.get("id", ""))
	state.urgent_problems = state.urgent_problems.filter(func(p: Variant) -> bool:
		return typeof(p) != TYPE_DICTIONARY or str((p as Dictionary).get("id", "")) != prob_id
	)
	RelationshipIssuePressureSystem.on_negotiation_resolved(state, problem, true)
	var side := str(pnl.get("side", problem.get("type", "")))
	if service_only:
		state.run_log.append(
			"Locked in service terms with %s — no $/qtr hit, relationship buffer +20. Reputation +%d." % [
				str(pnl.get("businessName", "business")),
				rep_gain,
			]
		)
	elif side == "supplier":
		state.run_log.append(
			"Settled supplier terms at %s — %s opex +%s/qtr (profit %s → %s). Reputation +%d." % [
				str(pnl.get("businessName", "business")),
				MathUtil.fmt_money(int(pnl.get("amountPerTurn", 0))),
				MathUtil.fmt_money(int(pnl.get("deltaCosts", 0))),
				MathUtil.fmt_money(int(pnl.get("profitBefore", 0))),
				MathUtil.fmt_money(int(pnl.get("profitAfter", 0))),
				rep_gain,
			]
		)
	else:
		state.run_log.append(
			"Settled client terms at %s — revenue %+s/qtr (profit %s → %s). Reputation +%d." % [
				str(pnl.get("businessName", "business")),
				MathUtil.fmt_money(int(pnl.get("deltaRevenue", 0))),
				MathUtil.fmt_money(int(pnl.get("profitBefore", 0))),
				MathUtil.fmt_money(int(pnl.get("profitAfter", 0))),
				rep_gain,
			]
		)


static func fail_relationship_deal(state: RunState, problem: Dictionary, reason: String = "walked") -> void:
	## Walk-away / ignore — full opening ask hits the P&L.
	var ask_amt := _ask_amount(problem)
	var pnl: Dictionary = apply_relationship_pnl(state, problem, ask_amt, true)
	var prob_id: String = str(problem.get("id", ""))
	state.urgent_problems = state.urgent_problems.filter(func(p: Variant) -> bool:
		return typeof(p) != TYPE_DICTIONARY or str((p as Dictionary).get("id", "")) != prob_id
	)
	RelationshipIssuePressureSystem.on_negotiation_resolved(state, problem, false)
	var side := str(pnl.get("side", problem.get("type", "")))
	var verb := "Ignored" if reason == "ignored" else "Walked from"
	if side == "supplier":
		state.run_log.append(
			"%s supplier urgency at %s — full ask applied, opex +%s/qtr (profit %s → %s)." % [
				verb,
				str(pnl.get("businessName", "business")),
				MathUtil.fmt_money(int(pnl.get("deltaCosts", 0))),
				MathUtil.fmt_money(int(pnl.get("profitBefore", 0))),
				MathUtil.fmt_money(int(pnl.get("profitAfter", 0))),
			]
		)
	else:
		state.run_log.append(
			"%s client urgency at %s — full ask applied, revenue %+s/qtr (profit %s → %s)." % [
				verb,
				str(pnl.get("businessName", "business")),
				MathUtil.fmt_money(int(pnl.get("deltaRevenue", 0))),
				MathUtil.fmt_money(int(pnl.get("profitBefore", 0))),
				MathUtil.fmt_money(int(pnl.get("profitAfter", 0))),
			]
		)


static func find_problem(state: RunState, problem_id: String) -> Dictionary:
	for prob_variant in state.urgent_problems:
		if typeof(prob_variant) == TYPE_DICTIONARY and str((prob_variant as Dictionary).get("id", "")) == problem_id:
			return prob_variant as Dictionary
	return {}


static func evaluate_relationship_utility(offer: Dictionary, counterparty: Dictionary) -> float:
	var value := 0.0
	value += float(offer.get("priceAdjustment", 0.0)) * -30.0
	value += float(offer.get("concessionSize", 0.0)) * 25.0
	var terms: Array = offer.get("termsOffered", [])
	var preferred: Array = counterparty.get("preferredTerms", [])
	for term_variant in terms:
		var term: String = str(term_variant).to_lower()
		for pref_variant in preferred:
			var pref: String = str(pref_variant).to_lower()
			if pref.split(" ")[0] in term:
				value += 8.0
	value += float(counterparty.get("trust", 0.5)) * 10.0
	value -= (1.0 - float(counterparty.get("riskTolerance", 0.3))) * float(offer.get("riskToCounterparty", 10.0))
	return value


static func relationship_player_stance(message: String, ai_parsed: Dictionary = {}) -> String:
	var lower := message.to_lower().strip_edges()
	var intent := str(ai_parsed.get("intent", "question")).to_lower()
	if intent == "walk" or _relationship_message_is_hostile(lower):
		return "walk" if intent == "walk" else "reject"
	if intent == "accept" and not _relationship_message_is_hostile(lower):
		return "accept"
	if _message_offers_cash_payment(message) or _message_offers_service_terms(lower):
		return "offer"
	if intent == "offer" and (_message_offers_cash_payment(message) or _message_offers_service_terms(lower)):
		return "offer"
	return "question"


static func relationship_service_terms_satisfied(offer: Dictionary, problem: Dictionary) -> bool:
	var issue := str(problem.get("issueType", ""))
	if issue not in SERVICE_TERM_ISSUES:
		return false
	var term_blob := " ".join(PackedStringArray(offer.get("termsOffered", []))).to_lower()
	match issue:
		"deliveryGuarantee", "qualityCommitment":
			return "service guarantee" in term_blob or "guarantee" in term_blob
		"volumeCommitment", "higherVolume":
			return "volume commitment" in term_blob
		"contractSecurity", "exclusiveTerritory":
			return "volume commitment" in term_blob or "exclusiv" in term_blob
	return false


static func build_relationship_offer(
	message: String,
	ask_amount: int,
	stance: String,
	ai_parsed: Dictionary,
	negotiation: Dictionary,
	problem: Dictionary,
) -> Dictionary:
	if stance == "accept":
		var last: Variant = negotiation.get("playerLastOffer")
		if last is Dictionary:
			var last_offer: Dictionary = last
			if int(last_offer.get("totalPrice", 0)) > 0 or bool(last_offer.get("serviceTermsOnly", false)):
				return last_offer.duplicate(true)
	var offer := parse_relationship_offer(message, ask_amount)
	if stance in ["reject", "question"]:
		offer["totalPrice"] = 0
		offer["cashAtClosing"] = 0
		offer["concessionSize"] = 0.0
		offer["serviceTermsOnly"] = false
		return offer
	if stance == "offer" and str(ai_parsed.get("intent", "")) == "offer":
		if ai_parsed.get("offer") is Dictionary and _message_offers_cash_payment(message):
			var ai_offer: Dictionary = ai_parsed["offer"]
			var ai_total := int(ai_offer.get("totalPrice", 0))
			if ai_total > 0:
				offer["totalPrice"] = ai_total
				offer["cashAtClosing"] = int(ai_offer.get("cashAtClosing", ai_total))
				if ask_amount > 0:
					offer["concessionSize"] = clampf(float(ai_total) / float(ask_amount), 0.05, 1.0)
	if stance == "offer":
		var built: Dictionary = _OfferParser.build_player_offer_from_message(message, ai_parsed, negotiation)
		if built.get("offer") is Dictionary and _message_offers_cash_payment(message):
			var parsed_total := int((built["offer"] as Dictionary).get("totalPrice", 0))
			if parsed_total > int(offer.get("totalPrice", 0)):
				offer = (built["offer"] as Dictionary).duplicate(true)
				if ask_amount > 0:
					offer["concessionSize"] = clampf(float(parsed_total) / float(ask_amount), 0.05, 1.0)
	if relationship_service_terms_satisfied(offer, problem) and int(offer.get("totalPrice", 0)) <= 0:
		offer["serviceTermsOnly"] = true
		offer["totalPrice"] = 0
		offer["cashAtClosing"] = 0
	return offer


static func parse_relationship_offer(message: String, ask_amount: int = 0) -> Dictionary:
	var lower := message.to_lower()
	var terms: Array[String] = []
	if "guarantee" in lower or "service" in lower or "sla" in lower or "deadline" in lower:
		terms.append("service guarantee")
	if "payment" in lower or "flexible" in lower or "net-" in lower:
		terms.append("flexible payment")
	if "volume" in lower or "commitment" in lower or "exclusiv" in lower:
		terms.append("volume commitment")
	if ("index" in lower or "price" in lower) and not _percent_is_non_payment_context(lower):
		terms.append("indexed pricing")
	if "covenant" in lower or "collateral" in lower:
		terms.append("collateral")

	var service_only := _message_offers_service_terms(lower) and not _message_offers_cash_payment(message)
	var offer_amount := 0 if service_only else _extract_relationship_offer_amount(message, ask_amount)
	var concession: float = 0.0
	if offer_amount > 0 and ask_amount > 0:
		concession = clampf(float(offer_amount) / float(ask_amount), 0.05, 1.0)
	elif not service_only:
		if "accept" in lower and ("term" in lower or "deal" in lower or "ok" in lower or "agree" in lower):
			concession = 0.95
		elif "accept your" in lower or "agree to your" in lower or "full ask" in lower or "pay the" in lower:
			concession = 0.95
		elif "halfway" in lower or "meet you" in lower or "split" in lower or "meet in the middle" in lower:
			concession = 0.55
		elif "partnership" in lower or ("deal" in lower and "no deal" not in lower):
			concession = 0.45
		elif "help" in lower or "work with" in lower or ("can do" in lower and _message_offers_cash_payment(message)) or "will pay" in lower:
			concession = 0.3
		elif "maybe" in lower or "consider" in lower:
			concession = 0.15

		var pct_match := _extract_percent(lower)
		if pct_match > 0.0 and ask_amount > 0 and not _percent_is_non_payment_context(lower):
			concession = maxf(concession, clampf(pct_match / 0.12, 0.1, 1.0))

	var total_price := offer_amount
	if total_price <= 0 and not service_only and ask_amount > 0:
		total_price = int(round(float(ask_amount) * clampf(concession, 0.0, 1.0)))

	return {
		"termsOffered": terms,
		"concessionSize": concession,
		"priceAdjustment": -concession,
		"riskToCounterparty": 5,
		"totalPrice": total_price,
		"cashAtClosing": total_price,
		"serviceTermsOnly": service_only,
	}


static func _relationship_message_is_hostile(lower: String) -> bool:
	return RegEx.create_from_string(
		"\\b(bribe|extort|refuse|won't pay|will not pay|not paying|no way|unacceptable|threat|retaliat|"
		+ "raise my price|raise your price|raise prices|rise my price|rise prices|rise your price|"
		+ "increase my price|increase your price|price gouge|"
		+ "forget it|hell no|absolutely not|take a hike|not a chance)\\b"
	).search(lower) != null


static func _message_offers_service_terms(lower: String) -> bool:
	return (
		"guarantee" in lower or "sla" in lower or "warrant" in lower or "deadline" in lower
		or ("free" in lower and "volume" in lower)
	)


static func _message_offers_cash_payment(message: String) -> bool:
	if _relationship_message_is_hostile(message.to_lower()):
		return false
	if not (_OfferParser.is_purchase_intent_text(message) or _OfferParser.message_has_offer_figures(message)):
		return false
	return _extract_relationship_offer_amount(message, 0) > 0


static func _percent_is_non_payment_context(lower: String) -> bool:
	return (
		"volume" in lower or "free" in lower or "guarantee" in lower or "sla" in lower
		or "deadline" in lower or "rise" in lower or "raise" in lower or "increase" in lower
		or "bribe" in lower or "threat" in lower or "pull" in lower
	)


static func _extract_relationship_offer_amount(message: String, ask_amount: int = 0) -> int:
	var amounts := _OfferParser.parse_offer_amounts_from_text(message, ask_amount)
	var parsed_total := int(amounts.get("totalPrice", 0))
	if parsed_total > 0:
		return parsed_total
	if _OfferParser.is_purchase_intent_text(message) or _OfferParser.message_has_offer_figures(message):
		var nums: Array = _OfferParser.extract_numbers_from_text(message)
		if nums.size() == 1:
			return int(nums[0])
		if nums.size() >= 2 and ask_amount > 0:
			for n in nums:
				var val := int(n)
				if val != ask_amount and val >= 50:
					return val
			return int(nums[0])
	return _extract_money(message.to_lower())


static func _extract_percent(lower: String) -> float:
	var re := RegEx.new()
	if re.compile("(\\d+(?:\\.\\d+)?)\\s*%") != OK:
		return 0.0
	var m := re.search(lower)
	if m == null:
		return 0.0
	return clampf(float(m.get_string(1)) / 100.0, 0.0, 1.0)


static func _extract_money(lower: String) -> int:
	var re := RegEx.new()
	if re.compile("\\$\\s*([0-9][0-9,]*(?:\\.[0-9]+)?)") != OK:
		return 0
	var m := re.search(lower)
	if m == null:
		return 0
	var raw := m.get_string(1).replace(",", "")
	return int(round(float(raw)))


static func build_counterparty(pool: Array, org_name: String, rng: SeededRng) -> Dictionary:
	var arch_id: String = pool[rng.randi_range(0, pool.size() - 1)]
	var cp: Dictionary = _Archetypes.build_counterparty(arch_id, 0, rng)
	cp["role"] = "client" if pool == CLIENT_ARCHETYPES else "supplier"
	cp["orgName"] = org_name
	cp["reservationPrice"] = 0
	cp["redLine"] = 0
	cp["preferredTerms"] = ["service guarantee", "flexible payment"] if cp["role"] == "client" else ["volume commitment", "faster payment"]
	cp["hiddenInfo"] = "they received a competing offer" if cp["role"] == "client" else "their own input costs rose"
	return cp


static func _build_counterparty(pool: Array, org_name: String, rng: SeededRng) -> Dictionary:
	return build_counterparty(pool, org_name, rng)


static func _make_problem(
	prob_type: String,
	biz: BusinessInstance,
	cp: Dictionary,
	stake_amount: int,
	autopilot_label: String,
	neglect_turns: int,
	rng: SeededRng,
) -> Dictionary:
	var escalation: String = biz.client_state if prob_type == "client" else biz.supplier_state
	var text: String = _NpcSpecies.urgent_problem_text(prob_type, {
		"businessName": biz.name,
		"npcName": str(cp.get("npcName", "Contact")),
		"stakeAmount": stake_amount,
		"escalation": escalation,
	})
	return {
		"id": MathUtil.uid(),
		"type": prob_type,
		"businessId": biz.id,
		"businessTemplateId": biz.template_id,
		"businessName": biz.name,
		"autopilotLabel": autopilot_label,
		"neglectTurns": neglect_turns,
		"text": text,
		"stake": {
			"kind": "revenue" if prob_type == "client" else "cost",
			"amount": stake_amount,
			"label": "relationship at risk",
		},
		"counterparty": cp,
	}
