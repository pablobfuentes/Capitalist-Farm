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
	var s := RunState.new()
	s.run_seed = int(d.get("seed", 0))
	s.mode = str(d.get("mode", "simulator"))
	s.turn = int(d.get("turn", 1))
	s.max_turns = int(d.get("maxTurns", d.get("max_turns", 30)))
	s.cash = int(d.get("cash", 0))
	s.reputation = int(d.get("reputation", 0))
	s.action_points = int(d.get("actionPoints", d.get("action_points", 2)))
	s.market_state = d.get("marketState", d.get("market_state", {}))
	s.portfolio = Portfolio.from_dict(d.get("portfolio", {}))
	s.loans = d.get("loans", [])
	s.strategic_edges = d.get("strategicEdges", d.get("strategic_edges", []))
	s.opportunities = d.get("opportunities", [])
	s.supply_policies = d.get("supplyPolicies", d.get("supply_policies", {}))
	s.starter_deal_offered = bool(d.get("starterDealOffered", d.get("starter_deal_offered", false)))
	s.farm_upgrade_v2 = bool(d.get("farmUpgradeV2", d.get("farm_upgrade_v2", true)))
	s.game_over = d.get("gameOver", d.get("game_over"))
	s.run_log = d.get("log", [])
	s.last_advance_report = d.get("lastAdvanceReport", d.get("last_advance_report", {}))
	s.period_snapshot = d.get("periodSnapshot", d.get("period_snapshot", {}))
	s.pending_turn_debrief = d.get("pendingTurnDebrief", d.get("pending_turn_debrief", {}))
	s.debrief_expanded = bool(d.get("debriefExpanded", d.get("debrief_expanded", false)))
	s.negotiation = d.get("negotiation", {})
	s.rival_contest_applied_turn = int(d.get("rivalContestAppliedTurn", d.get("rival_contest_applied_turn", 0)))
	s.active_rival_contest_opp_id = str(d.get("activeRivalContestOppId", d.get("active_rival_contest_opp_id", "")))
	s.supply_shortage_ack_turn = int(d.get("supplyShortageAckTurn", d.get("supply_shortage_ack_turn", -1)))
	s.last_chain_hint_turn = int(d.get("lastChainHintTurn", d.get("last_chain_hint_turn", 0)))
	s.synergy_snapshot = d.get("synergySnapshot", d.get("synergy_snapshot", []))
	s.urgent_problems = d.get("urgentProblems", d.get("urgent_problems", []))
	s.milestone_stage = str(d.get("milestoneStage", d.get("milestone_stage", "survival")))
	s.milestones_hit = d.get("milestonesHit", d.get("milestones_hit", []))
	s.edge_choices_pending = d.get("edgeChoicesPending", d.get("edge_choices_pending", []))
	s.wildcard_event = d.get("wildcardEvent", d.get("wildcard_event", {}))
	s.wildcard_triggered = bool(d.get("wildcardTriggered", d.get("wildcard_triggered", false)))
	s.sec_prices = d.get("secPrices", d.get("sec_prices", {}))
	s.run_stats = d.get("runStats", d.get("run_stats", {}))
	s.turn_history = d.get("turnHistory", d.get("turn_history", []))
	s.contracts = d.get("contracts", [])
	s.active_district_id = str(d.get("activeDistrictId", d.get("active_district_id", "meadowgate_commons")))
	s.parcel_assignments = d.get("parcelAssignments", d.get("parcel_assignments", {}))
	s.unlocked_districts = d.get("unlockedDistricts", d.get("unlocked_districts", []))
	s.district_unlock_dev_bypass = bool(d.get("districtUnlockDevBypass", d.get("district_unlock_dev_bypass", false)))
	s.bank_loan_drawn_turn = int(d.get("bankLoanDrawnTurn", d.get("bank_loan_drawn_turn", -1)))
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
	}


func is_capital_farm() -> bool:
	return mode == CAPITAL_FARM_MODE or mode == FARM_2D_MODE


func has_strategic_edge(edge_id: String) -> bool:
	return edge_id in strategic_edges
