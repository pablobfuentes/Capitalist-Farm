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
const OPPORTUNITY_OUTLINE := Color(1.0, 0.92, 0.12, 1.0)
const CONTESTED_OUTLINE := Color(1.0, 0.72, 0.18, 1.0)
const OUTLINE_WIDTH := 2.0
const OPPORTUNITY_BLINK_MIN_ALPHA := 0.22
const OPPORTUNITY_BLINK_MAX_ALPHA := 1.0

var _region: Dictionary = {}
var _region_offset := Vector2.ZERO
var _view_mode := "overview"
var _focus_district_id := ""
var _district_bundles: Array = []
var _textures: Array[Texture2D] = []
var _texture_pick: Dictionary = {}
var _sprite_metrics: Dictionary = {}
var _blink_phase := 0.0


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
	queue_redraw()


func refresh_ownership() -> void:
	queue_redraw()


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
	for bundle_variant in _district_bundles:
		if typeof(bundle_variant) != TYPE_DICTIONARY:
			continue
		var bundle: Dictionary = bundle_variant
		var district_id: String = str(bundle.get("district_id", ""))
		if not _Unlock.is_unlocked(Game.state, district_id):
			continue
		var dimmed := _should_dim_district(district_id)
		_draw_district_buildings(bundle, dimmed)


func _should_dim_district(district_id: String) -> bool:
	if _view_mode != "district" or _focus_district_id.is_empty():
		return false
	return district_id != _focus_district_id


func _draw_district_buildings(bundle: Dictionary, dimmed: bool) -> void:
	var district: Dictionary = bundle.get("district", {})
	var origin: Vector2i = bundle.get("origin", Vector2i.ZERO)
	var district_id: String = str(bundle.get("district_id", ""))
	var alpha := 0.42 if dimmed else 1.0

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
		var owner_state := _owner_state_for_entry(parcel, district)
		var layout: Dictionary = _draw_building_sprite(texture, lot_rect, alpha)
		_draw_sprite_status_outline(layout.get("world_outline", PackedVector2Array()), owner_state, alpha)


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


func _draw_sprite_status_outline(outline: PackedVector2Array, owner_state: String, alpha_mult: float) -> void:
	if outline.size() < 2:
		return
	var outline_color := _status_outline_color(owner_state)
	if outline_color.a <= 0.01:
		return
	outline_color.a *= alpha_mult
	draw_polyline(outline, outline_color, OUTLINE_WIDTH, true)


func _status_outline_color(owner_state: String) -> Color:
	match owner_state:
		_Ownership.OWNER_PLAYER:
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


func _opportunity_blink_alpha() -> float:
	var wave := 0.5 + 0.5 * sin(_blink_phase * TAU)
	return lerpf(OPPORTUNITY_BLINK_MIN_ALPHA, OPPORTUNITY_BLINK_MAX_ALPHA, wave)


func _owner_state_for_entry(entry: Dictionary, district: Dictionary) -> String:
	if Game.state == null:
		return _Ownership.OWNER_NPC
	return str(_Ownership.resolve(Game.state, entry, district).get("state", _Ownership.OWNER_NPC))


func _world_lot_rect(entry: Dictionary, district: Dictionary, origin: Vector2i) -> Rect2i:
	var local := _Layout.lot_rect_for_entry(entry, district)
	return Rect2i(local.position + origin, local.size)
