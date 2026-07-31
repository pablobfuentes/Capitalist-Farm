# Ollama-backed NPC dialogue provider (wraps AiClient — Phase 0 gate + contract).
class_name OllamaNpcDialogueProvider
extends NpcDialogueProvider


func generate_turn(request: Dictionary) -> Dictionary:
	var gate := AiClient.community_chat_gate()
	if not bool(gate.get("allowed", false)):
		return {
			"ok": false,
			"error": str(gate.get("message", "Community chat unavailable")),
			"raw": {},
			"validated": {},
			"gate": gate,
		}

	var context: Dictionary = request.get("context", {})
	if typeof(context) != TYPE_DICTIONARY:
		context = {}

	# HTTP inference is handled by AiClient.request_community_chat (CommunityChatRuntime).
	return {
		"ok": false,
		"error": "Use CommunityChatRuntime.send_player_message — direct provider calls are not supported",
		"raw": {},
		"validated": {},
		"gate": gate,
		"requestId": str(request.get("requestId", "")),
		"contextManifest": {
			"npcId": str(context.get("npcId", "")),
			"schemaVersion": CommunityConfig.dialogue_schema_version(),
		},
	}


static func parse_and_validate(raw: Variant, context: Dictionary = {}) -> Dictionary:
	var validation := NpcDialogueValidator.validate(raw, context)
	return {
		"ok": bool(validation.get("ok", false)),
		"validated": validation.get("normalized", {}),
		"errors": validation.get("errors", []),
		"warnings": validation.get("warnings", []),
	}
