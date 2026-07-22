/**
 * Negotiation close / offer parsing regression.
 * Run: node scripts/regression-negotiation-close.js
 */
const fs = require('fs');
const path = require('path');

function loadRivalFarmer() {
  const p = path.join(__dirname, '../js/rival-farmer.js');
  const tail = '})(globalThis);';
  eval(fs.readFileSync(p, 'utf8').replace(/\}\)\(typeof window !== 'undefined' \? window : globalThis\);$/, tail));
}

loadRivalFarmer();
const R = globalThis.RivalFarmer;

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

function normalizeOffer(raw) {
  const o = Object.assign({}, raw);
  if (o.totalPrice && (o.cashAtClosing == null || o.cashAtClosing === 0)) {
    o.cashAtClosing = raw._allCash ? o.totalPrice : Math.round(o.totalPrice * 0.45);
  }
  if (raw._allCash || o.cashAtClosing === o.totalPrice) {
    o.cashAtClosing = o.totalPrice;
    o.termsOffered = (o.termsOffered || []).filter((t) => !/seller note|payment schedule|earnout|deposit/i.test(t));
  }
  return o;
}

const helpers = { normalizeOffer };

const neg = {
  context: { price: 21251, opp: { revenue: 8500 } },
  counterparty: { archetypeId: 'desperate_seller', role: 'seller' },
  playerLastOffer: null,
};

console.log('Negotiation close parsing\n');

// 1. all upfront = all cash
const upfront = R.parseOfferAmountsFromText('is 18,000 good for you? all upfront.');
assert(upfront && upfront.totalPrice === 18000 && upfront.cashAtClosing === 18000,
  'all upfront parses as full cash at 18000');

// 2. at closing only (no note) = all cash
const atClose = R.parseOfferAmountsFromText("ok I'll do 16,500 at closing, that is the best I can do");
assert(atClose && atClose.totalPrice === 16500 && atClose.cashAtClosing === 16500,
  'single amount at closing is all cash');

// 3. close at $X
const closeAt = R.parseOfferAmountsFromText('all right, lets close at 18,000 if you agree');
assert(closeAt && closeAt.totalPrice === 18000 && closeAt.cashAtClosing === 18000,
  'close at 18000 parses as all cash');

// 4. seller note offer stays structured
const note = R.parseOfferAmountsFromText('10,000 upfront and 6,000 on a sellers note for next quarter');
assert(note && note.totalPrice === 16000 && note.cashAtClosing === 10000,
  'seller note split parses correctly');
assert(!R.isAllCashOfferText('10,000 upfront and 6,000 on a sellers note for next quarter'),
  'seller note text is not all-cash');

// 5. finalize strips stale terms on all-cash message
const built = R.buildPlayerOfferFromMessage(
  'is 18,000 good for you? all upfront. plus I will keep the business name and brand',
  { intent: 'offer' },
  neg,
  helpers
);
assert(built.offer && built.offer.totalPrice === 18000 && built.offer.cashAtClosing === 18000,
  'buildPlayerOffer all upfront full cash');
assert(!(built.offer.termsOffered || []).some((t) => /seller note|payment schedule/i.test(t)),
  'all upfront offer has no seller note terms');

// 6. closing intent
const closing = R.buildPlayerOfferFromMessage('all right, lets close at 18,000 if you agree', { intent: 'question' }, neg, helpers);
assert(closing.intent === 'accept' && closing.offer && closing.offer.totalPrice === 18000,
  'close at 18000 yields accept intent');

// 7. closing intent reuses last offer
neg.playerLastOffer = { totalPrice: 18000, cashAtClosing: 18000, closingSpeed: 'standard', termsOffered: [] };
const closeReuse = R.buildPlayerOfferFromMessage('all right, lets close if you agree', { intent: 'question' }, neg, helpers);
assert(closeReuse.intent === 'accept' && closeReuse.offer && closeReuse.offer.totalPrice === 18000,
  'close without number reuses playerLastOffer');

console.log(`\nNegotiation close: ${passed} passed, ${failed} failed`);
process.exit(failed > 0 ? 1 : 0);
