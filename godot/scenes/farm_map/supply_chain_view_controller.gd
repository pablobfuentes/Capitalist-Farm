extends Node

## Owns Supply Chain View state for the farm map (activation, selection, active path).

signal enabled_changed(enabled: bool)
signal selection_changed(node_id: String)
signal message_requested(text: String)
signal path_info_changed(index: int, total: int, paused: bool)

const _Graph := preload("res://core/systems/supply_chain_graph_service.gd")
const _Paths := preload("res://core/systems/supply_chain_path_resolver.gd")
const _SCOwn := preload("res://core/systems/supply_chain_ownership.gd")
const _World := preload("res://scenes/farm_map/world_layout_data.gd")

var enabled: bool = false
var selected_node_id: String = ""
var available_paths: Array = []
var active_path_index: int = 0
var auto_cycle_enabled: bool = true
var graph: Dictionary = {}

var _district_id: String = ""
var _district: Dictionary = {}
var _lots: Node2D = null
var _route_layer: Node2D = null
var _last_viz_parcel_id: String = ""
var _cycle_accum: float = 0.0
var _blocked_reasons: Dictionary = {} # reason -> true
var _manual_paused: bool = false
var _known_complete_keys: Dictionary = {} # biz_key -> true (seen this session before ack write)
const CYCLE_SEC := 3.0


func configure(lots: Node2D, route_layer: Node2D) -> void:
	_lots = lots
	_route_layer = route_layer


func set_district_context(district_id: String, district: Dictionary) -> void:
	_district_id = district_id
	_district = district
	if enabled:
		rebuild(true)


func is_enabled() -> bool:
	return enabled


func enable_view(preferred_parcel_id: String = "") -> void:
	enabled = true
	_manual_paused = false
	_blocked_reasons.clear()
	_sync_cycle_enabled()
	if _route_layer != null and _route_layer.has_method("set_enabled"):
		_route_layer.set_enabled(true)
	if _lots != null and _lots.has_method("set_supply_chain_highlights"):
		_lots.set_supply_chain_highlights(true, [])
	rebuild(false)
	var pick := preferred_parcel_id
	if pick.is_empty() and _lots != null and _lots.has_method("get_selection"):
		var sel: Dictionary = _lots.get_selection()
		pick = str(sel.get("id", ""))
	var node_id := _Graph.pick_initial_node_id(graph, pick)
	if node_id.is_empty():
		selected_node_id = ""
		available_paths.clear()
		active_path_index = 0
		_render_active_path(false)
		_emit_path_info()
		message_requested.emit("No supply chains available in this district")
	else:
		select_node(node_id)
	enabled_changed.emit(true)
	set_process(true)


func disable_view() -> void:
	enabled = false
	selected_node_id = ""
	available_paths.clear()
	active_path_index = 0
	_last_viz_parcel_id = ""
	_cycle_accum = 0.0
	_blocked_reasons.clear()
	_manual_paused = false
	auto_cycle_enabled = false
	graph = {}
	if _route_layer != null and _route_layer.has_method("set_enabled"):
		_route_layer.set_enabled(false)
	if _lots != null and _lots.has_method("set_supply_chain_highlights"):
		_lots.set_supply_chain_highlights(false, [])
	set_process(false)
	_emit_path_info()
	enabled_changed.emit(false)


func toggle_view(preferred_parcel_id: String = "") -> void:
	if enabled:
		disable_view()
	else:
		enable_view(preferred_parcel_id)


func rebuild(keep_selection: bool) -> void:
	if Game.state == null or _district_id.is_empty() or _district.is_empty():
		graph = _Graph.build_for_district(null, "", {})
		return
	var prev := selected_node_id
	var prev_complete_key := _active_path_key()
	graph = _Graph.build_for_district(Game.state, _district_id, _district)
	if not keep_selection:
		return
	if prev.is_empty() or not (graph.get("nodes", {}) as Dictionary).has(prev):
		var node_id := _Graph.pick_initial_node_id(graph, _last_viz_parcel_id)
		if node_id.is_empty():
			selected_node_id = ""
			available_paths.clear()
			_render_active_path(false)
			_emit_path_info()
			message_requested.emit("No supply chains available in this district")
		else:
			select_node(node_id)
	else:
		select_node(prev)
		# Celebrate if a path newly became complete after ownership change.
		_maybe_celebrate_became_complete(prev_complete_key)


## Returns true if the click was consumed by viz mode.
func handle_parcel_click(hit: Dictionary) -> bool:
	if not enabled:
		return false
	if hit.is_empty():
		return true
	var parcel_id := str(hit.get("id", ""))
	var district_id := str(hit.get("district_id", ""))
	if district_id != _district_id:
		return true
	var node_id := _Graph.find_node_id_for_parcel(graph, parcel_id)
	if node_id.is_empty():
		message_requested.emit("No supply chain connections")
		_last_viz_parcel_id = parcel_id
		return true
	if parcel_id == _last_viz_parcel_id and node_id == selected_node_id:
		_last_viz_parcel_id = ""
		return false
	select_node(node_id)
	_last_viz_parcel_id = parcel_id
	if _lots != null and _lots.has_method("set_selection"):
		_lots.set_selection(hit)
	return true


func select_node(node_id: String) -> void:
	selected_node_id = node_id
	available_paths = _Paths.build_supply_chain_paths(node_id, graph)
	active_path_index = 0
	_cycle_accum = 0.0
	if not _node_has_any_edge(node_id):
		available_paths.clear()
		message_requested.emit("No supply chain connections")
	_render_active_path(false)
	_maybe_celebrate_complete()
	_emit_path_info()
	selection_changed.emit(node_id)


func _node_has_any_edge(node_id: String) -> bool:
	if node_id.is_empty():
		return false
	for edge_variant in graph.get("edges", []):
		if typeof(edge_variant) != TYPE_DICTIONARY:
			continue
		var edge: Dictionary = edge_variant
		if str(edge.get("sourceId", "")) == node_id or str(edge.get("targetId", "")) == node_id:
			return true
	return false


func show_next_path() -> void:
	if available_paths.size() <= 1:
		return
	active_path_index = (active_path_index + 1) % available_paths.size()
	_cycle_accum = 0.0
	_render_active_path(true)
	_emit_path_info()


func show_previous_path() -> void:
	if available_paths.size() <= 1:
		return
	active_path_index = (active_path_index - 1 + available_paths.size()) % available_paths.size()
	_cycle_accum = 0.0
	_render_active_path(true)
	_emit_path_info()


func pause_cycling() -> void:
	_manual_paused = true
	_sync_cycle_enabled()
	_emit_path_info()


func resume_cycling() -> void:
	_manual_paused = false
	_sync_cycle_enabled()
	_emit_path_info()


func set_blocked(reason: String, blocked: bool) -> void:
	if reason.is_empty():
		return
	var was_blocked := _blocked_reasons.has(reason)
	if blocked == was_blocked:
		return
	if blocked:
		_blocked_reasons[reason] = true
	else:
		_blocked_reasons.erase(reason)
	_sync_cycle_enabled()
	_emit_path_info()


func is_cycling_paused() -> bool:
	return not auto_cycle_enabled


func _sync_cycle_enabled() -> void:
	auto_cycle_enabled = enabled and not _manual_paused and _blocked_reasons.is_empty()


func tooltip_at_world(world_pos: Vector2) -> Dictionary:
	if not enabled or _route_layer == null or not _route_layer.has_method("tooltip_at_world"):
		return {}
	return _route_layer.tooltip_at_world(world_pos)


## Chain summary for lot/route hover: prev → selected → next with acquisition profit gains.
func chain_hover_info() -> Dictionary:
	if not enabled or selected_node_id.is_empty() or available_paths.is_empty():
		return {}
	if active_path_index < 0 or active_path_index >= available_paths.size():
		return {}
	var path: Dictionary = available_paths[active_path_index]
	var biz_ids: Array = path.get("businessIds", [])
	if biz_ids.is_empty():
		return {}
	var sel_i := -1
	for i in biz_ids.size():
		if str(biz_ids[i]) == selected_node_id:
			sel_i = i
			break
	if sel_i < 0:
		return {}
	var nodes: Dictionary = graph.get("nodes", {})
	var prev_node: Dictionary = {}
	var next_node: Dictionary = {}
	if sel_i > 0:
		prev_node = nodes.get(str(biz_ids[sel_i - 1]), {})
	if sel_i < biz_ids.size() - 1:
		next_node = nodes.get(str(biz_ids[sel_i + 1]), {})
	var selected_node: Dictionary = nodes.get(selected_node_id, {})
	return {
		"prev": _hover_node_payload(prev_node),
		"selected": _hover_node_payload(selected_node),
		"next": _hover_node_payload(next_node),
	}


func _hover_node_payload(node: Dictionary) -> Dictionary:
	if node.is_empty():
		return {}
	var owned := bool(node.get("playerOwned", false))
	var profit := _estimate_node_profit(node)
	return {
		"name": str(node.get("displayName", node.get("templateId", "?"))),
		"owned": owned,
		"profit": profit,
		"parcelId": str(node.get("parcelId", "")),
	}


func _estimate_node_profit(node: Dictionary) -> int:
	if node.is_empty() or Game.state == null:
		return 0
	if bool(node.get("playerOwned", false)):
		var biz_id := str(node.get("businessId", ""))
		for biz in Game.state.portfolio.businesses:
			if biz is BusinessInstance and (biz as BusinessInstance).id == biz_id:
				var b: BusinessInstance = biz
				return b.revenue_per_turn - b.operating_costs
	var opp_id := str(node.get("opportunityId", ""))
	if not opp_id.is_empty():
		var opp: Dictionary = OpportunitySystem.find_opportunity(Game.state, opp_id)
		if not opp.is_empty():
			return int(opp.get("revenue", 0)) - int(opp.get("cost", 0))
	var template_id := str(node.get("templateId", ""))
	var tmpl := Content.get_template(template_id)
	if tmpl == null:
		return 0
	var rev := _range_mid(tmpl.rev_range)
	var margin := _range_mid(tmpl.margin_range)
	if rev <= 0.0:
		return 0
	if margin <= 0.0:
		margin = 0.18
	return maxi(0, int(round(rev * margin)))


func _range_mid(values: Array) -> float:
	if values.is_empty():
		return 0.0
	if values.size() == 1:
		return float(values[0])
	return (float(values[0]) + float(values[1])) * 0.5


func _process(delta: float) -> void:
	if not enabled or not auto_cycle_enabled:
		return
	if available_paths.size() <= 1:
		return
	_cycle_accum += delta
	if _cycle_accum >= CYCLE_SEC:
		_cycle_accum = 0.0
		show_next_path()


func _emit_path_info() -> void:
	path_info_changed.emit(active_path_index, available_paths.size(), is_cycling_paused())


func _render_active_path(crossfade: bool) -> void:
	if _route_layer == null or not _route_layer.has_method("set_routes"):
		return
	if not enabled or selected_node_id.is_empty() or available_paths.is_empty():
		_route_layer.clear_routes()
		if _lots != null and _lots.has_method("set_supply_chain_highlights"):
			_lots.set_supply_chain_highlights(enabled, [])
		return
	var path: Dictionary = available_paths[active_path_index]
	var nodes: Dictionary = graph.get("nodes", {})
	var edges_by_id: Dictionary = {}
	for edge_variant in graph.get("edges", []):
		if typeof(edge_variant) == TYPE_DICTIONARY:
			var e: Dictionary = edge_variant
			edges_by_id[str(e.get("id", ""))] = e

	var routes: Array = []
	var connection_ids: Array = path.get("connectionIds", [])
	var complete := bool(path.get("isComplete", false))
	var drawn_edge_ids: Dictionary = {}
	for cid_variant in connection_ids:
		var edge: Dictionary = edges_by_id.get(str(cid_variant), {})
		if edge.is_empty():
			continue
		var route := _route_dict_for_edge(edge, nodes, complete)
		if route.is_empty():
			continue
		routes.append(route)
		drawn_edge_ids[str(edge.get("id", ""))] = true

	# Pink Delivery / Repair links only when that support business itself is selected.
	var selected_meta: Dictionary = nodes.get(selected_node_id, {})
	if bool(selected_meta.get("isInfrastructure", false)):
		for edge_variant in graph.get("edges", []):
			if typeof(edge_variant) != TYPE_DICTIONARY:
				continue
			var infra_edge: Dictionary = edge_variant
			if not bool(infra_edge.get("isInfrastructure", false)):
				continue
			var eid := str(infra_edge.get("id", ""))
			if eid.is_empty() or drawn_edge_ids.has(eid):
				continue
			var s := str(infra_edge.get("sourceId", ""))
			var t := str(infra_edge.get("targetId", ""))
			if s != selected_node_id and t != selected_node_id:
				continue
			var infra_route := _route_dict_for_edge(infra_edge, nodes, false)
			if infra_route.is_empty():
				continue
			routes.append(infra_route)
			drawn_edge_ids[eid] = true

	var selected_node: Dictionary = nodes.get(selected_node_id, {})
	var selected_center := _anchor_for_node(selected_node, "center")
	var complete_centers: Array = []
	if complete:
		for bid_variant in path.get("businessIds", []):
			var n: Dictionary = nodes.get(str(bid_variant), {})
			if bool(n.get("isInfrastructure", false)):
				continue
			var c := _anchor_for_node(n, "center")
			if c != Vector2.ZERO:
				complete_centers.append(c)
	_route_layer.set_routes(routes, selected_center, complete, complete_centers, crossfade)
	_sync_chain_lot_highlights(path, nodes)


func _sync_chain_lot_highlights(path: Dictionary, nodes: Dictionary) -> void:
	if _lots == null or not _lots.has_method("set_supply_chain_highlights"):
		return
	if not enabled:
		_lots.set_supply_chain_highlights(false, [])
		return
	var neighbors: Array = []
	var biz_ids: Array = path.get("businessIds", [])
	var sel_i := -1
	for i in biz_ids.size():
		if str(biz_ids[i]) == selected_node_id:
			sel_i = i
			break
	var neighbor_ids: Array[String] = []
	if sel_i > 0:
		neighbor_ids.append(str(biz_ids[sel_i - 1]))
	if sel_i >= 0 and sel_i < biz_ids.size() - 1:
		neighbor_ids.append(str(biz_ids[sel_i + 1]))
	for nid in neighbor_ids:
		var node: Dictionary = nodes.get(nid, {})
		var hit := _parcel_hit_for_node(node)
		if not hit.is_empty():
			neighbors.append(hit)
	_lots.set_supply_chain_highlights(true, neighbors)


func _parcel_hit_for_node(node: Dictionary) -> Dictionary:
	if node.is_empty():
		return {}
	var parcel_id := str(node.get("parcelId", ""))
	if parcel_id.is_empty():
		return {}
	var hit := {
		"id": parcel_id,
		"district_id": str(node.get("districtId", _district_id)),
		"_district": _district,
		"_region_entry": _region_entry_for_district(str(node.get("districtId", _district_id))),
	}
	for parcel_variant in _district.get("parcels", []):
		if typeof(parcel_variant) != TYPE_DICTIONARY:
			continue
		var parcel: Dictionary = parcel_variant
		if str(parcel.get("id", "")) == parcel_id:
			for key in parcel.keys():
				hit[key] = parcel[key]
			break
	return hit


func _route_dict_for_edge(edge: Dictionary, nodes: Dictionary, path_complete: bool) -> Dictionary:
	var source: Dictionary = nodes.get(str(edge.get("sourceId", "")), {})
	var target: Dictionary = nodes.get(str(edge.get("targetId", "")), {})
	var from := _anchor_for_node(source, "outgoing")
	var to := _anchor_for_node(target, "incoming")
	if from == Vector2.ZERO or to == Vector2.ZERO:
		return {}
	var visual := _SCOwn.get_connection_visual_state(edge, path_complete)
	var status := "Shared Support"
	if visual == _SCOwn.STATE_INFRASTRUCTURE:
		status = "Delivery / Repair"
	elif path_complete:
		status = "Complete Chain"
	elif visual == _SCOwn.STATE_OWNED:
		status = "Player Controlled"
	else:
		status = "External"
	return {
		"from": from,
		"to": to,
		"visualState": visual,
		"label": "%s → %s" % [
			str(source.get("displayName", source.get("templateId", "?"))),
			str(target.get("displayName", target.get("templateId", "?"))),
		],
		"resource": str(edge.get("resourceType", edge.get("flow", ""))),
		"status": status,
		"edge": edge,
	}


func _anchor_for_node(node: Dictionary, direction: String = "center") -> Vector2:
	if node.is_empty() or _lots == null or not _lots.has_method("get_parcel_frame"):
		return Vector2.ZERO
	var parcel_id := str(node.get("parcelId", ""))
	if parcel_id.is_empty():
		return Vector2.ZERO
	var hit := {
		"id": parcel_id,
		"district_id": str(node.get("districtId", _district_id)),
		"_district": _district,
		"_region_entry": _region_entry_for_district(str(node.get("districtId", _district_id))),
	}
	for parcel_variant in _district.get("parcels", []):
		if typeof(parcel_variant) != TYPE_DICTIONARY:
			continue
		var parcel: Dictionary = parcel_variant
		if str(parcel.get("id", "")) == parcel_id:
			for key in parcel.keys():
				hit[key] = parcel[key]
			break
	var frame: Dictionary = _lots.get_parcel_frame(hit)
	var center: Vector2 = frame.get("center", Vector2.ZERO)
	if center == Vector2.ZERO:
		return Vector2.ZERO
	# Prefer roof / loading-bay style offsets instead of geometric dead-center.
	match direction:
		"outgoing":
			return center + Vector2(10, -18)
		"incoming":
			return center + Vector2(-10, -14)
		_:
			return center + Vector2(0, -16)


func _region_entry_for_district(district_id: String) -> Dictionary:
	var region: Dictionary = _World.load_region()
	return _World.find_entry_by_id(region, district_id)


func _active_path_key() -> String:
	if available_paths.is_empty() or active_path_index < 0 or active_path_index >= available_paths.size():
		return ""
	var path: Dictionary = available_paths[active_path_index]
	if not bool(path.get("isComplete", false)):
		return ""
	return _path_biz_key(path)


func _path_biz_key(path: Dictionary) -> String:
	var packed := PackedStringArray()
	for id_variant in path.get("businessIds", []):
		packed.append(str(id_variant))
	return "|".join(packed)


func _maybe_celebrate_complete() -> void:
	if available_paths.is_empty() or Game.state == null:
		return
	var path: Dictionary = available_paths[active_path_index]
	if not bool(path.get("isComplete", false)):
		return
	_ack_and_celebrate(path)


func _maybe_celebrate_became_complete(prev_complete_key: String) -> void:
	if available_paths.is_empty():
		return
	var path: Dictionary = available_paths[active_path_index]
	if not bool(path.get("isComplete", false)):
		return
	var key := _path_biz_key(path)
	# Only fire when it wasn't complete before this rebuild.
	if not prev_complete_key.is_empty() and prev_complete_key == key:
		return
	_ack_and_celebrate(path)


func _ack_and_celebrate(path: Dictionary) -> void:
	if Game.state == null:
		return
	var stats: Dictionary = RunStatsSystem.ensure(Game.state)
	var ack: Dictionary = stats.get("supplyChainCompleteAck", {})
	if typeof(ack) != TYPE_DICTIONARY:
		ack = {}
	var biz_key := _path_biz_key(path)
	var key := "%s|%s" % [_district_id, str(path.get("id", ""))]
	if ack.has(biz_key) or ack.has(key):
		return
	ack[biz_key] = true
	stats["supplyChainCompleteAck"] = ack
	FeedbackBus.toast_success("Complete Supply Chain")
	FeedbackBus.show_chip("Complete Supply Chain", null, 2.4)
	FeedbackBus.crest_burst(false)
