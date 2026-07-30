class_name NegotiationChatBubble
extends Control

## Flat chat bubbles (WhatsApp-style). StyleBoxFlat only — no nine-slice textures.
## Text is measured first; the panel is forced to that size so nothing collapses.

enum Kind { NPC, PLAYER, SYSTEM }

const FONT_SIZE_BASE := 12
const MIN_TEXT_W := 56.0
## Max fraction of the *inner* chat column (after side pad + pointer reserve).
const MAX_WIDTH_FRAC := 0.78
## Keep bubbles clear of the chat parchment edges.
const COLUMN_PAD := 16.0
const TIP_W_BASE := 12.0
const TIP_H_BASE := 16.0

const _NPC_BG := Color(0.165, 0.29, 0.43, 1.0)
const _NPC_BORDER := Color(0.77, 0.65, 0.45, 1.0)
const _NPC_TEXT := Color(0.96, 0.95, 0.92, 1.0)

const _PLAYER_BG := Color(0.94, 0.90, 0.82, 1.0)
const _PLAYER_BORDER := Color(0.43, 0.30, 0.16, 1.0)
const _PLAYER_TEXT := Color(0.28, 0.18, 0.10, 1.0)

const _SYSTEM_BG := Color(0.42, 0.36, 0.28, 0.88)
const _SYSTEM_BORDER := Color(0.62, 0.52, 0.38, 1.0)
const _SYSTEM_TEXT := Color(0.96, 0.92, 0.84, 1.0)


class Tip extends Control:
	var points: PackedVector2Array = PackedVector2Array()
	var fill: Color = Color.WHITE
	var border: Color = Color.BLACK
	var border_w: float = 2.0

	func _draw() -> void:
		if points.size() < 3:
			return
		draw_colored_polygon(points, fill)
		var loop := PackedVector2Array(points)
		loop.append(points[0])
		draw_polyline(loop, border, border_w, true)


static func create(text: String, kind: Kind, column_width: float, ui_scale: float = 1.0) -> Control:
	var s := clampf(ui_scale, 0.72, 1.15)
	var font_size := maxi(10, int(round(FONT_SIZE_BASE * s)))
	var pad := COLUMN_PAD * s
	var tip_w := TIP_W_BASE * s
	# Inner width available for the bubble body (pointer sits in the pad/reserve).
	var usable := maxf(column_width - pad * 2.0 - tip_w, 120.0)

	match kind:
		Kind.SYSTEM:
			return _make_bubble(
				text, usable * 0.90, font_size, s, pad, tip_w,
				_SYSTEM_BG, _SYSTEM_BORDER, _SYSTEM_TEXT,
				Vector4(14, 8, 14, 8), true, 0,
			)
		Kind.PLAYER:
			return _make_bubble(
				text, usable * MAX_WIDTH_FRAC, font_size, s, pad, tip_w,
				_PLAYER_BG, _PLAYER_BORDER, _PLAYER_TEXT,
				Vector4(16, 12, 16, 12), false, 1,
			)
		_:
			return _make_bubble(
				text, usable * MAX_WIDTH_FRAC, font_size, s, pad, tip_w,
				_NPC_BG, _NPC_BORDER, _NPC_TEXT,
				Vector4(16, 12, 16, 12), false, -1,
			)


## side: -1 = left (NPC), 0 = center (system), 1 = right (player)
static func _make_bubble(
	text: String,
	max_bubble_w: float,
	font_size: int,
	s: float,
	column_pad: float,
	tip_w: float,
	bg: Color,
	border: Color,
	font_color: Color,
	content_m: Vector4,
	center_text: bool,
	side: int,
) -> Control:
	content_m *= s
	var max_text_w := maxf(max_bubble_w - content_m.x - content_m.z, MIN_TEXT_W * s)

	var font: Font = ThemeDB.fallback_font
	var measured := _measure(text, font, font_size, max_text_w)
	var text_w := clampf(measured.x + 1.0, MIN_TEXT_W * s, max_text_w)
	measured = _measure(text, font, font_size, text_w)
	var text_h := maxf(measured.y, float(font_size) * 1.25)

	var pad_l := content_m.x
	var pad_t := content_m.y
	var pad_r := content_m.z
	var pad_b := content_m.w
	var panel_w := text_w + pad_l + pad_r
	var panel_h := text_h + pad_t + pad_b

	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border
	style.set_border_width_all(maxi(1, int(round(2.0 * s))))
	style.set_corner_radius_all(int(round(14.0 * s)))
	style.content_margin_left = int(round(pad_l))
	style.content_margin_top = int(round(pad_t))
	style.content_margin_right = int(round(pad_r))
	style.content_margin_bottom = int(round(pad_b))

	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", font_color)
	if center_text:
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.custom_minimum_size = Vector2(text_w, text_h)

	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel", style)
	panel.custom_minimum_size = Vector2(panel_w, panel_h)
	panel.add_child(label)

	var bubble_root: Control = panel
	if side != 0:
		bubble_root = _with_side_pointer(panel, panel_w, panel_h, bg, border, side, s, tip_w)

	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 0)
	if side < 0:
		row.add_child(bubble_root)
		var spacer := Control.new()
		spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(spacer)
	elif side > 0:
		var spacer := Control.new()
		spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(spacer)
		row.add_child(bubble_root)
	else:
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		row.add_child(bubble_root)

	var wrap := MarginContainer.new()
	wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wrap.add_theme_constant_override("margin_left", int(round(column_pad)))
	wrap.add_theme_constant_override("margin_right", int(round(column_pad)))
	wrap.add_theme_constant_override("margin_top", int(round(4.0 * s)))
	wrap.add_theme_constant_override("margin_bottom", int(round(4.0 * s)))
	wrap.add_child(row)
	return wrap


static func _with_side_pointer(
	panel: Control,
	panel_w: float,
	panel_h: float,
	fill: Color,
	border: Color,
	side: int,
	s: float,
	tip_w: float,
) -> Control:
	var tip_h := TIP_H_BASE * s
	var holder := Control.new()
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.custom_minimum_size = Vector2(panel_w + tip_w, panel_h)

	var panel_x := tip_w if side < 0 else 0.0
	panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	panel.offset_left = panel_x
	panel.offset_top = 0.0
	panel.offset_right = panel_x + panel_w
	panel.offset_bottom = panel_h
	holder.add_child(panel)

	# Sit on the lower side edge, pointing outward (not into the bubble).
	var y := panel_h - maxf(18.0 * s, tip_h * 0.9)
	y = clampf(y, tip_h * 0.55, panel_h - tip_h * 0.55)
	var edge_x := panel_x if side < 0 else panel_x + panel_w
	# Overlap the edge by 1px so the tip joins the border cleanly.
	var join := 1.0

	var tip := Tip.new()
	tip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tip.fill = fill
	tip.border = border
	tip.border_w = maxf(1.5, 2.0 * s)
	tip.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if side < 0:
		tip.points = PackedVector2Array([
			Vector2(edge_x + join, y - tip_h * 0.5),
			Vector2(edge_x + join, y + tip_h * 0.5),
			Vector2(edge_x - tip_w, y),
		])
	else:
		tip.points = PackedVector2Array([
			Vector2(edge_x - join, y - tip_h * 0.5),
			Vector2(edge_x - join, y + tip_h * 0.5),
			Vector2(edge_x + tip_w, y),
		])
	holder.add_child(tip)
	return holder


static func kind_from_role(role: String) -> Kind:
	var r := role.strip_edges().to_lower()
	if r in ["player", "you"]:
		return Kind.PLAYER
	if r in ["system", "status", "info"]:
		return Kind.SYSTEM
	return Kind.NPC


static func _measure(text: String, font: Font, font_size: int, width: float) -> Vector2:
	if text.is_empty():
		return Vector2(MIN_TEXT_W, float(font_size) * 1.25)
	if font == null:
		var lines := maxi(1, int(ceil(float(text.length()) * font_size * 0.5 / maxf(width, 1.0))))
		return Vector2(minf(width, float(text.length()) * font_size * 0.55), float(lines) * font_size * 1.3)
	return font.get_multiline_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, width, font_size)
