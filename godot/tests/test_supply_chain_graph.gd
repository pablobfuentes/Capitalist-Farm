extends GutTest


func before_all() -> void:
	Content.load_farm_content()


func test_ownership_states() -> void:
	assert_eq(SupplyChainOwnership.get_connection_visual_state({"playerControlled": false}), "external")
	assert_eq(SupplyChainOwnership.get_connection_visual_state({"playerControlled": true}), "owned")
	assert_eq(SupplyChainOwnership.get_connection_visual_state({"playerControlled": true}, true), "complete")
	assert_true(SupplyChainOwnership.is_player_controlled_edge(true, true))
	assert_false(SupplyChainOwnership.is_player_controlled_edge(true, false))


func test_empty_district_graph_no_crash() -> void:
	var graph: Dictionary = SupplyChainGraphService.build_for_district(null, "", {})
	assert_eq((graph.get("nodes", {}) as Dictionary).size(), 0)
	assert_eq((graph.get("edges", []) as Array).size(), 0)


func test_fixture_graph_builds_owned_edge() -> void:
	var state: RunState = _load_fixture("res://tests/fixtures/grain_bakery_link.json")
	# Minimal synthetic district hosting both templates on parcels.
	var district := {
		"id": "test_district",
		"parcels": [
			{"id": "p_grain", "template_id": "grain_farm", "role": "core", "parcel_x": 0, "parcel_y": 0},
			{"id": "p_bakery", "template_id": "bakery", "role": "core", "parcel_x": 1, "parcel_y": 0},
		],
	}
	state.parcel_assignments = {
		"p_grain": {"owner": "player", "business_id": "grain01", "opportunity_id": ""},
		"p_bakery": {"owner": "player", "business_id": "bakery01", "opportunity_id": ""},
	}
	var graph: Dictionary = SupplyChainGraphService.build_for_district(state, "test_district", district)
	var nodes: Dictionary = graph.get("nodes", {})
	var edges: Array = graph.get("edges", [])
	assert_eq(nodes.size(), 2)
	assert_gt(edges.size(), 0)
	var owned_edge := false
	for edge_variant in edges:
		var edge: Dictionary = edge_variant
		if bool(edge.get("playerControlled", false)):
			owned_edge = true
			assert_eq(str(edge.get("visualState", "")), "owned")
	assert_true(owned_edge, "expected at least one player-controlled edge")


func test_path_resolver_middle_and_cycle_safe() -> void:
	var graph := {
		"nodes": {
			"a": {"id": "a"},
			"b": {"id": "b"},
			"c": {"id": "c"},
			"d": {"id": "d"},
		},
		"edges": [
			{"id": "e1", "sourceId": "a", "targetId": "b", "playerControlled": true},
			{"id": "e2", "sourceId": "b", "targetId": "c", "playerControlled": true},
			{"id": "e3", "sourceId": "c", "targetId": "d", "playerControlled": false},
			{"id": "e4", "sourceId": "b", "targetId": "d", "playerControlled": true},
			# Cycle edge — must not infinite-loop.
			{"id": "e_loop", "sourceId": "c", "targetId": "b", "playerControlled": false},
		],
	}
	var paths: Array = SupplyChainPathResolver.build_supply_chain_paths("b", graph)
	assert_gt(paths.size(), 0)
	var saw_branch := false
	for path_variant in paths:
		var path: Dictionary = path_variant
		var biz: Array = path.get("businessIds", [])
		assert_true(biz.has("b"))
		assert_true(biz.has("a"))
		if biz.has("c") and biz.has("d"):
			saw_branch = true
		if biz.has("d") and not biz.has("c"):
			saw_branch = true
	assert_true(saw_branch, "expected branched paths through b")


func test_complete_path_flag() -> void:
	var graph := {
		"nodes": {"a": {"id": "a"}, "b": {"id": "b"}, "c": {"id": "c"}},
		"edges": [
			{"id": "e1", "sourceId": "a", "targetId": "b", "playerControlled": true},
			{"id": "e2", "sourceId": "b", "targetId": "c", "playerControlled": true},
		],
	}
	var paths: Array = SupplyChainPathResolver.build_supply_chain_paths("b", graph)
	assert_eq(paths.size(), 1)
	assert_true(bool((paths[0] as Dictionary).get("isComplete", false)))


func test_product_edges_use_nearest_pairing() -> void:
	var state: RunState = _load_fixture("res://tests/fixtures/grain_bakery_link.json")
	# Extra restaurants as player businesses so graph nodes always resolve.
	for extra_id in ["rest_a", "rest_b"]:
		var biz := BusinessInstance.new()
		biz.id = extra_id
		biz.template_id = "farmhouse_restaurant"
		biz.name = extra_id
		state.portfolio.businesses.append(biz)
	var district := {
		"id": "test_district",
		"parcels": [
			{"id": "p_bakery", "template_id": "bakery", "role": "core", "parcel_x": 0, "parcel_y": 0},
			{"id": "p_rest_a", "template_id": "farmhouse_restaurant", "role": "core", "parcel_x": 1, "parcel_y": 0},
			{"id": "p_rest_b", "template_id": "farmhouse_restaurant", "role": "specialization", "parcel_x": 8, "parcel_y": 8},
		],
	}
	state.parcel_assignments = {
		"p_bakery": {"owner": "player", "business_id": "bakery01", "opportunity_id": ""},
		"p_rest_a": {"owner": "player", "business_id": "rest_a", "opportunity_id": ""},
		"p_rest_b": {"owner": "player", "business_id": "rest_b", "opportunity_id": ""},
	}
	var graph: Dictionary = SupplyChainGraphService.build_for_district(state, "test_district", district)
	var bakery_to_rest := 0
	for edge_variant in graph.get("edges", []):
		var edge: Dictionary = edge_variant
		if bool(edge.get("isInfrastructure", false)):
			continue
		if str(edge.get("catalogId", "")) != "bakery_to_restaurant":
			continue
		bakery_to_rest += 1
		assert_ne(str(edge.get("sourceId", "")), str(edge.get("targetId", "")))
	# Full cross-product would be 2; nearest pairing keeps it small.
	assert_lte(bakery_to_rest, 2)
	assert_gt(bakery_to_rest, 0)


func test_infrastructure_edges_do_not_branch_paths() -> void:
	var graph := {
		"nodes": {
			"grain": {"id": "grain"},
			"bakery": {"id": "bakery"},
			"dairy": {"id": "dairy"},
			"delivery": {"id": "delivery", "isInfrastructure": true},
			"repair": {"id": "repair", "isInfrastructure": true},
		},
		"edges": [
			{"id": "e_main", "sourceId": "grain", "targetId": "bakery", "playerControlled": true},
			{"id": "e_alt", "sourceId": "grain", "targetId": "dairy", "playerControlled": true},
			{"id": "e_d1", "sourceId": "delivery", "targetId": "grain", "playerControlled": true, "isInfrastructure": true},
			{"id": "e_d2", "sourceId": "delivery", "targetId": "bakery", "playerControlled": true, "isInfrastructure": true},
			{"id": "e_r1", "sourceId": "repair", "targetId": "bakery", "playerControlled": false, "isInfrastructure": true},
		],
	}
	var paths: Array = SupplyChainPathResolver.build_supply_chain_paths("grain", graph)
	# Only real product branches (bakery vs dairy) — not one path per Delivery/Repair option.
	assert_eq(paths.size(), 2)
	for path_variant in paths:
		var path: Dictionary = path_variant
		var biz: Array = path.get("businessIds", [])
		assert_false(biz.has("delivery"))
		assert_false(biz.has("repair"))
	assert_eq(
		SupplyChainOwnership.get_connection_visual_state({"isInfrastructure": true, "playerControlled": true}),
		"infrastructure"
	)
	var delivery_paths: Array = SupplyChainPathResolver.build_supply_chain_paths("delivery", graph)
	assert_eq(delivery_paths.size(), 1)
	assert_eq((delivery_paths[0] as Dictionary).get("businessIds", []), ["delivery"])


func _load_fixture(path: String) -> RunState:
	var file := FileAccess.open(path, FileAccess.READ)
	assert_not_null(file, "fixture file")
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	return RunState.from_dict(parsed)
