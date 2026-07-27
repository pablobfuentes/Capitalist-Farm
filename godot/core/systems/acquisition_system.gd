class_name AcquisitionSystem
extends RefCounted

const _UpgradeSystem := preload("res://core/systems/upgrade_system.gd")
const _Finance := preload("res://core/systems/acquisition_finance.gd")


static func acquire_business(state: RunState, opportunity_id: String, price_override: int = -1) -> Dictionary:
	var ap: Dictionary = ActionPointsSystem.require(state, 1)
	if not bool(ap.get("ok", false)):
		return ap

	var opp: Dictionary = OpportunitySystem.find_opportunity(state, opportunity_id)
	if opp.is_empty():
		return {"ok": false, "error": "Opportunity not found"}

	if str(opp.get("assetType", "")) != "business":
		return {"ok": false, "error": "Not a business listing"}

	if bool(opp.get("rivalContest", false)):
		return {"ok": false, "error": "Cannot buy outright during a rival contest — negotiate"}

	var ask: int = price_override if price_override >= 0 else int(opp.get("price", 0))
	var offer: Dictionary = {
		"totalPrice": ask,
		"cashAtClosing": ask,
		"closingSpeed": "standard",
		"termsOffered": [],
		"riskToCounterparty": 8,
	}

	ActionPointsSystem.spend(state, 1)
	var result: Dictionary = close_business_acquisition(state, opportunity_id, offer)
	if not bool(result.get("ok", false)):
		return result
	state.run_log.append("Buy Now — %s at %s" % [str(opp.get("name", "business")), MathUtil.fmt_money(ask)])
	return result


static func close_business_acquisition(state: RunState, opportunity_id: String, offer: Dictionary) -> Dictionary:
	var opp: Dictionary = OpportunitySystem.find_opportunity(state, opportunity_id)
	if opp.is_empty():
		return {"ok": false, "error": "Opportunity not found"}

	if str(opp.get("assetType", "")) != "business":
		return {"ok": false, "error": "Not a business listing"}

	var total_price: int = int(offer.get("totalPrice", int(opp.get("price", 0))))
	var cash_requested: int = int(offer.get("cashAtClosing", total_price))
	var cash_at_closing: int = mini(state.cash, cash_requested)
	if state.cash < cash_at_closing:
		return {
			"ok": false,
			"error": "Need %s cash at closing" % MathUtil.fmt_money(cash_at_closing),
		}

	var biz := _create_business_from_opportunity(state, opp, total_price)
	state.portfolio.businesses.append(biz)
	var finance: Dictionary = _Finance.settle_acquisition_finance(
		state,
		int(opp.get("price", total_price)),
		offer,
		"business",
	)
	_remove_opportunity(state, opportunity_id)
	ParcelOwnershipSystem.on_business_acquired(state, biz, opp)

	return {
		"ok": true,
		"state": state,
		"business": biz,
		"price": total_price,
		"finance": finance,
	}


static func _create_business_from_opportunity(state: RunState, opp: Dictionary, paid_price: int) -> BusinessInstance:
	var biz := BusinessInstance.new()
	biz.id = MathUtil.uid()
	biz.template_id = str(opp.get("templateId", ""))
	biz.name = str(opp.get("name", "Business"))
	biz.revenue_per_turn = int(opp.get("revenue", 0))
	biz.operating_costs = int(opp.get("cost", 0))
	biz.industry = str(opp.get("industry", ""))
	biz.layer = str(opp.get("layer", ""))
	biz.purchase_price = paid_price
	biz.upgrades = _UpgradeSystem.default_upgrades()
	biz.marked_value = ValuationSystem.acquisition_entry_valuation(
		biz,
		paid_price,
		int(opp.get("fairValue", 0)),
		state.portfolio.businesses.size(),
	)
	biz.level = int(opp.get("level", 1))
	biz.cust_conc = float(opp.get("custConc", opp.get("cust_conc", 0.12)))
	biz.acquired_turn = state.turn
	biz.last_care_turn = state.turn
	_UpgradeSystem.ensure_business_upgrades(biz)
	return biz


static func acquire_real_estate(state: RunState, opportunity_id: String, price_override: int = -1) -> Dictionary:
	var ap: Dictionary = ActionPointsSystem.require(state, 1)
	if not bool(ap.get("ok", false)):
		return ap

	var opp: Dictionary = OpportunitySystem.find_opportunity(state, opportunity_id)
	if opp.is_empty():
		return {"ok": false, "error": "Opportunity not found"}
	if str(opp.get("assetType", "")) != "realestate":
		return {"ok": false, "error": "Not a real estate listing"}
	if bool(opp.get("rivalContest", false)):
		return {"ok": false, "error": "Cannot buy outright during a rival contest — negotiate"}

	var ask: int = price_override if price_override >= 0 else int(opp.get("price", 0))
	var offer: Dictionary = {
		"totalPrice": ask,
		"cashAtClosing": ask,
		"closingSpeed": "standard",
		"termsOffered": [],
		"riskToCounterparty": 8,
	}
	ActionPointsSystem.spend(state, 1)
	var result: Dictionary = close_real_estate_acquisition(state, opportunity_id, offer)
	if bool(result.get("ok", false)):
		state.run_log.append("Buy Now — %s at %s" % [str(opp.get("name", "property")), MathUtil.fmt_money(ask)])
	return result


static func close_real_estate_acquisition(state: RunState, opportunity_id: String, offer: Dictionary) -> Dictionary:
	var opp: Dictionary = OpportunitySystem.find_opportunity(state, opportunity_id)
	if opp.is_empty():
		return {"ok": false, "error": "Opportunity not found"}
	if str(opp.get("assetType", "")) != "realestate":
		return {"ok": false, "error": "Not a real estate listing"}

	var total_price: int = int(offer.get("totalPrice", int(opp.get("price", 0))))
	var cash_requested: int = int(offer.get("cashAtClosing", total_price))
	var cash_at_closing: int = mini(state.cash, cash_requested)
	if state.cash < cash_at_closing:
		return {"ok": false, "error": "Need %s cash at closing" % MathUtil.fmt_money(cash_at_closing)}

	var asset := _create_real_estate_from_opportunity(state, opp, total_price)
	state.portfolio.real_estate.append(asset)
	var finance: Dictionary = _Finance.settle_acquisition_finance(
		state,
		int(opp.get("price", total_price)),
		offer,
		"realestate",
	)
	_remove_opportunity(state, opportunity_id)
	return {"ok": true, "state": state, "realEstate": asset, "price": total_price, "finance": finance}


static func _create_real_estate_from_opportunity(state: RunState, opp: Dictionary, paid_price: int) -> Dictionary:
	var rng := SeededRng.new()
	rng.set_rng_seed(state.run_seed + paid_price)
	var marked: int = int(round(float(paid_price) * rng.randf_range(0.98, 1.05)))
	var template_id: String = str(opp.get("templateId", ""))
	var asset := {
		"id": MathUtil.uid(),
		"templateId": template_id,
		"name": str(opp.get("name", "Property")),
		"rentPerTurn": int(opp.get("rent", 0)),
		"operatingExpenses": int(round(float(opp.get("rent", 0)) * float(opp.get("opexPct", 0.3)))),
		"vacancyRisk": float(opp.get("vacancyRisk", 0.1)),
		"industry": str(opp.get("industry", "")),
		"layer": str(opp.get("layer", "")),
		"assetClass": "real_estate",
		"purchasePrice": paid_price,
		"markedValue": marked,
		"valuation": marked,
		"improvementsApplied": [],
	}
	if Content.is_infrastructure_template(template_id) and UpgradeSystem.is_active(state):
		asset["upgrades"] = UpgradeSystem.default_upgrades()
	return asset


static func _remove_opportunity(state: RunState, opportunity_id: String) -> void:
	var kept: Array = []
	for opp_variant in state.opportunities:
		if typeof(opp_variant) != TYPE_DICTIONARY:
			continue
		if str((opp_variant as Dictionary).get("id", "")) != opportunity_id:
			kept.append(opp_variant)
	state.opportunities = kept
