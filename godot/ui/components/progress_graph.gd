extends Control

## Multi-series progress chart (NW / Cash / Debt). Used on dashboard and run report.

const DEFAULT_SERIES: Array = [
	{"key": "netWorth", "label": "Net Worth", "color": Color(0.78, 0.62, 0.28, 0.95)},
	{"key": "cash", "label": "Cash", "color": Color(0.50, 0.75, 0.62, 0.95)},
	{"key": "debt", "label": "Debt", "color": Color(0.63, 0.28, 0.23, 0.95)},
]

const PAD_LEFT := 52.0
const PAD_RIGHT := 12.0
const PAD_TOP := 28.0
const PAD_BOTTOM := 24.0

var history: Array = []
var series: Array = []


func _ready() -> void:
	if series.is_empty():
		series = DEFAULT_SERIES.duplicate(true)
	EventBus.turn_advanced.connect(_on_refresh)
	EventBus.command_applied.connect(_on_refresh)
	EventBus.run_started.connect(_on_refresh)
	EventBus.run_loaded.connect(_on_refresh)
	resized.connect(_on_refresh)


func set_history(new_history: Array) -> void:
	history = new_history
	queue_redraw()


func set_series(new_series: Array) -> void:
	series = new_series
	queue_redraw()


func _on_refresh(_a = null, _b = null) -> void:
	queue_redraw()


func _draw() -> void:
	var data: Array = history
	if data.is_empty() and Game.state != null:
		data = Game.state.turn_history

	var rect := Rect2(Vector2.ZERO, size)
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
	_draw_legend(plot)

	for spec_variant in series:
		if typeof(spec_variant) != TYPE_DICTIONARY:
			continue
		var spec: Dictionary = spec_variant
		var key: String = str(spec.get("key", ""))
		var color: Color = spec.get("color", Color.WHITE)
		var points: PackedVector2Array = []
		var valid_count := 0
		for i in data.size():
			if typeof(data[i]) != TYPE_DICTIONARY:
				continue
			var entry: Dictionary = data[i]
			var x: float = plot.position.x + (float(i) / maxf(1.0, float(data.size() - 1))) * plot.size.x
			var y: float = plot.position.y + plot.size.y - (float(int(entry.get(key, 0))) / float(max_val)) * plot.size.y
			points.append(Vector2(x, y))
			valid_count += 1
		if valid_count >= 2:
			draw_polyline(points, color, 2.0)

	_draw_x_labels(plot, data)


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


func _draw_legend(plot: Rect2) -> void:
	var x: float = plot.position.x + 4.0
	var y: float = plot.position.y - 18.0
	for spec_variant in series:
		if typeof(spec_variant) != TYPE_DICTIONARY:
			continue
		var spec: Dictionary = spec_variant
		var color: Color = spec.get("color", Color.WHITE)
		draw_line(Vector2(x, y), Vector2(x + 14.0, y), color, 2.0)
		draw_string(
			ThemeDB.fallback_font,
			Vector2(x + 18.0, y + 4.0),
			str(spec.get("label", "")),
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			10,
			Color(0.7, 0.7, 0.65),
		)
		x += 88.0


func _draw_x_labels(plot: Rect2, data: Array) -> void:
	if data.size() <= 1:
		return
	var step: int = maxi(1, int(ceil(float(data.size()) / 6.0)))
	for i in range(0, data.size(), step):
		if typeof(data[i]) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = data[i]
		var turn_num: int = int(entry.get("turn", i))
		var x: float = plot.position.x + (float(i) / maxf(1.0, float(data.size() - 1))) * plot.size.x
		draw_string(
			ThemeDB.fallback_font,
			Vector2(x - 8.0, plot.position.y + plot.size.y + 16.0),
			"T%d" % turn_num,
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			10,
			Color(0.55, 0.55, 0.50),
		)
