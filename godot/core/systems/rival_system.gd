# Cassius "Cash" Rowe — three-way acquisition contests (port of js/rival-farmer.js).
class_name RivalSystem
extends RefCounted

const _Parser := preload("res://core/systems/negotiation_offer_parser.gd")
const _Negotiation := preload("res://core/systems/negotiation_system.gd")

const CONTEST_INTERVAL := 3
const RIVAL_NAME := "Cassius \"Cash\" Rowe"
const RIVAL_TITLE := "Rival Farmer"
const RIVAL_EMOJI := "🐐"

const EXCLUDED_TERMS: Array[String] = [
	"employee retention",
	"staff retention",
	"growth plan",
	"earnout",
	"seller note",
	"employment commitment",
	"continuity plan",
	"premium member card",
]

const OPENING_LINES: Array[String] = [
	"%s from Rowe Ag on %s — cash-heavy, paperwork-light.",
	"I'll open at %s for %s — no earnouts, no second place.",
	"Rowe Ag bids %s on %s — clean break, fast close.",
	"%s cash-forward for %s. Sharpen your pencil or step aside.",
]

const RIVAL_COUNTER_LINES: Array[String] = [
	"%s — I'll beat your headline. Cash at close, no barnyard drama.",
	"Try %s. Rowe Ag doesn't bid on feelings — we bid on closing dates.",
	"%s, cash-heavy. You can keep the creative financing.",
	"New number: %s. My accountant stopped screaming, so we're in business.",
]

const RIVAL_HOLD_LINES: Array[String] = [
	"Still ahead at %s on the package that actually closes.",
	"My %s cash package still lands harder here.",
	"I don't do retention plans — beat %s with cash or enjoy second place.",
]

const RIVAL_CONCEDE_LINES: Array[String] = [
	"Fine. You brought structure I won't touch — Rowe Ag buys dirt and cash flow, not HR newsletters.",
	"You out-structured me. I'll go find a seller who understands money over manifestos.",
	"That's past where my spreadsheet says brave turns into stupid. You take the listing.",
]

const RIVAL_WIN_WALK: Array[String] = [
	"Smart fold. I'll send you a postcard from the closing table on %s.",
	"Thanks for the clear lane. Rowe Ag accepts your surrender.",
]

const RIVAL_WIN_TIMEOUT: Array[String] = [
	"Turn's up. My bid stands — classic Rowe Ag efficiency.",
	"While you were drafting speeches, I was writing a check.",
]


static func is_active(state: RunState) -> bool:
	return state != null and state.is_capital_farm()


static func is_contest_turn(state: RunState) -> bool:
	if not is_active(state):
		return false
	if state.turn >= CONTEST_INTERVAL and state.turn % CONTEST_INTERVAL == 0:
		return true
	return false


static func score_opportunity(_state: RunState, opp: Dictionary) -> float:
	if opp.is_empty():
		return -1.0
	var asset_type := str(opp.get("assetType", ""))
	if asset_type != "business":
		return -1.0
	var revenue: int = int(opp.get("revenue", 0))
	var margin: float = float(opp.get("margin", 0.2))
	var price: int = maxi(int(opp.get("price", 1)), 1)
	var profit: float = float(revenue) * margin
	var score: float = (profit / float(price)) * 120.0 + float(revenue) / 800.0
	if bool(opp.get("starterDeal", false)):
		score += 25.0
	return score


static func pick_contest_target(state: RunState) -> Dictionary:
	var candidates: Array = []
	for opp_variant in state.opportunities:
		if typeof(opp_variant) != TYPE_DICTIONARY:
			continue
		var opp: Dictionary = opp_variant
		if bool(opp.get("rivalContest", false)):
			continue
		if str(opp.get("assetType", "")) != "business":
			continue
		candidates.append(opp)
	if candidates.is_empty():
		return {}
	candidates.sort_custom(func(a, b): return score_opportunity(state, a) > score_opportunity(state, b))
	return candidates[0]


static func apply_contest_to_turn(state: RunState) -> Dictionary:
	if not is_contest_turn(state):
		return {}
	if state.rival_contest_applied_turn == state.turn:
		return {}
	var target := pick_contest_target(state)
	if target.is_empty():
		return {}
	for i in state.opportunities.size():
		var opp: Dictionary = state.opportunities[i]
		if str(opp.get("id", "")) == str(target.get("id", "")):
			opp["rivalContest"] = true
			opp["rivalContestTurn"] = state.turn
			state.opportunities[i] = opp
			break
	state.rival_contest_applied_turn = state.turn
	state.active_rival_contest_opp_id = str(target.get("id", ""))
	state.run_log.append("%s is contesting %s" % [RIVAL_NAME, str(target.get("name", "a listing"))])
	return {"opp": target}


static func resolve_uncontested_contests(state: RunState) -> void:
	var removed: Array[String] = []
	for opp_variant in state.opportunities:
		if typeof(opp_variant) != TYPE_DICTIONARY:
			continue
		var opp: Dictionary = opp_variant
		if not bool(opp.get("rivalContest", false)):
			continue
		var short_name := str(opp.get("name", "Listing")).split("—")[0].strip_edges()
		state.run_log.append("%s closed %s — you didn't win the bidding war in time." % [RIVAL_NAME, short_name])
		removed.append(str(opp.get("id", "")))
	if removed.is_empty():
		return
	var kept: Array = []
	for opp_variant in state.opportunities:
		if typeof(opp_variant) != TYPE_DICTIONARY:
			continue
		if str((opp_variant as Dictionary).get("id", "")) in removed:
			continue
		kept.append(opp_variant)
	state.opportunities = kept
	state.active_rival_contest_opp_id = ""


static func create_rival(_state: RunState) -> Dictionary:
	return {
		"name": RIVAL_NAME,
		"npcName": RIVAL_NAME,
		"title": RIVAL_TITLE,
		"speciesId": "goat",
		"emoji": RIVAL_EMOJI,
		"archetypeId": "corporate_seller",
		"role": "rival_buyer",
	}


static func display_name(rival: Dictionary) -> String:
	return str(rival.get("npcName", rival.get("name", RIVAL_NAME)))


static func _offer_dict(negotiation: Dictionary, key: String) -> Dictionary:
	var value: Variant = negotiation.get(key)
	return value if value is Dictionary else {}


static func build_contest_rules(state: RunState, opp: Dictionary, counterparty: Dictionary) -> Dictionary:
	var ask: int = int(opp.get("price", 0))
	var cp: Dictionary = counterparty if counterparty else {}
	var rng := SeededRng.new(state.run_seed + state.turn * 31337 + ask)
	return {
		"askPrice": ask,
		"rivalMaxBid": int(round(float(ask) * rng.randf_range(1.03, 1.05))),
		"rivalMinBid": int(round(float(ask) * 0.9)),
		"rivalExcludedTerms": EXCLUDED_TERMS.duplicate(),
		"sellerReservation": int(cp.get("reservationPrice", int(round(float(ask) * 0.88)))),
		"sellerRedLine": int(cp.get("redLine", int(round(float(ask) * 0.8)))),
		"sellerPreferredTerms": cp.get("preferredTerms", []),
		"acceptUtility": 18.0,
		"playerMaxCashBid": int(round(float(state.cash) * 0.95)),
		"absurdBidThreshold": int(round(float(ask) * 1.12)),
		"playerHardCap": int(round(float(ask) * 1.2)),
	}


static func opening_offer(opp: Dictionary, rules: Dictionary, rng: SeededRng) -> Dictionary:
	var ask: int = int(rules.get("askPrice", opp.get("price", 0)))
	var mult: float = rng.randf_range(0.93, 0.98)
	var total: int = int(round(float(ask) * mult))
	return {
		"totalPrice": total,
		"cashAtClosing": int(round(float(total) * rng.randf_range(0.5, 0.65))),
		"closingSpeed": "fast",
		"termsOffered": ["fast close", "clean break"],
	}


static func rival_opening_line(opp: Dictionary, offer: Dictionary) -> String:
	var asset := str(opp.get("name", "the listing")).split("—")[0].strip_edges()
	var price := MathUtil.fmt_money(int(offer.get("totalPrice", 0)))
	return OPENING_LINES[randi() % OPENING_LINES.size()] % [price, asset]


static func seller_response_to_rival(opp: Dictionary, offer: Dictionary, counterparty: Dictionary) -> String:
	var ask: int = int(opp.get("price", 0))
	var bid: int = int(offer.get("totalPrice", 0))
	var species := str(counterparty.get("speciesId", ""))
	var hint := "I need more than speed alone to pick a buyer."
	if species == "hen":
		hint = "I need more than a fast close — show me certainty and structure."
	elif species == "horse":
		hint = "Price is one piece — continuity and how you treat people matter here."
	if bid >= int(float(ask) * 0.98):
		return "That's essentially my asking price of %s. I'm not committed yet — I'll hear what your competitor has to say." % MathUtil.fmt_money(ask)
	if bid >= int(float(ask) * 0.9):
		return "%s is in the conversation against %s, but %s" % [MathUtil.fmt_money(bid), MathUtil.fmt_money(ask), hint.to_lower()]
	return "%s is below where I need to be on %s. Both of you will need to sharpen your numbers." % [MathUtil.fmt_money(bid), MathUtil.fmt_money(ask)]


static func rival_cannot_match_terms(player_terms: Array, rules: Dictionary) -> Array:
	var excluded: Array = rules.get("rivalExcludedTerms", EXCLUDED_TERMS)
	var out: Array = []
	for t in player_terms:
		var tl := str(t).to_lower()
		for ex in excluded:
			var el := str(ex).to_lower()
			var first := el.split(" ")[0] if el.contains(" ") else el
			if tl.contains(first) or el.contains(tl.split(" ")[0]):
				out.append(t)
				break
	return out


static func compute_contest_utilities(negotiation: Dictionary, state: RunState) -> Dictionary:
	var rules: Dictionary = negotiation.get("contestRules", {})
	var cp: Dictionary = negotiation.get("counterparty", {})
	var ctx: Dictionary = negotiation.get("context", {})
	var player_u: float = -INF
	var rival_u: float = -INF
	var player_offer: Dictionary = _offer_dict(negotiation, "playerLastOffer")
	if not player_offer.is_empty():
		player_u = _Negotiation.evaluate_offer_utility(player_offer, cp, ctx, state)
		for t in rival_cannot_match_terms(player_offer.get("termsOffered", []), rules):
			player_u += 6.0
			for p in rules.get("sellerPreferredTerms", []):
				var pl := str(p).to_lower()
				var tl := str(t).to_lower()
				if tl.contains(pl.split(" ")[0]):
					player_u += 5.0
					break
	if not bool(negotiation.get("rivalConceded", false)):
		var rival_offer: Dictionary = _offer_dict(negotiation, "rivalLastOffer")
		if not rival_offer.is_empty():
			rival_u = _Negotiation.evaluate_offer_utility(rival_offer, cp, ctx, state)
	return {"playerU": player_u, "rivalU": rival_u}


static func compute_rival_response(negotiation: Dictionary, player_offer: Dictionary, player_u: float, rival_u: float, _text: String, rules: Dictionary) -> Dictionary:
	if bool(negotiation.get("rivalConceded", false)):
		return {"action": "none", "dialogue": ""}
	var rival_offer: Dictionary = _offer_dict(negotiation, "rivalLastOffer")
	var rival_price: int = int(rival_offer.get("totalPrice", 0))
	var player_price: int = int(player_offer.get("totalPrice", 0)) if not player_offer.is_empty() else 0
	var unmatched := rival_cannot_match_terms(player_offer.get("termsOffered", []), rules)
	var ask: int = int(rules.get("askPrice", 0))

	if not player_offer.is_empty() and player_price >= int(rules.get("absurdBidThreshold", ask)) and player_u >= rival_u:
		return {"action": "concede", "dialogue": RIVAL_CONCEDE_LINES[randi() % RIVAL_CONCEDE_LINES.size()]}
	if unmatched.size() > 0 and player_u >= rival_u - 4.0 and player_price >= rival_price:
		return {"action": "concede", "dialogue": "Fine. You brought %s I won't touch." % str(unmatched[0])}

	if player_u < rival_u:
		if player_price > rival_price:
			var bump: int = mini(int(round(maxf(float(player_price) + float(ask) * 0.012, float(rival_price) * 1.02))), int(rules.get("rivalMaxBid", ask)))
			if bump > rival_price:
				return {
					"action": "counter",
					"dialogue": RIVAL_COUNTER_LINES[randi() % RIVAL_COUNTER_LINES.size()] % MathUtil.fmt_money(bump),
					"rivalOffer": {
						"totalPrice": bump,
						"cashAtClosing": int(round(float(bump) * 0.55)),
						"closingSpeed": "fast",
						"termsOffered": ["fast close"],
					},
				}
		return {"action": "hold", "dialogue": RIVAL_HOLD_LINES[randi() % RIVAL_HOLD_LINES.size()] % MathUtil.fmt_money(rival_price)}

	if player_price >= rival_price:
		var bump2: int = mini(int(round(maxf(float(player_price) + float(ask) * 0.015, float(rival_price) * 1.02))), int(rules.get("rivalMaxBid", ask)))
		if bump2 <= rival_price:
			if unmatched.size() > 0:
				return {"action": "concede", "dialogue": RIVAL_CONCEDE_LINES[randi() % RIVAL_CONCEDE_LINES.size()]}
			return {"action": "hold", "dialogue": RIVAL_HOLD_LINES[randi() % RIVAL_HOLD_LINES.size()] % MathUtil.fmt_money(rival_price)}
		return {
			"action": "counter",
			"dialogue": RIVAL_COUNTER_LINES[randi() % RIVAL_COUNTER_LINES.size()] % MathUtil.fmt_money(bump2),
			"rivalOffer": {
				"totalPrice": bump2,
				"cashAtClosing": int(round(float(bump2) * 0.55)),
				"closingSpeed": "fast",
				"termsOffered": ["fast close"],
			},
		}
	return {"action": "hold", "dialogue": RIVAL_HOLD_LINES[randi() % RIVAL_HOLD_LINES.size()] % MathUtil.fmt_money(rival_price)}


static func seller_dialogue_for_contest(negotiation: Dictionary, player_offer: Dictionary, player_u: float, rival_u: float, intent: String) -> String:
	if player_offer.is_empty() or int(player_offer.get("totalPrice", 0)) <= 0:
		return "Give me a clear number and structure if you want a real comparison between you and Rowe." if intent == "question" else "I'm listening — put a package on the table."
	var rules: Dictionary = negotiation.get("contestRules", {})
	var rival_price: int = int(_offer_dict(negotiation, "rivalLastOffer").get("totalPrice", 0))
	var player_price: int = int(player_offer.get("totalPrice", 0))
	var rname := display_name(negotiation.get("rival", {}))
	var unmatched := rival_cannot_match_terms(player_offer.get("termsOffered", []), rules)
	var decision := _Negotiation.negotiation_decision(player_u, int(negotiation.get("round", 0)), int(negotiation.get("maxRounds", 8)))
	if bool(negotiation.get("rivalConceded", false)) and decision == "accept":
		return "With Rowe out, your package is the one I'd sign — close when you're ready."
	if player_u >= rival_u and decision == "accept":
		if unmatched.size() > 0:
			return "Your package beats Rowe — especially on %s, which he won't match. I'm ready to close." % " and ".join(unmatched)
		return "Your offer is the strongest package on the table — I'm ready when you are."
	if player_u >= rival_u:
		return "%s leads on the full package — I'm still comparing before I commit." % MathUtil.fmt_money(player_price)
	if player_price > rival_price:
		return "%s beats Rowe on price, but his cash-heavy structure still scores higher on what I weigh most." % MathUtil.fmt_money(player_price)
	return "%s trails %s's %s on the package I'd actually sign today." % [MathUtil.fmt_money(player_price), rname, MathUtil.fmt_money(rival_price)]


static func engine_resolve_contest_turn(negotiation: Dictionary, player_message: String, ai_parsed: Dictionary, state: RunState) -> Dictionary:
	var rules: Dictionary = negotiation.get("contestRules", {})
	var built: Dictionary = _Parser.build_player_offer_from_message(player_message, ai_parsed, negotiation)
	var intent: String = str(built.get("intent", "question"))
	var player_offer: Variant = built.get("offer")
	if player_offer is Dictionary and int((player_offer as Dictionary).get("totalPrice", 0)) > 0:
		negotiation["playerLastOffer"] = player_offer
		negotiation["lastOffer"] = player_offer

	var utils := compute_contest_utilities(negotiation, state)
	var player_u: float = float(utils.get("playerU", -INF))
	var rival_u: float = float(utils.get("rivalU", -INF))
	if player_offer is Dictionary and int((player_offer as Dictionary).get("totalPrice", 0)) > 0:
		negotiation["leadingBidder"] = "player" if player_u >= rival_u else "rival"

	if intent == "walk":
		return {
			"sellerDialogue": "Understood — I will talk to the other buyer.",
			"rivalDialogue": RIVAL_WIN_WALK[randi() % RIVAL_WIN_WALK.size()] % str(negotiation.get("context", {}).get("name", "the asset")).split("—")[0].strip_edges(),
			"walkAway": true,
		}

	var offer_dict: Dictionary = player_offer if player_offer is Dictionary else {}
	var seller_dialogue := seller_dialogue_for_contest(negotiation, offer_dict, player_u, rival_u, intent)
	var rival_resp := compute_rival_response(negotiation, offer_dict, player_u, rival_u, player_message, rules)

	var ready_to_close := false
	var pending_offer = null
	if intent == "accept" and negotiation.get("lastOffer") and (negotiation.get("leadingBidder") == "player" or bool(negotiation.get("rivalConceded", false))):
		ready_to_close = true
		pending_offer = negotiation.get("lastOffer")
	elif not offer_dict.is_empty() and player_u >= rival_u:
		var decision := _Negotiation.negotiation_decision(player_u, int(negotiation.get("round", 0)), int(negotiation.get("maxRounds", 8)))
		if decision == "accept":
			ready_to_close = true
			pending_offer = offer_dict

	if str(rival_resp.get("action", "")) == "concede":
		negotiation["rivalConceded"] = true
		if not offer_dict.is_empty() and player_u >= float(rules.get("acceptUtility", 18.0)) - 4.0:
			ready_to_close = true
			pending_offer = offer_dict

	return {
		"sellerDialogue": seller_dialogue,
		"rivalDialogue": str(rival_resp.get("dialogue", "")),
		"rivalAction": str(rival_resp.get("action", "hold")),
		"rivalOffer": rival_resp.get("rivalOffer"),
		"intent": intent,
		"offer": offer_dict,
		"playerU": player_u,
		"rivalU": rival_u,
		"readyToClose": ready_to_close,
		"pendingOffer": pending_offer,
		"walkAway": false,
	}


static func package_comparison_text(negotiation: Dictionary) -> String:
	if not negotiation.has("contestRules"):
		return ""
	var rname := display_name(negotiation.get("rival", {}))
	var player: Dictionary = _offer_dict(negotiation, "playerLastOffer")
	var rival: Dictionary = {} if bool(negotiation.get("rivalConceded", false)) else _offer_dict(negotiation, "rivalLastOffer")
	var lines: PackedStringArray = ["Packages on the table:", ""]
	if rival.is_empty() and player.is_empty():
		lines.append("%s opened — you haven't bid yet." % rname)
	elif player.is_empty():
		lines.append("%s: %s" % [rname, MathUtil.fmt_money(int(rival.get("totalPrice", 0)))])
	else:
		lines.append("You: %s (cash %s)" % [
			MathUtil.fmt_money(int(player.get("totalPrice", 0))),
			MathUtil.fmt_money(int(player.get("cashAtClosing", 0))),
		])
		if not rival.is_empty():
			lines.append("%s: %s (cash %s)" % [
				rname,
				MathUtil.fmt_money(int(rival.get("totalPrice", 0))),
				MathUtil.fmt_money(int(rival.get("cashAtClosing", 0))),
			])
	var lead := str(negotiation.get("leadingBidder", ""))
	if lead == "player":
		lines.append("")
		lines.append("You lead on overall package.")
	elif lead == "rival":
		lines.append("")
		lines.append("%s leads on overall package." % rname)
	return "\n".join(lines)
