/**
 * MVP 7.0 Phase 6 — manager drift + ghost preview data.
 * Run: node scripts/regression-upgrades-phase6.js
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
    lastCareTurn: 5,
    upgrades: U.defaultUpgrades(),
  }, extra || {});
}

function baseState(extra) {
  return Object.assign({
    mode: 'arcade',
    farmUpgradeV2: true,
    turn: 5,
    strategicEdges: [],
    portfolio: { businesses: [], realEstate: [] },
    supplyPolicies: {},
  }, extra || {});
}

console.log('Phase 6 upgrade polish\n');

// 1. Manager passive drift accumulates when not neglected
const driftNode = biz('g', 'grain_farm', 15000, 9000, {
  upgrades: { hire: 0, marketing: 0, automation: 0, care: 0, manager: true },
  lastCareTurn: 5,
});
const stDrift = baseState({ portfolio: { businesses: [driftNode], realEstate: [] } });
U.ensureBusinessUpgrades(driftNode);
const capBefore = driftNode.upgradeStats.capacityMult;
U.applyManagerPassiveDrift(stDrift);
assert((driftNode.managerDrift.hire || 0) >= U.MANAGER_DRIFT_PER_QTR - 0.0001,
  'manager drift adds hire axis drift');
assert(driftNode.upgradeStats.capacityMult > capBefore,
  'capacity mult increases after drift');
for (let i = 0; i < 5; i += 1) U.applyManagerPassiveDrift(stDrift);
assert((driftNode.managerDrift.hire || 0) >= U.MANAGER_DRIFT_PER_QTR * 5 - 0.001,
  'drift accumulates over multiple quarters');

// 2. Neglected business does not drift
const neglectNode = biz('n', 'feed_mill', 18000, 11000, {
  upgrades: { hire: 0, marketing: 0, automation: 0, care: 0, manager: true },
  lastCareTurn: 1,
});
const stNeg = baseState({ turn: 8, portfolio: { businesses: [neglectNode], realEstate: [] } });
U.ensureBusinessUpgrades(neglectNode);
neglectNode.managerDrift = U.defaultManagerDrift();
U.applyManagerPassiveDrift(stNeg);
assert((neglectNode.managerDrift.hire || 0) < 0.0001, 'neglected node skips manager drift');

// 3. Drift capped at tier headroom
const maxHire = biz('m', 'grain_farm', 15000, 9000, {
  upgrades: { hire: 3, marketing: 3, automation: 3, care: 0, manager: true },
  lastCareTurn: 5,
});
const stCap = baseState({ portfolio: { businesses: [maxHire], realEstate: [] } });
U.ensureBusinessUpgrades(maxHire);
for (let i = 0; i < 20; i += 1) U.applyManagerPassiveDrift(stCap);
assert((maxHire.managerDrift.hire || 0) < 0.001, 'drift stops when hire tiers maxed');

// 4. Ghost preview chain data — hire at strained supplier improves downstream fulfill
const grain = biz('grain', 'grain_farm', 15000, 9000, { valuation: 150000 });
const feed = biz('feed', 'feed_mill', 20000, 12000, { valuation: 150000 });
const store = biz('store', 'general_store', 36000, 25000, { valuation: 200000 });
const stGhost = baseState({
  portfolio: { businesses: [grain, feed, store], realEstate: [] },
});
U.ensurePortfolioUpgrades(stGhost);
const ghostPrev = U.computeUpgradePreview(stGhost, 'grain', 'hire');
assert(ghostPrev && ghostPrev.canApply, 'ghost preview hire is applicable');
assert(Array.isArray(ghostPrev.chain), 'ghost preview includes chain array');
const linkDelta = (ghostPrev.chain || []).find((l) => l.connectionId === 'grain_to_feed');
if (linkDelta && linkDelta.fulfillBefore < 0.99) {
  assert(linkDelta.fulfillAfter >= linkDelta.fulfillBefore,
    'hire ghost shows improved or equal fulfillment on grain→feed');
  console.log(`  Ghost hire: grain→feed ${Math.round(linkDelta.fulfillBefore * 100)}%→${Math.round(linkDelta.fulfillAfter * 100)}%`);
} else {
  console.log('  (skip link delta — chain not strained in fixture)');
}

// 5. resetUpgradesForLevel clears manager drift
const resetNode = biz('r', 'bakery', 28000, 19000, {
  upgrades: { hire: 2, marketing: 1, automation: 0, care: 0, manager: true },
});
resetNode.managerDrift = { hire: 0.01, marketing: 0.005, automation: 0 };
U.resetUpgradesForLevel(resetNode, 'bakery');
assert(resetNode.managerDrift.hire === 0 && resetNode.upgrades.hire === 0,
  'reset clears drift and tiers');

// 6. Hire preview shows capacity delta even with zero profit
const soloGrain = biz('solo', 'grain_farm', 15000, 9000, { valuation: 150000 });
const stSolo = baseState({ portfolio: { businesses: [soloGrain], realEstate: [] } });
U.ensurePortfolioUpgrades(stSolo);
const hirePrev = U.computeUpgradePreview(stSolo, 'solo', 'hire');
assert(hirePrev && hirePrev.canApply && hirePrev.capacityAfter > hirePrev.capacityBefore,
  'hire preview shows capacity increase');
const effectLine = U.formatTrackEffectLine(hirePrev, 'hire');
assert(effectLine.includes('Cap') && effectLine.includes('→'), 'hire effect line shows capacity arrow');
assert(F.baselineCapacityLoad('grain_farm', 75) > 0, 'baseline load is non-zero for grain farm');

console.log(`\nPhase 6 polish: ${passed} passed, ${failed} failed`);
process.exit(failed > 0 ? 1 : 0);
