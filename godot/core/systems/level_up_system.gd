class_name LevelUpSystem
extends RefCounted

const _UpgradeSystem := preload("res://core/systems/upgrade_system.gd")
const _Archetypes := preload("res://core/content/negotiation_archetypes.gd")

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


static func apply_level_up_effects(biz: BusinessInstance, tmpl: Dictionary, state: RunState) -> void:
	if biz == null or tmpl.is_empty():
		return
	biz.revenue_per_turn = int(round(float(biz.revenue_per_turn) * float(tmpl.get("revenueMult", 1.0))))
	biz.operating_costs = int(round(float(biz.operating_costs) * float(tmpl.get("costMult", 1.0))))
	if tmpl.has("custConcAdd"):
		biz.cust_conc = MathUtil.clamp(biz.cust_conc + float(tmpl.get("custConcAdd", 0.0)), 0.02, 0.9)
	biz.level = mini(3, biz.level + 1)
	_UpgradeSystem.reset_upgrades_for_level(biz)
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
	var rng := SeededRng.new()
	rng.set_rng_seed(state.run_seed + state.turn * 3137)
	var opps: Array = []
	for biz: BusinessInstance in state.portfolio.businesses:
		if biz.level >= 3:
			continue
		if not _UpgradeSystem.is_eligible_for_major_upgrade(biz):
			continue
		var already := false
		for opp_variant in state.opportunities:
			if typeof(opp_variant) == TYPE_DICTIONARY:
				var o: Dictionary = opp_variant
				if str(o.get("assetType", "")) == "levelup" and str(o.get("businessId", "")) == biz.id:
					already = true
					break
		if already:
			continue
		var tmpl: Dictionary = LEVEL_UP_TEMPLATES[rng.randi_range(0, LEVEL_UP_TEMPLATES.size() - 1)].duplicate(true)
		var val: int = biz.marked_value if biz.marked_value > 0 else _UpgradeSystem.estimate_valuation(biz, state)
		var base_price: int
		if tmpl.has("costFrac"):
			base_price = int(round(float(val) * float(tmpl.get("costFrac", 0.85))))
		else:
			base_price = int(round(float(val) * rng.randf_range(0.7, 1.1)))
		var counterparty: Dictionary = {}
		if bool(tmpl.get("requiresNegotiation", false)):
			var arch_id: String = str(tmpl.get("counterpartyArchetype", "relationship_owner"))
			counterparty = _Archetypes.build_counterparty(arch_id, base_price, rng)
		opps.append({
			"id": MathUtil.uid(),
			"kind": "levelup",
			"assetType": "levelup",
			"businessId": biz.id,
			"templateId": str(tmpl.get("id", "")),
			"name": "%s — %s" % [str(tmpl.get("name", "Level Up")), biz.name],
			"price": base_price,
			"requiresNegotiation": bool(tmpl.get("requiresNegotiation", false)),
			"levelUpTemplate": tmpl,
			"counterparty": counterparty,
			"diligenceDone": false,
			"expiresIn": 3,
			"blurb": str(tmpl.get("note", "")),
		})
	return opps


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
