extends Node2D

const _Grid := preload("res://scenes/farm_map/iso_grid_math.gd")
const _Layout := preload("res://scenes/farm_map/district_layout_data.gd")
const _Unlock := preload("res://core/systems/district_unlock_system.gd")
const _Ownership := preload("res://core/systems/parcel_ownership_system.gd")
const _SpriteUtil := preload("res://scenes/farm_map/building_sprite_util.gd")

const BUILDING_ASSET_DIRS := [
	"res://assets/2d_buildings/no_background/",
	"res://assets/2d_buildings/",
]
const PLAYER_OUTLINE := Color(0.20, 0.72, 1.0, 1.0)
const URGENCY_OUTLINE := Color(0.95, 0.18, 0.12, 1.0)
const OPPORTUNITY_OUTLINE := Color(1.0, 0.92, 0.12, 1.0)
const CONTESTED_OUTLINE := Color(1.0, 0.72, 0.18, 1.0)
const OUTLINE_WIDTH := 2.0
const URGENCY_OUTLINE_WIDTH := 2.6
## At blink speed 0.9: phase +1.8 ≈ 2.0s; red pulse lasts ~0.4s.
const URGENCY_FLASH_PERIOD := 1.8
const URGENCY_FLASH_ON := 0.36
const OPPORTUNITY_BLINK_MIN_ALPHA := 0.16
const OPPORTUNITY_BLINK_MAX_ALPHA := 1.0
const OWNED_SMOKE_COLOR := Color(0.78, 0.82, 0.86, 0.55)
const URGENCY_FLAME_CORE := Color(1.0, 0.82, 0.22, 1.0)
const URGENCY_FLAME_MID := Color(1.0, 0.45, 0.08, 0.95)
const URGENCY_FLAME_TIP := Color(0.98, 0.16, 0.04, 0.85)

var _region: Dictionary = {}
var _region_offset := Vector2.ZERO
var _view_mode := "overview"
var _focus_district_id := ""
var _district_bundles: Array = []
var _textures: Array[Texture2D] = []
var _texture_pick: Dictionary = {}
var _sprite_metrics: Dictionary = {}
var _blink_phase := 0.0
var _owned_count := 0
var _urgency_count := 0


func _ready() -> void:
	_ensure_textures_loaded()


func configure(region: Dictionary, region_offset: Vector2, district_bundles: Array) -> void:
	_ensure_textures_loaded()
	_region = region
	_region_offset = region_offset
	_district_bundles = district_bundles
	queue_redraw()


func set_view_context(view_mode: String, focus_district_id: String) -> void:
	_view_mode = view_mode
	_focus_district_id = focus_district_id
	queue_redraw()


func set_blink_phase(phase: float) -> void:
	_blink_phase = phase
	# Always redraw — opportunity outlines pulse from this phase even with zero owned parcels.
	queue_redraw()


func get_owned_count() -> int:
	return _owned_count


func get_urgency_count() -> int:
	return _urgency_count


func get_opportunity_outline_count() -> int:
	return _count_opportunity_parcels()


func refresh_ownership() -> void:
	_owned_count = _count_owned_parcels()
	_urgency_count = _count_urgency_parcels()
	queue_redraw()


func _count_owned_parcels() -> int:
	return _count_parcels_with_owner([_Ownership.OWNER_PLAYER])


func _count_opportunity_parcels() -> int:
	return _count_parcels_with_owner([_Ownership.OWNER_OPPORTUNITY, _Ownership.OWNER_CONTESTED])


func _count_parcels_with_owner(owners: Array) -> int:
	var count := 0
	for bundle_variant in _district_bundles:
		if typeof(bundle_variant) != TYPE_DICTIONARY:
			continue
		var bundle: Dictionary = bundle_variant
		var district: Dictionary = bundle.get("district", {})
		for parcel_variant in district.get("parcels", []):
			if typeof(parcel_variant) != TYPE_DICTIONARY:
				continue
			var parcel: Dictionary = parcel_variant
			var role := str(parcel.get("role", "core"))
			if role in ["development", "civic", "bank", "plaza"]:
				continue
			if _owner_state_for_entry(parcel, district) in owners:
				count += 1
	return count


func _ensure_textures_loaded() -> void:
	if not _textures.is_empty():
		return
	_load_textures()


func _load_textures() -> void:
	_textures.clear()
	_sprite_metrics.clear()
	for asset_dir: String in BUILDING_ASSET_DIRS:
		var dir := DirAccess.open(asset_dir)
		if dir == null:
			continue
		var loaded: Array[Texture2D] = []
		for file_name: String in dir.get_files():
			if not file_name.to_lower().ends_with(".png"):
				continue
			var tex: Texture2D = load(asset_dir + file_name)
			if tex != null:
				loaded.append(tex)
				_cache_metrics(tex)
		if not loaded.is_empty():
			_textures = loaded
			return
	push_warning("DistrictParcelBuildings: no PNG textures in %s" % ", ".join(BUILDING_ASSET_DIRS))


func _cache_metrics(texture: Texture2D) -> void:
	var key := _texture_key(texture)
	if key.is_empty() or _sprite_metrics.has(key):
		return
	var metrics: Dictionary = _SpriteUtil.analyze(texture)
	if not metrics.is_empty():
		_sprite_metrics[key] = metrics


func _texture_key(texture: Texture2D) -> String:
	var path := texture.resource_path
	if not path.is_empty():
		return path
	return str(texture.get_instance_id())


func _metrics_for(texture: Texture2D) -> Dictionary:
	var key := _texture_key(texture)
	if key.is_empty():
		return {}
	if not _sprite_metrics.has(key):
		_cache_metrics(texture)
	return _sprite_metrics.get(key, {})


func _draw() -> void:
	if _textures.is_empty():
		return
	var owned := 0
	var urgencies := 0
	for bundle_variant in _district_bundles:
		if typeof(bundle_variant) != TYPE_DICTIONARY:
			continue
		var bundle: Dictionary = bundle_variant
		var district_id: String = str(bundle.get("district_id", ""))
		if not _Unlock.is_unlocked(Game.state, district_id):
			continue
		var dimmed := _should_dim_district(district_id)
		var drawn: Dictionary = _draw_district_buildings(bundle, dimmed)
		owned += int(drawn.get("owned", 0))
		urgencies += int(drawn.get("urgencies", 0))
	_owned_count = owned
	_urgency_count = urgencies


func _should_dim_district(district_id: String) -> bool:
	if _view_mode != "district" or _focus_district_id.is_empty():
		return false
	return district_id != _focus_district_id


func _draw_district_buildings(bundle: Dictionary, dimmed: bool) -> Dictionary:
	var district: Dictionary = bundle.get("district", {})
	var origin: Vector2i = bundle.get("origin", Vector2i.ZERO)
	var district_id: String = str(bundle.get("district_id", ""))
	var alpha := 0.42 if dimmed else 1.0
	var owned := 0
	var urgencies := 0

	for parcel_variant in district.get("parcels", []):
		if typeof(parcel_variant) != TYPE_DICTIONARY:
			continue
		var parcel: Dictionary = parcel_variant
		var role := str(parcel.get("role", "core"))
		if role in ["development", "civic", "bank", "plaza"]:
			continue
		var lot_rect := _world_lot_rect(parcel, district, origin)
		var texture := _texture_for_parcel(district_id, str(parcel.get("id", "")))
		if texture == null:
			continue
		var owner_info := _owner_info_for_entry(parcel, district)
		var owner_state := str(owner_info.get("state", _Ownership.OWNER_NPC))
		var layout: Dictionary = _draw_building_sprite(texture, lot_rect, alpha)
		var business_id := str(owner_info.get("business_id", ""))
		var has_urgency := owner_state == _Ownership.OWNER_PLAYER and _business_has_urgency(business_id)
		_draw_sprite_status_outline(
			layout.get("world_outline", PackedVector2Array()),
			owner_state,
			alpha,
			has_urgency,
		)
		if owner_state == _Ownership.OWNER_PLAYER:
			owned += 1
			_draw_owned_idle_smoke(layout.get("dest_rect", Rect2()), alpha, str(parcel.get("id", "")))
			if has_urgency:
				urgencies += 1
				_draw_urgency_flames(
					layout.get("dest_rect", Rect2()),
					alpha,
					str(parcel.get("id", "")),
					RelationshipIssuePressureSystem.pending_severity_for_business(Game.state, business_id),
				)
	return {"owned": owned, "urgencies": urgencies}


func _count_urgency_parcels() -> int:
	if Game.state == null:
		return 0
	var count := 0
	for bundle_variant in _district_bundles:
		if typeof(bundle_variant) != TYPE_DICTIONARY:
			continue
		var bundle: Dictionary = bundle_variant
		var district: Dictionary = bundle.get("district", {})
		for parcel_variant in district.get("parcels", []):
			if typeof(parcel_variant) != TYPE_DICTIONARY:
				continue
			var parcel: Dictionary = parcel_variant
			var info := _owner_info_for_entry(parcel, district)
			if str(info.get("state", "")) != _Ownership.OWNER_PLAYER:
				continue
			if _business_has_urgency(str(info.get("business_id", ""))):
				count += 1
	return count


func _business_has_urgency(business_id: String) -> bool:
	if Game.state == null or business_id.is_empty():
		return false
	return RelationshipIssuePressureSystem.business_has_pending_issue(Game.state, business_id)


func _draw_owned_idle_smoke(dest_rect: Rect2, alpha: float, parcel_id: String) -> void:
	if dest_rect.size == Vector2.ZERO:
		return
	var seed_bias := float(hash(parcel_id) % 1000) / 1000.0
	var base := dest_rect.position + Vector2(dest_rect.size.x * 0.62, dest_rect.size.y * 0.18)
	for i in 3:
		var phase := fposmod(_blink_phase * 0.35 + seed_bias + float(i) * 0.28, 1.0)
		var rise := phase * 18.0
		var drift := sin((_blink_phase + seed_bias + float(i)) * TAU) * 3.0
		var puff_a := (1.0 - phase) * 0.45 * alpha
		if puff_a <= 0.02:
			continue
		var radius := lerpf(2.2, 5.5, phase)
		var color := OWNED_SMOKE_COLOR
		color.a = puff_a
		draw_circle(base + Vector2(drift, -rise), radius, color)


func _draw_urgency_flames(dest_rect: Rect2, alpha: float, parcel_id: String, severity: String) -> void:
	if dest_rect.size == Vector2.ZERO:
		return
	var seed_bias := float(hash(parcel_id + ":flame") % 1000) / 1000.0
	var scale := 1.25
	var flame_count := 8
	match severity:
		"crisis":
			scale = 1.6
			flame_count = 11
		"urgent":
			scale = 1.4
			flame_count = 10
		_:
			scale = 1.25
			flame_count = 8
	var top_y := dest_rect.position.y + dest_rect.size.y * 0.10
	var left_x := dest_rect.position.x + dest_rect.size.x * 0.06
	var span := dest_rect.size.x * 0.88
	var flicker := 0.82 + 0.18 * sin((_blink_phase * 8.0 + seed_bias) * TAU)
	for i in flame_count:
		var across := 0.0 if flame_count <= 1 else float(i) / float(flame_count - 1)
		var base := Vector2(left_x + span * across, top_y)
		var phase := fposmod(_blink_phase * 1.05 + seed_bias + float(i) * 0.13, 1.0)
		var rise := phase * 20.0 * scale
		var sway := sin((_blink_phase * 3.6 + seed_bias + float(i) * 1.4) * TAU) * (2.8 * scale)
		var tip_a := (1.0 - phase) * 0.95 * alpha * flicker
		if tip_a <= 0.03:
			continue
		var w := lerpf(4.4, 1.4, phase) * scale
		var h := lerpf(7.0, 12.0, phase) * scale
		var center := base + Vector2(sway, -rise)
		var tip := Color(URGENCY_FLAME_TIP.r, URGENCY_FLAME_TIP.g, URGENCY_FLAME_TIP.b, tip_a)
		var mid := Color(URGENCY_FLAME_MID.r, URGENCY_FLAME_MID.g, URGENCY_FLAME_MID.b, tip_a * 0.95)
		var core := Color(URGENCY_FLAME_CORE.r, URGENCY_FLAME_CORE.g, URGENCY_FLAME_CORE.b, tip_a)
		draw_circle(center + Vector2(0.0, -h * 0.18), w * 1.25, tip)
		draw_circle(center + Vector2(0.0, h * 0.02), w * 0.95, mid)
		draw_circle(center + Vector2(0.0, h * 0.24), w * 0.58, core)
		# Secondary ember slightly offset so the ridge looks denser.
		if i % 2 == 0:
			var ember_phase := fposmod(phase + 0.35, 1.0)
			var ember_a := (1.0 - ember_phase) * 0.7 * alpha * flicker
			if ember_a > 0.04:
				var ember_pos := base + Vector2(sway * 0.4, -ember_phase * 12.0 * scale)
				draw_circle(ember_pos, lerpf(2.8, 1.0, ember_phase) * scale, Color(1.0, 0.55, 0.12, ember_a))


func _texture_for_parcel(district_id: String, parcel_id: String) -> Texture2D:
	if parcel_id.is_empty() or _textures.is_empty():
		return null
	var key := "%s:%s" % [district_id, parcel_id]
	if not _texture_pick.has(key):
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(key)
		_texture_pick[key] = rng.randi_range(0, _textures.size() - 1)
	return _textures[int(_texture_pick[key])]


func _draw_building_sprite(texture: Texture2D, lot_rect: Rect2i, alpha: float) -> Dictionary:
	var metrics: Dictionary = _metrics_for(texture)
	var layout: Dictionary = _SpriteUtil.layout_in_lot(texture, metrics, lot_rect, _region_offset)
	if layout.is_empty():
		return {}

	var dest_rect: Rect2 = layout.get("dest_rect", Rect2())
	var source_rect: Rect2 = layout.get("source_rect", Rect2())
	draw_texture_rect_region(
		texture,
		dest_rect,
		source_rect,
		Color(1.0, 1.0, 1.0, alpha),
	)
	return layout


func _draw_sprite_status_outline(
	outline: PackedVector2Array,
	owner_state: String,
	alpha_mult: float,
	has_urgency: bool = false,
) -> void:
	if outline.size() < 2:
		return
	var outline_color := _status_outline_color(owner_state, has_urgency)
	if outline_color.a <= 0.01:
		return
	outline_color.a *= alpha_mult
	var width := URGENCY_OUTLINE_WIDTH if has_urgency and _urgency_outline_flashing_red() else OUTLINE_WIDTH
	draw_polyline(outline, outline_color, width, true)


func _status_outline_color(owner_state: String, has_urgency: bool = false) -> Color:
	match owner_state:
		_Ownership.OWNER_PLAYER:
			if has_urgency and _urgency_outline_flashing_red():
				return URGENCY_OUTLINE
			return PLAYER_OUTLINE
		_Ownership.OWNER_OPPORTUNITY:
			var color := OPPORTUNITY_OUTLINE
			color.a = _opportunity_blink_alpha()
			return color
		_Ownership.OWNER_CONTESTED:
			var color := CONTESTED_OUTLINE
			color.a = _opportunity_blink_alpha()
			return color
		_:
			return Color(0.0, 0.0, 0.0, 0.0)


func _urgency_outline_flashing_red() -> bool:
	return fposmod(_blink_phase, URGENCY_FLASH_PERIOD) < URGENCY_FLASH_ON


func _opportunity_blink_alpha() -> float:
	# Ease the sine so the bright peak lingers a bit — calmer, still obvious.
	var wave := 0.5 + 0.5 * sin(_blink_phase * TAU)
	var eased := wave * wave * (3.0 - 2.0 * wave)
	return lerpf(OPPORTUNITY_BLINK_MIN_ALPHA, OPPORTUNITY_BLINK_MAX_ALPHA, eased)


func _owner_state_for_entry(entry: Dictionary, district: Dictionary) -> String:
	return str(_owner_info_for_entry(entry, district).get("state", _Ownership.OWNER_NPC))


func _owner_info_for_entry(entry: Dictionary, district: Dictionary) -> Dictionary:
	if Game.state == null:
		return {"state": _Ownership.OWNER_NPC, "business_id": ""}
	return _Ownership.resolve(Game.state, entry, district)


func _world_lot_rect(entry: Dictionary, district: Dictionary, origin: Vector2i) -> Rect2i:
	var local := _Layout.lot_rect_for_entry(entry, district)
	return Rect2i(local.position + origin, local.size)
