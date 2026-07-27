# Negotiation Mechanics v2 — deterministic turn processor (two-gate model).
class_name NegotiationV2Engine
extends RefCounted

const _Data := preload("res://core/systems/negotiation_v2_data.gd")
const _Profile := preload("res://core/systems/negotiation_v2_profile.gd")
const _Tactics := preload("res://core/systems/negotiation_v2_tactics.gd")
const _Valuator := preload("res://core/systems/negotiation_v2_valuator.gd")


static func initialize_profile(
	ask_price: int,
	counterparty: Dictionary,
	state: RunState,
	opp: Dictionary,
	seed_salt: int,
) -> Dictionary:
	var rng := SeededRng.new(seed_salt)
	var profile: Dictionary = _Profile.build(ask_price, counterparty, state, opp, rng)
	return _Profile.recalculate_economics(profile)


static func profile_seed(state: RunState, ask_price: int, opportunity_id: String = "") -> int:
	var salt := str(opportunity_id).hash() if not opportunity_id.is_empty() else 0
	return state.run_seed + ask_price * 17 + salt


static func process_turn(
	profile: Dictionary,
	text: String,
	offer: Dictionary,
	ai_parsed: Dictionary,
	diligence_done: bool,
	round_num: int,
	max_rounds: int,
) -> Dictionary:
	profile = profile.duplicate(true)
	profile["previousGauge"] = int(profile.get("gauge", 0))

	var classified: Dictionary = _Tactics.classify(text, ai_parsed, diligence_done)
	var intent: String = str(classified.get("intent", "question"))
	var tags: Array = classified.get("tags", [])
	var species_id: String = str(profile.get("speciesId", "hen"))
	var situation_id: String = str(profile.get("situationId", "stable_position"))

	var sp_delta: float = _Tactics.species_progress_delta(species_id, tags, profile.get("tacticHistory", []))
	var sit_delta: float = _Tactics.situation_progress_delta(situation_id, tags, profile.get("tacticHistory", []))
	if tags.has("lowball"):
		sp_delta = minf(sp_delta, -10.0)
		sit_delta = minf(sit_delta, -10.0)

	var prev_sp: float = float(profile.get("speciesProgress", 0.0))
	var prev_sit: float = float(profile.get("situationProgress", 0.0))

	profile["speciesProgress"] = clampf(prev_sp + sp_delta, 0.0, 100.0)
	profile["situationProgress"] = clampf(prev_sit + sit_delta, 0.0, 100.0)

	if _Data.species_tag_hit(species_id, tags) and prev_sp < 1.0:
		profile["speciesProgress"] = maxf(float(profile.get("speciesProgress", 0.0)), _Data.FIRST_SPECIES_PROGRESS_FLOOR)
	if _Data.situation_tag_hit(situation_id, tags) and prev_sit < 1.0:
		profile["situationProgress"] = maxf(float(profile.get("situationProgress", 0.0)), _Data.FIRST_SITUATION_PROGRESS_FLOOR)

	profile = _Profile.recalculate_economics(profile)

	var conv_delta: int = _Tactics.conversation_gauge_delta(tags)
	if intent == "discovery":
		conv_delta += 4

	var offer_value := 0
	var offer_movement := 0
	var acceptable: int = int(profile.get("acceptableValue", 0))
	var hard_floor: int = int(profile.get("hardFloor", 0))
	var ask: int = int(profile.get("askPrice", 0))

	if not offer.is_empty() and int(offer.get("totalPrice", 0)) > 0:
		var valued: Dictionary = _Valuator.value_offer(offer, profile, {}, text)
		offer_value = int(valued.get("offerValue", 0))
		profile["lastOfferValue"] = offer_value
		offer_movement = _Valuator.offer_quality_gauge_delta(offer_value, acceptable, ask)

		if _Valuator.is_severe_lowball(offer_value, hard_floor):
			if not tags.has("lowball"):
				tags.append("lowball")
			profile["severeLowballs"] = int(profile.get("severeLowballs", 0)) + 1

	if tags.has("contradiction") or tags.has("unsupported_claim"):
		conv_delta -= 12
		profile["credibilityFailed"] = true

	var running: int = int(profile.get("gauge", int(profile.get("gaugeStart", _Data.GAUGE_BASE))))
	var gauge_delta: int = conv_delta + offer_movement
	running = clampi(running + gauge_delta, 0, 100)
	profile["gauge"] = running
	profile["gaugeDelta"] = gauge_delta
	profile["conversationMovement"] = conv_delta
	profile["offerMovement"] = offer_movement

	var history: Array = profile.get("tacticHistory", [])
	if not tags.is_empty():
		history.append(str(tags[0]))
		if history.size() > 12:
			history = history.slice(history.size() - 12)
	profile["tacticHistory"] = history

	var economic_met := offer_value > 0 and offer_value >= acceptable
	var willingness_met := running >= _Data.GAUGE_READY
	var zone: Dictionary = _Data.gauge_zone(running)

	var decision := "continue"
	var ready_to_close := false
	var status_hint := _Valuator.economic_status_hint(offer_value, acceptable, running, false)

	if bool(profile.get("redLineViolated", false)) or (running <= _Data.GAUGE_COLLAPSE and round_num > 1):
		decision = "reject"
	elif bool(profile.get("credibilityFailed", false)) and int(profile.get("severeLowballs", 0)) >= 2:
		decision = "reject"
	elif int(profile.get("severeLowballs", 0)) >= 2 and species_id != "goat" and situation_id != "cash_pressure":
		decision = "reject"
	elif round_num >= max_rounds and not economic_met and running < _Data.GAUGE_PATIENCE_FLOOR:
		decision = "reject"
	elif economic_met and willingness_met and not bool(profile.get("redLineViolated", false)):
		decision = "ready"
		ready_to_close = true
		status_hint = "Ready to Close"
	elif not offer.is_empty() and int(offer.get("totalPrice", 0)) > 0:
		decision = "counter"
	elif intent == "question" or intent == "discovery":
		decision = "continue"

	if economic_met and not willingness_met:
		status_hint = "Terms acceptable; confidence still needed"

	return {
		"profile": profile,
		"intent": intent,
		"tags": tags,
		"decision": decision,
		"readyToClose": ready_to_close,
		"economicGateMet": economic_met,
		"willingnessGateMet": willingness_met,
		"offerValue": offer_value,
		"acceptableValue": acceptable,
		"gauge": running,
		"gaugeDelta": gauge_delta,
		"gaugeZone": zone,
		"statusHint": status_hint,
	}


static func build_counter_total(profile: Dictionary, player_offer: Dictionary) -> int:
	var acceptable: int = int(profile.get("acceptableValue", 0))
	var ask: int = int(profile.get("askPrice", 0))
	if player_offer.is_empty():
		return acceptable if acceptable > 0 else ask
	var player_total: int = int(player_offer.get("totalPrice", 0))
	if player_total >= acceptable:
		return player_total
	return clampi(int(round(float(acceptable) / 50.0) * 50.0), int(profile.get("hardFloor", 0)), ask)


static func gauge_display(profile: Dictionary) -> Dictionary:
	var gauge: int = int(profile.get("gauge", 0))
	var zone: Dictionary = _Data.gauge_zone(gauge)
	var delta: int = int(profile.get("gaugeDelta", 0))
	var arrow := "→"
	if delta > 2:
		arrow = "↑"
	elif delta < -2:
		arrow = "↓"
	return {
		"gauge": gauge,
		"zoneId": str(zone.get("id", "")),
		"zoneLabel": str(zone.get("label", "")),
		"zoneHint": str(zone.get("hint", "")),
		"arrow": arrow,
	}
