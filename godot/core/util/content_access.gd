class_name ContentAccess
extends RefCounted

## Runtime lookup for the Content autoload without a parse-time global reference.
## Avoids cyclic dependency: Content -> BusinessTemplate <- Portfolio -> Content.

const REGISTRY_PATH := "/root/Content"


static func registry() -> FarmContentRegistry:
	var tree := Engine.get_main_loop()
	if tree == null:
		return null
	var node: Node = tree.root.get_node_or_null(REGISTRY_PATH)
	return node as FarmContentRegistry


static func get_template(template_id: String) -> BusinessTemplate:
	var reg: FarmContentRegistry = registry()
	if reg == null:
		return null
	return reg.get_template(template_id)


static func is_real_estate_asset(template_id: String) -> bool:
	var reg: FarmContentRegistry = registry()
	if reg == null:
		return false
	return reg.is_real_estate_asset(template_id)
