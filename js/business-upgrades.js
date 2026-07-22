/**
 * Capital Farm — five-axis business upgrades (7.0).
 * Requires FarmSupplyChain (load after farm-supply-chain.js).
 *
 *   BusinessUpgrades.UPGRADE_TRACKS
 *   BusinessUpgrades.ensurePortfolioUpgrades(state)
 *   BusinessUpgrades.recomputeUpgradeStats(node, templateId)
 *   BusinessUpgrades.quarterlyProfitForBusiness(b, state)
 */
(function (global) {
  'use strict';

  const F = () => global.FarmSupplyChain;

  const MAX_TIER = 3;
  const HIRE_PER_TIER = 0.08;
  const MARKETING_PER_TIER = 0.08;
  const AUTOMATION_PER_TIER = 0.06;
  const CARE_CRISIS_PER_TIER = 0.8;
  const MANAGER_BUNDLE = 1.03;
  const MANAGER_AUTOPILOT_BONUS = 1;
  const MANAGER_NEGLECT_GRACE = 2;
  const BASE_NEGLECT_TURNS = 4;
  /** Manager passive drift per quarter (toward tier caps) when not neglected. */
  const MANAGER_DRIFT_PER_QTR = 0.005;

  const UPGRADE_TRACKS = {
    hire: {
      id: 'hire',
      name: 'Hire people',
      maxTier: MAX_TIER,
      effectPerTier: HIRE_PER_TIER,
      benefitPoints: 8,
      note: 'Adds throughput headroom — capacity for the chain, not automatic sales.',
    },
    marketing: {
      id: 'marketing',
      name: 'Marketing',
      maxTier: MAX_TIER,
      effectPerTier: MARKETING_PER_TIER,
      benefitPoints: 8,
      note: 'Pulls more demand — capped by your capacity and supplier fulfillment.',
    },
    automation: {
      id: 'automation',
      name: 'Automation',
      maxTier: MAX_TIER,
      effectPerTier: AUTOMATION_PER_TIER,
      benefitPoints: 6,
      note: 'Lowers operating costs through process and labor efficiency.',
    },
    care: {
      id: 'care',
      name: 'Customer care',
      maxTier: MAX_TIER,
      crisisMultPerTier: CARE_CRISIS_PER_TIER,
      benefitPoints: 8,
      note: 'Fewer client and supplier urgencies; faster relationship recovery.',
    },
    manager: {
      id: 'manager',
      name: 'Manager',
      maxTier: 1,
      benefitPoints: 32,
      note: 'Capstone — less babysitting, modest boost to all levers, +1 effective autopilot.',
    },
  };

  const TIER_COST_MULT = [1, 1.35, 1.6];

  /** Legacy IMPROVEMENTS ids → new tracks (Capital Farm migration). */
  const LEGACY_IMPROVEMENT_MAP = {
    capacity: 'hire',
    sales: 'marketing',
    automation: 'automation',
    care: 'care',
    management: 'manager',
    quality: 'care',
    equipment: 'automation',
  };

  function clamp(v, a, b) {
    return Math.max(a, Math.min(b, v));
  }

  function isActive(state) {
    if (!state || state.mode !== 'arcade') return false;
    if (state.farmUpgradeV2 === false) return false;
    return true;
  }

  function defaultUpgrades() {
    return { hire: 0, marketing: 0, automation: 0, care: 0, manager: false };
  }

  function normalizeUpgrades(node) {
    if (!node.upgrades || typeof node.upgrades !== 'object') {
      node.upgrades = defaultUpgrades();
    }
    const u = node.upgrades;
    u.hire = clamp(Math.floor(u.hire || 0), 0, MAX_TIER);
    u.marketing = clamp(Math.floor(u.marketing || 0), 0, MAX_TIER);
    u.automation = clamp(Math.floor(u.automation || 0), 0, MAX_TIER);
    u.care = clamp(Math.floor(u.care || 0), 0, MAX_TIER);
    u.manager = !!u.manager;
    return u;
  }

  function defaultManagerDrift() {
    return { hire: 0, marketing: 0, automation: 0 };
  }

  function getManagerDrift(node) {
    if (!node.managerDrift || typeof node.managerDrift !== 'object') {
      node.managerDrift = defaultManagerDrift();
    }
    return node.managerDrift;
  }

  function migrateImprovementsApplied(node) {
    if (!node || node._upgradesMigrated) return;
    normalizeUpgrades(node);
    const legacy = node.improvementsApplied;
    if (!legacy || !legacy.length) {
      node._upgradesMigrated = true;
      return;
    }
    legacy.forEach((id) => {
      const track = LEGACY_IMPROVEMENT_MAP[id];
      if (!track) return;
      if (track === 'manager') {
        node.upgrades.manager = true;
        return;
      }
      if (node.upgrades[track] < MAX_TIER) node.upgrades[track] += 1;
    });
    node._upgradesMigrated = true;
  }

  function recomputeUpgradeStats(node, templateId) {
    if (!node) return null;
    const u = normalizeUpgrades(node);
    const drift = u.manager ? getManagerDrift(node) : defaultManagerDrift();
    let capacityMult = 1 + u.hire * HIRE_PER_TIER + (drift.hire || 0);
    let demandMult = 1 + u.marketing * MARKETING_PER_TIER + (drift.marketing || 0);
    let opexMult = Math.pow(1 - AUTOMATION_PER_TIER, u.automation) * (1 - (drift.automation || 0));
    let careCrisisMult = Math.pow(CARE_CRISIS_PER_TIER, u.care);
    if (u.manager) {
      capacityMult *= MANAGER_BUNDLE;
      demandMult *= MANAGER_BUNDLE;
      opexMult *= MANAGER_BUNDLE;
    }
    const baseAp = templateId && F() ? F().autopilotFor(templateId) : 3;
    const effectiveAutopilot = Math.min(5, baseAp + (u.manager ? MANAGER_AUTOPILOT_BONUS : 0));
    node.upgradeStats = {
      capacityMult,
      demandMult,
      opexMult,
      careCrisisMult,
      effectiveAutopilot,
      neglectGrace: u.manager ? MANAGER_NEGLECT_GRACE : 0,
      managerDrift: u.manager ? Object.assign({}, drift) : defaultManagerDrift(),
    };
    return node.upgradeStats;
  }

  function ensureBusinessUpgrades(node) {
    if (!node) return;
    migrateImprovementsApplied(node);
    recomputeUpgradeStats(node, node.templateId);
  }

  function ensurePortfolioUpgrades(state) {
    if (!state || !isActive(state)) return;
    (state.portfolio.businesses || []).forEach(ensureBusinessUpgrades);
    (state.portfolio.realEstate || []).forEach((r) => {
      if (F() && F().isInfrastructureTemplate(r.templateId)) ensureBusinessUpgrades(r);
    });
  }

  function resetUpgradesForLevel(node, templateId) {
    if (!node) return;
    node.upgrades = defaultUpgrades();
    node.managerDrift = defaultManagerDrift();
    node._upgradesMigrated = true;
    recomputeUpgradeStats(node, templateId || node.templateId);
  }

  /**
   * Quarterly manager passive drift — +0.5% per axis toward remaining tier headroom while not neglected.
   * Returns log notes for assets that drifted.
   */
  function applyManagerPassiveDrift(state) {
    if (!isActive(state) || !F()) return [];
    const notes = [];
    const nodes = (state.portfolio.businesses || []).slice();
    (state.portfolio.realEstate || []).forEach((r) => {
      if (F().isInfrastructureTemplate(r.templateId)) nodes.push(r);
    });
    nodes.forEach((node) => {
      normalizeUpgrades(node);
      if (!node.upgrades.manager) return;
      if (F().isNeglected(node, state.turn)) return;
      const drift = getManagerDrift(node);
      let changed = false;
      const axes = [
        { key: 'hire', perTier: HIRE_PER_TIER },
        { key: 'marketing', perTier: MARKETING_PER_TIER },
        { key: 'automation', perTier: AUTOMATION_PER_TIER },
      ];
      axes.forEach(({ key, perTier }) => {
        const tierEffect = (node.upgrades[key] || 0) * perTier;
        const maxEffect = MAX_TIER * perTier;
        const headroom = Math.max(0, maxEffect - tierEffect);
        if (headroom <= 0.0001) return;
        const before = drift[key] || 0;
        drift[key] = Math.min(before + MANAGER_DRIFT_PER_QTR, headroom);
        if (drift[key] > before + 0.00001) changed = true;
      });
      if (changed) {
        recomputeUpgradeStats(node, node.templateId);
        notes.push({ name: node.name, templateId: node.templateId });
      }
    });
    return notes;
  }

  function nodeForTemplate(state, templateId) {
    if (!state || !templateId) return null;
    const biz = (state.portfolio.businesses || []).find((b) => b.templateId === templateId);
    if (biz) return biz;
    return (state.portfolio.realEstate || []).find((r) => r.templateId === templateId) || null;
  }

  function statsForTemplate(state, templateId) {
    const node = nodeForTemplate(state, templateId);
    if (!node || !isActive(state)) return null;
    ensureBusinessUpgrades(node);
    return node.upgradeStats;
  }

  function businessCapacityMult(state, templateId) {
    const stats = statsForTemplate(state, templateId);
    return stats ? stats.capacityMult : 1;
  }

  function businessDemandMult(state, templateId) {
    const stats = statsForTemplate(state, templateId);
    return stats ? stats.demandMult : 1;
  }

  function businessOpexMult(node) {
    if (!node) return 1;
    ensureBusinessUpgrades(node);
    return node.upgradeStats ? node.upgradeStats.opexMult : 1;
  }

  function businessCareCrisisMult(node) {
    if (!node) return 1;
    ensureBusinessUpgrades(node);
    return node.upgradeStats ? node.upgradeStats.careCrisisMult : 1;
  }

  function neglectThreshold(business, templateId) {
    if (business && business.upgradeStats) {
      return BASE_NEGLECT_TURNS + (business.upgradeStats.neglectGrace || 0);
    }
    ensureBusinessUpgrades(business);
    if (business && business.upgradeStats) {
      return BASE_NEGLECT_TURNS + (business.upgradeStats.neglectGrace || 0);
    }
    return BASE_NEGLECT_TURNS;
  }

  function neglectUrgentDampen(business) {
    const ap = business && business.upgradeStats
      ? business.upgradeStats.effectiveAutopilot
      : (business && business.templateId && F() ? F().autopilotFor(business.templateId) : 3);
    return clamp(1.2 - ap * 0.15, 0.45, 1.1);
  }

  function urgentFreqMultForBusiness(business, templateId) {
    const ap = business && business.upgradeStats
      ? business.upgradeStats.effectiveAutopilot
      : (F() ? F().autopilotFor(templateId) : 3);
    return clamp(1.85 - ap * 0.27, 0.48, 1.85);
  }

  /**
   * Consumer-channel revenue multiplier from marketing + inbound fulfillment + own capacity.
   */
  function consumerDemandRevFactor(biz, state, synergies) {
    if (!biz || !isActive(state)) return 1;
    const farm = F();
    if (!farm) return 1;
    const tmpl = farm.templateById(biz.templateId);
    if (!tmpl || tmpl.layer !== 'consumer_channel') return 1;

    ensureBusinessUpgrades(biz);
    const demandMult = biz.upgradeStats.demandMult;
    if (demandMult <= 1) return 1;

    const asCustomer = (synergies || []).filter((y) => y.customerId === biz.id);
    let inboundFulfill = 1;
    if (asCustomer.length) {
      inboundFulfill = asCustomer.reduce((a, y) => a + (y.fulfillRatio != null ? y.fulfillRatio : 1), 0) / asCustomer.length;
    }
    inboundFulfill = clamp(inboundFulfill, 0, 1);

    let ownCapFactor = 1;
    const capUnits = tmpl.consumerCapacityUnits;
    if (capUnits) {
      const effectiveCap = capUnits * biz.upgradeStats.capacityMult;
      const requested = effectiveCap * demandMult;
      ownCapFactor = effectiveCap > 0 ? clamp(effectiveCap / Math.max(requested, 1), 0.35, 1) : 1;
    }

    const capFactor = inboundFulfill * ownCapFactor;
    return 1 + (demandMult - 1) * capFactor;
  }

  function quarterlyProfitForBusiness(b, state) {
    const farm = F();
    if (!farm || !b) return (b.revenuePerTurn || 0) - (b.operatingCosts || 0);
    ensurePortfolioUpgrades(state);
    const syns = farm.computeSynergies(state);
    const applied = farm.applyToBusiness(b, syns, state, {});
    const exp = farm.applyExportToBusiness(b, state);
    return applied.rev + (exp.exportRevenue || 0) - applied.cost;
  }

  function tierCostFraction(trackId, tierIndex) {
    const track = UPGRADE_TRACKS[trackId];
    if (!track) return 0;
    if (trackId === 'manager') return 0.15;
    const mult = TIER_COST_MULT[tierIndex] != null ? TIER_COST_MULT[tierIndex] : 1.6;
    return (track.benefitPoints / 100) * mult;
  }

  function tierPointSum(node) {
    const u = normalizeUpgrades(node);
    return u.hire + u.marketing + u.automation + u.care;
  }

  function upgradeTierSum(node) {
    const u = normalizeUpgrades(node);
    return tierPointSum(node) + (u.manager ? 1 : 0);
  }

  function isFullyMatured(node) {
    const u = normalizeUpgrades(node);
    return u.hire >= MAX_TIER && u.marketing >= MAX_TIER && u.automation >= MAX_TIER
      && u.care >= MAX_TIER && u.manager;
  }

  function isEligibleForMajorUpgrade(node) {
    const u = normalizeUpgrades(node);
    const sum = tierPointSum(node);
    return sum >= 8 || (u.manager && sum >= 6);
  }

  function canApplyTrack(node, trackId, templateId) {
    if (!node || !UPGRADE_TRACKS[trackId]) return { ok: false, reason: 'Unknown upgrade.' };
    normalizeUpgrades(node);
    const tmpl = templateId && F() ? F().templateById(templateId) : null;
    if (trackId === 'manager') {
      if (node.upgrades.manager) return { ok: false, reason: 'Manager already in place this level.' };
      return { ok: true };
    }
    if (trackId === 'marketing' && tmpl && tmpl.marketingEligible === false) {
      return { ok: false, reason: 'Infrastructure asset — use hire or automation.' };
    }
    if (node.upgrades[trackId] >= MAX_TIER) return { ok: false, reason: 'Max tier reached.' };
    return { ok: true };
  }

  function nextTierIndex(node, trackId) {
    normalizeUpgrades(node);
    if (trackId === 'manager') return node.upgrades.manager ? 1 : 0;
    return node.upgrades[trackId];
  }

  function businessImproveCost(node, trackId) {
    if (!node) return 0;
    normalizeUpgrades(node);
    const check = canApplyTrack(node, trackId, node.templateId);
    if (!check.ok) return 0;
    const val = node.valuation || 0;
    if (trackId === 'manager') return Math.round(val * tierCostFraction('manager', 0));
    const tierIndex = node.upgrades[trackId];
    return Math.round(val * tierCostFraction(trackId, tierIndex));
  }

  function estimateValuation(node, state) {
    if (!node) return 0;
    const profit = quarterlyProfitForBusiness(node, state);
    const ownerDep = node.ownerDependence != null ? node.ownerDependence : 0.5;
    const custConc = node.custConc != null ? node.custConc : 0.1;
    const equip = node.equipmentCondition != null ? node.equipmentCondition : 0.8;
    const multiple = 4 - ownerDep * 1.2 - custConc * 1.5 + (1 - equip) * -0.5;
    // Keep in sync with GAME_MODES.*.valuationMult (arcade no longer stacks a hidden 1.18×).
    let val = Math.max(1000, profit * 4 * clamp(multiple / 2.5, 0.6, 1.6));
    return Math.round(val);
  }

  function cloneStateForPreview(state) {
    return {
      mode: state.mode,
      turn: state.turn,
      farmUpgradeV2: state.farmUpgradeV2,
      strategicEdges: (state.strategicEdges || []).slice(),
      supplyPolicies: Object.assign({}, state.supplyPolicies || {}),
      portfolio: JSON.parse(JSON.stringify(state.portfolio)),
    };
  }

  function findPortfolioNode(state, nodeId) {
    const biz = (state.portfolio.businesses || []).find((b) => b.id === nodeId);
    if (biz) return biz;
    return (state.portfolio.realEstate || []).find((r) => r.id === nodeId) || null;
  }

  function portfolioQuarterlyProfit(state) {
    const farm = F();
    if (!farm) return 0;
    ensurePortfolioUpgrades(state);
    const syns = farm.computeSynergies(state);
    let total = 0;
    (state.portfolio.businesses || []).forEach((b) => {
      total += quarterlyProfitForBusiness(b, state);
    });
    (state.portfolio.realEstate || []).forEach((r) => {
      if (farm.isInfrastructureTemplate(r.templateId)) {
        const infra = farm.applyInfrastructureToRealEstate(r, state, syns);
        if (infra) total += infra.rent - infra.opex;
      }
    });
    return total;
  }

  function linksSnapshot(state, nodeId) {
    const farm = F();
    if (!farm) return [];
    const node = findPortfolioNode(state, nodeId);
    if (!node) return [];
    const syns = farm.computeSynergies(state);
    return syns
      .filter((s) => s.customerId === nodeId || s.supplierId === nodeId)
      .map((s) => ({
        connectionId: s.connectionId,
        supplier: s.supplierTemplateId,
        customer: s.customerTemplateId,
        label: s.label,
        fulfill: s.fulfillRatio != null ? s.fulfillRatio : 1,
        binding: s.supplierId === nodeId ? 'supplier' : 'customer',
      }));
  }

  function diffLinkSnapshots(before, after) {
    const afterMap = {};
    after.forEach((l) => { afterMap[l.connectionId + ':' + l.customer] = l; });
    return before.map((b) => {
      const key = b.connectionId + ':' + b.customer;
      const a = afterMap[key];
      return {
        connectionId: b.connectionId,
        supplier: b.supplier,
        customer: b.customer,
        label: b.label,
        fulfillBefore: b.fulfill,
        fulfillAfter: a ? a.fulfill : b.fulfill,
        binding: b.binding,
      };
    }).filter((l) => Math.abs(l.fulfillAfter - l.fulfillBefore) > 0.005
      || l.fulfillBefore < 0.99 || l.fulfillAfter < 0.99);
  }

  function marketingWastedPct(node, state, trackId) {
    if (trackId !== 'marketing') return 0;
    const farm = F();
    if (!farm) return 0;
    const tmpl = farm.templateById(node.templateId);
    if (!tmpl || tmpl.layer !== 'consumer_channel') return 0;
    const syns = farm.computeSynergies(state);
    const before = consumerDemandRevFactor(node, state, syns);
    const clone = cloneStateForPreview(state);
    const cloneNode = findPortfolioNode(clone, node.id);
    applyUpgradeToNode(cloneNode, 'marketing', cloneNode.templateId, state.turn, { skipCareSideEffects: true });
    const synsAfter = farm.computeSynergies(clone);
    const after = consumerDemandRevFactor(cloneNode, clone, synsAfter);
    const uncapped = 1 + (cloneNode.upgradeStats.demandMult - 1);
    const realized = after - 1;
    const potential = uncapped - 1;
    if (potential <= 0.001) return 0;
    return clamp(1 - realized / potential, 0, 1);
  }

  /** Apply one tier (mutates node). Returns false if blocked. */
  function applyUpgradeToNode(node, trackId, templateId, turn, opts) {
    opts = opts || {};
    const check = canApplyTrack(node, trackId, templateId);
    if (!check.ok) return false;
    normalizeUpgrades(node);
    if (trackId === 'manager') {
      node.upgrades.manager = true;
    } else {
      node.upgrades[trackId] += 1;
    }
    recomputeUpgradeStats(node, templateId);
    if (!opts.skipCareSideEffects && trackId === 'care') {
      const farm = F();
      const careBoost = farm ? farm.improveCareRecoveryMult(templateId) : 1;
      node.crisisMult = clamp((node.crisisMult ?? 1) * CARE_CRISIS_PER_TIER * careBoost, 0.15, 1);
      node.clientHealth = clamp((node.clientHealth ?? 72) + Math.round(15 * careBoost), 0, 100);
      node.supplierHealth = clamp((node.supplierHealth ?? 72) + Math.round(15 * careBoost), 0, 100);
    }
    if (!opts.skipCareSideEffects && (trackId === 'care' || trackId === 'manager') && F() && turn != null) {
      F().markBusinessCare(node, turn);
    }
    return true;
  }

  function applyUpgrade(node, trackId, state) {
    return applyUpgradeToNode(node, trackId, node.templateId, state ? state.turn : null);
  }

  function detectPortfolioBottlenecks(state) {
    const farm = F();
    if (!farm || !isActive(state)) return [];
    ensurePortfolioUpgrades(state);
    const out = [];
    const util = farm.computeSupplierUtilization(state);
    Object.keys(util).forEach((tid) => {
      const u = util[tid];
      if (u.overCapacity || u.utilizationPct > 100) {
        out.push({
          templateId: tid,
          name: u.name,
          utilPct: u.utilizationPct,
          message: `${u.name} at ${u.utilizationPct}% — hire relieves downstream shortage`,
          severity: u.utilizationPct - 100 + 50,
          track: 'hire',
          nodeId: nodeForTemplate(state, tid)?.id,
        });
      } else if (u.utilizationPct > 85) {
        out.push({
          templateId: tid,
          name: u.name,
          utilPct: u.utilizationPct,
          message: `${u.name} nearing capacity (${u.utilizationPct}%)`,
          severity: u.utilizationPct - 85,
          track: 'hire',
          nodeId: nodeForTemplate(state, tid)?.id,
        });
      }
    });
    const syns = farm.computeSynergies(state);
    (state.portfolio.businesses || []).forEach((b) => {
      const tmpl = farm.templateById(b.templateId);
      if (!tmpl || tmpl.layer !== 'consumer_channel') return;
      const inbound = syns.filter((s) => s.customerId === b.id);
      if (!inbound.length) return;
      const avg = inbound.reduce((a, s) => a + (s.fulfillRatio ?? 1), 0) / inbound.length;
      if (avg < 0.75) {
        const weakSupplier = inbound.find((s) => (s.fulfillRatio ?? 1) < 0.75);
        out.push({
          templateId: weakSupplier ? weakSupplier.supplierTemplateId : b.templateId,
          name: weakSupplier
            ? (farm.templateById(weakSupplier.supplierTemplateId) || {}).name
            : b.name,
          utilPct: Math.round(avg * 100),
          message: `${b.name} suppliers only ${Math.round(avg * 100)}% fulfilled — fix upstream capacity first`,
          severity: (0.75 - avg) * 100 + 20,
          track: 'hire',
          nodeId: weakSupplier ? nodeForTemplate(state, weakSupplier.supplierTemplateId)?.id : b.id,
        });
      }
    });
    return out.sort((a, b) => b.severity - a.severity);
  }

  function recommendUpgrade(state, focusBizId, opts) {
    opts = opts || {};
    if (!isActive(state)) return [];
    const recs = [];
    const bottlenecks = detectPortfolioBottlenecks(state);
    bottlenecks.slice(0, 2).forEach((b) => {
      if (b.nodeId) {
        recs.push({
          businessId: b.nodeId,
          templateId: b.templateId,
          track: b.track,
          reason: b.message,
        });
      }
    });
    if (focusBizId && !opts.skipPreviewScan && recs.length < 3) {
      const tracks = ['hire', 'marketing', 'automation', 'care', 'manager'];
      let best = null;
      tracks.forEach((trackId) => {
        const preview = computeUpgradePreview(state, focusBizId, trackId);
        if (!preview || !preview.canApply || preview.profitDelta <= 0) return;
        if (!best || preview.profitDelta > best.profitDelta) {
          best = {
            businessId: focusBizId,
            track: trackId,
            profitDelta: preview.profitDelta,
            reason: `+${Math.round(preview.profitDelta).toLocaleString('en-US')}/qtr profit`,
          };
        }
      });
      if (best) recs.push(best);
    }
    return recs.slice(0, 3);
  }

  function computeUpgradePreview(state, bizId, trackId) {
    if (!isActive(state)) return null;
    const farm = F();
    if (!farm) return null;
    ensurePortfolioUpgrades(state);
    const node = findPortfolioNode(state, bizId);
    if (!node) return null;
    const check = canApplyTrack(node, trackId, node.templateId);
    if (!check.ok) {
      return { canApply: false, trackId, reason: check.reason };
    }

    const profitBefore = quarterlyProfitForBusiness(node, state);
    const valBefore = estimateValuation(node, state);
    const beforeStats = Object.assign({}, node.upgradeStats);
    const beforeLinks = linksSnapshot(state, bizId);
    const cost = businessImproveCost(node, trackId);
    const tmplId = node.templateId;
    const capacityBefore = capacityUnitsForNode(state, node);
    const chainDemandBefore = farm.isAllocatableTemplate(tmplId)
      ? farm.computeOwnedDownstreamDemand(state, tmplId) : 0;
    const exportBefore = farm.applyExportToBusiness(node, state).exportRevenue || 0;

    const clone = cloneStateForPreview(state);
    const cloneNode = findPortfolioNode(clone, bizId);
    applyUpgradeToNode(cloneNode, trackId, cloneNode.templateId, state.turn, { skipCareSideEffects: true });
    ensurePortfolioUpgrades(clone);

    const profitAfter = quarterlyProfitForBusiness(cloneNode, clone);
    const valAfter = estimateValuation(cloneNode, clone);
    const capacityAfter = capacityUnitsForNode(clone, cloneNode);
    const exportAfter = farm.applyExportToBusiness(cloneNode, clone).exportRevenue || 0;
    const afterLinks = linksSnapshot(clone, bizId);
    const chain = diffLinkSnapshots(beforeLinks, afterLinks);
    const bottlenecks = detectPortfolioBottlenecks(state);
    const bottleneck = bottlenecks[0] || null;
    const wastedPct = marketingWastedPct(node, state, trackId);

    const warnings = [];
    if (trackId === 'marketing' && wastedPct > 0.12) {
      warnings.push(`~${Math.round(wastedPct * 100)}% of marketing upside unrealized until upstream capacity improves.`);
    }
    chain.forEach((l) => {
      if (l.binding === 'customer' && l.fulfillBefore < 0.7) {
        warnings.push(`Inbound ${l.label} only ${Math.round(l.fulfillBefore * 100)}% fulfilled.`);
      }
    });
    if (trackId === 'hire' && profitAfter <= profitBefore && chainDemandBefore === 0) {
      warnings.push('No owned downstream yet — hire adds throughput headroom for chain links and export; existing client revenue is separate.');
    }
    if (trackId === 'marketing' && profitAfter <= profitBefore && chainDemandBefore === 0
      && farm.templateById(tmplId)?.layer === 'consumer_channel') {
      warnings.push('Marketing lifts walk-in revenue here — upstream supply must keep pace.');
    }

    const tierNext = trackId === 'manager' ? 1 : nextTierIndex(node, trackId) + 1;
    const paybackQtrs = profitAfter > profitBefore
      ? Math.ceil(cost / Math.max(1, profitAfter - profitBefore))
      : null;

    return {
      canApply: true,
      trackId,
      tierNext,
      cost,
      profitBefore,
      profitAfter,
      profitDelta: profitAfter - profitBefore,
      valBefore,
      valAfter,
      valDelta: valAfter - valBefore,
      capacityBefore,
      capacityAfter,
      capacityDelta: (capacityBefore != null && capacityAfter != null) ? capacityAfter - capacityBefore : 0,
      exportRevBefore: exportBefore,
      exportRevAfter: exportAfter,
      exportRevDelta: exportAfter - exportBefore,
      chainDemandBefore,
      local: { before: beforeStats, after: Object.assign({}, cloneNode.upgradeStats) },
      chain,
      bottleneck,
      wastedPct,
      warnings,
      recommendations: bottlenecks.slice(0, 2).map((b) => ({
        templateId: b.templateId,
        track: b.track,
        reason: b.message,
        businessId: b.nodeId,
      })),
      paybackQtrs,
    };
  }

  function capacityUnitsForNode(state, node) {
    const farm = F();
    if (!farm || !node) return null;
    const tid = node.templateId;
    if (farm.isAllocatableTemplate(tid)) return farm.effectiveCapacity(state, tid);
    const t = farm.templateById(tid);
    if (t && t.consumerCapacityUnits) {
      return Math.round(t.consumerCapacityUnits * businessCapacityMult(state, tid));
    }
    return null;
  }

  /** Primary operational effect line for upgrade UI (always shown when applicable). */
  function formatTrackEffectLine(preview, trackId) {
    if (!preview || !preview.canApply) return '';
    const b = preview.local?.before || {};
    const a = preview.local?.after || {};
    const parts = [];
    if (trackId === 'hire' && preview.capacityBefore != null && preview.capacityAfter != null
      && preview.capacityAfter !== preview.capacityBefore) {
      parts.push(`Cap ${preview.capacityBefore} → ${preview.capacityAfter} (+${preview.capacityAfter - preview.capacityBefore})`);
    }
    if (trackId === 'marketing') {
      parts.push(`Demand ×${(b.demandMult || 1).toFixed(2)} → ×${(a.demandMult || 1).toFixed(2)}`);
    }
    if (trackId === 'automation') {
      parts.push(`Opex ×${(b.opexMult || 1).toFixed(2)} → ×${(a.opexMult || 1).toFixed(2)}`);
    }
    if (trackId === 'care') {
      parts.push(`Urgency weight ×${(b.careCrisisMult || 1).toFixed(2)} → ×${(a.careCrisisMult || 1).toFixed(2)}`);
    }
    if (trackId === 'manager') {
      parts.push(`Autopilot +${MANAGER_AUTOPILOT_BONUS} · all levers ×${MANAGER_BUNDLE.toFixed(2)}`);
    }
    if (preview.exportRevDelta > 0) {
      parts.push(`Export +$${Math.round(preview.exportRevDelta).toLocaleString('en-US')}/qtr`);
    }
    return parts.join(' · ');
  }

  /** Row meta: operational effect first, then P&L when non-zero. */
  function formatUpgradeRowMeta(preview, trackId, fallbackReason) {
    if (!preview || !preview.canApply) return fallbackReason || '';
    const effect = formatTrackEffectLine(preview, trackId);
    const profitParts = [];
    if (preview.profitDelta !== 0) {
      profitParts.push(`Δ profit ${preview.profitDelta >= 0 ? '+' : ''}${Math.round(preview.profitDelta).toLocaleString('en-US')}/qtr`);
    }
    if (preview.valDelta !== 0) {
      profitParts.push(`Δ val ${preview.valDelta >= 0 ? '+' : ''}${Math.round(preview.valDelta).toLocaleString('en-US')}`);
    }
    if (!profitParts.length && (trackId === 'hire' || trackId === 'marketing')) {
      profitParts.push('P&L unlocks when chain/customers use the headroom');
    }
    return [effect, profitParts.join(' · ')].filter(Boolean).join(' · ');
  }

  function trackTierLabel(trackId, tier) {
    const track = UPGRADE_TRACKS[trackId];
    if (!track) return '';
    if (trackId === 'manager') return tier ? 'Active' : 'Available';
    if (trackId === 'automation') return `−${Math.round(tier * track.effectPerTier * 100)}% opex`;
    if (trackId === 'care') return `−${Math.round((1 - Math.pow(CARE_CRISIS_PER_TIER, tier)) * 100)}% urgencies`;
    return `+${Math.round(tier * track.effectPerTier * 100)}%`;
  }

  function renderTierPips(tier, max) {
    let s = '';
    for (let i = 0; i < max; i++) s += i < tier ? '●' : '○';
    return s;
  }

  /** Compact lever data for portfolio / supply-chain UI. */
  function leverStripData(node) {
    if (!node) return [];
    ensureBusinessUpgrades(node);
    const u = node.upgrades;
    return [
      { id: 'hire', label: 'Cap', tier: u.hire, max: MAX_TIER },
      { id: 'marketing', label: 'Dem', tier: u.marketing, max: MAX_TIER },
      { id: 'automation', label: 'Ops', tier: u.automation, max: MAX_TIER },
      { id: 'care', label: 'Care', tier: u.care, max: MAX_TIER },
      { id: 'manager', label: 'Mgr', tier: u.manager ? 1 : 0, max: 1 },
    ];
  }

  function formatLeverStripText(node) {
    return leverStripData(node).map((t) => `${t.label} ${renderTierPips(t.tier, t.max)}`).join(' · ');
  }

  global.BusinessUpgrades = {
    UPGRADE_TRACKS,
    MAX_TIER,
    TIER_COST_MULT,
    LEGACY_IMPROVEMENT_MAP,
    BASE_NEGLECT_TURNS,
    isActive,
    MANAGER_DRIFT_PER_QTR,
    defaultManagerDrift,
    applyManagerPassiveDrift,
    defaultUpgrades,
    normalizeUpgrades,
    migrateImprovementsApplied,
    recomputeUpgradeStats,
    ensureBusinessUpgrades,
    ensurePortfolioUpgrades,
    resetUpgradesForLevel,
    nodeForTemplate,
    businessCapacityMult,
    businessDemandMult,
    businessOpexMult,
    businessCareCrisisMult,
    neglectThreshold,
    neglectUrgentDampen,
    urgentFreqMultForBusiness,
    consumerDemandRevFactor,
    quarterlyProfitForBusiness,
    tierCostFraction,
    tierPointSum,
    upgradeTierSum,
    isFullyMatured,
    isEligibleForMajorUpgrade,
    canApplyTrack,
    nextTierIndex,
    businessImproveCost,
    estimateValuation,
    applyUpgrade,
    applyUpgradeToNode,
    computeUpgradePreview,
    capacityUnitsForNode,
    formatTrackEffectLine,
    formatUpgradeRowMeta,
    detectPortfolioBottlenecks,
    recommendUpgrade,
    trackTierLabel,
    renderTierPips,
    leverStripData,
    formatLeverStripText,
  };
})(typeof window !== 'undefined' ? window : globalThis);
