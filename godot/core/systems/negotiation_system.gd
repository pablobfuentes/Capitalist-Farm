# Negotiation utility engine + session flow (port of MVP evaluateOfferUtility / negotiationDecision).
class_name NegotiationSystem
extends RefCounted

const _Parser := preload("res://core/systems/negotiation_offer_parser.gd")
const _NpcSpecies := preload("res://core/systems/npc_species_system.gd")
const _Archetypes := preload("res://core/content/negotiation_archetypes.gd")
const _Rival := preload("res://core/systems/rival_system.gd")
const _Diligence := preload("res://core/systems/diligence_system.gd")
const _AiPrompt := preload("res://core/systems/ai_negotiation_prompt.gd")
const _V2 := preload("res://core/systems/negotiation_v2_engine.gd")
const _V2Data := preload("res://core/systems/negotiation_v2_data.gd")
const _Transcript := preload("res://core/systems/negotiation_transcript.gd")
const _Urgent := preload("res://core/systems/urgent_system.gd")
const _LevelUp := preload("res://core/systems/level_up_system.gd")
const _UpgradeSystem := preload("res://core/systems/upgrade_system.gd")

const MAX_ROUNDS := 6
const ACCEPT_THRESHOLD := 18.0
const REJECT_THRESHOLD := -40.0
const LATE_ACCEPT_THRESHOLD := 16.0


static func start_negotiation(state: RunState, opportunity_id: String) -> Dictionary:
	if not state.negotiation.is_empty() and bool(state.negotiation.get("active", false)):
		return {"ok": false, "error": "Negotiation already in progress"}

	var opp: Dictionary = OpportunitySystem.find_opportunity(state, opportunity_id)
	if opp.is_empty():
		return {"ok": false, "error": "Opportunity not found"}

	if bool(opp.get("rivalContest", false)):
		return start_rival_contest(state, opportunity_id)

	var ap: Dictionary = ActionPointsSystem.require(state, 1)
	if not bool(ap.get("ok", false)):
		return ap
	ActionPointsSystem.spend(state, 1)

	var price: int = int(opp.get("price", 0))
	var asset_type: String = str(opp.get("assetType", "business"))
	var neg_kind: String = "levelup" if asset_type == "levelup" else ("realestate" if asset_type == "realestate" else "acquisition")
	var counterparty: Dictionary = opp.get("counterparty", {})
	if counterparty.is_empty():
		var rng := SeededRng.new(state.run_seed + state.turn * 7919 + price)
		var arch: Dictionary = _Archetypes.pick_archetype(rng)
		counterparty = _Archetypes.build_counterparty(str(arch.get("id", "desperate_seller")), price, rng)

	var diligence_done: bool = bool(opp.get("diligenceDone", false)) or (neg_kind == "levelup" and state.has_strategic_edge("negotiation_analyst"))
	var stakes: Dictionary = negotiation_stakes(price)
	var arch: Dictionary = _Archetypes.get_archetype(str(counterparty.get("archetypeId", "")))
	var open_rng := SeededRng.new(state.run_seed + price * 13 + state.turn)
	if not counterparty.has("businessSituation"):
		counterparty["businessSituation"] = _V2Data.pick_situation(opp, SeededRng.new(state.run_seed + price))
	if not counterparty.has("leverageScore"):
		counterparty["leverageScore"] = 0.5
	if not counterparty.has("relationshipMemory"):
		counterparty["relationshipMemory"] = {"trust": counterparty.get("trust", 0.5), "promisesKept": 0, "promisesBroken": 0, "grievances": []}
	CommunityNegotiationBridge.enrich_counterparty(state, counterparty, opp)

	var situation: Dictionary = _V2Data.SITUATIONS.get(str(counterparty.get("businessSituation", "")), {})
	var v2_profile: Dictionary
	var preview_raw: Variant = opp.get("v2Preview")
	if preview_raw is Dictionary and (preview_raw as Dictionary).has("profile"):
		v2_profile = ((preview_raw as Dictionary)["profile"] as Dictionary).duplicate(true)
		var leverage_score: float = float(counterparty.get("leverageScore", 0.5))
		var leverage_band: Dictionary = _V2Data.leverage_from_score(leverage_score)
		v2_profile["leverageGaugeAdj"] = int(leverage_band.get("gaugeAdj", 0))
		v2_profile["leverageEconomicAdj"] = float(leverage_band.get("econAdj", 0.0))
		v2_profile["leverageLabel"] = str(leverage_band.get("label", "Balanced"))
		v2_profile["communityIntelLeverageScore"] = leverage_score
		v2_profile = CommunityNegotiationBridge.apply_profile_fields(state, counterparty, v2_profile)
		var personal_adj := int(v2_profile.get("personalRelationshipGaugeAdj", 0))
		var gauge_start := clampi(
			_V2Data.GAUGE_BASE
			+ int(v2_profile.get("reputationGaugeAdj", 0))
			+ int(v2_profile.get("memoryGaugeAdj", 0))
			+ int(v2_profile.get("leverageGaugeAdj", 0))
			+ personal_adj,
			0,
			100,
		)
		v2_profile["gaugeStart"] = gauge_start
		v2_profile["gauge"] = gauge_start
		v2_profile["previousGauge"] = gauge_start
	else:
		v2_profile = _V2.initialize_profile(
			price,
			counterparty,
			state,
			opp,
			_V2.profile_seed(state, price, opportunity_id),
		)

	state.negotiation = {
		"active": true,
		"kind": neg_kind,
		"opportunityId": opportunity_id,
		"round": 0,
		"maxRounds": int(stakes.get("maxRounds", MAX_ROUNDS)),
		"intelUnlocked": diligence_done,
		"stakesTier": str(stakes.get("tier", "standard")),
		"stakesLabel": str(stakes.get("label", "")),
		"v2": v2_profile,
		"context": {
			"price": price,
			"name": str(opp.get("name", "Listing")),
			"opp": opp,
			"diligenceDone": diligence_done,
		},
		"counterparty": counterparty,
		"playerLastOffer": null,
		"playerLastOfferText": "",
		"readyToClose": false,
		"pendingOffer": null,
		"lastOffer": null,
		"status": "ongoing",
		"messages": [],
		"debugLog": [],
		"lastDecision": "",
		"lastUtility": 0.0,
		"economicStatusHint": "No offer",
		"aiStatus": "checking",
		"aiModel": "",
		"aiOfflineNoted": false,
	}

	var arch_name: String = str(arch.get("name", "Seller"))
	var opening := _v2_opening_line(counterparty, situation, v2_profile, open_rng)
	if opening.is_empty():
		opening = _NpcSpecies.seller_opening_line(
			counterparty,
			state.negotiation.get("context", {}),
			arch,
			open_rng,
			str(stakes.get("tier", "standard")),
		)
	_append_message(state, "seller", opening, arch_name)
	state.run_log.append("Started negotiation for %s" % str(opp.get("name", "")))

	return {"ok": true, "state": state, "negotiation": state.negotiation}


static func start_rival_contest(state: RunState, opportunity_id: String) -> Dictionary:
	if not state.negotiation.is_empty() and bool(state.negotiation.get("active", false)):
		return {"ok": false, "error": "Negotiation already in progress"}

	var opp: Dictionary = OpportunitySystem.find_opportunity(state, opportunity_id)
	if opp.is_empty() or not bool(opp.get("rivalContest", false)):
		return {"ok": false, "error": "Not a contested listing"}

	if state.action_points < 1:
		return {"ok": false, "error": "Need 1 AP to enter a three-way contest"}

	ActionPointsSystem.spend(state, 1)

	var price: int = int(opp.get("price", 0))
	var counterparty: Dictionary = opp.get("counterparty", {})
	var rival: Dictionary = _Rival.create_rival(state)
	var rules: Dictionary = _Rival.build_contest_rules(state, opp, counterparty)
	var rng := SeededRng.new(state.run_seed + state.turn * 5507 + price)
	var raw_rival_offer: Dictionary = _Rival.opening_offer(opp, rules, rng)
	var rival_offer: Dictionary = _Parser.normalize_offer(raw_rival_offer)
	var diligence_done: bool = bool(opp.get("diligenceDone", false))

	state.negotiation = {
		"active": true,
		"kind": "rival_contest",
		"opportunityId": opportunity_id,
		"round": 0,
		"maxRounds": 8,
		"intelUnlocked": diligence_done,
		"context": {
			"price": price,
			"name": str(opp.get("name", "Listing")),
			"opp": opp,
			"diligenceDone": diligence_done,
		},
		"counterparty": counterparty,
		"contestRules": rules,
		"rival": rival,
		"rivalLastOffer": rival_offer,
		"rivalConceded": false,
		"playerLastOffer": null,
		"leadingBidder": "rival",
		"lastDecision": "",
		"lastUtility": 0.0,
		"messages": [],
		"aiStatus": "checking",
		"aiModel": "",
		"aiOfflineNoted": false,
	}

	var arch_name: String = _Archetypes.get_archetype(str(counterparty.get("archetypeId", ""))).get("name", "Seller")
	_append_message(state, "rival", _Rival.rival_opening_line(opp, rival_offer), _Rival.display_name(rival))
	_append_message(state, "seller", _Rival.seller_response_to_rival(opp, rival_offer, counterparty), arch_name)
	_append_message(state, "system", "Three-way contest — your turn. Outbid Rowe before the turn ends.", "System")
	state.run_log.append("Entered rival contest for %s" % str(opp.get("name", "")))

	return {"ok": true, "state": state, "negotiation": state.negotiation, "rival_contest": true}


static func append_player_message(state: RunState, message: String) -> Dictionary:
	if state.negotiation.is_empty() or not bool(state.negotiation.get("active", false)):
		return {"ok": false, "error": "No active negotiation"}
	var text := message.strip_edges()
	if text.is_empty():
		return {"ok": false, "error": "Empty message"}
	_append_message(state, "player", text, "You")
	return {"ok": true, "state": state}


static func send_message(state: RunState, message: String, ai_parsed: Dictionary = {}, skip_player_append: bool = false) -> Dictionary:
	if state.negotiation.is_empty() or not bool(state.negotiation.get("active", false)):
		return {"ok": false, "error": "No active negotiation"}

	var text := message.strip_edges()
	if text.is_empty():
		return {"ok": false, "error": "Empty message"}

	if str(state.negotiation.get("kind", "")) == "rival_contest":
		return _send_contest_message(state, text, ai_parsed, skip_player_append)

	if str(state.negotiation.get("kind", "")) == "relationship":
		return _send_relationship_message(state, text, ai_parsed, skip_player_append)

	if not skip_player_append:
		_append_message(state, "player", text, "You")
	state.negotiation["round"] = int(state.negotiation.get("round", 0)) + 1

	var parsed_input: Dictionary = ai_parsed if not ai_parsed.is_empty() else {"intent": "question"}
	var built: Dictionary = _Parser.build_player_offer_from_message(
		text,
		parsed_input,
		state.negotiation,
	)
	var intent: String = str(built.get("intent", "question"))
	var offer: Variant = built.get("offer")

	if intent == "walk":
		return end_negotiation(state, true)

	var offer_dict: Dictionary = {}
	if offer is Dictionary and int((offer as Dictionary).get("totalPrice", 0)) > 0:
		offer_dict = _Parser.enrich_offer_from_message(offer as Dictionary, text, parsed_input)
		state.negotiation["playerLastOffer"] = offer_dict.duplicate(true)
		state.negotiation["playerLastOfferText"] = text

	var utility: float = 0.0
	var decision: String = "ongoing"
	var max_rounds: int = int(state.negotiation.get("maxRounds", MAX_ROUNDS))
	var round_num: int = int(state.negotiation.get("round", 0))
	var v2_result: Dictionary = {}

	if state.negotiation.has("v2"):
		var profile: Dictionary = state.negotiation.get("v2", {})
		v2_result = _V2.process_turn(
			profile,
			text,
			offer_dict,
			parsed_input,
			bool(state.negotiation.get("context", {}).get("diligenceDone", false)),
			round_num,
			max_rounds,
		)
		state.negotiation["v2"] = v2_result.get("profile", profile)
		state.negotiation["economicStatusHint"] = str(v2_result.get("statusHint", ""))
		decision = _map_v2_decision(str(v2_result.get("decision", "continue")))
		utility = float(v2_result.get("gauge", 0))
	elif intent == "accept":
		if offer_dict.is_empty():
			var last: Variant = state.negotiation.get("playerLastOffer")
			if last is Dictionary and int((last as Dictionary).get("totalPrice", 0)) > 0:
				offer_dict = last as Dictionary
		if not offer_dict.is_empty():
			utility = evaluate_offer_utility(offer_dict, state.negotiation.get("counterparty", {}), state.negotiation.get("context", {}), state)
			decision = negotiation_decision(utility, round_num, max_rounds)
		else:
			decision = "ongoing"
	elif intent == "offer" and not offer_dict.is_empty():
		utility = evaluate_offer_utility(offer_dict, state.negotiation.get("counterparty", {}), state.negotiation.get("context", {}), state)
		decision = negotiation_decision(utility, round_num, max_rounds)

	if state.negotiation.has("v2"):
		if bool(v2_result.get("readyToClose", false)):
			decision = "accept"
	else:
		decision = _apply_accept_overrides(decision, intent, utility, text, offer_dict, state, round_num, max_rounds)
	state.negotiation["lastUtility"] = utility
	state.negotiation["lastDecision"] = decision
	if not v2_result.is_empty():
		state.negotiation["lastV2"] = v2_result
		_Transcript.append_turn_debug(
			state.negotiation,
			round_num,
			text,
			offer_dict,
			v2_result,
			decision,
		)
		_Transcript.save_to_user_file(state.negotiation)

	var dialogue_decision := "question" if decision == "ongoing" else decision
	var seller_reply := _resolve_seller_dialogue(ai_parsed, dialogue_decision, state, text, offer_dict, v2_result)
	var offer_summary := summarize_offer(offer_dict) if not offer_dict.is_empty() else ""

	match decision:
		"accept":
			state.negotiation["readyToClose"] = bool(v2_result.get("readyToClose", true)) if not v2_result.is_empty() else true
			state.negotiation["pendingOffer"] = offer_dict.duplicate(true)
			state.negotiation["lastOffer"] = offer_dict.duplicate(true)
			var close_line := seller_reply if not seller_reply.is_empty() else _fallback_dialogue("accept", state)
			if close_line.find("close") == -1:
				close_line = "%s I'd be glad to close on that whenever you're ready." % close_line
			_append_message(state, "seller", close_line, _seller_name(state))
			if not offer_summary.is_empty():
				_append_system_message(state, "Your offer on the table: %s" % offer_summary)
			return {
				"ok": true,
				"state": state,
				"decision": "accept",
				"reply": close_line,
				"dialogue": close_line,
				"utility": utility,
				"ready_to_close": true,
			}
		"reject":
			state.negotiation["readyToClose"] = false
			state.negotiation["pendingOffer"] = null
			state.negotiation["status"] = "rejected"
			var redline_hit := _redline_hit(offer_dict, state)
			var reject_reply := seller_reply
			if redline_hit:
				reject_reply = "%s That's below what I can accept — no deal." % seller_reply
			else:
				reject_reply = "%s I don't think we can make this work." % seller_reply
			_append_message(state, "seller", reject_reply, _seller_name(state))
			state.negotiation = {}
			return {"ok": true, "state": state, "decision": "reject", "reply": reject_reply, "utility": utility, "closed": true}
		"counter":
			state.negotiation["readyToClose"] = false
			state.negotiation["pendingOffer"] = null
			var counter := build_counter_offer(state, offer_dict)
			state.negotiation["lastOffer"] = counter
			if state.negotiation.has("v2") and seller_reply.is_empty():
				seller_reply = _v2_counter_dialogue(state, v2_result, counter)
			_append_message(state, "seller", seller_reply, _seller_name(state))
			if state.negotiation.has("v2"):
				_append_v2_status_message(state, v2_result)
			if not offer_summary.is_empty():
				_append_system_message(state, "Your offer on the table: %s" % offer_summary)
			_maybe_append_final_round_hint(state, offer_dict, utility, round_num, max_rounds)
			return {"ok": true, "state": state, "decision": "counter", "reply": seller_reply, "utility": utility}
		_:
			_append_message(state, "seller", seller_reply, _seller_name(state))
			if state.negotiation.has("v2") and not v2_result.is_empty():
				_append_v2_status_message(state, v2_result)
			if not offer_summary.is_empty():
				_append_system_message(state, "Your offer on the table: %s" % offer_summary)
			_maybe_append_final_round_hint(state, offer_dict, utility, round_num, max_rounds)
			return {"ok": true, "state": state, "decision": "question", "reply": seller_reply, "utility": utility}


static func close_deal(state: RunState) -> Dictionary:
	if state.negotiation.is_empty() or not bool(state.negotiation.get("active", false)):
		return {"ok": false, "error": "No active negotiation"}
	if not bool(state.negotiation.get("readyToClose", false)):
		return {"ok": false, "error": "Seller has not agreed yet — keep negotiating"}

	var neg_kind: String = str(state.negotiation.get("kind", "acquisition"))
	if neg_kind == "relationship":
		var problem: Dictionary = (state.negotiation.get("context", {}) as Dictionary).get("problem", {})
		if typeof(problem) != TYPE_DICTIONARY:
			problem = {}
		var pending_rel: Variant = state.negotiation.get("pendingOffer")
		var rel_offer: Dictionary = pending_rel as Dictionary if pending_rel is Dictionary else {}
		_Urgent.resolve_relationship_deal(state, problem, rel_offer)
		state.negotiation = {}
		return {"ok": true, "state": state, "decision": "accept", "closed": true}

	var pending: Variant = state.negotiation.get("pendingOffer")
	if pending == null or not (pending is Dictionary) or int((pending as Dictionary).get("totalPrice", 0)) <= 0:
		return {"ok": false, "error": "No agreed offer to close"}

	var offer_dict: Dictionary = pending as Dictionary
	var last_text := str(state.negotiation.get("playerLastOfferText", ""))
	if not last_text.is_empty():
		var rebuilt: Dictionary = _Parser.build_player_offer_from_message(
			last_text,
			{"intent": "offer"},
			state.negotiation,
		)
		var rebuilt_offer: Variant = rebuilt.get("offer")
		if rebuilt_offer is Dictionary and int((rebuilt_offer as Dictionary).get("totalPrice", 0)) > 0:
			offer_dict = rebuilt_offer as Dictionary

	var cash_at_closing: int = mini(
		state.cash,
		int(offer_dict.get("cashAtClosing", int(offer_dict.get("totalPrice", 0)))),
	)
	if state.cash < cash_at_closing:
		var cash_reply := "You'll need %s in cash to close." % MathUtil.fmt_money(cash_at_closing)
		_append_message(state, "seller", cash_reply, _seller_name(state))
		return {"ok": true, "state": state, "decision": "counter", "reply": cash_reply}

	_append_message(state, "player", "Let's close on those terms.", "You")
	var opp_id: String = str(state.negotiation.get("opportunityId", ""))
	var opp: Dictionary = OpportunitySystem.find_opportunity(state, opp_id)
	var asset_type: String = str(opp.get("assetType", "business"))
	if neg_kind == "levelup":
		var cash_at: int = mini(state.cash, int(offer_dict.get("cashAtClosing", int(opp.get("price", 0)))))
		if state.cash < cash_at:
			return {"ok": false, "error": "Insufficient cash to close level-up"}
		state.cash -= cash_at
		var biz := _UpgradeSystem.find_business(state, str(opp.get("businessId", "")))
		if biz == null:
			return {"ok": false, "error": "Business not found for level-up"}
		var tmpl: Dictionary = opp.get("levelUpTemplate", {})
		_LevelUp.apply_level_up_effects(biz, tmpl, state)
		_remove_levelup_opportunity(state, opp_id)
		state.run_log.append("Level-up closed — %s now Level %d." % [biz.name, biz.level])
		state.negotiation = {}
		return {"ok": true, "state": state, "decision": "accept", "closed": true, "business": biz}
	var acquire: Dictionary
	if asset_type == "realestate":
		acquire = AcquisitionSystem.close_real_estate_acquisition(state, opp_id, offer_dict)
	else:
		acquire = AcquisitionSystem.close_business_acquisition(state, opp_id, offer_dict)
	if not bool(acquire.get("ok", false)):
		return acquire
	if acquire.get("business") is BusinessInstance:
		state.run_log.append("Deal closed — %s" % (acquire.get("business") as BusinessInstance).name)
	elif acquire.get("realEstate") is Dictionary:
		var re: Dictionary = acquire.get("realEstate")
		state.run_log.append("Deal closed — %s" % str(re.get("name", "Property")))
	state.negotiation = {}
	return {
		"ok": true,
		"state": state,
		"decision": "accept",
		"closed": true,
		"business": acquire.get("business"),
	}


static func negotiation_stakes(price: int) -> Dictionary:
	if price < 75000:
		return {"tier": "small", "maxRounds": 4, "label": "Quick deal", "note": "Smaller ticket — counterparties often move in fewer rounds."}
	if price < 180000:
		return {"tier": "standard", "maxRounds": 5, "label": "Standard deal", "note": ""}
	if price < 350000:
		return {"tier": "major", "maxRounds": 6, "label": "Major deal", "note": "High stakes — expect tighter terms and more back-and-forth."}
	return {"tier": "institutional", "maxRounds": 7, "label": "Institutional deal", "note": "Large capital commitment — structure and patience matter."}


static func summarize_offer(offer: Dictionary) -> String:
	if offer.is_empty():
		return ""
	var total: int = int(offer.get("totalPrice", 0))
	if total <= 0:
		return ""
	var cash: int = int(offer.get("cashAtClosing", total))
	var terms: Array = offer.get("termsOffered", [])
	var has_note := false
	for t in terms:
		if RegEx.create_from_string("seller note|payment schedule|earnout").search(str(t).to_lower()) != null:
			has_note = true
			break
	var all_cash := cash >= total and not has_note
	var cash_line := "All cash %s" % MathUtil.fmt_money(total) if all_cash else "Total %s · Cash at closing %s" % [MathUtil.fmt_money(total), MathUtil.fmt_money(cash)]
	var terms_bit := ""
	if not terms.is_empty():
		var parts: PackedStringArray = []
		for t in terms:
			parts.append(str(t))
		terms_bit = " · %s" % ", ".join(parts)
	return "%s · Closing: %s%s" % [cash_line, str(offer.get("closingSpeed", "standard")), terms_bit]


static func build_counter_offer(state: RunState, player_offer: Dictionary) -> Dictionary:
	var ask: int = int(state.negotiation.get("context", {}).get("price", 0))
	if ask <= 0:
		return player_offer.duplicate(true) if not player_offer.is_empty() else {}
	if state.negotiation.has("v2"):
		var total: int = _V2.build_counter_total(state.negotiation.get("v2", {}), player_offer)
		return {
			"totalPrice": total,
			"cashAtClosing": int(round(float(total) * 0.55)),
			"closingSpeed": "standard",
			"termsOffered": player_offer.get("termsOffered", []) if not player_offer.is_empty() else [],
			"riskToCounterparty": 8,
		}
	var cp: Dictionary = state.negotiation.get("counterparty", {})
	var style: String = str(cp.get("concessionStyle", "medium"))
	var factor: float = 0.55 if style == "fast" else (0.25 if style == "slow" else 0.4)
	var anchor: int = int(cp.get("reservationPrice", int(round(float(ask) * 0.85))))
	var base: int = int(player_offer.get("totalPrice", int(round(float(ask) * 0.9))))
	var legacy_total: int = int(round(float(base) + float(anchor - base) * (1.0 - factor)))
	return {
		"totalPrice": legacy_total,
		"cashAtClosing": int(round(float(legacy_total) * 0.4)),
		"closingSpeed": "standard",
		"termsOffered": [],
		"riskToCounterparty": 8,
	}


static func _apply_accept_overrides(
	decision: String,
	intent: String,
	utility: float,
	text: String,
	offer_dict: Dictionary,
	_state: RunState,
	round_num: int,
	max_rounds: int,
) -> String:
	if intent == "accept" and utility >= LATE_ACCEPT_THRESHOLD:
		decision = "accept"
	if (decision == "counter" or decision == "ongoing") and not offer_dict.is_empty():
		if _Parser.is_closing_intent_text(text):
			if utility >= 16.0:
				decision = "accept"
			elif utility >= 14.0 and round_num >= max_rounds:
				decision = "accept"
	return decision


static func _map_v2_decision(v2_decision: String) -> String:
	match v2_decision:
		"ready":
			return "accept"
		"reject":
			return "reject"
		"counter":
			return "counter"
		_:
			return "ongoing"


static func _v2_opening_line(counterparty: Dictionary, situation: Dictionary, profile: Dictionary, rng: SeededRng) -> String:
	var species := str(counterparty.get("speciesId", "seller")).capitalize()
	var sit_label := str(situation.get("label", profile.get("situationLabel", "Negotiation")))
	return _pick_dialogue(rng, [
		"%s — %s. My ask is on the table; show me serious terms." % [species, sit_label],
		"We're here because of %s. Talk to me about price and structure." % sit_label.to_lower(),
	])


static func _v2_counter_dialogue(state: RunState, v2_result: Dictionary, counter: Dictionary) -> String:
	var hint := str(v2_result.get("statusHint", "Terms too far apart"))
	var acceptable: int = int(v2_result.get("acceptableValue", 0))
	var gauge_zone: Dictionary = v2_result.get("gaugeZone", {})
	var zone_hint := str(gauge_zone.get("hint", ""))
	if hint == "Terms acceptable; confidence still needed":
		return "%s %s" % [_pick_dialogue(SeededRng.new(state.turn), [
			"The economics are getting there — I still need confidence in how we'd close.",
			"Price is closer, but I'm not ready to shake hands yet.",
		]), zone_hint]
	return _pick_dialogue(SeededRng.new(state.turn + 3), [
		"I need something closer to %s." % MathUtil.fmt_money(maxi(int(counter.get("totalPrice", 0)), acceptable)),
		"You're not there yet — %s" % hint.to_lower(),
	])


static func _resolve_seller_dialogue(
	ai_parsed: Dictionary,
	dialogue_decision: String,
	state: RunState,
	player_message: String,
	offer_dict: Dictionary = {},
	v2_result: Dictionary = {},
) -> String:
	if not v2_result.is_empty() and bool(v2_result.get("readyToClose", false)):
		return _player_offer_acceptance_line(offer_dict, state)

	var ai_dialogue: String = str(ai_parsed.get("dialogue", "")).strip_edges()
	var cp: Dictionary = state.negotiation.get("counterparty", {})
	var rng := SeededRng.new(state.run_seed + state.turn * 997 + int(state.negotiation.get("round", 0)))
	var dialogue := _NpcSpecies.sanitize_seller_dialogue(ai_dialogue, dialogue_decision)
	if not dialogue.is_empty() and _dialogue_gap_conflicts_with_math(dialogue, state.negotiation, player_message):
		dialogue = ""
	if dialogue.is_empty() and not v2_result.is_empty():
		var hint := str(v2_result.get("statusHint", ""))
		if dialogue_decision == "accept":
			dialogue = _pick_dialogue(rng, [
				"The terms work — press Close Deal when you're ready.",
				"I'm willing at these numbers. Close Deal when you want to finalize.",
			])
		elif hint == "Terms acceptable; confidence still needed":
			dialogue = _pick_dialogue(rng, [
				"The price is getting workable, but I need a bit more confidence before we close.",
				"Economics are close — help me trust the rest of the package.",
			])
	if dialogue.is_empty():
		dialogue = _gap_aware_dialogue(state.negotiation, player_message, dialogue_decision, cp, rng)
	if dialogue.is_empty():
		dialogue = _NpcSpecies.fallback_dialogue_farm(dialogue_decision, cp, rng)
	if dialogue.is_empty():
		dialogue = _fallback_dialogue(dialogue_decision, state)
	return dialogue


static func _player_offer_acceptance_line(offer_dict: Dictionary, state: RunState) -> String:
	var total: int = int(offer_dict.get("totalPrice", 0))
	var cash: int = int(offer_dict.get("cashAtClosing", total))
	var rng := SeededRng.new(state.run_seed + state.turn * 131)
	if total <= 0:
		return _pick_dialogue(rng, [
			"The terms work — press Close Deal when you're ready.",
		])
	if cash >= total:
		return _pick_dialogue(rng, [
			"%s all cash at closing works for me — press Close Deal when you're ready." % MathUtil.fmt_money(total),
			"I'm good at %s cash at closing. Use Close Deal to finalize." % MathUtil.fmt_money(total),
			"Yes — %s all cash. Close Deal whenever you're ready." % MathUtil.fmt_money(total),
		])
	return _pick_dialogue(rng, [
		"%s total with %s at closing — I can live with that. Press Close Deal to finalize." % [
			MathUtil.fmt_money(total),
			MathUtil.fmt_money(cash),
		],
	])


static func _dialogue_gap_conflicts_with_math(dialogue: String, negotiation: Dictionary, player_message: String) -> bool:
	var math: Dictionary = _AiPrompt.compute_offer_math(negotiation, player_message)
	if math.is_empty():
		return false
	var verified_gap: int = int(math.get("gapAbs", 0))
	var lower := dialogue.to_lower()
	for m in RegEx.create_from_string("(\\d[\\d,]*)\\s*(?:away|short|gap|difference|under|below|off)").search_all(lower):
		var claimed: int = int(m.get_string(1).replace(",", ""))
		if claimed >= 1000 and verified_gap < 500:
			return true
		if verified_gap > 0 and claimed > verified_gap * 3 and claimed >= 250:
			return true
	for m in RegEx.create_from_string("(\\d[\\d,]*)\\s*(?:k|thousand)").search_all(lower):
		if verified_gap < 500:
			return true
	if RegEx.create_from_string("over\\s+\\$?1[,\\d]{3}|more\\s+than\\s+\\$?1[,\\d]{3}|1[,\\d]{3}\\+").search(lower) != null:
		if verified_gap < 500:
			return true
	return false


static func _gap_aware_dialogue(negotiation: Dictionary, player_message: String, decision: String, cp: Dictionary, rng: SeededRng) -> String:
	var math: Dictionary = _AiPrompt.compute_offer_math(negotiation, player_message)
	if math.is_empty():
		return ""
	var ask: int = int(math.get("ask", 0))
	var total: int = int(math.get("total", 0))
	var gap: int = int(math.get("gap", 0))
	if decision == "accept":
		return _pick_dialogue(rng, [
			"%s works — let's get the paperwork moving." % MathUtil.fmt_money(total),
			"Fine by me at %s." % MathUtil.fmt_money(total),
		])
	if gap > 0:
		if gap < 500:
			return _pick_dialogue(rng, [
				"%s is close — you're only %s under my %s ask." % [MathUtil.fmt_money(total), MathUtil.fmt_money(gap), MathUtil.fmt_money(ask)],
				"You're %s short of %s, not miles apart. Sharpen the cash or terms." % [MathUtil.fmt_money(gap), MathUtil.fmt_money(ask)],
			])
		return _pick_dialogue(rng, [
			"%s is below my %s ask — you're %s short." % [MathUtil.fmt_money(total), MathUtil.fmt_money(ask), MathUtil.fmt_money(gap)],
			"I need more than %s. The gap to %s is %s." % [MathUtil.fmt_money(total), MathUtil.fmt_money(ask), MathUtil.fmt_money(gap)],
		])
	if gap < 0:
		return _pick_dialogue(rng, [
			"%s is above my ask — the price works." % MathUtil.fmt_money(total),
		])
	return _pick_dialogue(rng, [
		"That matches my %s ask — let's talk closing." % MathUtil.fmt_money(ask),
	])


static func _pick_dialogue(rng: SeededRng, options: Array) -> String:
	if options.is_empty():
		return ""
	return str(options[rng.randi_range(0, options.size() - 1)])


static func _redline_hit(offer_dict: Dictionary, state: RunState) -> bool:
	var bid: int = int(offer_dict.get("totalPrice", 0))
	var red_line: int = int(state.negotiation.get("counterparty", {}).get("redLine", 0))
	return red_line > 0 and bid > 0 and bid < red_line


static func _append_v2_status_message(state: RunState, v2_result: Dictionary) -> void:
	var display: Dictionary = _V2.gauge_display(v2_result.get("profile", state.negotiation.get("v2", {})))
	var hint := str(v2_result.get("statusHint", ""))
	var zone := str(display.get("zoneLabel", ""))
	var arrow := str(display.get("arrow", "→"))
	_append_system_message(state, "Deal Momentum: %s %s · %s · %s" % [zone, arrow, hint, _v2_gate_summary(v2_result)])


static func _v2_gate_summary(v2_result: Dictionary) -> String:
	var econ := "economics ✓" if bool(v2_result.get("economicGateMet", false)) else "economics —"
	var will := "willingness ✓" if bool(v2_result.get("willingnessGateMet", false)) else "willingness —"
	return "%s · %s" % [econ, will]


static func _append_system_message(state: RunState, text: String) -> void:
	_append_message(state, "system", text, "System")


static func _maybe_append_final_round_hint(
	state: RunState,
	offer_dict: Dictionary,
	utility: float,
	round_num: int,
	max_rounds: int,
) -> void:
	if round_num < max_rounds or str(state.negotiation.get("status", "ongoing")) != "ongoing":
		return
	if bool(state.negotiation.get("readyToClose", false)):
		return
	if not offer_dict.is_empty() and utility >= 14.0:
		_append_system_message(state, "(This is close to my final position — put your best number on the table and use Close Deal if you see the button.)")
	else:
		_append_system_message(state, "(This is close to my final position — we should wrap this up soon.)")


static func _send_contest_message(state: RunState, message: String, ai_parsed: Dictionary, skip_player_append: bool) -> Dictionary:
	if not skip_player_append:
		_append_message(state, "player", message, "You")
	state.negotiation["round"] = int(state.negotiation.get("round", 0)) + 1

	var parsed_input: Dictionary = ai_parsed if not ai_parsed.is_empty() else {"intent": "question"}
	var resolved: Dictionary = _Rival.engine_resolve_contest_turn(state.negotiation, message, parsed_input, state)
	var rival: Dictionary = state.negotiation.get("rival", {})

	if bool(resolved.get("walkAway", false)):
		if not str(resolved.get("rivalDialogue", "")).is_empty():
			_append_message(state, "rival", str(resolved.get("rivalDialogue", "")), _Rival.display_name(rival))
		return _rival_wins_contest(state, "You walked away — Rowe takes the listing.")

	var seller_dialogue: String = str(resolved.get("sellerDialogue", ""))
	if not seller_dialogue.is_empty():
		_append_message(state, "seller", seller_dialogue, _seller_name(state))

	var rival_action: String = str(resolved.get("rivalAction", "hold"))
	if not bool(state.negotiation.get("rivalConceded", false)) and not str(resolved.get("rivalDialogue", "")).is_empty():
		_append_message(state, "rival", str(resolved.get("rivalDialogue", "")), _Rival.display_name(rival))

	if rival_action == "concede":
		state.negotiation["rivalConceded"] = true
		_append_message(state, "system", "%s conceded — the seller will only consider your package now." % _Rival.display_name(rival), "System")
	elif rival_action == "counter":
		var ro: Variant = resolved.get("rivalOffer")
		if ro is Dictionary and int((ro as Dictionary).get("totalPrice", 0)) > 0:
			var normalized: Dictionary = _Parser.normalize_offer(ro as Dictionary)
			state.negotiation["rivalLastOffer"] = normalized
			_append_message(state, "system", "%s bid is now %s." % [_Rival.display_name(rival), MathUtil.fmt_money(int(normalized.get("totalPrice", 0)))], "System")

	state.negotiation["lastUtility"] = float(resolved.get("playerU", 0.0))
	state.negotiation["lastDecision"] = "counter"

	var round_num: int = int(state.negotiation.get("round", 0))
	var max_rounds: int = int(state.negotiation.get("maxRounds", 8))
	if round_num >= max_rounds and not bool(resolved.get("readyToClose", false)):
		if str(state.negotiation.get("leadingBidder", "")) == "rival" and not bool(state.negotiation.get("rivalConceded", false)):
			_append_message(state, "rival", _Rival.RIVAL_WIN_TIMEOUT[randi() % _Rival.RIVAL_WIN_TIMEOUT.size()], _Rival.display_name(rival))
			return _rival_wins_contest(state, "Time ran out — Rowe's package still leads.")

	if bool(resolved.get("readyToClose", false)):
		var pending: Variant = resolved.get("pendingOffer")
		if pending is Dictionary:
			var offer_dict: Dictionary = pending as Dictionary
			var cash_at_closing: int = mini(
				state.cash,
				int(offer_dict.get("cashAtClosing", int(offer_dict.get("totalPrice", 0)))),
			)
			if state.cash < cash_at_closing:
				var cash_reply := "I like your package, but you'll need %s in cash to close." % MathUtil.fmt_money(cash_at_closing)
				_append_message(state, "seller", cash_reply, _seller_name(state))
				return {"ok": true, "state": state, "decision": "counter", "reply": cash_reply}
			var opp_id: String = str(state.negotiation.get("opportunityId", ""))
			var acquire := AcquisitionSystem.close_business_acquisition(state, opp_id, offer_dict)
			if not bool(acquire.get("ok", false)):
				return acquire
			var done_msg := "%s Deal closed — you outbid Rowe." % _fallback_dialogue("accept", state)
			_append_message(state, "seller", done_msg, _seller_name(state))
			state.active_rival_contest_opp_id = ""
			if acquire.get("business") is BusinessInstance:
				state.run_log.append("Contest won — %s" % (acquire.get("business") as BusinessInstance).name)
			state.negotiation = {}
			return {
				"ok": true,
				"state": state,
				"decision": "accept",
				"reply": done_msg,
				"business": acquire.get("business"),
				"closed": true,
			}

	return {"ok": true, "state": state, "decision": "counter", "reply": seller_dialogue}


static func _rival_wins_contest(state: RunState, note: String) -> Dictionary:
	state.reputation = maxi(0, state.reputation - 2)
	state.run_log.append(note)
	state.active_rival_contest_opp_id = ""
	var opp_id: String = str(state.negotiation.get("opportunityId", ""))
	_remove_contested_opportunity(state, opp_id)
	state.negotiation = {}
	return {"ok": true, "state": state, "closed": true, "decision": "rival_win", "reply": note}


static func _remove_contested_opportunity(state: RunState, opportunity_id: String) -> void:
	var kept: Array = []
	for opp_variant in state.opportunities:
		if typeof(opp_variant) != TYPE_DICTIONARY:
			continue
		if str((opp_variant as Dictionary).get("id", "")) != opportunity_id:
			kept.append(opp_variant)
	state.opportunities = kept


static func end_negotiation(state: RunState, walked: bool = false) -> Dictionary:
	if state.negotiation.is_empty():
		return {"ok": true, "state": state}
	if walked:
		state.run_log.append("Walked away from negotiation")
		if str(state.negotiation.get("kind", "")) == "rival_contest":
			return _rival_wins_contest(state, "Walked away from the contest.")
	state.negotiation = {}
	return {"ok": true, "state": state, "closed": true}


static func evaluate_offer_utility(offer: Dictionary, counterparty: Dictionary, context: Dictionary, state: RunState) -> float:
	var cash_at_closing: int = int(offer.get("cashAtClosing", offer.get("totalPrice", 0)))
	var total_price: int = int(offer.get("totalPrice", 0))
	var value: float = 0.0
	var role: String = str(counterparty.get("role", "seller"))

	if role == "seller" or role == "lender":
		var reservation: int = int(counterparty.get("reservationPrice", 0))
		var price_score: float = 0.0
		if reservation > 0:
			price_score = float(total_price - reservation) / maxf(1.0, float(reservation))
		value += price_score * 40.0

		var speed_map := {"fast": 1.0, "standard": 0.5, "extended": 0.0}
		var closing_speed: String = str(offer.get("closingSpeed", "standard"))
		var closing_speed_score: float = float(speed_map.get(closing_speed, 0.5))
		value += closing_speed_score * float(counterparty.get("urgency", 0.5)) * 20.0

		var certainty: float = float(cash_at_closing) / maxf(1.0, float(total_price))
		value += certainty * 15.0
	else:
		value += float(offer.get("priceAdjustment", 0)) * -30.0
		value += float(offer.get("concessionSize", 0)) * 25.0

	var preferred: Array = counterparty.get("preferredTerms", [])
	var terms: Array = offer.get("termsOffered", [])
	var hits: Array = []
	for p in preferred:
		var pl := str(p).to_lower()
		for t in terms:
			if _term_matches_preferred(str(t), pl):
				hits.append(str(p))
				break
	offer["preferredTermsHit"] = hits
	value += float(hits.size()) * 8.0
	value += float(counterparty.get("trust", 0.5)) * 10.0
	value -= (1.0 - float(counterparty.get("riskTolerance", 0.3))) * float(offer.get("riskToCounterparty", 8))

	var red_line: int = int(counterparty.get("redLine", 0))
	if red_line > 0 and total_price > 0 and total_price < red_line:
		value -= 100.0

	if counterparty.has("speciesId"):
		value = _NpcSpecies.apply_utility_bonus(value, offer, counterparty, context, state)

	return value


static func _term_matches_preferred(term: String, preferred: String) -> bool:
	var tl := term.to_lower().strip_edges()
	var pl := preferred.to_lower().strip_edges()
	if tl.is_empty() or pl.is_empty():
		return false
	if tl.contains(pl) or pl.contains(tl):
		return true
	for word in pl.split(" ", false):
		if word.length() >= 4 and tl.contains(word):
			return true
	var first_word: String = pl.split(" ")[0] if pl.contains(" ") else pl
	return first_word.length() >= 3 and tl.contains(first_word)


static func negotiation_decision(utility: float, round_num: int, max_rounds: int) -> String:
	if utility >= ACCEPT_THRESHOLD:
		return "accept"
	if utility <= REJECT_THRESHOLD:
		return "reject"
	if round_num >= max_rounds:
		return "accept" if utility >= LATE_ACCEPT_THRESHOLD else "counter"
	return "counter"


static func _seller_name(state: RunState) -> String:
	var cp: Dictionary = state.negotiation.get("counterparty", {})
	var arch: Dictionary = _Archetypes.get_archetype(str(cp.get("archetypeId", "")))
	return str(arch.get("name", "Seller"))


static func _fallback_dialogue(decision: String, state: RunState) -> String:
	var cp: Dictionary = state.negotiation.get("counterparty", {})
	if cp.has("speciesId") and not str(cp.get("speciesId", "")).is_empty():
		return _NpcSpecies.fallback_dialogue_farm(decision, cp)
	match decision:
		"accept":
			return "Alright, that works for me."
		"reject":
			return "I appreciate the offer, but"
		"counter":
			return "I hear you, but I need something closer to my number."
		_:
			return "Go on, I'm listening."


static func _append_message(state: RunState, role: String, text: String, speaker: String) -> void:
	var msgs: Array = state.negotiation.get("messages", [])
	msgs.append({"role": role, "speaker": speaker, "text": text})
	state.negotiation["messages"] = msgs


static func _send_relationship_message(state: RunState, message: String, ai_parsed: Dictionary, skip_player_append: bool) -> Dictionary:
	var text := message.strip_edges()
	if not skip_player_append:
		_append_message(state, "player", text, "You")
	state.negotiation["round"] = int(state.negotiation.get("round", 0)) + 1

	var parsed_input: Dictionary = ai_parsed if not ai_parsed.is_empty() else {"intent": "question"}
	if str(parsed_input.get("intent", "")) == "walk":
		return end_negotiation(state, true)

	var offer_dict: Dictionary = _Urgent.parse_relationship_offer(text)
	if str(parsed_input.get("intent", "")) in ["offer", "accept"] or offer_dict.get("concessionSize", 0.0) > 0.0:
		state.negotiation["playerLastOffer"] = offer_dict.duplicate(true)
		state.negotiation["playerLastOfferText"] = text

	var cp: Dictionary = state.negotiation.get("counterparty", {})
	var utility: float = _Urgent.evaluate_relationship_utility(offer_dict, cp)
	var max_rounds: int = int(state.negotiation.get("maxRounds", 5))
	var round_num: int = int(state.negotiation.get("round", 0))
	var decision: String = negotiation_decision(utility, round_num, max_rounds)
	state.negotiation["lastUtility"] = utility
	state.negotiation["lastDecision"] = decision

	var seller_reply := _NpcSpecies.fallback_dialogue_farm(decision if decision != "ongoing" else "counter", cp)
	match decision:
		"accept":
			state.negotiation["readyToClose"] = true
			state.negotiation["pendingOffer"] = offer_dict.duplicate(true)
			if seller_reply.find("close") == -1:
				seller_reply = "%s We can work with that." % seller_reply
			_append_message(state, "seller", seller_reply, str(cp.get("npcName", "Contact")))
			return {"ok": true, "state": state, "decision": "accept", "reply": seller_reply, "ready_to_close": true}
		"reject":
			state.negotiation["readyToClose"] = false
			_append_message(state, "seller", seller_reply, str(cp.get("npcName", "Contact")))
			return {"ok": true, "state": state, "decision": "reject", "reply": seller_reply}
		_:
			_append_message(state, "seller", seller_reply, str(cp.get("npcName", "Contact")))
			return {"ok": true, "state": state, "decision": "counter", "reply": seller_reply, "utility": utility}


static func _remove_levelup_opportunity(state: RunState, opportunity_id: String) -> void:
	var kept: Array = []
	for opp_variant in state.opportunities:
		if typeof(opp_variant) != TYPE_DICTIONARY:
			continue
		if str((opp_variant as Dictionary).get("id", "")) != opportunity_id:
			kept.append(opp_variant)
	state.opportunities = kept
