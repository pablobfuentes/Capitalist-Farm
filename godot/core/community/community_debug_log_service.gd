# Human-readable community graph log for QA (8.3 dev tooling).
class_name CommunityDebugLogService
extends RefCounted

const LOG_DIR := "user://logs"
const LATEST_FILENAME := "community_map_latest.txt"


static func latest_path() -> String:
	return "%s/%s" % [LOG_DIR, LATEST_FILENAME]


static func latest_filesystem_path() -> String:
	return ProjectSettings.globalize_path(latest_path())


static func has_log() -> bool:
	return FileAccess.file_exists(latest_path())


static func read_latest() -> String:
	var path := latest_path()
	if not FileAccess.file_exists(path):
		return ""
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	return file.get_as_text()


static func write_from_state(state: RunState, district_id: String = "") -> Dictionary:
	if state == null:
		return {"ok": false, "error": "missing_state"}
	CommunityState.ensure_initialized(state)
	if not CommunityFeatureFlags.is_enabled(CommunityFeatureFlags.FLAG_COMMUNITY_GENERATION, state):
		return {"ok": false, "error": "community_generation_disabled", "skipped": true}

	var target := district_id if not district_id.is_empty() else CommunityConfig.mvp_district_id()
	var district_payload: Dictionary = state.community.get("districts", {}).get(target, {})
	if district_payload.is_empty() or not bool(district_payload.get("generated", false)):
		return {"ok": false, "error": "district_not_generated", "districtId": target}

	var body := format_mental_map(state, target)
	return write_text(body, state.run_seed, state.turn)


static func write_text(body: String, run_seed: int, turn: int = 0) -> Dictionary:
	DirAccess.make_dir_recursive_absolute(LOG_DIR)
	var latest := latest_path()
	var seeded := "%s/community_map_seed_%d_turn_%d.txt" % [LOG_DIR, run_seed, turn]
	for path in [latest, seeded]:
		var file := FileAccess.open(path, FileAccess.WRITE)
		if file == null:
			return {"ok": false, "error": "write_failed", "path": path}
		file.store_string(body)
	return {
		"ok": true,
		"path": latest,
		"seededPath": seeded,
		"bytes": body.length(),
	}


static func format_mental_map(state: RunState, district_id: String = "") -> String:
	var target := district_id if not district_id.is_empty() else CommunityConfig.mvp_district_id()
	var district_payload: Dictionary = state.community.get("districts", {}).get(target, {})
	if district_payload.is_empty():
		return "No generated community data for district: %s\nEnable community_generation and start a new run." % target

	var businesses: Dictionary = district_payload.get("businesses", {})
	var edges: Array = district_payload.get("supplyRelationships", [])
	var npcs: Dictionary = state.community.get("npcs", {})
	var facts_by_edge: Dictionary = _facts_by_edge_id(state.community.get("facts", {}))

	var cfg: Dictionary = CommunityConfig.generation_config()
	var validation: Dictionary = CommunityGraphValidator.validate(district_payload, cfg)
	var diagnostics: Dictionary = district_payload.get("diagnostics", {})

	var lines: PackedStringArray = []
	lines.append("COMMUNITY MENTAL MAP")
	lines.append("=".repeat(72))
	lines.append("District:     %s" % target)
	lines.append("Run seed:     %d" % state.run_seed)
	lines.append("Turn:         %d" % state.turn)
	lines.append("World ID:     %s" % str(state.community.get("worldId", "")))
	lines.append("Generator:    %s" % str(state.community.get("generatorVersion", "")))
	lines.append("Businesses:   %d" % businesses.size())
	lines.append("Supply edges: %d" % edges.size())
	lines.append("Connected:    %d (min %d)" % [
		int(validation.get("connectedBusinessCount", 0)),
		int(cfg.get("connectedBusinessMinimum", 15)),
	])
	lines.append("Validation:   %s" % ("OK" if bool(validation.get("valid", false)) else "ISSUES"))
	for err in validation.get("errors", []):
		lines.append("  ! %s" % str(err))
	lines.append("")
	lines.append("Log file:     %s" % latest_filesystem_path())
	lines.append("")

	lines.append("SUPPLY WEB (supplier ──→ client)")
	lines.append("-".repeat(72))
	lines.append(_format_supply_forest(businesses, edges, npcs, facts_by_edge))
	lines.append("")

	lines.append("ALL BUSINESSES")
	lines.append("-".repeat(72))
	for business_variant in _sorted_businesses(businesses):
		var business: Dictionary = business_variant
		lines.append(_format_business_line(business, npcs, true))
	lines.append("")

	lines.append("OPERATIONAL FACTS (one per supply edge)")
	lines.append("-".repeat(72))
	for edge_variant in edges:
		if typeof(edge_variant) != TYPE_DICTIONARY:
			continue
		var edge: Dictionary = edge_variant
		lines.append(_format_edge_fact_line(edge, businesses, npcs, facts_by_edge))
	lines.append("")

	lines.append("TEMPLATE MIX")
	lines.append("-".repeat(72))
	var template_counts: Dictionary = diagnostics.get("templateCounts", {})
	if template_counts.is_empty():
		template_counts = _count_templates(businesses)
	for template_id in template_counts.keys():
		lines.append("  %s × %d" % [str(template_id), int(template_counts[template_id])])

	return "\n".join(lines)


static func _format_supply_forest(
	businesses: Dictionary,
	edges: Array,
	npcs: Dictionary,
	facts_by_edge: Dictionary,
) -> String:
	var children: Dictionary = {}
	var is_client: Dictionary = {}
	for edge_variant in edges:
		if typeof(edge_variant) != TYPE_DICTIONARY:
			continue
		var edge: Dictionary = edge_variant
		var supplier_id := str(edge.get("supplierBusinessId", ""))
		var client_id := str(edge.get("clientBusinessId", ""))
		if not children.has(supplier_id):
			children[supplier_id] = []
		(children[supplier_id] as Array).append(edge)
		is_client[client_id] = true

	var roots: Array = []
	for business_id_key in businesses.keys():
		var business_id := str(business_id_key)
		if not is_client.has(business_id):
			roots.append(business_id)
	roots.sort()

	if roots.is_empty():
		for business_id_key in businesses.keys():
			roots.append(str(business_id_key))
		roots.sort()

	var lines: PackedStringArray = []
	var visited: Dictionary = {}
	for root_id in roots:
		lines.append_array(_format_supply_branch(
			str(root_id),
			businesses,
			npcs,
			children,
			facts_by_edge,
			visited,
			0,
			true,
		))

	var orphans: Array = []
	for business_id_key in businesses.keys():
		var business_id := str(business_id_key)
		if not visited.has(business_id):
			orphans.append(business_id)
	if not orphans.is_empty():
		lines.append("")
		lines.append("Unlinked in forest (cycles or isolated):")
		for orphan_id in orphans:
			var business: Dictionary = businesses.get(orphan_id, {})
			if not business.is_empty():
				lines.append("  • %s" % _format_business_line(business, npcs))
	return "\n".join(lines)


static func _format_supply_branch(
	business_id: String,
	businesses: Dictionary,
	npcs: Dictionary,
	children: Dictionary,
	facts_by_edge: Dictionary,
	visited: Dictionary,
	depth: int,
	is_root: bool,
) -> PackedStringArray:
	var lines: PackedStringArray = []
	var business: Dictionary = businesses.get(business_id, {})
	if business.is_empty():
		return lines

	var prefix := "  ".repeat(depth)
	var marker := "◆ " if is_root else "└─→ "
	if visited.has(business_id):
		lines.append("%s%s%s  ↺ (cycle back)" % [prefix, marker, _format_business_line(business, npcs)])
		return lines
	visited[business_id] = true

	lines.append("%s%s%s" % [prefix, marker, _format_business_line(business, npcs)])

	var outgoing: Array = children.get(business_id, [])
	outgoing.sort_custom(func(a, b):
		var client_a := str((a as Dictionary).get("clientBusinessId", ""))
		var client_b := str((b as Dictionary).get("clientBusinessId", ""))
		return client_a < client_b
	)
	for edge_variant in outgoing:
		var edge: Dictionary = edge_variant
		var client_id := str(edge.get("clientBusinessId", ""))
		var link := _format_edge_link(edge, facts_by_edge)
		lines.append("%s    │  %s" % [prefix, link])
		lines.append_array(_format_supply_branch(
			client_id,
			businesses,
			npcs,
			children,
			facts_by_edge,
			visited,
			depth + 1,
			false,
		))
	return lines


static func _format_edge_link(edge: Dictionary, facts_by_edge: Dictionary) -> String:
	var flow := str(edge.get("flow", edge.get("productTypeId", "supply")))
	var rel := float(edge.get("reliability", 0.0))
	var dep := float(edge.get("dependence", 0.0))
	var parts: PackedStringArray = [
		"[%s]" % flow,
		"rel %.2f" % rel,
		"dep %.0f%%" % (dep * 100.0),
	]
	var fact: Dictionary = facts_by_edge.get(str(edge.get("id", "")), {})
	if not fact.is_empty():
		var payload: Dictionary = fact.get("canonicalPayload", {})
		parts.append("fact: %s" % str(payload.get("summary", "")))
	return " · ".join(parts)


static func _format_business_line(business: Dictionary, npcs: Dictionary, include_id: bool = false) -> String:
	var template_id := str(business.get("templateId", ""))
	var template_name := template_id
	var tmpl := Content.get_template(template_id)
	if tmpl != null:
		template_name = tmpl.name
	var npc: Dictionary = npcs.get(str(business.get("ownerNpcId", "")), {})
	var npc_label := str(npc.get("displayName", business.get("ownerNpcId", "?")))
	var species := str(npc.get("speciesId", ""))
	if not species.is_empty():
		npc_label += " (%s)" % species
	var sale := str(business.get("saleState", "not_for_sale"))
	var head := "%s [%s]" % [str(business.get("displayName", template_id)), template_name]
	if include_id:
		head = "%s · %s" % [str(business.get("id", "")), head]
	return "%s @ %s · %s · %s" % [
		head,
		str(business.get("parcelId", "?")),
		npc_label,
		sale,
	]


static func _format_edge_fact_line(
	edge: Dictionary,
	businesses: Dictionary,
	npcs: Dictionary,
	facts_by_edge: Dictionary,
) -> String:
	var edge_id := str(edge.get("id", ""))
	var supplier: Dictionary = businesses.get(str(edge.get("supplierBusinessId", "")), {})
	var client: Dictionary = businesses.get(str(edge.get("clientBusinessId", "")), {})
	var fact: Dictionary = facts_by_edge.get(edge_id, {})
	var summary := ""
	if not fact.is_empty():
		summary = str(fact.get("canonicalPayload", {}).get("summary", ""))
	return "  %s → %s\n    edge %s · %s" % [
		_format_business_line(supplier, npcs) if not supplier.is_empty() else "?",
		_format_business_line(client, npcs) if not client.is_empty() else "?",
		edge_id,
		summary if not summary.is_empty() else "(no fact)",
	]


static func _facts_by_edge_id(facts: Variant) -> Dictionary:
	var by_edge: Dictionary = {}
	if typeof(facts) == TYPE_DICTIONARY:
		for fact_variant in (facts as Dictionary).values():
			if typeof(fact_variant) != TYPE_DICTIONARY:
				continue
			var fact: Dictionary = fact_variant
			by_edge[str(fact.get("subjectId", ""))] = fact
	elif typeof(facts) == TYPE_ARRAY:
		for fact_variant in facts:
			if typeof(fact_variant) != TYPE_DICTIONARY:
				continue
			var fact: Dictionary = fact_variant
			by_edge[str(fact.get("subjectId", ""))] = fact
	return by_edge


static func _sorted_businesses(businesses: Dictionary) -> Array:
	var sorted: Array = []
	for business_variant in businesses.values():
		if typeof(business_variant) == TYPE_DICTIONARY:
			sorted.append(business_variant)
	sorted.sort_custom(func(a, b):
		return str((a as Dictionary).get("displayName", "")) < str((b as Dictionary).get("displayName", ""))
	)
	return sorted


static func _count_templates(businesses: Dictionary) -> Dictionary:
	var counts: Dictionary = {}
	for business_id_key in businesses.keys():
		var template_id := str(businesses[business_id_key].get("templateId", ""))
		counts[template_id] = int(counts.get(template_id, 0)) + 1
	return counts
