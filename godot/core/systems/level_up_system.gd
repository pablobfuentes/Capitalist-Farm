class_name LevelUpSystem
extends RefCounted

const _UpgradeSystem := preload("res://core/systems/upgrade_system.gd")
const _Archetypes := preload("res://core/content/negotiation_archetypes.gd")

const MAX_BUSINESS_LEVEL := 3
const IMPROVEMENTS_FOR_LEVEL_UP: Dictionary = {
	1: 4,
	2: 10,
}

const LEVEL_UP_TEMPLATES: Array = [
	{
		"id": "expand_city", "name": "Expand to Another City", "requiresNegotiation": false, "costFrac": 0.85,
		"revenueMult": 1.75, "costMult": 1.5,
		"note": "Opens a second location in a new market — a step-change in revenue, and in overhead.",
	},
	{
		"id": "nationwide_client", "name": "Secure a Nationwide Client Contract", "requiresNegotiation": true,
		"revenueMult": 1.9, "costMult": 1.55, "custConcAdd": 0.25, "counterpartyArchetype": "relationship_owner",
		"hiddenInfo": "they are also evaluating a competitor location",
		"note": "A major national account would transform your revenue — but concentrates real risk in one relationship.",
	},
	{
		"id": "venue_remodel", "name": "Full Venue Remodel", "requiresNegotiation": false, "costFrac": 0.6,
		"revenueMult": 1.55, "costMult": 1.25, "conditionBoost": true, "ownerDepMult": 0.85,
		"note": "A ground-up remodel refreshes the brand and the customer experience.",
	},
	{
		"id": "franchise_license", "name": "License a Franchise Model", "requiresNegotiation": true,
		"revenueMult": 2.0, "costMult": 1.6, "counterpartyArchetype": "corporate_seller",
		"hiddenInfo": "territory exclusivity is their main internal negotiating point",
		"note": "Franchising multiplies revenue but adds an ongoing royalty and real operational complexity.",
	},
	{
		"id": "automation_overhaul", "name": "Institutional Automation Overhaul", "requiresNegotiation": false, "costFrac": 0.75,
		"revenueMult": 1.4, "costMult": 0.75,
		"note": "Heavy investment in systems and automation — more revenue capacity on a much leaner cost structure.",
	},
]


static func improvements_required_for_next_level(level: int) -> int:
	return int(IMPROVEMENTS_FOR_LEVEL_UP.get(level, 0))


static func improvements_applied(biz: BusinessInstance) -> int:
	if biz == null:
		return 0
	return _UpgradeSystem.upgrade_tier_sum(biz)


static func is_eligible_for_level_up(biz: BusinessInstance) -> bool:
	if biz == null or biz.level >= MAX_BUSINESS_LEVEL:
		return false
	var required := improvements_required_for_next_level(biz.level)
	return required > 0 and improvements_applied(biz) >= required


static func progress_label(biz: BusinessInstance) -> String:
	if biz == null:
		return ""
	if biz.level >= MAX_BUSINESS_LEVEL:
		return "Level %d · max level" % biz.level
	var required := improvements_required_for_next_level(biz.level)
	var applied := improvements_applied(biz)
	var next_level := biz.level + 1
	if is_eligible_for_level_up(biz):
		return "Level %d · %d/%d improvements · ready for Level %d" % [
			biz.level, applied, required, next_level,
		]
	return "Level %d · %d/%d improvements toward Level %d" % [
		biz.level, applied, required, next_level,
	]


static func find_opportunity_for_business(state: RunState, business_id: String) -> Dictionary:
	for opp_variant in state.opportunities:
		if typeof(opp_variant) != TYPE_DICTIONARY:
			continue
		var opp: Dictionary = opp_variant
		if str(opp.get("assetType", "")) == "levelup" and str(opp.get("businessId", "")) == business_id:
			return opp
	return {}


static func ensure_opportunity_for_business(state: RunState, business_id: String) -> Dictionary:
	var biz := _UpgradeSystem.find_business(state, business_id)
	if biz == null or not is_eligible_for_level_up(biz):
		return {}
	var existing := find_opportunity_for_business(state, business_id)
	if not existing.is_empty():
		if _must_direct_buy(biz) and bool(existing.get("requiresNegotiation", false)):
			_remove_opportunity(state, str(existing.get("id", "")))
		else:
			var normalized := _normalize_level_up_opportunity(existing, biz)
			_update_opportunity(state, normalized)
			return normalized
	var opp := _build_level_up_opportunity(state, biz)
	if opp.is_empty():
		return {}
	state.opportunities.append(opp)
	return opp


static func improve_panel_view(state: RunState, biz: BusinessInstance) -> Dictionary:
	if biz == null or not state.is_capital_farm() or not _UpgradeSystem.is_active(state):
		return {"visible": false}
	var progress := progress_label(biz)
	if biz.level >= MAX_BUSINESS_LEVEL:
		return {"visible": true, "progressLine": progress, "ready": false}
	if not is_eligible_for_level_up(biz):
		return {"visible": true, "progressLine": progress, "ready": false}
	var opp := ensure_opportunity_for_business(state, biz.id)
	if opp.is_empty():
		return {"visible": true, "progressLine": progress, "ready": false}
	opp = _normalize_level_up_opportunity(opp, biz)
	var tmpl: Dictionary = opp.get("levelUpTemplate", {})
	var price: int = int(opp.get("price", 0))
	var requires_negotiation := bool(opp.get("requiresNegotiation", false))
	var rev_mult: float = float(tmpl.get("revenueMult", 1.0))
	var cost_mult: float = float(tmpl.get("costMult", 1.0))
	return {
		"visible": true,
		"progressLine": progress,
		"ready": true,
		"opportunityId": str(opp.get("id", "")),
		"title": str(tmpl.get("name", "Level up")),
		"blurb": str(tmpl.get("note", "")),
		"targetLevel": biz.level + 1,
		"price": price,
		"requiresNegotiation": requires_negotiation,
		"canInvest": not requires_negotiation and state.action_points >= 1 and state.cash >= price,
		"canNegotiate": requires_negotiation and state.action_points >= 1,
		"rewardLine": "Revenue ×%.2f · Costs ×%.2f · keep your improvements" % [rev_mult, cost_mult],
	}


static func apply_level_up_effects(biz: BusinessInstance, tmpl: Dictionary, state: RunState) -> void:
	if biz == null or tmpl.is_empty():
		return
	biz.revenue_per_turn = int(round(float(biz.revenue_per_turn) * float(tmpl.get("revenueMult", 1.0))))
	biz.operating_costs = int(round(float(biz.operating_costs) * float(tmpl.get("costMult", 1.0))))
	if tmpl.has("custConcAdd"):
		biz.cust_conc = MathUtil.clamp(biz.cust_conc + float(tmpl.get("custConcAdd", 0.0)), 0.02, 0.9)
	biz.level = mini(MAX_BUSINESS_LEVEL, biz.level + 1)
	_UpgradeSystem.recompute_upgrade_stats(biz)
	biz.marked_value = _UpgradeSystem.estimate_valuation(biz, state)
	biz.last_care_turn = state.turn if state != null else biz.last_care_turn


static func do_level_up(state: RunState, opportunity_id: String) -> Dictionary:
	var ap: Dictionary = ActionPointsSystem.require(state, 1)
	if not bool(ap.get("ok", false)):
		return ap
	var opp: Dictionary = OpportunitySystem.find_opportunity(state, opportunity_id)
	if opp.is_empty() or str(opp.get("assetType", "")) != "levelup":
		return {"ok": false, "error": "Not a level-up opportunity"}
	if bool(opp.get("requiresNegotiation", false)):
		return {"ok": false, "error": "This level-up requires negotiation — use Negotiate"}
	var biz := _UpgradeSystem.find_business(state, str(opp.get("businessId", "")))
	if biz == null:
		return {"ok": false, "error": "Business not found"}
	var price: int = int(opp.get("price", 0))
	if state.cash < price:
		return {"ok": false, "error": "Insufficient cash"}
	state.cash -= price
	ActionPointsSystem.spend(state, 1)
	var tmpl: Dictionary = opp.get("levelUpTemplate", {})
	if tmpl.is_empty():
		tmpl = _template_by_id(str(opp.get("templateId", "")))
	apply_level_up_effects(biz, tmpl, state)
	_remove_opportunity(state, opportunity_id)
	var tmpl_name: String = str(tmpl.get("name", "Level up"))
	state.run_log.append("%s completed at %s — now Level %d." % [tmpl_name, biz.name, biz.level])
	return {"ok": true, "state": state, "business": biz}


static func generate_level_up_opportunities(state: RunState) -> Array:
	if not state.is_capital_farm() or not _UpgradeSystem.is_active(state):
		return []
	var opps: Array = []
	for biz: BusinessInstance in state.portfolio.businesses:
		if not is_eligible_for_level_up(biz):
			continue
		if not find_opportunity_for_business(state, biz.id).is_empty():
			continue
		var opp := _build_level_up_opportunity(state, biz)
		if not opp.is_empty():
			opps.append(opp)
	return opps


static func _build_level_up_opportunity(state: RunState, biz: BusinessInstance) -> Dictionary:
	if biz == null or biz.level >= MAX_BUSINESS_LEVEL or not is_eligible_for_level_up(biz):
		return {}
	var rng := SeededRng.new()
	rng.set_rng_seed(state.run_seed + state.turn * 3137 + hash(biz.id))
	var tmpl: Dictionary = _pick_level_up_template(rng, biz)
	var val: int = biz.marked_value if biz.marked_value > 0 else _UpgradeSystem.estimate_valuation(biz, state)
	var base_price: int
	if tmpl.has("costFrac"):
		base_price = int(round(float(val) * float(tmpl.get("costFrac", 0.85))))
	else:
		base_price = int(round(float(val) * rng.randf_range(0.7, 1.1)))
	var opp := {
		"id": MathUtil.uid(),
		"kind": "levelup",
		"assetType": "levelup",
		"businessId": biz.id,
		"templateId": str(tmpl.get("id", "")),
		"name": "%s — %s" % [str(tmpl.get("name", "Level Up")), biz.name],
		"price": base_price,
		"requiresNegotiation": bool(tmpl.get("requiresNegotiation", false)),
		"levelUpTemplate": tmpl,
		"counterparty": {},
		"diligenceDone": false,
		"expiresIn": 3,
		"blurb": str(tmpl.get("note", "")),
		"targetLevel": biz.level + 1,
	}
	if bool(opp.get("requiresNegotiation", false)):
		var arch_id: String = str(tmpl.get("counterpartyArchetype", "relationship_owner"))
		opp["counterparty"] = _Archetypes.build_counterparty(arch_id, base_price, rng)
	return _normalize_level_up_opportunity(opp, biz)


static func _must_direct_buy(biz: BusinessInstance) -> bool:
	# Level 1 → 2 is always a direct cash investment (no negotiation).
	return biz != null and biz.level == 1


static func _pick_level_up_template(rng: SeededRng, biz: BusinessInstance) -> Dictionary:
	var pool: Array = []
	for tmpl_variant in LEVEL_UP_TEMPLATES:
		if typeof(tmpl_variant) != TYPE_DICTIONARY:
			continue
		var tmpl: Dictionary = tmpl_variant
		if _must_direct_buy(biz) and bool(tmpl.get("requiresNegotiation", false)):
			continue
		pool.append(tmpl.duplicate(true))
	if pool.is_empty():
		return (LEVEL_UP_TEMPLATES[0] as Dictionary).duplicate(true)
	return pool[rng.randi_range(0, pool.size() - 1)] as Dictionary


static func _normalize_level_up_opportunity(opp: Dictionary, biz: BusinessInstance) -> Dictionary:
	if opp.is_empty() or not _must_direct_buy(biz):
		return opp
	var normalized: Dictionary = opp.duplicate(true)
	normalized["requiresNegotiation"] = false
	normalized["counterparty"] = {}
	normalized["targetLevel"] = biz.level + 1
	return normalized


static func _template_by_id(template_id: String) -> Dictionary:
	for tmpl_variant in LEVEL_UP_TEMPLATES:
		if typeof(tmpl_variant) == TYPE_DICTIONARY and str((tmpl_variant as Dictionary).get("id", "")) == template_id:
			return tmpl_variant as Dictionary
	return {}


static func _remove_opportunity(state: RunState, opportunity_id: String) -> void:
	var kept: Array = []
	for opp_variant in state.opportunities:
		if typeof(opp_variant) != TYPE_DICTIONARY:
			continue
		if str((opp_variant as Dictionary).get("id", "")) != opportunity_id:
			kept.append(opp_variant)
	state.opportunities = kept


static func _update_opportunity(state: RunState, opp: Dictionary) -> void:
	var opp_id := str(opp.get("id", ""))
	if opp_id.is_empty():
		return
	for i in state.opportunities.size():
		if typeof(state.opportunities[i]) != TYPE_DICTIONARY:
			continue
		if str((state.opportunities[i] as Dictionary).get("id", "")) == opp_id:
			state.opportunities[i] = opp
			return
