extends Node2D

const _Grid := preload("res://scenes/farm_map/iso_grid_math.gd")
const _Layout := preload("res://scenes/farm_map/district_layout_data.gd")
const _World := preload("res://scenes/farm_map/world_layout_data.gd")
const _Ownership := preload("res://core/systems/parcel_ownership_system.gd")
const _Unlock := preload("res://core/systems/district_unlock_system.gd")

const ROLE_COLORS := {
	"core": Color(0.95, 0.92, 0.78, 0.92),
	"specialization": Color(0.92, 0.90, 0.72, 0.90),
	"competitive": Color(0.96, 0.82, 0.72, 0.92),
	"premium": Color(0.98, 0.88, 0.55, 0.94),
	"development": Color(0.88, 0.90, 0.94, 0.88),
	"civic": Color(0.82, 0.88, 0.98, 0.92),
	"bank": Color(0.88, 0.92, 0.62, 0.94),
}

const BUILDING_COLOR := Color(0.72, 0.58, 0.38, 0.85)
const SELECT_FILL := Color(1.0, 0.92, 0.35, 0.22)
const SELECT_OUTLINE := Color(1.0, 0.88, 0.20, 0.95)
const HOVER_FILL := Color(1.0, 1.0, 1.0, 0.12)
const HOVER_OUTLINE := Color(1.0, 1.0, 1.0, 0.55)
const OPPORTUNITY_OUTLINE := Color(1.0, 0.92, 0.12, 1.0)
const CONTESTED_OUTLINE := Color(1.0, 0.72, 0.18, 1.0)
const OPPORTUNITY_BLINK_MIN_ALPHA := 0.22
const OPPORTUNITY_BLINK_MAX_ALPHA := 1.0
const LABEL_COLOR := Color(0.98, 0.97, 0.92, 0.96)
const LABEL_SHADOW := Color(0.08, 0.12, 0.08, 0.75)

var _region_offset := Vector2.ZERO
var _font: Font
var _view_mode := "overview"
var _focus_district_id := ""
var _selected: Dictionary = {}
var _hover: Dictionary = {}
var _blink_phase := 0.0
var _district_bundles: Array = []
var _opportunity_entries: Array = []


func configure(region_offset: Vector2, district_bundles: Array, font: Font = null) -> void:
	_region_offset = region_offset
	_font = font if font != null else ThemeDB.fallback_font
	_district_bundles = district_bundles
	_rebuild_opportunity_entries()
	queue_redraw()


func set_view_context(view_mode: String, focus_district_id: String) -> void:
	_view_mode = view_mode
	_focus_district_id = focus_district_id
	_rebuild_opportunity_entries()
	queue_redraw()


func set_hover(entry: Dictionary) -> void:
	_hover = entry.duplicate(true) if typeof(entry) == TYPE_DICTIONARY else {}
	queue_redraw()


func set_selection(entry: Dictionary) -> void:
	_selected = entry.duplicate(true) if typeof(entry) == TYPE_DICTIONARY else {}
	queue_redraw()


func clear_selection() -> void:
	_selected = {}
	queue_redraw()


func set_blink_phase(phase: float) -> void:
	_blink_phase = phase
	queue_redraw()


func refresh_ownership() -> void:
	_rebuild_opportunity_entries()
	queue_redraw()


func get_opportunity_count() -> int:
	return _opportunity_entries.size()


func _rebuild_opportunity_entries() -> void:
	_opportunity_entries.clear()
	if Game.state == null:
		return
	for bundle_variant in _district_bundles:
		var bundle: Dictionary = bundle_variant
		var district_id: String = str(bundle.get("district_id", ""))
		if not _Unlock.is_unlocked(Game.state, district_id):
			continue
		if not _is_district_interactive(district_id):
			continue
		var entry: Dictionary = bundle.get("entry", {})
		var district: Dictionary = bundle.get("district", {})
		var origin: Vector2i = bundle.get("origin", Vector2i.ZERO)
		for parcel_variant in district.get("parcels", []):
			if typeof(parcel_variant) != TYPE_DICTIONARY:
				continue
			var parcel: Dictionary = parcel_variant
			var owner_state := _owner_state_for_entry(parcel, district)
			if owner_state not in [_Ownership.OWNER_OPPORTUNITY, _Ownership.OWNER_CONTESTED]:
				continue
			var hit := parcel.duplicate(true)
			hit["district_id"] = district_id
			hit["_district"] = district
			hit["_region_entry"] = entry
			_opportunity_entries.append({
				"hit": hit,
				"lot_rect": _world_lot_rect(parcel, district, origin),
				"owner_state": owner_state,
				"role": str(parcel.get("role", "core")),
				"origin": origin,
				"district": district,
			})


func _draw() -> void:
	for item_variant in _opportunity_entries:
		var item: Dictionary = item_variant
		_draw_opportunity_item(item)
	_draw_hover()
	_draw_selection()


func _draw_opportunity_item(item: Dictionary) -> void:
	var lot_rect: Rect2i = item.get("lot_rect", Rect2i())
	var owner_state: String = str(item.get("owner_state", ""))
	var role: String = str(item.get("role", "core"))
	var district: Dictionary = item.get("district", {})
	var origin: Vector2i = item.get("origin", Vector2i.ZERO)
	var lot_color: Color = _outline_color(owner_state, role)
	_draw_dashed_outline(_Grid.tile_rect_outline(lot_rect, _region_offset), lot_color, 2.0, 7.0, 5.0)
	if role not in ["development", "civic", "bank"]:
		var parcel: Dictionary = item.get("hit", {})
		var lot_tiles: int = int(district.get("lot_tiles", _Layout.LOT_TILES))
		var building_tiles: int = int(district.get("building_tiles", _Layout.BUILDING_TILES))
		var road_gap: int = _Layout.road_gap_for(district)
		var building_rect := _world_building_rect(parcel, district, origin, lot_tiles, building_tiles, road_gap)
		var build_color := BUILDING_COLOR
		build_color.a = lot_color.a
		_draw_dashed_outline(_Grid.tile_rect_outline(building_rect, _region_offset), build_color, 1.5, 5.0, 4.0)
		var resolved := _Ownership.resolve(Game.state, parcel, district)
		var label := str(resolved.get("operator_name", ""))
		if label.is_empty():
			label = str(parcel.get("label", ""))
		_draw_parcel_label(label, lot_rect)


func _outline_color(owner_state: String, role: String) -> Color:
	match owner_state:
		_Ownership.OWNER_OPPORTUNITY:
			var color: Color = OPPORTUNITY_OUTLINE
			color.a = _opportunity_blink_alpha()
			return color
		_Ownership.OWNER_CONTESTED:
			var color: Color = CONTESTED_OUTLINE
			color.a = _opportunity_blink_alpha()
			return color
		_:
			var color: Color = ROLE_COLORS.get(role, ROLE_COLORS["core"])
			return color


func _opportunity_blink_alpha() -> float:
	var wave := 0.5 + 0.5 * sin(_blink_phase * TAU)
	return lerpf(OPPORTUNITY_BLINK_MIN_ALPHA, OPPORTUNITY_BLINK_MAX_ALPHA, wave)


func _draw_hover() -> void:
	if _hover.is_empty():
		return
	if str(_hover.get("id", "")) == str(_selected.get("id", "")) and str(_hover.get("district_id", "")) == str(_selected.get("district_id", "")):
		return
	_draw_lot_highlight(_hover, HOVER_FILL, HOVER_OUTLINE, 2.0)


func _draw_selection() -> void:
	if _selected.is_empty():
		return
	_draw_lot_highlight(_selected, SELECT_FILL, SELECT_OUTLINE, 3.0)


func _draw_lot_highlight(entry: Dictionary, fill: Color, outline: Color, width: float) -> void:
	var district: Dictionary = entry.get("_district", {})
	var region_entry: Dictionary = entry.get("_region_entry", {})
	if district.is_empty():
		return
	var origin: Vector2i = _World.world_tile_origin(region_entry)
	var lot_rect := _world_lot_rect(entry, district, origin)
	var poly := _Grid.tile_rect_outline(lot_rect, _region_offset)
	if poly.size() >= 3:
		var fill_poly := PackedVector2Array(poly)
		fill_poly.remove_at(fill_poly.size() - 1)
		draw_colored_polygon(fill_poly, fill)
	for idx in poly.size() - 1:
		draw_line(poly[idx], poly[idx + 1], outline, width, true)


func _is_district_interactive(district_id: String) -> bool:
	if _view_mode == "district" and not _focus_district_id.is_empty() and district_id != _focus_district_id:
		return false
	return true


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


func _draw_dashed_outline(outline: PackedVector2Array, color: Color, width: float, dash: float, gap: float) -> void:
	for idx in outline.size() - 1:
		_draw_dashed_segment(outline[idx], outline[idx + 1], color, width, dash, gap)


func _draw_dashed_segment(from: Vector2, to: Vector2, color: Color, width: float, dash: float, gap: float) -> void:
	var delta := to - from
	var length := delta.length()
	if length <= 0.001:
		return
	var dir := delta / length
	var traveled := 0.0
	var drawing := true
	var dash_len := maxf(dash, 0.5)
	var gap_len := maxf(gap, 0.5)
	while traveled < length:
		var segment_len := dash_len if drawing else gap_len
		var end_dist := minf(traveled + segment_len, length)
		if end_dist <= traveled:
			break
		if drawing:
			draw_line(from + dir * traveled, from + dir * end_dist, color, width, true)
		traveled = end_dist
		drawing = not drawing


func _draw_parcel_label(text: String, lot_rect: Rect2i) -> void:
	if text.is_empty() or _font == null:
		return
	var center := _Grid.tile_rect_center(lot_rect, _region_offset)
	var font_size := 11
	var text_size := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
	var pos := center - Vector2(text_size.x * 0.5, text_size.y * 0.5 + 8.0)
	draw_string(_font, pos + Vector2(1.0, 1.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, LABEL_SHADOW)
	draw_string(_font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, LABEL_COLOR)
