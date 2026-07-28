class_name IsoGridMath
extends RefCounted

const TILE_W := 64.0
const TILE_H := 32.0


static func grid_to_screen(i: int, j: int) -> Vector2:
	return Vector2(
		(i - j) * TILE_W * 0.5,
		(i + j) * TILE_H * 0.5
	)


static func map_center_offset(grid_w: int, grid_h: int) -> Vector2:
	var cx := grid_w * 0.5
	var cy := grid_h * 0.5
	return -grid_to_screen(int(cx), int(cy))


static func bounds_center_offset(bounds: Rect2i) -> Vector2:
	var cx := float(bounds.position.x) + float(bounds.size.x) * 0.5
	var cy := float(bounds.position.y) + float(bounds.size.y) * 0.5
	return -grid_to_screen(int(cx), int(cy))


static func tile_corners(i: int, j: int, offset: Vector2 = Vector2.ZERO) -> PackedVector2Array:
	var center := grid_to_screen(i, j) + offset
	return PackedVector2Array([
		center + Vector2(0.0, -TILE_H * 0.5),
		center + Vector2(TILE_W * 0.5, 0.0),
		center + Vector2(0.0, TILE_H * 0.5),
		center + Vector2(-TILE_W * 0.5, 0.0),
	])


static func tile_rect_outline(tile_rect: Rect2i, offset: Vector2 = Vector2.ZERO) -> PackedVector2Array:
	var lx := tile_rect.position.x
	var ly := tile_rect.position.y
	var lw := tile_rect.size.x
	var lh := tile_rect.size.y
	var nw := grid_to_screen(lx, ly) + offset + Vector2(0.0, -TILE_H * 0.5)
	var ne := grid_to_screen(lx + lw - 1, ly) + offset + Vector2(TILE_W * 0.5, 0.0)
	var se := grid_to_screen(lx + lw - 1, ly + lh - 1) + offset + Vector2(0.0, TILE_H * 0.5)
	var sw := grid_to_screen(lx, ly + lh - 1) + offset + Vector2(-TILE_W * 0.5, 0.0)
	return PackedVector2Array([nw, ne, se, sw, nw])


static func tile_rect_center(tile_rect: Rect2i, offset: Vector2 = Vector2.ZERO) -> Vector2:
	var cx := float(tile_rect.position.x) + (float(tile_rect.size.x) - 1.0) * 0.5
	var cy := float(tile_rect.position.y) + (float(tile_rect.size.y) - 1.0) * 0.5
	return grid_to_screen(int(round(cx)), int(round(cy))) + offset


static func tile_rect_bounds(tile_rect: Rect2i, offset: Vector2 = Vector2.ZERO) -> Rect2:
	var outline := tile_rect_outline(tile_rect, offset)
	if outline.is_empty():
		return Rect2()
	var min_v := outline[0]
	var max_v := outline[0]
	for point: Vector2 in outline:
		min_v = min_v.min(point)
		max_v = max_v.max(point)
	return Rect2(min_v, max_v - min_v)


static func lot_outline(lot: Rect2i, offset: Vector2 = Vector2.ZERO) -> PackedVector2Array:
	return tile_rect_outline(lot, offset)


static func point_in_lot_rect(point: Vector2, lot_rect: Rect2i, offset: Vector2 = Vector2.ZERO) -> bool:
	var outline := tile_rect_outline(lot_rect, offset)
	if outline.size() < 4:
		return false
	var poly := PackedVector2Array(outline)
	poly.remove_at(poly.size() - 1)
	return Geometry2D.is_point_in_polygon(point, poly)


static func point_in_tile_rect(point: Vector2, tile_rect: Rect2i, offset: Vector2 = Vector2.ZERO) -> bool:
	for j in tile_rect.size.y:
		for i in tile_rect.size.x:
			var tx := tile_rect.position.x + i
			var ty := tile_rect.position.y + j
			var corners := tile_corners(tx, ty, offset)
			if corners.size() >= 3 and Geometry2D.is_point_in_polygon(point, corners):
				return true
	return false

