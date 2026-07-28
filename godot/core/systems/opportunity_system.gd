class_name OpportunitySystem
extends RefCounted

const _Archetypes := preload("res://core/content/negotiation_archetypes.gd")
const _Diligence := preload("res://core/systems/diligence_system.gd")
const _LevelUp := preload("res://core/systems/level_up_system.gd")
const _Market := preload("res://core/systems/market_system.gd")
const _Security := preload("res://core/systems/security_system.gd")

const REGULAR_OPP_CAP := 6
const CHAIN_HINT_INTERVAL := 3
const MIN_OPPS_PER_DISTRICT := 2

const _World := preload("res://scenes/farm_map/world_layout_data.gd")

const LEVEL_PRICE_MULT: Dictionary = {1: 1.0, 2: 2.3, 3: 5.0}
const LEVEL_REVENUE_MULT: Dictionary = {1: 1.0, 2: 2.1, 3: 4.6}
const LEVEL_TAG: Dictionary = {1: "", 2: " — Regional Operation", 3: " — Corporate Division"}
const LEVEL_BLURB_SUFFIX: Dictionary = {
	1: "",
	2: " A larger, more established operation than a typical first deal.",
	3: " An institutional seller — expect a data-driven, less personal negotiation.",
}


## Initial fill for a new run (replaces full wipe on every turn).
static func refresh_opportunities(state: RunState) -> void:
	bootstrap_for_new_run(state)


static func bootstrap_for_new_run(state: RunState) -> void:
	state.opportunities.clear()
	if not state.is_capital_farm():
		return
	state.opportunities = _generate_fresh_batch(state, true)
	ParcelOwnershipSystem.sync_from_state(state)


static func advance_opportunities(state: RunState) -> void:
	if not state.is_capital_farm():
		return

	var surviving_regular: Array = []
	var surviving_levelups: Array = []
	for opp_variant in state.opportunities:
		if typeof(opp_variant) != TYPE_DICTIONARY:
			continue
		var opp: Dictionary = (opp_variant as Dictionary).duplicate(true)
		var expires: int = int(opp.get("expiresIn", 1)) - 1
		opp["expiresIn"] = expires
		if expires <= 0:
			continue
		var asset_type: String = str(opp.get("assetType", ""))
		if asset_type == "security":
			continue
		if asset_type == "levelup":
			surviving_levelups.append(opp)
		else:
			surviving_regular.append(opp)

	var fresh: Array = _generate_fresh_batch(state, false)
	var wildcard: Dictionary = _Market.maybe_trigger_wildcard(state)
	if not wildcard.is_empty():
		fresh.insert(0, wildcard)
	var fresh_regular: Array = []
	var fresh_levelups: Array = []
	for fresh_variant in fresh:
		if typeof(fresh_variant) != TYPE_DICTIONARY:
			continue
		var opp: Dictionary = fresh_variant
		if str(opp.get("assetType", "")) == "levelup":
			fresh_levelups.append(opp)
		else:
			fresh_regular.append(opp)

	fresh_levelups.append_array(_LevelUp.generate_level_up_opportunities(state))

	var combined: Array = surviving_regular + fresh_regular
	if combined.size() > REGULAR_OPP_CAP:
		combined = combined.slice(0, REGULAR_OPP_CAP)
	state.opportunities = combined + surviving_levelups + fresh_levelups
	ParcelOwnershipSystem.sync_from_state(state)


## Spawn listings on newly unlocked districts.
static func spawn_for_unlocked_districts(state: RunState, district_ids: Array) -> void:
	if not state.is_capital_farm() or district_ids.is_empty():
		return
	_spawn_district_opportunities(state, district_ids, true)


static func find_opportunity(state: RunState, opportunity_id: String) -> Dictionary:
	for opp_variant in state.opportunities:
		if typeof(opp_variant) != TYPE_DICTIONARY:
			continue
		var opp: Dictionary = opp_variant
		if str(opp.get("id", "")) == opportunity_id:
			return opp
	return {}


static func _spawn_district_opportunities(state: RunState, district_ids: Array, only_empty: bool) -> void:
	var rng := SeededRng.new()
	rng.set_rng_seed(state.run_seed + state.turn * 7919 + district_ids.size() * 131)
	var region: Dictionary = _World.load_region()
	for district_id_variant in district_ids:
		var district_id := str(district_id_variant)
		if district_id.is_empty() or not DistrictUnlockSystem.is_unlocked(state, district_id):
			continue
		var entry: Dictionary = _World.find_entry_by_id(region, district_id)
		if entry.is_empty():
			continue
		var district: Dictionary = _World.load_district_from_entry(entry)
		var existing := ParcelOwnershipSystem.count_district_opportunities(state, district)
		if only_empty and existing > 0:
			continue
		var target := MIN_OPPS_PER_DISTRICT
		var to_spawn := maxi(0, target - existing)
		for _i in to_spawn:
			var template_id := _pick_template_for_district(district, rng)
			if template_id.is_empty():
				continue
			var opp := _make_business_opportunity(state, rng, {
				"template_id": template_id,
				"expires_in": rng.randi_range(2, 4),
				"district_id": district_id,
			})
			if not opp.is_empty():
				state.opportunities.append(opp)


static func _pick_template_for_district(district: Dictionary, rng: SeededRng) -> String:
	var candidates: Array = []
	for parcel_variant in district.get("parcels", []):
		if typeof(parcel_variant) != TYPE_DICTIONARY:
			continue
		var parcel: Dictionary = parcel_variant
		var role := str(parcel.get("role", ""))
		if role in ["civic", "competitive"]:
			continue
		var template_id := str(parcel.get("template_id", ""))
		if template_id.is_empty():
			continue
		candidates.append(template_id)
	if candidates.is_empty():
		return ""
	return str(candidates[rng.randi_range(0, candidates.size() - 1)])


static func _generate_fresh_batch(state: RunState, include_starter: bool) -> Array:
	var rng := SeededRng.new()
	rng.set_rng_seed(state.run_seed + state.turn * 9973)

	var opps: Array = []
	if include_starter and not state.starter_deal_offered and state.turn <= 2 and state.portfolio.businesses.is_empty():
		var starter := _make_starter_opportunity(state, rng)
		if not starter.is_empty():
			opps.append(starter)
			state.starter_deal_offered = true

	if state.turn >= 2 and SynergySystem.has_critical_chain_gap(state):
		if state.turn == 2 or state.turn - state.last_chain_hint_turn >= CHAIN_HINT_INTERVAL:
			var hint := _make_chain_hint_opportunity(state, rng)
			if not hint.is_empty():
				opps.append(hint)
				state.last_chain_hint_turn = state.turn

	var count := 3 + rng.randi_range(0, 2)
	if state.turn <= 5:
		count = 4 + rng.randi_range(0, 1)

	for _i in count:
		var roll: float = rng.randf()
		var opp: Dictionary = {}
		if roll < 0.50:
			opp = _make_business_opportunity(state, rng, {})
		elif roll < 0.70:
			opp = _make_real_estate_opportunity(state, rng, {})
		elif roll < 0.90:
			opp = _Security.make_security_opportunity(state, rng)
		else:
			opp = _make_financing_opportunity(state, rng)
		if not opp.is_empty():
			opps.append(opp)

	_maybe_inject_financing_opportunity(state, rng, opps)
	return opps


static func _maybe_inject_financing_opportunity(state: RunState, rng: SeededRng, opps: Array) -> void:
	if not state.is_capital_farm() or state.turn > 4:
		return
	if state.cash >= 18000:
		return
	if _batch_has_asset_type(opps, "loan"):
		return
	opps.append(_make_financing_opportunity(state, rng))


static func _batch_has_asset_type(opps: Array, asset_type: String) -> bool:
	for opp_variant in opps:
		if typeof(opp_variant) == TYPE_DICTIONARY and str((opp_variant as Dictionary).get("assetType", "")) == asset_type:
			return true
	return false


static func _make_chain_hint_opportunity(state: RunState, rng: SeededRng) -> Dictionary:
	var tmpl := SynergySystem.pick_critical_missing_template(state)
	if tmpl == null:
		return {}
	if Content.is_real_estate_asset(tmpl.id):
		return _make_real_estate_opportunity(state, rng, {"template_id": tmpl.id, "expires_in": 2, "chain_hint": true})
	return _make_business_opportunity(state, rng, {"template_id": tmpl.id, "expires_in": 2, "chain_hint": true})


static func _make_starter_opportunity(state: RunState, rng: SeededRng) -> Dictionary:
	var template_id: String = GameMode.STARTER_FARM_TEMPLATES[rng.randi_range(0, GameMode.STARTER_FARM_TEMPLATES.size() - 1)]
	return _make_business_opportunity(state, rng, {
		"template_id": template_id,
		"price_mult": 0.82,
		"expires_in": 3,
		"starter_deal": true,
	})


static func _make_business_opportunity(state: RunState, rng: SeededRng, opts: Dictionary) -> Dictionary:
	var cfg: Dictionary = GameMode.config(state.mode)
	var level: int = _pick_business_level(state, rng)
	var template_id: String = str(opts.get("template_id", _pick_weighted_template(state, rng)))
	var tmpl := Content.get_template(template_id)
	if tmpl == null or tmpl.asset_class == "real_estate":
		return {}
	if tmpl.rev_range.size() < 2 or tmpl.margin_range.size() < 2:
		return {}

	var scale: float = _tier_scale(state, cfg)
	var revenue: int = int(round(
		rng.randf_range(float(tmpl.rev_range[0]), float(tmpl.rev_range[1]))
		* scale
		* float(cfg.get("revenue_mult", 1.0))
		* float(LEVEL_REVENUE_MULT.get(level, 1.0))
	))
	var margin: float = rng.randf_range(float(tmpl.margin_range[0]), float(tmpl.margin_range[1]))
	var cost: int = int(round(float(revenue) * (1.0 - margin) * float(cfg.get("cost_mult", 1.0))))
	var conc_damp: float = 1.0 if level == 1 else (0.8 if level == 2 else 0.5)
	var dep_damp: float = 1.0 if level == 1 else (0.7 if level == 2 else 0.4)
	var owner_dep: float = MathUtil.clamp(tmpl.owner_dep * dep_damp, 0.05, 0.95)
	var cust_conc: float = rng.randf_range(float(tmpl.cust_conc[0]), float(tmpl.cust_conc[1])) * conc_damp if tmpl.cust_conc.size() >= 2 else 0.12
	var equipment_condition: float = rng.randf_range(0.4, 0.9)

	var fair_value: int = ValuationSystem.estimate_listing_fair_value({
		"revenue": revenue,
		"cost": cost,
		"owner_dep": owner_dep,
		"cust_conc": cust_conc,
		"equipment_condition": equipment_condition,
	}, state.mode)

	var ask_premium: float = rng.randf_range(float(cfg.get("ask_premium_min", 1.1)), float(cfg.get("ask_premium_max", 1.22)))
	var price_mult: float = float(opts.get("price_mult", 1.0)) * float(LEVEL_PRICE_MULT.get(level, 1.0))
	var price: int = int(round(float(fair_value) * ask_premium * price_mult))

	var suffix: String = GameMode.FARM_SUFFIXES[rng.randi_range(0, GameMode.FARM_SUFFIXES.size() - 1)]
	var name := "%s — %s%s" % [tmpl.name, suffix, str(LEVEL_TAG.get(level, ""))]

	var arch_id: String = _Archetypes.pick_archetype_id_for_level(level, rng)
	var counterparty: Dictionary = _Archetypes.build_counterparty(arch_id, price, rng)
	counterparty["hiddenInfo"] = _Diligence.pick_hidden_info(arch_id, rng)

	var blurb: String = tmpl.blurb + str(LEVEL_BLURB_SUFFIX.get(level, ""))
	if bool(opts.get("starter_deal", false)):
		blurb += " Motivated local seller — discounted first foothold for new farm operators."

	var district_id := str(opts.get("district_id", ""))
	return {
		"id": MathUtil.uid(),
		"kind": "acquisition",
		"assetType": "business",
		"templateId": tmpl.id,
		"level": level,
		"name": name,
		"districtId": district_id,
		"price": price,
		"revenue": revenue,
		"cost": cost,
		"margin": margin,
		"ownerDep": owner_dep,
		"custConc": cust_conc,
		"equipmentCondition": equipment_condition,
		"fairValue": fair_value,
		"industry": tmpl.industry,
		"layer": tmpl.layer,
		"riskTags": tmpl.risk_tags,
		"expiresIn": int(opts.get("expires_in", rng.randi_range(1, 3))),
		"starterDeal": bool(opts.get("starter_deal", false)),
		"chainHintDeal": bool(opts.get("chain_hint", false)),
		"blurb": blurb,
		"strategicHint": SynergySystem.strategic_hint(state, tmpl.id),
		"counterparty": counterparty,
		"diligenceDone": false,
	}


static func _make_real_estate_opportunity(state: RunState, rng: SeededRng, opts: Dictionary) -> Dictionary:
	var cfg: Dictionary = GameMode.config(state.mode)
	var scale: float = _tier_scale(state, cfg)
	var template_id: String = str(opts.get("template_id", _pick_real_estate_template(state, rng)))
	var tmpl := Content.get_template(template_id)
	if tmpl == null or not Content.is_real_estate_asset(template_id):
		return {}
	if tmpl.price_range.size() < 2 or tmpl.rev_range.size() < 2:
		return {}

	var price_scale: float = scale * float(cfg.get("price_mult", 1.0))
	var rev_scale: float = scale * float(cfg.get("revenue_mult", 1.0))
	var price: int = int(round(rng.randf_range(float(tmpl.price_range[0]), float(tmpl.price_range[1])) * price_scale))
	var rent: int = int(round(rng.randf_range(float(tmpl.rev_range[0]), float(tmpl.rev_range[1])) * rev_scale))
	var opex_pct: float = 0.30 * float(cfg.get("cost_mult", 1.0))
	var vacancy: float = 0.10
	var district: String = GameMode.FARM_SUFFIXES[rng.randi_range(0, GameMode.FARM_SUFFIXES.size() - 1)]
	var arch: Dictionary = _Archetypes.pick_archetype(rng)
	var counterparty: Dictionary = _Archetypes.build_counterparty(str(arch.get("id", "desperate_seller")), price, rng)
	counterparty["hiddenInfo"] = _Diligence.pick_hidden_info(str(arch.get("id", "desperate_seller")), rng)

	return {
		"id": MathUtil.uid(),
		"kind": "investment",
		"assetType": "realestate",
		"templateId": tmpl.id,
		"name": "%s — %s" % [tmpl.name, district],
		"price": price,
		"downPct": MathUtil.clamp(0.22 * float(cfg.get("down_pct_mult", 1.0)), 0.08, 0.5),
		"rent": rent,
		"opexPct": opex_pct,
		"vacancyRisk": vacancy,
		"industry": tmpl.industry,
		"layer": tmpl.layer,
		"riskTags": tmpl.risk_tags,
		"assetClass": "real_estate",
		"expiresIn": int(opts.get("expires_in", rng.randi_range(1, 3))),
		"chainHintDeal": bool(opts.get("chain_hint", false)),
		"blurb": tmpl.blurb,
		"strategicHint": SynergySystem.strategic_hint(state, tmpl.id),
		"counterparty": counterparty,
		"diligenceDone": false,
	}


static func _pick_business_level(state: RunState, rng: SeededRng) -> int:
	var max_lvl := 1
	for biz: BusinessInstance in state.portfolio.businesses:
		max_lvl = maxi(max_lvl, biz.level)
	var roll: float = rng.randf()
	if max_lvl >= 3:
		if roll < 0.4:
			return 1
		if roll < 0.75:
			return 2
		return 3
	if max_lvl >= 2:
		return 1 if roll < 0.6 else 2
	return 1


static func _pick_real_estate_template(_state: RunState, rng: SeededRng) -> String:
	var candidates: Array[String] = []
	for tmpl in Content.get_all_templates():
		if Content.is_real_estate_asset(tmpl.id):
			candidates.append(tmpl.id)
	if candidates.is_empty():
		return "equipment_repair"
	return candidates[rng.randi_range(0, candidates.size() - 1)]


static func _pick_weighted_template(_state: RunState, rng: SeededRng) -> String:
	var templates: Array[BusinessTemplate] = Content.get_all_templates()
	var candidates: Array[String] = []
	for tmpl in templates:
		if tmpl.asset_class != "real_estate":
			candidates.append(tmpl.id)
	if candidates.is_empty():
		return "grain_farm"
	return candidates[rng.randi_range(0, candidates.size() - 1)]


static func _tier_scale(state: RunState, cfg: Dictionary) -> float:
	if not bool(cfg.get("tier_scale_on", false)):
		return 1.0
	var capital: float = float(maxi(FinanceSystem.net_worth(state), maxi(state.cash, 1000)))
	return MathUtil.clamp(capital / 90000.0, 0.35, 16.0)


static func _make_financing_opportunity(state: RunState, rng: SeededRng) -> Dictionary:
	var cfg: Dictionary = GameMode.config(state.mode)
	var scale: float = _tier_scale(state, cfg)
	var interest_env: String = str(state.market_state.get("interestRates", "stable"))
	var base_rate: float
	if interest_env in ["rising", "restrictive"]:
		base_rate = rng.randf_range(0.08, 0.12)
	else:
		base_rate = rng.randf_range(0.05, 0.08)
	var rate: float = MathUtil.clamp(
		base_rate + float(cfg.get("rate_adj", 0.0)) + LoanSystem.reputation_rate_adj(state.reputation),
		0.015,
		0.14,
	)
	var credit_mult: float = LoanSystem.credit_mult(state.reputation)
	var max_amount: int = int(round(rng.randf_range(20000.0, 80000.0) * scale * credit_mult))
	var rep_note := ""
	if state.reputation >= 35:
		rep_note = " Strong reputation improves terms."
	return {
		"id": MathUtil.uid(),
		"kind": "financing",
		"assetType": "loan",
		"name": "Bank Line of Credit Offer",
		"maxAmount": max_amount,
		"rate": rate,
		"termTurns": 10,
		"expiresIn": 2,
		"blurb": "Bank credit arranged in advance — typically cheaper than defaulting into a seller note if you close short on cash.%s" % rep_note,
	}
