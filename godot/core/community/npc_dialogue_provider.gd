# Provider boundary for NPC community dialogue (Community spec §11.5).
class_name NpcDialogueProvider
extends RefCounted

const _Validator := preload("res://core/community/npc_dialogue_validator.gd")


func generate_turn(request: Dictionary) -> Dictionary:
	push_error("NpcDialogueProvider.generate_turn must be overridden")
	return {"ok": false, "error": "not_implemented", "raw": {}, "validated": {}}


func validate_response(raw: Variant, context: Dictionary = {}) -> Dictionary:
	return _Validator.validate(raw, context)
