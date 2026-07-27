# Player-facing negotiation progress labels (v2).
class_name NegotiationV2Display
extends RefCounted

const _Data := preload("res://core/systems/negotiation_v2_data.gd")
const _NpcSpecies := preload("res://core/systems/npc_species_system.gd")


static func format_progress_panel(
	v2: Dictionary,
	counterparty: Dictionary,
	ready_to_close: bool,
	v2_preview: Dictionary = {},
) -> Dictionary:
	if v2.is_empty():
		return {"visible": false}

	var species_id := str(v2.get("speciesId", counterparty.get("speciesId", "")))
	var species_progress: float = float(v2.get("speciesProgress", 0.0))
	var situation_progress: float = float(v2.get("situationProgress", 0.0))
	var discount_pct: float = float(v2.get("unlockedDiscount", 0.0)) * 100.0
	var ask: int = int(v2.get("askPrice", 0))
	var acceptable: int = int(v2.get("acceptableValue", ask))
	var stable: bool = bool(v2.get("stablePosition", false))

	var rapport := "%s rapport: %s" % [species_id.capitalize(), _rapport_label(species_progress)]
	var discount_line := "Discount unlocked: %.1f%%" % discount_pct
	if ask > 0 and acceptable < ask:
		discount_line += " · Work toward ~%s" % MathUtil.fmt_money(acceptable)

	var situation_line := ""
	if not stable:
		situation_line = "Situation alignment: %s" % _rapport_label(situation_progress)

	var coach := _NpcSpecies.negotiation_coach_tip(counterparty, v2)
	if not ready_to_close and not v2_preview.is_empty():
		var keywords: Array = v2_preview.get("keywords", [])
		if keywords.size() >= 3:
			coach = "From diligence — try: \"%s\", \"%s\", \"%s\"" % [
				str(keywords[0]),
				str(keywords[1]),
				str(keywords[2]),
			]
		elif keywords.size() > 0:
			var parts: PackedStringArray = []
			for kw in keywords:
				parts.append("\"%s\"" % str(kw))
			coach = "From diligence — try: %s" % ", ".join(parts)
	if ready_to_close:
		coach = "Both gates passed — press Close Deal to finalize at your offered price."

	return {
		"visible": true,
		"rapportLine": rapport,
		"discountLine": discount_line,
		"situationLine": situation_line,
		"coachLine": coach,
	}


static func _rapport_label(progress: float) -> String:
	if progress >= 75.0:
		return "Strong"
	if progress >= 45.0:
		return "Building"
	if progress >= 15.0:
		return "Opening"
	return "Not yet engaged"
