# Negotiation archetypes autoload — delegates to core NegotiationArchetypes.
extends Node


func _ready() -> void:
	NegotiationArchetypes.ensure_loaded()


func pick_archetype(rng: SeededRng) -> Dictionary:
	return NegotiationArchetypes.pick_archetype(rng)


func get_archetype(archetype_id: String) -> Dictionary:
	return NegotiationArchetypes.get_archetype(archetype_id)


func build_counterparty(archetype_id: String, asking_price: int, rng: SeededRng) -> Dictionary:
	return NegotiationArchetypes.build_counterparty(archetype_id, asking_price, rng)
