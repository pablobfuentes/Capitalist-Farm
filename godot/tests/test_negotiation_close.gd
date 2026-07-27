extends GutTest

const Parser := preload("res://core/systems/negotiation_offer_parser.gd")


func _neg_fixture() -> Dictionary:
	return {
		"context": {"price": 21251, "opp": {"revenue": 8500}},
		"counterparty": {"archetypeId": "desperate_seller", "role": "seller"},
		"playerLastOffer": null,
	}


func test_all_upfront_parses_full_cash() -> void:
	var upfront: Dictionary = Parser.parse_offer_amounts_from_text("is 18,000 good for you? all upfront.")
	assert_eq(int(upfront.get("totalPrice", 0)), 18000)
	assert_eq(int(upfront.get("cashAtClosing", 0)), 18000)


func test_at_closing_only_is_all_cash() -> void:
	var at_close: Dictionary = Parser.parse_offer_amounts_from_text("ok I'll do 16,500 at closing, that is the best I can do")
	assert_eq(int(at_close.get("totalPrice", 0)), 16500)
	assert_eq(int(at_close.get("cashAtClosing", 0)), 16500)


func test_close_at_parses_all_cash() -> void:
	var close_at: Dictionary = Parser.parse_offer_amounts_from_text("all right, lets close at 18,000 if you agree")
	assert_eq(int(close_at.get("totalPrice", 0)), 18000)
	assert_eq(int(close_at.get("cashAtClosing", 0)), 18000)


func test_seller_note_split() -> void:
	var note: Dictionary = Parser.parse_offer_amounts_from_text("10,000 upfront and 6,000 on a sellers note for next quarter")
	assert_eq(int(note.get("totalPrice", 0)), 16000)
	assert_eq(int(note.get("cashAtClosing", 0)), 10000)
	assert_false(Parser.is_all_cash_offer_text("10,000 upfront and 6,000 on a sellers note for next quarter"))


func test_seller_note_at_closing_split() -> void:
	var note: Dictionary = Parser.parse_offer_amounts_from_text("8000 at closing and 4000 on seller note", 11400)
	assert_eq(int(note.get("totalPrice", 0)), 12000)
	assert_eq(int(note.get("cashAtClosing", 0)), 8000)


func test_seller_note_offer_accepted_by_utility() -> void:
	var offer: Dictionary = Parser.build_player_offer_from_message(
		"8000 upfront and 4000 on seller note",
		{"intent": "question"},
		{"context": {"price": 11400}, "counterparty": {}},
	).get("offer", {})
	assert_eq(int(offer.get("totalPrice", 0)), 12000)
	assert_eq(int(offer.get("cashAtClosing", 0)), 8000)
	var cp: Dictionary = NegotiationArchetypes.build_counterparty("desperate_seller", 11400, SeededRng.new(42))
	var utility: float = NegotiationSystem.evaluate_offer_utility(
		offer,
		cp,
		{"price": 11400},
		RunState.create_new(GameMode.MODE_CAPITAL_FARM),
	)
	assert_gte(utility, NegotiationSystem.ACCEPT_THRESHOLD)


func test_ai_wrong_total_overridden_by_split_text() -> void:
	var built: Dictionary = Parser.build_player_offer_from_message(
		"8000 upfront and 4000 on seller note",
		{
			"intent": "offer",
			"offer": {"totalPrice": 8000, "cashAtClosing": 8000, "closingSpeed": "standard", "termsOffered": []},
		},
		{"context": {"price": 11400}, "counterparty": {}},
	)
	assert_eq(str(built.get("intent", "")), "offer")
	var offer: Dictionary = built.get("offer", {})
	assert_eq(int(offer.get("totalPrice", 0)), 12000)
	assert_eq(int(offer.get("cashAtClosing", 0)), 8000)


func test_plain_ask_amount_is_all_cash() -> void:
	var parsed: Dictionary = Parser.parse_offer_amounts_from_text("11400", 11400)
	assert_eq(int(parsed.get("totalPrice", 0)), 11400)
	assert_eq(int(parsed.get("cashAtClosing", 0)), 11400)


func test_pay_asking_price_parses_all_cash() -> void:
	var parsed: Dictionary = Parser.parse_offer_amounts_from_text("I'll pay your asking price of 11400", 11400)
	assert_eq(int(parsed.get("totalPrice", 0)), 11400)
	assert_eq(int(parsed.get("cashAtClosing", 0)), 11400)


func test_at_ask_offer_accepted() -> void:
	var built: Dictionary = Parser.build_player_offer_from_message(
		"I'll pay 11400",
		{"intent": "question"},
		{"context": {"price": 11400}, "counterparty": {}},
	)
	var offer: Dictionary = built.get("offer", {})
	assert_eq(int(offer.get("totalPrice", 0)), 11400)
	assert_eq(int(offer.get("cashAtClosing", 0)), 11400)
	var cp: Dictionary = NegotiationArchetypes.build_counterparty("proud_founder", 11400, SeededRng.new(7))
	var utility: float = NegotiationSystem.evaluate_offer_utility(
		offer,
		cp,
		{"price": 11400},
		RunState.create_new(GameMode.MODE_CAPITAL_FARM),
	)
	assert_gte(utility, NegotiationSystem.ACCEPT_THRESHOLD)


func test_at_ask_sets_ready_to_close() -> void:
	var state := RunState.create_new(GameMode.MODE_CAPITAL_FARM)
	state.cash = 50000
	var cp: Dictionary = NegotiationArchetypes.build_counterparty("desperate_seller", 11400, SeededRng.new(42))
	state.opportunities = [{
		"id": "test-opp",
		"price": 11400,
		"assetType": "business",
		"name": "Test Farm",
		"templateId": "grain_farm",
		"revenue": 4000,
		"margin": 0.2,
	}]
	state.negotiation = {
		"active": true,
		"opportunityId": "test-opp",
		"round": 0,
		"maxRounds": 6,
		"context": {"price": 11400, "opp": state.opportunities[0], "name": "Test Farm"},
		"counterparty": cp,
		"messages": [],
	}
	var send: Dictionary = NegotiationSystem.send_message(state, "11400 all cash", {})
	assert_true(bool(state.negotiation.get("readyToClose", false)))
	assert_eq(str(send.get("decision", "")), "accept")
	var closed: Dictionary = NegotiationSystem.close_deal(state)
	assert_true(bool(closed.get("ok", false)))
	assert_true(bool(closed.get("closed", false)))
	assert_true(state.negotiation.is_empty())
	var built: Dictionary = Parser.build_player_offer_from_message(
		"is 18,000 good for you? all upfront. plus I will keep the business name and brand",
		{"intent": "offer"},
		_neg_fixture(),
	)
	var offer: Dictionary = built.get("offer", {})
	assert_eq(int(offer.get("totalPrice", 0)), 18000)
	assert_eq(int(offer.get("cashAtClosing", 0)), 18000)
	for t in offer.get("termsOffered", []):
		assert_false(RegEx.create_from_string("seller note|payment schedule").search(str(t).to_lower()) != null)


func test_closing_intent_yields_accept() -> void:
	var closing: Dictionary = Parser.build_player_offer_from_message(
		"all right, lets close at 18,000 if you agree",
		{"intent": "question"},
		_neg_fixture(),
	)
	assert_eq(str(closing.get("intent", "")), "accept")
	assert_eq(int(closing.get("offer", {}).get("totalPrice", 0)), 18000)


func test_closing_reuses_last_offer() -> void:
	var neg := _neg_fixture()
	neg["playerLastOffer"] = {
		"totalPrice": 18000,
		"cashAtClosing": 18000,
		"closingSpeed": "standard",
		"termsOffered": [],
	}
	var close_reuse: Dictionary = Parser.build_player_offer_from_message(
		"all right, lets close if you agree",
		{"intent": "question"},
		neg,
	)
	assert_eq(str(close_reuse.get("intent", "")), "accept")
	assert_eq(int(close_reuse.get("offer", {}).get("totalPrice", 0)), 18000)


func test_retention_terms_extract_from_natural_phrasing() -> void:
	var phrases: PackedStringArray = [
		"13500 plus employee retention",
		"I'll keep all your employees at 13500",
		"13500 with a commitment to keep the team",
	]
	for phrase in phrases:
		var terms: Array = Parser.extract_terms_from_text(phrase)
		assert_true(terms.has("employee retention") or terms.has("continuity"), "expected retention/continuity in: %s" % phrase)


func test_retention_offer_beats_bare_ask_on_utility() -> void:
	var ask := 13750
	var cp: Dictionary = {
		"archetypeId": "proud_founder",
		"role": "seller",
		"reservationPrice": 13400,
		"redLine": 11000,
		"urgency": 0.35,
		"trust": 0.5,
		"riskTolerance": 0.25,
		"preferredTerms": ["respect", "continuity", "employee retention"],
		"speciesId": "horse",
	}
	var ctx := {"price": ask}
	var state := RunState.create_new(GameMode.MODE_CAPITAL_FARM)

	var bare_below: Dictionary = {"totalPrice": 13500, "cashAtClosing": 13500, "closingSpeed": "standard", "termsOffered": [], "riskToCounterparty": 8}
	var with_retention: Dictionary = Parser.enrich_offer_from_message(
		bare_below.duplicate(true),
		"13500 plus employee retention",
		{},
	)
	var at_ask: Dictionary = {"totalPrice": ask, "cashAtClosing": ask, "closingSpeed": "standard", "termsOffered": [], "riskToCounterparty": 8}

	var u_below: float = NegotiationSystem.evaluate_offer_utility(bare_below, cp, ctx, state)
	var u_retention: float = NegotiationSystem.evaluate_offer_utility(with_retention, cp, ctx, state)
	var u_ask: float = NegotiationSystem.evaluate_offer_utility(at_ask, cp, ctx, state)

	assert_gte(u_ask, NegotiationSystem.ACCEPT_THRESHOLD)
	assert_lt(u_below, NegotiationSystem.ACCEPT_THRESHOLD)
	assert_gte(u_retention, NegotiationSystem.ACCEPT_THRESHOLD)
	assert_gt(u_retention, u_below)


func test_earn_out_split_with_total_label() -> void:
	var msg := "all right, I can do 17000 total, but 14500 upfront and 2500 on an earn out to 2 quarters"
	var parsed: Dictionary = Parser.parse_offer_amounts_from_text(msg, 17562)
	assert_eq(int(parsed.get("totalPrice", 0)), 17000)
	assert_eq(int(parsed.get("cashAtClosing", 0)), 14500)
	assert_false(Parser.is_all_cash_offer_text(msg))


func test_earn_out_from_which_phrasing() -> void:
	var msg := "how about 16900 total, from which 15000 are upfront and 1900 on an earn out at 2 quarters"
	var parsed: Dictionary = Parser.parse_offer_amounts_from_text(msg, 17562)
	assert_eq(int(parsed.get("totalPrice", 0)), 16900)
	assert_eq(int(parsed.get("cashAtClosing", 0)), 15000)


func test_earn_out_offer_not_min_component() -> void:
	var built: Dictionary = Parser.build_player_offer_from_message(
		"all right, I can do 17000 total, but 14500 upfront and 2500 on an earn out to 2 quarters",
		{
			"intent": "offer",
			"offer": {"totalPrice": 2500, "cashAtClosing": 2500, "closingSpeed": "standard", "termsOffered": []},
		},
		{"context": {"price": 17562}, "counterparty": {}},
	)
	var offer: Dictionary = built.get("offer", {})
	assert_eq(int(offer.get("totalPrice", 0)), 17000)
	assert_eq(int(offer.get("cashAtClosing", 0)), 14500)


func test_built_offer_includes_retention_terms() -> void:
	var neg := {
		"context": {"price": 13750},
		"counterparty": {"archetypeId": "proud_founder"},
	}
	var built: Dictionary = Parser.build_player_offer_from_message(
		"13500 plus employee retention",
		{"intent": "offer", "offer": {"totalPrice": 13500, "cashAtClosing": 13500, "termsOffered": []}},
		neg,
	)
	var offer: Dictionary = built.get("offer", {})
	assert_eq(int(offer.get("totalPrice", 0)), 13500)
	assert_true(offer.get("termsOffered", []).has("employee retention"))
