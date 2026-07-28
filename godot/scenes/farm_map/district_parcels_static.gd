extends Node2D

const _Grid := preload("res://scenes/farm_map/iso_grid_math.gd")
const _Layout := preload("res://scenes/farm_map/district_layout_data.gd")
const _World := preload("res://scenes/farm_map/world_layout_data.gd")
const _Ownership := preload("res://core/systems/parcel_ownership_system.gd")
const _Bank := preload("res://core/systems/bank_system.gd")
const _Unlock := preload("res://core/systems/district_unlock_system.gd")

const ROLE_COLORS := {
	"core": Color(0.95, 0.92, 0.78, 0.92),
	"specialization": Color(0.92, 0.90, 0.72, 0.90),
	"competitive": Color(0.96, 0.82, 0.72, 0.92),
	"premium": Color(0.98, 0.88, 0.55, 0.94),
	"development": Color(0.88, 0.90, 0.94, 0.88),
		"civic": Color(0.82, 0.88, 0.98, 0.92),
		"bank": Color(0.88, 0.92, 0.62, 0.94),
		"plaza": Color(0.78, 0.92, 0.68, 0.92),
}

const BUILDING_COLOR := Color(0.72, 0.58, 0.38, 0.85)
const PLAYER_OUTLINE := Color(0.20, 0.72, 1.0, 1.0)
const LABEL_COLOR := Color(0.98, 0.97, 0.92, 0.96)
const LABEL_SHADOW := Color(0.08, 0.12, 0.08, 0.75)
const LOCKED_SILHOUETTE := Color(0.22, 0.24, 0.28, 0.55)
const LOCKED_TEXT := Color(0.88, 0.90, 0.94, 0.95)

const OWNER_TINTS := {
	"player": Color(0.35, 0.78, 0.45, 0.30),
	"npc": Color(0.52, 0.46, 0.40, 0.16),
	"vacant": Color(0.62, 0.66, 0.72, 0.24),
	"civic": Color(0.42, 0.54, 0.82, 0.18),
	"bank": Color(0.62, 0.78, 0.42, 0.24),
}

var _region: Dictionary = {}
var _region_offset := Vector2.ZERO
var _font: Font
var _view_mode := "overview"
var _focus_district_id := ""
var _district_bundles: Array = []


func configure(region: Dictionary, region_offset: Vector2, font: Font) -> void:
	_region = region
	_region_offset = region_offset
	_font = font
	_rebuild_district_bundles()
	queue_redraw()


func set_view_context(view_mode: String, focus_district_id: String) -> void:
	_view_mode = view_mode
	_focus_district_id = focus_district_id
	queue_redraw()


func refresh_ownership() -> void:
	queue_redraw()


func get_district_bundles() -> Array:
	return _district_bundles


func _rebuild_district_bundles() -> void:
	_district_bundles.clear()
	for entry_variant in _World.district_entries(_region):
		if typeof(entry_variant) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = entry_variant
		var district: Dictionary = _World.load_district_from_entry(entry)
		if district.is_empty():
			continue
		_district_bundles.append({
			"entry": entry,
			"district": district,
			"district_id": _World.district_id(entry),
			"origin": _World.world_tile_origin(entry),
		})


func _draw() -> void:
	for bundle_variant in _district_bundles:
		var bundle: Dictionary = bundle_variant
		var entry: Dictionary = bundle.get("entry", {})
		var district: Dictionary = bundle.get("district", {})
		var district_id: String = str(bundle.get("district_id", ""))
		var origin: Vector2i = bundle.get("origin", Vector2i.ZERO)
		var locked := not _Unlock.is_unlocked(Game.state, district_id)
		var dimmed := _should_dim_district(district_id)
		if locked:
			_draw_locked_district(entry, district, origin)
		else:
			_draw_district(entry, district, origin, dimmed)


func _should_dim_district(district_id: String) -> bool:
	if _view_mode != "district" or _focus_district_id.is_empty():
		return false
	return district_id != _focus_district_id


func _draw_district(entry: Dictionary, district: Dictionary, origin: Vector2i, dimmed: bool) -> void:
	var lot_tiles: int = int(district.get("lot_tiles", _Layout.LOT_TILES))
	var building_tiles: int = int(district.get("building_tiles", _Layout.BUILDING_TILES))
	var road_gap: int = _Layout.road_gap_for(district)
	var alpha_mult := 0.45 if dimmed else 1.0

	for parcel_variant in district.get("parcels", []):
		if typeof(parcel_variant) != TYPE_DICTIONARY:
			continue
		var parcel: Dictionary = parcel_variant
		var lot_rect := _world_lot_rect(parcel, district, origin)
		var role := str(parcel.get("role", "core"))
		var owner_state := _owner_state_for_entry(parcel, district)
		if owner_state in [_Ownership.OWNER_OPPORTUNITY, _Ownership.OWNER_CONTESTED]:
			continue
		var lot_color: Color = PLAYER_OUTLINE if owner_state == _Ownership.OWNER_PLAYER else ROLE_COLORS.get(role, ROLE_COLORS["core"])
		lot_color.a *= alpha_mult
		_draw_solid_outline(_Grid.tile_rect_outline(lot_rect, _region_offset), lot_color, 2.0)

		var building_rect := Rect2i()
		if role not in ["development", "civic", "bank"]:
			building_rect = _world_building_rect(parcel, district, origin, lot_tiles, building_tiles, road_gap)
			var build_color := PLAYER_OUTLINE if owner_state == _Ownership.OWNER_PLAYER else BUILDING_COLOR
			build_color.a *= alpha_mult
			_draw_solid_outline(_Grid.tile_rect_outline(building_rect, _region_offset), build_color, 1.5)

		if not dimmed:
			_draw_ownership_tint(lot_rect, building_rect, role, owner_state)
			var label := str(parcel.get("label", ""))
			if owner_state == _Ownership.OWNER_PLAYER:
				label = str(_Ownership.resolve(Game.state, parcel, district).get("operator_name", label))
			elif role == "bank":
				label = str(parcel.get("label", _Bank.BANK_LABEL))
			_draw_parcel_label(label, lot_rect)

	for plaza_variant in district.get("plazas", []):
		if typeof(plaza_variant) != TYPE_DICTIONARY:
			continue
		var plaza: Dictionary = plaza_variant
		var plaza_rect := _world_plaza_rect(plaza, district, origin, lot_tiles, road_gap)
		var plaza_color: Color = ROLE_COLORS["plaza"]
		plaza_color.a *= alpha_mult
		_draw_solid_outline(_Grid.tile_rect_outline(plaza_rect, _region_offset), plaza_color, 2.0)
		if not dimmed:
			var plaza_entry := _plaza_entry(district, plaza)
			var owner_state := _owner_state_for_entry(plaza_entry, district)
			_draw_ownership_tint(plaza_rect, plaza_rect, "plaza", owner_state)
			_draw_parcel_label(str(plaza.get("label", "Plaza")), plaza_rect)

	if not dimmed:
		_draw_district_title(entry, district, origin)


func _draw_locked_district(entry: Dictionary, district: Dictionary, origin: Vector2i) -> void:
	var bounds: Rect2i = _World.district_world_bounds(entry, district)
	var poly := _Grid.tile_rect_outline(bounds, _region_offset)
	if poly.size() >= 3:
		var fill_poly := PackedVector2Array(poly)
		fill_poly.remove_at(fill_poly.size() - 1)
		draw_colored_polygon(fill_poly, LOCKED_SILHOUETTE)
		for idx in poly.size() - 1:
			draw_line(poly[idx], poly[idx + 1], Color(0.14, 0.16, 0.20, 0.85), 2.0, true)

	var center: Vector2 = _World.district_center_screen(entry, district, _region_offset)
	var requirement: int = _Unlock.unlock_requirement(Game.state, entry)
	var lines: PackedStringArray = []
	lines.append("LOCKED")
	lines.append(str(district.get("name", "District")))
	lines.append("Net worth %s" % MathUtil.fmt_money(requirement))
	_draw_centered_text_block(center, lines)


func _draw_district_title(entry: Dictionary, district: Dictionary, _origin: Vector2i) -> void:
	var bounds: Rect2i = _World.district_world_bounds(entry, district)
	var top_center := _Grid.tile_rect_center(
		Rect2i(bounds.position.x, bounds.position.y, bounds.size.x, 1),
		_region_offset
	)
	var label := "D%d · %s" % [int(entry.get("index", 0)), str(district.get("name", ""))]
	var font_size := 13
	var text_size := _font.get_string_size(label, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
	var pos := top_center - Vector2(text_size.x * 0.5, text_size.y + 10.0)
	draw_string(_font, pos + Vector2(1.0, 1.0), label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, LABEL_SHADOW)
	draw_string(_font, pos, label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, LABEL_COLOR)


func _draw_centered_text_block(center: Vector2, lines: PackedStringArray) -> void:
	if _font == null:
		return
	var font_size := 14
	var lock_size := 28
	draw_string(_font, center + Vector2(-10.0, -36.0), "⛨", HORIZONTAL_ALIGNMENT_LEFT, -1, lock_size, LOCKED_TEXT)
	var y := center.y - 8.0
	for line in lines:
		var size := _font.get_string_size(line, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
		var pos := Vector2(center.x - size.x * 0.5, y)
		draw_string(_font, pos + Vector2(1.0, 1.0), line, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, LABEL_SHADOW)
		draw_string(_font, pos, line, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, LOCKED_TEXT)
		y += font_size + 4.0


func _draw_ownership_tint(
	lot_rect: Rect2i,
	building_rect: Rect2i,
	role: String,
	owner_state: String
) -> void:
	var tint: Color = OWNER_TINTS.get(owner_state, Color(0.0, 0.0, 0.0, 0.0))
	if tint.a <= 0.01:
		return
	var target_rect := lot_rect if role in ["development", "civic", "bank", "plaza"] else building_rect
	var poly := _Grid.tile_rect_outline(target_rect, _region_offset)
	if poly.size() < 3:
		return
	var fill_poly := PackedVector2Array(poly)
	fill_poly.remove_at(fill_poly.size() - 1)
	draw_colored_polygon(fill_poly, tint)


func _owner_state_for_entry(entry: Dictionary, district: Dictionary) -> String:
	if Game.state == null:
		return _Ownership.OWNER_NPC
	return str(_Ownership.resolve(Game.state, entry, district).get("state", _Ownership.OWNER_NPC))


func _world_lot_rect(entry: Dictionary, district: Dictionary, origin: Vector2i) -> Rect2i:
	var local := _Layout.lot_rect_for_entry(entry, district)
	return Rect2i(local.position + origin, local.size)


func _world_building_rect(
	entry: Dictionary,
	district: Dictionary,
	origin: Vector2i,
	lot_tiles: int,
	building_tiles: int,
	road_gap: int
) -> Rect2i:
	var local := _Layout.building_tile_rect(
		int(entry.get("parcel_x", 0)),
		int(entry.get("parcel_y", 0)),
		lot_tiles,
		building_tiles,
		road_gap
	)
	return Rect2i(local.position + origin, local.size)


func _world_plaza_rect(plaza: Dictionary, district: Dictionary, origin: Vector2i, lot_tiles: int, road_gap: int) -> Rect2i:
	var local := _Layout.tile_rect_for_parcel(
		int(plaza.get("parcel_x", 0)),
		int(plaza.get("parcel_y", 0)),
		lot_tiles,
		road_gap
	)
	return Rect2i(local.position + origin, local.size)


func _plaza_entry(district: Dictionary, plaza: Dictionary) -> Dictionary:
	var plaza_id := _Ownership.plaza_id_for(district, plaza)
	return {
		"id": plaza_id,
		"_plaza_key": plaza_id,
		"parcel_x": int(plaza.get("parcel_x", 0)),
		"parcel_y": int(plaza.get("parcel_y", 0)),
		"label": str(plaza.get("label", "Plaza")),
		"template_id": "",
		"role": "plaza",
	}


func _draw_parcel_label(text: String, lot_rect: Rect2i) -> void:
	if text.is_empty() or _font == null:
		return
	var center := _Grid.tile_rect_center(lot_rect, _region_offset)
	var font_size := 11
	var text_size := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
	var pos := center - Vector2(text_size.x * 0.5, text_size.y * 0.5 + 8.0)
	draw_string(_font, pos + Vector2(1.0, 1.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, LABEL_SHADOW)
	draw_string(_font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, LABEL_COLOR)


func _draw_solid_outline(outline: PackedVector2Array, color: Color, width: float) -> void:
	for idx in outline.size() - 1:
		draw_line(outline[idx], outline[idx + 1], color, width, true)
