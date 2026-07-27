extends GutTest

const V2 := preload("res://core/systems/negotiation_v2_engine.gd")
const V2Data := preload("res://core/systems/negotiation_v2_data.gd")
const V2Val := preload("res://core/systems/negotiation_v2_valuator.gd")
const Parser := preload("res://core/systems/negotiation_offer_parser.gd")


func test_profile_generates_bounded_discount_lanes() -> void:
	var cp := {
		"speciesId": "horse",
		"businessSituation": "retirement_transition",
		"leverageScore": 0.5,
		"relationshipMemory": {"trust": 0.5, "promisesKept": 0, "promisesBroken": 0, "grievances": []},
	}
	var state := RunState.create_new(GameMode.MODE_CAPITAL_FARM)
	var profile: Dictionary = V2.initialize_profile(100000, cp, state, {}, 4242)
	assert_eq(int(profile.get("askPrice", 0)), 100000)
	assert_gt(int(profile.get("hardFloor", 0)), 0)
	assert_gt(float(profile.get("speciesCapacity", 0.0)), 0.0)
	assert_gt(float(profile.get("situationCapacity", 0.0)), 0.0)
	assert_gte(int(profile.get("gaugeStart", 0)), 0)


func test_fresh_negotiation_starts_gauge_at_center() -> void:
	const V2Profile := preload("res://core/systems/negotiation_v2_profile.gd")
	var cp := {
		"speciesId": "hen",
		"businessSituation": "stable_position",
		"leverageScore": 0.5,
		"trust": 0.4,
		"relationshipMemory": {"trust": 0.4, "promisesKept": 0, "promisesBroken": 0, "grievances": []},
	}
	var state := RunState.create_new(GameMode.MODE_CAPITAL_FARM)
	state.reputation = 12
	var rng := SeededRng.new(99)
	var profile: Dictionary = V2Profile.build(50000, cp, state, {}, rng)
	assert_eq(int(profile.get("gaugeStart", -1)), 50)
	assert_eq(int(profile.get("gauge", -1)), 50)


func test_reputation_tier_shifts_starting_gauge() -> void:
	const V2Profile := preload("res://core/systems/negotiation_v2_profile.gd")
	var cp := {
		"speciesId": "hen",
		"businessSituation": "stable_position",
		"leverageScore": 0.5,
		"relationshipMemory": {},
	}
	var state := RunState.create_new(GameMode.MODE_CAPITAL_FARM)
	state.reputation = 40
	var rng := SeededRng.new(99)
	var profile: Dictionary = V2Profile.build(50000, cp, state, {}, rng)
	assert_eq(int(profile.get("gaugeStart", -1)), 54)


func test_employee_retention_adds_offer_value() -> void:
	var profile := {
		"askPrice": 13750,
		"speciesId": "horse",
		"situationId": "retirement_transition",
	}
	var offer := Parser.enrich_offer_from_message(
		{"totalPrice": 13500, "cashAtClosing": 13500, "termsOffered": [], "closingSpeed": "standard"},
		"13500 plus employee retention",
		{},
	)
	var bare: Dictionary = V2Val.value_offer(
		{"totalPrice": 13500, "cashAtClosing": 13500, "termsOffered": [], "closingSpeed": "standard"},
		profile,
		{},
	)
	var with_terms: Dictionary = V2Val.value_offer(offer, profile, {}, "13500 plus employee retention")
	assert_gt(int(with_terms.get("offerValue", 0)), int(bare.get("offerValue", 0)))


func test_sheep_entrepreneur_opens_with_meaningful_discount() -> void:
	var cp := {
		"speciesId": "sheep",
		"businessSituation": "entrepreneur_growth",
		"leverageScore": 0.5,
		"relationshipMemory": {},
	}
	var state := RunState.create_new(GameMode.MODE_CAPITAL_FARM)
	var profile: Dictionary = V2.initialize_profile(21145, cp, state, {}, 4242)
	var discount: float = float(profile.get("unlockedDiscount", 0.0))
	var acceptable: int = int(profile.get("acceptableValue", 21145))
	assert_gte(discount, 0.08, "Sheep + entrepreneur should open with ~8%+ discount headroom")
	assert_lt(acceptable, int(round(21145 * 0.92)))


func test_sheep_pitch_unlocks_more_discount() -> void:
	var cp := {
		"speciesId": "sheep",
		"businessSituation": "entrepreneur_growth",
		"leverageScore": 0.5,
		"relationshipMemory": {},
	}
	var state := RunState.create_new(GameMode.MODE_CAPITAL_FARM)
	var profile: Dictionary = V2.initialize_profile(21145, cp, state, {}, 4242)
	var before: int = int(profile.get("acceptableValue", 21145))
	var msg := "We are part of mega retail BnL expanding territory — you can be the face of the chain and grow with us."
	var offer := {"totalPrice": 19000, "cashAtClosing": 19000, "termsOffered": [], "closingSpeed": "standard"}
	var result: Dictionary = V2.process_turn(profile, msg, offer, {}, false, 1, 6)
	var after: int = int(result.get("profile", {}).get("acceptableValue", before))
	assert_lt(after, before)


func test_first_species_aligned_message_grants_progress_floor() -> void:
	var cp := {
		"speciesId": "hen",
		"businessSituation": "stable_position",
		"leverageScore": 0.5,
		"relationshipMemory": {},
	}
	var state := RunState.create_new(GameMode.MODE_CAPITAL_FARM)
	var profile: Dictionary = V2.initialize_profile(15437, cp, state, {}, 777)
	var offer := {"totalPrice": 14100, "cashAtClosing": 14100, "termsOffered": [], "closingSpeed": "standard"}
	var msg := "We reviewed the records — all cash at closing within 48 hours and a written guarantee after inspection."
	var result: Dictionary = V2.process_turn(profile, msg, offer, {}, false, 1, 6)
	assert_gte(float(result.get("profile", {}).get("speciesProgress", 0.0)), V2Data.FIRST_SPECIES_PROGRESS_FLOOR)


func test_two_gates_required_for_ready() -> void:
	var cp := {
		"speciesId": "horse",
		"businessSituation": "retirement_transition",
		"leverageScore": 0.5,
		"relationshipMemory": {"trust": 0.6, "promisesKept": 1, "promisesBroken": 0, "grievances": []},
	}
	var state := RunState.create_new(GameMode.MODE_CAPITAL_FARM)
	state.reputation = 40
	var profile: Dictionary = V2.initialize_profile(13750, cp, state, {}, 999)
	profile["speciesProgress"] = 80.0
	profile["situationProgress"] = 70.0
	profile = preload("res://core/systems/negotiation_v2_profile.gd").recalculate_economics(profile)

	var offer := Parser.enrich_offer_from_message(
		{"totalPrice": 13750, "cashAtClosing": 13750, "termsOffered": [], "closingSpeed": "standard"},
		"13750 all cash",
		{},
	)
	# Strong economics but gauge still in Listening zone — should not be ready.
	profile["gauge"] = 52
	profile["gaugeStart"] = 52
	var r1: Dictionary = V2.process_turn(profile, "13750 all cash", offer, {}, false, 1, 5)
	if int(r1.get("gauge", 0)) < V2Data.GAUGE_READY:
		assert_false(bool(r1.get("readyToClose", false)))
		assert_true(bool(r1.get("economicGateMet", false)))

	var rapport_offer := offer
	var r2: Dictionary = V2.process_turn(
		r1.get("profile", profile),
		"I respect what you built and will keep your employees — 13500 plus employee retention",
		Parser.enrich_offer_from_message(
			{"totalPrice": 13500, "cashAtClosing": 13500, "termsOffered": [], "closingSpeed": "standard"},
			"13500 plus employee retention",
			{},
		),
		{},
		false,
		2,
		5,
	)
	assert_gt(int(r2.get("gauge", 0)), int(r1.get("gauge", 0)))


func test_severe_lowball_flags_and_moves_gauge_down() -> void:
	var cp := {"speciesId": "donkey", "businessSituation": "stable_position", "leverageScore": 0.5, "relationshipMemory": {}}
	var state := RunState.create_new(GameMode.MODE_CAPITAL_FARM)
	var profile: Dictionary = V2.initialize_profile(100000, cp, state, {}, 123)
	var offer := {"totalPrice": 70000, "cashAtClosing": 70000, "termsOffered": [], "closingSpeed": "standard"}
	var result: Dictionary = V2.process_turn(profile, "70000", offer, {}, false, 1, 5)
	assert_gt(int(result.get("profile", {}).get("severeLowballs", 0)), 0)
	assert_lt(int(result.get("gauge", 100)), int(profile.get("gaugeStart", 50)))
