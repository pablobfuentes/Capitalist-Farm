class_name RunBootstrap
extends RefCounted

const _Debrief := preload("res://core/systems/debrief_system.gd")

const _SECTOR_KEYS: Array[String] = [
	"technology", "consumer", "energy", "finance", "healthcare", "small_cap", "bonds", "broad",
]


static func prepare_new_run(state: RunState) -> void:
	if state == null:
		return
	var rng := SeededRng.new()
	rng.set_rng_seed(state.run_seed)
	var wildcard_pool: Array = MarketSystem.WILDCARD_EVENTS
	if not wildcard_pool.is_empty():
		state.wildcard_event = (wildcard_pool[rng.randi_range(0, wildcard_pool.size() - 1)] as Dictionary).duplicate(true)
	if state.market_state.is_empty():
		state.market_state = RunBootstrap.default_market_state()
	elif not state.market_state.has("sectorMomentum") or (state.market_state.get("sectorMomentum", {}) as Dictionary).is_empty():
		state.market_state["sectorMomentum"] = RunBootstrap._default_sector_momentum()
	SecuritySystem.init_run(state)
	RunStatsSystem.ensure(state)
	RunStatsSystem.record_baseline(state)
	state.period_snapshot = _Debrief.snapshot_period_state(state)
	state.pending_turn_debrief = {}
	state.debrief_expanded = false


static func default_market_state() -> Dictionary:
	return {
		"interestRates": "stable",
		"creditAvailability": "normal",
		"consumerDemand": "stable",
		"businessConfidence": "neutral",
		"inflation": "moderate",
		"sectorMomentum": _default_sector_momentum(),
	}


static func _default_market_state() -> Dictionary:
	return default_market_state()


static func _default_sector_momentum() -> Dictionary:
	var out: Dictionary = {}
	for sector: String in _SECTOR_KEYS:
		out[sector] = "neutral"
	return out
