class_name BuildingSpriteUtil
extends RefCounted

const ALPHA_THRESHOLD := 0.08
const SILHOUETTE_SAMPLES := 96


## Returns content_rect (opaque pixels) and outline (texture pixel coords).
static func analyze(texture: Texture2D) -> Dictionary:
	if texture == null:
		return {}
	var img := texture.get_image()
	if img.is_empty():
		return {}
	if img.is_compressed():
		img.decompress()

	var content: Rect2i = img.get_used_rect()
	if content.size.x <= 0 or content.size.y <= 0:
		return {}

	var outline := _build_silhouette_outline(img, content)
	var south_offset := _content_south_offset(img, content)
	return {
		"content_rect": content,
		"outline": outline,
		"south_offset": south_offset,
	}


## Fit sprite by aligning lot/sw ground edge and lot left/right diamond points.
static func layout_in_lot(
	texture: Texture2D,
	metrics: Dictionary,
	lot_rect: Rect2i,
	region_offset: Vector2,
) -> Dictionary:
	if texture == null or metrics.is_empty():
		return {}

	var content: Rect2i = metrics.get("content_rect", Rect2i())
	if content.size.x <= 0 or content.size.y <= 0:
		return {}

	var content_size := Vector2(content.size)
	var outline: PackedVector2Array = IsoGridMath.tile_rect_outline(lot_rect, region_offset)
	if outline.size() < 4:
		return {}

	var ne := outline[1]
	var se := outline[2]
	var sw := outline[3]

	# Diamond extremes: sw = leftmost, ne = rightmost, se = southmost.
	var lot_left_x := sw.x
	var lot_right_x := ne.x
	var lot_south_y := se.y
	var lot_width := lot_right_x - lot_left_x
	if lot_width <= 1.0:
		return {}

	# Scale so sprite left/right coincide with lot left/right.
	var scale := lot_width / content_size.x
	var draw_size := content_size * scale
	# Anchor sprite southmost opaque point to lot southmost point (se).
	var south_offset: float = float(metrics.get("south_offset", 1.0))
	var dest_pos := Vector2(lot_left_x, lot_south_y - draw_size.y * south_offset)
	var dest_rect := Rect2(dest_pos, draw_size)
	return _layout_result(metrics, content, dest_rect)


static func _layout_result(metrics: Dictionary, content: Rect2i, dest_rect: Rect2) -> Dictionary:
	var world_outline := _outline_to_world(
		metrics.get("outline", PackedVector2Array()),
		content,
		dest_rect,
	)
	return {
		"dest_rect": dest_rect,
		"source_rect": Rect2(content),
		"world_outline": world_outline,
	}


static func _content_south_offset(img: Image, content: Rect2i) -> float:
	var south_y := content.position.y
	var found := false
	for y in range(content.position.y, content.position.y + content.size.y):
		for x in range(content.position.x, content.position.x + content.size.x):
			if _alpha_at(img, x, y) >= ALPHA_THRESHOLD:
				south_y = maxi(south_y, y)
				found = true
	if not found or content.size.y <= 0:
		return 1.0
	return float(south_y - content.position.y + 1) / float(content.size.y)


static func _build_silhouette_outline(img: Image, content: Rect2i) -> PackedVector2Array:
	var cx := float(content.position.x) + float(content.size.x) * 0.5
	var cy := float(content.position.y) + float(content.size.y) * 0.5
	var center := Vector2(cx, cy)
	var max_r := float(maxi(content.size.x, content.size.y)) * 0.72
	var points: PackedVector2Array = []

	for i in SILHOUETTE_SAMPLES:
		var angle := float(i) * TAU / float(SILHOUETTE_SAMPLES)
		var dir := Vector2(cos(angle), sin(angle))
		var hit := _raycast_opaque(img, center, dir, max_r, content)
		if hit.x >= 0.0:
			points.append(hit)

	if points.size() < 3:
		return _rect_outline(content)
	return points


static func _raycast_opaque(
	img: Image,
	origin: Vector2,
	dir: Vector2,
	max_r: float,
	content: Rect2i,
) -> Vector2:
	var steps := int(ceil(max_r))
	for step in range(steps, 0, -1):
		var p := origin + dir * float(step)
		var x := int(round(p.x))
		var y := int(round(p.y))
		if not _point_in_rect(x, y, content):
			continue
		if _alpha_at(img, x, y) >= ALPHA_THRESHOLD:
			return Vector2(x, y)
	return Vector2(-1.0, -1.0)


static func _rect_outline(content: Rect2i) -> PackedVector2Array:
	var x0 := float(content.position.x)
	var y0 := float(content.position.y)
	var x1 := x0 + float(content.size.x)
	var y1 := y0 + float(content.size.y)
	return PackedVector2Array([
		Vector2(x0, y0),
		Vector2(x1, y0),
		Vector2(x1, y1),
		Vector2(x0, y1),
	])


static func _outline_to_world(
	outline: PackedVector2Array,
	content: Rect2i,
	dest_rect: Rect2,
) -> PackedVector2Array:
	if outline.is_empty() or content.size.x <= 0 or content.size.y <= 0:
		return PackedVector2Array()

	var content_pos := Vector2(content.position)
	var content_size := Vector2(content.size)
	var world: PackedVector2Array = []
	for point: Vector2 in outline:
		var rel := (point - content_pos) / content_size
		world.append(dest_rect.position + Vector2(rel.x * dest_rect.size.x, rel.y * dest_rect.size.y))
	if world.size() >= 2 and world[0].distance_to(world[world.size() - 1]) > 0.5:
		world.append(world[0])
	return world


static func _point_in_rect(x: int, y: int, rect: Rect2i) -> bool:
	return x >= rect.position.x and y >= rect.position.y and x < rect.position.x + rect.size.x and y < rect.position.y + rect.size.y


static func _alpha_at(img: Image, x: int, y: int) -> float:
	if x < 0 or y < 0 or x >= img.get_width() or y >= img.get_height():
		return 0.0
	return img.get_pixel(x, y).a
