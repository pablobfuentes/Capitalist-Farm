class_name RealEstateSystem
extends RefCounted

const IMPROVEMENTS_PATH := "res://data/farm_real_estate_improvements.json"

static var _improvements_cache: Array = []


static func load_improvements() -> Array:
	if not _improvements_cache.is_empty():
		return _improvements_cache
	var file := FileAccess.open(IMPROVEMENTS_PATH, FileAccess.READ)
	if file == null:
		push_error("RealEstateSystem: missing %s" % IMPROVEMENTS_PATH)
		return []
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		return []
	var raw_list: Array = (parsed as Dictionary).get("improvements", [])
	_improvements_cache = []
	for raw_variant in raw_list:
		if typeof(raw_variant) == TYPE_DICTIONARY:
			_improvements_cache.append((raw_variant as Dictionary).duplicate(true))
	return _improvements_cache


static func improvements_for(_state: RunState) -> Array:
	return load_improvements()


static func improvement_by_id(improvement_id: String) -> Dictionary:
	for raw_variant in load_improvements():
		if typeof(raw_variant) == TYPE_DICTIONARY and str((raw_variant as Dictionary).get("id", "")) == improvement_id:
			return raw_variant as Dictionary
	return {}


static func improvements_for_asset(state: RunState, asset: Dictionary) -> Array:
	if not state.is_capital_farm():
		return []
	var template_id: String = str(asset.get("templateId", asset.get("template_id", "")))
	if not Content.is_infrastructure_template(template_id):
		return []
	var applied: Array = asset.get("improvementsApplied", asset.get("improvements_applied", []))
	var out: Array = []
	for raw_variant in load_improvements():
		if typeof(raw_variant) != TYPE_DICTIONARY:
			continue
		var imp: Dictionary = raw_variant
		var imp_id: String = str(imp.get("id", ""))
		if imp_id in applied:
			continue
		var templates: Array = imp.get("templates", [])
		if templates.is_empty() or template_id in templates:
			out.append(imp.duplicate(true))
	return out


static func improve_cost(asset: Dictionary, imp: Dictionary) -> int:
	var valuation: int = int(asset.get("valuation", asset.get("markedValue", asset.get("marked_value", 0))))
	return int(round(float(valuation) * float(imp.get("cost_pct", 0.0))))


static func downstream_link_count(state: RunState, template_id: String) -> int:
	var owned: Dictionary = state.portfolio.owned_template_ids()
	var count := 0
	for conn: SupplyConnection in Content.connections:
		if conn.supplier == template_id and owned.has(conn.customer):
			count += 1
	return count


static func find_asset(state: RunState, asset_id: String) -> Dictionary:
	for raw_variant in state.portfolio.real_estate:
		if typeof(raw_variant) == TYPE_DICTIONARY and str((raw_variant as Dictionary).get("id", "")) == asset_id:
			return raw_variant as Dictionary
	return {}


static func apply_improvement(state: RunState, asset_id: String, improvement_id: String) -> Dictionary:
	var ap: Dictionary = ActionPointsSystem.require(state, 1)
	if not bool(ap.get("ok", false)):
		return ap

	var asset: Dictionary = find_asset(state, asset_id)
	if asset.is_empty():
		return {"ok": false, "error": "Property not found"}

	var imp: Dictionary = improvement_by_id(improvement_id)
	if imp.is_empty():
		return {"ok": false, "error": "Unknown improvement"}

	var available: Array = improvements_for_asset(state, asset)
	var allowed := false
	for avail_variant in available:
		if typeof(avail_variant) == TYPE_DICTIONARY and str((avail_variant as Dictionary).get("id", "")) == improvement_id:
			allowed = true
			break
	if not allowed:
		return {"ok": false, "error": "Improvement not available for this property"}

	var cost: int = improve_cost(asset, imp)
	if state.cash < cost:
		return {"ok": false, "error": "Not enough cash for %s (need %s)" % [str(imp.get("name", "")), MathUtil.fmt_money(cost)]}

	var val_before: int = int(asset.get("valuation", asset.get("markedValue", 0)))
	var rent_before: int = int(asset.get("rentPerTurn", asset.get("rent_per_turn", 0)))
	state.cash -= cost
	ActionPointsSystem.spend(state, 1)

	var val_boost: float = float(imp.get("val_boost", 0.0))
	var rent_boost: float = float(imp.get("rent_boost", 0.0))
	var val_after: int = int(round(float(val_before) * (1.0 + val_boost)))
	var rent_after: int = int(round(float(rent_before) * (1.0 + rent_boost)))
	asset["valuation"] = val_after
	asset["markedValue"] = val_after
	asset["rentPerTurn"] = rent_after

	if not asset.has("improvementsApplied"):
		asset["improvementsApplied"] = []
	(asset["improvementsApplied"] as Array).append(improvement_id)

	state.run_log.append(
		"%s at %s: %s (cost %s) · Val %s → %s (%s%s) · Rent %s → %s/qtr" % [
			str(imp.get("name", "Improvement")),
			str(asset.get("name", "Property")),
			str(imp.get("note", "")),
			MathUtil.fmt_money(cost),
			MathUtil.fmt_money(val_before),
			MathUtil.fmt_money(val_after),
			"+" if val_after >= val_before else "",
			MathUtil.fmt_money(val_after - val_before),
			MathUtil.fmt_money(rent_before),
			MathUtil.fmt_money(rent_after),
		]
	)

	return {
		"ok": true,
		"state": state,
		"asset": asset,
		"cost": cost,
		"valuationBefore": val_before,
		"valuationAfter": val_after,
		"rentBefore": rent_before,
		"rentAfter": rent_after,
	}
