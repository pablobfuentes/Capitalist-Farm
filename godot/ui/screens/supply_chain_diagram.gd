extends Control

const LAYOUT: Dictionary = {
	"grain_farm": Vector2(80, 72),
	"vegetable_farm": Vector2(240, 72),
	"dairy_barn": Vector2(560, 72),
	"poultry_coop": Vector2(720, 72),
	"feed_mill": Vector2(160, 200),
	"bakery": Vector2(640, 200),
	"equipment_repair": Vector2(200, 340),
	"delivery_cold_storage": Vector2(520, 340),
	"farmhouse_restaurant": Vector2(280, 480),
	"general_store": Vector2(560, 480),
}

const NODE_SIZE := Vector2(118, 56)


func _ready() -> void:
	custom_minimum_size = Vector2(860, 560)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	if Game.state == null or not Game.state.is_capital_farm():
		draw_string(ThemeDB.fallback_font, Vector2(16, 24), "Supply chain diagram — Capital Farm only", HORIZONTAL_ALIGNMENT_LEFT, -1, 14)
		return
	var owned: Dictionary = Game.state.portfolio.owned_template_ids()
	var synergies: Array = SynergySystem.compute_synergies(Game.state)
	var syn_by_key: Dictionary = {}
	for syn_variant in synergies:
		if typeof(syn_variant) != TYPE_DICTIONARY:
			continue
		var syn: Dictionary = syn_variant
		var key: String = "%s|%s" % [str(syn.get("supplierTemplateId", "")), str(syn.get("customerTemplateId", ""))]
		syn_by_key[key] = syn

	for conn: SupplyConnection in Content.connections:
		if not LAYOUT.has(conn.supplier) or not LAYOUT.has(conn.customer):
			continue
		if not owned.has(conn.supplier) or not owned.has(conn.customer):
			continue
		var from: Vector2 = LAYOUT[conn.supplier] + NODE_SIZE * 0.5
		var to: Vector2 = LAYOUT[conn.customer] + NODE_SIZE * 0.5
		var key: String = "%s|%s" % [conn.supplier, conn.customer]
		var syn: Dictionary = syn_by_key.get(key, {})
		var strained: bool = bool(syn.get("capacityStrained", false))
		var color := Color(0.35, 0.65, 0.45, 0.9) if not strained else Color(0.85, 0.45, 0.35, 0.95)
		draw_line(from, to, color, 2.0)

	for template_id: String in LAYOUT.keys():
		var pos: Vector2 = LAYOUT[template_id]
		var tmpl := Content.get_template(template_id)
		var label: String = tmpl.name if tmpl else template_id
		var owned_here: bool = owned.has(template_id)
		var fill := Color(0.12, 0.18, 0.16, 0.95) if owned_here else Color(0.08, 0.08, 0.08, 0.55)
		var border := Color(0.78, 0.62, 0.28, 0.95) if owned_here else Color(0.25, 0.25, 0.25, 0.8)
		draw_rect(Rect2(pos, NODE_SIZE), fill)
		draw_rect(Rect2(pos, NODE_SIZE), border, false, 1.5)
		draw_string(ThemeDB.fallback_font, pos + Vector2(6, 20), label.substr(0, 16), HORIZONTAL_ALIGNMENT_LEFT, int(NODE_SIZE.x - 8), 11)
		if owned_here:
			var layer_text: String = tmpl.layer_label if tmpl else ""
			draw_string(ThemeDB.fallback_font, pos + Vector2(6, 38), layer_text, HORIZONTAL_ALIGNMENT_LEFT, int(NODE_SIZE.x - 8), 10, Color(0.65, 0.75, 0.7))
		else:
			draw_string(ThemeDB.fallback_font, pos + Vector2(6, 38), "not owned", HORIZONTAL_ALIGNMENT_LEFT, int(NODE_SIZE.x - 8), 10, Color(0.45, 0.45, 0.45))
