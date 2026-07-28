class_name TurnPipeline
extends RefCounted

## Single entry point for turn advance. Phases (in order):
## 1. pre_checks — negotiation gate, supply shortage ack
## 2. pre_turn — rival uncontested resolution, urgent rep penalty
## 3. core_sim — TurnResolver (P&L, reval, synergies, debrief, milestones)
## 4. post_turn — opportunities, rivals, urgent gen, upgrade drift, stats
## 5. post_unlock — district auto-unlock (2D mode), parcel sync
##
## Returns { ok, state?, events?, error?, requires_supply_policy?, shortages? }
## `events` is an Array of { type, ...payload } for Game to emit on EventBus.

const PHASE_PRE_CHECKS := "pre_checks"
const PHASE_PRE_TURN := "pre_turn"
const PHASE_CORE_SIM := "core_sim"
const PHASE_POST_TURN := "post_turn"
const PHASE_POST_UNLOCK := "post_unlock"

const EVENT_TURN_DEBRIEF_READY := "turn_debrief_ready"
const EVENT_MILESTONE_REACHED := "milestone_reached"
const EVENT_EDGE_CHOICES_PENDING := "edge_choices_pending"
const EVENT_DISTRICTS_UNLOCKED := "districts_unlocked"
const EVENT_SUPPLY_SHORTAGE_DETECTED := "supply_shortage_detected"


static func advance_turn(state: RunState) -> Dictionary:
	var pre: Dictionary = _run_pre_checks(state)
	if not bool(pre.get("ok", false)):
		return pre

	var events: Array = []
	var milestones_before: int = state.milestones_hit.size()
	var edges_before: int = state.edge_choices_pending.size()

	_run_pre_turn(state)

	var resolver := TurnResolver.new()
	var next: RunState = resolver.advance_turn(state)

	_collect_core_events(next, events, milestones_before, edges_before)

	if next.game_over == null:
		_run_post_turn(next)
		_collect_post_unlock_events(next, events)

	next.supply_shortage_ack_turn = -1

	if next.is_capital_farm() and next.game_over == null:
		var post_shortages: Array = SynergySystem.detect_supply_shortages(next)
		if not post_shortages.is_empty():
			events.append({
				"type": EVENT_SUPPLY_SHORTAGE_DETECTED,
				"shortages": post_shortages,
			})

	return {"ok": true, "state": next, "events": events}


static func _run_pre_checks(state: RunState) -> Dictionary:
	if not state.negotiation.is_empty() and bool(state.negotiation.get("active", false)):
		return {"ok": false, "error": "Close the current negotiation before advancing turn"}

	if state.is_capital_farm():
		var shortages: Array = SynergySystem.detect_supply_shortages(state)
		if not shortages.is_empty() and state.supply_shortage_ack_turn != state.turn:
			return {
				"ok": false,
				"error": "Supply capacity shortage — set allocation policy before advancing",
				"requires_supply_policy": true,
				"shortages": shortages,
			}

	return {"ok": true}


static func _run_pre_turn(state: RunState) -> void:
	RivalSystem.resolve_uncontested_contests(state)
	if state.is_capital_farm():
		UrgentSystem.apply_unresolved_rep_penalty(state)


static func _collect_core_events(
	next: RunState,
	events: Array,
	milestones_before: int,
	edges_before: int,
) -> void:
	if not next.pending_turn_debrief.is_empty():
		events.append({
			"type": EVENT_TURN_DEBRIEF_READY,
			"debrief": next.pending_turn_debrief,
		})

	if next.milestones_hit.size() > milestones_before:
		var milestone_id: String = str(next.milestones_hit.back())
		events.append({
			"type": EVENT_MILESTONE_REACHED,
			"milestoneId": milestone_id,
			"stage": next.milestone_stage,
		})

	if next.edge_choices_pending.size() > edges_before:
		events.append({
			"type": EVENT_EDGE_CHOICES_PENDING,
			"choices": next.edge_choices_pending.duplicate(true),
		})


static func _run_post_turn(next: RunState) -> void:
	OpportunitySystem.advance_opportunities(next)
	RivalSystem.apply_contest_to_turn(next)
	if next.is_capital_farm():
		UrgentSystem.update_relationship_health(next)
		for neglect_note: Dictionary in SynergySystem.apply_neglect_pressure(next):
			next.run_log.append("%s: neglected %d turns — %s" % [
				str(neglect_note.get("name", "Business")),
				int(neglect_note.get("turns", 0)),
				str(neglect_note.get("label", "relationship health slipping")),
			])
		UpgradeSystem.apply_manager_passive_drift(next)
		next.urgent_problems = UrgentSystem.generate_urgent_problems(next)
	RunStatsSystem.snapshot_turn(next, next.last_advance_report)


static func _collect_post_unlock_events(next: RunState, events: Array) -> void:
	if not DistrictUnlockSystem.applies_to(next):
		return
	var newly: Array = DistrictUnlockSystem.refresh_auto_unlocks(next)
	if newly.is_empty():
		return
	OpportunitySystem.spawn_for_unlocked_districts(next, newly)
	ParcelOwnershipSystem.sync_from_state(next)
	events.append({
		"type": EVENT_DISTRICTS_UNLOCKED,
		"districtIds": newly,
	})
