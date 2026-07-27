class_name ValuationSystem
extends RefCounted

static func estimate_listing_fair_value(econ: Dictionary, mode: String) -> int:
	var revenue: int = int(econ.get("revenue", 0))
	var cost: int = int(econ.get("cost", 0))
	var profit: int = revenue - cost
	var owner_dep: float = float(econ.get("owner_dep", econ.get("ownerDep", 0.5)))
	var cust_conc: float = float(econ.get("cust_conc", econ.get("custConc", 0.12)))
	var equip: float = float(econ.get("equipment_condition", econ.get("equipmentCondition", 0.8)))
	var multiple: float = 4.0 - owner_dep * 1.2 - cust_conc * 1.5 + (1.0 - equip) * -0.5
	var val: float = maxf(1000.0, float(profit) * 4.0 * MathUtil.clamp(multiple / 2.5, 0.6, 1.6))
	val *= float(GameMode.config(mode).get("valuation_mult", 1.0))
	return int(round(val))


static func acquisition_entry_valuation(
	biz: BusinessInstance,
	paid_price: int,
	opp_fair_value: int,
	owned_count: int
) -> int:
	var fair: int = _valuate_business(biz)
	if opp_fair_value > 0:
		fair = opp_fair_value if owned_count <= 1 else int(round((float(fair) + float(opp_fair_value)) / 2.0))
	var paid: int = maxi(0, paid_price)
	if paid <= 0:
		return fair
	if fair <= paid:
		return fair
	var max_windfall: int = int(round(maxf(float(paid) * 0.28, float(fair) * 0.14)))
	return mini(fair, paid + max_windfall)


static func _valuate_business(biz: BusinessInstance) -> int:
	var profit: int = biz.revenue_per_turn - biz.operating_costs
	return maxi(1000, int(round(float(profit) * 8.0)))


static func valuate_business(biz: BusinessInstance, state: RunState = null) -> int:
	if state != null and state.is_capital_farm():
		var rates: Dictionary = FinanceSystem.compute_quarterly_run_rates(state, false)
		var synergies: Array = rates.get("synergies", [])
		for node: BusinessInstance in state.portfolio.businesses:
			if node.id == biz.id:
				var applied: Dictionary = SynergySystem.apply_to_business(biz, synergies, state, {})
				var exp: Dictionary = SynergySystem.apply_export_to_business(biz, state)
				var profit: int = int(applied.get("rev", biz.revenue_per_turn)) + int(exp.get("exportRevenue", 0)) - int(applied.get("cost", biz.operating_costs))
				return maxi(1000, int(round(float(profit) * 8.0)))
	return _valuate_business(biz)


static func revalue_assets(state: RunState) -> Dictionary:
	var rng := SeededRng.new()
	rng.set_rng_seed(state.run_seed + state.turn * 5821 + 3)
	var count := 0
	var appreciation_sum := 0.0
	for raw_variant in state.portfolio.real_estate:
		if typeof(raw_variant) != TYPE_DICTIONARY:
			continue
		var asset: Dictionary = raw_variant as Dictionary
		var vacancy: float = float(asset.get("vacancyRisk", asset.get("vacancy_risk", 0.1)))
		var appreciation: float = MathUtil.clamp(rng.randf_range(0.05, 0.10) - vacancy * 0.03, 0.03, 0.10)
		var marked: int = int(asset.get("markedValue", asset.get("marked_value", asset.get("valuation", asset.get("purchasePrice", 0)))))
		asset["markedValue"] = int(round(float(marked) * (1.0 + appreciation)))
		asset["valuation"] = asset["markedValue"]
		var rent: int = int(asset.get("rentPerTurn", asset.get("rent_per_turn", 0)))
		asset["rentPerTurn"] = int(round(float(rent) * 1.03))
		count += 1
		appreciation_sum += appreciation
	return {
		"count": count,
		"avgAppreciation": appreciation_sum / float(count) if count > 0 else 0.0,
	}
