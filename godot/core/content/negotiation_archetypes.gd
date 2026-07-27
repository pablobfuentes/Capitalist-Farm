# Negotiation archetypes — core layer (no autoload dependency).
class_name NegotiationArchetypes
extends RefCounted

const ARCHETYPES_PATH := "res://data/negotiation/archetypes.json"

static var _loaded: bool = false
static var _archetypes_by_id: Dictionary = {}
static var _species_data: Dictionary = {}


static func ensure_loaded() -> void:
	if _loaded:
		return
	_archetypes_by_id.clear()
	_species_data.clear()
	var file := FileAccess.open(ARCHETYPES_PATH, FileAccess.READ)
	if file == null:
		push_error("NegotiationArchetypes: missing %s" % ARCHETYPES_PATH)
		_loaded = true
		return
	var root: Variant = JSON.parse_string(file.get_as_text())
	if typeof(root) == TYPE_DICTIONARY:
		for raw_variant in root.get("archetypes", []):
			if typeof(raw_variant) != TYPE_DICTIONARY:
				continue
			var raw: Dictionary = raw_variant
			_archetypes_by_id[str(raw.get("id", ""))] = raw
		_species_data = root.get("species", {})
	_loaded = true


static func pick_archetype(rng: SeededRng) -> Dictionary:
	ensure_loaded()
	var ids: Array = _archetypes_by_id.keys()
	if ids.is_empty():
		return _fallback_archetype()
	return _archetypes_by_id[ids[rng.randi_range(0, ids.size() - 1)]].duplicate()


static func pick_archetype_id_for_level(level: int, rng: SeededRng) -> String:
	ensure_loaded()
	var pool: Array = LEVEL_ARCHETYPE_POOLS.get(level, LEVEL_ARCHETYPE_POOLS.get(1, []))
	var candidates: Array[String] = []
	for arch_id_variant in pool:
		var arch_id: String = str(arch_id_variant)
		if _archetypes_by_id.has(arch_id):
			candidates.append(arch_id)
	if candidates.is_empty():
		return str(pick_archetype(rng).get("id", "desperate_seller"))
	return candidates[rng.randi_range(0, candidates.size() - 1)]


const LEVEL_ARCHETYPE_POOLS: Dictionary = {
	1: ["desperate_seller", "proud_founder", "proud_founder", "relationship_owner"],
	2: ["skeptical_buyer", "meticulous_investor", "relationship_owner"],
	3: ["meticulous_investor", "aggressive_banker", "corporate_seller", "corporate_seller"],
}


static func get_archetype(archetype_id: String) -> Dictionary:
	ensure_loaded()
	return _archetypes_by_id.get(archetype_id, _fallback_archetype())


static func build_counterparty(archetype_id: String, asking_price: int, rng: SeededRng) -> Dictionary:
	ensure_loaded()
	var arch: Dictionary = get_archetype(archetype_id)
	var reservation: int = int(round(float(asking_price) * rng.randf_range(0.85, 0.95)))
	var red_line: int = int(round(float(asking_price) * rng.randf_range(0.72, 0.82)))
	return {
		"archetypeId": str(arch.get("id", "desperate_seller")),
		"role": "seller",
		"reservationPrice": reservation,
		"redLine": red_line,
		"urgency": float(arch.get("urgency", 0.5)),
		"trust": float(arch.get("trust", 0.5)),
		"riskTolerance": float(arch.get("risk_tolerance", 0.3)),
		"concessionStyle": str(arch.get("concession_style", "medium")),
		"preferredTerms": arch.get("responds_to", []),
		"primaryMotivator": str(arch.get("primary_motivator", "greed")),
		"speciesId": _pick_species(rng),
	}


static func _pick_species(rng: SeededRng) -> String:
	var pool: Array[String] = ["hen", "horse", "pig", "donkey", "goat", "sheep"]
	return pool[rng.randi_range(0, pool.size() - 1)]


static func _fallback_archetype() -> Dictionary:
	return {
		"id": "desperate_seller",
		"name": "Desperate Seller",
		"urgency": 0.8,
		"trust": 0.4,
		"risk_tolerance": 0.3,
		"responds_to": ["fast closing", "simple terms"],
		"flavor": "anxious to close quickly",
	}
