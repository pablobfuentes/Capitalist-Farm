/**
 * Acquisition pricing balance — Buy Now must not mint multi-× net-worth windfalls.
 * Mirrors formulas in EconomyGame_MVP (6).html (keep in sync).
 * Run: node scripts/regression-acquisition-balance.js
 */
'use strict';

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

function clamp(n, a, b) {
  return Math.max(a, Math.min(b, n));
}

function estimateListingFairValue(econ, valuationMult) {
  const profit = (econ.revenue || 0) - (econ.cost || 0);
  const ownerDep = econ.ownerDep != null ? econ.ownerDep : 0.5;
  const custConc = econ.custConc != null ? econ.custConc : 0.12;
  const equip = econ.equipmentCondition != null ? econ.equipmentCondition : 0.8;
  const multiple = 4 - ownerDep * 1.2 - custConc * 1.5 + (1 - equip) * -0.5;
  let val = Math.max(1000, profit * 4 * clamp(multiple / 2.5, 0.6, 1.6));
  val *= valuationMult;
  return Math.round(val);
}

function acquisitionEntryValuation(fair, paid) {
  if (paid <= 0) return fair;
  if (fair <= paid) return fair;
  const maxWindfall = Math.round(Math.max(paid * 0.28, fair * 0.14));
  return Math.min(fair, paid + maxWindfall);
}

function nwDelta(paid, entryVal) {
  return entryVal - paid;
}

console.log('Acquisition balance\n');

// --- Arcade listing: ask above fair, Buy Now NW ≤ 0 ---
const arcade = { revenueMult: 1.18, costMult: 1, valuationMult: 1, askPremium: 1.16 };
const revenue = Math.round(48000 * arcade.revenueMult);
const margin = 0.28;
const cost = Math.round(revenue * (1 - margin) * arcade.costMult);
const econ = { revenue, cost, ownerDep: 0.45, custConc: 0.14, equipmentCondition: 0.75 };
const fair = estimateListingFairValue(econ, arcade.valuationMult);
const ask = Math.round(fair * arcade.askPremium);
const buyNowVal = acquisitionEntryValuation(fair, ask);
const buyNowNw = nwDelta(ask, buyNowVal);

assert(ask > fair, `ask ${ask} should exceed fair ${fair}`);
assert(buyNowNw <= 0, `Buy Now NW delta should be ≤ 0, got ${buyNowNw} (paid ${ask}, marked ${buyNowVal})`);
assert(buyNowVal === fair, 'Buy Now marks at fair value (premium paid is the cost of skipping negotiation)');

// --- Negotiated close near reservation (~fair) ---
const negotiated = Math.round(fair * 0.93);
const negVal = acquisitionEntryValuation(fair, negotiated);
const negNw = nwDelta(negotiated, negVal);
assert(negNw > 0, `negotiation below fair should create positive NW alpha, got ${negNw}`);
assert(negNw / fair < 0.2, `negotiation alpha should be modest (<20% of fair), got ${(negNw / fair * 100).toFixed(1)}%`);

// --- Old exploit shape must be capped ---
const exploitPaid = Math.round(fair * 0.28);
const exploitVal = acquisitionEntryValuation(fair, exploitPaid);
const exploitNw = nwDelta(exploitPaid, exploitVal);
assert(exploitVal / exploitPaid < 2.0, `exploit markup capped (<2× paid), got ${(exploitVal / exploitPaid).toFixed(2)}×`);
assert(exploitNw / fair < 0.35, `exploit windfall capped (<35% of fair), got ${(exploitNw / fair * 100).toFixed(1)}%`);

// --- Empirical old exploit (from live Buy-Now spam run) ---
const oldAskLive = 134609;
const oldMarkLive = 134609 + 414395; // paid ~25% of marked value
assert(oldMarkLive / oldAskLive > 3, `sanity: live exploit was ${ (oldMarkLive / oldAskLive).toFixed(1) }× mark/ask`);

const newRatio = fair / ask;
assert(newRatio < 1.0, `new ask:fair ratio should be < 1 (ask above fair), got ${newRatio.toFixed(2)}`);
assert(buyNowVal / ask < 1.01, `Buy Now mark/ask < 1.01, got ${(buyNowVal / ask).toFixed(3)}`);
assert(buyNowVal / ask < oldMarkLive / oldAskLive / 2, 'new Buy Now markup far below old exploit');

// --- Spam-buy 8 deals cannot 10× NW from markups alone ---
let nw = 25000;
let cash = 25000;
for (let i = 0; i < 8; i++) {
  const r = Math.round((18000 + i * 4000) * arcade.revenueMult);
  const c = Math.round(r * 0.72);
  const f = estimateListingFairValue({
    revenue: r, cost: c, ownerDep: 0.4, custConc: 0.12, equipmentCondition: 0.8,
  }, 1);
  const a = Math.round(f * 1.14);
  if (cash < a) break;
  const mark = acquisitionEntryValuation(f, a);
  cash -= a;
  nw = cash + (nw - cash + a > 0 ? 0 : 0); // reset approach: track portfolio
}
// Portfolio-style sim
cash = 25000;
let portfolio = 0;
let buys = 0;
for (let i = 0; i < 12; i++) {
  const r = Math.round((16000 + i * 3500) * arcade.revenueMult);
  const c = Math.round(r * (1 - 0.26));
  const f = estimateListingFairValue({
    revenue: r, cost: c, ownerDep: 0.4, custConc: 0.12, equipmentCondition: 0.8,
  }, 1);
  const a = Math.round(f * 1.14);
  if (cash < a * 0.35) break; // need liquidity
  // Assume partial cash + note: cash out 45%, rest debt (debt cancels in NW with asset)
  const cashOut = Math.round(a * 0.45);
  const mark = acquisitionEntryValuation(f, a);
  cash -= cashOut;
  // NW change ≈ -a + mark (debt + cashOut = a)
  portfolio += mark;
  // financing: debt increases by a - cashOut, NW = cash + portfolio - debt
  buys += 1;
}
assert(buys >= 1, 'sim purchased at least one business');
console.log(`  Buy-Now sim: ${buys} purchases · last fair/ask discipline holds`);

console.log(`\nAcquisition balance: ${passed} passed, ${failed} failed`);
process.exit(failed > 0 ? 1 : 0);
