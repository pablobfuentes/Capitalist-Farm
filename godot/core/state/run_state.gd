class_name RunState
extends RefCounted

## Matches GameMode.MODE_CAPITAL_FARM — kept here so core/state has no parse-order dependency on GameMode.
const CAPITAL_FARM_MODE := "arcade"
const FARM_2D_MODE := "farm_2d"

var run_seed: int = 0
var mode: String = "simulator"
var turn: int = 1
var max_turns: int = 30
var cash: int = 25000
var reputation: int = 12
var action_points: int = 2
var market_state: Dictionary = {}
var portfolio: Portfolio = Portfolio.new()
var loans: Array = []
var strategic_edges: Array = []
var opportunities: Array = []
var supply_policies: Dictionary = {}
var starter_deal_offered: bool = false
var farm_upgrade_v2: bool = true
var game_over: Variant = null
var run_log: Array = []
var last_advance_report: Dictionary = {}
var period_snapshot: Dictionary = {}
var pending_turn_debrief: Dictionary = {}
var debrief_expanded: bool = false
var negotiation: Dictionary = {}
var rival_contest_applied_turn: int = 0
var active_rival_contest_opp_id: String = ""
var supply_shortage_ack_turn: int = -1
var last_chain_hint_turn: int = 0
var synergy_snapshot: Array = []
var urgent_problems: Array = []
var milestone_stage: String = "survival"
var milestones_hit: Array = []
var edge_choices_pending: Array = []
var wildcard_event: Dictionary = {}
var wildcard_triggered: bool = false
var sec_prices: Dictionary = {}
var run_stats: Dictionary = {}
var turn_history: Array = []
var contracts: Array = []
var active_district_id: String = "meadowgate_commons"
var parcel_assignments: Dictionary = {}
var unlocked_districts: Array = []
var district_unlock_dev_bypass: bool = false
var bank_loan_drawn_turn: int = -1
var community_schema_version: int = 0
var community: Dictionary = {}


static func create_new(run_mode: String = CAPITAL_FARM_MODE) -> RunState:
	var s := RunState.new()
	s.mode = run_mode
	s.run_seed = randi() % 1_000_000_000
	s.cash = 25000
	s.reputation = 12
	s.action_points = 2
	s.turn = 1
	s.farm_upgrade_v2 = true
	s.milestone_stage = "survival"
	s.milestones_hit = []
	s.wildcard_triggered = false
	s.market_state = {
		"interestRates": "stable",
		"creditAvailability": "normal",
		"consumerDemand": "stable",
		"businessConfidence": "neutral",
		"inflation": "moderate",
		"sectorMomentum": {},
	}
	return s


static func from_dict(d: Dictionary) -> RunState:
	var data := CommunityMigration.migrate_run_dict(d.duplicate(true))
	var s := RunState.new()
	s.run_seed = int(data.get("seed", 0))
	s.mode = str(data.get("mode", "simulator"))
	s.turn = int(data.get("turn", 1))
	s.max_turns = int(data.get("maxTurns", data.get("max_turns", 30)))
	s.cash = int(data.get("cash", 0))
	s.reputation = int(data.get("reputation", 0))
	s.action_points = int(data.get("actionPoints", data.get("action_points", 2)))
	s.market_state = data.get("marketState", data.get("market_state", {}))
	s.portfolio = Portfolio.from_dict(data.get("portfolio", {}))
	s.loans = data.get("loans", [])
	s.strategic_edges = data.get("strategicEdges", data.get("strategic_edges", []))
	s.opportunities = data.get("opportunities", [])
	s.supply_policies = data.get("supplyPolicies", data.get("supply_policies", {}))
	s.starter_deal_offered = bool(data.get("starterDealOffered", data.get("starter_deal_offered", false)))
	s.farm_upgrade_v2 = bool(data.get("farmUpgradeV2", data.get("farm_upgrade_v2", true)))
	s.game_over = data.get("gameOver", data.get("game_over"))
	s.run_log = data.get("log", [])
	s.last_advance_report = data.get("lastAdvanceReport", data.get("last_advance_report", {}))
	s.period_snapshot = data.get("periodSnapshot", data.get("period_snapshot", {}))
	s.pending_turn_debrief = data.get("pendingTurnDebrief", data.get("pending_turn_debrief", {}))
	s.debrief_expanded = bool(data.get("debriefExpanded", data.get("debrief_expanded", false)))
	s.negotiation = data.get("negotiation", {})
	s.rival_contest_applied_turn = int(data.get("rivalContestAppliedTurn", data.get("rival_contest_applied_turn", 0)))
	s.active_rival_contest_opp_id = str(data.get("activeRivalContestOppId", data.get("active_rival_contest_opp_id", "")))
	s.supply_shortage_ack_turn = int(data.get("supplyShortageAckTurn", data.get("supply_shortage_ack_turn", -1)))
	s.last_chain_hint_turn = int(data.get("lastChainHintTurn", data.get("last_chain_hint_turn", 0)))
	s.synergy_snapshot = data.get("synergySnapshot", data.get("synergy_snapshot", []))
	s.urgent_problems = data.get("urgentProblems", data.get("urgent_problems", []))
	s.milestone_stage = str(data.get("milestoneStage", data.get("milestone_stage", "survival")))
	s.milestones_hit = data.get("milestonesHit", data.get("milestones_hit", []))
	s.edge_choices_pending = data.get("edgeChoicesPending", data.get("edge_choices_pending", []))
	s.wildcard_event = data.get("wildcardEvent", data.get("wildcard_event", {}))
	s.wildcard_triggered = bool(data.get("wildcardTriggered", data.get("wildcard_triggered", false)))
	s.sec_prices = data.get("secPrices", data.get("sec_prices", {}))
	s.run_stats = data.get("runStats", data.get("run_stats", {}))
	s.turn_history = data.get("turnHistory", data.get("turn_history", []))
	s.contracts = data.get("contracts", [])
	s.active_district_id = str(data.get("activeDistrictId", data.get("active_district_id", "meadowgate_commons")))
	s.parcel_assignments = data.get("parcelAssignments", data.get("parcel_assignments", {}))
	s.unlocked_districts = data.get("unlockedDistricts", data.get("unlocked_districts", []))
	s.district_unlock_dev_bypass = bool(data.get("districtUnlockDevBypass", data.get("district_unlock_dev_bypass", false)))
	s.bank_loan_drawn_turn = int(data.get("bankLoanDrawnTurn", data.get("bank_loan_drawn_turn", -1)))
	s.community_schema_version = int(data.get("communitySchemaVersion", data.get("community_schema_version", 0)))
	s.community = data.get("community", {})
	CommunityState.ensure_initialized(s)
	return s


func to_dict() -> Dictionary:
	return {
		"seed": run_seed,
		"mode": mode,
		"turn": turn,
		"maxTurns": max_turns,
		"cash": cash,
		"reputation": reputation,
		"actionPoints": action_points,
		"marketState": market_state,
		"portfolio": portfolio.to_dict(),
		"loans": loans,
		"strategicEdges": strategic_edges,
		"opportunities": opportunities,
		"supplyPolicies": supply_policies,
		"starterDealOffered": starter_deal_offered,
		"farmUpgradeV2": farm_upgrade_v2,
		"gameOver": game_over,
		"log": run_log,
		"lastAdvanceReport": last_advance_report,
		"periodSnapshot": period_snapshot,
		"pendingTurnDebrief": pending_turn_debrief,
		"debriefExpanded": debrief_expanded,
		"negotiation": negotiation,
		"rivalContestAppliedTurn": rival_contest_applied_turn,
		"activeRivalContestOppId": active_rival_contest_opp_id,
		"supplyShortageAckTurn": supply_shortage_ack_turn,
		"lastChainHintTurn": last_chain_hint_turn,
		"synergySnapshot": synergy_snapshot,
		"urgentProblems": urgent_problems,
		"milestoneStage": milestone_stage,
		"milestonesHit": milestones_hit,
		"edgeChoicesPending": edge_choices_pending,
		"wildcardEvent": wildcard_event,
		"wildcardTriggered": wildcard_triggered,
		"secPrices": sec_prices,
		"runStats": run_stats,
		"turnHistory": turn_history,
		"contracts": contracts,
		"activeDistrictId": active_district_id,
		"parcelAssignments": parcel_assignments,
		"unlockedDistricts": unlocked_districts,
		"districtUnlockDevBypass": district_unlock_dev_bypass,
		"bankLoanDrawnTurn": bank_loan_drawn_turn,
		"communitySchemaVersion": community_schema_version,
		"community": community,
	}


func is_capital_farm() -> bool:
	return mode == CAPITAL_FARM_MODE or mode == FARM_2D_MODE


func has_strategic_edge(edge_id: String) -> bool:
	return edge_id in strategic_edges
