extends Node2D

## Draws active supply-chain path as elevated dotted Bezier arcs + direction dots.

const _SCOwn := preload("res://core/systems/supply_chain_ownership.gd")

const DOT_SPACING := 14.0
const DOT_RADIUS := 2.6
const MOVE_DOT_RADIUS := 4.2
const MIN_ARC_HEIGHT := 36.0
const ARC_HEIGHT_FACTOR := 0.28
const SAMPLES_PER_CURVE := 28
const HOVER_HIT_PX := 14.0
const CROSSFADE_SEC := 0.35

var _routes: Array = [] # active path routes
var _fade_out_routes: Array = []
var _fade_t := 1.0
var _selected_center := Vector2.ZERO
var _complete_centers: Array = [] # Vector2 markers for path businesses when complete
var _has_selection := false
var _path_complete := false
var _anim_t := 0.0
var _enabled := false
var _pair_offsets: Dictionary = {} # "x,y|x,y" -> int count for overlap spread


func set_enabled(on: bool) -> void:
	_enabled = on
	visible = on
	set_process(on)
	if not on:
		_routes.clear()
		_fade_out_routes.clear()
		_complete_centers.clear()
		_has_selection = false
		_pair_offsets.clear()
		queue_redraw()


func clear_routes() -> void:
	_routes.clear()
	_fade_out_routes.clear()
	_complete_centers.clear()
	_has_selection = false
	_pair_offsets.clear()
	queue_redraw()


## routes: Array of { from, to, visualState, label?, status?, resource? }
## complete_centers: optional Array of Vector2 for green building treatment
func set_routes(
	routes: Array,
	selected_center: Vector2 = Vector2.ZERO,
	path_complete: bool = false,
	complete_centers: Array = [],
	crossfade: bool = false,
) -> void:
	if crossfade and not _routes.is_empty():
		_fade_out_routes = _routes.duplicate(true)
		_fade_t = 0.0
	else:
		_fade_out_routes.clear()
		_fade_t = 1.0
	_routes.clear()
	_pair_offsets.clear()
	_path_complete = path_complete
	_has_selection = selected_center != Vector2.ZERO
	_selected_center = selected_center
	_complete_centers = complete_centers.duplicate()
	for route_variant in routes:
		if typeof(route_variant) != TYPE_DICTIONARY:
			continue
		var route: Dictionary = route_variant
		var from: Vector2 = route.get("from", Vector2.ZERO)
		var to: Vector2 = route.get("to", Vector2.ZERO)
		if from == to:
			continue
		var state := str(route.get("visualState", _SCOwn.STATE_EXTERNAL))
		# Infrastructure (Delivery / Repair) stays pink even on a complete green path.
		if path_complete and state != _SCOwn.STATE_INFRASTRUCTURE:
			state = _SCOwn.STATE_COMPLETE
		var offset_i := _next_pair_offset(from, to)
		var points := _bezier_points(from, to, offset_i)
		var length := _polyline_length(points)
		_routes.append({
			"points": points,
			"color": _SCOwn.color_for_state(state),
			"length": length,
			"label": str(route.get("label", "")),
			"status": str(route.get("status", "")),
			"resource": str(route.get("resource", "")),
		})
	queue_redraw()


## World-space hover: returns tooltip dict or empty.
func tooltip_at_world(world_pos: Vector2) -> Dictionary:
	if not _enabled:
		return {}
	var best_d := HOVER_HIT_PX
	var best: Dictionary = {}
	for route_variant in _routes:
		var route: Dictionary = route_variant
		var d := _distance_to_polyline(world_pos, route.get("points", PackedVector2Array()))
		if d < best_d:
			best_d = d
			best = {
				"label": str(route.get("label", "")),
				"status": str(route.get("status", "")),
				"resource": str(route.get("resource", "")),
			}
	return best


func _process(delta: float) -> void:
	if not _enabled:
		return
	_anim_t += delta
	if _fade_t < 1.0:
		_fade_t = minf(1.0, _fade_t + delta / CROSSFADE_SEC)
		if _fade_t >= 1.0:
			_fade_out_routes.clear()
	if not _routes.is_empty() or not _fade_out_routes.is_empty() or _has_selection:
		queue_redraw()


func _draw() -> void:
	if not _enabled:
		return
	if not _fade_out_routes.is_empty() and _fade_t < 1.0:
		var out_a := 1.0 - _fade_t
		for route_variant in _fade_out_routes:
			var route: Dictionary = route_variant
			var c: Color = route.get("color", Color.WHITE)
			c.a *= out_a * 0.85
			_draw_dotted_polyline(route.get("points", PackedVector2Array()), c, float(route.get("length", 1.0)), false)
	var in_a := _fade_t
	for route_variant in _routes:
		var route: Dictionary = route_variant
		var c: Color = route.get("color", Color.WHITE)
		c.a *= in_a
		_draw_dotted_polyline(route.get("points", PackedVector2Array()), c, float(route.get("length", 1.0)), true)
	for center_variant in _complete_centers:
		if typeof(center_variant) == TYPE_VECTOR2:
			_draw_complete_building_marker(center_variant)
	if _has_selection:
		_draw_selection_marker(_selected_center, _path_complete)


func _draw_selection_marker(center: Vector2, complete: bool) -> void:
	# Match opportunity blink cadence (~0.9 Hz sine).
	var wave := 0.5 + 0.5 * sin(_anim_t * 0.9 * TAU)
	var pulse := lerpf(0.28, 1.0, wave)
	# Dark orange selection ring (green tint only when the full path is complete).
	var color := Color(0.42, 0.88, 0.48, 0.85) if complete else Color(0.92, 0.42, 0.10, 0.95)
	color.a = 0.35 + 0.55 * pulse
	draw_arc(center + Vector2(0, 8), 16.0 + 4.0 * pulse, 0.0, TAU, 28, color, 2.0 + pulse, true)
	draw_circle(center + Vector2(0, 8), 3.0 + pulse, color)


func _draw_complete_building_marker(center: Vector2) -> void:
	var pulse := 0.5 + 0.5 * sin(_anim_t * 1.6)
	var color := Color(0.42, 0.88, 0.48, 0.25 + 0.2 * pulse)
	draw_arc(center + Vector2(0, 10), 22.0, 0.0, TAU, 24, color, 2.0, true)


func _draw_dotted_polyline(points: PackedVector2Array, color: Color, length: float, animate_dot: bool) -> void:
	if points.size() < 2:
		return
	var shadow := Color(0.08, 0.1, 0.08, 0.35 * color.a)
	var cursor := 0.0
	while cursor < length:
		var p := _point_at_distance(points, cursor)
		draw_circle(p + Vector2(1.2, 1.2), DOT_RADIUS, shadow)
		draw_circle(p, DOT_RADIUS, color)
		cursor += DOT_SPACING
	if not animate_dot or color.a < 0.2:
		return
	var duration := clampf(length / 90.0, 1.5, 2.5)
	var u := fposmod(_anim_t / duration, 1.0)
	var move_p := _point_at_distance(points, u * length)
	var bright := Color(color.r, color.g, color.b, color.a).lightened(0.25)
	draw_circle(move_p + Vector2(1.4, 1.4), MOVE_DOT_RADIUS, shadow)
	draw_circle(move_p, MOVE_DOT_RADIUS, bright)


func _next_pair_offset(from: Vector2, to: Vector2) -> int:
	var key := "%d,%d|%d,%d" % [int(from.x), int(from.y), int(to.x), int(to.y)]
	var n := int(_pair_offsets.get(key, 0))
	_pair_offsets[key] = n + 1
	return n


func _bezier_points(from: Vector2, to: Vector2, pair_index: int = 0) -> PackedVector2Array:
	var mid := (from + to) * 0.5
	var dist := from.distance_to(to)
	var height := maxf(MIN_ARC_HEIGHT, dist * ARC_HEIGHT_FACTOR)
	height += float(pair_index) * 14.0
	var control := mid + Vector2(0, -height)
	var delta := to - from
	var lateral := Vector2(-delta.y, delta.x)
	if lateral.length_squared() > 0.001:
		lateral = lateral.normalized() * (10.0 + float(pair_index) * 8.0)
	control += lateral
	var pts := PackedVector2Array()
	for i in SAMPLES_PER_CURVE + 1:
		var t := float(i) / float(SAMPLES_PER_CURVE)
		pts.append(_quad_bezier(from, control, to, t))
	return pts


func _quad_bezier(a: Vector2, b: Vector2, c: Vector2, t: float) -> Vector2:
	var u := 1.0 - t
	return u * u * a + 2.0 * u * t * b + t * t * c


func _polyline_length(points: PackedVector2Array) -> float:
	var total := 0.0
	for i in range(1, points.size()):
		total += points[i - 1].distance_to(points[i])
	return total


func _point_at_distance(points: PackedVector2Array, distance: float) -> Vector2:
	if points.is_empty():
		return Vector2.ZERO
	if points.size() == 1:
		return points[0]
	var remaining := maxf(0.0, distance)
	for i in range(1, points.size()):
		var a: Vector2 = points[i - 1]
		var b: Vector2 = points[i]
		var seg := a.distance_to(b)
		if remaining <= seg or i == points.size() - 1:
			if seg <= 0.001:
				return b
			return a.lerp(b, clampf(remaining / seg, 0.0, 1.0))
		remaining -= seg
	return points[points.size() - 1]


func _distance_to_polyline(point: Vector2, points: PackedVector2Array) -> float:
	if points.size() < 2:
		return INF
	var best := INF
	for i in range(1, points.size()):
		best = minf(best, _distance_point_to_segment(point, points[i - 1], points[i]))
	return best


func _distance_point_to_segment(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var len_sq := ab.length_squared()
	if len_sq <= 0.0001:
		return p.distance_to(a)
	var t := clampf((p - a).dot(ab) / len_sq, 0.0, 1.0)
	return p.distance_to(a + ab * t)
