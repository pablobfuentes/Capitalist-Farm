class_name UrgentSystem
extends RefCounted

const _UpgradeSystem := preload("res://core/systems/upgrade_system.gd")
const _Archetypes := preload("res://core/content/negotiation_archetypes.gd")
const _NpcSpecies := preload("res://core/systems/npc_species_system.gd")
const _Negotiation := preload("res://core/systems/negotiation_system.gd")

const CLIENT_ARCHETYPES: Array[String] = ["skeptical_buyer", "relationship_owner"]
const SUPPLIER_ARCHETYPES: Array[String] = ["aggressive_banker", "proud_founder"]


static func apply_unresolved_rep_penalty(state: RunState) -> void:
	if state.urgent_problems.is_empty():
		return
	var rep_loss: int = state.urgent_problems.size() * 2
	state.reputation = maxi(0, state.reputation - rep_loss)
	state.run_log.append("%d urgent issue(s) left unresolved — reputation −%d." % [state.urgent_problems.size(), rep_loss])


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
	if not state.is_capital_farm():
		return []
	var cfg: Dictionary = GameMode.config(state.mode)
	var rng := SeededRng.new()
	rng.set_rng_seed(state.run_seed + state.turn * 8282 + state.portfolio.businesses.size())
	var problems: Array = []
	var urgent_freq: float = float(cfg.get("urgent_freq_mult", 1.0))

	for biz: BusinessInstance in state.portfolio.businesses:
		if biz.template_id == "":
			continue
		if biz.acquired_turn <= 0:
			biz.acquired_turn = state.turn
			biz.last_care_turn = state.turn
		if biz.cust_conc <= 0.0:
			biz.cust_conc = 0.12
		var care_mult: float = biz.crisis_mult
		var ap_mult: float = _UpgradeSystem.urgent_freq_mult_for_business(biz)
		var neglect_mult: float = SynergySystem.neglect_urgent_mult(biz, state.turn)
		var stake_mult: float = SynergySystem.urgent_stake_mult(biz.template_id)
		var neglect_turns: int = SynergySystem.turns_since_care(biz, state.turn)
		var autopilot_label: String = SynergySystem.autopilot_burden_label(biz.template_id)

		if biz.client_cooldown <= 0:
			var client_chance: float = MathUtil.clamp((100.0 - float(biz.client_health)) / 100.0, 0.0, 1.0)
			client_chance *= 0.35 * urgent_freq * care_mult * ap_mult * neglect_mult
			if rng.randf() < client_chance:
				if biz.client_state == "at_risk":
					var loss: int = int(round(float(biz.revenue_per_turn) * biz.cust_conc))
					biz.revenue_per_turn = maxi(0, biz.revenue_per_turn - loss)
					biz.client_state = "stable"
					biz.client_health = mini(100, biz.client_health + 10)
					biz.client_cooldown = 3
					state.run_log.append("%s lost its at-risk client — revenue drops %s/qtr, permanently." % [biz.name, MathUtil.fmt_money(loss)])
				else:
					biz.client_state = "strained" if biz.client_state == "stable" else "at_risk"
					biz.client_health = maxi(0, biz.client_health - 15)
					biz.client_cooldown = 2
					var stake_amount: int = int(round(float(biz.revenue_per_turn) * biz.cust_conc * (1.0 if biz.client_state == "at_risk" else 0.55) * stake_mult))
					var cp: Dictionary = _build_counterparty(CLIENT_ARCHETYPES, biz.name, rng)
					problems.append(_make_problem("client", biz, cp, stake_amount, autopilot_label, neglect_turns, rng))

		if biz.supplier_cooldown <= 0:
			var supplier_chance: float = MathUtil.clamp((100.0 - float(biz.supplier_health)) / 100.0, 0.0, 1.0)
			supplier_chance *= 0.3 * urgent_freq * care_mult * ap_mult * neglect_mult
			if rng.randf() < supplier_chance:
				if biz.supplier_state == "at_risk":
					var hike: int = int(round(float(biz.operating_costs) * rng.randf_range(0.10, 0.20)))
					biz.operating_costs += hike
					biz.supplier_state = "stable"
					biz.supplier_health = mini(100, biz.supplier_health + 10)
					biz.supplier_cooldown = 3
					state.run_log.append("%s supplier situation went unresolved — operating costs rise %s/qtr, permanently." % [biz.name, MathUtil.fmt_money(hike)])
				else:
					biz.supplier_state = "strained" if biz.supplier_state == "stable" else "at_risk"
					biz.supplier_health = maxi(0, biz.supplier_health - 15)
					biz.supplier_cooldown = 2
					var stake_amount: int = int(round(float(biz.operating_costs) * rng.randf_range(0.10, 0.20) * (1.0 if biz.supplier_state == "at_risk" else 0.55) * stake_mult))
					var cp: Dictionary = _build_counterparty(SUPPLIER_ARCHETYPES, biz.name, rng)
					problems.append(_make_problem("supplier", biz, cp, stake_amount, autopilot_label, neglect_turns, rng))

	return problems


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
	var cp: Dictionary = (problem.get("counterparty", {}) as Dictionary).duplicate(true)
	if cp.is_empty():
		cp = _Archetypes.build_counterparty("relationship_owner", 0, SeededRng.new(state.run_seed + problem_id.hash()))
		cp["role"] = "client" if str(problem.get("type", "")) == "client" else "supplier"
	state.negotiation = {
		"active": true,
		"kind": "relationship",
		"problemId": problem_id,
		"round": 0,
		"maxRounds": 5,
		"intelUnlocked": true,
		"counterparty": cp,
		"context": {
			"price": 0,
			"name": str(problem.get("text", "Relationship issue")),
			"assetType": "relationship",
			"problem": problem,
		},
		"messages": [{
			"who": "counterparty",
			"name": str(cp.get("npcName", "Contact")),
			"text": str(problem.get("text", "We need to talk about terms.")),
		}],
		"readyToClose": false,
		"pendingOffer": null,
	}
	state.run_log.append("Opened urgent negotiation — %s" % str(problem.get("text", "")).substr(0, 60))
	return {"ok": true, "state": state, "negotiation": state.negotiation}


static func resolve_relationship_deal(state: RunState, problem: Dictionary, _offer: Dictionary = {}) -> void:
	var prob_type: String = str(problem.get("type", ""))
	var biz := _UpgradeSystem.find_business(state, str(problem.get("businessId", "")))
	if prob_type == "client" and biz != null:
		biz.client_state = "stable"
		biz.revenue_per_turn = int(round(float(biz.revenue_per_turn) * 0.97))
		biz.client_health = mini(100, biz.client_health + 25)
		biz.client_cooldown = 3
	elif prob_type == "supplier" and biz != null:
		biz.supplier_state = "stable"
		biz.operating_costs = int(round(float(biz.operating_costs) * 1.03))
		biz.supplier_health = mini(100, biz.supplier_health + 25)
		biz.supplier_cooldown = 3
	elif prob_type == "lender":
		var loan_id: String = str(problem.get("loanId", ""))
		for loan_variant in state.loans:
			if typeof(loan_variant) == TYPE_DICTIONARY and str((loan_variant as Dictionary).get("id", "")) == loan_id:
				var loan: Dictionary = loan_variant
				loan["paymentPerTurn"] = int(round(float(loan.get("paymentPerTurn", 0)) * 1.02))
				break
	if biz != null:
		_UpgradeSystem.mark_business_care(biz, state.turn)
	var rep_gain: int = 5 if state.has_strategic_edge("relationship_capital") else 4
	state.reputation += rep_gain
	var prob_id: String = str(problem.get("id", ""))
	state.urgent_problems = state.urgent_problems.filter(func(p: Variant) -> bool:
		return typeof(p) != TYPE_DICTIONARY or str((p as Dictionary).get("id", "")) != prob_id
	)
	state.run_log.append("Resolved relationship issue — reputation +%d." % rep_gain)


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


static func parse_relationship_offer(message: String) -> Dictionary:
	var lower := message.to_lower()
	var terms: Array[String] = []
	if "guarantee" in lower or "service" in lower:
		terms.append("service guarantee")
	if "payment" in lower or "flexible" in lower:
		terms.append("flexible payment")
	if "volume" in lower or "commitment" in lower:
		terms.append("volume commitment")
	if "covenant" in lower or "collateral" in lower:
		terms.append("collateral")
	var concession: float = 0.0
	if "commit" in lower or "guarantee" in lower or "partnership" in lower:
		concession = 0.35
	elif "help" in lower or "work with" in lower:
		concession = 0.2
	return {
		"termsOffered": terms,
		"concessionSize": concession,
		"priceAdjustment": -concession,
		"riskToCounterparty": 5,
	}


static func _build_counterparty(pool: Array, org_name: String, rng: SeededRng) -> Dictionary:
	var arch_id: String = pool[rng.randi_range(0, pool.size() - 1)]
	var cp: Dictionary = _Archetypes.build_counterparty(arch_id, 0, rng)
	cp["role"] = "client" if pool == CLIENT_ARCHETYPES else "supplier"
	cp["reservationPrice"] = 0
	cp["redLine"] = 0
	cp["preferredTerms"] = ["service guarantee", "flexible payment"] if cp["role"] == "client" else ["volume commitment", "faster payment"]
	cp["hiddenInfo"] = "they received a competing offer" if cp["role"] == "client" else "their own input costs rose"
	return cp


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
