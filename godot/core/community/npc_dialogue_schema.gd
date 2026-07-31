# JSON response schema constants for NPC community chat (Community spec §10.3).
class_name NpcDialogueSchema
extends RefCounted

const TONES := [
	"neutral",
	"warm",
	"irritated",
	"guarded",
	"amused",
	"hostile",
]

const SOCIAL_ACTIONS := [
	"none",
	"small_talk",
	"compliment",
	"apology",
	"gift_offer",
	"request",
	"promise",
	"disclosure",
	"refusal",
]

const DISCLOSURE_MODES := ["direct", "hint", "rumor"]

const CONFIDENCE_LANGUAGE := ["certain", "likely", "uncertain"]

const SINCERITY_LEVELS := ["low", "medium", "high"]

const RESPECTFULNESS_LEVELS := ["low", "medium", "high"]

const MANIPULATION_SIGNALS := ["none", "mild", "strong"]

const REPETITION_BANDS := ["new", "repeated", "excessive"]

const MAX_DIALOGUE_CHARS := 1200
const MAX_GIFT_CONCEPT_CHARS := 120
const MAX_NEW_FACT_PROPOSAL_CHARS := 240


static func empty_response() -> Dictionary:
	return {
		"dialogue": "",
		"tone": "neutral",
		"social_action": "none",
		"fact_disclosures": [],
		"gift": null,
		"promise_proposal": null,
		"interaction_classification": {
			"sincerity": "medium",
			"respectfulness": "medium",
			"manipulation_signal": "none",
			"repetition": "new",
		},
		"new_fact_proposals": [],
	}
