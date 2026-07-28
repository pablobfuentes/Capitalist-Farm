extends Node2D
class_name DistrictParcels

signal parcel_selected(parcel: Dictionary)
signal selection_cleared

const _Grid := preload("res://scenes/farm_map/iso_grid_math.gd")
const _Layout := preload("res://scenes/farm_map/district_layout_data.gd")
const _World := preload("res://scenes/farm_map/world_layout_data.gd")
const _Unlock := preload("res://core/systems/district_unlock_system.gd")
const _StaticLayer := preload("res://scenes/farm_map/district_parcels_static.gd")
const _BuildingLayer := preload("res://scenes/farm_map/district_parcel_buildings.gd")
const _OverlayLayer := preload("res://scenes/farm_map/district_parcels_overlay.gd")

const OPPORTUNITY_BLINK_SPEED := 2.8

var _region: Dictionary = {}
var _region_offset := Vector2.ZERO
var _selected: Dictionary = {}
var _hover: Dictionary = {}
var _blink_phase := 0.0
var _focus_district_id := ""
var _view_mode := "overview"
var _pick_cache: Array = []
var _static_layer: Node2D
var _building_layer: Node2D
var _overlay_layer: Node2D


func _ready() -> void:
	_region = _World.load_region()
	_region_offset = _World.region_center_offset(_region)
	_static_layer = Node2D.new()
	_static_layer.name = "StaticParcels"
	_static_layer.set_script(_StaticLayer)
	add_child(_static_layer)
	_building_layer = Node2D.new()
	_building_layer.name = "BuildingArt"
	_building_layer.set_script(_BuildingLayer)
	add_child(_building_layer)
	_overlay_layer = Node2D.new()
	_overlay_layer.name = "OverlayParcels"
	_overlay_layer.z_index = 1
	_overlay_layer.set_script(_OverlayLayer)
	add_child(_overlay_layer)
	_static_layer.configure(_region, _region_offset, ThemeDB.fallback_font)
	_building_layer.configure(_region, _region_offset, _static_layer.get_district_bundles())
	_overlay_layer.configure(_region_offset, _static_layer.get_district_bundles(), ThemeDB.fallback_font)
	_rebuild_pick_cache()
	_update_blink_process()


func set_view_context(view_mode: String, focus_district_id: String) -> void:
	_view_mode = view_mode
	_focus_district_id = focus_district_id
	_static_layer.set_view_context(view_mode, focus_district_id)
	_building_layer.set_view_context(view_mode, focus_district_id)
	_overlay_layer.set_view_context(view_mode, focus_district_id)
	_rebuild_pick_cache()
	var terrain = get_parent().get_node_or_null("Terrain")
	if terrain != null and terrain.has_method("set_view_context"):
		terrain.set_view_context(view_mode, focus_district_id)


func set_region_offset(offset: Vector2) -> void:
	_region_offset = offset
	_static_layer.configure(_region, _region_offset, ThemeDB.fallback_font)
	_building_layer.configure(_region, _region_offset, _static_layer.get_district_bundles())
	_overlay_layer.configure(_region_offset, _static_layer.get_district_bundles(), ThemeDB.fallback_font)
	_rebuild_pick_cache()


func get_region_offset() -> Vector2:
	return _region_offset


func get_district_for_hit(hit: Dictionary) -> Dictionary:
	if typeof(hit.get("_district", {})) == TYPE_DICTIONARY:
		return hit.get("_district", {})
	return {}


func pick_at_world_pos(world_point: Vector2) -> Dictionary:
	var hits: Array = []
	for pick_variant in _pick_cache:
		var pick: Dictionary = pick_variant
		var lot_rect: Rect2i = pick.get("lot_rect", Rect2i())
		if not _Grid.point_in_lot_rect(world_point, lot_rect, _region_offset):
			continue
		hits.append(pick.get("hit", {}))
	if hits.is_empty():
		return {}
	var best: Dictionary = hits[0]
	var best_y := _parcel_screen_y(best)
	for hit_variant in hits:
		var hit: Dictionary = hit_variant
		var y := _parcel_screen_y(hit)
		if y > best_y:
			best_y = y
			best = hit
	return best


func get_parcel_frame(hit: Dictionary) -> Dictionary:
	if typeof(hit) != TYPE_DICTIONARY or hit.is_empty():
		return {}
	var district: Dictionary = hit.get("_district", {})
	var entry: Dictionary = hit.get("_region_entry", {})
	if district.is_empty() or entry.is_empty():
		return {}
	var lot_rect := _Layout.lot_rect_for_entry(hit, district)
	var origin := _World.world_tile_origin(entry)
	var world_rect := Rect2i(lot_rect.position + origin, lot_rect.size)
	return {
		"center": _Grid.tile_rect_center(world_rect, _region_offset),
		"bounds": _Grid.tile_rect_bounds(world_rect, _region_offset),
		"world_rect": world_rect,
	}


func get_selection() -> Dictionary:
	return _selected


func set_selection(entry: Dictionary) -> void:
	_selected = entry.duplicate(true) if typeof(entry) == TYPE_DICTIONARY else {}
	_overlay_layer.set_selection(_selected)
	if _selected.is_empty():
		selection_cleared.emit()
	else:
		parcel_selected.emit(_selected)


func clear_selection() -> void:
	if _selected.is_empty():
		return
	_selected = {}
	_overlay_layer.clear_selection()
	selection_cleared.emit()


func set_hover(entry: Dictionary) -> void:
	var next: Dictionary = entry.duplicate(true) if typeof(entry) == TYPE_DICTIONARY else {}
	if str(next.get("id", "")) == str(_hover.get("id", "")) and str(next.get("district_id", "")) == str(_hover.get("district_id", "")):
		return
	_hover = next
	_overlay_layer.set_hover(_hover)


func refresh_ownership() -> void:
	_static_layer.refresh_ownership()
	_building_layer.refresh_ownership()
	_overlay_layer.configure(_region_offset, _static_layer.get_district_bundles())
	_overlay_layer.refresh_ownership()
	_rebuild_pick_cache()
	_update_blink_process()


func _process(delta: float) -> void:
	if not is_processing():
		return
	_blink_phase += delta * OPPORTUNITY_BLINK_SPEED
	_overlay_layer.set_blink_phase(_blink_phase)
	_building_layer.set_blink_phase(_blink_phase)


func _rebuild_pick_cache() -> void:
	_pick_cache.clear()
	for bundle_variant in _static_layer.get_district_bundles():
		var bundle: Dictionary = bundle_variant
		var district_id: String = str(bundle.get("district_id", ""))
		if not _is_district_interactive(district_id):
			continue
		var entry: Dictionary = bundle.get("entry", {})
		var district: Dictionary = bundle.get("district", {})
		var origin: Vector2i = bundle.get("origin", Vector2i.ZERO)
		for selectable_variant in _Layout.all_selectables(district):
			if typeof(selectable_variant) != TYPE_DICTIONARY:
				continue
			var parcel_entry: Dictionary = selectable_variant
			var local_rect := _Layout.lot_rect_for_entry(parcel_entry, district)
			var world_rect := Rect2i(local_rect.position + origin, local_rect.size)
			var hit := parcel_entry.duplicate(true)
			hit["district_id"] = district_id
			hit["_district"] = district
			hit["_region_entry"] = entry
			_pick_cache.append({
				"lot_rect": world_rect,
				"hit": hit,
			})


func _update_blink_process() -> void:
	set_process(_overlay_layer.get_opportunity_count() > 0)
	if not is_processing():
		_blink_phase = 0.0


func _is_district_interactive(district_id: String) -> bool:
	if not _Unlock.is_unlocked(Game.state, district_id):
		return false
	if _view_mode == "district" and not _focus_district_id.is_empty() and district_id != _focus_district_id:
		return false
	return true


func _parcel_screen_y(hit: Dictionary) -> float:
	var district: Dictionary = hit.get("_district", {})
	var entry: Dictionary = hit.get("_region_entry", {})
	if district.is_empty():
		return 0.0
	var lot_rect := _Layout.lot_rect_for_entry(hit, district)
	var origin := _World.world_tile_origin(entry)
	var world_rect := Rect2i(lot_rect.position + origin, lot_rect.size)
	return _Grid.tile_rect_center(world_rect, _region_offset).y
