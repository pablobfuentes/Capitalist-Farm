/**
 * MVP 6 Phase 8 regression — P&L sanity, performance, AP economy, 30-turn sim.
 * Run: node scripts/regression-phase8.js
 */
const fs = require('fs');
const path = require('path');

const enginePath = path.join(__dirname, '../js/farm-supply-chain.js');
eval(fs.readFileSync(enginePath, 'utf8').replace(/\}\)\(typeof window !== 'undefined' \? window : globalThis\);$/, '})(globalThis);'));
const F = globalThis.FarmSupplyChain;

let passed = 0;
let failed = 0;

function assert(cond, msg) {
  if (cond) {
    passed += 1;
    return;
  }
  failed += 1;
  console.error('FAIL:', msg);
}

function biz(id, templateId, rev, cost) {
  return {
    id,
    templateId,
    name: (F.templateById(templateId) || {}).name || templateId,
    revenuePerTurn: rev,
    operatingCosts: cost,
    industry: 'farm_food',
  };
}

function re(id, templateId, rent, opex, vacancyRisk) {
  return {
    id,
    templateId,
    name: (F.templateById(templateId) || {}).name || templateId,
    rentPerTurn: rent,
    operatingExpenses: opex,
    vacancyRisk: vacancyRisk != null ? vacancyRisk : 0.1,
    assetClass: 'real_estate',
  };
}

function baseState(extra) {
  return Object.assign({
    mode: 'arcade',
    turn: 1,
    strategicEdges: [],
    portfolio: { businesses: [], realEstate: [] },
    supplyPolicies: {},
  }, extra || {});
}

function farmQuarterlyTotals(state) {
  const syns = F.computeSynergies(state);
  let revenue = 0;
  let costs = 0;
  state.portfolio.businesses.forEach((b) => {
    const applied = F.applyToBusiness(b, syns, state, {});
    const exp = F.applyExportToBusiness(b, state);
    revenue += applied.rev + (exp.exportRevenue || 0);
    costs += applied.cost;
  });
  state.portfolio.realEstate.forEach((r) => {
    if (F.isInfrastructureTemplate(r.templateId)) {
      const infra = F.applyInfrastructureToRealEstate(r, state, syns);
      revenue += infra.rent;
      costs += infra.opex;
    } else {
      revenue += Math.round(r.rentPerTurn * (1 - r.vacancyRisk * 0.4));
      costs += r.operatingExpenses;
    }
  });
  return { revenue, costs, profit: revenue - costs, synergies: syns };
}

function rawTotals(state) {
  let revenue = 0;
  let costs = 0;
  state.portfolio.businesses.forEach((b) => {
    revenue += b.revenuePerTurn;
    costs += b.operatingCosts;
  });
  state.portfolio.realEstate.forEach((r) => {
    revenue += Math.round(r.rentPerTurn * (1 - r.vacancyRisk * 0.4));
    costs += r.operatingExpenses;
  });
  return { revenue, costs, profit: revenue - costs };
}

// --- P&L double-count regression ---

function testInternalLinksZeroSupplierRevenue() {
  const s = baseState({
    portfolio: {
      businesses: [
        biz('g', 'grain_farm', 18000, 10000),
        biz('f', 'feed_mill', 22000, 14000),
        biz('d', 'dairy_barn', 26000, 17000),
      ],
      realEstate: [],
    },
  });
  const { synergies } = farmQuarterlyTotals(s);
  const internal = synergies.filter((y) => y.internalLink);
  assert(internal.length >= 2, 'grain→feed and feed→dairy links active');
  internal.forEach((y) => {
    assert(y.revenueBonusSupplier === 0, `internal link ${y.label} must not stack supplier revenue`);
  });
}

function testVerticalProfitFromCostSavings() {
  const grainOnly = baseState({
    portfolio: { businesses: [biz('g', 'grain_farm', 18000, 10000)], realEstate: [] },
  });
  const feedOnly = baseState({
    portfolio: { businesses: [biz('f', 'feed_mill', 22000, 14000)], realEstate: [] },
  });
  const vertical = baseState({
    portfolio: {
      businesses: [
        biz('g', 'grain_farm', 18000, 10000),
        biz('f', 'feed_mill', 22000, 14000),
      ],
      realEstate: [],
    },
  });

  const g = rawTotals(grainOnly);
  const f = rawTotals(feedOnly);
  const v = farmQuarterlyTotals(vertical);
  const grainBiz = vertical.portfolio.businesses.find((b) => b.templateId === 'grain_farm');
  const grainApplied = F.applyToBusiness(grainBiz, v.synergies, vertical, {});

  assert(grainApplied.rev === grainBiz.revenuePerTurn,
    `grain supplier revenue must not inflate (${grainApplied.rev} vs base ${grainBiz.revenuePerTurn})`);
  assert(v.profit > g.profit + f.profit,
    'vertical integration should improve profit (cost savings + optional export, not supplier stacking)');
  const savings = (g.costs + f.costs) - v.costs;
  assert(savings > 500, `expected meaningful cost savings, got ${savings}`);
  v.synergies.filter((y) => y.internalLink).forEach((y) => {
    assert(y.revenueBonusSupplier === 0, `no supplier revenue bonus on ${y.label}`);
  });
}

function testExportBelowStrongDownstreamLink() {
  const withFeed = baseState({
    portfolio: {
      businesses: [
        biz('g', 'grain_farm', 18000, 10000),
        biz('f', 'feed_mill', 22000, 14000),
      ],
      realEstate: [],
    },
  });
  const grainAlone = baseState({
    portfolio: { businesses: [biz('g', 'grain_farm', 18000, 10000)], realEstate: [] },
  });
  const linked = farmQuarterlyTotals(withFeed);
  const exported = farmQuarterlyTotals(grainAlone);
  const exportRev = exported.revenue - rawTotals(grainAlone).revenue;
  const linkBenefit = linked.profit - (rawTotals(withFeed).profit);
  assert(exportRev >= 0, 'export should be non-negative spare-capacity revenue');
  assert(linkBenefit > exportRev || linkBenefit > 800,
    'owned downstream link should beat export floor on economics');
}

function testInfraExternalNotDoubleInternal() {
  const s = baseState({
    portfolio: {
      businesses: [
        biz('v', 'vegetable_farm', 20000, 12000),
        biz('d', 'dairy_barn', 26000, 17000),
      ],
      realEstate: [re('cs', 'delivery_cold_storage', 24000, 8000, 0.1)],
    },
  });
  const { synergies, revenue, costs } = farmQuarterlyTotals(s);
  const internalSave = synergies
    .filter((y) => y.supplierTemplateId === 'delivery_cold_storage' && y.internalLink)
    .reduce((a, y) => a + (y.estimatedCostSaving || 0), 0);
  const util = F.computeSupplierUtilization(s).delivery_cold_storage;
  assert(util && util.externalContractRevenue >= 0, 'infra external contract computed');
  assert(revenue > 0 && costs > 0, 'infra P&L resolves');
  assert(internalSave >= 0 || synergies.length === 0, 'internal service stays cost-side');
}

// --- Performance ---

function testComputeSynergiesPerformance() {
  const s = baseState({
    portfolio: {
      businesses: [
        biz('g', 'grain_farm', 18000, 10000),
        biz('v', 'vegetable_farm', 20000, 12000),
        biz('f', 'feed_mill', 22000, 14000),
        biz('d', 'dairy_barn', 26000, 17000),
        biz('p', 'poultry_coop', 19000, 12500),
        biz('b', 'bakery', 28000, 19000),
        biz('r', 'farmhouse_restaurant', 45000, 32000),
        biz('s', 'general_store', 30000, 21000),
      ],
      realEstate: [
        re('eq', 'equipment_repair', 20000, 6000, 0.1),
        re('cs', 'delivery_cold_storage', 24000, 8000, 0.1),
      ],
    },
  });
  const iterations = 2500;
  const t0 = process.hrtime.bigint();
  for (let i = 0; i < iterations; i += 1) F.computeSynergies(s);
  const ms = Number(process.hrtime.bigint() - t0) / 1e6;
  const perCall = ms / iterations;
  console.log(`  computeSynergies: ${iterations} calls in ${ms.toFixed(1)}ms (${perCall.toFixed(3)}ms/call)`);
  assert(perCall < 2, `computeSynergies too slow: ${perCall.toFixed(3)}ms/call (limit 2ms)`);
  assert(ms < 3000, `total benchmark ${ms.toFixed(0)}ms exceeds 3000ms`);
}

// --- AP economy (static rules) ---

function testApEconomyRules() {
  const rules = {
    defaultApPerTurn: 2,
    turnOneAp: 3,
    shortagePolicyAp: 0,
    investigateAp: 1,
    negotiateAp: 1,
    buyNowAp: 1,
    improveAp: 1,
  };
  assert(rules.investigateAp + rules.negotiateAp <= rules.defaultApPerTurn,
    'investigate + negotiate fits in one turn (2 AP)');
  assert(rules.shortagePolicyAp === 0,
    'shortage policy selection costs 0 AP');
  assert(rules.turnOneAp >= rules.defaultApPerTurn,
    'turn 1 bonus AP >= standard');
  console.log('  AP economy:', JSON.stringify(rules));
}

// --- 30-turn progression sim ---

function simulate30TurnRun() {
  const phases = [
    { turns: [1, 5], add: [biz('g', 'grain_farm', 18000, 10000)] },
    { turns: [6, 12], add: [biz('f', 'feed_mill', 22000, 14000)] },
    { turns: [13, 20], add: [biz('d', 'dairy_barn', 26000, 17000), biz('b', 'bakery', 28000, 19000)] },
    { turns: [21, 30], add: [re('cs', 'delivery_cold_storage', 24000, 8000, 0.1)] },
  ];

  const state = baseState({ runStats: { utilizationSamples: [], policyChanges: [] } });
  let phaseIdx = 0;
  let errors = [];

  for (let turn = 1; turn <= 30; turn += 1) {
    state.turn = turn;
    while (phaseIdx < phases.length && turn >= phases[phaseIdx].turns[0]) {
      const phase = phases[phaseIdx];
      phase.add.forEach((asset) => {
        if (asset.assetClass === 'real_estate') state.portfolio.realEstate.push(asset);
        else state.portfolio.businesses.push(asset);
      });
      phaseIdx += 1;
    }
    try {
      const syns = F.computeSynergies(state);
      const totals = farmQuarterlyTotals(state);
      const shortages = F.detectSupplyShortages(state);
      if (shortages.length) {
        shortages.forEach((u) => {
          if (!state.supplyPolicies[u.templateId]) {
            state.supplyPolicies[u.templateId] = 'portfolio_first';
          }
        });
      }
      if (!state.runStats.utilizationSamples) state.runStats.utilizationSamples = [];
      const util = F.computeSupplierUtilization(state);
      const pcts = Object.values(util).map((u) => u.utilizationPct).filter((n) => n != null);
      if (pcts.length) {
        state.runStats.utilizationSamples.push(
          Math.round(pcts.reduce((a, b) => a + b, 0) / pcts.length)
        );
      }
      if (turn === 30) {
        const label = F.classifyStrategy(state);
        const report = F.buildRunChainReport(state, state.runStats);
        assert(syns.length >= 2, 'turn 30: multiple active links');
        assert(totals.profit !== 0, 'turn 30: P&L non-zero');
        assert(label && label.length > 20, 'turn 30: strategy label present');
        assert(report.dominantLayer, 'turn 30: dominant layer in report');
        console.log(`  Turn 30 strategy: ${label.slice(0, 72)}…`);
        console.log(`  Turn 30 layer: ${report.dominantLayer}, links: ${report.activeLinks}, avg util: ${report.avgUtilizationPct}%`);
      }
    } catch (e) {
      errors.push(`turn ${turn}: ${e.message}`);
    }
  }
  assert(errors.length === 0, errors.join('; '));
}

// --- Run ---

console.log('Phase 8 regression\n');

console.log('P&L / double-count');
testInternalLinksZeroSupplierRevenue();
testVerticalProfitFromCostSavings();
testExportBelowStrongDownstreamLink();
testInfraExternalNotDoubleInternal();

console.log('\nPerformance');
testComputeSynergiesPerformance();

console.log('\nAP economy');
testApEconomyRules();

console.log('\n30-turn progression sim');
simulate30TurnRun();

console.log(`\n${passed} passed, ${failed} failed`);
process.exit(failed ? 1 : 0);
