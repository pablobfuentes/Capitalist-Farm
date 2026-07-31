# Procedural Meadowgate community graph generation (8.3 Phase 1).
class_name CommunityGenerator
extends RefCounted

const _Layout := preload("res://scenes/farm_map/district_layout_data.gd")

const SPECIES_POOL: Array[String] = ["hen", "horse", "pig", "donkey", "goat", "sheep"]


static func ensure_district_generated(state: RunState, district_id: String = "") -> Dictionary:
	CommunityState.ensure_initialized(state)
	if state == null:
		return {"ok": false, "error": "missing_state"}
	if not CommunityFeatureFlags.is_enabled(CommunityFeatureFlags.FLAG_COMMUNITY_GENERATION, state):
		return {"ok": false, "error": "feature_disabled", "skipped": true}
	if not Content.templates_by_id.size() > 0:
		Content.load_farm_content()
	CommunityChainCatalog.load_catalog()

	var target_district := district_id
	if target_district.is_empty():
		target_district = CommunityConfig.mvp_district_id()

	var districts: Dictionary = state.community.get("districts", {})
	if typeof(districts) != TYPE_DICTIONARY:
		districts = {}
		state.community["districts"] = districts
	var existing: Dictionary = districts.get(target_district, {})
	if bool(existing.get("generated", false)):
		sync_parcel_assignments(state, target_district)
		return {"ok": true, "skipped": true, "districtId": target_district}

	var payload := generate_district(state, target_district)
	if not bool(payload.get("ok", false)):
		push_warning(
			"CommunityGenerator: failed for %s (%s) validation=%s"
			% [target_district, str(payload.get("error", "")), str(payload.get("validation", {}))]
		)
		return payload

	_persist_district(state, target_district, payload)
	sync_parcel_assignments(state, target_district)
	return {"ok": true, "districtId": target_district, "diagnostics": payload.get("diagnostics", {})}


static func generate_district(state: RunState, district_id: String) -> Dictionary:
	var cfg: Dictionary = CommunityConfig.generation_config()
	var district: Dictionary = _Layout.load_district(_district_path(district_id))
	if district.is_empty():
		return {"ok": false, "error": "missing_district_layout:%s" % district_id}

	var slot_ids: Array = CommunityChainCatalog.district_slot_ids(district_id)
	if slot_ids.is_empty():
		return {"ok": false, "error": "missing_district_slots:%s" % district_id}

	var rng := SeededRng.new()
	rng.set_rng_seed(_district_seed(state, district_id))
	var max_attempts := int(cfg.get("supplyGraphMaxAttempts", 12))
	var last_payload: Dictionary = {}
	var last_validation: Dictionary = {}

	for attempt in max_attempts:
		var attempt_rng := SeededRng.new()
		attempt_rng.set_rng_seed(_district_seed(state, district_id) + attempt * 104729)
		last_payload = _build_district_payload(state, district_id, district, slot_ids, attempt_rng)
		last_validation = CommunityGraphValidator.validate(last_payload, cfg)
		last_payload["diagnostics"] = _merge_diagnostics(last_payload.get("diagnostics", {}), last_validation, attempt)
		if bool(last_validation.get("valid", false)):
			last_payload["ok"] = true
			return last_payload

	last_payload["ok"] = false
	last_payload["error"] = "graph_validation_failed"
	last_payload["validation"] = last_validation
	return last_payload


static func diagnostics_report(state: RunState, district_id: String = "") -> Dictionary:
	CommunityState.ensure_initialized(state)
	var target := district_id if not district_id.is_empty() else CommunityConfig.mvp_district_id()
	var districts: Dictionary = state.community.get("districts", {})
	var district_payload: Dictionary = districts.get(target, {})
	if district_payload.is_empty():
		return {"districtId": target, "generated": false}
	var cfg: Dictionary = CommunityConfig.generation_config()
	var validation: Dictionary = CommunityGraphValidator.validate(district_payload, cfg)
	return {
		"districtId": target,
		"generated": bool(district_payload.get("generated", false)),
		"worldId": str(state.community.get("worldId", "")),
		"seed": state.run_seed,
		"generatorVersion": str(state.community.get("generatorVersion", "")),
		"diagnostics": district_payload.get("diagnostics", {}),
		"validation": validation,
	}


static func seed_replay_batch(seeds: Array, district_id: String = "") -> Array:
	var reports: Array = []
	var target := district_id if not district_id.is_empty() else CommunityConfig.mvp_district_id()
	Content.load_farm_content()
	CommunityChainCatalog.load_catalog()
	CommunityConfig.load_config()
	for seed_variant in seeds:
		var seed_value := int(seed_variant)
		var state: RunState = RunState.create_new(GameMode.MODE_CAPITAL_FARM)
		state.run_seed = seed_value
		RunBootstrap.prepare_new_run(state)
		CommunityFeatureFlags.set_override(CommunityFeatureFlags.FLAG_COMMUNITY_GENERATION, true)
		var result: Dictionary = ensure_district_generated(state, target)
		var report: Dictionary = diagnostics_report(state, target)
		report["seed"] = seed_value
		report["generationOk"] = bool(result.get("ok", false))
		reports.append(report)
	CommunityFeatureFlags.reset_overrides()
	return reports


static func get_business(state: RunState, business_id: String) -> Dictionary:
	CommunityState.ensure_initialized(state)
	for district_payload_variant in (state.community.get("districts", {}) as Dictionary).values():
		if typeof(district_payload_variant) != TYPE_DICTIONARY:
			continue
		var district_payload: Dictionary = district_payload_variant
		var businesses: Dictionary = district_payload.get("businesses", {})
		if businesses.has(business_id):
			return (businesses[business_id] as Dictionary).duplicate(true)
	return {}


static func get_npc(state: RunState, npc_id: String) -> Dictionary:
	CommunityState.ensure_initialized(state)
	var npcs: Dictionary = state.community.get("npcs", {})
	if npcs.has(npc_id):
		return (npcs[npc_id] as Dictionary).duplicate(true)
	return {}


static func get_business_for_parcel(
	state: RunState,
	parcel_id: String,
	district_id: String = "",
) -> Dictionary:
	CommunityState.ensure_initialized(state)
	if parcel_id.is_empty():
		return {}
	var target_district := district_id
	if target_district.is_empty():
		target_district = CommunityConfig.mvp_district_id()
	var districts: Dictionary = state.community.get("districts", {})
	var district_payload: Dictionary = districts.get(target_district, {})
	var businesses: Dictionary = district_payload.get("businesses", {})
	for business_variant in businesses.values():
		if typeof(business_variant) != TYPE_DICTIONARY:
			continue
		var business: Dictionary = business_variant
		if str(business.get("parcelId", "")) == parcel_id:
			return business.duplicate(true)
	return {}


static func sync_parcel_assignments(state: RunState, district_id: String = "") -> void:
	if state == null or not ParcelOwnershipSystem.applies_to(state):
		return
	CommunityState.ensure_initialized(state)
	if not CommunityFeatureFlags.is_enabled(CommunityFeatureFlags.FLAG_COMMUNITY_GENERATION, state):
		return
	var target_district := district_id
	if target_district.is_empty():
		target_district = CommunityConfig.mvp_district_id()
	var district_payload: Dictionary = state.community.get("districts", {}).get(target_district, {})
	if not bool(district_payload.get("generated", false)):
		return
	var businesses: Dictionary = district_payload.get("businesses", {})
	for business_variant in businesses.values():
		if typeof(business_variant) != TYPE_DICTIONARY:
			continue
		var business: Dictionary = business_variant
		var parcel_id := str(business.get("parcelId", ""))
		var business_id := str(business.get("id", ""))
		if parcel_id.is_empty() or business_id.is_empty():
			continue
		var assignment: Dictionary = state.parcel_assignments.get(parcel_id, {})
		if typeof(assignment) != TYPE_DICTIONARY:
			assignment = {}
		if str(assignment.get("business_id", "")) != "":
			continue
		if str(assignment.get("opportunity_id", "")) != "":
			continue
		state.parcel_assignments[parcel_id] = {
			"owner": ParcelOwnershipSystem.OWNER_NPC,
			"business_id": "",
			"community_business_id": business_id,
			"opportunity_id": "",
			"npc_label": str(business.get("displayName", "Local operator")),
		}


static func _persist_district(state: RunState, district_id: String, payload: Dictionary) -> void:
	var districts: Dictionary = state.community.get("districts", {})
	districts[district_id] = {
		"generated": true,
		"generatedTurn": state.turn,
		"businesses": payload.get("businesses", {}),
		"supplyRelationships": payload.get("supplyRelationships", []),
		"diagnostics": payload.get("diagnostics", {}),
	}
	state.community["districts"] = districts

	var npcs: Dictionary = state.community.get("npcs", {})
	for npc_variant in (payload.get("npcs", []) as Array):
		if typeof(npc_variant) != TYPE_DICTIONARY:
			continue
		var npc: Dictionary = npc_variant
		npcs[str(npc.get("id", ""))] = npc
	state.community["npcs"] = npcs

	var facts: Dictionary = state.community.get("facts", {})
	for fact_variant in (payload.get("facts", []) as Array):
		if typeof(fact_variant) != TYPE_DICTIONARY:
			continue
		var fact: Dictionary = fact_variant
		facts[str(fact.get("id", ""))] = fact
	state.community["facts"] = facts

	var knowledge: Dictionary = state.community.get("npcFactKnowledge", {})
	for record_variant in (payload.get("npcFactKnowledge", []) as Array):
		if typeof(record_variant) != TYPE_DICTIONARY:
			continue
		var record: Dictionary = record_variant
		var npc_id := str(record.get("npcId", ""))
		var fact_id := str(record.get("factId", ""))
		if npc_id.is_empty() or fact_id.is_empty():
			continue
		if not knowledge.has(npc_id):
			knowledge[npc_id] = {}
		(knowledge[npc_id] as Dictionary)[fact_id] = {
			"knowledgeState": str(record.get("knowledgeState", "knows")),
			"confidence": float(record.get("confidence", 1.0)),
			"willingnessToDisclose": float(record.get("willingnessToDisclose", 0.5)),
		}
	state.community["npcFactKnowledge"] = knowledge

	for npc_id_key in (payload.get("socialNpcIds", []) as Array):
		CommunityState.get_social_state(state, str(npc_id_key))


static func _build_district_payload(
	state: RunState,
	district_id: String,
	district: Dictionary,
	slot_ids: Array,
	rng: SeededRng,
) -> Dictionary:
	var cfg: Dictionary = CommunityConfig.generation_config()
	var templates: Array = _select_templates(slot_ids.size(), rng, cfg)
	var slot_assignments: Array = _assign_templates_to_slots(templates, slot_ids, district, rng)
	var businesses: Dictionary = {}
	var npcs: Array = []
	var business_index := 1

	for slot_entry_variant in slot_assignments:
		if typeof(slot_entry_variant) != TYPE_DICTIONARY:
			continue
		var slot_entry: Dictionary = slot_entry_variant
		var business_index_value := business_index
		business_index += 1
		var business_id := CommunityIds.business_id(district_id, business_index_value)
		var npc_id := CommunityIds.npc_id(district_id, business_index_value)
		var template_id := str(slot_entry.get("templateId", ""))
		var parcel_id := str(slot_entry.get("parcelId", ""))
		var display_name := _business_display_name(template_id, business_index_value, rng)
		var species_id := _pick_species(template_id, rng)
		var npc_name := _npc_display_name(species_id, business_index_value, rng)

		businesses[business_id] = {
			"id": business_id,
			"districtId": district_id,
			"templateId": template_id,
			"parcelId": parcel_id,
			"displayName": display_name,
			"ownerNpcId": npc_id,
			"saleState": "not_for_sale",
			"index": business_index_value,
		}
		npcs.append({
			"id": npc_id,
			"districtId": district_id,
			"primaryBusinessId": business_id,
			"displayName": npc_name,
			"speciesId": species_id,
			"gossipTendency": rng.randf_range(0.2, 0.75),
			"personalityTraits": _species_traits(species_id),
			"voiceProfile": {"speciesId": species_id},
		})

	var edges: Array = _build_supply_relationships(businesses, district_id, rng)
	edges = _repair_graph_connectivity(businesses, edges, slot_assignments, district, district_id, rng, cfg)
	var fact_bundle: Dictionary = _build_operational_facts(businesses, edges, district_id, rng)
	var social_bundle: Dictionary = _build_social_facts(
		businesses,
		npcs,
		district_id,
		rng,
		int(fact_bundle.get("nextFactIndex", 1)),
	)
	var all_facts: Array = []
	all_facts.append_array(fact_bundle.get("facts", []) as Array)
	all_facts.append_array(social_bundle.get("facts", []) as Array)
	var all_knowledge: Array = []
	all_knowledge.append_array(fact_bundle.get("npcFactKnowledge", []) as Array)
	all_knowledge.append_array(social_bundle.get("npcFactKnowledge", []) as Array)
	var social_npc_ids: Array = []
	for npc_variant in npcs:
		if typeof(npc_variant) == TYPE_DICTIONARY:
			social_npc_ids.append(str((npc_variant as Dictionary).get("id", "")))

	return {
		"businesses": businesses,
		"supplyRelationships": edges,
		"npcs": npcs,
		"facts": all_facts,
		"npcFactKnowledge": all_knowledge,
		"socialNpcIds": social_npc_ids,
		"diagnostics": {
			"templateCounts": _template_counts(businesses),
			"slotCount": slot_ids.size(),
			"operationalFactCount": (fact_bundle.get("facts", []) as Array).size(),
			"socialFactCount": (social_bundle.get("facts", []) as Array).size(),
		},
	}


static func _select_templates(target_count: int, rng: SeededRng, cfg: Dictionary) -> Array:
	var selected: Array = []
	for chain_variant in CommunityChainCatalog.pick_chain_skeletons(rng, cfg):
		if typeof(chain_variant) != TYPE_DICTIONARY:
			continue
		var chain: Dictionary = chain_variant
		for template_variant in chain.get("templates", []):
			selected.append(str(template_variant))

	for required_variant in CommunityChainCatalog.required_templates():
		var required_id := str(required_variant)
		if required_id.is_empty():
			continue
		if required_id not in selected:
			selected.append(required_id)

	var fill_pool: Array = CommunityChainCatalog.fill_templates()
	while selected.size() < target_count:
		selected.append(_pick_connectable_template(selected, fill_pool, rng))

	if selected.size() > target_count:
		selected = selected.slice(0, target_count)
	return selected


static func _pick_connectable_template(selected: Array, fill_pool: Array, rng: SeededRng) -> String:
	if fill_pool.is_empty():
		return "grain_farm"
	var connection_map: Dictionary = CommunityChainCatalog.connection_map()
	var scored: Array = []
	for template_variant in fill_pool:
		var template_id := str(template_variant)
		var score := 0
		for existing_variant in selected:
			var existing_id := str(existing_variant)
			if template_id in CommunityChainCatalog.customers_of(existing_id, connection_map):
				score += 2
			if template_id in CommunityChainCatalog.suppliers_of(existing_id, connection_map):
				score += 2
		scored.append({"templateId": template_id, "score": score})
	scored.sort_custom(func(a, b): return int(a.score) > int(b.score))
	var top_score := int(scored[0].score)
	var top_candidates: Array = []
	for entry in scored:
		if int(entry.score) == top_score:
			top_candidates.append(str(entry.templateId))
	return str(top_candidates[rng.randi_range(0, top_candidates.size() - 1)])


static func _assign_templates_to_slots(
	templates: Array,
	slot_ids: Array,
	district: Dictionary,
	rng: SeededRng,
) -> Array:
	var parcel_by_id: Dictionary = {}
	for parcel_variant in district.get("parcels", []):
		if typeof(parcel_variant) != TYPE_DICTIONARY:
			continue
		var parcel: Dictionary = parcel_variant
		parcel_by_id[str(parcel.get("id", ""))] = parcel

	var remaining_templates: Array = templates.duplicate(true)
	var assignments: Array = []
	var unmatched_slots: Array = []

	for slot_id_variant in slot_ids:
		var slot_id := str(slot_id_variant)
		var parcel: Dictionary = parcel_by_id.get(slot_id, {})
		var authored_template := str(parcel.get("template_id", ""))
		var matched_idx := -1
		if not authored_template.is_empty():
			for i in remaining_templates.size():
				if str(remaining_templates[i]) == authored_template:
					matched_idx = i
					break
		if matched_idx >= 0:
			assignments.append({"parcelId": slot_id, "templateId": str(remaining_templates[matched_idx])})
			remaining_templates.remove_at(matched_idx)
		else:
			unmatched_slots.append(slot_id)

	for slot_id_variant in unmatched_slots:
		if remaining_templates.is_empty():
			break
		var idx := rng.randi_range(0, remaining_templates.size() - 1)
		assignments.append({"parcelId": str(slot_id_variant), "templateId": str(remaining_templates[idx])})
		remaining_templates.remove_at(idx)

	while not remaining_templates.is_empty() and assignments.size() < slot_ids.size():
		var idx := rng.randi_range(0, remaining_templates.size() - 1)
		var fallback_slot := str(slot_ids[mini(assignments.size(), slot_ids.size() - 1)])
		assignments.append({"parcelId": fallback_slot, "templateId": str(remaining_templates[idx])})
		remaining_templates.remove_at(idx)

	return assignments


static func _build_supply_relationships(businesses: Dictionary, district_id: String, rng: SeededRng) -> Array:
	var by_template: Dictionary = {}
	for business_id_key in businesses.keys():
		var business: Dictionary = businesses[business_id_key]
		var template_id := str(business.get("templateId", ""))
		if template_id.is_empty():
			continue
		if not by_template.has(template_id):
			by_template[template_id] = []
		(by_template[template_id] as Array).append(str(business_id_key))

	var edges: Array = []
	var seen: Dictionary = {}
	var connection_map: Dictionary = CommunityChainCatalog.connection_map()
	for supplier_template in connection_map.keys():
		if not by_template.has(supplier_template):
			continue
		for edge_def_variant in connection_map[supplier_template]:
			if typeof(edge_def_variant) != TYPE_DICTIONARY:
				continue
			var edge_def: Dictionary = edge_def_variant
			var customer_template := str(edge_def.get("customer", ""))
			if not by_template.has(customer_template):
				continue
			var supplier_ids: Array = by_template[supplier_template]
			var client_ids: Array = by_template[customer_template]
			var supplier_id := str(supplier_ids[rng.randi_range(0, supplier_ids.size() - 1)])
			var client_id := str(client_ids[rng.randi_range(0, client_ids.size() - 1)])
			if supplier_id == client_id:
				continue
			var pair_key := "%s->%s" % [supplier_id, client_id]
			if seen.has(pair_key):
				continue
			seen[pair_key] = true
			var product_type_id := str(edge_def.get("productTypeId", "supply"))
			edges.append({
				"id": CommunityIds.supply_relationship_id(supplier_id, client_id, product_type_id),
				"connectionId": str(edge_def.get("id", "")),
				"supplierBusinessId": supplier_id,
				"clientBusinessId": client_id,
				"productTypeId": product_type_id,
				"flow": str(edge_def.get("flow", "")),
				"status": "active",
				"reliability": rng.randf_range(0.55, 0.95),
				"dependence": rng.randf_range(0.25, 0.85),
				"inheritedOnSale": true,
			})
	return edges


static func _repair_graph_connectivity(
	businesses: Dictionary,
	edges: Array,
	slot_assignments: Array,
	district: Dictionary,
	district_id: String,
	rng: SeededRng,
	cfg: Dictionary,
) -> Array:
	var min_connected: int = int(cfg.get("connectedBusinessMinimum", 15))
	for _attempt in 8:
		var degree: Dictionary = _degree_map(businesses, edges)
		var connected := 0
		var isolated: Array = []
		for business_id_key in businesses.keys():
			var business_id := str(business_id_key)
			var deg := int(degree.get(business_id, 0))
			if deg >= 1:
				connected += 1
			else:
				isolated.append(business_id)
		if connected >= min_connected:
			return edges
		if isolated.is_empty():
			return edges
		var isolated_id := str(isolated[0])
		var swap_ok := _swap_isolated_template(isolated_id, businesses, slot_assignments, district, rng)
		if swap_ok:
			edges = _build_supply_relationships(businesses, district_id, rng)
	return edges


static func _swap_isolated_template(
	isolated_business_id: String,
	businesses: Dictionary,
	slot_assignments: Array,
	district: Dictionary,
	rng: SeededRng,
) -> bool:
	var business: Dictionary = businesses.get(isolated_business_id, {})
	var parcel_id := str(business.get("parcelId", ""))
	var parcel := _find_parcel(district, parcel_id)
	var role := str(parcel.get("role", "development"))
	if role not in ["development", "specialization"]:
		return false

	var existing_templates: Array = []
	for business_id_key in businesses.keys():
		if str(business_id_key) == isolated_business_id:
			continue
		existing_templates.append(str(businesses[business_id_key].get("templateId", "")))

	var fill_pool: Array = CommunityChainCatalog.fill_templates()
	var candidates: Array = []
	for template_variant in fill_pool:
		var template_id := str(template_variant)
		for existing_template_variant in existing_templates:
			var existing_template := str(existing_template_variant)
			if template_id in CommunityChainCatalog.customers_of(existing_template):
				candidates.append(template_id)
				break
			if template_id in CommunityChainCatalog.suppliers_of(existing_template):
				candidates.append(template_id)
				break
	if candidates.is_empty():
		return false

	var replacement := str(candidates[rng.randi_range(0, candidates.size() - 1)])
	businesses[isolated_business_id]["templateId"] = replacement
	for i in slot_assignments.size():
		var slot_entry: Dictionary = slot_assignments[i]
		if str(slot_entry.get("parcelId", "")) == parcel_id:
			slot_assignments[i]["templateId"] = replacement
			break
	return true


static func _build_operational_facts(
	businesses: Dictionary,
	edges: Array,
	district_id: String,
	rng: SeededRng,
) -> Dictionary:
	var facts: Array = []
	var knowledge: Array = []
	var issue_types: Array = CommunityChainCatalog.operational_issue_types()
	if issue_types.is_empty():
		return {"facts": facts, "npcFactKnowledge": knowledge, "nextFactIndex": 1}

	var fact_index := 1
	for edge_variant in edges:
		if typeof(edge_variant) != TYPE_DICTIONARY:
			continue
		var edge: Dictionary = edge_variant
		var supplier_id := str(edge.get("supplierBusinessId", ""))
		var client_id := str(edge.get("clientBusinessId", ""))
		var supplier: Dictionary = businesses.get(supplier_id, {})
		var client: Dictionary = businesses.get(client_id, {})
		if supplier.is_empty() or client.is_empty():
			continue

		var issue: Dictionary = issue_types[rng.randi_range(0, issue_types.size() - 1)]
		var issue_id := str(issue.get("id", "late_delivery"))
		var summaries: Array = issue.get("summaries", [])
		var summary_template := str(summaries[rng.randi_range(0, summaries.size() - 1)] if summaries.size() > 0 else "%s issue noted.")
		var flow_label := str(edge.get("flow", "supply"))
		var delay_days := rng.randi_range(1, 5)
		var summary: String
		if summary_template.find("%d") >= 0:
			summary = summary_template % [flow_label, delay_days]
		elif summary_template.find("%s") >= 0:
			summary = summary_template % flow_label
		else:
			summary = summary_template

		var fact_id := CommunityIds.fact_id(district_id, fact_index)
		fact_index += 1
		var topic_tags: Array = issue.get("topicTags", ["supply"])
		facts.append({
			"id": fact_id,
			"factType": "operational",
			"subjectType": "supply_relationship",
			"subjectId": str(edge.get("id", "")),
			"supplierBusinessId": supplier_id,
			"clientBusinessId": client_id,
			"truthState": "true",
			"canonicalPayload": {
				"issueType": issue_id,
				"severity": _issue_severity(rng),
				"summary": summary,
				"flow": flow_label,
				"topicTags": topic_tags,
			},
			"sensitivity": int(issue.get("sensitivity", 2)),
			"leverageTags": issue.get("leverageTags", []),
			"disclosureThreshold": _disclosure_threshold_for_sensitivity(int(issue.get("sensitivity", 2))),
			"createdTurn": 0,
		})

		var supplier_npc := str(supplier.get("ownerNpcId", ""))
		var client_npc := str(client.get("ownerNpcId", ""))
		if not supplier_npc.is_empty():
			knowledge.append({
				"npcId": supplier_npc,
				"factId": fact_id,
				"knowledgeState": "knows",
				"confidence": rng.randf_range(0.85, 1.0),
				"willingnessToDisclose": rng.randf_range(0.35, 0.75),
			})
		if not client_npc.is_empty():
			knowledge.append({
				"npcId": client_npc,
				"factId": fact_id,
				"knowledgeState": "knows",
				"confidence": rng.randf_range(0.75, 1.0),
				"willingnessToDisclose": rng.randf_range(0.45, 0.9),
			})

	return {"facts": facts, "npcFactKnowledge": knowledge, "nextFactIndex": fact_index}


static func _build_social_facts(
	businesses: Dictionary,
	npcs: Array,
	district_id: String,
	rng: SeededRng,
	start_fact_index: int = 1,
) -> Dictionary:
	var facts: Array = []
	var knowledge: Array = []
	var social_types: Array = CommunityChainCatalog.social_fact_types()
	if social_types.is_empty() or npcs.is_empty():
		return {"facts": facts, "npcFactKnowledge": knowledge, "nextFactIndex": start_fact_index}

	var business_ids: Array = businesses.keys()
	var fact_index := maxi(start_fact_index, 1)
	for npc_variant in npcs:
		if typeof(npc_variant) != TYPE_DICTIONARY:
			continue
		var npc: Dictionary = npc_variant
		var npc_id := str(npc.get("id", ""))
		var business_id := str(npc.get("primaryBusinessId", ""))
		var business: Dictionary = businesses.get(business_id, {})
		if npc_id.is_empty() or business.is_empty():
			continue
		var display_name := str(business.get("displayName", "this shop"))

		# Seed 2–3 social/atmospheric facts per owner for chat variety.
		var picks: Array = _pick_social_fact_types(social_types, rng, 2 + (1 if rng.randf() < 0.55 else 0))
		for type_variant in picks:
			if typeof(type_variant) != TYPE_DICTIONARY:
				continue
			var social_type: Dictionary = type_variant
			var summaries: Array = social_type.get("summaries", [])
			if summaries.is_empty():
				continue
			var template := str(summaries[rng.randi_range(0, summaries.size() - 1)])
			var summary := template
			var other_business_id := ""
			if bool(social_type.get("needsOtherBusiness", false)):
				other_business_id = _pick_other_business_id(business_ids, business_id, rng)
				if other_business_id.is_empty():
					continue
				var other_name := str(businesses.get(other_business_id, {}).get("displayName", "another shop"))
				if template.find("%s") >= 0:
					summary = template % [display_name, other_name]
				else:
					summary = template
			elif template.find("%s") >= 0:
				summary = template % display_name

			var fact_id := CommunityIds.fact_id(district_id, fact_index)
			fact_index += 1
			var fact_type := str(social_type.get("factType", "atmospheric"))
			var topic_tags: Array = social_type.get("topicTags", [fact_type])
			var sensitivity := int(social_type.get("sensitivity", 1))
			facts.append({
				"id": fact_id,
				"factType": fact_type,
				"subjectType": "business",
				"subjectId": business_id,
				"truthState": "true",
				"canonicalPayload": {
					"issueType": str(social_type.get("id", fact_type)),
					"summary": summary,
					"topicTags": topic_tags,
					"otherBusinessId": other_business_id,
				},
				"sensitivity": sensitivity,
				"leverageTags": social_type.get("leverageTags", []),
				"disclosureThreshold": _disclosure_threshold_for_sensitivity(sensitivity),
				"createdTurn": 0,
			})
			knowledge.append({
				"npcId": npc_id,
				"factId": fact_id,
				"knowledgeState": "knows",
				"confidence": rng.randf_range(0.8, 1.0),
				"willingnessToDisclose": rng.randf_range(0.5, 0.95),
			})

	return {"facts": facts, "npcFactKnowledge": knowledge, "nextFactIndex": fact_index}


static func _pick_social_fact_types(social_types: Array, rng: SeededRng, count: int) -> Array:
	if social_types.is_empty() or count <= 0:
		return []
	var pool: Array = social_types.duplicate()
	# Mild shuffle.
	for i in range(pool.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp: Variant = pool[i]
		pool[i] = pool[j]
		pool[j] = tmp
	var out: Array = []
	var used_ids: Dictionary = {}
	for type_variant in pool:
		if out.size() >= count:
			break
		if typeof(type_variant) != TYPE_DICTIONARY:
			continue
		var type_id := str((type_variant as Dictionary).get("id", ""))
		if used_ids.has(type_id):
			continue
		used_ids[type_id] = true
		out.append(type_variant)
	return out


static func _pick_other_business_id(business_ids: Array, self_id: String, rng: SeededRng) -> String:
	var candidates: Array = []
	for id_variant in business_ids:
		var bid := str(id_variant)
		if bid != self_id and not bid.is_empty():
			candidates.append(bid)
	if candidates.is_empty():
		return ""
	return str(candidates[rng.randi_range(0, candidates.size() - 1)])


static func _business_display_name(template_id: String, index: int, rng: SeededRng) -> String:
	var gen_data: Dictionary = CommunityChainCatalog.generation_data()
	var suffixes: Dictionary = gen_data.get("businessSuffixes", {})
	var options: Array = suffixes.get(template_id, [template_id.replace("_", " ").capitalize()])
	var suffix := str(options[rng.randi_range(0, options.size() - 1)])
	var tmpl := Content.get_template(template_id)
	if tmpl != null and not str(tmpl.name).is_empty() and rng.randf() < 0.35:
		return "%s #%d" % [tmpl.name, index]
	return suffix


static func _npc_display_name(species_id: String, index: int, rng: SeededRng) -> String:
	var gen_data: Dictionary = CommunityChainCatalog.generation_data()
	var first_names: Dictionary = gen_data.get("firstNames", {})
	var pool: Array = first_names.get(species_id, ["Pat"])
	var last_names: Array = gen_data.get("lastNames", ["River"])
	var first := str(pool[rng.randi_range(0, pool.size() - 1)])
	var last := str(last_names[rng.randi_range(0, last_names.size() - 1)])
	return "%s %s" % [first, last]


static func _pick_species(template_id: String, rng: SeededRng) -> String:
	if template_id in ["farmhouse_restaurant", "general_store"]:
		return "sheep" if rng.randf() < 0.35 else SPECIES_POOL[rng.randi_range(0, SPECIES_POOL.size() - 1)]
	if template_id in ["feed_mill", "equipment_repair"]:
		return "donkey" if rng.randf() < 0.35 else SPECIES_POOL[rng.randi_range(0, SPECIES_POOL.size() - 1)]
	return SPECIES_POOL[rng.randi_range(0, SPECIES_POOL.size() - 1)]


static func _species_traits(species_id: String) -> Array:
	match species_id:
		"pig":
			return ["calculating", "opportunistic"]
		"donkey":
			return ["stubborn", "skeptical"]
		"sheep":
			return ["reputation-sensitive", "herd-aware"]
		"goat":
			return ["fast", "package-oriented"]
		"horse":
			return ["proud", "continuity-focused"]
		"hen":
			return ["precise", "schedule-driven"]
		_:
			return ["practical"]


static func _district_seed(state: RunState, district_id: String) -> int:
	var slug := CommunityIds.district_slug(district_id)
	var hash := slug.hash()
	return int(state.run_seed) ^ hash


static func _district_path(district_id: String) -> String:
	if district_id == "meadowgate_commons":
		return _Layout.MEADOWGATE_PATH
	return "res://data/districts/%s.json" % district_id


static func _degree_map(businesses: Dictionary, edges: Array) -> Dictionary:
	var degree: Dictionary = {}
	for business_id_key in businesses.keys():
		degree[str(business_id_key)] = 0
	for edge_variant in edges:
		if typeof(edge_variant) != TYPE_DICTIONARY:
			continue
		var edge: Dictionary = edge_variant
		var supplier_id := str(edge.get("supplierBusinessId", ""))
		var client_id := str(edge.get("clientBusinessId", ""))
		if degree.has(supplier_id):
			degree[supplier_id] = int(degree[supplier_id]) + 1
		if degree.has(client_id):
			degree[client_id] = int(degree[client_id]) + 1
	return degree


static func _template_counts(businesses: Dictionary) -> Dictionary:
	var counts: Dictionary = {}
	for business_id_key in businesses.keys():
		var template_id := str(businesses[business_id_key].get("templateId", ""))
		counts[template_id] = int(counts.get(template_id, 0)) + 1
	return counts


static func _find_parcel(district: Dictionary, parcel_id: String) -> Dictionary:
	for parcel_variant in district.get("parcels", []):
		if typeof(parcel_variant) != TYPE_DICTIONARY:
			continue
		var parcel: Dictionary = parcel_variant
		if str(parcel.get("id", "")) == parcel_id:
			return parcel
	return {}


static func _issue_severity(rng: SeededRng) -> String:
	var roll := rng.randf()
	if roll < 0.25:
		return "low"
	if roll < 0.7:
		return "moderate"
	return "high"


static func _disclosure_threshold_for_sensitivity(sensitivity: int) -> float:
	match sensitivity:
		1:
			return 0.20
		2:
			return 0.35
		3:
			return 0.50
		4:
			return 0.65
		_:
			return CommunitySocialEffects.disclosure_default_threshold()


static func _merge_diagnostics(existing: Dictionary, validation: Dictionary, attempt: int) -> Dictionary:
	var merged := existing.duplicate(true)
	merged["attempt"] = attempt
	merged["connectedBusinessCount"] = validation.get("connectedBusinessCount", 0)
	merged["edgeCount"] = validation.get("edgeCount", 0)
	merged["valid"] = validation.get("valid", false)
	if validation.has("errors"):
		merged["errors"] = validation.get("errors", [])
	if validation.has("warnings"):
		merged["warnings"] = validation.get("warnings", [])
	return merged
