extends Node2D

const _Grid := preload("res://scenes/farm_map/iso_grid_math.gd")
const _World := preload("res://scenes/farm_map/world_layout_data.gd")
const _Layout := preload("res://scenes/farm_map/district_layout_data.gd")
const _Unlock := preload("res://core/systems/district_unlock_system.gd")

enum TerrainKind { GRASS, MEADOW, FALLOW, DIRT_ROAD, PLAZA, BUILDING_PAD }

var _region: Dictionary = {}
var _region_offset := Vector2.ZERO
var _focus_district_id := ""
var _view_mode := "overview"
var _district_bundles: Array = []


func _ready() -> void:
	_region = _World.load_region()
	_region_offset = _World.region_center_offset(_region)
	_rebuild_district_bundles()
	queue_redraw()


func set_view_context(view_mode: String, focus_district_id: String) -> void:
	_view_mode = view_mode
	_focus_district_id = focus_district_id
	queue_redraw()


func set_region_offset(offset: Vector2) -> void:
	_region_offset = offset
	queue_redraw()


func refresh_map() -> void:
	queue_redraw()


func _rebuild_district_bundles() -> void:
	_district_bundles.clear()
	for entry_variant in _World.district_entries(_region):
		if typeof(entry_variant) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = entry_variant
		var district: Dictionary = _World.load_district_from_entry(entry)
		if district.is_empty():
			continue
		var origin: Vector2i = _World.world_tile_origin(entry)
		var local_bounds := _Layout.compute_tile_bounds(district)
		var sets: Dictionary = _Layout.collect_tile_sets(district)
		_district_bundles.append({
			"entry": entry,
			"district": district,
			"district_id": _World.district_id(entry),
			"origin": origin,
			"world_bounds": Rect2i(local_bounds.position + origin, local_bounds.size),
			"building_tiles": sets.get("building_tiles", {}),
			"plaza_tiles": sets.get("plaza_tiles", {}),
			"road_tiles": _Layout.compute_road_tiles(district),
		})


func _draw() -> void:
	if _district_bundles.is_empty():
		return
	for bundle_variant in _district_bundles:
		var bundle: Dictionary = bundle_variant
		var district_id: String = str(bundle.get("district_id", ""))
		var locked := not _Unlock.is_unlocked(Game.state, district_id)
		var dimmed := _should_dim_district(district_id)
		_draw_district_terrain(bundle, locked, dimmed)


func _should_dim_district(district_id: String) -> bool:
	if _view_mode != "district" or _focus_district_id.is_empty():
		return false
	return district_id != _focus_district_id


func _draw_district_terrain(bundle: Dictionary, locked: bool, dimmed: bool) -> void:
	var origin: Vector2i = bundle.get("origin", Vector2i.ZERO)
	var world_bounds: Rect2i = bundle.get("world_bounds", Rect2i())
	var building_tiles: Dictionary = bundle.get("building_tiles", {})
	var plaza_tiles: Dictionary = bundle.get("plaza_tiles", {})
	var road_tiles: Dictionary = bundle.get("road_tiles", {})

	for j in world_bounds.size.y:
		for i in world_bounds.size.x:
			var tx := world_bounds.position.x + i
			var ty := world_bounds.position.y + j
			var local_key := "%d,%d" % [tx - origin.x, ty - origin.y]
			var kind := _terrain_kind_at(local_key, building_tiles, road_tiles, plaza_tiles, tx, ty)
			var corners := _Grid.tile_corners(tx, ty, _region_offset)
			draw_colored_polygon(corners, _terrain_color(kind, tx, ty, locked, dimmed))


func _terrain_kind_at(
	local_key: String,
	building_tiles: Dictionary,
	road_tiles: Dictionary,
	plaza_tiles: Dictionary,
	tx: int,
	ty: int
) -> int:
	if building_tiles.has(local_key):
		return TerrainKind.BUILDING_PAD
	if road_tiles.has(local_key):
		return TerrainKind.DIRT_ROAD
	if plaza_tiles.has(local_key):
		return TerrainKind.PLAZA
	var hash_value := int(absi(tx * 928371 + ty * 689287)) % 997
	var n := float(hash_value) / 997.0
	if n < 0.06:
		return TerrainKind.MEADOW
	if n < 0.10:
		return TerrainKind.FALLOW
	return TerrainKind.GRASS


func _terrain_color(kind: int, tx: int, ty: int, locked: bool, dimmed: bool) -> Color:
	var flicker := (float((tx * 928371 + ty * 689287) % 97) / 97.0 - 0.5) * 0.04
	var color: Color
	match kind:
		TerrainKind.MEADOW:
			color = Color(0.34 + flicker, 0.58 + flicker, 0.30, 1.0)
		TerrainKind.FALLOW:
			color = Color(0.48 + flicker, 0.44 + flicker, 0.28, 1.0)
		TerrainKind.DIRT_ROAD:
			color = Color(0.56 + flicker, 0.42 + flicker, 0.24, 1.0)
		TerrainKind.PLAZA:
			color = Color(0.58 + flicker, 0.72 + flicker, 0.42, 1.0)
		TerrainKind.BUILDING_PAD:
			color = Color(0.44 + flicker, 0.50 + flicker, 0.30, 1.0)
		_:
			color = Color(0.30 + flicker, 0.52 + flicker, 0.24, 1.0)
	if locked:
		return Color(0.28, 0.30, 0.34, 0.92)
	if dimmed:
		return color.lerp(Color(0.45, 0.50, 0.44, 0.75), 0.45)
	return color
