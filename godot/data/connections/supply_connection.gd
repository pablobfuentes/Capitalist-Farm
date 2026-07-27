class_name SupplyConnection
extends RefCounted

var id: String = ""
var supplier: String = ""
var customer: String = ""
var flow: String = ""
var effects: Dictionary = {}
var risk_links: Array = []
var vulnerability_label: String = ""


static func from_dict(d: Dictionary) -> SupplyConnection:
	var c := SupplyConnection.new()
	c.id = str(d.get("id", ""))
	c.supplier = str(d.get("supplier", ""))
	c.customer = str(d.get("customer", ""))
	c.flow = str(d.get("flow", ""))
	c.effects = d.get("effects", {})
	var risk_links_raw: Array = d.get("risk_links", [])
	c.risk_links.assign(risk_links_raw)
	c.vulnerability_label = str(d.get("vulnerability_label", ""))
	return c
