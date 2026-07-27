# Deterministic tactic classification from player text (v2 §9.1).
class_name NegotiationV2Tactics
extends RefCounted

const _Data := preload("res://core/systems/negotiation_v2_data.gd")
const _Parser := preload("res://core/systems/negotiation_offer_parser.gd")


static func classify(text: String, ai_parsed: Dictionary = {}, diligence_done: bool = false) -> Dictionary:
	var lower := text.to_lower()
	var tags: Array = []
	var intent := str(ai_parsed.get("intent", "question"))

	if _re_match("\\?|what would|why are|tell me about|help me understand|what matters|what do you need", lower):
		intent = "discovery" if intent == "question" else intent
	if _Parser.is_closing_intent_text(text):
		intent = "accept"
	if _re_match("walk|withdraw|never mind|give up", lower):
		intent = "walk"

	_add_if(tags, "employee_care", _re_match("employee retention|keep (?:all )?(?:the |your )?(?:staff|employees|team|workers)|retain (?:all )?(?:the |your )?(?:staff|employees)|keep everyone|keep the team", lower))
	_add_if(tags, "legacy", _re_match("\\blegacy\\b|built this|what you created|what you built", lower))
	_add_if(tags, "continuity", _re_match("continuity|keep the team|transition plan|smooth handoff", lower))
	_add_if(tags, "warm_rapport", _re_match("respect|appreciate|understand|comfortable|care about|thank you for|means a lot", lower))
	_add_if(tags, "small_talk", _re_match("how long|history|story|family|community|your people", lower))
	_add_if(tags, "cash_upfront", _re_match("all cash|all upfront|cash at closing|full cash|100% cash|pay cash|one wire|nothing deferred|100% hits your account|same day|no seller note|no earn.?out", lower))
	_add_if(tags, "fast_closing", _re_match("fast close|quick close|close quickly|30 day|thirty day|close fast|48 hour|48-hour|finalize this week|immediate close|finalize immediately|close within", lower))
	_add_if(tags, "warranty", _re_match("warrant|guarantee|stand behind", lower))
	_add_if(tags, "inspection", _re_match("inspect|due diligence|verification|audit|inspection window|inspection clears", lower))
	_add_if(tags, "guarantee", _re_match("guarantee|escrow|collateral|secured|written guarantee", lower))
	_add_if(tags, "evidence", _re_match("contract|document|record|proof|verified|show you|here are the numbers|reviewed the|looked at the|underwriting|books match|records reviewed|conservative numbers|documented", lower))
	_add_if(tags, "realistic_numbers", _re_match("realistic|conservative|based on actual|last four quarter|historical|conservative read", lower))
	_add_if(tags, "reputation", _re_match("reputation|track record|paid on time|fair dealing|close deals|how you close", lower))
	_add_if(tags, "testimonial", _re_match("reference|testimonial|recommend|spoke with|they trust|referral|introduce you", lower))
	_add_if(tags, "comparable_deal", _re_match("comparable|similar deal|last acquisition|other farm", lower))
	_add_if(tags, "social_proof", _re_match("others are|market is|everyone|community|valley|recognize you|already know you|biggest retail|mega retail", lower))
	_add_if(tags, "respected_partner", _re_match("face of|part of the brand|part of the chain|brand ambassador|respected partner|stay with the brand|be the face", lower))
	_add_if(tags, "volume_commitment", _re_match("expand|territory|territories|neighborhood|new locations|volume|footprint|growth plan", lower))
	_add_if(tags, "firm_boundary", _re_match("final offer|best i can|won't go|cannot exceed|walk away if", lower))
	_add_if(tags, "reciprocal_concession", _re_match("in exchange|if you|trade|reciprocal|meet me halfway", lower))
	_add_if(tags, "patience", _re_match("take your time|no rush|when you're ready|patient", lower))
	_add_if(tags, "option_package", _re_match("earn.?out|exclusiv|option|upside|royalt|territor|volume", lower))
	_add_if(tags, "pressure", _re_match("take it or leave|now or never|decide today|last chance|hurry", lower))
	_add_if(tags, "aggression", _re_match("ridiculous|absurd|greedy|foolish|stupid|insult", lower))
	_add_if(tags, "complex_structure", _re_match("complicated structure|layered|multi.?tranche|contingent stack", lower))
	_add_if(tags, "vague_term", _re_match("maybe|perhaps|roughly|around|something like|we'll figure", lower))
	_add_if(tags, "unsupported_claim", _re_match("trust me|believe me|obviously|everyone knows|guaranteed success", lower))

	if diligence_done and _re_match("investigat|diligence|looked into|reviewed", lower):
		_add_unique(tags, "verified_history")

	# Merge AI-suggested tactic tags when present.
	if typeof(ai_parsed.get("tacticTags")) == TYPE_ARRAY:
		for t in ai_parsed["tacticTags"]:
			_add_unique(tags, str(t).to_lower())

	return {"intent": intent, "tags": tags}


static func species_progress_delta(species_id: String, tags: Array, history: Array) -> float:
	var positives: Array = _Data.SPECIES_POSITIVE_TAGS.get(species_id, [])
	var negatives: Array = _Data.SPECIES_NEGATIVE_TAGS.get(species_id, [])
	var delta := 0.0
	var positive_hits: Array = []
	for tag in tags:
		var t := str(tag)
		if t in negatives:
			return _apply_repetition(-15.0, tags, history)
		if t in positives:
			positive_hits.append(t)
		elif t in ["warm_rapport", "small_talk", "patience"]:
			positive_hits.append(t)

	if positive_hits.is_empty():
		return 0.0

	delta = _Data.PROGRESS_PRIMARY_DELTA
	if positive_hits.size() >= 2:
		delta += _Data.PROGRESS_SECONDARY_DELTA
	delta = minf(delta, _Data.PROGRESS_TURN_CAP)
	return _apply_repetition(delta, tags, history)


static func situation_progress_delta(situation_id: String, tags: Array, history: Array) -> float:
	if situation_id == "stable_position":
		return 0.0
	var positives: Array = _Data.SITUATION_POSITIVE_TAGS.get(situation_id, [])
	var matched: Array = []
	for tag in tags:
		var t := str(tag)
		if t in positives:
			matched.append(t)
		elif t in ["cash_upfront", "fast_closing"] and situation_id == "cash_pressure":
			matched.append(t)
		elif t in ["employee_care", "legacy", "continuity"] and situation_id == "retirement_transition":
			matched.append(t)

	if matched.is_empty():
		return 0.0

	var delta := _Data.PROGRESS_PRIMARY_DELTA
	if matched.size() >= 2:
		delta += _Data.PROGRESS_SECONDARY_DELTA
	delta = minf(delta, _Data.PROGRESS_TURN_CAP)
	return _apply_repetition(delta, tags, history)


static func conversation_gauge_delta(tags: Array) -> int:
	var delta := 0
	for tag in tags:
		match str(tag):
			"employee_care", "legacy", "continuity", "warm_rapport", "evidence", "cash_upfront":
				delta += 5
			"reputation", "testimonial", "social_proof", "respected_partner", "option_package", "volume_commitment", "comparable_deal":
				delta += 5
			"pressure", "aggression", "unsupported_claim":
				delta -= 10
			"lowball":
				delta -= 8
			_:
				pass
	if tags.is_empty():
		return 0
	return clampi(delta, -15, 15)


static func _apply_repetition(raw_delta: float, tags: Array, history: Array) -> float:
	if raw_delta == 0.0 or tags.is_empty():
		return 0.0
	var key := str(tags[0])
	var consecutive := 0
	for i in range(history.size() - 1, -1, -1):
		if str(history[i]) == key:
			consecutive += 1
		else:
			break
	if consecutive >= 2:
		return 0.0
	if consecutive == 1:
		return raw_delta * 0.5
	return raw_delta


static func _re_match(pattern: String, text: String) -> bool:
	return RegEx.create_from_string(pattern).search(text) != null


static func _add_if(tags: Array, tag: String, matched: bool) -> void:
	if matched:
		_add_unique(tags, tag)


static func _add_unique(tags: Array, tag: String) -> void:
	if tag.is_empty():
		return
	for existing in tags:
		if str(existing) == tag:
			return
	tags.append(tag)
