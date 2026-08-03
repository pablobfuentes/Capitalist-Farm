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
@onready var _supply_chain_toggle: Button = %SupplyChainToggleButton
@onready var _advance_button: Button = %AdvanceButton
@onready var _district_lock_toggle: Button = %DistrictLockToggleButton
@onready var _back_button: Button = %BackButton
@onready var _parcel_panel: PanelContainer = %ParcelBusinessPanel
@onready var _portfolio_sidebar: PanelContainer = %PortfolioSidebar
@onready var _sc_path_controls: PanelContainer = %SupplyChainPathControls
@onready var _sc_route_tooltip: PanelContainer = %SupplyChainRouteTooltip
@onready var _sc_route_tooltip_label: RichTextLabel = %TooltipLabel

const _ICON_LOCK := preload("res://assets/ui/icons/icon_lock.svg")
const _ICON_LOCK_OPEN := preload("res://assets/ui/icons/icon_lock_open.svg")
const _SupplyChainController := preload("res://scenes/farm_map/supply_chain_view_controller.gd")
const _SupplyChainRouteLayer := preload("res://scenes/farm_map/supply_chain_route_layer.gd")

const MIN_ZOOM := 0.18
const MAX_ZOOM := 2.0
const PAN_SPEED := 520.0
const OVERVIEW_ZOOM := 0.30
const DISTRICT_ZOOM := 0.92
const CAMERA_LERP := 7.0
const PARCEL_FOCUS_FILL := 0.88
const ADVANCE_BUTTON_RESERVE := 80.0

var _region: Dictionary = {}
var _view_mode := "overview"
var _focus_district_id := "meadowgate_commons"
var _camera_mode := "district"
var _camera_target_pos := Vector2.ZERO
var _camera_target_zoom := Vector2(OVERVIEW_ZOOM, OVERVIEW_ZOOM)
var _improve_panel: Window = null
var _negotiation_panel: CanvasLayer = null
var _community_chat_panel: CanvasLayer = null
var _certificate_modal: CanvasLayer = null
var _edge_modal: Window = null
var _shortage_modal: Window = null
var _turn_debrief_modal: Window = null
var _bank_modal: Window = null
var _supply_chain: Node = null
var _supply_chain_routes: Node2D = null
var _quit_confirm: ConfirmationDialog = null


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
	if _portfolio_sidebar != null and _portfolio_sidebar.has_signal("expanded_toggled"):
		_portfolio_sidebar.expanded_toggled.connect(_on_portfolio_expanded_toggled)
	if _portfolio_sidebar != null and _portfolio_sidebar.has_signal("business_selected"):
		_portfolio_sidebar.business_selected.connect(_on_portfolio_business_selected)
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
	_setup_supply_chain_view()
	_overview_button.pressed.connect(_on_overview_pressed)
	_district_lock_toggle.pressed.connect(_on_district_lock_toggle_pressed)
	FeedbackBus.wire_button(_overview_button)
	FeedbackBus.wire_button(_advance_button)
	FeedbackBus.wire_button(_district_lock_toggle)
	FeedbackBus.wire_button(_back_button)
	FeedbackBus.wire_button(_supply_chain_toggle)
	_style_icon_button(_back_button)
	_style_icon_button(_district_lock_toggle)
	_style_icon_button(_supply_chain_toggle)
	_apply_view_context()
	_go_to_overview(false)
	_bootstrap_map()
	_maybe_show_edge_choices()
	FeedbackBus.set_ambient("map")


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

	_certificate_modal = preload("res://ui/screens/acquisition_certificate_modal.tscn").instantiate()
	add_child(_certificate_modal)

	_community_chat_panel = preload("res://ui/screens/community_chat_panel.tscn").instantiate()
	add_child(_community_chat_panel)
	_community_chat_panel.closed.connect(_on_modal_closed_refresh_parcels)

	_parcel_panel.improve_business.connect(_on_parcel_improve)
	_parcel_panel.sell_business.connect(_on_parcel_sell)
	_parcel_panel.buy_opportunity.connect(_on_parcel_buy)
	_parcel_panel.investigate_opportunity.connect(_on_parcel_investigate)
	_parcel_panel.negotiate_opportunity.connect(_on_parcel_negotiate)
	_parcel_panel.negotiate_urgency.connect(_on_parcel_negotiate_urgency)
	_parcel_panel.chat_community_business.connect(_on_parcel_chat)


func _on_parcel_improve(business_id: String) -> void:
	_improve_panel.open_for_business(business_id)


func _on_improve_level_up(_opportunity_id: String) -> void:
	_refresh_hud()
	_lots.refresh_ownership()
	_refresh_selected_parcel()


func _on_parcel_sell(business_id: String) -> void:
	var before := _economy_snapshot()
	var result: Dictionary = Game.apply_command(GameCommand.sell_asset("business", business_id))
	if not bool(result.get("ok", false)):
		_deny_with_reason(str(result.get("error", "Sell failed")))
		return
	_emit_economy_deltas(before)
	_refresh_parcels()
	_refresh_selected_parcel()
	if _parcel_panel != null:
		_parcel_panel.hide_panel()
	_sync_supply_chain_blocks()


func _on_parcel_buy(opportunity_id: String) -> void:
	var before := _economy_snapshot()
	var selected: Dictionary = _lots.get_selection() if _lots != null else {}
	var result: Dictionary = Game.apply_command(GameCommand.acquire_business(opportunity_id))
	if not bool(result.get("ok", false)):
		_deny_with_reason(str(result.get("error", "Purchase failed")))
		_refresh_selected_parcel()
		return
	# Quiet HUD/map update — money/NW celebration runs only after certificate dismiss.
	_refresh_hud()
	if _lots != null:
		_lots.flash_acquisition(selected)
	await _present_acquisition_certificate(result, int(before.get("nw", 0)))
	_on_modal_closed_refresh_parcels()


func _present_acquisition_certificate(result: Dictionary, nw_before: int = -1) -> void:
	if _certificate_modal == null:
		return
	var CertScript = preload("res://ui/screens/acquisition_certificate_modal.gd")
	if not CertScript.is_acquisition_result(result):
		return
	if _parcel_panel != null:
		_parcel_panel.hide_panel()
	var before_nw := nw_before if nw_before >= 0 else 0
	var after_nw := FinanceSystem.net_worth(Game.state) if Game.state != null else before_nw
	var deal: Dictionary = CertScript.deal_from_command_result(result, before_nw, after_nw)
	await _certificate_modal.present(deal, _run_stats)


func _on_parcel_investigate(opportunity_id: String) -> void:
	var before := _economy_snapshot()
	var result: Dictionary = Game.apply_command(GameCommand.investigate(opportunity_id))
	if not bool(result.get("ok", false)):
		_deny_with_reason(str(result.get("error", "Investigate failed")))
		return
	_emit_economy_deltas(before)


func _on_parcel_negotiate(opportunity_id: String) -> void:
	var selected: Dictionary = _lots.get_selection() if _lots != null else {}
	if not selected.is_empty():
		_focus_parcel(selected)
		_snap_camera_to_targets()
	if _parcel_panel != null:
		_parcel_panel.hide_panel()
	_negotiation_panel.open_for_opportunity(opportunity_id)
	_sync_supply_chain_blocks()


func _on_parcel_negotiate_urgency(problem_id: String) -> void:
	var selected: Dictionary = _lots.get_selection() if _lots != null else {}
	if not selected.is_empty():
		_focus_parcel(selected)
		_snap_camera_to_targets()
	var result: Dictionary = Game.apply_command(GameCommand.start_urgent_negotiation(problem_id))
	if not bool(result.get("ok", false)):
		_deny_with_reason(str(result.get("error", "Urgent negotiation failed")))
		_refresh_selected_parcel()
		return
	if _parcel_panel != null:
		_parcel_panel.hide_panel()
	_negotiation_panel.open_active()
	_sync_supply_chain_blocks()


func _on_parcel_chat(community_business_id: String, parcel_id: String, district_id: String) -> void:
	var selected: Dictionary = _lots.get_selection() if _lots != null else {}
	if not selected.is_empty():
		_focus_parcel(selected)
		_snap_camera_to_targets()
	if _parcel_panel != null:
		_parcel_panel.hide_panel()
	if _community_chat_panel != null:
		_community_chat_panel.open_for_community_business(community_business_id, parcel_id, district_id)
	_sync_supply_chain_blocks()


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
	FeedbackBus.advance_whoosh()
	FeedbackBus.pulse(_advance_button)
	await get_tree().create_timer(0.12).timeout
	var before := _economy_snapshot()
	var result: Dictionary = Game.apply_command(GameCommand.advance_turn())
	if bool(result.get("requires_supply_policy", false)):
		FeedbackBus.deny(_advance_button)
		_shortage_modal.open_with_shortages(result.get("shortages", []))
		return
	if not bool(result.get("ok", false)):
		FeedbackBus.deny(_advance_button)
		var err := str(result.get("error", "Turn failed"))
		FeedbackBus.toast_error(err)
		push_warning("Turn failed: %s" % err)
		return
	_emit_economy_deltas(before)


func _on_shortage_confirmed() -> void:
	_refresh_hud()
	FeedbackBus.advance_whoosh()
	var before := _economy_snapshot()
	var result: Dictionary = Game.apply_command(GameCommand.advance_turn())
	if bool(result.get("requires_supply_policy", false)):
		FeedbackBus.deny(_advance_button)
		_shortage_modal.open_with_shortages(result.get("shortages", []))
	elif not bool(result.get("ok", false)):
		FeedbackBus.deny(_advance_button)
		var err := str(result.get("error", "Turn failed"))
		FeedbackBus.toast_error(err)
		push_warning("Turn failed: %s" % err)
	else:
		_emit_economy_deltas(before)


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
	_position_portfolio_sidebar()
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
	# Leave room above the lower-right Advance Turn button.
	var bottom_margin := ADVANCE_BUTTON_RESERVE
	var panel_height := maxf(160.0, view_size.y - top_y - bottom_margin)
	# Reset any stray position from older swipe tweens, then pin with anchors/offsets.
	_parcel_panel.position = Vector2.ZERO
	_parcel_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_parcel_panel.offset_left = -panel_width - side_margin
	_parcel_panel.offset_right = -side_margin
	_parcel_panel.offset_top = top_y
	_parcel_panel.offset_bottom = top_y + panel_height
	_parcel_panel.custom_minimum_size = Vector2(panel_width, 0)


func _position_portfolio_sidebar() -> void:
	if _portfolio_sidebar == null:
		return
	var view_size := get_viewport_rect().size
	var top_y := _top_bar_bottom_y()
	var side_margin := 16.0
	var panel_width := 272.0
	if _portfolio_sidebar.has_method("expanded_width"):
		panel_width = float(_portfolio_sidebar.call("expanded_width"))
	var bottom_margin := ADVANCE_BUTTON_RESERVE
	var panel_height := maxf(160.0, view_size.y - top_y - bottom_margin)
	_portfolio_sidebar.position = Vector2.ZERO
	_portfolio_sidebar.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_portfolio_sidebar.offset_left = side_margin
	_portfolio_sidebar.offset_right = side_margin + panel_width
	_portfolio_sidebar.offset_top = top_y
	_portfolio_sidebar.offset_bottom = top_y + panel_height
	_portfolio_sidebar.custom_minimum_size = Vector2(panel_width, 0)


func _on_portfolio_expanded_toggled(_expanded: bool) -> void:
	_position_portfolio_sidebar()
	if _camera_mode == "parcel" and _lots != null:
		var selected: Dictionary = _lots.get_selection()
		if not selected.is_empty():
			_focus_parcel(selected)


func _on_portfolio_business_selected(business_id: String) -> void:
	if business_id.is_empty() or _lots == null:
		return
	var hit: Dictionary = _lots.find_hit_for_business(business_id)
	if hit.is_empty():
		return
	var district_id := str(hit.get("district_id", ""))
	if not district_id.is_empty() and (_view_mode == "overview" or district_id != _focus_district_id):
		_focus_district(district_id)
		hit = _lots.find_hit_for_business(business_id)
		if hit.is_empty():
			return
	_lots.set_selection(hit)
	_parcel_panel.show_parcel(hit, _lots.get_district_for_hit(hit))
	_position_parcel_panel()
	_focus_parcel(hit)
	_sync_supply_chain_blocks()


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
	# Certificate reparents to the scene root — without this, map clicks steal dismiss input.
	if _certificate_modal != null and _certificate_modal.visible:
		return true
	var hovered: Control = get_viewport().gui_get_hovered_control()
	if hovered == null:
		return false
	if _top_bar and (_top_bar == hovered or _top_bar.is_ancestor_of(hovered)):
		return true
	if _advance_button != null and (_advance_button == hovered or _advance_button.is_ancestor_of(hovered)):
		return true
	if _sc_path_controls != null and _sc_path_controls.visible and (
		_sc_path_controls == hovered or _sc_path_controls.is_ancestor_of(hovered)
	):
		return true
	if _portfolio_sidebar != null and _portfolio_sidebar.visible:
		var mouse := get_viewport().get_mouse_position()
		if _portfolio_sidebar.get_global_rect().has_point(mouse):
			return true
	if hovered is BaseButton:
		return true
	if _parcel_panel.visible and _parcel_panel.is_ancestor_of(hovered):
		return true
	return false


func _update_hover() -> void:
	_sync_supply_chain_blocks()
	if _negotiation_panel != null and _negotiation_panel.visible:
		_lots.set_hover({})
		_hide_sc_route_tooltip()
		return
	if _community_chat_panel != null and _community_chat_panel.visible:
		_lots.set_hover({})
		_hide_sc_route_tooltip()
		return
	if _pointer_over_ui():
		_lots.set_hover({})
		_hide_sc_route_tooltip()
		return
	var hit: Dictionary = _lots.pick_at_world_pos(_world_mouse())
	_lots.set_hover(hit)
	_update_sc_route_tooltip()


func _handle_map_click() -> void:
	var hit: Dictionary = _lots.pick_at_world_pos(_world_mouse())
	if not hit.is_empty():
		var district_id := str(hit.get("district_id", _focus_district_id))
		if _view_mode == "overview":
			_focus_district(district_id)
			hit = _lots.pick_at_world_pos(_world_mouse())
		var viz_second_click := false
		if (
			_supply_chain != null
			and _supply_chain.has_method("is_enabled")
			and _supply_chain.is_enabled()
			and not hit.is_empty()
		):
			if _supply_chain.handle_parcel_click(hit):
				_parcel_panel.hide_panel()
				_sync_supply_chain_blocks()
				return
			# Second click on same parcel — open normal panel while keeping viz on.
			viz_second_click = true
		var current: Dictionary = _lots.get_selection()
		if (
			not viz_second_click
			and not current.is_empty()
			and str(hit.get("id", "")) == str(current.get("id", ""))
			and str(hit.get("district_id", "")) == str(current.get("district_id", ""))
		):
			_lots.clear_selection()
			_parcel_panel.hide_panel()
			_sync_supply_chain_blocks()
			return
		_lots.set_selection(hit)
		if _Bank.is_bank_parcel(hit):
			_parcel_panel.hide_panel()
			_bank_modal.open_bank()
		else:
			_parcel_panel.show_parcel(hit, _lots.get_district_for_hit(hit))
			_position_parcel_panel()
			_focus_parcel(hit)
		_sync_supply_chain_blocks()
		return

	var district_entry: Dictionary = _World.find_district_at_point(_region, _world_mouse(), _lots.get_region_offset())
	if district_entry.is_empty():
		_lots.clear_selection()
		_parcel_panel.hide_panel()
		_sync_supply_chain_blocks()
		return

	var empty_district_id: String = _World.district_id(district_entry)
	if not _Unlock.is_unlocked(Game.state, empty_district_id):
		_show_locked_district(district_entry)
		return

	if _view_mode == "overview":
		_focus_district(empty_district_id)
	else:
		_lots.clear_selection()
		_parcel_panel.hide_panel()
		_sync_supply_chain_blocks()


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
	_refresh_title(true)
	FeedbackBus.panel_swipe(_title, true)
	_sync_supply_chain_district()


func _go_to_overview(animate: bool = true) -> void:
	if _supply_chain != null and _supply_chain.has_method("is_enabled") and _supply_chain.is_enabled():
		_supply_chain.disable_view()
		_refresh_supply_chain_toggle()
	_camera_mode = "district"
	_view_mode = "overview"
	_apply_view_context()
	_update_camera_targets()
	_refresh_title(true)
	if animate:
		FeedbackBus.panel_swipe(_title, false)
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


func _map_focus_rect() -> Rect2:
	var view_size := get_viewport_rect().size
	var top_y := _top_bar_bottom_y()
	var side_margin := 16.0
	var bottom_margin := ADVANCE_BUTTON_RESERVE
	var left_x := side_margin
	if _portfolio_sidebar != null and _portfolio_sidebar.visible:
		var pp_width := 272.0
		if _portfolio_sidebar.has_method("expanded_width"):
			pp_width = float(_portfolio_sidebar.call("expanded_width"))
		left_x = side_margin + pp_width
	var right_x := view_size.x - side_margin
	if _parcel_panel != null and _parcel_panel.visible:
		right_x = view_size.x - side_margin - 300.0
	return Rect2(
		left_x,
		top_y,
		maxf(right_x - left_x, 1.0),
		maxf(view_size.y - top_y - bottom_margin, 1.0),
	)


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
	var focus_rect := _map_focus_rect()
	var usable_w := focus_rect.size.x
	var usable_h := focus_rect.size.y
	var bounds_w := maxf(bounds.size.x, 1.0)
	var bounds_h := maxf(bounds.size.y, 1.0)
	var zoom_val := minf(usable_w / bounds_w, usable_h / bounds_h) * PARCEL_FOCUS_FILL
	zoom_val = clampf(zoom_val, MIN_ZOOM, MAX_ZOOM)

	var diamond: Vector2 = frame.get("diamond_size", bounds.size)
	var focus_center := focus_rect.position + focus_rect.size * 0.5
	var screen_target := focus_center + Vector2(
		-diamond.x * zoom_val * 0.5,
		diamond.y * zoom_val * 0.5,
	)
	_camera_mode = "parcel"
	_camera_target_zoom = Vector2(zoom_val, zoom_val)
	_camera_target_pos = center - (screen_target - viewport_center) / zoom_val


func _restore_district_camera() -> void:
	if _camera_mode != "parcel":
		return
	_camera_mode = "district"
	_update_camera_targets()


func _refresh_title(fade: bool = false) -> void:
	if _view_mode == "overview":
		_title.text = "Capital Farm Valley — Overview"
	else:
		var entry: Dictionary = _World.find_entry_by_id(_region, _focus_district_id)
		var district: Dictionary = _World.load_district_from_entry(entry)
		_title.text = "D%d · %s" % [int(entry.get("index", 0)), str(district.get("name", "District"))]
	if fade and _title != null:
		_title.modulate.a = 0.0
		var tween := create_tween()
		tween.tween_property(_title, "modulate:a", 1.0, 0.28).set_ease(Tween.EASE_OUT)


func _on_selection_cleared() -> void:
	_parcel_panel.hide_panel()
	_restore_district_camera()
	_sync_supply_chain_blocks()


func _on_panel_closed() -> void:
	if _lots != null:
		_lots.clear_selection()
	_sync_supply_chain_blocks()


func _setup_supply_chain_view() -> void:
	_supply_chain_routes = Node2D.new()
	_supply_chain_routes.name = "SupplyChainRoutes"
	_supply_chain_routes.z_index = 4
	_supply_chain_routes.set_script(_SupplyChainRouteLayer)
	_world.add_child(_supply_chain_routes)
	_supply_chain = Node.new()
	_supply_chain.name = "SupplyChainView"
	_supply_chain.set_script(_SupplyChainController)
	add_child(_supply_chain)
	_supply_chain.configure(_lots, _supply_chain_routes)
	_supply_chain.message_requested.connect(_on_supply_chain_message)
	_supply_chain.enabled_changed.connect(_on_supply_chain_enabled_changed)
	_supply_chain.path_info_changed.connect(_on_supply_chain_path_info)
	_supply_chain_toggle.pressed.connect(_on_supply_chain_toggle_pressed)
	if _sc_path_controls != null:
		_sc_path_controls.prev_pressed.connect(func() -> void:
			if _supply_chain != null and _supply_chain.has_method("show_previous_path"):
				_supply_chain.show_previous_path()
		)
		_sc_path_controls.next_pressed.connect(func() -> void:
			if _supply_chain != null and _supply_chain.has_method("show_next_path"):
				_supply_chain.show_next_path()
		)
		_sc_path_controls.pause_toggled.connect(_on_sc_path_pause_toggled)
		_sc_path_controls.controls_hover_changed.connect(_on_sc_controls_hover_changed)
	_refresh_supply_chain_toggle()


func _on_supply_chain_toggle_pressed() -> void:
	if _view_mode != "district":
		# Mode is district-scoped — jump into the focused district first.
		if not _focus_district_id.is_empty():
			_focus_district(_focus_district_id)
	_sync_supply_chain_district()
	var preferred := ""
	var sel: Dictionary = _lots.get_selection() if _lots != null else {}
	preferred = str(sel.get("id", ""))
	_supply_chain.toggle_view(preferred)
	_refresh_supply_chain_toggle()
	_sync_supply_chain_blocks()


func _on_supply_chain_enabled_changed(on: bool) -> void:
	_refresh_supply_chain_toggle()
	if on:
		_parcel_panel.hide_panel()
	else:
		if _sc_path_controls != null and _sc_path_controls.has_method("hide_controls"):
			_sc_path_controls.hide_controls()
		_hide_sc_route_tooltip()
	_sync_supply_chain_blocks()


func _on_supply_chain_path_info(index: int, total: int, paused: bool) -> void:
	if _sc_path_controls == null:
		return
	if _supply_chain == null or not _supply_chain.is_enabled():
		_sc_path_controls.hide_controls()
		return
	_sc_path_controls.set_path_info(index, total, paused)


func _on_sc_path_pause_toggled(paused: bool) -> void:
	if _supply_chain == null:
		return
	if paused:
		_supply_chain.pause_cycling()
	else:
		_supply_chain.resume_cycling()


func _on_sc_controls_hover_changed(hovered: bool) -> void:
	if _supply_chain != null and _supply_chain.has_method("set_blocked"):
		_supply_chain.set_blocked("controls_hover", hovered)


func _on_supply_chain_message(text: String) -> void:
	if text.strip_edges().is_empty():
		return
	FeedbackBus.show_chip(text, _supply_chain_toggle, 2.0)


func _refresh_supply_chain_toggle() -> void:
	if _supply_chain_toggle == null:
		return
	var on: bool = (
		_supply_chain != null
		and _supply_chain.has_method("is_enabled")
		and bool(_supply_chain.is_enabled())
	)
	_supply_chain_toggle.tooltip_text = "Hide Supply Chain" if on else "Supply Chain"
	_supply_chain_toggle.modulate = Color(1.15, 1.05, 0.55, 1.0) if on else Color(1, 1, 1, 1)


func _sync_supply_chain_blocks() -> void:
	if _supply_chain == null or not _supply_chain.has_method("set_blocked"):
		return
	if not _supply_chain.is_enabled():
		return
	var panel_open := _parcel_panel != null and _parcel_panel.visible
	var modal_open := _any_blocking_modal_open()
	var game_paused := get_tree() != null and get_tree().paused
	_supply_chain.set_blocked("panel", panel_open)
	_supply_chain.set_blocked("modal", modal_open)
	_supply_chain.set_blocked("game_pause", game_paused)


func _any_blocking_modal_open() -> bool:
	if _negotiation_panel != null and _negotiation_panel.visible:
		return true
	if _community_chat_panel != null and _community_chat_panel.visible:
		return true
	if _certificate_modal != null and _certificate_modal.visible:
		return true
	if _improve_panel != null and _improve_panel.visible:
		return true
	if _bank_modal != null and _bank_modal.visible:
		return true
	if _edge_modal != null and _edge_modal.visible:
		return true
	if _shortage_modal != null and _shortage_modal.visible:
		return true
	if _turn_debrief_modal != null and _turn_debrief_modal.visible:
		return true
	return false


func _update_sc_route_tooltip() -> void:
	if (
		_sc_route_tooltip == null
		or _sc_route_tooltip_label == null
		or _supply_chain == null
		or not _supply_chain.is_enabled()
	):
		_hide_sc_route_tooltip()
		return
	var hit: Dictionary = _lots.get_hover() if _lots != null and _lots.has_method("get_hover") else {}
	if hit.is_empty():
		hit = _lots.pick_at_world_pos(_world_mouse()) if _lots != null else {}
	var on_route := false
	if _supply_chain.has_method("tooltip_at_world"):
		on_route = not _supply_chain.tooltip_at_world(_world_mouse()).is_empty()
	if hit.is_empty() and not on_route:
		_hide_sc_route_tooltip()
		return
	if not _supply_chain.has_method("chain_hover_info"):
		_hide_sc_route_tooltip()
		return
	var info: Dictionary = _supply_chain.chain_hover_info()
	if info.is_empty():
		_hide_sc_route_tooltip()
		return
	_ensure_sc_tooltip_style()
	_sc_route_tooltip_label.text = _format_sc_chain_tooltip(info)
	_sc_route_tooltip.visible = true
	_sc_route_tooltip.reset_size()
	var screen := get_viewport().get_mouse_position()
	var tip_size := _sc_route_tooltip.size
	if tip_size.x < 8.0:
		tip_size = _sc_route_tooltip.get_combined_minimum_size()
	var vp := get_viewport_rect().size
	var pos := screen + Vector2(18, 20)
	pos.x = minf(pos.x, vp.x - tip_size.x - 12.0)
	pos.y = minf(pos.y, vp.y - tip_size.y - 12.0)
	_sc_route_tooltip.position = pos


func _format_sc_chain_tooltip(info: Dictionary) -> String:
	const LIGHT := "#ffb85c"
	const DARK := "#e86a14"
	var parts: PackedStringArray = PackedStringArray()
	var prev: Dictionary = info.get("prev", {})
	var selected: Dictionary = info.get("selected", {})
	var next: Dictionary = info.get("next", {})
	if not prev.is_empty():
		parts.append(_sc_tooltip_node_bbcode(prev, LIGHT, true))
	if not selected.is_empty():
		parts.append(_sc_tooltip_node_bbcode(selected, DARK, false))
	if not next.is_empty():
		parts.append(_sc_tooltip_node_bbcode(next, LIGHT, true))
	return " → ".join(parts)


func _sc_tooltip_node_bbcode(node: Dictionary, color_hex: String, show_profit: bool) -> String:
	const LOSS := "#e05040"
	var name := str(node.get("name", "?"))
	var text := "[color=%s]%s[/color]" % [color_hex, name]
	# Acquisition upside only for businesses the player does not already own.
	if show_profit and not bool(node.get("owned", false)):
		var profit := int(node.get("profit", 0))
		if profit > 0:
			text += "[color=%s] +%s[/color]" % [color_hex, MathUtil.fmt_money(profit)]
		elif profit < 0:
			text += "[color=%s] %s[/color]" % [LOSS, MathUtil.fmt_money(profit)]
	return text


func _ensure_sc_tooltip_style() -> void:
	if _sc_route_tooltip == null or _sc_route_tooltip.has_meta("_styled"):
		return
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.14, 0.12, 0.94)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(0)
	style.border_color = Color(0.42, 0.48, 0.38, 0.85)
	style.set_border_width_all(1)
	_sc_route_tooltip.add_theme_stylebox_override("panel", style)
	_sc_route_tooltip.set_meta("_styled", true)


func _hide_sc_route_tooltip() -> void:
	if _sc_route_tooltip != null:
		_sc_route_tooltip.visible = false


func _sync_supply_chain_district() -> void:
	if _supply_chain == null or not _supply_chain.has_method("set_district_context"):
		return
	if _view_mode != "district" or _focus_district_id.is_empty():
		return
	var entry: Dictionary = _World.find_entry_by_id(_region, _focus_district_id)
	if entry.is_empty():
		return
	var district: Dictionary = _World.load_district_from_entry(entry)
	_supply_chain.set_district_context(_focus_district_id, district)


func _on_overview_pressed() -> void:
	if _supply_chain != null and _supply_chain.has_method("is_enabled") and _supply_chain.is_enabled():
		_supply_chain.disable_view()
		_refresh_supply_chain_toggle()
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


func _style_icon_button(button: Button) -> void:
	if button == null:
		return
	button.text = ""
	button.flat = true
	button.expand_icon = true
	button.custom_minimum_size = Vector2(36, 36)
	button.add_theme_constant_override("icon_max_width", 22)


func _refresh_district_lock_toggle() -> void:
	if _district_lock_toggle == null or Game.state == null:
		return
	_district_lock_toggle.text = ""
	if Game.state.district_unlock_dev_bypass:
		_district_lock_toggle.icon = _ICON_LOCK_OPEN
		_district_lock_toggle.tooltip_text = "Enforce district locks"
	else:
		_district_lock_toggle.icon = _ICON_LOCK
		_district_lock_toggle.tooltip_text = "Unlock all districts (test)"


func _on_run_bootstrap(_state: RunState) -> void:
	_bootstrap_map()


func _on_turn_advanced(_state: RunState) -> void:
	_refresh_hud()
	_refresh_parcels()
	_refresh_selected_parcel()


func _on_turn_debrief_ready(_state: RunState, _debrief: Dictionary) -> void:
	_maybe_show_turn_debrief()


func _on_districts_unlocked(_state: RunState, district_ids: Array) -> void:
	_refresh_terrain()
	_refresh_parcels()
	if district_ids.is_empty():
		return
	FeedbackBus.celebrate_acquisition()
	var names: PackedStringArray = []
	for id_variant in district_ids:
		var entry: Dictionary = _World.find_entry_by_id(_region, str(id_variant))
		var district: Dictionary = _World.load_district_from_entry(entry)
		var dname := str(district.get("name", id_variant))
		if not dname.is_empty():
			names.append(dname)
	var banner := "District unlocked: %s" % ", ".join(names) if not names.is_empty() else "New district unlocked"
	FeedbackBus.show_chip(banner, _title, 2.6)
	FeedbackBus.pulse(_title, 1.08, 0.3)


func _on_map_state_changed(_state: RunState) -> void:
	_refresh_hud()
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
	_sync_supply_chain_blocks()


func _on_modal_closed_refresh_parcels() -> void:
	_refresh_hud()
	_refresh_parcels()
	_refresh_selected_parcel()
	_sync_supply_chain_blocks()


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
	if _supply_chain != null and _supply_chain.has_method("is_enabled") and _supply_chain.is_enabled():
		_sync_supply_chain_district()
		_supply_chain.rebuild(true)


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


func _economy_snapshot() -> Dictionary:
	if Game.state == null:
		return {"cash": 0, "ap": 0, "nw": 0}
	return {
		"cash": Game.state.cash,
		"ap": Game.state.action_points,
		"nw": FinanceSystem.net_worth(Game.state),
	}


func _emit_economy_deltas(before: Dictionary) -> void:
	if Game.state == null:
		return
	var cash_delta: int = Game.state.cash - int(before.get("cash", Game.state.cash))
	var ap_delta: int = Game.state.action_points - int(before.get("ap", Game.state.action_points))
	var nw_delta: int = FinanceSystem.net_worth(Game.state) - int(before.get("nw", 0))
	if cash_delta != 0:
		FeedbackBus.cash_delta(cash_delta, _run_stats)
	if ap_delta != 0:
		FeedbackBus.ap_delta(ap_delta, _run_stats)
	# Big portfolio moves get a NW punch (stand-in for sparkline pulse).
	if absi(nw_delta) >= 5000:
		FeedbackBus.pulse(_run_stats, 1.06, 0.28)
		FeedbackBus.float_text_near(_run_stats, "NW %s%s" % ["+" if nw_delta > 0 else "-", MathUtil.fmt_money(absi(nw_delta))], Color(0.7, 0.85, 1.0, 1.0))
	_refresh_hud()


func _float_ownership_at_parcel(entry: Dictionary, price: int) -> void:
	if entry.is_empty():
		return
	var label := "Owned · %s" % MathUtil.fmt_money(price)
	var color := Color(1.0, 0.86, 0.35, 1.0)
	if _parcel_panel != null and _parcel_panel.visible:
		FeedbackBus.float_text_near(_parcel_panel, label, color)
		return
	if _lots == null:
		return
	var frame: Dictionary = _lots.get_parcel_frame(entry)
	if frame.is_empty():
		return
	var world_center: Vector2 = frame.get("center", Vector2.ZERO)
	var screen: Vector2 = get_viewport().get_canvas_transform() * world_center
	FeedbackBus.float_text(label, screen, color)


func _deny_with_reason(reason: String) -> void:
	FeedbackBus.deny(_parcel_panel)
	if not reason.strip_edges().is_empty():
		FeedbackBus.show_chip(reason, _parcel_panel if _parcel_panel != null else _run_stats, 2.0)
		FeedbackBus.toast_error(reason)


func _show_what_changed_chip(before: Dictionary, result: Dictionary) -> void:
	if Game.state == null:
		return
	var cash_delta: int = Game.state.cash - int(before.get("cash", Game.state.cash))
	var ap_delta: int = Game.state.action_points - int(before.get("ap", Game.state.action_points))
	var name := ""
	if result.get("business") is BusinessInstance:
		name = (result.get("business") as BusinessInstance).name
	elif typeof(result.get("realEstate")) == TYPE_DICTIONARY:
		name = str((result.get("realEstate") as Dictionary).get("name", "Property"))
	var bits: PackedStringArray = []
	if not name.is_empty():
		bits.append(name)
	if cash_delta != 0:
		bits.append("%s%s" % ["+" if cash_delta > 0 else "-", MathUtil.fmt_money(absi(cash_delta))])
	if ap_delta != 0:
		bits.append("%+d AP" % ap_delta)
	bits.append("parcel owned")
	FeedbackBus.show_chip("What changed: %s" % " · ".join(bits), _run_stats, 2.4)


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
	if _quit_confirm == null:
		_quit_confirm = ConfirmationDialog.new()
		_quit_confirm.title = "Leave run"
		_quit_confirm.dialog_text = "Are you sure you want to quit?"
		_quit_confirm.ok_button_text = "Quit"
		_quit_confirm.cancel_button_text = "Cancel"
		_quit_confirm.unresizable = true
		add_child(_quit_confirm)
		_quit_confirm.confirmed.connect(_on_quit_confirmed)
	_quit_confirm.popup_centered()


func _on_quit_confirmed() -> void:
	Game.go_to_main_menu()
