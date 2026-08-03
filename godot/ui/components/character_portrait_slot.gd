extends Control

## Species portrait inside negotiation / community chat panels.

const _PortraitUtil := preload("res://core/util/character_portrait_util.gd")

@onready var _sprite: TextureRect = %PortraitSprite
@onready var _placeholder: Label = %PortraitPlaceholder

var _species_id := ""


func _ready() -> void:
	clip_contents = false
	z_index = 6
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(_on_resized)
	if _sprite != null:
		_sprite.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	if _placeholder != null:
		_placeholder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	call_deferred("_apply_layout")


func set_species(species_id: String) -> void:
	_species_id = species_id.strip_edges().to_lower()
	_apply_layout()


func refresh_layout() -> void:
	_apply_layout()


func _on_resized() -> void:
	_apply_layout()


func _apply_layout() -> void:
	if _sprite == null or _placeholder == null:
		return
	var texture := _PortraitUtil.texture_for_species(_species_id)
	if texture == null:
		_sprite.visible = false
		_sprite.texture = null
		_placeholder.visible = true
		return

	_sprite.texture = texture
	_sprite.visible = true
	_placeholder.visible = false
	_sprite.modulate = Color(1, 1, 1, 1)

	var layout: Dictionary = _PortraitUtil.layout_sprite(texture, size)
	if layout.is_empty():
		return
	var sprite_size: Vector2 = layout.get("size", Vector2.ZERO)
	var sprite_pos: Vector2 = layout.get("position", Vector2.ZERO)
	_sprite.custom_minimum_size = sprite_size
	_sprite.size = sprite_size
	_sprite.position = sprite_pos
