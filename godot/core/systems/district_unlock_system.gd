class_name DistrictUnlockSystem
extends RefCounted

const _World := preload("res://scenes/farm_map/world_layout_data.gd")

const STARTER_DISTRICT := "meadowgate_commons"


static func applies_to(state: RunState) -> bool:
	return state != null and GameMode.is_2d_run(state.mode)


static func ensure_initialized(state: RunState) -> void:
	if not applies_to(state):
		return
	if state.unlocked_districts.is_empty():
		state.unlocked_districts = [STARTER_DISTRICT]


static func is_unlocked(state: RunState, district_id: String) -> bool:
	if not applies_to(state):
		return true
	ensure_initialized(state)
	if state.district_unlock_dev_bypass:
		return true
	return district_id in state.unlocked_districts


static func unlock_requirement(state: RunState, entry: Dictionary) -> int:
	return _World.unlock_net_worth(entry)


static func can_unlock(state: RunState, entry: Dictionary) -> bool:
	if not applies_to(state):
		return false
	var district_id_value: String = _World.district_id(entry)
	if is_unlocked(state, district_id_value):
		return false
	if state.district_unlock_dev_bypass:
		return true
	return FinanceSystem.net_worth(state) >= unlock_requirement(state, entry)


static func try_unlock(state: RunState, district_id: String, region: Dictionary = {}) -> Dictionary:
	if not applies_to(state):
		return {"ok": false, "error": "Not a 2D run"}
	if region.is_empty():
		region = _World.load_region()
	var entry: Dictionary = _World.find_entry_by_id(region, district_id)
	if entry.is_empty():
		return {"ok": false, "error": "Unknown district"}
	if is_unlocked(state, district_id):
		return {"ok": false, "error": "Already unlocked"}
	if not can_unlock(state, entry):
		return {
			"ok": false,
			"error": "Need %s net worth" % MathUtil.fmt_money(unlock_requirement(state, entry)),
		}
	state.unlocked_districts.append(district_id)
	state.active_district_id = district_id
	ParcelOwnershipSystem.seed_district(state, _World.load_district_from_entry(entry))
	OpportunitySystem.spawn_for_unlocked_districts(state, [district_id])
	ParcelOwnershipSystem.sync_from_state(state, _World.load_district_from_entry(entry))
	state.run_log.append("Unlocked district: %s" % str(_World.load_district_from_entry(entry).get("name", district_id)))
	return {"ok": true, "districtId": district_id}


static func unlock_all_for_testing(state: RunState, region: Dictionary = {}) -> void:
	if not applies_to(state):
		return
	if region.is_empty():
		region = _World.load_region()
	state.district_unlock_dev_bypass = true
	for entry_variant in _World.district_entries(region):
		var entry: Dictionary = entry_variant
		var district_id_value: String = _World.district_id(entry)
		if district_id_value not in state.unlocked_districts:
			state.unlocked_districts.append(district_id_value)
		ParcelOwnershipSystem.seed_district(state, _World.load_district_from_entry(entry))
	OpportunitySystem.spawn_for_unlocked_districts(state, state.unlocked_districts.duplicate())
	ParcelOwnershipSystem.sync_from_state(state)


static func lock_all_except_starter(state: RunState) -> void:
	if not applies_to(state):
		return
	state.district_unlock_dev_bypass = false
	state.unlocked_districts = [STARTER_DISTRICT]
	state.active_district_id = STARTER_DISTRICT


static func refresh_auto_unlocks(state: RunState, region: Dictionary = {}) -> Array:
	var newly_unlocked: Array = []
	if not applies_to(state) or state.district_unlock_dev_bypass:
		return newly_unlocked
	if region.is_empty():
		region = _World.load_region()
	var net_worth := FinanceSystem.net_worth(state)
	for entry_variant in _World.district_entries(region):
		var entry: Dictionary = entry_variant
		var district_id_value: String = _World.district_id(entry)
		if district_id_value in state.unlocked_districts:
			continue
		if net_worth >= unlock_requirement(state, entry):
			state.unlocked_districts.append(district_id_value)
			ParcelOwnershipSystem.seed_district(state, _World.load_district_from_entry(entry))
			newly_unlocked.append(district_id_value)
	return newly_unlocked
