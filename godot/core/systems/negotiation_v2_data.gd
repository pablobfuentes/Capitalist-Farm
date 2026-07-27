# Negotiation Mechanics v2 — constants and lookup tables (see docs/Capital_Farm_Negotiation_Mechanics_v2).
class_name NegotiationV2Data
extends RefCounted

const GLOBAL_DISCOUNT_CAP := 0.35
const GAUGE_BASE := 50  # Neutral starting point (middle of bar) before dialogue; rep/memory/leverage shift from here.
const GAUGE_READY := 55  # Willingness gate when economics are met (Close zone and above).
const GAUGE_COLLAPSE := 14
const GAUGE_PATIENCE_FLOOR := 55
const SPECIES_PREF_BONUS_CAP_RATIO := 0.08
# Portion of hidden capacity that is "in play" before dialogue; progress unlocks the rest.
const SPECIES_BASELINE_UNLOCK := 0.35
const SITUATION_BASELINE_UNLOCK := 0.40
const PROGRESS_PRIMARY_DELTA := 20.0
const PROGRESS_SECONDARY_DELTA := 12.0
const PROGRESS_TURN_CAP := 32.0
const FIRST_SPECIES_PROGRESS_FLOOR := 15.0
const FIRST_SITUATION_PROGRESS_FLOOR := 12.0

const SPECIES_CAPACITY_RANGES := {
	# Ranges widened (+10% min, +20% max cap) so engaged play reaches meaningful discounts.
	"pig": {"min": 0.20, "max": 0.35},
	"donkey": {"min": 0.15, "max": 0.30},
	"sheep": {"min": 0.25, "max": 0.35},
	"goat": {"min": 0.20, "max": 0.35},
	"horse": {"min": 0.30, "max": 0.35},
	"hen": {"min": 0.15, "max": 0.35},
}

const SITUATIONS := {
	"cash_pressure": {
		"id": "cash_pressure",
		"label": "Cash Pressure / Failing",
		"capacity_min": 0.08,
		"capacity_max": 0.15,
		"stable": false,
	},
	"retirement_transition": {
		"id": "retirement_transition",
		"label": "Retirement / Transition",
		"capacity_min": 0.05,
		"capacity_max": 0.10,
		"stable": false,
	},
	"entrepreneur_growth": {
		"id": "entrepreneur_growth",
		"label": "Entrepreneur / Growth",
		"capacity_min": 0.05,
		"capacity_max": 0.10,
		"stable": false,
	},
	"stable_position": {
		"id": "stable_position",
		"label": "Stable Position",
		"capacity_min": 0.0,
		"capacity_max": 0.0,
		"stable": true,
	},
}

# Species-aligned tactic tags (positive routes).
const SPECIES_POSITIVE_TAGS := {
	"pig": ["evidence", "realistic_numbers", "verified_history", "option_package", "volume_commitment"],
	"donkey": ["evidence", "realistic_numbers", "verified_history", "warranty", "inspection", "guarantee", "risk_sharing"],
	"sheep": ["reputation", "testimonial", "comparable_deal", "respected_partner", "social_proof", "warm_rapport"],
	"goat": ["firm_boundary", "reciprocal_concession", "option_package", "patience", "credible_walkaway", "volume_commitment"],
	"horse": ["warm_rapport", "small_talk", "legacy", "employee_care", "continuity", "promise_reference", "reciprocity"],
	"hen": ["warm_rapport", "cash_upfront", "fast_closing", "warranty", "inspection", "guarantee", "realistic_numbers"],
}

const SPECIES_NEGATIVE_TAGS := {
	"pig": ["pressure", "aggression", "lowball"],
	"donkey": ["lowball", "unsupported_claim", "exaggeration", "pressure"],
	"sheep": ["lowball", "aggression"],
	"goat": ["aggression", "pressure"],
	"horse": ["pressure", "aggression", "lowball"],
	"hen": ["aggression", "pressure", "complex_structure", "vague_term"],
}

const SITUATION_POSITIVE_TAGS := {
	"cash_pressure": ["cash_upfront", "fast_closing", "realistic_numbers", "guarantee"],
	"retirement_transition": ["legacy", "employee_care", "continuity", "warm_rapport", "promise_reference"],
	"entrepreneur_growth": ["volume_commitment", "option_package", "realistic_numbers", "comparable_deal"],
	"stable_position": [],
}

const GAUGE_ZONES := [
	{"max": 14, "id": "collapsing", "label": "Deal Collapsing", "hint": "They are close to ending the conversation."},
	{"max": 34, "id": "resistant", "label": "Resistant", "hint": "Your position is moving away from agreement."},
	{"max": 54, "id": "listening", "label": "Listening", "hint": "They are still considering the deal."},
	{"max": 74, "id": "close", "label": "Close", "hint": "You are close, but something is still missing."},
	{"max": 100, "id": "ready", "label": "Ready to Close", "hint": "Terms and willingness are aligned."},
]


static func species_tag_hit(species_id: String, tags: Array) -> bool:
	var positives: Array = SPECIES_POSITIVE_TAGS.get(species_id, [])
	for tag in tags:
		var t := str(tag)
		if t in positives or t in ["warm_rapport", "small_talk", "patience"]:
			return true
	return false


static func situation_tag_hit(situation_id: String, tags: Array) -> bool:
	if situation_id == "stable_position":
		return false
	var positives: Array = SITUATION_POSITIVE_TAGS.get(situation_id, [])
	for tag in tags:
		var t := str(tag)
		if t in positives:
			return true
		if situation_id == "cash_pressure" and t in ["cash_upfront", "fast_closing"]:
			return true
		if situation_id == "retirement_transition" and t in ["employee_care", "legacy", "continuity"]:
			return true
	return false


static func reputation_tier(reputation: int) -> Dictionary:
	if reputation >= 80:
		return {"id": "market_anchor", "label": "Market Anchor", "gaugeAdj": 10}
	if reputation >= 55:
		return {"id": "regional_player", "label": "Regional Player", "gaugeAdj": 7}
	if reputation >= 35:
		return {"id": "trusted_operator", "label": "Trusted Operator", "gaugeAdj": 4}
	if reputation >= 18:
		return {"id": "local_name", "label": "Local Name", "gaugeAdj": 0}
	return {"id": "unknown", "label": "Unknown", "gaugeAdj": 0}


static func summarize_memory_gauge(counterparty: Dictionary, include_baseline_trust: bool = false) -> int:
	var mem: Dictionary = counterparty.get("relationshipMemory", {})
	if typeof(mem) != TYPE_DICTIONARY:
		mem = {}
	var score := 0
	score += int(mem.get("promisesKept", 0)) * 4
	score -= int(mem.get("promisesBroken", 0)) * 8
	var grievances: Array = mem.get("grievances", [])
	if grievances is Array:
		score -= grievances.size() * 6
	var last_q: Variant = mem.get("lastDealQuality", null)
	if last_q != null:
		score += int(round((float(last_q) - 55.0) / 45.0 * 8.0))
	if include_baseline_trust:
		var trust: float = float(mem.get("trust", counterparty.get("trust", 0.5)))
		score += int(round((trust - 0.5) * 20.0))
	return clampi(score, -25, 25)


static func leverage_from_score(score: float) -> Dictionary:
	var s := clampf(score, 0.0, 1.0)
	var gauge_adj := int(round((s - 0.5) * 40.0))
	var econ_adj := clampf((s - 0.5) * 0.10, -0.05, 0.05)
	var label := "Balanced"
	if s < 0.25:
		label = "Weak"
	elif s < 0.4:
		label = "Limited"
	elif s > 0.75:
		label = "Dominant"
	elif s > 0.6:
		label = "Strong"
	return {"score": s, "gaugeAdj": clampi(gauge_adj, -20, 20), "econAdj": econ_adj, "label": label}


static func gauge_zone(gauge: int) -> Dictionary:
	var g := clampi(gauge, 0, 100)
	for zone in GAUGE_ZONES:
		if g <= int(zone.get("max", 100)):
			return zone
	return GAUGE_ZONES[GAUGE_ZONES.size() - 1]


static func pick_situation(opp: Dictionary, rng: SeededRng) -> String:
	if bool(opp.get("distressed", false)) or str(opp.get("urgencyTag", "")) == "cash_pressure":
		return "cash_pressure"
	var roll := rng.randf()
	if roll < 0.22:
		return "cash_pressure"
	if roll < 0.44:
		return "retirement_transition"
	if roll < 0.66:
		return "entrepreneur_growth"
	return "stable_position"
