class_name UpgradeSystem
extends RefCounted

const _SynergySystem := preload("res://core/systems/synergy_system.gd")

const MAX_TIER := 3
const HIRE_PER_TIER := 0.08
const MARKETING_PER_TIER := 0.08
const AUTOMATION_PER_TIER := 0.06
const CARE_CRISIS_PER_TIER := 0.8
const MANAGER_BUNDLE := 1.03
const MANAGER_AUTOPILOT_BONUS := 1
const MANAGER_DRIFT_PER_QTR := 0.005
const BASE_NEGLECT_TURNS := 4
const MANAGER_NEGLECT_GRACE := 2
const TIER_COST_MULT: Array[float] = [1.0, 1.35, 1.6]

const TRACKS: Dictionary = {
	"hire": {"name": "Hire people", "max_tier": 3, "effect_per_tier": HIRE_PER_TIER, "benefit_points": 8},
	"marketing": {"name": "Marketing", "max_tier": 3, "effect_per_tier": MARKETING_PER_TIER, "benefit_points": 8},
	"automation": {"name": "Automation", "max_tier": 3, "effect_per_tier": AUTOMATION_PER_TIER, "benefit_points": 6},
	"care": {"name": "Customer care", "max_tier": 3, "benefit_points": 8},
	"manager": {"name": "Manager", "max_tier": 1, "benefit_points": 32},
}


static func is_active(state: RunState) -> bool:
	return state != null and state.is_capital_farm() and state.farm_upgrade_v2


static func default_upgrades() -> Dictionary:
	return {"hire": 0, "marketing": 0, "automation": 0, "care": 0, "manager": false}


static func default_manager_drift() -> Dictionary:
	return {"hire": 0.0, "marketing": 0.0, "automation": 0.0}


static func normalize_upgrades(biz: BusinessInstance) -> Dictionary:
	if biz.upgrades.is_empty():
		biz.upgrades = default_upgrades()
	var u: Dictionary = biz.upgrades
	u["hire"] = clampi(int(u.get("hire", 0)), 0, MAX_TIER)
	u["marketing"] = clampi(int(u.get("marketing", 0)), 0, MAX_TIER)
	u["automation"] = clampi(int(u.get("automation", 0)), 0, MAX_TIER)
	u["care"] = clampi(int(u.get("care", 0)), 0, MAX_TIER)
	u["manager"] = bool(u.get("manager", false))
	biz.upgrades = u
	return u


static func ensure_business_upgrades(biz: BusinessInstance) -> void:
	if biz == null:
		return
	normalize_upgrades(biz)
	recompute_upgrade_stats(biz)


static func ensure_portfolio_upgrades(state: RunState) -> void:
	if not is_active(state):
		return
	for biz: BusinessInstance in state.portfolio.businesses:
		ensure_business_upgrades(biz)


static func recompute_upgrade_stats(biz: BusinessInstance) -> Dictionary:
	var u: Dictionary = normalize_upgrades(biz)
	var drift: Dictionary = biz.manager_drift if bool(u.get("manager", false)) else default_manager_drift()

	var capacity_mult: float = 1.0 + float(u.get("hire", 0)) * HIRE_PER_TIER + float(drift.get("hire", 0.0))
	var demand_mult: float = 1.0 + float(u.get("marketing", 0)) * MARKETING_PER_TIER + float(drift.get("marketing", 0.0))
	var opex_mult: float = pow(1.0 - AUTOMATION_PER_TIER, float(u.get("automation", 0))) * (1.0 - float(drift.get("automation", 0.0)))
	var care_crisis_mult: float = pow(CARE_CRISIS_PER_TIER, float(u.get("care", 0)))

	if bool(u.get("manager", false)):
		capacity_mult *= MANAGER_BUNDLE
		demand_mult *= MANAGER_BUNDLE
		opex_mult *= MANAGER_BUNDLE

	var tmpl := Content.get_template(biz.template_id)
	var base_ap: int = tmpl.autopilot if tmpl else 3
	var effective_autopilot: int = mini(5, base_ap + (MANAGER_AUTOPILOT_BONUS if bool(u.get("manager", false)) else 0))

	biz.upgrade_stats = {
		"capacityMult": capacity_mult,
		"demandMult": demand_mult,
		"opexMult": opex_mult,
		"careCrisisMult": care_crisis_mult,
		"effectiveAutopilot": effective_autopilot,
		"neglectGrace": MANAGER_NEGLECT_GRACE if bool(u.get("manager", false)) else 0,
	}
	return biz.upgrade_stats


static func business_capacity_mult(state: RunState, template_id: String) -> float:
	var biz := _business_for_template(state, template_id)
	if biz == null or not is_active(state):
		return 1.0
	ensure_business_upgrades(biz)
	return float(biz.upgrade_stats.get("capacityMult", 1.0))


static func business_demand_mult(state: RunState, template_id: String) -> float:
	var biz := _business_for_template(state, template_id)
	if biz == null or not is_active(state):
		return 1.0
	ensure_business_upgrades(biz)
	return float(biz.upgrade_stats.get("demandMult", 1.0))


static func business_opex_mult(biz: BusinessInstance) -> float:
	if biz == null:
		return 1.0
	ensure_business_upgrades(biz)
	return float(biz.upgrade_stats.get("opexMult", 1.0))


static func business_care_crisis_mult(biz: BusinessInstance) -> float:
	if biz == null:
		return 1.0
	ensure_business_upgrades(biz)
	return float(biz.upgrade_stats.get("careCrisisMult", 1.0))


static func consumer_demand_rev_factor(biz: BusinessInstance, state: RunState, synergies: Array) -> float:
	if biz == null or not is_active(state):
		return 1.0
	var tmpl := Content.get_template(biz.template_id)
	if tmpl == null or tmpl.layer != "consumer_channel":
		return 1.0

	ensure_business_upgrades(biz)
	var demand_mult: float = float(biz.upgrade_stats.get("demandMult", 1.0))
	if demand_mult <= 1.0:
		return 1.0

	var inbound_fulfill := 1.0
	var inbound: Array = synergies.filter(func(s: Variant) -> bool:
		return typeof(s) == TYPE_DICTIONARY and str((s as Dictionary).get("customerId", "")) == biz.id
	)
	if not inbound.is_empty():
		var sum := 0.0
		for syn_variant in inbound:
			sum += float((syn_variant as Dictionary).get("fulfillRatio", 1.0))
		inbound_fulfill = sum / float(inbound.size())
	inbound_fulfill = MathUtil.clamp(inbound_fulfill, 0.0, 1.0)

	var own_cap_factor := 1.0
	if tmpl.consumer_capacity_units != null:
		var cap_units: float = float(tmpl.consumer_capacity_units) * float(biz.upgrade_stats.get("capacityMult", 1.0))
		var requested: float = cap_units * demand_mult
		own_cap_factor = cap_units / maxf(requested, 1.0) if cap_units > 0.0 else 1.0
		own_cap_factor = MathUtil.clamp(own_cap_factor, 0.35, 1.0)

	var cap_factor: float = inbound_fulfill * own_cap_factor
	return 1.0 + (demand_mult - 1.0) * cap_factor


static func can_apply_track(biz: BusinessInstance, track_id: String) -> Dictionary:
	if biz == null or not TRACKS.has(track_id):
		return {"ok": false, "reason": "Unknown upgrade."}
	normalize_upgrades(biz)
	var tmpl := Content.get_template(biz.template_id)
	if track_id == "manager":
		if bool(biz.upgrades.get("manager", false)):
			return {"ok": false, "reason": "Manager already in place this level."}
		return {"ok": true}
	if track_id == "marketing" and tmpl != null and not tmpl.marketing_eligible:
		return {"ok": false, "reason": "Infrastructure asset — use hire or automation."}
	if int(biz.upgrades.get(track_id, 0)) >= MAX_TIER:
		return {"ok": false, "reason": "Max tier reached."}
	return {"ok": true}


static func business_improve_cost(biz: BusinessInstance, track_id: String, state: RunState) -> int:
	if biz == null:
		return 0
	var check: Dictionary = can_apply_track(biz, track_id)
	if not bool(check.get("ok", false)):
		return 0
	var val: int = estimate_valuation(biz, state)
	if track_id == "manager":
		return int(round(float(val) * _tier_cost_fraction("manager", 0)))
	var tier_index: int = int(biz.upgrades.get(track_id, 0))
	return int(round(float(val) * _tier_cost_fraction(track_id, tier_index)))


static func apply_upgrade(biz: BusinessInstance, track_id: String) -> bool:
	var check: Dictionary = can_apply_track(biz, track_id)
	if not bool(check.get("ok", false)):
		return false
	if track_id == "manager":
		biz.upgrades["manager"] = true
	else:
		biz.upgrades[track_id] = int(biz.upgrades.get(track_id, 0)) + 1
	if track_id == "care":
		biz.crisis_mult = MathUtil.clamp(biz.crisis_mult * CARE_CRISIS_PER_TIER, 0.15, 1.0)
		biz.client_health = mini(100, biz.client_health + 8)
		biz.supplier_health = mini(100, biz.supplier_health + 8)
	recompute_upgrade_stats(biz)
	return true


static func tier_point_sum(biz: BusinessInstance) -> int:
	if biz == null:
		return 0
	var u: Dictionary = normalize_upgrades(biz)
	return int(u.get("hire", 0)) + int(u.get("marketing", 0)) + int(u.get("automation", 0)) + int(u.get("care", 0))


static func upgrade_tier_sum(biz: BusinessInstance) -> int:
	var u: Dictionary = normalize_upgrades(biz)
	return tier_point_sum(biz) + (1 if bool(u.get("manager", false)) else 0)


static func is_eligible_for_major_upgrade(biz: BusinessInstance) -> bool:
	if biz == null or biz.level >= 3:
		return false
	var required := 4 if biz.level == 1 else (10 if biz.level == 2 else 0)
	return required > 0 and upgrade_tier_sum(biz) >= required


static func reset_upgrades_for_level(biz: BusinessInstance) -> void:
	if biz == null:
		return
	biz.upgrades = default_upgrades()
	biz.manager_drift = default_manager_drift()
	recompute_upgrade_stats(biz)


static func urgent_freq_mult_for_business(biz: BusinessInstance) -> float:
	if biz == null:
		return 1.0
	var tmpl := Content.get_template(biz.template_id)
	if tmpl == null:
		return 1.0
	var ap: int = int(biz.upgrade_stats.get("effectiveAutopilot", tmpl.autopilot if tmpl else 3))
	return MathUtil.clamp(1.0 + float(5 - ap) * 0.08, 0.85, 1.35)


static func neglect_threshold(biz: BusinessInstance) -> int:
	if biz == null:
		return BASE_NEGLECT_TURNS
	ensure_business_upgrades(biz)
	return BASE_NEGLECT_TURNS + int(biz.upgrade_stats.get("neglectGrace", 0))


static func mark_business_care(biz: BusinessInstance, turn: int) -> void:
	SynergySystem.mark_business_care(biz, turn)


static func apply_upgrade_command(state: RunState, business_id: String, track_id: String) -> Dictionary:
	if not is_active(state):
		return {"ok": false, "error": "Upgrades not active in this mode"}
	var ap: Dictionary = ActionPointsSystem.require(state, 1)
	if not bool(ap.get("ok", false)):
		return ap
	var biz := find_business(state, business_id)
	if biz == null:
		return {"ok": false, "error": "Business not found"}
	var check: Dictionary = can_apply_track(biz, track_id)
	if not bool(check.get("ok", false)):
		return {"ok": false, "error": str(check.get("reason", "Cannot apply"))}
	var cost: int = business_improve_cost(biz, track_id, state)
	if state.cash < cost:
		return {"ok": false, "error": "Insufficient cash"}
	if not apply_upgrade(biz, track_id):
		return {"ok": false, "error": "Apply failed"}
	state.cash -= cost
	biz.marked_value = estimate_valuation(biz, state)
	mark_business_care(biz, state.turn)
	ActionPointsSystem.spend(state, 1)
	return {"ok": true, "state": state, "business": biz, "cost": cost}


static func compute_upgrade_preview(state: RunState, business_id: String, track_id: String) -> Dictionary:
	if not is_active(state):
		return {"canApply": false, "reason": "Upgrades inactive"}
	var biz := find_business(state, business_id)
	if biz == null:
		return {"canApply": false, "reason": "Business not found"}
	var check: Dictionary = can_apply_track(biz, track_id)
	if not bool(check.get("ok", false)):
		return {"canApply": false, "reason": str(check.get("reason", ""))}

	var profit_before: int = quarterly_profit_for_business(biz, state)
	var cost: int = business_improve_cost(biz, track_id, state)

	var clone: RunState = RunState.from_dict(state.to_dict())
	var clone_biz := find_business(clone, business_id)
	apply_upgrade(clone_biz, track_id)
	var profit_after: int = quarterly_profit_for_business(clone_biz, clone)

	var capacity_before: Variant = capacity_units_for_business(state, biz)
	var capacity_after: Variant = capacity_units_for_business(clone, clone_biz)
	var demand_before: float = float(biz.upgrade_stats.get("demandMult", 1.0))
	var demand_after: float = float(clone_biz.upgrade_stats.get("demandMult", 1.0))

	return {
		"canApply": true,
		"trackId": track_id,
		"cost": cost,
		"profitBefore": profit_before,
		"profitAfter": profit_after,
		"profitDelta": profit_after - profit_before,
		"tierNext": 1 if track_id == "manager" else int(biz.upgrades.get(track_id, 0)) + 1,
		"capacityBefore": capacity_before,
		"capacityAfter": capacity_after,
		"capacityDelta": (int(capacity_after) - int(capacity_before)) if capacity_before != null and capacity_after != null else 0,
		"demandMultBefore": demand_before,
		"demandMultAfter": demand_after,
	}


static func quarterly_profit_for_business(biz: BusinessInstance, state: RunState) -> int:
	ensure_portfolio_upgrades(state)
	var synergies: Array = _SynergySystem.compute_synergies(state)
	var applied: Dictionary = _SynergySystem.apply_to_business(biz, synergies, state, {})
	return int(applied.get("rev", 0)) - int(applied.get("cost", 0))


static func estimate_valuation(biz: BusinessInstance, state: RunState) -> int:
	var profit: int = quarterly_profit_for_business(biz, state)
	var multiple: float = 4.0 - 0.5 * 1.2 - 0.1 * 1.5
	var val: float = maxf(1000.0, float(profit) * 4.0 * MathUtil.clamp(multiple / 2.5, 0.6, 1.6))
	if biz.marked_value > 0:
		val = maxf(val, float(biz.marked_value))
	return int(round(val))


static func apply_manager_passive_drift(state: RunState) -> void:
	if not is_active(state):
		return
	for biz: BusinessInstance in state.portfolio.businesses:
		if not bool(biz.upgrades.get("manager", false)):
			continue
		var drift: Dictionary = biz.manager_drift if not biz.manager_drift.is_empty() else default_manager_drift()
		for axis: String in ["hire", "marketing", "automation"]:
			var tier: int = int(biz.upgrades.get(axis, 0))
			if tier >= MAX_TIER:
				continue
			var per_tier: float = HIRE_PER_TIER
			if axis == "marketing":
				per_tier = MARKETING_PER_TIER
			elif axis == "automation":
				per_tier = AUTOMATION_PER_TIER
			var headroom: float = float(MAX_TIER - tier) * per_tier
			drift[axis] = float(drift.get(axis, 0.0)) + minf(MANAGER_DRIFT_PER_QTR, headroom)
		biz.manager_drift = drift
		recompute_upgrade_stats(biz)


static func find_business(state: RunState, business_id: String) -> BusinessInstance:
	for biz: BusinessInstance in state.portfolio.businesses:
		if biz.id == business_id:
			return biz
	return null


static func render_tier_pips(tier: int, max_tier: int) -> String:
	var filled := mini(tier, max_tier)
	return "●".repeat(filled) + "○".repeat(maxi(0, max_tier - filled))


static func capacity_units_for_business(state: RunState, biz: BusinessInstance) -> Variant:
	var cap: Variant = SynergySystem.effective_capacity(state, biz.template_id)
	if cap != null:
		return cap
	var tmpl := Content.get_template(biz.template_id)
	if tmpl != null and tmpl.consumer_capacity_units != null:
		return int(round(float(tmpl.consumer_capacity_units) * float(biz.upgrade_stats.get("capacityMult", 1.0))))
	return null


static func format_track_effect_line(preview: Dictionary, track_id: String) -> String:
	if not bool(preview.get("canApply", false)):
		return ""
	var parts: PackedStringArray = []
	if track_id == "hire":
		var before: Variant = preview.get("capacityBefore")
		var after: Variant = preview.get("capacityAfter")
		if before != null and after != null and int(after) != int(before):
			parts.append("Cap %d → %d (+%d)" % [int(before), int(after), int(after) - int(before)])
	if track_id == "marketing":
		parts.append("Demand ×%.2f → ×%.2f" % [
			float(preview.get("demandMultBefore", 1.0)),
			float(preview.get("demandMultAfter", 1.0)),
		])
	if track_id == "automation":
		parts.append("Opex lever — see profit preview")
	if track_id == "manager":
		parts.append("Autopilot +1 · all levers ×%.2f" % MANAGER_BUNDLE)
	return " · ".join(parts)


static func autopilot_display(biz: BusinessInstance) -> String:
	ensure_business_upgrades(biz)
	var ap: int = int(biz.upgrade_stats.get("effectiveAutopilot", 3))
	return "★".repeat(ap) + "☆".repeat(maxi(0, 5 - ap))


static func _business_for_template(state: RunState, template_id: String) -> BusinessInstance:
	for biz: BusinessInstance in state.portfolio.businesses:
		if biz.template_id == template_id:
			return biz
	return null


static func _tier_cost_fraction(track_id: String, tier_index: int) -> float:
	if track_id == "manager":
		return 0.15
	var track: Dictionary = TRACKS.get(track_id, {})
	var mult: float = TIER_COST_MULT[tier_index] if tier_index < TIER_COST_MULT.size() else 1.6
	return float(track.get("benefit_points", 8)) / 100.0 * mult
