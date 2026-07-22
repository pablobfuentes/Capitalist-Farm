/**
 * MVP 7.0 Phase 0–1 — business upgrade engine hooks.
 * Run: node scripts/regression-upgrades.js
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
    industry: 'farm_food',
    crisisMult: 1,
    clientHealth: 72,
    supplierHealth: 72,
    acquiredTurn: 1,
    lastCareTurn: 1,
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

// --- Phase 0: data model ---
assert(U.isActive({ mode: 'arcade' }), 'v2 active in Capital Farm');
assert(!U.isActive({ mode: 'simulator' }), 'v2 off in simulator');
assert(!U.isActive({ mode: 'arcade', farmUpgradeV2: false }), 'v2 flag can disable');

const b0 = biz('g1', 'grain_farm', 15000, 9000);
U.ensureBusinessUpgrades(b0);
assert(b0.upgrades && b0.upgrades.hire === 0, 'default upgrades');
assert(b0.upgradeStats.capacityMult === 1, 'default capacity mult');

const legacy = biz('g2', 'grain_farm', 15000, 9000, {
  improvementsApplied: ['capacity', 'sales', 'automation'],
});
U.ensureBusinessUpgrades(legacy);
assert(legacy.upgrades.hire === 1 && legacy.upgrades.marketing === 1 && legacy.upgrades.automation === 1, 'legacy migration');

U.recomputeUpgradeStats(b0, 'grain_farm');
b0.upgrades.hire = 3;
U.recomputeUpgradeStats(b0, 'grain_farm');
assert(Math.abs(b0.upgradeStats.capacityMult - 1.24) < 0.001, 'hire tier cap mult 1.24');

b0.upgrades.manager = true;
U.recomputeUpgradeStats(b0, 'grain_farm');
assert(b0.upgradeStats.effectiveAutopilot === 5, 'manager +1 autopilot on grain (4→5)');
assert(F.neglectThresholdFor(b0) === 6, 'manager +2 neglect grace');

// --- Phase 1: capacity demand hooks ---
const state = baseState({
  portfolio: {
    businesses: [
      biz('grain', 'grain_farm', 15000, 9000, { upgrades: { hire: 2, marketing: 0, automation: 0, care: 0, manager: false } }),
      biz('feed', 'feed_mill', 18000, 11000),
    ],
    realEstate: [],
  },
});
U.ensurePortfolioUpgrades(state);

const capBase = F.capacityFor('grain_farm');
const capUp = F.effectiveCapacity(state, 'grain_farm');
assert(capUp > capBase, 'hire raises effective capacity');

const stateM = baseState({
  portfolio: {
    businesses: [
      biz('grain', 'grain_farm', 15000, 9000),
      biz('feed', 'feed_mill', 18000, 11000, { upgrades: { hire: 0, marketing: 2, automation: 0, care: 0, manager: false } }),
    ],
    realEstate: [],
  },
});
U.ensurePortfolioUpgrades(stateM);
const demandBase = F.computeOwnedDownstreamDemand(baseState({
  portfolio: { businesses: [biz('grain', 'grain_farm', 1, 1), biz('feed', 'feed_mill', 1, 1)], realEstate: [] },
}), 'grain_farm');
const demandUp = F.computeOwnedDownstreamDemand(stateM, 'grain_farm');
assert(demandUp > demandBase, 'customer marketing raises downstream demand on grain');

// --- automation opex ---
const autoBiz = biz('bakery', 'bakery', 22000, 14000, {
  upgrades: { hire: 0, marketing: 0, automation: 3, care: 0, manager: false },
});
const stAuto = baseState({ portfolio: { businesses: [autoBiz], realEstate: [] } });
U.ensurePortfolioUpgrades(stAuto);
const syns = F.computeSynergies(stAuto);
const plain = F.applyToBusiness(autoBiz, syns, stAuto, {});
autoBiz.upgrades.automation = 0;
U.recomputeUpgradeStats(autoBiz, 'bakery');
const syns2 = F.computeSynergies(stAuto);
const noAuto = F.applyToBusiness(autoBiz, syns2, stAuto, {});
autoBiz.upgrades.automation = 3;
U.recomputeUpgradeStats(autoBiz, 'bakery');
const syns3 = F.computeSynergies(stAuto);
const withAuto = F.applyToBusiness(autoBiz, syns3, stAuto, {});
assert(withAuto.cost < noAuto.cost, 'automation lowers opex in applyToBusiness');

// --- valuation profit path ---
const store = biz('store', 'general_store', 32000, 20000, {
  upgrades: { hire: 0, marketing: 2, automation: 0, care: 0, manager: false },
});
const stStore = baseState({ portfolio: { businesses: [store], realEstate: [] } });
U.ensurePortfolioUpgrades(stStore);
const profit = U.quarterlyProfitForBusiness(store, stStore);
assert(typeof profit === 'number' && !Number.isNaN(profit), 'quarterlyProfitForBusiness returns number');

// --- reset on level ---
U.resetUpgradesForLevel(store, 'general_store');
assert(store.upgrades.hire === 0 && store.upgrades.manager === false, 'level reset clears upgrades');

// --- Phase 2: preview & bottlenecks ---
const stChain = baseState({
  portfolio: {
    businesses: [
      biz('grain', 'grain_farm', 15000, 9000, { id: 'grain', upgrades: { hire: 0, marketing: 0, automation: 0, care: 0, manager: false } }),
      biz('feed', 'feed_mill', 18000, 11000, { id: 'feed' }),
    ],
    realEstate: [],
  },
});
stChain.portfolio.businesses[0].upgrades = { hire: 0, marketing: 0, automation: 0, care: 0, manager: false };
U.ensurePortfolioUpgrades(stChain);
const hirePreview = U.computeUpgradePreview(stChain, 'grain', 'hire');
assert(hirePreview && hirePreview.canApply && hirePreview.profitDelta >= 0, 'hire preview computes');
assert(hirePreview.chain !== undefined, 'hire preview includes chain array');
assert(Array.isArray(U.detectPortfolioBottlenecks(stChain)), 'bottleneck detection returns array');

const blocked = U.computeUpgradePreview(stChain, 'grain', 'manager');
U.applyUpgrade(stChain.portfolio.businesses[0], 'manager', stChain);
const blocked2 = U.computeUpgradePreview(stChain, 'grain', 'manager');
assert(blocked2 && !blocked2.canApply, 'manager blocked when already applied');

assert(U.isEligibleForMajorUpgrade({ upgrades: { hire: 2, marketing: 2, automation: 2, care: 2, manager: false } }), 'eligible at 8 tiers');
assert(U.isFullyMatured({ upgrades: { hire: 3, marketing: 3, automation: 3, care: 3, manager: true } }), 'fully matured check');

console.log(`\nUpgrade regression: ${passed} passed, ${failed} failed`);
process.exit(failed > 0 ? 1 : 0);
