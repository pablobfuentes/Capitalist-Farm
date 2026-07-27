extends Control

const _World := preload("res://scenes/farm_map/world_layout_data.gd")
const _Unlock := preload("res://core/systems/district_unlock_system.gd")

@onready var _camera: Camera2D = $World/Camera2D
@onready var _world: Node2D = $World
@onready var _terrain = $World/Terrain
@onready var _lots: DistrictParcels = $World/Lots
@onready var _hud: Control = $UI/Hud
@onready var _top_bar: Control = $UI/Hud/TopBar
@onready var _title: Label = $UI/Hud/TopBar/Row/Title
@onready var _run_stats: Label = %RunStats
@onready var _overview_button: Button = %OverviewButton
@onready var _unlock_all_button: Button = %UnlockAllButton
@onready var _enforce_locks_button: Button = %EnforceLocksButton
@onready var _parcel_panel: PanelContainer = %ParcelBusinessPanel

const MIN_ZOOM := 0.18
const MAX_ZOOM := 2.0
const PAN_SPEED := 520.0
const OVERVIEW_ZOOM := 0.30
const DISTRICT_ZOOM := 0.92
const CAMERA_LERP := 7.0

var _region: Dictionary = {}
var _view_mode := "overview"
var _focus_district_id := "meadowgate_commons"
var _camera_target_pos := Vector2.ZERO
var _camera_target_zoom := Vector2(OVERVIEW_ZOOM, OVERVIEW_ZOOM)


func _ready() -> void:
	if Game.state == null:
		Game.go_to_main_menu()
		return
	_region = _World.load_region()
	_Unlock.ensure_initialized(Game.state)
	resized.connect(_center_world)
	_camera.make_current()
	_center_world()
	_lots.selection_cleared.connect(_on_selection_cleared)
	_parcel_panel.closed.connect(_on_panel_closed)
	EventBus.command_applied.connect(_on_run_state_changed)
	EventBus.turn_advanced.connect(_on_turn_advanced)
	EventBus.run_loaded.connect(_on_run_loaded)
	EventBus.asset_acquired.connect(_on_asset_acquired)
	_overview_button.pressed.connect(_on_overview_pressed)
	_unlock_all_button.pressed.connect(_on_unlock_all_pressed)
	_enforce_locks_button.pressed.connect(_on_enforce_locks_pressed)
	_apply_view_context()
	_go_to_overview(false)
	_refresh_map_state()


func _center_world() -> void:
	if _world == null:
		return
	_world.position = get_viewport_rect().size * 0.5
	_position_parcel_panel()
	_update_camera_targets()


func _position_parcel_panel() -> void:
	if _parcel_panel == null:
		return
	var view_size := get_viewport_rect().size
	_parcel_panel.offset_top = 96.0
	_parcel_panel.offset_bottom = minf(view_size.y - 24.0, 420.0)
	_parcel_panel.offset_right = -16.0
	_parcel_panel.offset_left = maxf(16.0, view_size.x - 316.0)


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
		_parcel_panel.show_parcel(hit, _lots.get_district_for_hit(hit))
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


func _focus_district(district_id: String) -> void:
	if district_id.is_empty() or not _Unlock.is_unlocked(Game.state, district_id):
		return
	_view_mode = "district"
	_focus_district_id = district_id
	if Game.state != null:
		Game.state.active_district_id = district_id
	_apply_view_context()
	_update_camera_targets()
	_refresh_title()


func _go_to_overview(animate: bool = true) -> void:
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


func _refresh_title() -> void:
	if _view_mode == "overview":
		_title.text = "Capital Farm Valley — Overview"
		return
	var entry: Dictionary = _World.find_entry_by_id(_region, _focus_district_id)
	var district: Dictionary = _World.load_district_from_entry(entry)
	_title.text = "D%d · %s" % [int(entry.get("index", 0)), str(district.get("name", "District"))]


func _on_selection_cleared() -> void:
	_parcel_panel.hide_panel()


func _on_panel_closed() -> void:
	if _lots != null:
		_lots.clear_selection()


func _on_overview_pressed() -> void:
	_go_to_overview()
	_lots.clear_selection()
	_parcel_panel.hide_panel()


func _on_unlock_all_pressed() -> void:
	_Unlock.unlock_all_for_testing(Game.state, _region)
	_refresh_map_state()


func _on_enforce_locks_pressed() -> void:
	_Unlock.lock_all_except_starter(Game.state)
	if not _Unlock.is_unlocked(Game.state, _focus_district_id):
		_go_to_overview()
	_refresh_map_state()


func _on_run_state_changed(_command_name: String = "", _state: RunState = null) -> void:
	_refresh_map_state()


func _on_turn_advanced(_state: RunState) -> void:
	_refresh_map_state()


func _on_run_loaded(_state: RunState) -> void:
	_refresh_map_state()


func _on_asset_acquired(_asset_type: String = "", _asset_id: String = "") -> void:
	_refresh_map_state()


func _refresh_map_state() -> void:
	if _lots == null:
		return
	_Unlock.refresh_auto_unlocks(Game.state, _region)
	_lots.refresh_ownership()
	if _terrain != null and _terrain.has_method("refresh_map"):
		_terrain.refresh_map()
	_refresh_run_hud()
	_refresh_title()
	if _parcel_panel.visible:
		var selected: Dictionary = _lots.get_selection()
		if not selected.is_empty():
			_parcel_panel.show_parcel(selected, _lots.get_district_for_hit(selected))


func _refresh_run_hud() -> void:
	if _run_stats == null or Game.state == null:
		return
	var s: RunState = Game.state
	_run_stats.text = "Turn %d · %s · NW %s · %d AP" % [
		s.turn,
		MathUtil.fmt_money(s.cash),
		MathUtil.fmt_money(FinanceSystem.net_worth(s)),
		s.action_points,
	]


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
