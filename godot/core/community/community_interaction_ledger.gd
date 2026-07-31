# Append-only interaction events and conversation summaries (Community spec §6, §10).
class_name CommunityInteractionLedger
extends RefCounted


static func append_event(state: RunState, draft: Dictionary) -> Dictionary:
	CommunityState.ensure_initialized(state)
	var events: Array = state.community.get("interactionEvents", [])
	if typeof(events) != TYPE_ARRAY:
		events = []

	var event := draft.duplicate(true)
	if not event.has("id"):
		event["id"] = CommunityState.next_event_id(state)
	if not event.has("turn"):
		event["turn"] = state.turn
	if not event.has("summary"):
		event["summary"] = str(event.get("eventType", "interaction"))

	events.append(event)
	state.community["interactionEvents"] = events
	return event.duplicate(true)


static func recent_events_for_npc(state: RunState, npc_id: String, limit: int = 10) -> Array:
	CommunityState.ensure_initialized(state)
	var events: Array = state.community.get("interactionEvents", [])
	var filtered: Array = []
	for i in range(events.size() - 1, -1, -1):
		var event_variant = events[i]
		if typeof(event_variant) != TYPE_DICTIONARY:
			continue
		var event: Dictionary = event_variant
		if str(event.get("npcId", "")) != npc_id:
			continue
		filtered.append(event.duplicate(true))
		if filtered.size() >= limit:
			break
	return filtered


static func save_conversation_summary(
	state: RunState,
	session_id: String,
	summary_text: String,
	important_event_ids: Array = [],
) -> Dictionary:
	CommunityState.ensure_initialized(state)
	var summaries: Dictionary = state.community.get("conversationSummaries", {})
	if typeof(summaries) != TYPE_DICTIONARY:
		summaries = {}
	var record := {
		"sessionId": session_id,
		"summaryVersion": 1,
		"summaryText": summary_text.strip_edges(),
		"importantEventIds": important_event_ids.duplicate(true),
		"updatedTurn": state.turn,
	}
	summaries[session_id] = record
	state.community["conversationSummaries"] = summaries
	return record.duplicate(true)


static func get_conversation_summary(state: RunState, session_id: String) -> Dictionary:
	CommunityState.ensure_initialized(state)
	var summaries: Dictionary = state.community.get("conversationSummaries", {})
	if summaries.has(session_id):
		return (summaries[session_id] as Dictionary).duplicate(true)
	return {}
