# Build copyable negotiation transcripts + debug logs for QA.
class_name NegotiationTranscript
extends RefCounted

const _V2 := preload("res://core/systems/negotiation_v2_engine.gd")


static func build_transcript(negotiation: Dictionary) -> String:
	if negotiation.is_empty():
		return ""
	var parts: PackedStringArray = []
	parts.append("=== NEGOTIATION TRANSCRIPT ===")
	parts.append(_header_block(negotiation))
	parts.append("")
	parts.append("--- Messages ---")
	parts.append(build_messages(negotiation))
	parts.append("")
	parts.append(build_data_panel(negotiation))
	return "\n".join(parts)


static func build_messages(negotiation: Dictionary) -> String:
	if negotiation.is_empty():
		return ""
	var lines: PackedStringArray = []
	for msg_variant in negotiation.get("messages", []):
		if typeof(msg_variant) != TYPE_DICTIONARY:
			continue
		var msg: Dictionary = msg_variant
		var speaker := str(msg.get("speaker", msg.get("role", "?")))
		var text := str(msg.get("text", "")).strip_edges()
		if text.is_empty():
			continue
		lines.append("%s:\n%s" % [speaker, text])
		lines.append("")
	return "\n".join(lines).strip_edges()


static func build_data_panel(negotiation: Dictionary) -> String:
	if negotiation.is_empty():
		return ""
	var parts: PackedStringArray = []
	parts.append(_engine_block(negotiation))
	var offer_text := _offer_block(negotiation)
	if not offer_text.is_empty():
		parts.append("")
		parts.append(offer_text)
	var debug: Array = negotiation.get("debugLog", [])
	if not debug.is_empty():
		parts.append("")
		parts.append("--- Turn log ---")
		for entry_variant in debug:
			if typeof(entry_variant) != TYPE_DICTIONARY:
				continue
			parts.append(_format_debug_entry(entry_variant as Dictionary))
	return "\n".join(parts)


static func append_turn_debug(
	negotiation: Dictionary,
	round_num: int,
	player_text: String,
	offer: Dictionary,
	v2_result: Dictionary,
	decision: String,
) -> void:
	var log: Array = negotiation.get("debugLog", [])
	var entry := {
		"round": round_num,
		"playerText": player_text,
		"decision": decision,
		"tags": v2_result.get("tags", []),
		"intent": v2_result.get("intent", ""),
		"gauge": v2_result.get("gauge", negotiation.get("v2", {}).get("gauge", 0)),
		"gaugeDelta": v2_result.get("gaugeDelta", 0),
		"economicGateMet": v2_result.get("economicGateMet", false),
		"willingnessGateMet": v2_result.get("willingnessGateMet", false),
		"offerValue": v2_result.get("offerValue", 0),
		"acceptableValue": v2_result.get("acceptableValue", 0),
		"statusHint": v2_result.get("statusHint", ""),
		"readyToClose": v2_result.get("readyToClose", false),
	}
	if not offer.is_empty():
		entry["offer"] = {
			"totalPrice": offer.get("totalPrice", 0),
			"cashAtClosing": offer.get("cashAtClosing", 0),
			"termsOffered": offer.get("termsOffered", []),
		}
	var profile: Dictionary = v2_result.get("profile", negotiation.get("v2", {}))
	if not profile.is_empty():
		entry["speciesProgress"] = profile.get("speciesProgress", 0)
		entry["situationProgress"] = profile.get("situationProgress", 0)
		entry["unlockedDiscount"] = profile.get("unlockedDiscount", 0)
	log.append(entry)
	if log.size() > 40:
		log = log.slice(log.size() - 40)
	negotiation["debugLog"] = log


static func save_to_user_file(negotiation: Dictionary) -> String:
	var text := build_transcript(negotiation)
	var path := "user://negotiation_debug.log"
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return ""
	file.store_string(text)
	file.store_string("\n\n--- saved %s ---\n" % Time.get_datetime_string_from_system())
	file.close()
	return ProjectSettings.globalize_path(path)


static func _header_block(negotiation: Dictionary) -> String:
	var ctx: Dictionary = negotiation.get("context", {})
	var cp: Dictionary = negotiation.get("counterparty", {})
	var v2: Dictionary = negotiation.get("v2", {})
	var parts: PackedStringArray = []
	parts.append("Listing: %s" % str(ctx.get("name", "?")))
	parts.append("Ask: %s" % MathUtil.fmt_money(int(ctx.get("price", 0))))
	parts.append("Round: %d/%d" % [int(negotiation.get("round", 0)), int(negotiation.get("maxRounds", 6))])
	parts.append("Species: %s" % str(cp.get("speciesId", "—")))
	if not v2.is_empty():
		parts.append("Situation: %s" % str(v2.get("situationLabel", "")))
		parts.append("Leverage: %s" % str(v2.get("leverageLabel", "")))
		parts.append("Economic hint: %s" % str(negotiation.get("economicStatusHint", "")))
		parts.append("Ready to close: %s" % str(negotiation.get("readyToClose", false)))
	return "\n".join(parts)


static func _engine_block(negotiation: Dictionary) -> String:
	var v2: Dictionary = negotiation.get("v2", {})
	if v2.is_empty():
		return "--- Engine: legacy utility ---"
	var display: Dictionary = _V2.gauge_display(v2)
	var lines: PackedStringArray = []
	lines.append("--- Deal Momentum (v2) ---")
	lines.append("Gauge: %d (%s %s)" % [int(display.get("gauge", 0)), str(display.get("zoneLabel", "")), str(display.get("arrow", ""))])
	lines.append("Zone hint: %s" % str(display.get("zoneHint", "")))
	lines.append("Species progress: %.0f%% · Situation progress: %.0f%%" % [
		float(v2.get("speciesProgress", 0.0)),
		float(v2.get("situationProgress", 0.0)),
	])
	lines.append("Unlocked discount: %.1f%% · Acceptable value: %s" % [
		float(v2.get("unlockedDiscount", 0.0)) * 100.0,
		MathUtil.fmt_money(int(v2.get("acceptableValue", 0))),
	])
	lines.append("Hard floor (hidden in UI): %s" % MathUtil.fmt_money(int(v2.get("hardFloor", 0))))
	var last_v2: Dictionary = negotiation.get("lastV2", {})
	if not last_v2.is_empty():
		lines.append("Last turn: econ gate %s · willingness gate %s · offer value %s" % [
			"✓" if bool(last_v2.get("economicGateMet", false)) else "✗",
			"✓" if bool(last_v2.get("willingnessGateMet", false)) else "✗",
			MathUtil.fmt_money(int(last_v2.get("offerValue", 0))),
		])
	return "\n".join(lines)


static func _offer_block(negotiation: Dictionary) -> String:
	var offer: Variant = negotiation.get("playerLastOffer")
	if offer == null or not (offer is Dictionary):
		return ""
	var o: Dictionary = offer as Dictionary
	if int(o.get("totalPrice", 0)) <= 0:
		return ""
	return "--- Current offer ---\n%s" % NegotiationSystem.summarize_offer(o)


static func _format_debug_entry(entry: Dictionary) -> String:
	var terms: Array = []
	if entry.has("offer") and typeof(entry.get("offer")) == TYPE_DICTIONARY:
		terms = (entry["offer"] as Dictionary).get("termsOffered", [])
	return "R%d | %s | gauge %d (%+d) | offerVal %s / accept %s | gates econ:%s will:%s | tags:%s | %s" % [
		int(entry.get("round", 0)),
		str(entry.get("decision", "")),
		int(entry.get("gauge", 0)),
		int(entry.get("gaugeDelta", 0)),
		MathUtil.fmt_money(int(entry.get("offerValue", 0))),
		MathUtil.fmt_money(int(entry.get("acceptableValue", 0))),
		"Y" if bool(entry.get("economicGateMet", false)) else "N",
		"Y" if bool(entry.get("willingnessGateMet", false)) else "N",
		", ".join(terms) if terms.is_empty() else str(terms),
		str(entry.get("playerText", "")).substr(0, 80),
	]
