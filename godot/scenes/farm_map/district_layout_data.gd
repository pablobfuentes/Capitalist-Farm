class_name DistrictLayoutData
extends RefCounted

const MEADOWGATE_PATH := "res://data/districts/meadowgate_commons.json"

const LOT_TILES := 3
const BUILDING_TILES := 2
const ROAD_GAP := 1

static var _district_cache: Dictionary = {}


static func clear_district_cache() -> void:
	_district_cache.clear()


static func load_district(path: String = MEADOWGATE_PATH) -> Dictionary:
	if _district_cache.has(path):
		return _district_cache[path]
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("DistrictLayoutData: missing %s" % path)
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	var district: Dictionary = parsed if typeof(parsed) == TYPE_DICTIONARY else {}
	_district_cache[path] = district
	return district


static func parcel_stride(lot_tiles: int = LOT_TILES, road_gap: int = ROAD_GAP) -> int:
	return lot_tiles + road_gap


static func road_gap_for(district: Dictionary) -> int:
	return int(district.get("road_gap", ROAD_GAP))


static func lot_tiles_for(district: Dictionary) -> int:
	return int(district.get("lot_tiles", LOT_TILES))


static func tile_rect_for_parcel(
	parcel_x: int,
	parcel_y: int,
	lot_tiles: int = LOT_TILES,
	road_gap: int = ROAD_GAP
) -> Rect2i:
	var stride := lot_tiles + road_gap
	return Rect2i(parcel_x * stride, parcel_y * stride, lot_tiles, lot_tiles)


static func building_tile_rect(
	parcel_x: int,
	parcel_y: int,
	lot_tiles: int = LOT_TILES,
	building_tiles: int = BUILDING_TILES,
	road_gap: int = ROAD_GAP
) -> Rect2i:
	var lot := tile_rect_for_parcel(parcel_x, parcel_y, lot_tiles, road_gap)
	var inset := (lot_tiles - building_tiles + 1) / 2
	return Rect2i(lot.position + Vector2i(inset, inset), Vector2i(building_tiles, building_tiles))


static func compute_tile_bounds(district: Dictionary) -> Rect2i:
	var lot_tiles := lot_tiles_for(district)
	var road_gap := road_gap_for(district)
	var min_x := 9999
	var min_y := 9999
	var max_x := -9999
	var max_y := -9999

	for parcel_variant in district.get("parcels", []):
		if typeof(parcel_variant) != TYPE_DICTIONARY:
			continue
		var parcel: Dictionary = parcel_variant
		var rect := tile_rect_for_parcel(
			int(parcel.get("parcel_x", 0)),
			int(parcel.get("parcel_y", 0)),
			lot_tiles,
			road_gap
		)
		min_x = mini(min_x, rect.position.x)
		min_y = mini(min_y, rect.position.y)
		max_x = maxi(max_x, rect.position.x + rect.size.x)
		max_y = maxi(max_y, rect.position.y + rect.size.y)

	for plaza_variant in district.get("plazas", []):
		if typeof(plaza_variant) != TYPE_DICTIONARY:
			continue
		var plaza: Dictionary = plaza_variant
		var rect := tile_rect_for_parcel(
			int(plaza.get("parcel_x", 0)),
			int(plaza.get("parcel_y", 0)),
			lot_tiles,
			road_gap
		)
		min_x = mini(min_x, rect.position.x)
		min_y = mini(min_y, rect.position.y)
		max_x = maxi(max_x, rect.position.x + rect.size.x)
		max_y = maxi(max_y, rect.position.y + rect.size.y)

	if min_x == 9999:
		return Rect2i(0, 0, 18, 14)

	var pad := road_gap + 1
	return Rect2i(min_x - pad, min_y - pad, max_x - min_x + pad * 2, max_y - min_y + pad * 2)


static func collect_tile_sets(district: Dictionary) -> Dictionary:
	var lot_tiles := lot_tiles_for(district)
	var road_gap := road_gap_for(district)
	var building_tiles: int = int(district.get("building_tiles", BUILDING_TILES))
	var parcel_tiles: Dictionary = {}
	var building_tiles_map: Dictionary = {}
	var plaza_tiles: Dictionary = {}

	for parcel_variant in district.get("parcels", []):
		if typeof(parcel_variant) != TYPE_DICTIONARY:
			continue
		var parcel: Dictionary = parcel_variant
		var role := str(parcel.get("role", "core"))
		var lot_rect := tile_rect_for_parcel(
			int(parcel.get("parcel_x", 0)),
			int(parcel.get("parcel_y", 0)),
			lot_tiles,
			road_gap
		)
		for j in lot_rect.size.y:
			for i in lot_rect.size.x:
				var key := "%d,%d" % [lot_rect.position.x + i, lot_rect.position.y + j]
				parcel_tiles[key] = role
		if role not in ["development", "civic", "bank"]:
			var build_rect := building_tile_rect(
				int(parcel.get("parcel_x", 0)),
				int(parcel.get("parcel_y", 0)),
				lot_tiles,
				building_tiles,
				road_gap
			)
			for j in build_rect.size.y:
				for i in build_rect.size.x:
					var bkey := "%d,%d" % [build_rect.position.x + i, build_rect.position.y + j]
					building_tiles_map[bkey] = true

	for plaza_variant in district.get("plazas", []):
		if typeof(plaza_variant) != TYPE_DICTIONARY:
			continue
		var plaza: Dictionary = plaza_variant
		var rect := tile_rect_for_parcel(
			int(plaza.get("parcel_x", 0)),
			int(plaza.get("parcel_y", 0)),
			lot_tiles,
			road_gap
		)
		for j in rect.size.y:
			for i in rect.size.x:
				var key := "%d,%d" % [rect.position.x + i, rect.position.y + j]
				plaza_tiles[key] = str(plaza.get("label", "Plaza"))

	return {
		"parcel_tiles": parcel_tiles,
		"building_tiles": building_tiles_map,
		"plaza_tiles": plaza_tiles,
	}


static func compute_road_tiles(district: Dictionary) -> Dictionary:
	var lot_tiles := lot_tiles_for(district)
	var road_gap := road_gap_for(district)
	var cells := _occupied_parcel_cells(district)
	var roads: Dictionary = {}

	for cell_key in cells.keys():
		var parts: PackedStringArray = cell_key.split(",")
		var px := int(parts[0])
		var py := int(parts[1])
		var rect := tile_rect_for_parcel(px, py, lot_tiles, road_gap)

		if cells.has("%d,%d" % [px + 1, py]):
			_stamp_vertical_gap(roads, rect, lot_tiles, road_gap)
		if cells.has("%d,%d" % [px, py + 1]):
			_stamp_horizontal_gap(roads, rect, lot_tiles, road_gap)

		_stamp_exterior_edge(roads, rect, cells, px, py, lot_tiles, road_gap)

	return roads


static func _occupied_parcel_cells(district: Dictionary) -> Dictionary:
	var cells: Dictionary = {}
	for parcel_variant in district.get("parcels", []):
		if typeof(parcel_variant) != TYPE_DICTIONARY:
			continue
		var parcel: Dictionary = parcel_variant
		cells["%d,%d" % [int(parcel.get("parcel_x", 0)), int(parcel.get("parcel_y", 0))]] = "parcel"
	for plaza_variant in district.get("plazas", []):
		if typeof(plaza_variant) != TYPE_DICTIONARY:
			continue
		var plaza: Dictionary = plaza_variant
		cells["%d,%d" % [int(plaza.get("parcel_x", 0)), int(plaza.get("parcel_y", 0))]] = "plaza"
	return cells


static func _stamp_vertical_gap(roads: Dictionary, left_rect: Rect2i, _lot_tiles: int, road_gap: int) -> void:
	var road_x := left_rect.position.x + left_rect.size.x
	for gy in road_gap:
		for y in range(left_rect.position.y, left_rect.position.y + left_rect.size.y):
			roads["%d,%d" % [road_x + gy, y]] = true


static func _stamp_horizontal_gap(roads: Dictionary, top_rect: Rect2i, _lot_tiles: int, road_gap: int) -> void:
	var road_y := top_rect.position.y + top_rect.size.y
	for gx in road_gap:
		for x in range(top_rect.position.x, top_rect.position.x + top_rect.size.x):
			roads["%d,%d" % [x, road_y + gx]] = true


static func _stamp_exterior_edge(
	roads: Dictionary,
	rect: Rect2i,
	cells: Dictionary,
	px: int,
	py: int,
	_lot_tiles: int,
	road_gap: int
) -> void:
	if not cells.has("%d,%d" % [px - 1, py]):
		for gy in rect.size.y:
			for gx in road_gap:
				roads["%d,%d" % [rect.position.x - road_gap + gx, rect.position.y + gy]] = true
	if not cells.has("%d,%d" % [px, py - 1]):
		for gx in rect.size.x:
			for gy in road_gap:
				roads["%d,%d" % [rect.position.x + gx, rect.position.y - road_gap + gy]] = true
	if not cells.has("%d,%d" % [px + 1, py]):
		for gy in rect.size.y:
			for gx in road_gap:
				roads["%d,%d" % [rect.position.x + rect.size.x + gx, rect.position.y + gy]] = true
	if not cells.has("%d,%d" % [px, py + 1]):
		for gx in rect.size.x:
			for gy in road_gap:
				roads["%d,%d" % [rect.position.x + gx, rect.position.y + rect.size.y + gy]] = true


static func all_selectables(district: Dictionary) -> Array:
	var entries: Array = []
	for parcel_variant in district.get("parcels", []):
		if typeof(parcel_variant) == TYPE_DICTIONARY:
			var entry: Dictionary = parcel_variant
			entries.append(entry.duplicate(true))
	for plaza_variant in district.get("plazas", []):
		if typeof(plaza_variant) != TYPE_DICTIONARY:
			continue
		var plaza: Dictionary = plaza_variant
		var district_id := str(district.get("id", "district"))
		entries.append({
			"id": "%s:plaza_%d_%d" % [district_id, int(plaza.get("parcel_x", 0)), int(plaza.get("parcel_y", 0))],
			"parcel_x": int(plaza.get("parcel_x", 0)),
			"parcel_y": int(plaza.get("parcel_y", 0)),
			"label": str(plaza.get("label", "Plaza")),
			"template_id": "",
			"role": "plaza",
			"kind": "plaza",
		})
	return entries


static func lot_rect_for_entry(entry: Dictionary, district: Dictionary) -> Rect2i:
	return tile_rect_for_parcel(
		int(entry.get("parcel_x", 0)),
		int(entry.get("parcel_y", 0)),
		lot_tiles_for(district),
		road_gap_for(district)
	)


static func find_selectable_at_point(district: Dictionary, world_point: Vector2, offset: Vector2) -> Dictionary:
	const _Grid := preload("res://scenes/farm_map/iso_grid_math.gd")
	var hits: Array = []
	for entry_variant in all_selectables(district):
		if typeof(entry_variant) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = entry_variant
		var lot_rect := lot_rect_for_entry(entry, district)
		if _Grid.point_in_tile_rect(world_point, lot_rect, offset):
			hits.append(entry)
	if hits.is_empty():
		return {}
	var best: Dictionary = hits[0]
	var best_screen_y := _Grid.tile_rect_center(lot_rect_for_entry(best, district), offset).y
	for entry_variant in hits:
		var entry: Dictionary = entry_variant
		var center_y := _Grid.tile_rect_center(lot_rect_for_entry(entry, district), offset).y
		if center_y > best_screen_y:
			best_screen_y = center_y
			best = entry
	return best

