extends Control

const _World := preload("res://scenes/farm_map/world_layout_data.gd")
const _Unlock := preload("res://core/systems/district_unlock_system.gd")
const _Bank := preload("res://core/systems/bank_system.gd")

@onready var _camera: Camera2D = $World/Camera2D
@onready var _world: Node2D = $World
@onready var _terrain = $World/Terrain
@onready var _lots: DistrictParcels = $World/Lots
@onready var _hud: Control = $UI/Hud
@onready var _top_bar: Control = $UI/Hud/TopBar
@onready var _title: Label = $UI/Hud/TopBar/Row/Title
@onready var _run_stats: Label = %RunStats
@onready var _overview_button: Button = %OverviewButton
@onready var _advance_button: Button = %AdvanceButton
@onready var _district_lock_toggle: Button = %DistrictLockToggleButton
@onready var _parcel_panel: PanelContainer = %ParcelBusinessPanel

const MIN_ZOOM := 0.18
const MAX_ZOOM := 2.0
const PAN_SPEED := 520.0
const OVERVIEW_ZOOM := 0.30
const DISTRICT_ZOOM := 0.92
const CAMERA_LERP := 7.0
const PARCEL_FOCUS_FILL := 0.88
const PARCEL_FOCUS_SIDE_MARGIN := 24.0

var _region: Dictionary = {}
var _view_mode := "overview"
var _focus_district_id := "meadowgate_commons"
var _camera_mode := "district"
var _camera_target_pos := Vector2.ZERO
var _camera_target_zoom := Vector2(OVERVIEW_ZOOM, OVERVIEW_ZOOM)
var _improve_panel: Window = null
var _negotiation_panel: CanvasLayer = null
var _community_chat_panel: CanvasLayer = null
var _edge_modal: Window = null
var _shortage_modal: Window = null
var _turn_debrief_modal: Window = null
var _bank_modal: Window = null


func _ready() -> void:
	if Game.state == null:
		Game.go_to_main_menu()
		return
	_region = _World.load_region()
	_Unlock.ensure_initialized(Game.state)
	_Unlock.refresh_auto_unlocks(Game.state, _region)
	resized.connect(_center_world)
	_camera.make_current()
	_center_world()
	_lots.selection_cleared.connect(_on_selection_cleared)
	_parcel_panel.closed.connect(_on_panel_closed)
	_connect_parcel_panel_actions()
	_edge_modal = preload("res://ui/components/edge_choice_modal.gd").new()
	add_child(_edge_modal)
	_edge_modal.edge_chosen.connect(_on_edge_chosen)
	_edge_modal.skipped.connect(_on_edge_skipped)

	_shortage_modal = preload("res://ui/screens/supply_shortage_modal.tscn").instantiate()
	add_child(_shortage_modal)
	_shortage_modal.confirmed.connect(_on_shortage_confirmed)
	_shortage_modal.cancelled.connect(_on_shortage_cancelled)

	_turn_debrief_modal = preload("res://ui/screens/turn_debrief_modal.tscn").instantiate()
	add_child(_turn_debrief_modal)
	_turn_debrief_modal.continued.connect(_on_turn_debrief_continued)

	_bank_modal = preload("res://ui/screens/bank_modal.tscn").instantiate()
	add_child(_bank_modal)
	_bank_modal.closed.connect(_on_bank_modal_closed)

	_wire_map_events()
	_overview_button.pressed.connect(_on_overview_pressed)
	_district_lock_toggle.pressed.connect(_on_district_lock_toggle_pressed)
	_apply_view_context()
	_go_to_overview(false)
	_bootstrap_map()
	_maybe_show_edge_choices()


func _wire_map_events() -> void:
	EventBus.run_started.connect(_on_run_bootstrap)
	EventBus.run_loaded.connect(_on_run_bootstrap)
	EventBus.turn_advanced.connect(_on_turn_advanced)
	EventBus.turn_debrief_ready.connect(_on_turn_debrief_ready)
	EventBus.edge_choices_pending.connect(_on_edge_choices_pending)
	EventBus.districts_unlocked.connect(_on_districts_unlocked)
	EventBus.map_state_changed.connect(_on_map_state_changed)
	EventBus.asset_acquired.connect(_on_asset_acquired)
	EventBus.run_ended.connect(_on_run_ended)


func _connect_parcel_panel_actions() -> void:
	_improve_panel = preload("res://ui/screens/improve_panel.tscn").instantiate()
	add_child(_improve_panel)
	_improve_panel.closed.connect(_on_modal_closed_refresh_parcels)
	_improve_panel.level_up.connect(_on_improve_level_up)
	_improve_panel.negotiate.connect(_on_parcel_negotiate)

	_negotiation_panel = preload("res://ui/screens/negotiation_panel.tscn").instantiate()
	add_child(_negotiation_panel)
	_negotiation_panel.closed.connect(_on_modal_closed_refresh_parcels)

	_community_chat_panel = preload("res://ui/screens/community_chat_panel.tscn").instantiate()
	add_child(_community_chat_panel)
	_community_chat_panel.closed.connect(_on_modal_closed_refresh_parcels)

	_parcel_panel.improve_business.connect(_on_parcel_improve)
	_parcel_panel.sell_business.connect(_on_parcel_sell)
	_parcel_panel.buy_opportunity.connect(_on_parcel_buy)
	_parcel_panel.investigate_opportunity.connect(_on_parcel_investigate)
	_parcel_panel.negotiate_opportunity.connect(_on_parcel_negotiate)
	_parcel_panel.chat_community_business.connect(_on_parcel_chat)


func _on_parcel_improve(business_id: String) -> void:
	_improve_panel.open_for_business(business_id)


func _on_improve_level_up(_opportunity_id: String) -> void:
	_refresh_hud()
	_lots.refresh_ownership()
	_refresh_selected_parcel()


func _on_parcel_sell(business_id: String) -> void:
	Game.apply_command(GameCommand.sell_asset("business", business_id))


func _on_parcel_buy(opportunity_id: String) -> void:
	Game.apply_command(GameCommand.acquire_business(opportunity_id))


func _on_parcel_investigate(opportunity_id: String) -> void:
	Game.apply_command(GameCommand.investigate(opportunity_id))


func _on_parcel_negotiate(opportunity_id: String) -> void:
	var selected: Dictionary = _lots.get_selection() if _lots != null else {}
	if not selected.is_empty():
		_focus_parcel(selected)
		_snap_camera_to_targets()
	if _parcel_panel != null:
		_parcel_panel.hide_panel()
	_negotiation_panel.open_for_opportunity(opportunity_id)


func _on_parcel_chat(community_business_id: String, parcel_id: String, district_id: String) -> void:
	var selected: Dictionary = _lots.get_selection() if _lots != null else {}
	if not selected.is_empty():
		_focus_parcel(selected)
		_snap_camera_to_targets()
	if _parcel_panel != null:
		_parcel_panel.hide_panel()
	if _community_chat_panel != null:
		_community_chat_panel.open_for_community_business(community_business_id, parcel_id, district_id)


func _snap_camera_to_targets() -> void:
	_camera.position = _camera_target_pos
	_camera.zoom = _camera_target_zoom


func _on_edge_choices_pending(_state: RunState, _choices: Array) -> void:
	_maybe_show_edge_choices()


func _maybe_show_edge_choices() -> void:
	var s: RunState = Game.state
	if s == null or s.edge_choices_pending.is_empty() or s.game_over != null:
		if _edge_modal != null and _edge_modal.visible:
			_edge_modal.close_modal()
		return
	if _edge_modal != null and _edge_modal.visible:
		return
	_edge_modal.open_with_choices(s.edge_choices_pending)


func _on_edge_chosen(edge_id: String) -> void:
	Game.apply_command(GameCommand.choose_edge(edge_id))


func _on_edge_skipped() -> void:
	Game.apply_command(GameCommand.skip_edge())


func _on_advance_pressed() -> void:
	var result: Dictionary = Game.apply_command(GameCommand.advance_turn())
	if bool(result.get("requires_supply_policy", false)):
		_shortage_modal.open_with_shortages(result.get("shortages", []))
		return
	if not bool(result.get("ok", false)):
		push_warning("Turn failed: %s" % str(result.get("error", "unknown")))


func _on_shortage_confirmed() -> void:
	_refresh_hud()
	var result: Dictionary = Game.apply_command(GameCommand.advance_turn())
	if bool(result.get("requires_supply_policy", false)):
		_shortage_modal.open_with_shortages(result.get("shortages", []))
	elif not bool(result.get("ok", false)):
		push_warning("Turn failed: %s" % str(result.get("error", "unknown")))


func _on_shortage_cancelled() -> void:
	pass


func _on_turn_debrief_continued() -> void:
	Game.apply_command(GameCommand.dismiss_turn_debrief())


func _maybe_show_turn_debrief() -> void:
	var s: RunState = Game.state
	if s == null or s.pending_turn_debrief.is_empty() or s.game_over != null:
		return
	if _turn_debrief_modal.visible:
		return
	_turn_debrief_modal.open_with_report(s.pending_turn_debrief)


func _center_world() -> void:
	if _world == null:
		return
	_world.position = get_viewport_rect().size * 0.5
	_position_parcel_panel()
	if _camera_mode == "parcel" and _lots != null:
		var selected: Dictionary = _lots.get_selection()
		if not selected.is_empty():
			_focus_parcel(selected)
			return
	_update_camera_targets()


func _position_parcel_panel() -> void:
	if _parcel_panel == null:
		return
	var view_size := get_viewport_rect().size
	var top_y := _top_bar_bottom_y()
	var side_margin := 16.0
	var panel_width := 300.0
	var bottom_margin := 24.0
	var panel_height := maxf(160.0, view_size.y - top_y - bottom_margin)
	_parcel_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_parcel_panel.offset_left = -panel_width - side_margin
	_parcel_panel.offset_right = -side_margin
	_parcel_panel.offset_top = top_y
	_parcel_panel.offset_bottom = top_y + panel_height
	_parcel_panel.custom_minimum_size = Vector2(panel_width, 0)


func _world_mouse() -> Vector2:
	var screen := get_viewport().get_mouse_position()
	var center := get_viewport_rect().size * 0.5
	return _camera.position + (screen - center) / _camera.zoom.x


func _input(event: InputEvent) -> void:
	if _camera == null or _lots == null:
		return
	if event is InputEventMouseMotion:
		_update_hover()
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if not mb.pressed:
			return
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if _pointer_over_ui():
				return
			_handle_map_click()
			get_viewport().set_input_as_handled()
		elif mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			if _pointer_over_ui():
				return
			_set_zoom(_camera.zoom.x * 1.1)
			get_viewport().set_input_as_handled()
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			if _pointer_over_ui():
				return
			_set_zoom(_camera.zoom.x / 1.1)
			get_viewport().set_input_as_handled()


func _set_zoom(next_zoom: float) -> void:
	var clamped := clampf(next_zoom, MIN_ZOOM, MAX_ZOOM)
	_camera.zoom = Vector2(clamped, clamped)
	_camera_target_zoom = _camera.zoom
	_camera_target_pos = _camera.position


func _pointer_over_ui() -> bool:
	if _negotiation_panel != null and _negotiation_panel.visible:
		return true
	if _community_chat_panel != null and _community_chat_panel.visible:
		return true
	var hovered: Control = get_viewport().gui_get_hovered_control()
	if hovered == null:
		return false
	if _top_bar and (_top_bar == hovered or _top_bar.is_ancestor_of(hovered)):
		return true
	if hovered is BaseButton:
		return true
	if _parcel_panel.visible and _parcel_panel.is_ancestor_of(hovered):
		return true
	return false


func _update_hover() -> void:
	if _negotiation_panel != null and _negotiation_panel.visible:
		_lots.set_hover({})
		return
	if _community_chat_panel != null and _community_chat_panel.visible:
		_lots.set_hover({})
		return
	if _pointer_over_ui():
		_lots.set_hover({})
		return
	var hit: Dictionary = _lots.pick_at_world_pos(_world_mouse())
	_lots.set_hover(hit)


func _handle_map_click() -> void:
	var hit: Dictionary = _lots.pick_at_world_pos(_world_mouse())
	if not hit.is_empty():
		var district_id := str(hit.get("district_id", _focus_district_id))
		if _view_mode == "overview":
			_focus_district(district_id)
		var current: Dictionary = _lots.get_selection()
		if not current.is_empty() and str(hit.get("id", "")) == str(current.get("id", "")) and str(hit.get("district_id", "")) == str(current.get("district_id", "")):
			_lots.clear_selection()
			_parcel_panel.hide_panel()
			return
		_lots.set_selection(hit)
		if _Bank.is_bank_parcel(hit):
			_parcel_panel.hide_panel()
			_bank_modal.open_bank()
		else:
			_parcel_panel.show_parcel(hit, _lots.get_district_for_hit(hit))
			_position_parcel_panel()
			_focus_parcel(hit)
		return

	var district_entry: Dictionary = _World.find_district_at_point(_region, _world_mouse(), _lots.get_region_offset())
	if district_entry.is_empty():
		_lots.clear_selection()
		_parcel_panel.hide_panel()
		return

	var district_id: String = _World.district_id(district_entry)
	if not _Unlock.is_unlocked(Game.state, district_id):
		_show_locked_district(district_entry)
		return

	if _view_mode == "overview":
		_focus_district(district_id)
	else:
		_lots.clear_selection()
		_parcel_panel.hide_panel()


func _show_locked_district(entry: Dictionary) -> void:
	_lots.clear_selection()
	var district: Dictionary = _World.load_district_from_entry(entry)
	_title.text = "%s (Locked)" % str(district.get("name", "District"))
	var requirement: int = _Unlock.unlock_requirement(Game.state, entry)
	var net_worth := FinanceSystem.net_worth(Game.state)
	_parcel_panel.show_locked_district(
		str(district.get("name", "District")),
		requirement,
		net_worth,
		_Unlock.can_unlock(Game.state, entry)
	)
	_position_parcel_panel()


func _focus_district(district_id: String) -> void:
	if district_id.is_empty() or not _Unlock.is_unlocked(Game.state, district_id):
		return
	_camera_mode = "district"
	_view_mode = "district"
	_focus_district_id = district_id
	if Game.state != null:
		Game.state.active_district_id = district_id
	_apply_view_context()
	_update_camera_targets()
	_refresh_title()


func _go_to_overview(animate: bool = true) -> void:
	_camera_mode = "district"
	_view_mode = "overview"
	_apply_view_context()
	_update_camera_targets()
	_refresh_title()
	if not animate:
		_camera.position = _camera_target_pos
		_camera.zoom = _camera_target_zoom


func _apply_view_context() -> void:
	_lots.set_view_context(_view_mode, _focus_district_id)
	if _terrain != null and _terrain.has_method("set_view_context"):
		_terrain.set_view_context(_view_mode, _focus_district_id)


func _update_camera_targets() -> void:
	var region_offset: Vector2 = _lots.get_region_offset()
	if _view_mode == "overview":
		_camera_target_zoom = Vector2(OVERVIEW_ZOOM, OVERVIEW_ZOOM)
		_camera_target_pos = Vector2.ZERO
		return

	var entry: Dictionary = _World.find_entry_by_id(_region, _focus_district_id)
	if entry.is_empty():
		return
	var district: Dictionary = _World.load_district_from_entry(entry)
	_camera_target_zoom = Vector2(DISTRICT_ZOOM, DISTRICT_ZOOM)
	_camera_target_pos = _World.district_center_screen(entry, district, region_offset)


func _top_bar_bottom_y() -> float:
	if _top_bar != null:
		return _top_bar.offset_top + _top_bar.size.y + 12.0
	return 88.0


func _focus_parcel(hit: Dictionary) -> void:
	if hit.is_empty() or _view_mode != "district" or _lots == null:
		return
	var frame: Dictionary = _lots.get_parcel_frame(hit)
	if frame.is_empty():
		return

	var center: Vector2 = frame.get("center", Vector2.ZERO)
	var bounds: Rect2 = frame.get("bounds", Rect2())
	var view_size := get_viewport_rect().size
	var viewport_center := view_size * 0.5
	var top_y := _top_bar_bottom_y()
	var left_half_w := view_size.x * 0.5 - PARCEL_FOCUS_SIDE_MARGIN
	var usable_h := view_size.y - top_y - PARCEL_FOCUS_SIDE_MARGIN
	var bounds_w := maxf(bounds.size.x, 1.0)
	var bounds_h := maxf(bounds.size.y, 1.0)
	var zoom_val := minf(left_half_w / bounds_w, usable_h / bounds_h) * PARCEL_FOCUS_FILL
	zoom_val = clampf(zoom_val, MIN_ZOOM, MAX_ZOOM)

	var screen_target := Vector2(view_size.x * 0.25, top_y + usable_h * 0.5)
	_camera_mode = "parcel"
	_camera_target_zoom = Vector2(zoom_val, zoom_val)
	_camera_target_pos = center - (screen_target - viewport_center) / zoom_val


func _restore_district_camera() -> void:
	if _camera_mode != "parcel":
		return
	_camera_mode = "district"
	_update_camera_targets()


func _refresh_title() -> void:
	if _view_mode == "overview":
		_title.text = "Capital Farm Valley — Overview"
		return
	var entry: Dictionary = _World.find_entry_by_id(_region, _focus_district_id)
	var district: Dictionary = _World.load_district_from_entry(entry)
	_title.text = "D%d · %s" % [int(entry.get("index", 0)), str(district.get("name", "District"))]


func _on_selection_cleared() -> void:
	_parcel_panel.hide_panel()
	_restore_district_camera()


func _on_panel_closed() -> void:
	if _lots != null:
		_lots.clear_selection()


func _on_overview_pressed() -> void:
	_go_to_overview()
	_lots.clear_selection()
	_parcel_panel.hide_panel()


func _on_district_lock_toggle_pressed() -> void:
	if Game.state != null and Game.state.district_unlock_dev_bypass:
		_Unlock.lock_all_except_starter(Game.state)
		if not _Unlock.is_unlocked(Game.state, _focus_district_id):
			_go_to_overview()
	else:
		_Unlock.unlock_all_for_testing(Game.state, _region)
	_bootstrap_map()
	_refresh_district_lock_toggle()


func _refresh_district_lock_toggle() -> void:
	if _district_lock_toggle == null or Game.state == null:
		return
	if Game.state.district_unlock_dev_bypass:
		_district_lock_toggle.text = "Enforce Locks"
	else:
		_district_lock_toggle.text = "Unlock All (Test)"


func _on_run_bootstrap(_state: RunState) -> void:
	_bootstrap_map()


func _on_turn_advanced(_state: RunState) -> void:
	_refresh_hud()
	_refresh_parcels()
	_refresh_selected_parcel()


func _on_turn_debrief_ready(_state: RunState, _debrief: Dictionary) -> void:
	_maybe_show_turn_debrief()


func _on_districts_unlocked(_state: RunState, _district_ids: Array) -> void:
	_refresh_terrain()
	_refresh_parcels()


func _on_map_state_changed(_state: RunState) -> void:
	_refresh_parcels()
	_refresh_selected_parcel()


func _on_asset_acquired(_asset_type: String = "", _asset_id: String = "") -> void:
	_refresh_hud()
	_refresh_parcels()
	_refresh_selected_parcel()


func _on_run_ended(_state: RunState) -> void:
	_refresh_hud()
	Game.go_to_run_report()


func _on_bank_modal_closed() -> void:
	_refresh_hud()


func _on_modal_closed_refresh_parcels() -> void:
	_refresh_hud()
	_refresh_parcels()
	_refresh_selected_parcel()


func _bootstrap_map() -> void:
	if Game.state != null:
		_Unlock.refresh_auto_unlocks(Game.state, _region)
	_refresh_all()


func _refresh_all() -> void:
	if _lots == null:
		return
	_refresh_parcels()
	_refresh_terrain()
	_refresh_hud()
	_refresh_title()
	_refresh_selected_parcel()


func _refresh_parcels() -> void:
	if _lots == null:
		return
	_lots.refresh_ownership()


func _refresh_terrain() -> void:
	if _terrain != null and _terrain.has_method("refresh_map"):
		_terrain.refresh_map()


func _refresh_selected_parcel() -> void:
	if _parcel_panel == null or not _parcel_panel.visible or _lots == null:
		return
	var selected: Dictionary = _lots.get_selection()
	if selected.is_empty():
		return
	_parcel_panel.show_parcel(selected, _lots.get_district_for_hit(selected))
	_position_parcel_panel()
	_focus_parcel(selected)


func _refresh_hud() -> void:
	if _run_stats == null or Game.state == null:
		return
	var stats: Dictionary = RunView.header_stats(Game.state)
	_run_stats.text = "Turn %d · %s · NW %s · Debt %s · %d AP" % [
		int(stats.get("turn", 0)),
		MathUtil.fmt_money(int(stats.get("cash", 0))),
		MathUtil.fmt_money(int(stats.get("netWorth", 0))),
		MathUtil.fmt_money(int(stats.get("debt", 0))),
		int(stats.get("actionPoints", 0)),
	]
	if _advance_button != null:
		_advance_button.disabled = Game.state.game_over != null
	_refresh_district_lock_toggle()


func _process(delta: float) -> void:
	if _camera == null:
		return
	var t := clampf(delta * CAMERA_LERP, 0.0, 1.0)
	_camera.position = _camera.position.lerp(_camera_target_pos, t)
	_camera.zoom = _camera.zoom.lerp(_camera_target_zoom, t)

	var motion := Vector2.ZERO
	if Input.is_action_pressed("ui_right"):
		motion.x += 1.0
	if Input.is_action_pressed("ui_left"):
		motion.x -= 1.0
	if Input.is_action_pressed("ui_down"):
		motion.y += 1.0
	if Input.is_action_pressed("ui_up"):
		motion.y -= 1.0
	if motion != Vector2.ZERO:
		_camera.position += motion * PAN_SPEED * delta / _camera.zoom.x
		_camera_target_pos = _camera.position


func _on_back_pressed() -> void:
	Game.go_to_main_menu()
