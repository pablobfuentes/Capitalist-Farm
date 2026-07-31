# Community casual chat session lifecycle (8.3 Phase 3).
class_name CommunityChatRuntime
extends RefCounted

const _Provider := preload("res://core/community/ollama_npc_dialogue_provider.gd")


static func can_open_chat(state: RunState, business: Dictionary) -> Dictionary:
	if not CommunityFeatureFlags.is_enabled(CommunityFeatureFlags.FLAG_COMMUNITY_CHAT, state):
		return {"allowed": false, "message": AiClient.COMMUNITY_CHAT_DISABLED_NOTE}
	var gate := AiClient.community_chat_gate(state)
	if not bool(gate.get("allowed", false)):
		return gate
	var sale_state := str(business.get("saleState", "not_for_sale"))
	if sale_state == "under_negotiation":
		return {"allowed": false, "message": "This business is in active negotiation. Chat is unavailable."}
	if sale_state == "available":
		return {"allowed": false, "message": "This business is listed for sale — use Negotiate instead."}
	return {"allowed": true, "message": ""}


static func start_session(
	state: RunState,
	npc_id: String,
	business_id: String,
	parcel_id: String,
	district_id: String,
) -> Dictionary:
	CommunityState.ensure_initialized(state)
	var business: Dictionary = CommunityGenerator.get_business(state, business_id)
	if business.is_empty():
		return {"ok": false, "error": "Unknown business"}
	var allowed: Dictionary = can_open_chat(state, business)
	if not bool(allowed.get("allowed", false)):
		return {"ok": false, "error": str(allowed.get("message", "Chat unavailable"))}

	var sessions: Dictionary = state.community.get("activeChatSessions", {})
	if typeof(sessions) != TYPE_DICTIONARY:
		sessions = {}
	var seq := int(state.community.get(CommunityState.SESSION_COUNTER_KEY, 1))
	state.community[CommunityState.SESSION_COUNTER_KEY] = seq + 1
	var session_id := CommunityIds.conversation_session_id(district_id, npc_id, state.turn, seq)

	var session := {
		"sessionId": session_id,
		"npcId": npc_id,
		"businessId": business_id,
		"parcelId": parcel_id,
		"districtId": district_id,
		"mode": "casual",
		"status": "active",
		"playerMessagesSent": 0,
		"maxPlayerMessages": CommunityConfig.chat_max_player_messages(),
		"messages": [],
		"startedTurn": state.turn,
		"conversationSummary": "",
		"debugLog": [],
	}
	sessions[npc_id] = session
	state.community["activeChatSessions"] = sessions

	var npc: Dictionary = CommunityGenerator.get_npc(state, npc_id)
	var display := str(npc.get("displayName", "Neighbor"))
	var greeting := "%s looks up from the counter. \"Hey — I'm juggling a few things, but what's on your mind?\"" % display
	if not npc.is_empty():
		match str(npc.get("speciesId", "")):
			"sheep":
				greeting = "%s offers a small smile. \"Oh, hello — haven't seen you around today. What's going on?\"" % display
			"donkey":
				greeting = "%s nods once. \"If you've got a minute, I can talk — what did you want to know?\"" % display
			"hen":
				greeting = "%s clicks her pen. \"Quick visit? Alright — what can I help with?\"" % display
	_append_message(session, "npc", display, greeting)
	sessions[npc_id] = session
	state.community["activeChatSessions"] = sessions

	return {"ok": true, "session": session.duplicate(true)}


static func get_active_session(state: RunState, npc_id: String) -> Dictionary:
	CommunityState.ensure_initialized(state)
	var sessions: Dictionary = state.community.get("activeChatSessions", {})
	if sessions.has(npc_id):
		return (sessions[npc_id] as Dictionary).duplicate(true)
	return {}


static func send_player_message(state: RunState, npc_id: String, player_message: String, callback: Callable) -> void:
	var sessions: Dictionary = state.community.get("activeChatSessions", {})
	if not sessions.has(npc_id):
		callback.call({"ok": false, "error": "No active chat session"})
		return
	var session: Dictionary = sessions[npc_id]
	if str(session.get("status", "")) != "active":
		callback.call({"ok": false, "error": "Chat session ended"})
		return
	if int(session.get("playerMessagesSent", 0)) >= int(session.get("maxPlayerMessages", 5)):
		_dismiss_session(state, npc_id, "You've taken enough of my time for today.")
		callback.call({"ok": false, "error": "Message limit reached", "dismissed": true})
		return

	var trimmed := player_message.strip_edges()
	if trimmed.is_empty():
		callback.call({"ok": false, "error": "Empty message"})
		return

	_append_message(session, "player", "You", trimmed)
	session["playerMessagesSent"] = int(session.get("playerMessagesSent", 0)) + 1
	sessions[npc_id] = session
	state.community["activeChatSessions"] = sessions

	var context := CommunityContextBuilder.build(state, session, trimmed)
	var request := CommunityChatPrompt.build_request(state, context, trimmed)
	request["context"] = context
	request["requestId"] = str(session.get("sessionId", ""))

	var provider := _Provider.new()
	AiClient.request_community_chat(request, func(raw: Dictionary, err: String) -> void:
		var live_sessions: Dictionary = state.community.get("activeChatSessions", {})
		if not live_sessions.has(npc_id):
			callback.call({"ok": false, "error": "Chat session ended"})
			return
		session = live_sessions[npc_id]

		if not err.is_empty():
			_append_debug(session, {"error": err})
			callback.call(_apply_fallback_reply(state, npc_id, session, err, trimmed))
			return

		var validation_context := {
			"allowedFactIds": context.get("allowedFactIds", []),
			"allowedPromiseTypes": context.get("allowedPromiseTypes", []),
			"allowedEntityIds": context.get("allowedEntityIds", []),
		}
		var parsed: Dictionary = _Provider.parse_and_validate(raw, validation_context)
		var validated: Dictionary = parsed.get("validated", {})
		if not bool(parsed.get("ok", false)):
			_append_debug(session, {"validationErrors": parsed.get("errors", [])})
			validated = _coerce_dialogue_only_validated(raw, validated)
			if str(validated.get("dialogue", "")).strip_edges().is_empty():
				callback.call(_apply_fallback_reply(
					state,
					npc_id,
					session,
					"AI response failed validation",
					trimmed,
				))
				return

		callback.call(process_validated_turn(state, npc_id, session, validated, validation_context))
	)


static func process_validated_turn(
	state: RunState,
	npc_id: String,
	session: Dictionary,
	validated: Dictionary,
	validation_context: Dictionary = {},
) -> Dictionary:
	var npc: Dictionary = CommunityGenerator.get_npc(state, npc_id)
	var dialogue := str(validated.get("dialogue", "")).strip_edges()
	if dialogue.is_empty():
		dialogue = "..."

	_append_message(session, "npc", str(npc.get("displayName", "NPC")), dialogue)

	var social_effects: Dictionary = CommunitySocialRules.apply_validated_turn(state, npc_id, validated, {
		"firstTimeGift": _is_first_gift(session, validated),
	})

	var discoveries: Array = []
	for disclosure_variant in validated.get("fact_disclosures", []):
		if typeof(disclosure_variant) != TYPE_DICTIONARY:
			continue
		var disclosure: Dictionary = disclosure_variant
		var result: Dictionary = CommunityKnowledgeService.disclose_fact_to_player(
			state,
			npc_id,
			str(disclosure.get("fact_id", "")),
			str(disclosure.get("mode", "direct")),
			str(disclosure.get("confidence_language", "likely")),
		)
		if bool(result.get("ok", false)):
			discoveries.append(result)

	var promise_record: Dictionary = {}
	var proposal: Variant = validated.get("promise_proposal", null)
	if proposal is Dictionary and not (proposal as Dictionary).is_empty():
		promise_record = CommunityPromiseService.record_from_chat_proposal(
			state,
			npc_id,
			proposal as Dictionary,
			session,
		)

	CommunityInteractionLedger.append_event(state, {
		"eventType": str(validated.get("social_action", "none")),
		"npcId": npc_id,
		"businessId": str(session.get("businessId", "")),
		"conversationSessionId": str(session.get("sessionId", "")),
		"payload": {
			"tone": validated.get("tone", "neutral"),
			"validated": validated,
		},
		"effects": social_effects,
		"summary": dialogue.substr(0, 120),
	})

	_append_debug(session, {
		"socialEffects": social_effects,
		"discoveries": discoveries.size(),
		"validationContext": validation_context,
	})

	var dismissed := false
	var dismiss_line := ""
	if int(session.get("playerMessagesSent", 0)) >= int(session.get("maxPlayerMessages", 5)):
		dismissed = true
		dismiss_line = "I need to get back to work. We'll talk another time."
		_dismiss_session(state, npc_id, dismiss_line, session)

	var sessions: Dictionary = state.community.get("activeChatSessions", {})
	sessions[npc_id] = session
	state.community["activeChatSessions"] = sessions

	return {
		"ok": true,
		"session": session.duplicate(true),
		"dialogue": dialogue,
		"socialEffects": social_effects,
		"discoveries": discoveries,
		"promise": promise_record,
		"dismissed": dismissed,
		"dismissLine": dismiss_line,
	}


static func end_session(state: RunState, npc_id: String) -> void:
	var sessions: Dictionary = state.community.get("activeChatSessions", {})
	if sessions.has(npc_id):
		var session: Dictionary = sessions[npc_id]
		session["status"] = "closed"
		sessions[npc_id] = session
		state.community["activeChatSessions"] = sessions


static func _dismiss_session(state: RunState, npc_id: String, line: String, session: Dictionary = {}) -> void:
	var sessions: Dictionary = state.community.get("activeChatSessions", {})
	if session.is_empty() and sessions.has(npc_id):
		session = sessions[npc_id]
	if session.is_empty():
		return
	session["status"] = "dismissed"
	if not line.is_empty():
		var npc: Dictionary = CommunityGenerator.get_npc(state, npc_id)
		_append_message(session, "system", "System", line)
	sessions[npc_id] = session
	state.community["activeChatSessions"] = sessions
	CommunityInteractionLedger.save_conversation_summary(
		state,
		str(session.get("sessionId", "")),
		_summarize_session(session),
	)


static func _append_message(session: Dictionary, role: String, speaker: String, text: String) -> void:
	var messages: Array = session.get("messages", [])
	messages.append({"role": role, "speaker": speaker, "text": text})
	session["messages"] = messages


static func _append_debug(session: Dictionary, entry: Dictionary) -> void:
	var log: Array = session.get("debugLog", [])
	log.append(entry)
	session["debugLog"] = log


static func _is_first_gift(session: Dictionary, validated: Dictionary) -> bool:
	if str(validated.get("social_action", "")) != "gift_offer":
		return false
	var gift: Variant = validated.get("gift", null)
	if typeof(gift) != TYPE_DICTIONARY:
		return false
	var concept := str((gift as Dictionary).get("concept", "")).strip_edges().to_lower()
	if concept.is_empty():
		return true
	for msg_variant in session.get("messages", []):
		if typeof(msg_variant) != TYPE_DICTIONARY:
			continue
		var msg: Dictionary = msg_variant
		if str(msg.get("role", "")) == "player" and concept in str(msg.get("text", "")).to_lower():
			return false
	return true


static func _coerce_dialogue_only_validated(raw: Dictionary, validated: Dictionary) -> Dictionary:
	var dialogue := str(validated.get("dialogue", "")).strip_edges()
	if dialogue.is_empty():
		dialogue = str(raw.get("dialogue", "")).strip_edges()
	if dialogue.is_empty():
		return {}
	var safe := NpcDialogueSchema.empty_response()
	safe["dialogue"] = dialogue
	var tone := str(raw.get("tone", validated.get("tone", "neutral")))
	if tone in NpcDialogueSchema.TONES:
		safe["tone"] = tone
	var social_action := str(raw.get("social_action", validated.get("social_action", "none")))
	if social_action in NpcDialogueSchema.SOCIAL_ACTIONS:
		safe["social_action"] = social_action
	return safe


static func _apply_fallback_reply(
	state: RunState,
	npc_id: String,
	session: Dictionary,
	reason: String,
	player_message: String = "",
) -> Dictionary:
	var npc: Dictionary = CommunityGenerator.get_npc(state, npc_id)
	var dialogue := _casual_fallback_line(npc, player_message)
	var validated := NpcDialogueSchema.empty_response()
	validated["dialogue"] = dialogue
	var outcome := process_validated_turn(state, npc_id, session, validated, {})
	outcome["fallback"] = true
	outcome["error"] = reason
	return outcome


static func _casual_fallback_line(npc: Dictionary, player_message: String) -> String:
	var name := str(npc.get("displayName", "They"))
	var lowered := player_message.strip_edges().to_lower()
	if lowered.is_empty():
		return "%s nods. \"What's on your mind?\"" % name
	if "supplier" in lowered or "supply" in lowered or "feed" in lowered or "poultry" in lowered:
		return "%s exhales. \"Supply's been uneven for everyone lately — I've had my headaches too, but I'd rather not name names on a quick porch visit.\"" % name
	if "?" in player_message:
		return "%s thinks for a moment. \"That's a fair question. I don't have a clean answer for you right now — maybe catch me when I'm not buried in orders.\"" % name
	return "%s listens. \"I hear you. I'm short on time today, but we can talk more another visit.\"" % name


static func _summarize_session(session: Dictionary) -> String:
	var parts: PackedStringArray = []
	for msg_variant in session.get("messages", []):
		if typeof(msg_variant) != TYPE_DICTIONARY:
			continue
		var msg: Dictionary = msg_variant
		if str(msg.get("role", "")) == "system":
			continue
		parts.append("%s: %s" % [str(msg.get("speaker", "")), str(msg.get("text", ""))])
	return "\n".join(parts)
