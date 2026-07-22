/**
 * MVP 7.0 Phase 5 — acceptance tests for five-axis upgrades.
 * Run: node scripts/regression-upgrades-phase5.js
 */
const fs = require('fs');
const path = require('path');

function loadEngine() {
  const farmPath = path.join(__dirname, '../js/farm-supply-chain.js');
  const upPath = path.join(__dirname, '../js/business-upgrades.js');
  const tail = '})(globalThis);';
  eval(fs.readFileSync(farmPath, 'utf8').replace(/\}\)\(typeof window !== 'undefined' \? window : globalThis\);$/, tail));
  eval(fs.readFileSync(upPath, 'utf8').replace(/\}\)\(typeof window !== 'undefined' \? window : globalThis\);$/, tail));
}

loadEngine();
const F = globalThis.FarmSupplyChain;
const U = globalThis.BusinessUpgrades;

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

function biz(id, templateId, rev, cost, extra) {
  return Object.assign({
    id,
    templateId,
    name: (F.templateById(templateId) || {}).name || templateId,
    revenuePerTurn: rev,
    operatingCosts: cost,
    ownerDependence: 0.5,
    custConc: 0.12,
    equipmentCondition: 0.85,
    valuation: Math.max(50000, (rev - cost) * 4 * 3),
    industry: 'farm_food',
    crisisMult: 1,
    clientHealth: 72,
    supplierHealth: 72,
    acquiredTurn: 1,
    lastCareTurn: 1,
    upgrades: U.defaultUpgrades(),
  }, extra || {});
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
  return { revenue, costs, profit: revenue - costs, synergies: syns };
}

console.log('Phase 5 upgrade acceptance\n');

// 1. Marketing capped when upstream short
const stChain = baseState({
  portfolio: {
    businesses: [
      biz('grain', 'grain_farm', 15000, 9000),
      biz('feed', 'feed_mill', 18000, 11000),
      biz('bakery', 'bakery', 22000, 14000),
      biz('store', 'general_store', 32000, 20000),
    ],
    realEstate: [],
  },
});
U.ensurePortfolioUpgrades(stChain);
const grainUtil = F.computeSupplierUtilization(stChain).grain_farm;
if (grainUtil && grainUtil.overCapacity) {
  const mktPreview = U.computeUpgradePreview(stChain, 'store', 'marketing');
  assert(mktPreview && mktPreview.wastedPct > 0.05,
    `store marketing wasted when grain short (${Math.round((mktPreview?.wastedPct || 0) * 100)}%)`);
  assert(mktPreview.profitDelta < mktPreview.cost / 2,
    'marketing profit delta modest when bottlenecked');
} else {
  console.log('  (skip marketing cap — grain not over capacity in fixture)');
}

// 2. Hire unlocks chain fulfillment
const stHire = baseState({
  portfolio: {
    businesses: [
      biz('grain', 'grain_farm', 15000, 9000, { valuation: 120000 }),
      biz('feed', 'feed_mill', 18000, 11000, { valuation: 140000 }),
    ],
    realEstate: [],
  },
});
U.ensurePortfolioUpgrades(stHire);
const hirePrev = U.computeUpgradePreview(stHire, 'grain', 'hire');
assert(hirePrev && hirePrev.canApply, 'hire preview available');
const feedLink = (hirePrev.chain || []).find((l) => l.customer === 'feed_mill' || l.label.includes('Feed'));
if (feedLink) {
  assert(feedLink.fulfillAfter >= feedLink.fulfillBefore,
    'hire weakly improves feed link fulfillment');
} else {
  assert(hirePrev.profitDelta >= 0, 'hire improves profit when chain active');
}

// Apply hire and check shortage relief
const capBefore = F.effectiveCapacity(stHire, 'grain_farm');
U.applyUpgrade(stHire.portfolio.businesses[0], 'hire', stHire);
const capAfter = F.effectiveCapacity(stHire, 'grain_farm');
assert(capAfter > capBefore, 'hire applied raises capacity');

// 3. Automation valuation ≈ profit delta × multiple
const autoB = biz('bakery', 'bakery', 22000, 14000, { valuation: 180000 });
autoB.upgrades = { hire: 0, marketing: 0, automation: 2, care: 0, manager: false };
const stAuto = baseState({ portfolio: { businesses: [autoB], realEstate: [] } });
U.ensurePortfolioUpgrades(stAuto);
const prevAuto = U.computeUpgradePreview(stAuto, 'bakery', 'automation');
assert(prevAuto && prevAuto.canApply && prevAuto.profitDelta > 0, 'automation T3 preview positive profit');
const valRatio = prevAuto.valDelta / Math.max(1, prevAuto.profitDelta);
assert(valRatio >= 2 && valRatio <= 20,
  `valuation delta scales with profit (ratio ${valRatio.toFixed(1)})`);

// 4. Care on restaurant lowers crisis mult
const rest = biz('rest', 'farmhouse_restaurant', 45000, 32000, { valuation: 280000, crisisMult: 1 });
const stCare = baseState({ portfolio: { businesses: [rest], realEstate: [] } });
U.applyUpgrade(rest, 'care', stCare);
assert(rest.crisisMult < 1, 'care tier lowers crisisMult');
assert(rest.upgradeStats.effectiveAutopilot === F.autopilotFor('farmhouse_restaurant'),
  'care alone does not bump autopilot');

// 5. Manager capstone once per level
const mgrB = biz('rest2', 'farmhouse_restaurant', 45000, 32000, { valuation: 280000 });
const stMgr = baseState({ portfolio: { businesses: [mgrB], realEstate: [] } });
U.applyUpgrade(mgrB, 'manager', stMgr);
assert(mgrB.upgradeStats.effectiveAutopilot === F.autopilotFor('farmhouse_restaurant') + 1,
  'manager +1 effective autopilot');
assert(F.neglectThresholdFor(mgrB) === U.BASE_NEGLECT_TURNS + 2, 'manager +2 neglect grace');
const blocked = U.computeUpgradePreview(stMgr, 'rest2', 'manager');
assert(blocked && !blocked.canApply, 'second manager blocked');

// 6. Consolidated P&L — marketing demand does not stack fake supplier revenue
const stMkt = baseState({
  portfolio: {
    businesses: [
      biz('grain', 'grain_farm', 18000, 10000),
      biz('store', 'general_store', 32000, 20000),
    ],
    realEstate: [],
  },
});
U.ensurePortfolioUpgrades(stMkt);
const before = farmQuarterlyTotals(stMkt);
const grainBiz = stMkt.portfolio.businesses.find((b) => b.templateId === 'grain_farm');
const grainRevBefore = F.applyToBusiness(grainBiz, before.synergies, stMkt, {}).rev;
U.applyUpgrade(stMkt.portfolio.businesses.find((b) => b.templateId === 'general_store'), 'marketing', stMkt);
const after = farmQuarterlyTotals(stMkt);
const grainRevAfter = F.applyToBusiness(grainBiz, after.synergies, stMkt, {}).rev;
assert(grainRevAfter === grainRevBefore,
  'marketing on store must not inflate grain supplier revenue');
after.synergies.filter((y) => y.internalLink).forEach((y) => {
  assert(y.revenueBonusSupplier === 0, `no supplier rev stack on ${y.label}`);
});

// 7. Migration — four legacy improvements
const mig = biz('m', 'feed_mill', 18000, 11000, {
  improvementsApplied: ['capacity', 'sales', 'automation', 'care'],
});
U.ensureBusinessUpgrades(mig);
assert(mig.upgrades.hire === 1 && mig.upgrades.marketing === 1
  && mig.upgrades.automation === 1 && mig.upgrades.care === 1, 'four legacy maps to four tiers');
const val = U.estimateValuation(mig, baseState({ portfolio: { businesses: [mig], realEstate: [] } }));
assert(Number.isFinite(val) && val > 0, 'migration produces finite valuation');

// 8. Payback band — tier 1 hire on grain with active feed downstream
const payGrain = biz('grain', 'grain_farm', 15000, 9000, { valuation: 150000 });
const payFeed = biz('feedp', 'feed_mill', 20000, 12000, { valuation: 150000 });
const stPay = baseState({ portfolio: { businesses: [payGrain, payFeed], realEstate: [] } });
U.ensurePortfolioUpgrades(stPay);
const payPrev = U.computeUpgradePreview(stPay, 'grain', 'hire');
if (payPrev && payPrev.canApply && payPrev.profitDelta > 0 && payPrev.paybackQtrs) {
  assert(payPrev.paybackQtrs === Math.ceil(payPrev.cost / payPrev.profitDelta),
    'payback quarters matches cost / profit delta');
  if (payPrev.profitDelta > 100) {
    assert(payPrev.paybackQtrs >= 2 && payPrev.paybackQtrs <= 12,
      `hire T1 payback ${payPrev.paybackQtrs} qtrs in 2–12 band`);
  }
  console.log(`  Hire T1 payback (Grain→Feed): ~${payPrev.paybackQtrs} qtrs · Δ profit ${payPrev.profitDelta}/qtr`);
} else {
  console.log(`  (skip payback band — delta ${payPrev?.profitDelta || 0} in chain fixture)`);
}

// 9. Manager cost fraction
const mgrCost = U.businessImproveCost(
  biz('x', 'grain_farm', 15000, 9000, { valuation: 200000 }),
  'manager'
);
assert(mgrCost === Math.round(200000 * 0.15), 'manager costs 15% of valuation');

console.log(`\nPhase 5 acceptance: ${passed} passed, ${failed} failed`);
process.exit(failed > 0 ? 1 : 0);
