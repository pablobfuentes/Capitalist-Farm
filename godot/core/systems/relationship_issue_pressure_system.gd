class_name RelationshipIssuePressureSystem
extends RefCounted

## Deterministic supplier/client issue pressure (docs/Supplier_Client_Issue_Pressure_Implementation.docx).
## Replaces RNG urgent generation while still emitting `urgent_problems` for existing UI/negotiation.

const _UpgradeSystem := preload("res://core/systems/upgrade_system.gd")
const _Urgent := preload("res://core/systems/urgent_system.gd")
const _NpcSpecies := preload("res://core/systems/npc_species_system.gd")

const BASE_PRESSURE := 16
const TRIGGER_THRESHOLD := 100
const MANDATORY_ROUNDS := 5
const PRESSURE_AFTER_SUCCESS := 20
const PRESSURE_AFTER_FAILURE := 35
const SERVICE_PREVENTION_PRESSURE_FRAC := 0.40
const REQUIRED_BUFFER_BASE := 30
const MAX_NORMAL_EVENTS := 1
const MAX_SEVERE_EVENTS := 2
const MAX_PENDING_SHOWN := 3

const ISSUE_SUPPLIER := [
	"priceIncrease", "paymentTerms", "volumeCommitment",
	"deliveryFrequency", "contractSecurity", "costSharing",
]
const ISSUE_CLIENT := [
	"priceReduction", "deliveryGuarantee", "qualityCommitment",
	"higherVolume", "flexiblePayment", "exclusiveTerritory",
]


static func ensure_states(state: RunState) -> Dictionary:
	if state == null:
		return {}
	if typeof(state.relationship_issue_states) != TYPE_DICTIONARY:
		state.relationship_issue_states = {}
	return state.relationship_issue_states


## End-of-turn: accumulate pressure, trigger issues, fill urgent_problems.
static func process_turn(state: RunState) -> Array:
	if state == null or not state.is_capital_farm():
		return []
	var states := ensure_states(state)
	var active_ids: Dictionary = {}
	var candidates: Array = []
	var util_map: Dictionary = SynergySystem.compute_supplier_utilization(state)

	for rel in _enumerate_relationships(state):
		var rel_id := str(rel.get("relationshipId", ""))
		if rel_id.is_empty():
			continue
		active_ids[rel_id] = true
		var st: Dictionary = _ensure_rel_state(states, rel_id)
		if not str(st.get("pendingIssueId", "")).is_empty():
			# Unresolved pending issue: keep pressure warm, do not spawn a duplicate.
			st["roundsSinceIssue"] = int(st.get("roundsSinceIssue", 0)) + 1
			_refill_service_buffer(state, rel, st)
			continue

		st["roundsSinceIssue"] = int(st.get("roundsSinceIssue", 0)) + 1
		var breakdown := calculate_pressure_breakdown(state, rel, util_map)
		st["lastPressureBreakdown"] = breakdown
		st["issuePressure"] = float(st.get("issuePressure", 0.0)) + float(breakdown.get("totalGain", 0.0))
		_refill_service_buffer(state, rel, st)

		var needs := float(st.get("issuePressure", 0.0)) >= float(TRIGGER_THRESHOLD) \
			or int(st.get("roundsSinceIssue", 0)) >= MANDATORY_ROUNDS
		if not needs:
			continue

		var prevention := evaluate_service_protection(state, rel, st)
		if bool(prevention.get("prevented", false)):
			_apply_prevention(state, st, prevention)
			continue
		if bool(prevention.get("downgraded", false)):
			st["_downgradeNext"] = true
			var half_buf := float(prevention.get("requiredBuffer", REQUIRED_BUFFER_BASE))
			st["serviceBuffer"] = maxf(0.0, float(st.get("serviceBuffer", 0.0)) - half_buf)
			state.run_log.append(str(prevention.get("message", "Customer care softened an issue.")))

		var issue := build_highest_scoring_issue(state, rel, st)
		if issue.is_empty():
			continue
		candidates.append(issue)

	# Drop stale relationship keys no longer active.
	var drop: Array[String] = []
	for key_variant in states.keys():
		var key := str(key_variant)
		if not active_ids.has(key) and str((states[key] as Dictionary).get("pendingIssueId", "")).is_empty():
			drop.append(key)
	for key in drop:
		states.erase(key)

	var presented := _present_queue(state, candidates)
	# Mark only presented issues as pending; record issue history only for shown events.
	var presented_ids: Dictionary = {}
	for p_variant in presented:
		var p: Dictionary = p_variant
		presented_ids[str(p.get("id", ""))] = true
		var rid := str(p.get("relationshipId", ""))
		if rid.is_empty() or not states.has(rid):
			continue
		var st_p: Dictionary = states[rid]
		st_p["pendingIssueId"] = str(p.get("id", ""))
		st_p["lastIssueType"] = str(p.get("issueType", ""))
		st_p["lastReviewedRound"] = state.turn
		var recent: Array = st_p.get("recentIssueTypes", [])
		if typeof(recent) != TYPE_ARRAY:
			recent = []
		recent.append(str(p.get("issueType", "")))
		if recent.size() > 4:
			recent = recent.slice(recent.size() - 4)
		st_p["recentIssueTypes"] = recent

	# Carry unresolved problems from last turn that are still pending.
	var carry: Array = []
	for prev_variant in state.urgent_problems:
		if typeof(prev_variant) != TYPE_DICTIONARY:
			continue
		var prev: Dictionary = prev_variant
		var pid := str(prev.get("id", ""))
		if pid.is_empty() or presented_ids.has(pid):
			continue
		for st_variant in states.values():
			if typeof(st_variant) != TYPE_DICTIONARY:
				continue
			if str((st_variant as Dictionary).get("pendingIssueId", "")) == pid:
				carry.append(prev)
				presented_ids[pid] = true
				break
	for p in presented:
		carry.append(p)
	if carry.size() > MAX_PENDING_SHOWN:
		carry = carry.slice(0, MAX_PENDING_SHOWN)
	apply_presented_escalation(state, presented)
	return carry


static func calculate_pressure_breakdown(state: RunState, rel: Dictionary, util_map: Dictionary = {}) -> Dictionary:
	var biz: BusinessInstance = rel.get("business")
	var side := str(rel.get("side", "client")) # client = client-initiated vs our biz; supplier = supplier-initiated
	var reasons: Array = []
	var base := float(BASE_PRESSURE)
	reasons.append({"code": "base", "label": "Base commercial attention", "value": base, "sourceVariable": "basePressure"})

	var health := float(biz.client_health if side == "client" else biz.supplier_health)
	var operational := _operational_risk(biz, side, util_map, reasons)
	var financial := _financial_risk(state, biz, side, reasons)
	var relationship := _relationship_risk(biz, side, reasons)
	var dependency := _dependency_risk(biz, reasons)
	var mitigation := _service_mitigation(biz, reasons)
	var total := base + operational + financial + relationship + dependency - mitigation
	# Doc: mitigation can soften but stable unmanaged links still climb.
	total = maxf(total, 4.0)
	return {
		"base": base,
		"operational": operational,
		"financial": financial,
		"relationship": relationship,
		"dependency": dependency,
		"serviceMitigation": mitigation,
		"totalGain": total,
		"reasons": reasons,
		"health": health,
	}


static func evaluate_service_protection(state: RunState, rel: Dictionary, st: Dictionary) -> Dictionary:
	var biz: BusinessInstance = rel.get("business")
	var required := REQUIRED_BUFFER_BASE
	var pressure := float(st.get("issuePressure", 0.0))
	if pressure >= 150.0:
		required += 30
	elif pressure >= 120.0:
		required += 15
	var buffer := float(st.get("serviceBuffer", 0.0))
	var mandatory := int(st.get("roundsSinceIssue", 0)) >= MANDATORY_ROUNDS
	if buffer >= float(required) and (mandatory or pressure >= float(TRIGGER_THRESHOLD)):
		return {
			"prevented": true,
			"requiredBuffer": required,
			"downgraded": false,
			"message": "Your account manager resolved a concern at %s before it became a negotiation." % biz.name,
		}
	if buffer >= float(required) * 0.5 and pressure >= 120.0:
		return {
			"prevented": false,
			"downgraded": true,
			"requiredBuffer": int(required * 0.5),
			"message": "Customer care softened an escalating issue at %s." % biz.name,
		}
	return {"prevented": false, "downgraded": false, "requiredBuffer": required}


static func build_highest_scoring_issue(state: RunState, rel: Dictionary, st: Dictionary) -> Dictionary:
	var biz: BusinessInstance = rel.get("business")
	var side := str(rel.get("side", "client"))
	var catalog: Array = ISSUE_CLIENT if side == "client" else ISSUE_SUPPLIER
	var scores: Dictionary = _score_issue_types(state, rel, st)
	var best_type := ""
	var best_score := -INF
	for issue_type_variant in catalog:
		var issue_type := str(issue_type_variant)
		var score := float(scores.get(issue_type, 0.0))
		score += _repetition_penalty(st, issue_type)
		if score > best_score:
			best_score = score
			best_type = issue_type
	if best_type.is_empty():
		best_type = "deliveryComplaint" if side == "client" else "priceIncrease"

	var pressure := float(st.get("issuePressure", 0.0))
	var severity := "concern"
	if pressure >= 150.0:
		severity = "crisis"
	elif pressure >= 120.0:
		severity = "urgent"
	if bool(st.get("_downgradeNext", false)):
		if severity == "crisis":
			severity = "urgent"
		elif severity == "urgent":
			severity = "concern"
		st["_downgradeNext"] = false

	var rng := SeededRng.new()
	rng.set_rng_seed(state.run_seed + state.turn * 9109 + str(rel.get("relationshipId", "")).hash())
	var escalation := "strained" if severity == "concern" else "at_risk"
	var ask: Dictionary = _build_quantified_ask(state, rel, best_type, severity, rng)
	var stake_amount := int(ask.get("amountPerTurn", 0))
	var cp: Dictionary = _build_supply_chain_counterparty(state, rel, side, rng)
	var accept_terms: Dictionary = _build_hidden_accept_terms(ask, severity, rng)

	var top_reasons: Array = []
	var breakdown: Dictionary = st.get("lastPressureBreakdown", {})
	for reason_variant in breakdown.get("reasons", []):
		if typeof(reason_variant) != TYPE_DICTIONARY:
			continue
		var reason: Dictionary = reason_variant
		if str(reason.get("code", "")) in ["base", "service"]:
			continue
		if float(reason.get("value", 0.0)) == 0.0:
			continue
		top_reasons.append(reason)
		if top_reasons.size() >= 3:
			break
	if top_reasons.is_empty():
		top_reasons.append({
			"code": "review",
			"label": "Scheduled commercial review",
			"value": float(st.get("roundsSinceIssue", 0)),
			"sourceVariable": "roundsSinceIssue",
		})

	var reason_line := _player_facing_reason(top_reasons, best_type, side)
	var flow := str(rel.get("flow", "supply"))
	var cp_biz_name := str(cp.get("orgName", "their operation"))
	var npc_name := str(cp.get("npcName", "Contact"))
	var ask_statement := str(ask.get("statement", ""))
	var text := ask_statement
	if not reason_line.is_empty():
		text = "%s %s" % [ask_statement, reason_line]

	var problem := {
		"id": MathUtil.uid(),
		"type": side,
		"issueType": best_type,
		"severity": severity,
		"relationshipId": str(rel.get("relationshipId", "")),
		"connectionId": str(rel.get("connectionId", "")),
		"businessId": biz.id,
		"businessTemplateId": biz.template_id,
		"businessName": biz.name,
		"counterpartyTemplateId": str(rel.get("counterpartyTemplateId", "")),
		"counterpartyBusinessName": cp_biz_name,
		"flow": flow,
		"autopilotLabel": SynergySystem.autopilot_burden_label(biz.template_id),
		"neglectTurns": SynergySystem.turns_since_care(biz, state.turn),
		"text": text,
		"askStatement": ask_statement,
		"reasonLine": reason_line,
		"topReasons": top_reasons,
		"pressure": pressure,
		"score": best_score,
		"mandatoryReview": int(st.get("roundsSinceIssue", 0)) >= MANDATORY_ROUNDS,
		"ask": ask,
		"acceptTerms": accept_terms,
		"stake": {
			"kind": "revenue" if side == "client" else "cost",
			"amount": stake_amount,
			"label": str(ask.get("stakeLabel", "relationship at risk")),
			"pct": float(ask.get("pct", 0.0)),
		},
		"counterparty": cp,
		"escalation": escalation,
		"situationId": str(ask.get("situationId", "stable_position")),
	}
	# Keep npc name on the problem for UI summaries.
	problem["npcName"] = npc_name
	return problem


static func apply_presented_escalation(state: RunState, problems: Array) -> void:
	for prob_variant in problems:
		if typeof(prob_variant) != TYPE_DICTIONARY:
			continue
		var prob: Dictionary = prob_variant
		var biz := _UpgradeSystem.find_business(state, str(prob.get("businessId", "")))
		if biz == null:
			continue
		var side := str(prob.get("type", ""))
		var severity := str(prob.get("severity", "concern"))
		var escalation := str(prob.get("escalation", "strained" if severity == "concern" else "at_risk"))
		var health_hit := 10 if severity == "concern" else 18
		if side == "client":
			biz.client_state = escalation
			biz.client_health = maxi(0, biz.client_health - health_hit)
			biz.client_cooldown = 2
		elif side == "supplier":
			biz.supplier_state = escalation
			biz.supplier_health = maxi(0, biz.supplier_health - health_hit)
			biz.supplier_cooldown = 2


static func on_negotiation_resolved(state: RunState, problem: Dictionary, success: bool) -> void:
	var states := ensure_states(state)
	var rel_id := str(problem.get("relationshipId", ""))
	if rel_id.is_empty() or not states.has(rel_id):
		return
	var st: Dictionary = states[rel_id]
	st["issuePressure"] = float(PRESSURE_AFTER_SUCCESS if success else PRESSURE_AFTER_FAILURE)
	st["roundsSinceIssue"] = 0
	st["pendingIssueId"] = ""
	if success:
		st["consecutiveIssues"] = 0
	else:
		st["consecutiveIssues"] = int(st.get("consecutiveIssues", 0)) + 1
	states[rel_id] = st


static func business_has_pending_issue(state: RunState, business_id: String) -> bool:
	return not pending_problem_for_business(state, business_id).is_empty()


static func pending_problem_for_business(state: RunState, business_id: String) -> Dictionary:
	if state == null or business_id.is_empty():
		return {}
	for prob_variant in state.urgent_problems:
		if typeof(prob_variant) != TYPE_DICTIONARY:
			continue
		var prob: Dictionary = prob_variant
		if str(prob.get("businessId", "")) == business_id:
			return prob
	return {}


static func issue_type_label(issue_type: String) -> String:
	match issue_type:
		"priceIncrease":
			return "Price increase"
		"paymentTerms":
			return "Payment terms"
		"volumeCommitment":
			return "Volume commitment"
		"deliveryFrequency":
			return "Delivery frequency"
		"contractSecurity":
			return "Contract security"
		"costSharing":
			return "Cost sharing"
		"priceReduction":
			return "Price reduction"
		"deliveryGuarantee":
			return "Delivery guarantee"
		"qualityCommitment":
			return "Quality commitment"
		"higherVolume":
			return "Higher volume"
		"flexiblePayment":
			return "Flexible payment"
		"exclusiveTerritory":
			return "Exclusive territory"
		_:
			return issue_type.capitalize() if not issue_type.is_empty() else "Commercial review"


static func stake_consequence_line(problem: Dictionary) -> String:
	var ask: Dictionary = problem.get("ask", {}) if typeof(problem.get("ask", {})) == TYPE_DICTIONARY else {}
	if not ask.is_empty() and not str(ask.get("stakeLabel", "")).is_empty():
		return str(ask.get("stakeLabel", ""))
	var side := str(problem.get("type", ""))
	var stake: Dictionary = problem.get("stake", {}) if typeof(problem.get("stake", {})) == TYPE_DICTIONARY else {}
	var amount := int(stake.get("amount", 0))
	var money := MathUtil.fmt_money(amount)
	if side == "client":
		return "At stake: %s/qtr revenue if the client walks." % money
	if side == "supplier":
		return "At stake: %s/qtr higher costs if unresolved." % money
	return "At stake: relationship terms under pressure."


static func enumerate_relationships(state: RunState) -> Array:
	return _enumerate_relationships(state)


static func _build_supply_chain_counterparty(
	state: RunState,
	rel: Dictionary,
	side: String,
	rng: SeededRng,
) -> Dictionary:
	var pool: Array = _Urgent.CLIENT_ARCHETYPES if side == "client" else _Urgent.SUPPLIER_ARCHETYPES
	var player_biz: BusinessInstance = rel.get("business")
	var cp_template := str(rel.get("counterpartyTemplateId", ""))
	var tmpl := Content.get_template(cp_template)
	var org_name := tmpl.name if tmpl != null else cp_template.capitalize().replace("_", " ")
	var flow := str(rel.get("flow", "supply"))
	var cp: Dictionary = _Urgent.build_counterparty(pool, org_name, rng)
	cp["role"] = side
	cp["orgName"] = org_name
	cp["templateId"] = cp_template
	cp["flow"] = flow
	cp["playerBusinessName"] = player_biz.name if player_biz != null else ""
	cp["preferredTerms"] = (
		["service guarantee", "flexible payment", "volume commitment"]
		if side == "client"
		else ["volume commitment", "faster payment", "indexed pricing"]
	)
	cp["hiddenInfo"] = (
		"they are already talking to a competing %s supplier" % flow
		if side == "client"
		else "their %s input costs rose this season" % flow
	)

	# Bind to a real community NPC on the counterparty template in the supply chain.
	CommunityState.ensure_initialized(state)
	CommunityGenerator.ensure_district_generated(state)
	var district_id := str(state.active_district_id)
	if district_id.is_empty():
		district_id = CommunityConfig.mvp_district_id()
	var npc_id := CommunityNegotiationBridge.npc_id_for_template(state, district_id, cp_template)
	if npc_id.is_empty():
		# Fall back: any district that has this template.
		var districts: Dictionary = state.community.get("districts", {})
		for did_variant in districts.keys():
			npc_id = CommunityNegotiationBridge.npc_id_for_template(state, str(did_variant), cp_template)
			if not npc_id.is_empty():
				district_id = str(did_variant)
				break
	if not npc_id.is_empty():
		cp["communityNpcId"] = npc_id
		var npc: Dictionary = CommunityGenerator.get_npc(state, npc_id)
		if not npc.is_empty():
			var npc_name := str(npc.get("displayName", "")).strip_edges()
			if not npc_name.is_empty():
				cp["npcName"] = npc_name
			var species_id := str(npc.get("speciesId", "")).strip_edges()
			if not species_id.is_empty():
				cp["speciesId"] = species_id
		var community_biz := _community_business_for_template(state, district_id, cp_template)
		if not community_biz.is_empty():
			var display := str(community_biz.get("displayName", "")).strip_edges()
			if not display.is_empty():
				cp["orgName"] = display
			cp["communityBusinessId"] = str(community_biz.get("id", ""))
	if str(cp.get("npcName", "")).is_empty():
		cp["npcName"] = org_name
	return cp


static func _community_business_for_template(state: RunState, district_id: String, template_id: String) -> Dictionary:
	var district_payload: Dictionary = state.community.get("districts", {}).get(district_id, {})
	var businesses: Dictionary = district_payload.get("businesses", {})
	for business_variant in businesses.values():
		if typeof(business_variant) != TYPE_DICTIONARY:
			continue
		var business: Dictionary = business_variant
		if str(business.get("templateId", "")) == template_id:
			return business
	return {}


static func _build_quantified_ask(
	state: RunState,
	rel: Dictionary,
	issue_type: String,
	severity: String,
	rng: SeededRng,
) -> Dictionary:
	var biz: BusinessInstance = rel.get("business")
	var side := str(rel.get("side", "client"))
	var flow := str(rel.get("flow", "goods"))
	var sev_mult := 1.0
	match severity:
		"crisis":
			sev_mult = 1.25
		"urgent":
			sev_mult = 1.0
		_:
			sev_mult = 0.75
	var pct := 0.0
	var amount := 0
	var statement := ""
	var stake_label := ""
	var situation_id := "stable_position"
	var kind := issue_type

	match issue_type:
		"priceIncrease":
			pct = snappedf(rng.randf_range(0.08, 0.14) * sev_mult, 0.01)
			amount = maxi(50, int(round(float(biz.operating_costs) * pct)))
			statement = "I will raise my %s prices %.0f%% starting next quarter (%s/qtr) because my input costs climbed." % [
				flow, pct * 100.0, MathUtil.fmt_money(amount),
			]
			stake_label = "At stake: %s/qtr higher costs if you accept their ask." % MathUtil.fmt_money(amount)
			situation_id = "cash_pressure"
		"paymentTerms":
			pct = snappedf(rng.randf_range(0.06, 0.12) * sev_mult, 0.01)
			amount = maxi(40, int(round(float(biz.operating_costs) * pct)))
			statement = "I need faster payment — net-15 or a %s deposit — or I throttle your %s deliveries." % [
				MathUtil.fmt_money(amount), flow,
			]
			stake_label = "At stake: %s/qtr cash drag / delivery throttle." % MathUtil.fmt_money(amount)
			situation_id = "cash_pressure"
		"volumeCommitment":
			pct = snappedf(rng.randf_range(0.20, 0.35) * sev_mult, 0.01)
			amount = maxi(50, int(round(float(biz.operating_costs) * 0.10 * sev_mult)))
			statement = "Commit to %.0f%% of my %s capacity next quarter, or I reallocate that slot — worth about %s/qtr to your line." % [
				pct * 100.0, flow, MathUtil.fmt_money(amount),
			]
			stake_label = "At stake: lose reserved %s capacity (~%s/qtr)." % [flow, MathUtil.fmt_money(amount)]
			situation_id = "entrepreneur_growth"
		"deliveryFrequency":
			pct = snappedf(rng.randf_range(0.05, 0.10) * sev_mult, 0.01)
			amount = maxi(40, int(round(float(biz.operating_costs) * pct)))
			statement = "I am consolidating %s runs — accept fewer deliveries or pay a %s/qtr routing surcharge." % [
				flow, MathUtil.fmt_money(amount),
			]
			stake_label = "At stake: %s/qtr surcharge or thinner delivery schedule." % MathUtil.fmt_money(amount)
			situation_id = "stable_position"
		"contractSecurity":
			pct = snappedf(rng.randf_range(0.25, 0.40) * sev_mult, 0.01)
			amount = maxi(60, int(round(float(biz.operating_costs) * 0.12 * sev_mult)))
			statement = "Sign a longer exclusivity on %s, or I move %.0f%% of that capacity to another buyer (~%s/qtr at risk)." % [
				flow, pct * 100.0, MathUtil.fmt_money(amount),
			]
			stake_label = "At stake: %.0f%% of %s supply (~%s/qtr)." % [pct * 100.0, flow, MathUtil.fmt_money(amount)]
			situation_id = "entrepreneur_growth"
		"costSharing":
			pct = snappedf(rng.randf_range(0.04, 0.09) * sev_mult, 0.01)
			amount = maxi(40, int(round(float(biz.operating_costs) * pct)))
			statement = "Special handling on %s is eating my margin — share %s/qtr starting next quarter or I cut the service extras." % [
				flow, MathUtil.fmt_money(amount),
			]
			stake_label = "At stake: %s/qtr cost share or service cut." % MathUtil.fmt_money(amount)
			situation_id = "cash_pressure"
		"priceReduction":
			pct = snappedf(rng.randf_range(0.08, 0.15) * sev_mult, 0.01)
			amount = maxi(50, int(round(float(biz.revenue_per_turn) * maxf(biz.cust_conc, 0.12) * pct)))
			statement = "Cut my %s price %.0f%% (%s/qtr) or I move that spend to a competitor next quarter." % [
				flow, pct * 100.0, MathUtil.fmt_money(amount),
			]
			stake_label = "At stake: %s/qtr revenue if they leave." % MathUtil.fmt_money(amount)
			situation_id = "cash_pressure"
		"deliveryGuarantee":
			pct = snappedf(rng.randf_range(0.15, 0.30) * sev_mult, 0.01)
			amount = maxi(50, int(round(float(biz.revenue_per_turn) * maxf(biz.cust_conc, 0.12) * 0.55 * sev_mult)))
			statement = "Miss my %s SLA again and I pull %.0f%% of my orders (~%s/qtr) — put a delivery guarantee in writing." % [
				flow, pct * 100.0, MathUtil.fmt_money(amount),
			]
			stake_label = "At stake: %.0f%% of this client's orders (~%s/qtr)." % [pct * 100.0, MathUtil.fmt_money(amount)]
			situation_id = "stable_position"
		"qualityCommitment":
			pct = snappedf(rng.randf_range(0.12, 0.25) * sev_mult, 0.01)
			amount = maxi(50, int(round(float(biz.revenue_per_turn) * maxf(biz.cust_conc, 0.12) * 0.5 * sev_mult)))
			statement = "Quality on %s slipped — meet a written QA bar or I shift %.0f%% of volume (~%s/qtr)." % [
				flow, pct * 100.0, MathUtil.fmt_money(amount),
			]
			stake_label = "At stake: %.0f%% of client volume (~%s/qtr)." % [pct * 100.0, MathUtil.fmt_money(amount)]
			situation_id = "stable_position"
		"higherVolume":
			pct = snappedf(rng.randf_range(0.20, 0.35) * sev_mult, 0.01)
			amount = maxi(50, int(round(float(biz.revenue_per_turn) * pct * 0.35)))
			statement = "I need %.0f%% more %s reserved for my growth — lock it or I dual-source (~%s/qtr opportunity)." % [
				pct * 100.0, flow, MathUtil.fmt_money(amount),
			]
			stake_label = "At stake: growth volume worth ~%s/qtr." % MathUtil.fmt_money(amount)
			situation_id = "entrepreneur_growth"
		"flexiblePayment":
			pct = snappedf(rng.randf_range(0.10, 0.20) * sev_mult, 0.01)
			amount = maxi(40, int(round(float(biz.revenue_per_turn) * maxf(biz.cust_conc, 0.12) * pct)))
			statement = "Extend my payment terms on %s or I cut orders by about %.0f%% (~%s/qtr)." % [
				flow, pct * 100.0, MathUtil.fmt_money(amount),
			]
			stake_label = "At stake: ~%s/qtr order cut if refused." % MathUtil.fmt_money(amount)
			situation_id = "cash_pressure"
		"exclusiveTerritory":
			pct = snappedf(rng.randf_range(0.20, 0.35) * sev_mult, 0.01)
			amount = maxi(60, int(round(float(biz.revenue_per_turn) * maxf(biz.cust_conc, 0.15) * 0.7 * sev_mult)))
			statement = "Give me exclusive %s territory rights, or I move %.0f%% of my business to your competitor (~%s/qtr)." % [
				flow, pct * 100.0, MathUtil.fmt_money(amount),
			]
			stake_label = "At stake: %.0f%% of this client (~%s/qtr)." % [pct * 100.0, MathUtil.fmt_money(amount)]
			situation_id = "entrepreneur_growth"
		_:
			amount = maxi(50, int(round(float(biz.operating_costs if side == "supplier" else biz.revenue_per_turn) * 0.08)))
			pct = 0.10
			statement = "We need revised %s terms next quarter — about %s/qtr is on the table." % [
				flow, MathUtil.fmt_money(amount),
			]
			stake_label = "At stake: %s/qtr if unresolved." % MathUtil.fmt_money(amount)
			situation_id = "stable_position"

	return {
		"kind": kind,
		"pct": pct,
		"amountPerTurn": amount,
		"statement": statement,
		"stakeLabel": stake_label,
		"situationId": situation_id,
		"flow": flow,
		"side": side,
	}


static func _build_hidden_accept_terms(ask: Dictionary, severity: String, rng: SeededRng) -> Dictionary:
	## Hidden settlement band: NPC opens at full ask; will close down to hardFloor.
	var ask_amt := float(ask.get("amountPerTurn", 0))
	var floor_frac := 0.40
	var accept_frac := 0.62
	match severity:
		"crisis":
			floor_frac = 0.55
			accept_frac = 0.78
		"urgent":
			floor_frac = 0.45
			accept_frac = 0.68
		_:
			floor_frac = 0.35
			accept_frac = 0.58
	floor_frac = clampf(floor_frac + rng.randf_range(-0.04, 0.04), 0.25, 0.7)
	accept_frac = clampf(accept_frac + rng.randf_range(-0.04, 0.04), floor_frac + 0.08, 0.9)
	return {
		"askAmount": int(ask_amt),
		"hardFloorAmount": maxi(1, int(round(ask_amt * floor_frac))),
		"acceptableAmount": maxi(1, int(round(ask_amt * accept_frac))),
		"minConcession": snappedf(1.0 - accept_frac, 0.01),
		"preferredTerms": (
			["service guarantee", "volume commitment", "flexible payment"]
			if str(ask.get("side", "")) == "client"
			else ["volume commitment", "indexed pricing", "faster payment"]
		),
	}


static func pending_severity_for_business(state: RunState, business_id: String) -> String:
	var best := ""
	for prob_variant in state.urgent_problems:
		if typeof(prob_variant) != TYPE_DICTIONARY:
			continue
		var prob: Dictionary = prob_variant
		if str(prob.get("businessId", "")) != business_id:
			continue
		var sev := str(prob.get("severity", "concern"))
		if sev == "crisis":
			return "crisis"
		if sev == "urgent":
			best = "urgent"
		elif best.is_empty():
			best = "concern"
	return best


# --- internals ---------------------------------------------------------------

static func _enumerate_relationships(state: RunState) -> Array:
	var out: Array = []
	var owned_templates: Dictionary = {}
	for biz in state.portfolio.businesses:
		if biz is BusinessInstance:
			var b: BusinessInstance = biz
			owned_templates[b.template_id] = true
	for biz in state.portfolio.businesses:
		if not (biz is BusinessInstance):
			continue
		var b: BusinessInstance = biz
		if b.template_id.is_empty():
			continue
		# Supplier-initiated issues: connections where this biz is the customer.
		for conn in Content.connections:
			if conn == null or conn.customer != b.template_id:
				continue
			# Skip pure internal links (player owns both) — no NPC counterparty to negotiate.
			if owned_templates.has(conn.supplier):
				continue
			out.append({
				"relationshipId": "supplier|%s|%s" % [conn.id, b.id],
				"side": "supplier",
				"connectionId": conn.id,
				"business": b,
				"counterpartyTemplateId": conn.supplier,
				"flow": conn.flow,
			})
		# Client-initiated issues: connections where this biz is the supplier.
		for conn in Content.connections:
			if conn == null or conn.supplier != b.template_id:
				continue
			if owned_templates.has(conn.customer):
				continue
			out.append({
				"relationshipId": "client|%s|%s" % [conn.id, b.id],
				"side": "client",
				"connectionId": conn.id,
				"business": b,
				"counterpartyTemplateId": conn.customer,
				"flow": conn.flow,
			})
	return out


static func _ensure_rel_state(states: Dictionary, rel_id: String) -> Dictionary:
	if states.has(rel_id) and typeof(states[rel_id]) == TYPE_DICTIONARY:
		return states[rel_id]
	var st := {
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
	states[rel_id] = st
	return st


static func _refill_service_buffer(state: RunState, rel: Dictionary, st: Dictionary) -> void:
	var biz: BusinessInstance = rel.get("business")
	var tier := int((biz.upgrades if biz != null else {}).get("care", 0))
	var capacity := 0.0
	match clampi(tier, 0, 3):
		1:
			capacity = 15.0
		2:
			capacity = 30.0
		3:
			capacity = 45.0
		_:
			capacity = 0.0
	var buffer := float(st.get("serviceBuffer", 0.0))
	# Passive refill toward capacity (account team standing by).
	if capacity > 0.0:
		buffer = minf(capacity, buffer + capacity * 0.2)
	st["serviceBuffer"] = buffer


static func _apply_prevention(state: RunState, st: Dictionary, prevention: Dictionary) -> void:
	var required := float(prevention.get("requiredBuffer", REQUIRED_BUFFER_BASE))
	st["serviceBuffer"] = maxf(0.0, float(st.get("serviceBuffer", 0.0)) - required)
	st["issuePressure"] = floorf(float(st.get("issuePressure", 0.0)) * SERVICE_PREVENTION_PRESSURE_FRAC)
	st["roundsSinceIssue"] = 0
	st["pendingIssueId"] = ""
	st["lastReviewedRound"] = state.turn
	state.run_log.append(str(prevention.get("message", "Customer care prevented a negotiation.")))


static func _operational_risk(biz: BusinessInstance, side: String, util_map: Dictionary, reasons: Array) -> float:
	var total := 0.0
	var util: Dictionary = util_map.get(biz.template_id, {})
	var util_pct := int(util.get("utilizationPct", 0))
	var util_pts := 0.0
	if util_pct > 100:
		util_pts = 15.0
	elif util_pct >= 91:
		util_pts = 8.0
	elif util_pct >= 75:
		util_pts = 3.0
	if util_pts > 0.0:
		total += util_pts
		reasons.append({"code": "capacity", "label": "Capacity utilization pressure", "value": util_pts, "sourceVariable": "utilizationPct"})

	var health := float(biz.client_health if side == "client" else biz.supplier_health)
	var late_proxy := 0.0
	if health < 40.0:
		late_proxy = 16.0
	elif health < 55.0:
		late_proxy = 9.0
	elif health < 70.0:
		late_proxy = 4.0
	if late_proxy > 0.0:
		total += late_proxy
		reasons.append({
			"code": "delivery",
			"label": "Delivery / fulfillment stress",
			"value": late_proxy,
			"sourceVariable": "clientHealth" if side == "client" else "supplierHealth",
		})
	return minf(total, 30.0)


static func _financial_risk(state: RunState, biz: BusinessInstance, side: String, reasons: Array) -> float:
	var total := 0.0
	var profit := biz.revenue_per_turn - biz.operating_costs
	var margin_pts := 0.0
	if profit < 0:
		margin_pts = 22.0
	elif float(profit) < float(biz.revenue_per_turn) * 0.08:
		margin_pts = 12.0
	elif float(profit) < float(biz.revenue_per_turn) * 0.15:
		margin_pts = 5.0
	if margin_pts > 0.0:
		total += margin_pts
		reasons.append({"code": "margin", "label": "Relationship margin strain", "value": margin_pts, "sourceVariable": "profit"})

	if state.cash < 5000:
		var cash_pts := 14.0 if state.cash < 2000 else 6.0
		total += cash_pts
		reasons.append({"code": "payment", "label": "Cash / payment stress", "value": cash_pts, "sourceVariable": "cash"})
	elif side == "supplier" and str(state.market_state.get("inflation", "")) == "high":
		total += 8.0
		reasons.append({"code": "input_cost", "label": "Input-cost inflation", "value": 8.0, "sourceVariable": "inflation"})
	return minf(total, 30.0)


static func _relationship_risk(biz: BusinessInstance, side: String, reasons: Array) -> float:
	var health := int(biz.client_health if side == "client" else biz.supplier_health)
	var pts := 0.0
	if health >= 80:
		pts = -5.0
	elif health >= 60:
		pts = -2.0
	elif health >= 40:
		pts = 0.0
	elif health >= 20:
		pts = 7.0
	else:
		pts = 15.0
	var state_label := str(biz.client_state if side == "client" else biz.supplier_state)
	if state_label == "at_risk":
		pts += 10.0
	elif state_label == "strained":
		pts += 4.0
	if pts != 0.0:
		reasons.append({
			"code": "trust",
			"label": "Trust / relationship score",
			"value": pts,
			"sourceVariable": "clientHealth" if side == "client" else "supplierHealth",
		})
	return pts


static func _dependency_risk(biz: BusinessInstance, reasons: Array) -> float:
	var share := biz.cust_conc * 100.0
	var pts := 0.0
	if share >= 75.0:
		pts = 15.0
	elif share >= 50.0:
		pts = 8.0
	elif share >= 25.0:
		pts = 3.0
	if pts > 0.0:
		reasons.append({"code": "dependency", "label": "Concentration / dependency", "value": pts, "sourceVariable": "custConc"})
	return pts


static func _service_mitigation(biz: BusinessInstance, reasons: Array) -> float:
	var tier := int(biz.upgrades.get("care", 0))
	var pts := 0.0
	match clampi(tier, 0, 3):
		1:
			pts = 2.0
		2:
			pts = 4.0
		3:
			pts = 6.0
	if pts > 0.0:
		reasons.append({"code": "service", "label": "Customer care mitigation", "value": -pts, "sourceVariable": "careTier"})
	return pts


static func _score_issue_types(state: RunState, rel: Dictionary, st: Dictionary) -> Dictionary:
	var biz: BusinessInstance = rel.get("business")
	var side := str(rel.get("side", "client"))
	var health := float(biz.client_health if side == "client" else biz.supplier_health)
	var profit := float(biz.revenue_per_turn - biz.operating_costs)
	var margin_gap := maxf(0.0, -profit) / maxf(1.0, float(biz.revenue_per_turn))
	var late_w := clampf((70.0 - health) / 70.0, 0.0, 1.0)
	var cash_stress := clampf((8000.0 - float(state.cash)) / 8000.0, 0.0, 1.0)
	var dep := biz.cust_conc
	var scores := {}
	if side == "supplier":
		scores["priceIncrease"] = margin_gap * 80.0 + (8.0 if str(state.market_state.get("inflation", "")) == "high" else 0.0)
		scores["paymentTerms"] = cash_stress * 60.0 + late_w * 20.0
		scores["volumeCommitment"] = dep * 40.0 + (10.0 if health < 55.0 else 0.0)
		scores["deliveryFrequency"] = late_w * 50.0
		scores["contractSecurity"] = dep * 55.0 + (12.0 if str(biz.supplier_state) == "at_risk" else 0.0)
		scores["costSharing"] = margin_gap * 45.0 + late_w * 15.0
	else:
		scores["priceReduction"] = margin_gap * 50.0 + (10.0 if str(state.market_state.get("consumerDemand", "")) == "weak" else 0.0)
		scores["deliveryGuarantee"] = late_w * 70.0
		scores["qualityCommitment"] = late_w * 40.0 + (8.0 if health < 50.0 else 0.0)
		scores["higherVolume"] = dep * 35.0 + (10.0 if str(state.market_state.get("consumerDemand", "")) == "strong" else 0.0)
		scores["flexiblePayment"] = cash_stress * 55.0
		scores["exclusiveTerritory"] = dep * 45.0
	return scores


static func _repetition_penalty(st: Dictionary, issue_type: String) -> float:
	var last := str(st.get("lastIssueType", ""))
	if last == issue_type:
		return -30.0
	var recent: Array = st.get("recentIssueTypes", [])
	var hits := 0
	for t in recent:
		if str(t) == issue_type:
			hits += 1
	if hits > 0:
		return -15.0
	return 5.0


static func _player_facing_reason(reasons: Array, issue_type: String, side: String) -> String:
	var bits: PackedStringArray = []
	for reason_variant in reasons:
		if typeof(reason_variant) != TYPE_DICTIONARY:
			continue
		var reason: Dictionary = reason_variant
		var label := str(reason.get("label", "")).strip_edges()
		if label.is_empty() or str(reason.get("code", "")) in ["base", "service"]:
			continue
		bits.append(label)
		if bits.size() >= 2:
			break
	if bits.is_empty():
		return "Commercial review due." if side == "supplier" else "A key client wants revised terms."
	return "%s." % " and ".join(bits)


static func _present_queue(state: RunState, candidates: Array) -> Array:
	if candidates.is_empty():
		return []
	candidates.sort_custom(func(a: Variant, b: Variant) -> bool:
		return _priority(a as Dictionary) > _priority(b as Dictionary)
	)
	var out: Array = []
	var normal_n := 0
	var severe_n := 0
	for cand_variant in candidates:
		var cand: Dictionary = cand_variant
		var sev := str(cand.get("severity", "concern"))
		var is_severe := sev in ["urgent", "crisis"]
		if is_severe:
			if severe_n >= MAX_SEVERE_EVENTS:
				continue
			severe_n += 1
		else:
			if normal_n >= MAX_NORMAL_EVENTS:
				# Mandatory reviews may slip one extra slot.
				if not bool(cand.get("mandatoryReview", false)):
					continue
				if normal_n >= MAX_NORMAL_EVENTS + 1:
					continue
			normal_n += 1
		out.append(cand)
		if out.size() >= MAX_PENDING_SHOWN:
			break
	return out


static func _priority(issue: Dictionary) -> float:
	var pressure := float(issue.get("pressure", 0.0))
	var sev := str(issue.get("severity", "concern"))
	var sev_bonus := 0.0
	match sev:
		"crisis":
			sev_bonus = 40.0
		"urgent":
			sev_bonus = 20.0
	var rounds := float(issue.get("neglectTurns", 0))
	return pressure + sev_bonus + rounds * 5.0
