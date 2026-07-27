# Pre-negotiation v2 snapshot — built during Investigate (1 AP) so intel matches opening terms.
class_name NegotiationV2Preview
extends RefCounted

const _V2 := preload("res://core/systems/negotiation_v2_engine.gd")
const _V2Data := preload("res://core/systems/negotiation_v2_data.gd")


static func build_for_opportunity(state: RunState, opp: Dictionary) -> Dictionary:
	if opp.is_empty() or state == null:
		return {}

	var price: int = int(opp.get("price", 0))
	if price <= 0:
		return {}

	var cp: Dictionary = opp.get("counterparty", {})
	if typeof(cp) != TYPE_DICTIONARY:
		cp = {}
	else:
		cp = cp.duplicate(true)

	_ensure_counterparty_v2_fields(cp, opp, state, price)

	var opp_id := str(opp.get("id", ""))
	var seed: int = NegotiationV2Engine.profile_seed(state, price, opp_id)
	var profile: Dictionary = _V2.initialize_profile(price, cp, state, opp, seed)
	var keywords: PackedStringArray = negotiation_keywords(
		str(profile.get("speciesId", "")),
		str(profile.get("situationId", "")),
	)

	return {
		"profile": profile,
		"askPrice": price,
		"hardFloor": int(profile.get("hardFloor", 0)),
		"openingDiscountPct": float(profile.get("unlockedDiscount", 0.0)),
		"openingAcceptable": int(profile.get("acceptableValue", price)),
		"speciesId": str(profile.get("speciesId", "")),
		"speciesLabel": str(profile.get("speciesId", "")).capitalize(),
		"situationId": str(profile.get("situationId", "")),
		"situationLabel": str(profile.get("situationLabel", "")),
		"keywords": keywords,
		"profileSeed": seed,
	}


static func attach_to_opportunity(state: RunState, opp: Dictionary) -> Dictionary:
	var preview: Dictionary = build_for_opportunity(state, opp)
	if preview.is_empty():
		return preview

	var cp: Dictionary = opp.get("counterparty", {})
	if typeof(cp) != TYPE_DICTIONARY:
		cp = {}
	else:
		cp = cp.duplicate(true)

	_ensure_counterparty_v2_fields(cp, opp, state, int(opp.get("price", 0)))
	opp["counterparty"] = cp

	opp["v2Preview"] = preview
	return preview


static func format_intel_block(preview: Dictionary, ask_price: int = 0) -> String:
	if preview.is_empty():
		return ""

	var ask: int = ask_price if ask_price > 0 else int(preview.get("askPrice", 0))
	var discount_pct: float = float(preview.get("openingDiscountPct", 0.0)) * 100.0
	var floor: int = int(preview.get("hardFloor", 0))
	var acceptable: int = int(preview.get("openingAcceptable", ask))
	var species_label := str(preview.get("speciesLabel", "Seller"))
	var situation_label := str(preview.get("situationLabel", ""))

	var lines: PackedStringArray = [
		"NEGOTIATION ECONOMICS",
		"%s · %s" % [species_label, situation_label] if not situation_label.is_empty() else species_label,
		"Opening discount unlocked: %.1f%%" % discount_pct,
		"Hard floor (minimum risk-adjusted value): %s" % MathUtil.fmt_money(floor),
		"Opening workable target: ~%s" % MathUtil.fmt_money(acceptable),
		"",
		"Phrases that unlock progress (use in your pitch):",
	]
	for kw in preview.get("keywords", []):
		lines.append("• \"%s\"" % str(kw))

	return "\n".join(lines)


static func log_summary(preview: Dictionary) -> String:
	if preview.is_empty():
		return ""
	return "opening discount %.1f%% · hard floor %s · target ~%s" % [
		float(preview.get("openingDiscountPct", 0.0)) * 100.0,
		MathUtil.fmt_money(int(preview.get("hardFloor", 0))),
		MathUtil.fmt_money(int(preview.get("openingAcceptable", 0))),
	]


static func negotiation_keywords(species_id: String, situation_id: String) -> PackedStringArray:
	var phrases: PackedStringArray = []

	match species_id:
		"sheep":
			phrases.append("reputation and community trust")
			phrases.append("references or respected partner role")
		"hen":
			phrases.append("all cash at closing")
			phrases.append("fast close with inspection window")
		"donkey":
			phrases.append("reviewed records and conservative numbers")
			phrases.append("inspection rights and written warranty")
		"horse":
			phrases.append("employee retention through transition")
			phrases.append("legacy respect and continuity")
		"pig":
			phrases.append("earn-out or upside structure")
			phrases.append("exclusivity or volume commitment")
		"goat":
			phrases.append("full package — price, cash, timeline together")
			phrases.append("two concrete terms, not price alone")
		_:
			phrases.append("clear price and structured terms")
			phrases.append("fair dealing and realistic numbers")

	match situation_id:
		"cash_pressure":
			phrases.append("all cash, fast close, no seller note")
		"retirement_transition":
			phrases.append("keep the team and honor what they built")
		"entrepreneur_growth":
			phrases.append("growth plan, territory, or volume partnership")
		"stable_position":
			phrases.append("clean all-cash close, no complicated structure")
		_:
			phrases.append("match your offer to what they care about")

	var out: PackedStringArray = []
	var seen: Dictionary = {}
	for phrase in phrases:
		var key := str(phrase).to_lower()
		if seen.has(key):
			continue
		seen[key] = true
		out.append(str(phrase))
		if out.size() >= 3:
			break

	while out.size() < 3:
		out.append("name your price after terms")
	return out


static func _ensure_counterparty_v2_fields(
	counterparty: Dictionary,
	opp: Dictionary,
	state: RunState,
	price: int,
) -> void:
	if not counterparty.has("businessSituation"):
		counterparty["businessSituation"] = _V2Data.pick_situation(opp, SeededRng.new(state.run_seed + price))
	if not counterparty.has("leverageScore"):
		counterparty["leverageScore"] = 0.5
	if not counterparty.has("relationshipMemory"):
		counterparty["relationshipMemory"] = {
			"trust": counterparty.get("trust", 0.5),
			"promisesKept": 0,
			"promisesBroken": 0,
			"grievances": [],
		}
