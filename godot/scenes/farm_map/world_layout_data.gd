class_name WorldLayoutData
extends RefCounted

const REGION_PATH := "res://data/world/capital_farm_region.json"
const GRID_GAP := 3

const DISTRICT_GRID: Dictionary = {
	"highland_terrace": Vector2i(0, 0),
	"northfield_heights": Vector2i(1, 0),
	"meadowgate_commons": Vector2i(0, 1),
	"ironwood_yard": Vector2i(1, 1),
	"riverbend_flats": Vector2i(0, 2),
	"sunmarket_row": Vector2i(1, 2),
}

const _Layout := preload("res://scenes/farm_map/district_layout_data.gd")
const _Grid := preload("res://scenes/farm_map/iso_grid_math.gd")


static func load_region(path: String = REGION_PATH) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("WorldLayoutData: missing %s" % path)
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	return apply_grid_layout(parsed)


static func district_entries(region: Dictionary = {}) -> Array:
	if region.is_empty():
		region = load_region()
	var entries: Array = []
	for entry_variant in region.get("districts", []):
		if typeof(entry_variant) == TYPE_DICTIONARY:
			entries.append(entry_variant)
	entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.get("index", 0)) < int(b.get("index", 0))
	)
	return entries


static func apply_grid_layout(region: Dictionary) -> Dictionary:
	if region.is_empty():
		return region
	var next_region: Dictionary = region.duplicate(true)
	var districts: Array = next_region.get("districts", [])
	var bounds_by_id: Dictionary = {}

	for entry_variant in districts:
		if typeof(entry_variant) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = entry_variant
		var id := district_id(entry)
		var district: Dictionary = load_district_from_entry(entry)
		if district.is_empty() or not DISTRICT_GRID.has(id):
			continue
		bounds_by_id[id] = _Layout.compute_tile_bounds(district)

	if not bounds_by_id.has("meadowgate_commons"):
		return next_region

	var mg_bounds: Rect2i = bounds_by_id["meadowgate_commons"]
	var anchor_origin := Vector2i(-mg_bounds.position.x, -mg_bounds.position.y)
	var origins: Dictionary = {"meadowgate_commons": anchor_origin}

	var col0_origin_x: int = anchor_origin.x
	var col0_world_max_x: int = col0_origin_x
	for id in bounds_by_id.keys():
		if int(DISTRICT_GRID[id].x) != 0:
			continue
		var local_bounds: Rect2i = bounds_by_id[id]
		col0_world_max_x = maxi(
			col0_world_max_x,
			col0_origin_x + local_bounds.position.x + local_bounds.size.x
		)

	var row1_world_max_y: int = anchor_origin.y + mg_bounds.position.y + mg_bounds.size.y

	for id in bounds_by_id.keys():
		if id == "meadowgate_commons":
			continue
		var slot: Vector2i = DISTRICT_GRID[id]
		if slot.y == 2:
			continue
		var local_bounds: Rect2i = bounds_by_id[id]
		var origin := Vector2i(
			col0_world_max_x + GRID_GAP - local_bounds.position.x if slot.x == 1 else col0_origin_x,
			-GRID_GAP - local_bounds.position.y - local_bounds.size.y if slot.y == 0 else anchor_origin.y
		)
		origins[id] = origin
		if slot.y == 1:
			row1_world_max_y = maxi(
				row1_world_max_y,
				origin.y + local_bounds.position.y + local_bounds.size.y
			)

	for id in bounds_by_id.keys():
		if int(DISTRICT_GRID[id].y) != 2:
			continue
		var local_bounds: Rect2i = bounds_by_id[id]
		var slot: Vector2i = DISTRICT_GRID[id]
		origins[id] = Vector2i(
			col0_world_max_x + GRID_GAP - local_bounds.position.x if slot.x == 1 else col0_origin_x,
			row1_world_max_y + GRID_GAP - local_bounds.position.y
		)

	for entry_variant in districts:
		if typeof(entry_variant) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = entry_variant
		var id := district_id(entry)
		if not origins.has(id):
			continue
		var origin: Vector2i = origins[id]
		entry["world_tile_origin"] = [origin.x, origin.y]

	return next_region


static func load_district_from_entry(entry: Dictionary) -> Dictionary:
	var path := str(entry.get("path", ""))
	if path.is_empty():
		return {}
	return _Layout.load_district(path)


static func world_tile_origin(entry: Dictionary) -> Vector2i:
	var raw: Variant = entry.get("world_tile_origin", [0, 0])
	if typeof(raw) != TYPE_ARRAY or (raw as Array).size() < 2:
		return Vector2i.ZERO
	var arr: Array = raw
	return Vector2i(int(arr[0]), int(arr[1]))


static func district_id(entry: Dictionary) -> String:
	return str(entry.get("district_id", ""))


static func unlock_net_worth(entry: Dictionary) -> int:
	return int(entry.get("unlock_net_worth", 0))


static func district_world_bounds(entry: Dictionary, district: Dictionary) -> Rect2i:
	var local_bounds := _Layout.compute_tile_bounds(district)
	var origin := world_tile_origin(entry)
	return Rect2i(local_bounds.position + origin, local_bounds.size)


static func compute_region_tile_bounds(region: Dictionary = {}) -> Rect2i:
	if region.is_empty():
		region = load_region()
	var min_x := 999999
	var min_y := 999999
	var max_x := -999999
	var max_y := -999999
	for entry_variant in district_entries(region):
		var entry: Dictionary = entry_variant
		var district := load_district_from_entry(entry)
		if district.is_empty():
			continue
		var bounds := district_world_bounds(entry, district)
		min_x = mini(min_x, bounds.position.x)
		min_y = mini(min_y, bounds.position.y)
		max_x = maxi(max_x, bounds.position.x + bounds.size.x)
		max_y = maxi(max_y, bounds.position.y + bounds.size.y)
	if min_x == 999999:
		return Rect2i(0, 0, 32, 32)
	return Rect2i(min_x, min_y, max_x - min_x, max_y - min_y)


static func region_center_offset(region: Dictionary = {}) -> Vector2:
	var bounds := compute_region_tile_bounds(region)
	var cx := float(bounds.position.x) + float(bounds.size.x) * 0.5
	var cy := float(bounds.position.y) + float(bounds.size.y) * 0.5
	return -_Grid.grid_to_screen(int(cx), int(cy))


static func district_center_screen(entry: Dictionary, district: Dictionary, region_offset: Vector2) -> Vector2:
	var bounds := district_world_bounds(entry, district)
	var cx := float(bounds.position.x) + float(bounds.size.x) * 0.5
	var cy := float(bounds.position.y) + float(bounds.size.y) * 0.5
	return _Grid.grid_to_screen(int(cx), int(cy)) + region_offset


static func local_to_world_tile(local_tile: Vector2i, entry: Dictionary) -> Vector2i:
	return local_tile + world_tile_origin(entry)


static func find_entry_by_id(region: Dictionary, district_id_value: String) -> Dictionary:
	for entry_variant in district_entries(region):
		var entry: Dictionary = entry_variant
		if district_id(entry) == district_id_value:
			return entry
	return {}


static func find_selectable_at_point(
	region: Dictionary,
	world_point: Vector2,
	region_offset: Vector2,
	is_district_interactive: Callable
) -> Dictionary:
	var hits: Array = []
	for entry_variant in district_entries(region):
		var entry: Dictionary = entry_variant
		var district_id_value := district_id(entry)
		if not bool(is_district_interactive.call(district_id_value)):
			continue
		var district := load_district_from_entry(entry)
		if district.is_empty():
			continue
		var origin := world_tile_origin(entry)
		for selectable_variant in _Layout.all_selectables(district):
			if typeof(selectable_variant) != TYPE_DICTIONARY:
				continue
			var parcel_entry: Dictionary = selectable_variant
			var local_rect := _Layout.lot_rect_for_entry(parcel_entry, district)
			var world_rect := Rect2i(local_rect.position + origin, local_rect.size)
			if not _Grid.point_in_tile_rect(world_point, world_rect, region_offset):
				continue
			var hit := parcel_entry.duplicate(true)
			hit["district_id"] = district_id_value
			hit["_district"] = district
			hit["_region_entry"] = entry
			hits.append(hit)
	if hits.is_empty():
		return {}
	var best: Dictionary = hits[0]
	var best_y := _parcel_screen_y(best, region_offset)
	for hit_variant in hits:
		var hit: Dictionary = hit_variant
		var y := _parcel_screen_y(hit, region_offset)
		if y > best_y:
			best_y = y
			best = hit
	return best


static func find_district_at_point(
	region: Dictionary,
	world_point: Vector2,
	region_offset: Vector2
) -> Dictionary:
	var best_entry: Dictionary = {}
	var best_y := -INF
	for entry_variant in district_entries(region):
		var entry: Dictionary = entry_variant
		var district := load_district_from_entry(entry)
		if district.is_empty():
			continue
		var bounds := district_world_bounds(entry, district)
		if not _point_in_world_bounds(world_point, bounds, region_offset):
			continue
		var center_y := district_center_screen(entry, district, region_offset).y
		if center_y > best_y:
			best_y = center_y
			best_entry = entry
	return best_entry


static func _parcel_screen_y(hit: Dictionary, region_offset: Vector2) -> float:
	var district: Dictionary = hit.get("_district", {})
	var entry: Dictionary = hit.get("_region_entry", {})
	if district.is_empty():
		return 0.0
	var lot_rect := _Layout.lot_rect_for_entry(hit, district)
	var origin := world_tile_origin(entry)
	var world_rect := Rect2i(lot_rect.position + origin, lot_rect.size)
	return _Grid.tile_rect_center(world_rect, region_offset).y


static func _point_in_world_bounds(world_point: Vector2, bounds: Rect2i, region_offset: Vector2) -> bool:
	for j in bounds.size.y:
		for i in bounds.size.x:
			var tx := bounds.position.x + i
			var ty := bounds.position.y + j
			var corners := _Grid.tile_corners(tx, ty, region_offset)
			if corners.size() >= 3 and Geometry2D.is_point_in_polygon(world_point, corners):
				return true
	return false
