/**
 * Capital Farm — Rival Farmer three-way acquisition contests.
 *
 * Hidden contest rules drive seller/rival behavior; the player sees outcomes
 * through dialogue and the package comparison panel, not a rules brief.
 *
 *   <script src="js/rival-farmer.js"></script>
 */
(function (global) {
  'use strict';

  const CONTEST_INTERVAL = 3;
  const RIVAL = {
    name: 'Cassius "Cash" Rowe',
    title: 'Rival Farmer',
    speciesId: 'goat',
    emoji: '🐐',
    tagline: 'Aggressive expander — bids fast, hates losing listings.',
  };

  /** Cassius "Cash" Rowe — goat audacity, farm-capitalism wit (Stardew meets Bloomberg). */
  const RIVAL_BANTER = {
    opening: [
      (ctx) => `${formatMoney(ctx.price)} from Rowe Ag — cash-heavy, paperwork-light. ${ctx.asset} fits my map and I'm not here to wait on sentiment.`,
      (ctx) => `I'll open at ${formatMoney(ctx.price)}. I don't do earnouts, I don't do poetry, and I don't do second place on listings I want.`,
      (ctx) => `${formatMoney(ctx.price)} cash-forward on ${ctx.asset}. Tell your other bidder to stop sharpening their pencil and start counting.`,
      (ctx) => `Rowe Ag bids ${formatMoney(ctx.price)} — clean break, fast close. I've already mentally plowed this asset into my expansion plan.`,
    ],
    counter: [
      (ctx) => `${formatMoney(ctx.price)} — I'll beat your headline. Cash at close, no barnyard drama.`,
      (ctx) => `Try ${formatMoney(ctx.price)}. Rowe Ag doesn't bid on feelings — we bid on closing dates.`,
      (ctx) => `${formatMoney(ctx.price)}, cash-heavy. You can keep the creative financing; I'll keep the seller's attention.`,
      (ctx) => `New number: ${formatMoney(ctx.price)}. My accountant stopped screaming, so we're in business.`,
    ],
    hold: [
      (ctx) => `Still ahead at ${formatMoney(ctx.price)} on the package that actually closes — talk louder if you want to change that.`,
      (ctx) => `My ${formatMoney(ctx.price)} cash package still lands harder here. Impress me with money, not adjectives.`,
      (ctx) => `I don't do retention plans or side quests — beat ${formatMoney(ctx.price)} with cash or enjoy the view from second place.`,
      (ctx) => `You're doing a lot of talking for someone trailing ${formatMoney(ctx.price)} where it counts.`,
    ],
    concedeTerms: [
      (ctx) => `Fine. You brought ${ctx.term || 'structure'} I won't touch — Rowe Ag buys dirt and cash flow, not HR newsletters.`,
      (ctx) => `${ctx.term || 'Those terms'}? Hard pass. You win the parts I can't put in writing without my lawyer crying.`,
      (ctx) => `Keep your ${ctx.term || 'side deals'}. I'll go find a seller who understands money over manifestos.`,
      (ctx) => `You out-structured me. Enjoy the win — I'll be at the next listing with actual cash and fewer footnotes.`,
    ],
    concedeCeiling: [
      (ctx) => `That's past where my spreadsheet says "brave" turns into "stupid." Take ${ctx.asset} — I take the lesson.`,
      (ctx) => `${formatMoney(ctx.playerPrice || ctx.price)} is my ceiling dressed in ambition. You take the listing.`,
      (ctx) => `I'm not chasing that number into a ditch. Rowe Ag is done bidding on ${ctx.asset}.`,
      (ctx) => `My cash stops here. You win — try not to spend it all on seller notes and hope.`,
    ],
    concedeBlown: [
      (ctx) => `I'm not matching ${formatMoney(ctx.playerPrice || ctx.price)} with pretend money. Take the listing — I need a drink and a cheaper farm.`,
      (ctx) => `That package doesn't pencil for a cash buyer. You win. I'll pretend I wasn't interested anyway.`,
    ],
    winWalk: [
      (ctx) => `Smart fold. I'll send you a postcard from the closing table on ${ctx.asset}.`,
      (ctx) => `Walking away? Bold strategy. I'll tell the seller you had a sudden allergy to competition.`,
      (ctx) => `Thanks for the clear lane. Rowe Ag accepts your surrender — ${ctx.asset} is mine.`,
      (ctx) => `You left money on the table and the listing on mine. Pleasure doing almost-business with you.`,
    ],
    winTimeout: [
      (ctx) => `Turn's up. My bid stands, your AP doesn't — classic Rowe Ag efficiency on ${ctx.asset}.`,
      (ctx) => `While you were drafting margin speeches, I was writing a check. Property's mine.`,
      (ctx) => `Time ran out. ${formatMoney(ctx.price)} still leads — I'll take ${ctx.asset} and you take the lesson.`,
      (ctx) => `The clock beat you before I had to. ${ctx.asset} joins Rowe Ag Holdings — no charge for the education.`,
    ],
    winOutbid: [
      (ctx) => `My package still wins where it matters. ${ctx.asset} is Rowe Ag land now — better luck at the next auction.`,
      (ctx) => `Seller chose cash and certainty over your spreadsheet theater. I'll put a goat on the deed for luck.`,
      (ctx) => `You had your shot. ${formatMoney(ctx.price)} closed it — I'll wave from ${ctx.asset} at the quarterly.`,
      (ctx) => `Outbid, outpaced, out the door. ${ctx.asset} was always going to end up in competent hooves.`,
    ],
    loseClosed: [
      (ctx) => `Congratulations — you overpaid with extra steps. I'll be at the next auction with actual cash and fewer feelings.`,
      (ctx) => `Enjoy ${ctx.asset}. I'll enjoy not explaining a seller note to my accountant.`,
      (ctx) => `You beat me. Don't let it go to your head — I still own half the valley's hay routes.`,
      (ctx) => `Fine, take it. ${formatMoney(ctx.playerPrice || ctx.price)} for ${ctx.asset} — I hope you love the maintenance as much as I love saying I told you so.`,
      (ctx) => `You win this round. Rowe Ag will remember — we have long memories and short forgiveness.`,
      (ctx) => `Seller picked your package. Rude, but legal. I'll go sharpen my horns on someone else's listing.`,
    ],
  };

  /** Player portfolio layer — situational taunts in rival contests. */
  const LAYER_TAUNTS = {
    infrastructure: [
      'Rowe Ag buys dirt and cash flow — not HR newsletters. Your tollbooth still has to outbid my wire transfer.',
      'Nice repair-shed empire. Rowe Ag bids closing dates, not maintenance schedules.',
      'Cold storage margins are cute. Cash at close is still the language sellers speak.',
    ],
    consumer_channel: [
      'Love the storefront story. Rowe Ag bids cash — your customer experience does not shorten my close.',
      'Restaurant margins are delicious. Rowe Ag still serves all-cash offers at the closing table.',
      'Retail traffic is not a down payment. Rowe Ag brings wire transfers, not foot traffic projections.',
    ],
    primary_production: [
      'Lot of acres on your map — lot of weather risk too. Rowe Ag prefers assets that do not spoil in a heat wave.',
      'Upstream scale is impressive. Rowe Ag still bids on cash flow, not bushels on paper.',
      'Grain and livestock are volatile. Rowe Ag bids what closes — not what composts.',
    ],
    processing: [
      'Feed mills and bakeries are fine. Rowe Ag buys what pencils — not what smells good at noon.',
      'Processing spread is a nice thesis. Rowe Ag still bids cash-forward on the listing you both want.',
      'You process inputs into margin. Rowe Ag processes bids into closings.',
    ],
  };

  function rivalLayerTaunt(state) {
    if (!state || typeof global.FarmSupplyChain === 'undefined') return null;
    const dom = global.FarmSupplyChain.dominantLayer(state);
    if (!dom || !dom.layer || dom.count < 2) return null;
    const pool = LAYER_TAUNTS[dom.layer];
    return pool && pool.length ? pick(pool) : null;
  }

  const RIVAL_EXCLUDED_TERMS = [
    'employee retention',
    'staff retention',
    'growth plan',
    'earnout',
    'seller note',
    'employment commitment',
    'continuity plan',
    'premium member card',
  ];

  const SPECIES_TERM_WEIGHTS = {
    hen: ['cash certainty', 'milestones', 'deposits', 'payment schedule', 'downside protection'],
    horse: ['employee retention', 'continuity', 'reliability', 'legacy care'],
    pig: ['fast closing', 'credible funding', 'simple terms'],
    sheep: ['evidence', 'warranties', 'risk-sharing'],
    goat: ['fast close', 'cash certainty'],
    donkey: ['evidence', 'warranties', 'risk-sharing', 'precise terms'],
  };

  function isActive(state) {
    return state && state.mode === 'arcade';
  }

  function isContestTurn(state) {
    if (!isActive(state)) return false;
    if (state.turn >= CONTEST_INTERVAL && state.turn % CONTEST_INTERVAL === 0) return true;
    const mono = (state.runStats && state.runStats.monopolyLeverageWins) || 0;
    return mono >= 3 && state.turn >= 6 && state.turn % 5 === 0;
  }

  function scoreOpportunity(state, opp) {
    if (!opp || (opp.assetType !== 'business' && opp.assetType !== 'realestate')) return -1;
    let score = 0;

    if (opp.assetType === 'business') {
      const profit = (opp.revenue || 0) * (opp.margin || 0.2);
      score += (profit / Math.max(1, opp.price)) * 120;
      score += (opp.revenue || 0) / 800;
    } else {
      score += ((opp.rent || 0) / Math.max(1, opp.price)) * 100;
    }

    if (typeof global.FarmSupplyChain !== 'undefined' && opp.templateId) {
      const critical = global.FarmSupplyChain.pickCriticalMissingTemplate(state);
      if (critical && critical.id === opp.templateId) score += 55;
      const hint = global.FarmSupplyChain.strategicHint(state, opp.templateId);
      if (hint) score += 35;
    }
    if (opp.chainHintDeal) score += 40;
    if (opp.starterDeal) score += 25;
    if (opp.wildcardDeal) score += 20;
    return score;
  }

  function pickContestTarget(state, opportunities) {
    const candidates = (opportunities || []).filter(
      (o) => (o.assetType === 'business' || o.assetType === 'realestate') && !o.rivalContest
    );
    if (!candidates.length) return null;
    return candidates.slice().sort((a, b) => scoreOpportunity(state, b) - scoreOpportunity(state, a))[0];
  }

  function displayName(rival) {
    if (!rival) return RIVAL.name;
    return rival.npcName || rival.name || RIVAL.name;
  }

  function formatMoney(n) {
    if (n == null) return '$0';
    return '$' + Math.round(n).toLocaleString();
  }

  function clamp(v, a, b) {
    return Math.max(a, Math.min(b, v));
  }

  function rnd(min, max) {
    return min + Math.random() * (max - min);
  }

  function pick(arr) {
    return arr[Math.floor(Math.random() * arr.length)];
  }

  function contestContext(n, extra) {
    const opp = (n && n.context && n.context.opp) || {};
    const rules = (n && n.contestRules) || {};
    const asset = (opp.name || n.context?.name || 'the listing').split('—')[0].trim();
    const playerPrice = n && n.playerLastOffer && n.playerLastOffer.totalPrice;
    const rivalPrice = n && n.rivalLastOffer && n.rivalLastOffer.totalPrice;
    return Object.assign({
      asset,
      price: rivalPrice || rules.askPrice || opp.price || 0,
      ask: rules.askPrice || opp.price || 0,
      playerPrice,
      rivalPrice,
    }, extra || {});
  }

  function rivalBanter(pool, ctx) {
    const lines = RIVAL_BANTER[pool];
    if (!lines || !lines.length) return '';
    const fn = pick(lines);
    return typeof fn === 'function' ? fn(ctx || {}) : fn;
  }

  function rivalOpeningLine(opp, offer, state) {
    if (state && Math.random() < 0.42) {
      const taunt = rivalLayerTaunt(state);
      if (taunt) return taunt;
    }
    return rivalBanter('opening', {
      asset: (opp.name || 'the listing').split('—')[0].trim(),
      price: offer.totalPrice || 0,
    });
  }

  function rivalWinLine(n, opts) {
    opts = opts || {};
    const ctx = contestContext(n, { price: (n.rivalLastOffer && n.rivalLastOffer.totalPrice) || 0 });
    if (opts.reason === 'walk') return rivalBanter('winWalk', ctx);
    if (opts.reason === 'timeout') return rivalBanter('winTimeout', ctx);
    return rivalBanter('winOutbid', ctx);
  }

  function rivalLoseLine(n) {
    const ctx = contestContext(n, {
      playerPrice: (n.pendingOffer && n.pendingOffer.totalPrice) || (n.playerLastOffer && n.playerLastOffer.totalPrice),
    });
    return rivalBanter('loseClosed', ctx);
  }

  function rivalConcedeLine(reason, ctx) {
    if (reason === 'terms') return rivalBanter('concedeTerms', ctx);
    if (reason === 'blown') return rivalBanter('concedeBlown', ctx);
    return rivalBanter('concedeCeiling', ctx);
  }

  /** Hidden mechanics — never shown as a rules panel to the player. */
  function buildContestRules(state, opp, counterparty) {
    const ask = opp.price || 0;
    const cp = counterparty || {};
    const speciesTerms = SPECIES_TERM_WEIGHTS[cp.speciesId] || [];
    const cash = state && state.cash != null ? state.cash : 0;

    return {
      askPrice: ask,
      rivalMaxBid: Math.round(ask * (1.03 + rnd(0, 0.02))),
      rivalMinBid: Math.round(ask * 0.9),
      rivalExcludedTerms: RIVAL_EXCLUDED_TERMS.slice(),
      rivalAllowedTerms: ['fast close', 'clean break', 'cash certainty'],
      sellerReservation: cp.reservationPrice || Math.round(ask * 0.88),
      sellerRedLine: cp.redLine || Math.round(ask * 0.8),
      sellerPreferredTerms: [...(cp.preferredTerms || []), ...speciesTerms],
      acceptUtility: 18,
      playerMaxCashBid: Math.round(cash * 0.95),
      absurdBidThreshold: Math.round(ask * 1.12),
      playerHardCap: Math.round(ask * 1.2),
    };
  }

  function createRival(state) {
    const base = {
      name: RIVAL.name,
      npcName: RIVAL.name,
      title: RIVAL.title,
      speciesId: RIVAL.speciesId,
      emoji: RIVAL.emoji,
      archetypeId: 'corporate_seller',
      role: 'rival_buyer',
    };
    if (typeof global.FarmAnimalNPC !== 'undefined' && global.FarmAnimalNPC.decorateCounterparty) {
      const cp = global.FarmAnimalNPC.decorateCounterparty(
        {
          archetypeId: 'proud_founder',
          role: 'rival_buyer',
          reservationPrice: null,
          urgency: 0.72,
          trust: 0.35,
          riskTolerance: 0.55,
          concessionStyle: 'fast',
          preferredTerms: ['fast close', 'cash certainty'],
          redLine: null,
          hiddenInfo: 'they are trying to block your supply-chain expansion',
        },
        state,
        { speciesId: RIVAL.speciesId, npcName: RIVAL.name, orgName: 'Rowe Ag Holdings' }
      );
      cp.name = cp.npcName || RIVAL.name;
      cp.title = RIVAL.title;
      cp.emoji = RIVAL.emoji;
      return cp;
    }
    return base;
  }

  function openingOffer(opp, rules) {
    const ask = (rules && rules.askPrice) || opp.price || 0;
    const mult = 0.93 + Math.random() * 0.05;
    const total = Math.round(ask * mult);
    return {
      totalPrice: total,
      cashAtClosing: Math.round(total * (0.5 + Math.random() * 0.15)),
      closingSpeed: 'fast',
      termsOffered: ['fast close', 'clean break'],
    };
  }

  function sellerResponseToRival(opp, offer, counterparty) {
    const ask = opp.price || 0;
    const bid = offer.totalPrice || 0;
    const cp = counterparty || {};
    const speciesHint = cp.speciesId === 'hen'
      ? 'I need more than a fast close — show me certainty and structure.'
      : cp.speciesId === 'horse'
        ? 'Price is one piece — continuity and how you treat people matter here.'
        : 'I need more than speed alone to pick a buyer.';

    if (bid >= ask * 0.98) {
      return `That's essentially my asking price of ${formatMoney(ask)}. I'm not committed yet — I'll hear what your competitor has to say.`;
    }
    if (bid >= ask * 0.9) {
      return `${formatMoney(bid)} is in the conversation against ${formatMoney(ask)}, but ${speciesHint.toLowerCase()}`;
    }
    return `${formatMoney(bid)} is below where I need to be on ${formatMoney(ask)}. Both of you will need to sharpen your numbers.`;
  }

  function extractTermsFromText(text) {
    const lower = (text || '').toLowerCase();
    const terms = [];
    const add = (t) => {
      if (!terms.some((x) => x.toLowerCase() === t.toLowerCase())) terms.push(t);
    };

    if (/keep (the )?staff|employee retention|retain (employees|staff)|keep employees|keeping staff/.test(lower)) {
      add('employee retention');
    }
    if (/growth plan|expansion plan for staff|staff growth/.test(lower)) add('growth plan');
    if (/premium|member card|loyalty card|loyalty program/.test(lower)) add('premium member card');
    if (/milestone|payment schedule|installment|staged payment/.test(lower)) add('payment schedule');
    if (/deposit|down payment/.test(lower)) add('deposit');
    else if (/upfront/.test(lower) && isStructuredFinancingText(lower)) add('deposit');
    if (/fast close|quick close|30 day|thirty day/.test(lower)) add('fast close');
    if (/seller note|earnout|contingent|financing structure|note payable|rest on|balance on/.test(lower)) {
      add('seller note');
    }
    if (/\d+\s*quarter|quarterly|over \d+ quarter|to \d+ quarter/.test(lower)) add('payment schedule');
    if (/continuity|legacy|keep the team/.test(lower)) add('continuity');
    if (/warrant|inspection window|due diligence period/.test(lower)) add('warranties');
    return terms;
  }

  function expandMoneyShorthand(text) {
    return (text || '').replace(/\b(\d+(?:\.\d+)?)\s*([kKmM])\b/g, (_, num, unit) => {
      const mult = unit.toLowerCase() === 'm' ? 1000000 : 1000;
      return String(Math.round(parseFloat(num) * mult));
    });
  }

  function extractNumbersFromText(text) {
    const expanded = expandMoneyShorthand(text);
    return (expanded.match(/\$?\d[\d,]{2,}/g) || []).map((x) => Number(x.replace(/[$,]/g, '')));
  }

  function messageHasOfferFigures(text) {
    const expanded = expandMoneyShorthand(text);
    return (
      /\d[\d,]{2,}/.test(expanded) ||
      /\b\d+\s*[kKmM]\b/.test(text || '') ||
      /\bpercent\b|%/i.test(text || '')
    );
  }

  function isStructuredFinancingText(text) {
    const lower = (text || '').toLowerCase();
    return /seller note|earnout|contingent|deferred|note payable|rest on|remainder|balance on|balance due|carry back|next quarter|over \d+ quarter|installment|financing structure/.test(lower);
  }

  function isClosingIntentText(text) {
    const lower = (text || '').toLowerCase();
    return /\b(?:let'?s|lets)\s+close\b|\bclose\s+(?:at|for|on)\b|\bready to close\b|\bfinalize\b|\bwrap (?:this )?up\b|\bclose the deal\b|\bif you agree\b|\bagreed\b|\bsounds good\b|\bdeal\b|\baccept\b/.test(lower);
  }

  /**
   * Parse total vs cash-at-closing from natural language (order-independent).
   * Supports shorthand: 10k, 33k, 15K
   */
  function isAllCashOfferText(text) {
    const lower = (text || '').toLowerCase();
    if (/no seller note|without a seller note|without seller note|no note\b|no deferred/.test(lower)) return true;
    if (isStructuredFinancingText(text)) return false;
    if (/all\s+cash|full\s+cash|cash\s+only|cash\s+deal|pay\s+(?:in\s+)?cash|entire(?:ly)?\s+in\s+cash|100%\s*cash|(?:in|as|via|with)\s+(?:direct\s+)?cash\b|direct\s+cash/.test(lower)) {
      return true;
    }
    if (/all\s+upfront|pay\s+upfront|entire(?:ly)?\s+upfront|full\s+upfront|100%\s*upfront|upfront\s+all|all\s+at\s+closing/.test(lower)) {
      return true;
    }
    if (/(?:let'?s|lets)\s+close\s+(?:at|for|on)\s+\d/.test(lower)) return true;
    if (/\d[\d,]+\s*at closing/.test(lower) && !isStructuredFinancingText(text)) return true;
    if (/(?:only|just|will do|i'?ll do)\s+\d[\d,]+\s*at closing/.test(lower) && !isStructuredFinancingText(text)) return true;
    return false;
  }

  function parseOfferAmountsFromText(text, opts) {
    opts = opts || {};
    const raw = expandMoneyShorthand(text || '');
    const lower = raw.toLowerCase();
    const askPrice = opts.askPrice || null;

    const closeAtRe = lower.match(/(?:let'?s|lets)\s+close\s+(?:at|for|on)\s+\$?(\d[\d,]{2,})/);
    if (closeAtRe && !isStructuredFinancingText(text)) {
      const val = Number(closeAtRe[1].replace(/,/g, ''));
      if (val >= 500) return { totalPrice: val, cashAtClosing: val };
    }

    const closeBareRe = lower.match(/\bclose\s+(?:at|for|on)\s+\$?(\d[\d,]{2,})/);
    if (closeBareRe && !isStructuredFinancingText(text)) {
      const val = Number(closeBareRe[1].replace(/,/g, ''));
      if (val >= 500) return { totalPrice: val, cashAtClosing: val };
    }

    const directCashRe = lower.match(/(\d[\d,]{2,})\s*(?:dollars?\s*)?(?:in|as|via|with)\s+(?:direct\s+)?cash\b/);
    if (directCashRe) {
      const val = Number(directCashRe[1].replace(/,/g, ''));
      if (val >= 500) return { totalPrice: val, cashAtClosing: val };
    }

    if (isAllCashOfferText(text)) {
      const nums = extractNumbersFromText(text).filter((n) => n >= 500);
      if (nums.length === 1) return { totalPrice: nums[0], cashAtClosing: nums[0] };
      if (nums.length >= 2) {
        let offerAmt = nums[0];
        if (askPrice && nums.includes(askPrice)) {
          offerAmt = nums.find((n) => n !== askPrice) || Math.min.apply(null, nums);
        } else {
          offerAmt = Math.min.apply(null, nums);
        }
        return { totalPrice: offerAmt, cashAtClosing: offerAmt };
      }
    }

    const matches = [];
    const re = /\$?\d[\d,]{2,}/g;
    let m;
    while ((m = re.exec(raw)) !== null) {
      matches.push({
        value: Number(m[0].replace(/[$,]/g, '')),
        index: m.index,
        end: m.index + m[0].length,
      });
    }
    if (!matches.length) return null;

    const values = matches.map((x) => x.value);

    if (isStructuredFinancingText(text) && values.length >= 2) {
      const upfrontMatch = lower.match(/(\d[\d,]+)\s*upfront/);
      const noteMatch = lower.match(/(\d[\d,]+)\s*(?:on|as|via)\s+(?:a\s+)?(?:seller'?s?\s*)?note/);
      if (upfrontMatch && noteMatch) {
        const up = Number(upfrontMatch[1].replace(/,/g, ''));
        const note = Number(noteMatch[1].replace(/,/g, ''));
        if (up >= 500 && note >= 500) {
          return { totalPrice: up + note, cashAtClosing: up };
        }
      }
    }

    let totalPrice = null;
    let cashAtClosing = null;

    matches.forEach((match) => {
      const after = lower.slice(match.end, match.end + 48);
      const before = lower.slice(Math.max(0, match.index - 32), match.index);
      const isClosing =
        /^\s*(at closing|cash at closing|upfront|down payment|at close|cash at close|due at closing)/.test(after) ||
        /^\s*(?:in|as|via|with)\s+(?:direct\s+)?cash\b/.test(after) ||
        /(?:only|just|with only)\s+(?:\$)?\d[\d,]*\s*$/.test(before) && /(?:at closing|upfront|down|cash at close)/.test(after) ||
        /(at closing|cash at closing|upfront|down payment|at close)\s*(and|,)?.{0,8}$/.test(before);
      const isTotal =
        /^\s*(total|altogether|in total|all in|all-in|overall)/.test(after) ||
        /(total|altogether|in total|all in)\s*(and|,)?.{0,8}$/.test(before) ||
        /\boffer(?:ing)?\s+\$?\d/.test(before + raw.slice(match.index, match.end + 12));

      if (isClosing && cashAtClosing == null) cashAtClosing = match.value;
      if (isTotal && totalPrice == null) totalPrice = match.value;
    });

    const onlyClosingRe = lower.match(/(?:only|just|with only)\s+\$?(\d[\d,]{2,})\s*(?:at closing|upfront|down|cash at close)/);
    if (onlyClosingRe) cashAtClosing = Number(onlyClosingRe[1].replace(/,/g, ''));

    const totalRe = lower.match(/(\d[\d,]{2,})\s*(?:dollars?\s*)?(?:total|altogether|in total|all in|all-in|overall)\b/);
    const closingRe = lower.match(/(\d[\d,]{2,})\s*(?:dollars?\s*)?(?:at closing|cash at closing|upfront|down payment|at close|due at closing)\b/);
    if (totalRe) totalPrice = Number(totalRe[1].replace(/,/g, ''));
    if (closingRe) cashAtClosing = Number(closingRe[1].replace(/,/g, ''));

    if (totalPrice == null && values.length === 1) {
      totalPrice = values[0];
      if (isAllCashOfferText(text)) cashAtClosing = values[0];
    }

    if (askPrice && totalPrice === askPrice && values.length >= 2) {
      const alt = values.find((v) => v !== askPrice);
      if (alt != null) totalPrice = alt;
    }
    if (askPrice && cashAtClosing === askPrice && values.length >= 2) {
      const alt = values.find((v) => v !== askPrice);
      if (alt != null) cashAtClosing = alt;
    }

    if (totalPrice == null && cashAtClosing == null && values.length >= 2) {
      totalPrice = Math.max(values[0], values[1]);
      cashAtClosing = Math.min(values[0], values[1]);
    } else {
      if (totalPrice == null && cashAtClosing != null) {
        const other = values.find((v) => v !== cashAtClosing);
        totalPrice = other != null ? other : cashAtClosing;
      }
      if (cashAtClosing == null && totalPrice != null) {
        const other = values.find((v) => v !== totalPrice);
        if (isAllCashOfferText(text)) cashAtClosing = totalPrice;
        else cashAtClosing = other != null ? other : Math.round(totalPrice * 0.45);
      }
    }

    if (isAllCashOfferText(text) && totalPrice != null) {
      cashAtClosing = totalPrice;
    }

    if (totalPrice != null && cashAtClosing != null && cashAtClosing > totalPrice) {
      const hi = Math.max(totalPrice, cashAtClosing);
      const lo = Math.min(totalPrice, cashAtClosing);
      totalPrice = hi;
      cashAtClosing = lo;
    }

    if (totalPrice == null) return null;
    return {
      totalPrice,
      cashAtClosing: cashAtClosing != null ? cashAtClosing : Math.round(totalPrice * 0.45),
    };
  }

  function inferOfferStructure(text, amounts) {
    const lower = (text || '').toLowerCase();
    let terms = extractTermsFromText(text);
    if (!amounts) return { amounts: null, terms };

    let totalPrice = amounts.totalPrice;
    let cashAtClosing = amounts.cashAtClosing;

    if (isAllCashOfferText(text)) {
      cashAtClosing = totalPrice;
      terms = terms.filter((t) => !/seller note|payment schedule|earnout/i.test(t));
      return { amounts: { totalPrice, cashAtClosing }, terms };
    }

    if (isAllCashOfferText(text)) {
      cashAtClosing = totalPrice;
      terms = terms.filter((t) => !/seller note|payment schedule|earnout|deposit/i.test(t));
      return { amounts: { totalPrice, cashAtClosing }, terms };
    }

    if (/no seller note|without a seller note|without seller note|no note\b|no deferred/.test(lower)) {
      cashAtClosing = totalPrice;
      terms = terms.filter((t) => !/seller note|payment schedule|earnout|deposit/i.test(t));
      return { amounts: { totalPrice, cashAtClosing }, terms };
    }

    if (/rest (on|via|as|over)|remainder|balance (on|as|over)|seller note|deferred|note payable|carry back/.test(lower)) {
      terms = mergeTerms(terms, ['seller note']);
    }

    if (/upfront.*(?:rest|remainder|balance).*(?:at closing|at close)/.test(lower)) {
      cashAtClosing = totalPrice;
      terms = mergeTerms(terms, ['deposit', 'payment schedule']);
    } else if (/(?:upfront|down payment|deposit)/.test(lower) && !/rest|remainder|balance|note|deferred|seller note/.test(lower)) {
      cashAtClosing = totalPrice;
      terms = mergeTerms(terms, ['deposit', 'payment schedule']);
    } else if (/(?:only|just|with only)\s+\d[\d,]*\s*(?:at closing|upfront|down)/.test(lower) && !isAllCashOfferText(text)) {
      terms = mergeTerms(terms, ['seller note', 'payment schedule']);
    }

    if (
      cashAtClosing < totalPrice * 0.72 &&
      !isAllCashOfferText(text) &&
      !/all cash|full cash|100% cash|cash deal/.test(lower) &&
      !terms.some((t) => /deposit|payment schedule/.test(t))
    ) {
      terms = mergeTerms(terms, ['seller note', 'payment schedule']);
    }

    return { amounts: { totalPrice, cashAtClosing }, terms };
  }

  function finalizePlayerOffer(offer, text, normalizeOfferFn, n) {
    if (!offer) return null;
    const inferred = inferOfferStructure(text, {
      totalPrice: offer.totalPrice,
      cashAtClosing: offer.cashAtClosing,
    });
    offer.totalPrice = inferred.amounts.totalPrice;
    offer.cashAtClosing = inferred.amounts.cashAtClosing;
    offer.termsOffered = mergeTerms(offer.termsOffered, inferred.terms);
    if (offer.termsOffered.some((t) => /seller note|payment schedule|earnout/i.test(t))) {
      offer.riskToCounterparty = offer.termsOffered.some((t) => /earnout|contingent/i.test(t)) ? 14 : 10;
    }
    return normalizeOfferFn ? normalizeOfferFn(offer, n) : offer;
  }

  function reconcileOfferAmounts(offer, text) {
    if (!offer) return offer;
    const parsed = parseOfferAmountsFromText(text);
    if (!parsed) return offer;

    const labeled = /at closing|cash at closing|upfront|down payment|\btotal\b|altogether|in total|all in/i.test(text);
    const inverted = offer.cashAtClosing > offer.totalPrice;
    const textMismatch =
      offer.totalPrice !== parsed.totalPrice || offer.cashAtClosing !== parsed.cashAtClosing;

    if (labeled || inverted || (textMismatch && extractNumbersFromText(text).length >= 2)) {
      offer.totalPrice = parsed.totalPrice;
      offer.cashAtClosing = parsed.cashAtClosing;
    }
    return offer;
  }

  function buildRawOfferFromAmounts(val, text, terms) {
    const allCash = isAllCashOfferText(text);
    return {
      totalPrice: val,
      cashAtClosing: allCash ? val : Math.round(val * 0.45),
      closingSpeed: 'standard',
      termsOffered: terms || extractTermsFromText(text),
      _allCash: allCash,
    };
  }

  function extractPurchaseOfferFromText(text, negotiation, helpers) {
    const n = negotiation || {};
    const ctx = n.context || {};
    const opp = ctx.opp || {};
    const ask = ctx.price || 0;
    const rev = opp.revenue || listingFromCtx(ctx).quarterlyRevenue;
    const raw = expandMoneyShorthand(text || '');
    const lower = raw.toLowerCase();
    const normalizeOfferFn = helpers && helpers.normalizeOffer;

    const parsedAmounts = parseOfferAmountsFromText(text, { askPrice: ask || null });
    if (parsedAmounts && parsedAmounts.totalPrice) {
      const rawOffer = {
        totalPrice: parsedAmounts.totalPrice,
        cashAtClosing: parsedAmounts.cashAtClosing,
        closingSpeed: 'standard',
        termsOffered: extractTermsFromText(text),
        _allCash: parsedAmounts.cashAtClosing === parsedAmounts.totalPrice,
      };
      return finalizePlayerOffer(rawOffer, text, normalizeOfferFn, n);
    }

    const purchasePatterns = [
      /(?:offer|pay|bid|buy(?:\s+(?:at|for))?|do|take|give|can you do|could you do|i(?:'ll| will) do)\s+\$?(\d[\d,]*(?:\.\d+)?)/i,
      /\$?(\d[\d,]*(?:\.\d+)?)\s*(?:is\s+(?:my\s+|a\s+)?(?:offer|bid|fair(?:\s+offer)?|fair\s+price))/i,
    ];
    for (let i = 0; i < purchasePatterns.length; i++) {
      const m = raw.match(purchasePatterns[i]);
      if (m) {
        const val = Number(String(m[1]).replace(/,/g, ''));
        if (val >= 500) {
          return finalizePlayerOffer(buildRawOfferFromAmounts(val, text), text, normalizeOfferFn, n);
        }
      }
    }

    const re = /\$?\d[\d,]{2,}/g;
    let match;
    const candidates = [];
    while ((match = re.exec(raw)) !== null) {
      const val = Number(match[0].replace(/[$,]/g, ''));
      if (val < 500) continue;
      const near = lower.slice(Math.max(0, match.index - 40), match.index + match[0].length + 40);
      if (/%|percent|\bmargin\b/.test(near) && val <= 100) continue;
      if (/revenue|quarter|qtr|\/qtr|per quarter|operating|profit|fumes|barely|desperately need/.test(near)
          && !/offer|pay|bid|buy|fair|do|take|give|cash/.test(near)) continue;
      if (rev && Math.abs(val - rev) / Math.max(1, rev) < 0.08 && !/offer|pay|bid|buy|fair|do|cash/.test(near)) continue;
      if (ask && val === ask && /business|listing|asking|listed|sign|property|farm|asset/.test(near)) continue;
      let score = 0;
      if (/offer|pay|bid|buy|fair|do|take|give|cash|direct/.test(near)) score += 10;
      if (ask && val !== ask && Math.abs(val - ask) / Math.max(1, ask) < 0.25) score += 4;
      if (ask && val === ask) score -= 8;
      candidates.push({ val, score });
    }
    if (!candidates.length) return null;
    candidates.sort((a, b) => b.score - a.score);
    const best = candidates[0];
    return finalizePlayerOffer(buildRawOfferFromAmounts(best.val, text), text, normalizeOfferFn, n);
  }

  function listingFromCtx(ctx) {
    ctx = ctx || {};
    return ctx.listingEconomics || {};
  }

  function mergeTerms(existing, fromText) {
    const out = [...(existing || [])];
    fromText.forEach((t) => {
      if (!out.some((x) => x.toLowerCase() === t.toLowerCase())) out.push(t);
    });
    return out;
  }

  function rivalCannotMatchTerms(playerTerms, rules) {
    const excluded = (rules && rules.rivalExcludedTerms) || RIVAL_EXCLUDED_TERMS;
    return (playerTerms || []).filter((t) =>
      excluded.some((ex) => {
        const a = t.toLowerCase();
        const b = ex.toLowerCase();
        return a.includes(b.split(' ')[0]) || b.includes(a.split(' ')[0]);
      })
    );
  }

  function buildPlayerOfferFromMessage(text, parsed, negotiation, helpers) {
    const n = negotiation || {};
    const rules = n.contestRules || {};
    const normalizeOfferFn = helpers && helpers.normalizeOffer;
    const lower = (text || '').toLowerCase();
    const nums = extractNumbersFromText(text);
    const mentionsFigure = messageHasOfferFigures(text);
    let intent = (parsed && parsed.intent) || 'question';

    if (mentionsFigure && /\boffer|\boffering|\bi'?ll do|\bi will do|\bdo \d|\bwith \d|\bclose at|\bclose for|\bclose on|\ball upfront|\ball cash/i.test(lower)) {
      intent = 'offer';
    }
    if (isClosingIntentText(text) && mentionsFigure) intent = 'accept';

    if (intent === 'offer' && parsed && parsed.offer && mentionsFigure && normalizeOfferFn) {
      let fromAi = normalizeOfferFn(parsed.offer, n);
      if (fromAi && fromAi.totalPrice) {
        fromAi = reconcileOfferAmounts(fromAi, text);
        fromAi = finalizePlayerOffer(fromAi, text, normalizeOfferFn, n);
        return { offer: fromAi, intent: 'offer' };
      }
    }

    if (!mentionsFigure || !nums.length) {
      if (isClosingIntentText(text)) {
        const amounts = parseOfferAmountsFromText(text, { askPrice: n.context && n.context.price });
        if (amounts && amounts.totalPrice) {
          const rawOffer = {
            totalPrice: amounts.totalPrice,
            cashAtClosing: amounts.cashAtClosing,
            closingSpeed: 'standard',
            termsOffered: extractTermsFromText(text),
            _allCash: amounts.cashAtClosing === amounts.totalPrice,
          };
          const offer = finalizePlayerOffer(rawOffer, text, normalizeOfferFn, n);
          if (offer && offer.totalPrice) return { offer, intent: 'accept' };
        }
        if (n.playerLastOffer && n.playerLastOffer.totalPrice) {
          return { offer: n.playerLastOffer, intent: 'accept' };
        }
        return { offer: null, intent: 'accept' };
      }
      if (/walk|withdraw|never mind|give up/.test(lower)) return { offer: null, intent: 'walk' };
      return { offer: null, intent };
    }

    const amounts = parseOfferAmountsFromText(text, { askPrice: n.context && n.context.price });
    const raw = amounts || {
      totalPrice: nums.length >= 2 ? Math.max(nums[0], nums[1]) : nums[0],
      cashAtClosing: nums.length >= 2 ? Math.min(nums[0], nums[1]) : Math.round(nums[0] * 0.45),
    };
    raw.closingSpeed = /fast|quick|30 day|thirty day/.test(lower) ? 'fast' : 'standard';
    raw.termsOffered = extractTermsFromText(text);

    if (raw.totalPrice > rules.playerHardCap) {
      raw.totalPrice = rules.playerHardCap;
      raw._capped = true;
    }

    const offer = finalizePlayerOffer(raw, text, normalizeOfferFn, n);
    if (offer && offer.totalPrice) {
      const outIntent = isClosingIntentText(text) ? 'accept' : 'offer';
      return { offer, intent: outIntent };
    }
    return { offer: null, intent };
  }

  function sellerDialogueForTurn(n, playerOffer, playerU, rivalU, intent, rules, helpers) {
    const decisionFn = helpers && helpers.negotiationDecision;
    const round = n.round || 0;
    const maxRounds = n.maxRounds || 6;
    const rname = displayName(n.rival);
    const rivalPrice = (n.rivalLastOffer && n.rivalLastOffer.totalPrice) || 0;
    const terms = (playerOffer && playerOffer.termsOffered) || [];
    const playerPrice = playerOffer && playerOffer.totalPrice;

    if (!playerOffer || !playerPrice) {
      return intent === 'question'
        ? 'Give me a clear number and structure if you want a real comparison between you and Rowe.'
        : "I'm listening — put a package on the table.";
    }

    if (playerOffer._capped) {
      return `${formatMoney(playerPrice)} is as far as I'll entertain without re-trading the whole asset — show me how you fund and structure the rest.`;
    }

    const cashDue = (playerOffer && playerOffer.cashAtClosing) || playerPrice;
    const hasFinancing = terms.some((t) => /seller note|earnout|financing|installment|payment schedule|deposit/i.test(t));
    const isStructuredDeal = hasFinancing || cashDue < playerPrice * 0.72;

    if (cashDue > rules.playerMaxCashBid && !isStructuredDeal) {
      return `${formatMoney(cashDue)} at closing is a stretch on cash — show me how you fund it or add structure.`;
    }

    if (
      playerPrice > rules.playerMaxCashBid &&
      !isStructuredDeal &&
      cashDue >= playerPrice * 0.85
    ) {
      return `${formatMoney(playerPrice)} is a big number — I need to see how you fund that without overextending cash at closing.`;
    }

    if (playerPrice >= rules.absurdBidThreshold) {
      return `${formatMoney(playerPrice)} clears my asking price by a wide margin. If the funding is real, you're leading — but I won't hand over keys on a bluff.`;
    }

    const decision = decisionFn ? decisionFn(playerU, round, maxRounds) : (playerU >= rules.acceptUtility ? 'accept' : 'counter');
    const termNote = terms.length ? ` Your ${terms.join(', ')} is part of why I'm comparing.` : '';
    const unmatched = rivalCannotMatchTerms(terms, rules);

    if (n.rivalConceded && decision === 'accept') {
      return `With Rowe out, your package is the one I'd sign${termNote} — close when you're ready.`;
    }

    if (playerU >= rivalU && decision === 'accept') {
      if (unmatched.length) {
        return `Your package beats Rowe — especially on ${unmatched.join(' and ')}, which he won't put in writing${termNote} I'm ready to close.`;
      }
      return `Your offer is the strongest package on the table${termNote} — I'm ready when you are.`;
    }

    if (playerU >= rivalU) {
      if (playerPrice > rivalPrice && unmatched.length) {
        return `${formatMoney(playerPrice)} leads, and Rowe can't match ${unmatched.join(' or ')} — that's real leverage${termNote}`;
      }
      return `${formatMoney(playerPrice)} leads on the full package${termNote} — I'm still comparing before I commit.`;
    }

    if (playerPrice > rivalPrice) {
      return `${formatMoney(playerPrice)} beats Rowe on price, but his cash-heavy structure still scores higher on what I weigh most right now.`;
    }

    return `${formatMoney(playerPrice)} trails ${rname}'s ${formatMoney(rivalPrice)} on the package I'd actually sign today.`;
  }

  function computeRivalResponse(n, playerOffer, playerU, rivalU, text, rules) {
    const lower = (text || '').toLowerCase();
    const rivalOffer = n.rivalLastOffer || {};
    const rivalPrice = rivalOffer.totalPrice || 0;
    const playerPrice = (playerOffer && playerOffer.totalPrice) || 0;
    const playerTerms = (playerOffer && playerOffer.termsOffered) || [];
    const unmatched = rivalCannotMatchTerms(playerTerms, rules);
    const termAttack = /rowe|rival|cassius|staff|retention|can't match|cannot match|not considering/.test(lower);
    const ask = rules.askPrice;
    const ctxBase = contestContext(n, { price: rivalPrice, playerPrice, rivalPrice });

    if (n.rivalConceded) return { action: 'none' };

    if (playerOffer && playerPrice >= rules.absurdBidThreshold && playerU >= rivalU) {
      return {
        action: 'concede',
        dialogue: rivalConcedeLine('blown', ctxBase),
      };
    }

    if (unmatched.length && playerU >= rivalU - 4 && playerPrice >= rivalPrice) {
      return {
        action: 'concede',
        dialogue: rivalConcedeLine('terms', Object.assign({}, ctxBase, { term: unmatched[0] })),
      };
    }

    if (rivalPrice >= rules.rivalMaxBid && playerU >= rivalU) {
      return {
        action: 'concede',
        dialogue: rivalConcedeLine('ceiling', ctxBase),
      };
    }

    if (playerU < rivalU) {
      if (playerPrice > rivalPrice) {
        const bump = Math.round(Math.max(playerPrice + ask * 0.012, rivalPrice * 1.02));
        const newPrice = Math.min(bump, rules.rivalMaxBid);
        if (newPrice > rivalPrice) {
          return {
            action: 'counter',
            rivalOffer: {
              totalPrice: newPrice,
              cashAtClosing: Math.round(newPrice * 0.55),
              closingSpeed: 'fast',
              termsOffered: ['fast close'],
            },
            dialogue: rivalBanter('counter', Object.assign({}, ctxBase, { price: newPrice })),
          };
        }
      }
      if (termAttack && unmatched.length) {
        return {
          action: 'hold',
          dialogue: rivalBanter('hold', ctxBase),
        };
      }
      if (termAttack) {
        return {
          action: 'hold',
          dialogue: rivalBanter('hold', ctxBase),
        };
      }
      if (playerPrice > rivalPrice) {
        return {
          action: 'hold',
          dialogue: rivalBanter('hold', ctxBase),
        };
      }
      return {
        action: 'hold',
        dialogue: rivalBanter('hold', ctxBase),
      };
    }

    if (playerPrice >= rivalPrice) {
      const bump = Math.round(Math.max(playerPrice + ask * 0.015, rivalPrice * 1.02));
      const newPrice = Math.min(bump, rules.rivalMaxBid);

      if (newPrice <= rivalPrice) {
        if (unmatched.length) {
          return {
            action: 'concede',
            dialogue: rivalConcedeLine('terms', Object.assign({}, ctxBase, { term: unmatched.join(' or ') })),
          };
        }
        return {
          action: 'hold',
          dialogue: rivalBanter('hold', ctxBase),
        };
      }

      return {
        action: 'counter',
        rivalOffer: {
          totalPrice: newPrice,
          cashAtClosing: Math.round(newPrice * 0.55),
          closingSpeed: 'fast',
          termsOffered: ['fast close'],
        },
        dialogue: rivalBanter('counter', Object.assign({}, ctxBase, { price: newPrice })),
      };
    }

    return { action: 'hold', dialogue: rivalBanter('hold', ctxBase) };
  }

  function applyContestToTurn(state, opportunities) {
    if (!isContestTurn(state)) return null;
    if (state.rivalContestAppliedTurn === state.turn) return null;

    const target = pickContestTarget(state, opportunities);
    if (!target) return null;

    target.rivalContest = true;
    target.rivalContestTurn = state.turn;
    state.rivalContestAppliedTurn = state.turn;
    state.activeRivalContestOppId = target.id;

    const rival = createRival(state);
    return { opp: target, rival, score: scoreOpportunity(state, target) };
  }

  function buildThreeWayPrompt(negotiation, playerMessage, archetype) {
    const n = negotiation || {};
    const c = n.counterparty || {};
    const arch = archetype || {};
    const ctx = n.context || {};
    const rules = n.contestRules || {};
    const history = (n.messages || []).filter((m) => m.who !== 'system');
    const ask = ctx.price != null ? ctx.price : null;
    const rivalOffer = n.rivalLastOffer || {};
    const playerOffer = n.playerLastOffer || null;

    let claimBlock = '';
    if (typeof global.EconGameAI !== 'undefined' && global.EconGameAI.claimVerificationRules) {
      claimBlock = global.EconGameAI.claimVerificationRules(
        global.EconGameAI.portfolioFactsFromContext ? global.EconGameAI.portfolioFactsFromContext(ctx) : ''
      );
    }

    const conceded = n.rivalConceded ? 'Rival has CONCEDED — they will not bid again.' : 'Rival is still active.';
    const playerTerms = playerOffer && playerOffer.termsOffered ? playerOffer.termsOffered.join(', ') : 'none';

    return `You are simulating a THREE-WAY acquisition negotiation in Capital Farm.
SELLER: ${c.npcName || 'Seller'} (${arch.name || 'Negotiator'} — ${arch.flavor || ''}). Asking price: ${ask != null ? ask : 'n/a'}.
RIVAL BUYER: ${displayName(n.rival)} (${RIVAL.title}) — cash-only buyer, fast close. Current rival bid: ${formatMoney(rivalOffer.totalPrice)} (${conceded}).
PLAYER: local investor trying to acquire the asset.

${claimBlock}

TURN RULES (critical):
- This is turn-based. The PLAYER just spoke. Respond as SELLER and RIVAL separately.
- Seller compares FULL PACKAGES (price + cash at closing + speed + terms), not price alone.
- Rival is cash-only and cannot match employee retention, growth plans, seller notes, or earnouts.
- Player may address the seller OR the rival directly — respond appropriately.
- Do NOT ask the player to upload proof or documents.
- The game engine decides final acceptance and bid caps — you produce dialogue and structured fields only.
- Voice: dry farm-capitalism (Stardew meets Bloomberg). Lead with dollars and structure; one sharp character line max. Never cartoonish.

Current bids — Rival: ${formatMoney(rivalOffer.totalPrice)}${playerOffer ? ` · Player: ${formatMoney(playerOffer.totalPrice)} · Player terms: ${playerTerms}` : ' · Player: no bid yet'}.

Conversation:
${history.map((m) => `${String(m.who || '').toUpperCase()}: ${m.text || ''}`).join('\n')}
PLAYER: ${playerMessage || ''}

Classify PLAYER message:
- "question": dialogue, no new numeric deal terms
- "offer": player proposed specific numeric price/terms in THIS message
- "accept": player explicitly accepts terms currently on the table
- "walk": player ends the negotiation

RIVAL ACTION (if rival not conceded):
- "hold": stay at current bid
- "counter": raise bid (only if still below engine cap ~${formatMoney(rules.rivalMaxBid || ask)})
- "concede": rival drops out (when player wins on terms rival cannot match or rival is at cap)

Reply with ONLY raw JSON (no markdown):
{"sellerDialogue":"1-3 sentences in character","rivalDialogue":"1-3 sentences in character","rivalAction":"hold|counter|concede","rivalOffer":{"totalPrice":number|null,"cashAtClosing":number|null,"closingSpeed":"fast|standard|extended","termsOffered":[string]}|null,"intent":"question|offer|accept|walk","offer":{"totalPrice":number|null,"cashAtClosing":number|null,"closingSpeed":"fast|standard|extended","termsOffered":[string],"priceAdjustment":number|null,"concessionSize":number|null}}`;
  }

  function normalizeThreeWayResponse(raw, negotiation, playerMessage, helpers) {
    if (!raw || typeof raw !== 'object') {
      return engineResolveTurn(negotiation, playerMessage, null, helpers);
    }

    const normalized = {
      sellerDialogue: raw.sellerDialogue || raw.dialogue || '',
      rivalDialogue: raw.rivalDialogue || '',
      rivalAction: raw.rivalAction || 'hold',
      rivalOffer: raw.rivalOffer && typeof raw.rivalOffer === 'object' ? raw.rivalOffer : null,
      intent: raw.intent || 'question',
      offer: raw.offer && typeof raw.offer === 'object' ? raw.offer : null,
      dialogue: raw.sellerDialogue || raw.dialogue || '',
    };

    return engineResolveTurn(negotiation, playerMessage, normalized, helpers);
  }

  /** Authoritative contest resolution — overrides AI where mechanics require it. */
  function engineResolveTurn(negotiation, playerMessage, aiParsed, helpers) {
    const n = negotiation || {};
    const rules = n.contestRules || {};
    const text = playerMessage || '';
    const parsed = aiParsed || {
      sellerDialogue: '',
      rivalDialogue: '',
      rivalAction: 'hold',
      rivalOffer: null,
      intent: 'question',
      offer: null,
    };

    const built = buildPlayerOfferFromMessage(text, parsed, n, helpers);
    let intent = built.intent || parsed.intent || 'question';
    const playerOffer = built.offer;

    if (playerOffer && playerOffer.totalPrice) {
      n.playerLastOffer = playerOffer;
      n.lastOffer = playerOffer;
    }

    let playerU = -Infinity;
    let rivalU = -Infinity;
    const evalFn = helpers && helpers.evaluateUtility;
    if (playerOffer && evalFn) {
      playerU = evalFn(playerOffer, n.counterparty, n.context);
    }
    if (n.rivalLastOffer && !n.rivalConceded && evalFn) {
      rivalU = evalFn(n.rivalLastOffer, n.counterparty, n.context);
    }
    if (playerOffer && evalFn) {
      const unmatched = rivalCannotMatchTerms(playerOffer.termsOffered, rules);
      unmatched.forEach((t) => {
        playerU += 6;
        if ((rules.sellerPreferredTerms || []).some((p) => {
          const a = t.toLowerCase();
          const b = p.toLowerCase();
          return a.includes(b.split(' ')[0]) || b.includes(a.split(' ')[0]);
        })) {
          playerU += 5;
        }
      });
    }
    if (playerOffer) {
      n.leadingBidder = playerU >= rivalU ? 'player' : 'rival';
    }

    const sellerDialogue = sellerDialogueForTurn(n, playerOffer, playerU, rivalU, intent, rules, helpers);
    const rivalResp = computeRivalResponse(n, playerOffer, playerU, rivalU, text, rules);

    let rivalAction = rivalResp.action || 'hold';
    let rivalDialogue = rivalResp.dialogue || parsed.rivalDialogue || '';
    let rivalOffer = rivalResp.rivalOffer || null;

    if (rivalAction === 'counter' && rivalOffer && rivalOffer.totalPrice > rules.rivalMaxBid) {
      rivalOffer.totalPrice = rules.rivalMaxBid;
      rivalOffer.cashAtClosing = Math.round(rules.rivalMaxBid * 0.55);
    }

    if (rivalAction === 'counter' && rivalOffer && n.rivalLastOffer && rivalOffer.totalPrice <= n.rivalLastOffer.totalPrice) {
      if (playerU >= rivalU && rivalCannotMatchTerms(playerOffer && playerOffer.termsOffered, rules).length) {
        rivalAction = 'concede';
        rivalDialogue = rivalDialogue || rivalConcedeLine('terms', contestContext(n, { term: 'that package' }));
        rivalOffer = null;
      } else {
        rivalAction = 'hold';
        rivalOffer = null;
      }
    }

    if (intent === 'walk') {
      return {
        sellerDialogue: 'Understood — I will talk to the other buyer.',
        rivalDialogue: rivalWinLine(n, { reason: 'walk' }),
        rivalAction: 'hold',
        rivalOffer: null,
        intent: 'walk',
        offer: playerOffer,
        playerU,
        rivalU,
        readyToClose: false,
      };
    }

    let readyToClose = false;
    let pendingOffer = null;
    const decisionFn = helpers && helpers.negotiationDecision;
    const decision = playerOffer && decisionFn
      ? decisionFn(playerU, n.round || 1, n.maxRounds || 6)
      : (playerU >= rules.acceptUtility ? 'accept' : 'counter');

    if (intent === 'accept' && n.lastOffer && (n.leadingBidder === 'player' || n.rivalConceded)) {
      readyToClose = true;
      pendingOffer = n.lastOffer;
    } else if (playerOffer && playerU >= rivalU && decision === 'accept') {
      readyToClose = true;
      pendingOffer = playerOffer;
    }

    if (rivalAction === 'concede') {
      n.rivalConceded = true;
      if (playerOffer && playerU >= rules.acceptUtility - 4) {
        readyToClose = true;
        pendingOffer = playerOffer;
      }
    }

    return {
      sellerDialogue,
      rivalDialogue,
      rivalAction,
      rivalOffer,
      intent,
      offer: playerOffer,
      playerU,
      rivalU,
      readyToClose,
      pendingOffer,
    };
  }

  function processContestTurn(negotiation, playerMessage, aiParsed, helpers) {
    const n = negotiation;
    n.round = (n.round || 0) + 1;

    const resolved = normalizeThreeWayResponse(aiParsed, n, playerMessage, helpers);
    const rname = displayName(n.rival);
    const messages = [];
    const summarize = helpers && helpers.summarizeOffer;

    if (resolved.sellerDialogue) {
      messages.push({
        who: 'counterparty',
        text: resolved.sellerDialogue,
        offerSummary: resolved.offer && summarize ? summarize(resolved.offer) : null,
      });
    }

    if (!n.rivalConceded && resolved.rivalDialogue) {
      messages.push({ who: 'rival', text: resolved.rivalDialogue });
    }

    if (resolved.rivalAction === 'concede') {
      n.rivalConceded = true;
      messages.push({ who: 'system', text: `${rname} conceded — the seller will only consider your package now.` });
    } else if (resolved.rivalAction === 'counter' && resolved.rivalOffer && !n.rivalConceded) {
      const normalizeOfferFn = helpers && helpers.normalizeOffer;
      const ro = normalizeOfferFn ? normalizeOfferFn(resolved.rivalOffer, n) : resolved.rivalOffer;
      if (ro && ro.totalPrice) {
        n.rivalLastOffer = ro;
        messages.push({ who: 'system', text: `${rname} bid is now ${formatMoney(ro.totalPrice)}.` });
      }
    }

    if (resolved.intent === 'walk') {
      return { messages, walkAway: true, resolved };
    }

    if (resolved.readyToClose) {
      n.readyToClose = true;
      n.pendingOffer = resolved.pendingOffer;
    }

    if (n.round >= n.maxRounds && n.status === 'ongoing' && !n.readyToClose) {
      if (n.leadingBidder === 'rival' && !n.rivalConceded) {
        messages.push({ who: 'rival', text: rivalWinLine(n, { reason: 'timeout' }) });
        return { messages, rivalWins: true, resolved };
      }
      messages.push({ who: 'counterparty', text: '(Final round — best package wins.)' });
      if (n.leadingBidder === 'player' && resolved.offer) {
        n.readyToClose = true;
        n.pendingOffer = resolved.offer;
      }
    }

    return { messages, walkAway: false, rivalWins: false, resolved };
  }

  function packageCompareRow(label, playerVal, rivalVal, playerBetter) {
    const pCls = playerBetter === true ? ' pkg-better' : playerBetter === false ? ' pkg-worse' : '';
    const rCls = playerBetter === false ? ' pkg-better' : playerBetter === true ? ' pkg-worse' : '';
    return `<tr><td class="pkg-label">${label}</td><td class="pkg-you${pCls}">${playerVal || '—'}</td><td class="pkg-rival${rCls}">${rivalVal || '—'}</td></tr>`;
  }

  function renderPackageComparison(negotiation, formatMoneyFn) {
    const n = negotiation || {};
    if (!n.contestRules) return '';
    const fmtFn = formatMoneyFn || formatMoney;
    const rname = displayName(n.rival);
    const player = n.playerLastOffer;
    const rival = n.rivalConceded ? null : n.rivalLastOffer;
    const playerPrice = player && player.totalPrice;
    const rivalPrice = rival && rival.totalPrice;

    const playerTerms = (player && player.termsOffered && player.termsOffered.length)
      ? player.termsOffered.join(', ')
      : '—';
    const rivalTerms = rival && rival.termsOffered && rival.termsOffered.length
      ? rival.termsOffered.join(', ')
      : (n.rivalConceded ? 'conceded' : '—');

    let leadText = 'No bids yet';
    if (player && rival && n.leadingBidder === 'player') leadText = 'You lead on overall package';
    else if (player && rival && n.leadingBidder === 'rival') leadText = `${rname} leads on overall package`;
    else if (player && n.rivalConceded) leadText = 'You lead — rival out of bidding';
    else if (rival && !player) leadText = `${rname} opened the bidding`;

    return `<div class="contest-compare">
      <div class="contest-compare-head">Packages on the table</div>
      <table class="contest-compare-table">
        <thead><tr><th></th><th>You</th><th>${rname}</th></tr></thead>
        <tbody>
          ${packageCompareRow('Price', playerPrice != null ? fmtFn(playerPrice) : '—', rivalPrice != null ? fmtFn(rivalPrice) : '—', playerPrice != null && rivalPrice != null ? playerPrice >= rivalPrice : null)}
          ${packageCompareRow('Cash at close', player ? fmtFn(player.cashAtClosing || 0) : '—', rival ? fmtFn(rival.cashAtClosing || 0) : '—', player && rival ? (player.cashAtClosing || 0) >= (rival.cashAtClosing || 0) : null)}
          ${packageCompareRow('Closing', player ? (player.closingSpeed || '—') : '—', rival ? (rival.closingSpeed || '—') : '—', null)}
          ${packageCompareRow('Terms', playerTerms, rivalTerms, player && player.termsOffered && player.termsOffered.length && (!rival || !rival.termsOffered || !rival.termsOffered.length) ? true : null)}
        </tbody>
      </table>
      <div class="contest-compare-lead">${leadText}</div>
    </div>`;
  }

  function contestUtilities(negotiation, helpers) {
    const n = negotiation || {};
    const rules = n.contestRules || {};
    const evalFn = helpers && helpers.evaluateUtility;
    let playerU = -Infinity;
    let rivalU = -Infinity;
    if (n.playerLastOffer && evalFn) {
      playerU = evalFn(n.playerLastOffer, n.counterparty, n.context);
    }
    if (n.rivalLastOffer && !n.rivalConceded && evalFn) {
      rivalU = evalFn(n.rivalLastOffer, n.counterparty, n.context);
    }
    if (n.playerLastOffer && evalFn) {
      const unmatched = rivalCannotMatchTerms(n.playerLastOffer.termsOffered, rules);
      unmatched.forEach((t) => {
        playerU += 6;
        if ((rules.sellerPreferredTerms || []).some((p) => {
          const a = t.toLowerCase();
          const b = p.toLowerCase();
          return a.includes(b.split(' ')[0]) || b.includes(a.split(' ')[0]);
        })) {
          playerU += 5;
        }
      });
      if (unmatched.some((t) => /seller note|payment schedule|deposit/i.test(t))) {
        playerU += 4;
      }
    }
    return { playerU, rivalU };
  }

  function rivalUncontestedWinLine(opp) {
    return rivalBanter('winTimeout', {
      asset: ((opp && opp.name) || 'the listing').split('—')[0].trim(),
      price: (opp && opp.price) || 0,
    });
  }

  function contestLogLine(opp, state) {
    const short = opp.name.split('—')[0].trim();
    if (state && Math.random() < 0.35) {
      const taunt = rivalLayerTaunt(state);
      if (taunt) return `${RIVAL.name} is contesting ${short} — ${taunt}`;
    }
    return `${RIVAL.name} is contesting ${short} — three-way negotiation open (1 AP). Outbid him or lose the listing at turn end.`;
  }

  global.RivalFarmer = {
    RIVAL,
    CONTEST_INTERVAL,
    isActive,
    isContestTurn,
    scoreOpportunity,
    pickContestTarget,
    createRival,
    displayName,
    buildContestRules,
    openingOffer,
    rivalOpeningLine,
    rivalWinLine,
    rivalLoseLine,
    rivalUncontestedWinLine,
    sellerResponseToRival,
    extractPurchaseOfferFromText,
    expandMoneyShorthand,
    messageHasOfferFigures,
    extractTermsFromText,
    parseOfferAmountsFromText,
    isAllCashOfferText,
    isClosingIntentText,
    isStructuredFinancingText,
    inferOfferStructure,
    reconcileOfferAmounts,
    buildPlayerOfferFromMessage,
    applyContestToTurn,
    buildThreeWayPrompt,
    normalizeThreeWayResponse,
    processContestTurn,
    renderPackageComparison,
    contestUtilities,
    contestLogLine,
  };
})(typeof window !== 'undefined' ? window : globalThis);
