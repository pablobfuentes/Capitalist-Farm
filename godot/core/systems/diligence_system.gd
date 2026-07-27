# Seller diligence + Investigate (1 AP) — port of MVP ensureSellerDiligence / investigate().
class_name DiligenceSystem
extends RefCounted

const _Archetypes := preload("res://core/content/negotiation_archetypes.gd")
const _V2Preview := preload("res://core/systems/negotiation_v2_preview.gd")

const MOTIVATOR_LABELS: Dictionary = {
	"relationship": "Relationship — trust, fair dealing, and long-term commitment move them most.",
	"emotion": "Emotion — legacy, people, and personal stakes move them most.",
	"greed": "Economics — price, terms, speed, and certainty move them most.",
}

const CONCESSION_PATIENCE: Dictionary = {
	"fast": "Moves quickly — 2–3 credible rounds may be enough if you match what they care about.",
	"medium": "Will stay at the table ~4–5 rounds with structured, serious offers.",
	"slow": "Patient and stubborn — expect 5+ rounds; rushing or lowballing backfires.",
}

const HIDDEN_INFO_BY_ARCHETYPE: Dictionary = {
	"desperate_seller": [
		"the owner has a health issue and wants a fast close",
		"they received a competing offer",
		"there is deferred maintenance not reflected in the asking price",
	],
	"proud_founder": [
		"a key employee is considering leaving",
		"there is deferred maintenance not reflected in the asking price",
		"a top customer may not renew next year",
	],
	"relationship_owner": [
		"the owner has a health issue and wants a fast close",
		"a key employee is considering leaving",
	],
	"corporate_seller": [
		"there is a pending assessment from the municipality",
		"a top customer may not renew next year",
	],
}

const SELL_REASON_BY_ARCHETYPE: Dictionary = {
	"desperate_seller": [
		"Personal timeline is tight — they need liquidity and a clean close this quarter.",
		"A competing offer is on the table; they will take the path of least friction.",
	],
	"proud_founder": [
		"Built this over decades — ready to step back but only if the story continues right.",
		"No family successor — selling while the team and customer base are still strong.",
	],
	"relationship_owner": [
		"Wants a buyer they can trust with customers and staff — price is not the only variable.",
		"Community ties matter — selling to someone who will stay, not flip.",
	],
	"corporate_seller": [
		"Division no longer strategic — divestment committee wants a defensible close this fiscal year.",
		"Non-core asset sale mandated from headquarters after the last portfolio review.",
	],
}

const HIDDEN_INFO_TIPS: Dictionary = {
	"the owner has a health issue and wants a fast close": "Their health situation means speed matters more than price — offer a fast, clean close in exchange for a lower number.",
	"a top customer may not renew next year": "That customer risk is real leverage — cite the revenue risk to justify a lower price or a retention-linked earn-out.",
	"there is deferred maintenance not reflected in the asking price": "Raise the deferred maintenance calmly — it's grounds for a price reduction or a repair credit.",
	"a key employee is considering leaving": "If that employee walks, the business is worth less. Ask for employee retention or a price adjustment tied to it.",
	"there is a pending assessment from the municipality": "That assessment is a cost you'll likely inherit — get clarity on who's responsible before agreeing to a price.",
	"they received a competing offer": "They have another offer — matching specific terms they care about can matter more than a blanket discount.",
}


static func pick_hidden_info(archetype_id: String, rng: SeededRng) -> String:
	var pool: Array = HIDDEN_INFO_BY_ARCHETYPE.get(archetype_id, [
		"the owner has a health issue and wants a fast close",
		"a top customer may not renew next year",
		"there is deferred maintenance not reflected in the asking price",
	])
	return str(pool[rng.randi_range(0, pool.size() - 1)])


static func pick_sell_reason(archetype_id: String, rng: SeededRng) -> String:
	var pool: Array = SELL_REASON_BY_ARCHETYPE.get(archetype_id, [
		"Timing works now — personal or strategic reasons favor a sale this quarter.",
		"Market interest picked up and they want to test serious buyers.",
	])
	return str(pool[rng.randi_range(0, pool.size() - 1)])


static func ensure_seller_diligence(counterparty: Dictionary, asking_price: int, rng: SeededRng) -> Dictionary:
	if counterparty.is_empty():
		return {}
	var archetype_id := str(counterparty.get("archetypeId", ""))
	var arch: Dictionary = _Archetypes.get_archetype(archetype_id)
	if not counterparty.has("sellReason") or str(counterparty.get("sellReason", "")).is_empty():
		counterparty["sellReason"] = pick_sell_reason(archetype_id, rng)
	if not counterparty.has("primaryMotivator") or str(counterparty.get("primaryMotivator", "")).is_empty():
		counterparty["primaryMotivator"] = str(arch.get("primary_motivator", "greed"))
	var motivator := str(counterparty.get("primaryMotivator", "greed"))
	return {
		"motivator": motivator,
		"motivatorLabel": MOTIVATOR_LABELS.get(motivator, MOTIVATOR_LABELS.greed),
		"sellReason": str(counterparty.get("sellReason", "")),
		"reach": format_seller_negotiation_reach(counterparty, asking_price, arch),
		"hiddenNote": str(counterparty.get("hiddenInfo", "")),
	}


static func format_seller_negotiation_reach(counterparty: Dictionary, asking_price: int, archetype: Dictionary = {}) -> String:
	var ask: int = asking_price
	var red: int = int(counterparty.get("redLine", 0))
	var res: int = int(counterparty.get("reservationPrice", 0))
	if ask <= 0 or red <= 0:
		return "Floor unclear — keep negotiating with diligence-backed leverage."
	var price_floor: int = red
	var likely: int = res if res > 0 and res < ask else int(round(float(red) * 1.04))
	var discount_pct: int = maxi(0, int(round((1.0 - float(price_floor) / float(ask)) * 100.0)))
	var style := str(counterparty.get("concessionStyle", archetype.get("concession_style", "medium")))
	var patience: String = CONCESSION_PATIENCE.get(style, CONCESSION_PATIENCE.medium)
	return "With the right approach, they may concede toward %s–%s (up to ~%d%% below ask). %s" % [
		MathUtil.fmt_money(price_floor),
		MathUtil.fmt_money(likely),
		discount_pct,
		patience,
	]


static func seller_diligence_block_text(asking_price: int, counterparty: Dictionary, rng: SeededRng) -> String:
	var d: Dictionary = ensure_seller_diligence(counterparty, asking_price, rng)
	if d.is_empty():
		return ""
	var lines: PackedStringArray = [
		"SELLER DILIGENCE",
		"Moved most by: %s" % str(d.get("motivatorLabel", "")),
		"Why selling now: %s" % str(d.get("sellReason", "")),
		"If negotiated well: %s" % str(d.get("reach", "")),
	]
	var hidden: String = str(d.get("hiddenNote", "")).strip_edges()
	if not hidden.is_empty():
		lines.append("Hidden leverage: %s." % hidden[0].to_upper() + hidden.substr(1))
	return "\n".join(lines)


static func seller_diligence_log_line(opp: Dictionary, rng: SeededRng) -> String:
	var cp: Dictionary = opp.get("counterparty", {})
	var d: Dictionary = ensure_seller_diligence(cp, int(opp.get("price", 0)), rng)
	if d.is_empty():
		return ""
	return "Moved by %s · Why now: %s · Reach: %s" % [
		str(d.get("motivatorLabel", "")).split(" — ")[0].to_lower(),
		str(d.get("sellReason", "")),
		str(d.get("reach", "")),
	]


static func format_intel_panel(negotiation: Dictionary, state: RunState) -> String:
	var intel_unlocked: bool = bool(negotiation.get("intelUnlocked", false))
	if not intel_unlocked:
		return "NEGOTIATION INTEL — LOCKED\nInvestigate this opportunity (1 AP) before negotiating to reveal opening discount, hard floor, and phrases that unlock better terms."

	var cp: Dictionary = negotiation.get("counterparty", {})
	var asking: int = int(negotiation.get("context", {}).get("price", 0))
	var ctx: Dictionary = negotiation.get("context", {})
	var opp: Dictionary = ctx.get("opp", {}) if typeof(ctx.get("opp")) == TYPE_DICTIONARY else {}
	var rng := SeededRng.new(state.run_seed + asking + state.turn)
	var lines: PackedStringArray = []

	var preview_raw: Variant = opp.get("v2Preview")
	if preview_raw is Dictionary and not (preview_raw as Dictionary).is_empty():
		var preview_block := _V2Preview.format_intel_block(preview_raw as Dictionary, asking)
		if not preview_block.is_empty():
			lines.append(preview_block)
			lines.append("")

	var diligence_text := seller_diligence_block_text(asking, cp, rng)
	if not diligence_text.is_empty():
		lines.append(diligence_text)
		lines.append("")

	lines.append("NEGOTIATION TACTICS")
	var arch: Dictionary = _Archetypes.get_archetype(str(cp.get("archetypeId", "")))
	for tip_variant in arch.get("tips", []):
		lines.append("• %s" % str(tip_variant))

	var hidden: String = str(cp.get("hiddenInfo", ""))
	if HIDDEN_INFO_TIPS.has(hidden):
		lines.append("• %s" % HIDDEN_INFO_TIPS[hidden])

	for tip in NpcSpeciesSystem.intel_tips(cp):
		lines.append("• %s" % tip)

	return "\n".join(lines)


static func investigate_opportunity(state: RunState, opportunity_id: String) -> Dictionary:
	if state.action_points < 1:
		return {"ok": false, "error": "Need 1 AP to investigate"}

	var opp: Dictionary = OpportunitySystem.find_opportunity(state, opportunity_id)
	if opp.is_empty():
		return {"ok": false, "error": "Opportunity not found"}
	if bool(opp.get("diligenceDone", false)):
		return {"ok": false, "error": "Already investigated this listing"}

	state.action_points -= 1
	opp["diligenceDone"] = true

	var price: int = int(opp.get("price", 0))
	var cp: Dictionary = opp.get("counterparty", {})
	var rng := SeededRng.new(state.run_seed + state.turn * 8803 + price)
	if cp is Dictionary and not cp.is_empty():
		ensure_seller_diligence(cp, price, rng)
		opp["counterparty"] = cp

	var preview: Dictionary = _V2Preview.attach_to_opportunity(state, opp)

	if str(opp.get("assetType", "")) == "business":
		var margin: float = float(opp.get("margin", 0.2))
		margin = MathUtil.clamp(margin + rng.randf_range(-0.02, 0.02), 0.05, 0.6)
		opp["margin"] = margin
		var cost_mult: float = float(GameMode.config(state.mode).get("cost_mult", 1.0))
		opp["cost"] = int(round(float(opp.get("revenue", 0)) * (1.0 - margin) * cost_mult))
		opp["fairValue"] = ValuationSystem.estimate_listing_fair_value({
			"revenue": opp.get("revenue", 0),
			"cost": opp.get("cost", 0),
			"ownerDep": opp.get("ownerDep", 0.5),
			"custConc": opp.get("custConc", 0.12),
			"equipmentCondition": opp.get("equipmentCondition", 0.8),
		}, state.mode)

	_replace_opportunity(state, opp)

	var log_parts: PackedStringArray = []
	var diligence_line := seller_diligence_log_line(opp, rng)
	if not diligence_line.is_empty():
		log_parts.append(diligence_line)
	var preview_line := _V2Preview.log_summary(preview)
	if not preview_line.is_empty():
		log_parts.append(preview_line)
	log_parts.append("margin %s" % MathUtil.fmt_pct(float(opp.get("margin", 0.0))))
	log_parts.append("fair value ~%s vs ask %s" % [
		MathUtil.fmt_money(int(opp.get("fairValue", 0))),
		MathUtil.fmt_money(price),
	])
	state.run_log.append("Diligence on %s: %s. Negotiation Intel unlocked." % [
		str(opp.get("name", "Listing")),
		" · ".join(log_parts),
	])

	return {"ok": true, "state": state, "opportunity": opp}


static func _replace_opportunity(state: RunState, opp: Dictionary) -> void:
	var opp_id := str(opp.get("id", ""))
	for i in state.opportunities.size():
		if str((state.opportunities[i] as Dictionary).get("id", "")) == opp_id:
			state.opportunities[i] = opp
			return
