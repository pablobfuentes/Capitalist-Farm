class_name CharacterPortraitUtil
extends RefCounted

## Portraits in res://assets/characters/ are authored with transparent backgrounds.
const TEXTURES: Dictionary = {
	"pig": "res://assets/characters/pig.png",
	"donkey": "res://assets/characters/donkey.png",
	"hen": "res://assets/characters/hen.png",
	"horse": "res://assets/characters/horse.png",
	"goat": "res://assets/characters/goat.png",
	"sheep": "res://assets/characters/sheep.png",
}

## negotiation/layout.json design coordinates (y grows downward).
const DESIGN_HEADER_BOTTOM_Y := 306.0
const DESIGN_GAUGE_TOP_Y := 695.0
const DESIGN_PORTRAIT_TOP_Y := 306.0
const DESIGN_PORTRAIT_BOTTOM_Y := 667.0
## Small gap below the header art where the portrait top should sit.
const DESIGN_SPRITE_TOP_INSET := 14.0
const CONTENT_ALPHA_THRESHOLD := 8


static func texture_for_species(species_id: String) -> Texture2D:
	var key := species_id.strip_edges().to_lower()
	var path: String = str(TEXTURES.get(key, ""))
	if path.is_empty() or not ResourceLoader.exists(path):
		return null
	return load(path) as Texture2D


static func layout_sprite(texture: Texture2D, slot_size: Vector2) -> Dictionary:
	if texture == null or slot_size.y <= 0.0:
		return {}
	var tex_size := texture.get_size()
	if tex_size.y <= 0.0:
		return {}

	var content := _texture_content_bounds(texture)
	if content.size.y <= 0:
		content = Rect2i(Vector2i.ZERO, Vector2i(int(tex_size.x), int(tex_size.y)))

	var portrait_span := DESIGN_PORTRAIT_BOTTOM_Y - DESIGN_PORTRAIT_TOP_Y
	if portrait_span <= 0.0:
		return {}

	var top_y_design := DESIGN_HEADER_BOTTOM_Y + DESIGN_SPRITE_TOP_INSET
	var bottom_y_design := DESIGN_GAUGE_TOP_Y
	var target_h_design := bottom_y_design - top_y_design

	var to_local := slot_size.y / portrait_span
	var top_local := (top_y_design - DESIGN_PORTRAIT_TOP_Y) * to_local
	var bottom_local := (bottom_y_design - DESIGN_PORTRAIT_TOP_Y) * to_local
	var target_h := bottom_local - top_local

	var scale := target_h / float(content.size.y)
	var sprite_size := tex_size * scale
	var content_top_local := float(content.position.y) * scale
	var content_bottom_local := float(content.position.y + content.size.y) * scale
	var pos_y := top_local - content_top_local
	# Keep feet anchored on the gauge line if content bounds differ from canvas size.
	pos_y = bottom_local - content_bottom_local
	return {
		"size": sprite_size,
		"position": Vector2((slot_size.x - sprite_size.x) * 0.5, pos_y),
	}


static func _texture_content_bounds(texture: Texture2D) -> Rect2i:
	var image := texture.get_image()
	if image == null or image.is_empty():
		return Rect2i()
	var w := image.get_width()
	var h := image.get_height()
	var min_x := w
	var min_y := h
	var max_x := -1
	var max_y := -1
	for y in h:
		for x in w:
			if image.get_pixel(x, y).a <= CONTENT_ALPHA_THRESHOLD:
				continue
			min_x = mini(min_x, x)
			min_y = mini(min_y, y)
			max_x = maxi(max_x, x)
			max_y = maxi(max_y, y)
	if max_x < min_x or max_y < min_y:
		return Rect2i()
	return Rect2i(min_x, min_y, max_x - min_x + 1, max_y - min_y + 1)
