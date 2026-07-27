class_name FinanceSystem
extends RefCounted

const _UpgradeSystem := preload("res://core/systems/upgrade_system.gd")
const _SynergySystem := preload("res://core/systems/synergy_system.gd")


static func compute_quarterly_run_rates(state: RunState, mutate: bool = false) -> Dictionary:
	if _UpgradeSystem.is_active(state):
		_UpgradeSystem.ensure_portfolio_upgrades(state)

	var synergies: Array = []
	if state.is_capital_farm():
		synergies = _SynergySystem.compute_synergies(state)

	var revenue_total := 0
	var cost_total := 0
	var external_revenue_total := 0

	for biz: BusinessInstance in state.portfolio.businesses:
		var rev: int = biz.revenue_per_turn
		var cost: int = biz.operating_costs

		if state.is_capital_farm():
			rev = int(round(float(rev) * MarketSystem.season_rev_mult(biz, state)))
			cost = int(round(float(cost) * MarketSystem.season_cost_mult(biz, state)))
			var applied: Dictionary = _SynergySystem.apply_to_business(biz, synergies, state, {
				"supply_chain_builder_bonus": state.has_strategic_edge("supply_chain_builder"),
			})
			rev = int(applied.get("rev", rev))
			cost = int(applied.get("cost", cost))
			var exp: Dictionary = _SynergySystem.apply_export_to_business(biz, state)
			var export_rev: int = int(exp.get("exportRevenue", 0))
			rev += export_rev
			external_revenue_total += export_rev
			if mutate:
				biz.crisis_mult = float(applied.get("crisisMult", biz.crisis_mult))

		revenue_total += rev
		cost_total += cost

	var re_revenue := 0
	var re_cost := 0
	for raw_variant in state.portfolio.real_estate:
		if typeof(raw_variant) != TYPE_DICTIONARY:
			continue
		var asset: Dictionary = (raw_variant as Dictionary).duplicate(true)
		var rent: int = int(asset.get("rentPerTurn", asset.get("rent_per_turn", 0)))
		var vacancy: float = float(asset.get("vacancyRisk", asset.get("vacancy_risk", 0.1)))
		var effective_rent: int = int(round(float(rent) * (1.0 - vacancy * 0.4)))
		var opex: int = int(asset.get("operatingExpenses", asset.get("operating_expenses", 0)))
		if state.is_capital_farm() and str(asset.get("assetClass", asset.get("asset_class", ""))) == "real_estate":
			var template_id: String = str(asset.get("templateId", asset.get("template_id", "")))
			if Content.is_infrastructure_template(template_id):
				var infra: Dictionary = _SynergySystem.apply_infrastructure_to_real_estate(asset, state, synergies)
				if not infra.is_empty():
					effective_rent = int(infra.get("rent", effective_rent))
					opex = int(infra.get("opex", opex))
					external_revenue_total += int(infra.get("externalContractRevenue", 0))
		re_revenue += effective_rent
		re_cost += opex

	revenue_total += re_revenue
	cost_total += re_cost

	var debt_service: int = _debt_service(state)
	var profit: int = revenue_total - cost_total - debt_service

	return {
		"revenueTotal": revenue_total,
		"costTotal": cost_total,
		"debtService": debt_service,
		"profit": profit,
		"synergies": synergies,
		"externalRevenueTotal": external_revenue_total,
	}


static func net_worth(state: RunState) -> int:
	var total: int = state.cash
	for biz: BusinessInstance in state.portfolio.businesses:
		total += biz.marked_value if biz.marked_value > 0 else _estimate_business_value(biz)
	for raw: Dictionary in state.portfolio.real_estate:
		total += int(raw.get("markedValue", raw.get("marked_value", raw.get("valuation", raw.get("purchasePrice", 0)))))
	total += SecuritySystem.securities_market_value(state)
	for loan_variant in state.loans:
		if typeof(loan_variant) == TYPE_DICTIONARY:
			var loan: Dictionary = loan_variant
			total -= int(loan.get("principal", loan.get("balance", 0)))
	return total


static func _debt_service(state: RunState) -> int:
	var service := 0
	for loan_variant in state.loans:
		if typeof(loan_variant) != TYPE_DICTIONARY:
			continue
		var loan: Dictionary = loan_variant
		service += int(loan.get("paymentPerTurn", loan.get("payment_per_turn", 0)))
	return service


static func _estimate_business_value(biz: BusinessInstance) -> int:
	var profit: int = biz.revenue_per_turn - biz.operating_costs
	return maxi(0, int(round(float(profit) * 8.0)))
