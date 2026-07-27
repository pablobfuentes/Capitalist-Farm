class_name GameMode
extends RefCounted

const MODE_SIMULATOR := "simulator"
const MODE_CAPITAL_FARM := "arcade"

const STARTER_FARM_TEMPLATES: Array[String] = ["grain_farm", "vegetable_farm", "general_store"]

const FARM_SUFFIXES: Array[String] = [
	"North Field", "Willow Creek", "Red Barn Road", "Meadowgate", "Hearthstead", "Copper Silo",
]


static func config(mode: String) -> Dictionary:
	match mode:
		MODE_CAPITAL_FARM:
			return {
				"label": "Capital Farm",
				"price_mult": 1.0,
				"revenue_mult": 1.18,
				"cost_mult": 1.0,
				"valuation_mult": 1.0,
				"ask_premium_min": 1.10,
				"ask_premium_max": 1.22,
				"tier_scale_on": true,
				"farm_theme": true,
				"rate_adj": -0.02,
				"urgent_freq_mult": 1.4,
				"event_freq_mult": 1.45,
			}
		_:
			return {
				"label": "Simulator",
				"price_mult": 1.0,
				"revenue_mult": 1.0,
				"cost_mult": 1.0,
				"valuation_mult": 1.0,
				"ask_premium_min": 1.08,
				"ask_premium_max": 1.16,
				"tier_scale_on": false,
				"farm_theme": false,
				"rate_adj": 0.0,
			}


static func is_capital_farm(mode: String) -> bool:
	return mode == MODE_CAPITAL_FARM
