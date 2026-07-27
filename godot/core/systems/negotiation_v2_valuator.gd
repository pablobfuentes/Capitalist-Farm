# Risk-adjusted offer valuation (v2 §7.3–7.4).
class_name NegotiationV2Valuator
extends RefCounted

const _Data := preload("res://core/systems/negotiation_v2_data.gd")
const _Parser := preload("res://core/systems/negotiation_offer_parser.gd")


static func value_offer(
	offer: Dictionary,
	profile: Dictionary,
	counterparty: Dictionary,
	text: String = "",
) -> Dictionary:
	if offer.is_empty():
		return {"offerValue": 0, "cashValue": 0, "termBonus": 0, "riskPenalty": 0}

	var ask: int = int(profile.get("askPrice", 0))
	var total: int = int(offer.get("totalPrice", 0))
	var cash: int = int(offer.get("cashAtClosing", total))
	var terms: Array = offer.get("termsOffered", [])

	# Seller note: present value discount for deferred portion.
	var note_face: int = maxi(0, total - cash)
	var note_pv: int = int(round(float(note_face) * 0.92))
	var cash_value: int = cash + note_pv

	var term_bonus := 0
	var species_id := str(profile.get("speciesId", counterparty.get("speciesId", "")))
	var situation_id := str(profile.get("situationId", ""))
	var cap: int = int(round(float(ask) * _Data.SPECIES_PREF_BONUS_CAP_RATIO))

	for t in terms:
		var tl := str(t).to_lower()
		term_bonus += _term_value(tl, species_id, situation_id, ask)

	term_bonus = mini(term_bonus, cap)

	# Closing speed certainty bonus for Hen / cash pressure.
	if str(offer.get("closingSpeed", "")) == "fast":
		term_bonus += int(round(float(ask) * 0.005))

	var risk_penalty := 0
	if note_face > 0 and cash < int(float(total) * 0.5):
		risk_penalty += int(round(float(note_face) * 0.08))
	if species_id == "hen" and note_face > int(float(total) * 0.25):
		risk_penalty += int(round(float(note_face) * 0.05))

	var offer_value: int = cash_value + term_bonus - risk_penalty
	return {
		"offerValue": offer_value,
		"cashValue": cash_value,
		"termBonus": term_bonus,
		"riskPenalty": risk_penalty,
		"headlineTotal": total,
	}


static func offer_quality_gauge_delta(offer_value: int, acceptable_value: int, ask_price: int) -> int:
	if ask_price <= 0 or offer_value <= 0:
		return 0
	var gap: float = float(offer_value - acceptable_value) / float(ask_price)
	if gap >= 0.05:
		return 20
	if gap >= 0.0:
		return int(round(lerpf(10.0, 20.0, gap / 0.05)))
	if gap >= -0.05:
		return int(round(lerpf(0.0, 10.0, 1.0 + gap / 0.05)))
	if gap >= -0.15:
		return int(round(lerpf(-15.0, -5.0, (gap + 0.15) / 0.10)))
	return -22


static func is_severe_lowball(offer_value: int, hard_floor: int) -> bool:
	return offer_value > 0 and offer_value < hard_floor


static func economic_status_hint(offer_value: int, acceptable_value: int, gauge: int, ready: bool) -> String:
	if ready:
		return "Ready to Close"
	if offer_value <= 0:
		return "No offer"
	if offer_value >= acceptable_value and gauge < _Data.GAUGE_READY:
		return "Terms acceptable; confidence still needed"
	var gap_pct: float = float(acceptable_value - offer_value) / maxf(1.0, float(acceptable_value))
	if gap_pct <= 0.03:
		return "Terms nearly workable"
	return "Terms too far apart"


static func _term_value(term_lower: String, species_id: String, situation_id: String, ask: int) -> int:
	var base := int(round(float(ask) * 0.015))
	if _re_match("employee|staff|retention|continuity|legacy|worker", term_lower):
		if species_id == "horse" or situation_id == "retirement_transition":
			return int(round(float(ask) * 0.025))
		return base * 2
	if _re_match("warrant|inspect|guarantee|guarantee|coverage|collateral|escrow", term_lower):
		if species_id in ["donkey", "hen"]:
			return int(round(float(ask) * 0.012))
		return base
	if _re_match("fast close|all cash|deposit|milestone|schedule", term_lower):
		if species_id == "hen" or situation_id == "cash_pressure":
			return int(round(float(ask) * 0.018))
		return base
	if _re_match("earn.?out|exclusiv|option|upside|royalt|territor", term_lower):
		if species_id == "pig":
			return int(round(float(ask) * 0.02))
		return base
	if _re_match("reference|reputation|comparable|testimonial|social", term_lower):
		if species_id == "sheep":
			return int(round(float(ask) * 0.02))
		return base
	return 0


static func _re_match(pattern: String, text: String) -> bool:
	return RegEx.create_from_string(pattern).search(text) != null
