# Thin coordinator: run lifecycle, commands, save/load.
extends Node

const DASHBOARD_SCENE := "res://ui/screens/dashboard.tscn"
const RUN_REPORT_SCENE := "res://ui/screens/run_report.tscn"
const MAIN_MENU_SCENE := "res://ui/screens/main_menu.tscn"
const ISO_FARM_MAP_SCENE := "res://scenes/farm_map/iso_farm_map.tscn"
const DEFAULT_SAVE_PATH := "user://saves/slot_0.json"

var state: RunState = null


func _ready() -> void:
	Content.load_farm_content()
	NegotiationArchetypes.ensure_loaded()


func has_active_run() -> bool:
	return state != null and state.game_over == null


func has_save_file(path: String = DEFAULT_SAVE_PATH) -> bool:
	return FileAccess.file_exists(path)


func start_new_run(mode: String = RunState.CAPITAL_FARM_MODE) -> RunState:
	state = RunState.create_new(mode)
	RunBootstrap.prepare_new_run(state)
	OpportunitySystem.refresh_opportunities(state)
	ParcelOwnershipSystem.sync_from_state(state)
	DistrictUnlockSystem.ensure_initialized(state)
	DistrictUnlockSystem.refresh_auto_unlocks(state)
	ActionPointsSystem.reset_for_turn(state)
	EventBus.run_started.emit(state)
	return state


func load_from_dict(data: Dictionary) -> RunState:
	state = RunState.from_dict(data)
	EventBus.run_loaded.emit(state)
	return state


func save_to_dict() -> Dictionary:
	if state == null:
		return {}
	return state.to_dict()


func save_to_file(path: String = DEFAULT_SAVE_PATH) -> bool:
	var dir := path.get_base_dir()
	DirAccess.make_dir_recursive_absolute(dir)
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("Game.save_to_file: cannot open %s" % path)
		return false
	file.store_string(JSON.stringify(save_to_dict(), "\t"))
	return true


func load_from_file(path: String = DEFAULT_SAVE_PATH) -> bool:
	if not FileAccess.file_exists(path):
		return false
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return false
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("Game.load_from_file: invalid JSON in %s" % path)
		return false
	load_from_dict(parsed)
	ParcelOwnershipSystem.sync_from_state(state)
	return true


func apply_command(command: Dictionary) -> Dictionary:
	if state == null:
		return {"ok": false, "error": "No active run"}

	var command_name: String = str(command.get("type", ""))
	var result: Dictionary = CommandProcessor.apply(state, command)
	if not bool(result.get("ok", false)):
		return result

	if result.has("state"):
		state = result.get("state")

	match command_name:
		GameCommand.ADVANCE_TURN:
			_emit_turn_pipeline_events(result.get("events", []))
			EventBus.turn_advanced.emit(state)
			if state.game_over != null:
				EventBus.run_ended.emit(state)
		GameCommand.ACQUIRE_BUSINESS, GameCommand.ACQUIRE_REAL_ESTATE:
			var biz: Variant = result.get("business")
			if biz is BusinessInstance:
				EventBus.asset_acquired.emit("business", (biz as BusinessInstance).id)
			elif command_name == GameCommand.ACQUIRE_REAL_ESTATE:
				var re: Variant = result.get("realEstate")
				if re is Dictionary:
					EventBus.asset_acquired.emit("realestate", str((re as Dictionary).get("id", "")))
		GameCommand.APPLY_UPGRADE:
			var upgraded: Variant = result.get("business")
			if upgraded is BusinessInstance:
				EventBus.asset_acquired.emit("upgrade", (upgraded as BusinessInstance).id)
		GameCommand.SELL_ASSET:
			_emit_map_state_if_2d()
		GameCommand.TAKE_BANK_LOAN, GameCommand.BUY_SECURITY_TICKER:
			_emit_map_state_if_2d()
		GameCommand.INVESTIGATE:
			_emit_map_state_if_2d()
		GameCommand.START_NEGOTIATION:
			EventBus.negotiation_started.emit(state)
		GameCommand.SEND_NEGOTIATION_MESSAGE:
			if bool(result.get("closed", false)):
				if result.has("business"):
					EventBus.asset_acquired.emit("business", (result.get("business") as BusinessInstance).id)
				else:
					EventBus.negotiation_ended.emit(state)
		GameCommand.END_NEGOTIATION:
			EventBus.negotiation_ended.emit(state)

	if command_name != GameCommand.ADVANCE_TURN:
		_try_emit_district_unlocks()

	EventBus.command_applied.emit(command_name, state)
	return result


func _emit_turn_pipeline_events(events: Variant) -> void:
	if typeof(events) != TYPE_ARRAY:
		return
	for ev_variant in events:
		if typeof(ev_variant) != TYPE_DICTIONARY:
			continue
		var ev: Dictionary = ev_variant
		match str(ev.get("type", "")):
			TurnPipeline.EVENT_TURN_DEBRIEF_READY:
				EventBus.turn_debrief_ready.emit(state, ev.get("debrief", {}))
			TurnPipeline.EVENT_MILESTONE_REACHED:
				EventBus.milestone_reached.emit(state, str(ev.get("milestoneId", "")))
			TurnPipeline.EVENT_EDGE_CHOICES_PENDING:
				EventBus.edge_choices_pending.emit(state, ev.get("choices", []))
			TurnPipeline.EVENT_SUPPLY_SHORTAGE_DETECTED:
				EventBus.supply_shortage_detected.emit(state, ev.get("shortages", []))
			TurnPipeline.EVENT_DISTRICTS_UNLOCKED:
				var district_ids: Array = ev.get("districtIds", [])
				EventBus.districts_unlocked.emit(state, district_ids)
				EventBus.map_state_changed.emit(state)


func _try_emit_district_unlocks() -> void:
	if state == null or not DistrictUnlockSystem.applies_to(state):
		return
	var newly: Array = DistrictUnlockSystem.refresh_auto_unlocks(state)
	if newly.is_empty():
		return
	OpportunitySystem.spawn_for_unlocked_districts(state, newly)
	ParcelOwnershipSystem.sync_from_state(state)
	EventBus.districts_unlocked.emit(state, newly)
	EventBus.map_state_changed.emit(state)


func _emit_map_state_if_2d() -> void:
	if state == null or not DistrictUnlockSystem.applies_to(state):
		return
	EventBus.map_state_changed.emit(state)


func net_worth() -> int:
	if state == null:
		return 0
	return FinanceSystem.net_worth(state)


func go_to_main_menu() -> void:
	get_tree().change_scene_to_file(MAIN_MENU_SCENE)


func go_to_dashboard() -> void:
	if state != null and state.game_over != null:
		get_tree().change_scene_to_file(RUN_REPORT_SCENE)
		return
	get_tree().change_scene_to_file(DASHBOARD_SCENE)


func go_to_active_run() -> void:
	if state == null:
		go_to_main_menu()
		return
	if state.game_over != null:
		go_to_run_report()
		return
	if GameMode.is_2d_run(state.mode):
		go_to_iso_farm_map()
	else:
		go_to_dashboard()


func go_to_run_report() -> void:
	get_tree().change_scene_to_file(RUN_REPORT_SCENE)


func go_to_iso_farm_map() -> void:
	if state != null and state.game_over != null:
		get_tree().change_scene_to_file(RUN_REPORT_SCENE)
		return
	get_tree().change_scene_to_file(ISO_FARM_MAP_SCENE)


func send_negotiation_message_async(text: String, callback: Callable) -> void:
	if state == null:
		callback.call({"ok": false, "error": "No active run"})
		return

	var trimmed := text.strip_edges()
	if trimmed.is_empty():
		callback.call({"ok": false, "error": "Empty message"})
		return

	var send_with_ai := func() -> void:
		var append_result: Dictionary = apply_command(GameCommand.append_negotiation_player(trimmed))
		if not bool(append_result.get("ok", false)):
			callback.call(append_result)
			return
		EventBus.negotiation_updated.emit(state)
		AiClient.request_negotiation(state, trimmed, func(ai_parsed: Dictionary, err: String) -> void:
			var parsed: Dictionary = ai_parsed if err.is_empty() else {}
			callback.call(apply_command(
				GameCommand.send_negotiation_message(trimmed, parsed, true)
			))
		)

	if AiClient.ai_available:
		send_with_ai.call()
	else:
		AiClient.check_health(func(_available: bool, _model: String) -> void:
			send_with_ai.call()
		)
