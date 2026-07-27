extends GutTest

const _World := preload("res://scenes/farm_map/world_layout_data.gd")
const _Layout := preload("res://scenes/farm_map/district_layout_data.gd")


func before_all() -> void:
	Content.load_farm_content()


func test_each_district_has_twenty_four_parcels() -> void:
	var region: Dictionary = _World.load_region()
	for entry_variant in _World.district_entries(region):
		var entry: Dictionary = entry_variant
		var district: Dictionary = _World.load_district_from_entry(entry)
		assert_eq(district.get("parcels", []).size(), 24, _World.district_id(entry))


func test_district_bounds_do_not_overlap() -> void:
	var region: Dictionary = _World.load_region()
	var world_bounds: Array[Rect2i] = []
	for entry_variant in _World.district_entries(region):
		var entry: Dictionary = entry_variant
		var district: Dictionary = _World.load_district_from_entry(entry)
		world_bounds.append(_World.district_world_bounds(entry, district))

	for i in world_bounds.size():
		for j in range(i + 1, world_bounds.size()):
			var a: Rect2i = world_bounds[i]
			var b: Rect2i = world_bounds[j]
			var overlap := Rect2i(
				maxi(a.position.x, b.position.x),
				maxi(a.position.y, b.position.y),
				mini(a.end.x, b.end.x) - maxi(a.position.x, b.position.x),
				mini(a.end.y, b.end.y) - maxi(a.position.y, b.position.y)
			)
			assert_true(
				overlap.size.x <= 0 or overlap.size.y <= 0,
				"District bounds overlap: %s vs %s" % [i, j]
			)
