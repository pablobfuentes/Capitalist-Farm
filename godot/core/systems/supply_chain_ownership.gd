class_name SupplyChainOwnership
extends RefCounted

## Visual states for a supply-chain edge (renderer must not re-derive ownership).
const STATE_EXTERNAL := "external"
const STATE_OWNED := "owned"
const STATE_COMPLETE := "complete"
## Delivery / Equipment Repair — shared support links (always pink; never path-cycle).
const STATE_INFRASTRUCTURE := "infrastructure"


## Classify a connection edge. Pass path_complete=true when drawing a fully owned path (green).
static func get_connection_visual_state(connection: Dictionary, path_complete: bool = false) -> String:
	if bool(connection.get("isInfrastructure", false)):
		return STATE_INFRASTRUCTURE
	if path_complete:
		return STATE_COMPLETE
	if bool(connection.get("playerControlled", false)):
		return STATE_OWNED
	return STATE_EXTERNAL


static func color_for_state(state: String) -> Color:
	match state:
		STATE_COMPLETE:
			return Color(0.42, 0.88, 0.48, 0.95)
		STATE_OWNED:
			return Color(0.35, 0.72, 1.0, 0.95)
		STATE_INFRASTRUCTURE:
			return Color(0.95, 0.48, 0.72, 0.92)
		_:
			return Color(0.96, 0.96, 0.94, 0.92)


static func is_player_controlled_edge(source_owned: bool, target_owned: bool) -> bool:
	return source_owned and target_owned
