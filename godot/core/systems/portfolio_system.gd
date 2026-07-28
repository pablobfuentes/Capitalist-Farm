class_name PortfolioSystem
extends RefCounted


static func business_market_value(state: RunState, biz: BusinessInstance) -> int:
	if UpgradeSystem.is_active(state):
		UpgradeSystem.ensure_business_upgrades(biz)
	if biz.marked_value > 0:
		return biz.marked_value
	return ValuationSystem.valuate_business(biz, state)


static func estimate_business_sell_proceeds(state: RunState, biz: BusinessInstance) -> int:
	# Midpoint estimate; actual sale randomizes ±8% around market value.
	return business_market_value(state, biz)


static func real_estate_market_value(asset: Dictionary) -> int:
	return int(asset.get("markedValue", asset.get("marked_value", asset.get("valuation", 0))))


static func estimate_real_estate_sell_proceeds(asset: Dictionary) -> int:
	var valuation: int = real_estate_market_value(asset)
	if valuation > 0:
		return valuation
	return int(asset.get("purchasePrice", asset.get("purchase_price", 0)))


static func sell_asset(state: RunState, asset_kind: String, asset_id: String) -> Dictionary:
	var ap: Dictionary = ActionPointsSystem.require(state, 1)
	if not bool(ap.get("ok", false)):
		return ap

	var rng := SeededRng.new()
	rng.set_rng_seed(state.run_seed + state.turn * 3571 + asset_id.hash())

	if asset_kind == "business":
		var biz := _find_business(state, asset_id)
		if biz == null:
			return {"ok": false, "error": "Business not found"}
		var valuation: int = business_market_value(state, biz)
		var price: int = int(round(float(valuation) * rng.randf_range(0.92, 1.08)))
		state.cash += price
		state.portfolio.businesses = state.portfolio.businesses.filter(func(b: BusinessInstance) -> bool:
			return b.id != asset_id
		)
		ActionPointsSystem.spend(state, 1)
		state.run_log.append("Sold %s for %s" % [biz.name, MathUtil.fmt_money(price)])
		ParcelOwnershipSystem.sync_from_state(state)
		return {"ok": true, "state": state, "proceeds": price, "assetKind": asset_kind}

	if asset_kind == "realestate":
		var asset: Dictionary = _find_real_estate(state, asset_id)
		if asset.is_empty():
			return {"ok": false, "error": "Property not found"}
		var valuation: int = int(asset.get("markedValue", asset.get("marked_value", asset.get("valuation", asset.get("purchasePrice", 0)))))
		var price: int = int(round(float(valuation) * rng.randf_range(0.95, 1.05)))
		state.cash += price
		var kept: Array = []
		for raw_variant in state.portfolio.real_estate:
			if typeof(raw_variant) != TYPE_DICTIONARY:
				continue
			if str((raw_variant as Dictionary).get("id", "")) != asset_id:
				kept.append(raw_variant)
		state.portfolio.real_estate = kept
		ActionPointsSystem.spend(state, 1)
		state.run_log.append("Sold %s for %s" % [str(asset.get("name", "Property")), MathUtil.fmt_money(price)])
		return {"ok": true, "state": state, "proceeds": price, "assetKind": asset_kind}

	return {"ok": false, "error": "Unknown asset kind: %s" % asset_kind}


static func _find_business(state: RunState, business_id: String) -> BusinessInstance:
	for biz: BusinessInstance in state.portfolio.businesses:
		if biz.id == business_id:
			return biz
	return null


static func _find_real_estate(state: RunState, asset_id: String) -> Dictionary:
	for raw_variant in state.portfolio.real_estate:
		if typeof(raw_variant) != TYPE_DICTIONARY:
			continue
		var asset: Dictionary = raw_variant
		if str(asset.get("id", "")) == asset_id:
			return asset
	return {}
