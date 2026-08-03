class_name SupplyChainPathResolver
extends RefCounted

const MAX_PATHS := 24
const MAX_DEPTH := 12


## Build all simple root→sink paths that include selected_node_id.
static func build_supply_chain_paths(selected_node_id: String, graph: Dictionary) -> Array:
	var out: Array = []
	if selected_node_id.is_empty():
		return out
	var nodes: Dictionary = graph.get("nodes", {})
	if not nodes.has(selected_node_id):
		return out

	var outgoing: Dictionary = {}
	var incoming: Dictionary = {}
	var edges_by_id: Dictionary = {}
	for edge_variant in graph.get("edges", []):
		if typeof(edge_variant) != TYPE_DICTIONARY:
			continue
		var edge: Dictionary = edge_variant
		var eid := str(edge.get("id", ""))
		var s := str(edge.get("sourceId", ""))
		var t := str(edge.get("targetId", ""))
		if eid.is_empty() or s.is_empty() or t.is_empty():
			continue
		edges_by_id[eid] = edge
		if not outgoing.has(s):
			outgoing[s] = []
		(outgoing[s] as Array).append(eid)
		if not incoming.has(t):
			incoming[t] = []
		(incoming[t] as Array).append(eid)

	var upstream: Array = _paths_ending_at(selected_node_id, incoming, edges_by_id)
	var downstream: Array = _paths_starting_at(selected_node_id, outgoing, edges_by_id)

	var path_i := 0
	for up_variant in upstream:
		if typeof(up_variant) != TYPE_DICTIONARY:
			continue
		var up: Dictionary = up_variant
		for down_variant in downstream:
			if typeof(down_variant) != TYPE_DICTIONARY:
				continue
			var down: Dictionary = down_variant
			var biz: Array = []
			var conns: Array = []
			for id_variant in up.get("businessIds", []):
				biz.append(str(id_variant))
			for cid_variant in up.get("connectionIds", []):
				conns.append(str(cid_variant))
			var down_biz: Array = down.get("businessIds", [])
			var down_conns: Array = down.get("connectionIds", [])
			for i in range(1, down_biz.size()):
				biz.append(str(down_biz[i]))
			for cid_variant in down_conns:
				conns.append(str(cid_variant))
			if biz.size() < 2:
				continue
			out.append({
				"id": "path_%d" % path_i,
				"businessIds": biz,
				"connectionIds": conns,
				"isComplete": _path_is_complete(conns, edges_by_id),
			})
			path_i += 1
			if out.size() >= MAX_PATHS:
				return out
	# Infrastructure-only nodes (Delivery / Repair) have no product-path walks —
	# return a stub so the view can still overlay pink support links.
	if out.is_empty():
		out.append({
			"id": "path_0",
			"businessIds": [selected_node_id],
			"connectionIds": [],
			"isComplete": false,
		})
	return out


static func _path_is_complete(connection_ids: Array, edges_by_id: Dictionary) -> bool:
	if connection_ids.is_empty():
		return false
	for cid_variant in connection_ids:
		var edge: Dictionary = edges_by_id.get(str(cid_variant), {})
		if edge.is_empty() or not bool(edge.get("playerControlled", false)):
			return false
	return true


## Paths from roots → node (inclusive), walking reverse edges then reversing.
static func _paths_ending_at(node_id: String, incoming: Dictionary, edges_by_id: Dictionary) -> Array:
	var results: Array = []
	_walk_back(node_id, [node_id], [], {}, incoming, edges_by_id, results)
	if results.is_empty():
		results.append({"businessIds": [node_id], "connectionIds": []})
	return results


static func _walk_back(
	current: String,
	biz_stack: Array,
	conn_stack: Array,
	visited: Dictionary,
	incoming: Dictionary,
	edges_by_id: Dictionary,
	results: Array,
) -> void:
	if results.size() >= MAX_PATHS or biz_stack.size() > MAX_DEPTH:
		return
	var ins: Array = incoming.get(current, [])
	var expandable: Array = []
	for eid_variant in ins:
		var eid := str(eid_variant)
		var edge: Dictionary = edges_by_id.get(eid, {})
		# Delivery / Repair are shared support links — never branch main paths through them.
		if bool(edge.get("isInfrastructure", false)):
			continue
		var source := str(edge.get("sourceId", ""))
		if source.is_empty() or visited.has(source) or biz_stack.has(source):
			continue
		expandable.append(eid)

	if expandable.is_empty():
		# Root (or cycle-blocked): emit reversed path root→current.
		var biz: Array = []
		var conns: Array = []
		for i in range(biz_stack.size() - 1, -1, -1):
			biz.append(str(biz_stack[i]))
		for i in range(conn_stack.size() - 1, -1, -1):
			conns.append(str(conn_stack[i]))
		results.append({"businessIds": biz, "connectionIds": conns})
		return

	for eid_variant in _prefer_unique_templates(expandable, edges_by_id, true):
		if results.size() >= MAX_PATHS:
			return
		var eid := str(eid_variant)
		var edge: Dictionary = edges_by_id.get(eid, {})
		var source := str(edge.get("sourceId", ""))
		var next_visited := visited.duplicate()
		next_visited[current] = true
		var next_biz: Array = biz_stack.duplicate()
		next_biz.append(source)
		var next_conns: Array = conn_stack.duplicate()
		next_conns.append(eid)
		_walk_back(source, next_biz, next_conns, next_visited, incoming, edges_by_id, results)


static func _paths_starting_at(node_id: String, outgoing: Dictionary, edges_by_id: Dictionary) -> Array:
	var results: Array = []
	_walk_forward(node_id, [node_id], [], {}, outgoing, edges_by_id, results)
	if results.is_empty():
		results.append({"businessIds": [node_id], "connectionIds": []})
	return results


static func _walk_forward(
	current: String,
	biz: Array,
	conns: Array,
	visited: Dictionary,
	outgoing: Dictionary,
	edges_by_id: Dictionary,
	results: Array,
) -> void:
	if results.size() >= MAX_PATHS or biz.size() > MAX_DEPTH:
		return
	var outs: Array = outgoing.get(current, [])
	var expandable: Array = []
	for eid_variant in outs:
		var eid := str(eid_variant)
		var edge: Dictionary = edges_by_id.get(eid, {})
		# Delivery / Repair are shared support links — never branch main paths through them.
		if bool(edge.get("isInfrastructure", false)):
			continue
		var target := str(edge.get("targetId", ""))
		if target.is_empty() or visited.has(target) or biz.has(target):
			continue
		expandable.append(eid)

	if expandable.is_empty():
		results.append({"businessIds": biz.duplicate(), "connectionIds": conns.duplicate()})
		return

	for eid_variant in _prefer_unique_templates(expandable, edges_by_id, false):
		if results.size() >= MAX_PATHS:
			return
		var eid := str(eid_variant)
		var edge: Dictionary = edges_by_id.get(eid, {})
		var target := str(edge.get("targetId", ""))
		var next_visited := visited.duplicate()
		next_visited[current] = true
		var next_biz: Array = biz.duplicate()
		next_biz.append(target)
		var next_conns: Array = conns.duplicate()
		next_conns.append(eid)
		_walk_forward(target, next_biz, next_conns, next_visited, outgoing, edges_by_id, results)


## Keep at most one next hop per catalog connection type.
## Prevents peer duplicates (two restaurants of the same link) from exploding paths.
static func _prefer_unique_templates(edge_ids: Array, edges_by_id: Dictionary, _upstream: bool) -> Array:
	var chosen: Array = []
	var seen_catalog: Dictionary = {}
	for eid_variant in edge_ids:
		var eid := str(eid_variant)
		var edge: Dictionary = edges_by_id.get(eid, {})
		if edge.is_empty():
			continue
		var catalog := str(edge.get("catalogId", ""))
		if catalog.is_empty():
			catalog = str(edge.get("id", eid))
		if seen_catalog.has(catalog):
			continue
		seen_catalog[catalog] = true
		chosen.append(eid)
	return chosen if not chosen.is_empty() else edge_ids
