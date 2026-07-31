# v2 profile generation — economic bounds + starting gauge (Negotiation Mechanics v2 §3, §6).
class_name NegotiationV2Profile
extends RefCounted

const _Data := preload("res://core/systems/negotiation_v2_data.gd")


static func build(
	ask_price: int,
	counterparty: Dictionary,
	state: RunState,
	opp: Dictionary,
	rng: SeededRng,
) -> Dictionary:
	var species_id := str(counterparty.get("speciesId", "hen"))
	if not _Data.SPECIES_CAPACITY_RANGES.has(species_id):
		species_id = "hen"

	var cap_range: Dictionary = _Data.SPECIES_CAPACITY_RANGES[species_id]
	var species_capacity: float = rng.randf_range(float(cap_range["min"]), float(cap_range["max"]))

	var situation_id := str(counterparty.get("businessSituation", _Data.pick_situation(opp, rng)))
	if not _Data.SITUATIONS.has(situation_id):
		situation_id = "stable_position"
	var situation: Dictionary = _Data.SITUATIONS[situation_id]

	var situation_capacity := 0.0
	if not bool(situation.get("stable", false)):
		situation_capacity = rng.randf_range(
			float(situation.get("capacity_min", 0.0)),
			float(situation.get("capacity_max", 0.0)),
		)

	var hard_floor_ratio: float = rng.randf_range(0.68, 0.86)
	var hard_floor: int = int(round(float(ask_price) * hard_floor_ratio))
	hard_floor = mini(hard_floor, int(round(float(ask_price) * (1.0 - _Data.GLOBAL_DISCOUNT_CAP))))

	var rep: Dictionary = _Data.reputation_tier(state.reputation if state else 12)
	var memory_adj: int = _Data.summarize_memory_gauge(counterparty)
	var leverage_score: float = float(counterparty.get("leverageScore", 0.5))
	var leverage: Dictionary = _Data.leverage_from_score(leverage_score)
	var personal_adj: int = CommunityNegotiationBridge.personal_relationship_gauge_adj(
		state,
		str(counterparty.get("communityNpcId", "")),
		species_id,
	)

	var gauge_start: int = clampi(
		_Data.GAUGE_BASE
		+ int(rep.get("gaugeAdj", 0))
		+ memory_adj
		+ int(leverage.get("gaugeAdj", 0))
		+ personal_adj,
		0,
		100,
	)

	var profile := {
		"version": 2,
		"askPrice": ask_price,
		"hardFloor": hard_floor,
		"globalDiscountCap": _Data.GLOBAL_DISCOUNT_CAP,
		"speciesId": species_id,
		"speciesCapacity": species_capacity,
		"situationId": situation_id,
		"situationLabel": str(situation.get("label", situation_id)),
		"situationCapacity": situation_capacity,
		"stablePosition": bool(situation.get("stable", false)),
		"leverageEconomicAdj": float(leverage.get("econAdj", 0.0)),
		"leverageGaugeAdj": int(leverage.get("gaugeAdj", 0)),
		"leverageLabel": str(leverage.get("label", "Balanced")),
		"reputationTier": str(rep.get("label", "Unknown")),
		"reputationGaugeAdj": int(rep.get("gaugeAdj", 0)),
		"memoryGaugeAdj": memory_adj,
		"moralityGaugeAdj": 0,
		"personalRelationshipGaugeAdj": personal_adj,
		"communityIntelLeverageScore": leverage_score,
		"gaugeStart": gauge_start,
		"speciesProgress": 0.0,
		"situationProgress": 0.0,
		"gauge": gauge_start,
		"previousGauge": gauge_start,
		"conversationMovement": 0,
		"offerMovement": 0,
		"acceptableValue": ask_price,
		"lastOfferValue": 0,
		"unlockedDiscount": 0.0,
		"severeLowballs": 0,
		"redLineViolated": false,
		"credibilityFailed": false,
		"tacticHistory": [],
		"discoveredFacts": [],
		"permittedTerms": [],
	}
	return CommunityNegotiationBridge.apply_profile_fields(state, counterparty, profile)


static func recalculate_economics(profile: Dictionary) -> Dictionary:
	var ask: int = int(profile.get("askPrice", 0))
	var hard_floor: int = int(profile.get("hardFloor", 0))
	if ask <= 0:
		return profile

	var species_progress_norm: float = float(profile.get("speciesProgress", 0.0)) / 100.0
	var species_unlock: float = _Data.SPECIES_BASELINE_UNLOCK + (1.0 - _Data.SPECIES_BASELINE_UNLOCK) * species_progress_norm
	var species_part: float = float(profile.get("speciesCapacity", 0.0)) * species_unlock
	if bool(profile.get("stablePosition", false)):
		species_part *= 0.75

	var situation_part: float = 0.0
	if not bool(profile.get("stablePosition", false)):
		var situation_progress_norm: float = float(profile.get("situationProgress", 0.0)) / 100.0
		var situation_unlock: float = _Data.SITUATION_BASELINE_UNLOCK + (1.0 - _Data.SITUATION_BASELINE_UNLOCK) * situation_progress_norm
		situation_part = float(profile.get("situationCapacity", 0.0)) * situation_unlock

	var raw_discount: float = species_part + situation_part + float(profile.get("leverageEconomicAdj", 0.0))
	var max_by_floor: float = 1.0 - float(hard_floor) / maxf(1.0, float(ask))
	var final_discount: float = minf(_Data.GLOBAL_DISCOUNT_CAP, minf(raw_discount, max_by_floor))
	final_discount = maxf(0.0, final_discount)

	var acceptable: int = maxi(hard_floor, int(round(float(ask) * (1.0 - final_discount))))
	profile["unlockedDiscount"] = final_discount
	profile["acceptableValue"] = acceptable
	return profile
