extends Control

## Multi-series progress chart (NW / Cash / Debt). Used on dashboard and run report.

const DEFAULT_SERIES: Array = [
	{"key": "netWorth", "label": "Net Worth", "color": Color(0.78, 0.62, 0.28, 0.95)},
	{"key": "cash", "label": "Cash", "color": Color(0.50, 0.75, 0.62, 0.95)},
	{"key": "debt", "label": "Debt", "color": Color(0.63, 0.28, 0.23, 0.95)},
]

const PAD_LEFT := 52.0
const PAD_RIGHT := 8.0
const PAD_TOP := 36.0
const PAD_BOTTOM := 22.0
const MAX_VISIBLE_TURNS := 40

var history: Array = []
var series: Array = []
var max_visible_turns: int = MAX_VISIBLE_TURNS


func _ready() -> void:
	if series.is_empty():
		series = DEFAULT_SERIES.duplicate(true)
	set_anchors_preset(Control.PRESET_FULL_RECT)
	set_offsets_preset(Control.PRESET_FULL_RECT)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	EventBus.turn_advanced.connect(_on_refresh)
	EventBus.command_applied.connect(_on_refresh)
	EventBus.run_started.connect(_on_refresh)
	EventBus.run_loaded.connect(_on_refresh)
	resized.connect(_on_refresh)
	if get_parent() is Control:
		(get_parent() as Control).resized.connect(_on_refresh)


func set_history(new_history: Array) -> void:
	history = new_history
	queue_redraw()


func set_series(new_series: Array) -> void:
	series = new_series
	queue_redraw()


func _on_refresh(_a = null, _b = null) -> void:
	queue_redraw()


func _draw() -> void:
	var raw: Array = history
	if raw.is_empty() and Game.state != null:
		raw = Game.state.turn_history
	var data := _visible_data(raw)

	var rect := Rect2(Vector2.ZERO, _draw_size())
	draw_rect(rect, Color(0.08, 0.1, 0.09, 1.0))

	if data.is_empty():
		draw_string(ThemeDB.fallback_font, Vector2(8, 20), "No turn history yet", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.7, 0.7, 0.65))
		return

	var plot := Rect2(
		rect.position.x + PAD_LEFT,
		rect.position.y + PAD_TOP,
		maxf(1.0, rect.size.x - PAD_LEFT - PAD_RIGHT),
		maxf(1.0, rect.size.y - PAD_TOP - PAD_BOTTOM),
	)

	var max_val := 1
	for entry_variant in data:
		if typeof(entry_variant) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = entry_variant
		for spec_variant in series:
			if typeof(spec_variant) != TYPE_DICTIONARY:
				continue
			var spec: Dictionary = spec_variant
			max_val = maxi(max_val, int(entry.get(str(spec.get("key", "")), 0)))

	_draw_y_axis(plot, max_val)
	_draw_legend(rect, plot)

	var turn_bounds := _turn_bounds(data)
	for spec_variant in series:
		if typeof(spec_variant) != TYPE_DICTIONARY:
			continue
		var spec: Dictionary = spec_variant
		var key: String = str(spec.get("key", ""))
		var color: Color = spec.get("color", Color.WHITE)
		var points: PackedVector2Array = []
		for i in data.size():
			if typeof(data[i]) != TYPE_DICTIONARY:
				continue
			var entry: Dictionary = data[i]
			var x: float = _entry_x(plot, entry, i, data.size(), turn_bounds)
			var y: float = plot.position.y + plot.size.y - (float(int(entry.get(key, 0))) / float(max_val)) * plot.size.y
			points.append(Vector2(x, y))
		if points.size() >= 2:
			draw_polyline(points, color, 2.0)
		elif points.size() == 1:
			draw_circle(points[0], 3.0, color)

	_draw_x_labels(plot, data, turn_bounds)


func _visible_data(raw: Array) -> Array:
	var out: Array = []
	for entry_variant in raw:
		if typeof(entry_variant) == TYPE_DICTIONARY:
			out.append(entry_variant)
	var cap := maxi(1, max_visible_turns)
	if out.size() > cap:
		out = out.slice(out.size() - cap)
	return out


func _draw_size() -> Vector2:
	if size.x >= 16.0 and size.y >= 8.0:
		return size
	var parent := get_parent()
	if parent is Control:
		var parent_size: Vector2 = (parent as Control).size
		return Vector2(maxf(size.x, parent_size.x), maxf(size.y, parent_size.y))
	return size


func _turn_bounds(data: Array) -> Vector2i:
	var min_turn := 999999
	var max_turn := 0
	for entry_variant in data:
		if typeof(entry_variant) != TYPE_DICTIONARY:
			continue
		var turn_num := int((entry_variant as Dictionary).get("turn", 0))
		min_turn = mini(min_turn, turn_num)
		max_turn = maxi(max_turn, turn_num)
	if min_turn > max_turn:
		return Vector2i(0, 0)
	return Vector2i(min_turn, max_turn)


func _entry_x(plot: Rect2, entry: Dictionary, index: int, count: int, turn_bounds: Vector2i) -> float:
	if count <= 1:
		return plot.position.x + plot.size.x
	var min_turn := turn_bounds.x
	var max_turn := turn_bounds.y
	if max_turn > min_turn:
		var turn_num := int(entry.get("turn", index))
		return plot.position.x + (float(turn_num - min_turn) / float(max_turn - min_turn)) * plot.size.x
	return plot.position.x + (float(index) / float(count - 1)) * plot.size.x


static func fmt_axis_value(value: int) -> String:
	var abs_val: int = absi(value)
	if abs_val >= 1_000_000:
		return "$%.1fM" % (float(value) / 1_000_000.0)
	if abs_val >= 1000:
		return "$%.0fk" % (float(value) / 1000.0)
	return MathUtil.fmt_money(value)


func _draw_y_axis(plot: Rect2, max_val: int) -> void:
	var ticks := 4
	for i in ticks + 1:
		var frac: float = float(i) / float(ticks)
		var y: float = plot.position.y + plot.size.y - frac * plot.size.y
		var tick_val: int = int(round(float(max_val) * frac))
		draw_line(Vector2(plot.position.x - 4.0, y), Vector2(plot.position.x, y), Color(0.25, 0.28, 0.26, 0.8), 1.0)
		draw_string(
			ThemeDB.fallback_font,
			Vector2(4.0, y + 4.0),
			fmt_axis_value(tick_val),
			HORIZONTAL_ALIGNMENT_LEFT,
			int(plot.position.x - 8.0),
			10,
			Color(0.55, 0.55, 0.50),
		)


func _draw_legend(rect: Rect2, plot: Rect2) -> void:
	var active: Array = []
	for spec_variant in series:
		if typeof(spec_variant) == TYPE_DICTIONARY:
			active.append(spec_variant)
	if active.is_empty():
		return
	var slot_w: float = maxf(56.0, (rect.size.x - 8.0) / float(active.size()))
	var x: float = 4.0
	var y: float = rect.position.y + 8.0
	for spec_variant in active:
		var spec: Dictionary = spec_variant
		var color: Color = spec.get("color", Color.WHITE)
		var label: String = _legend_label(str(spec.get("label", "")), slot_w)
		draw_line(Vector2(x, y + 5.0), Vector2(x + 12.0, y + 5.0), color, 2.0)
		draw_string(
			ThemeDB.fallback_font,
			Vector2(x + 14.0, y + 9.0),
			label,
			HORIZONTAL_ALIGNMENT_LEFT,
			int(slot_w - 16.0),
			10,
			Color(0.7, 0.7, 0.65),
		)
		x += slot_w


static func _legend_label(full: String, slot_w: float) -> String:
	if slot_w >= 78.0:
		return full
	match full.to_lower():
		"net worth":
			return "NW"
		_:
			return full


func _draw_x_labels(plot: Rect2, data: Array, turn_bounds: Vector2i) -> void:
	if data.is_empty():
		return
	var count := data.size()
	var step := 1 if count <= max_visible_turns else maxi(1, int(ceil(float(count) / 5.0)))
	var drawn_turns: Dictionary = {}
	for i in range(0, count, step):
		_draw_turn_tick(plot, data, i, turn_bounds)
		if typeof(data[i]) == TYPE_DICTIONARY:
			drawn_turns[int((data[i] as Dictionary).get("turn", i))] = true
	if count > 1:
		var last_i := count - 1
		var last_turn := int((data[last_i] as Dictionary).get("turn", last_i)) if typeof(data[last_i]) == TYPE_DICTIONARY else last_i
		if not drawn_turns.has(last_turn):
			_draw_turn_tick(plot, data, last_i, turn_bounds)


func _draw_turn_tick(plot: Rect2, data: Array, index: int, turn_bounds: Vector2i) -> void:
	if index < 0 or index >= data.size() or typeof(data[index]) != TYPE_DICTIONARY:
		return
	var entry: Dictionary = data[index]
	var turn_num: int = int(entry.get("turn", index))
	var x: float = _entry_x(plot, entry, index, data.size(), turn_bounds)
	draw_line(Vector2(x, plot.position.y + plot.size.y), Vector2(x, plot.position.y + plot.size.y + 3.0), Color(0.35, 0.38, 0.34, 0.9), 1.0)
	draw_string(
		ThemeDB.fallback_font,
		Vector2(x - 10.0, plot.position.y + plot.size.y + 14.0),
		"T%d" % turn_num,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		9,
		Color(0.55, 0.55, 0.50),
	)
