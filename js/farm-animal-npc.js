/**
 * Capital Farm — Animal NPC Negotiation addendum.
 *
 * Sits on top of the existing archetype / utility / AI negotiation stack.
 * Active when game mode has farmTheme:true (Arcade → Capital Farm).
 *
 *   <script src="js/farm-animal-npc.js"></script>
 *
 *   FarmAnimalNPC.decorateCounterparty(base, S, { orgName, role })
 *   FarmAnimalNPC.applyUtilityBonus(utility, offer, counterparty, context, S)
 *   FarmAnimalNPC.buildPrompt(negotiation, playerMessage, archetype)
 *   FarmAnimalNPC.renderIdentityStrip(counterparty)
 *   FarmAnimalNPC.speakerName(counterparty, archetypeName)
 *   FarmAnimalNPC.intelTips(counterparty)
 *   FarmAnimalNPC.recordOutcome(S, counterparty, { accepted, dealQuality })
 */
(function (global) {
  'use strict';

  const SPECIES = {
    pig: {
      id: 'pig', label: 'Pig', emoji: '🐷',
      traits: ['calculating', 'opportunistic'],
      descriptor: 'Seeks structural upside and information advantage',
      voice: 'Calculating and opportunistic. Prefer deal structure, earn-outs, exclusivity, and upside participation over pure price fights.',
      exampleVoice: 'The price can move. The question is what I receive if this business grows exactly as you claim it will.',
      concessionStyleAdj: 0,
      tips: [
        'This Pig cares about structure — earn-outs, exclusivity, or upside participation can move them more than shaving the headline price.',
        'Do not reveal desperation. They look for the clause that compounds later.',
        'Vague control rights are dangerous; keep future upside explicitly valued.',
      ],
      firstNames: ['Percival', 'Hamish', 'Truffle', 'Barnaby', 'Greta', 'Portia'],
      lastNames: ['Troughworth', 'Mudford', 'Snoutley', 'Oakpen', 'Bristle'],
    },
    donkey: {
      id: 'donkey', label: 'Donkey', emoji: '🫏',
      traits: ['stubborn', 'skeptical'],
      descriptor: 'Concedes slowly; demands evidence and precise terms',
      voice: 'Stubborn and skeptical. Assume optimistic claims are incomplete until shown evidence, warranties, or risk-sharing.',
      exampleVoice: 'You keep telling me the harvest will improve. Show me the contracts, the water rights, and the last four quarters.',
      concessionStyleAdj: -0.2,
      tips: [
        'This Donkey needs evidence — warranties, inspection rights, or verified numbers beat pressure.',
        'Small concessions after uncertainty is removed work; inconsistent claims get punished.',
        'Resistance is not irrationality. Remove risk before asking them to move price.',
      ],
      firstNames: ['Martha', 'Duncan', 'Ivy', 'Silas', 'Ned', 'Clara'],
      lastNames: ['Longstep', 'Burro', 'Stonepath', 'Hayridge', 'Stubbs'],
    },
    sheep: {
      id: 'sheep', label: 'Sheep', emoji: '🐑',
      traits: ['agreeable', 'herd_driven'],
      descriptor: 'Responds to reputation, consensus, and market mood',
      voice: 'Agreeable and herd-driven. Reputation, comparable deals, and what respected others are doing strongly shape confidence.',
      exampleVoice: 'The Horses at North Field renewed with you, didn\'t they? If they trust your delivery schedule, perhaps we can too.',
      concessionStyleAdj: 0.1,
      tips: [
        'This Sheep follows social proof — references, comparable deals, and your reputation matter.',
        'Early agreement can reverse if the wider market turns fearful.',
        'Do not assume a friendly tone means the deal is locked.',
      ],
      firstNames: ['Wooliam', 'Dolly', 'Fleecy', 'Ramsey', 'Mabel', 'Shepherd'],
      lastNames: ['Meadow', 'Softfield', 'Ewetide', 'Lambton', 'Pasture'],
    },
    goat: {
      id: 'goat', label: 'Goat', emoji: '🐐',
      traits: ['audacious', 'boundary_testing'],
      descriptor: 'Tests limits; respects firm, reciprocal packages',
      voice: 'Audacious and boundary-testing. Ask for more than expected, introduce unconventional terms, and respect disciplined resistance.',
      exampleVoice: 'Fine, keep your price. I want the eastern territory, priority loading, and the right to reopen terms after two quarters.',
      concessionStyleAdj: 0.05,
      tips: [
        'This Goat tests boundaries — concede only in exchange for something back.',
        'Firm walk-away willingness earns respect; immediate giveaways invite more demands.',
        'Package trades (one demand for another) work better than pure price cuts.',
      ],
      firstNames: ['Gideon', 'Billy', 'Capra', 'Hornace', 'Nanny', 'Ruff'],
      lastNames: ['Horn', 'Ridgeclimb', 'Boulder', 'Thicket', 'Scramble'],
    },
    horse: {
      id: 'horse', label: 'Horse', emoji: '🐴',
      traits: ['reliable', 'duty_bound'],
      descriptor: 'Values continuity, promises, and how people are treated',
      voice: 'Reliable and duty-bound. Continuity, kept promises, employee treatment, and durable relationships can outweigh a slightly better price.',
      exampleVoice: 'Before we discuss another barn, I want to know whether you kept every worker you promised to keep.',
      concessionStyleAdj: 0,
      tips: [
        'This Horse values the long-term bond — employee retention and continuity plans are real leverage.',
        'Broken promises hurt more here than almost anywhere else.',
        'Purely transactional language underperforms versus reliability and legacy care.',
      ],
      firstNames: ['Clara', 'Bridle', 'Chester', 'Maggie', 'Duke', 'Ada'],
      lastNames: ['Bridle', 'Northfield', 'Stableworth', 'Gallop', 'Harness'],
    },
    hen: {
      id: 'hen', label: 'Hen', emoji: '🐔',
      traits: ['cautious', 'detail_oriented'],
      descriptor: 'Prioritizes cash certainty, schedules, and downside protection',
      voice: 'Cautious and detail-oriented. Prefer cash certainty, milestones, deposits, schedules, and clear default remedies over broad promises.',
      exampleVoice: 'I am less interested in your vision than in the payment calendar, the inspection window, and what happens if quarter two misses.',
      concessionStyleAdj: -0.1,
      tips: [
        'This Hen wants measurable safeguards — deposits, milestones, and clear schedules.',
        'Cash at closing and downside protection move them more than visionary pitches.',
        'Open-ended risk is a hard sell; stage the commitment.',
      ],
      firstNames: ['Henrietta', 'Cluck', 'Peck', 'Rosie', 'Nestoria', 'Gilda'],
      lastNames: ['Cluckwell', 'Nestworth', 'Barnyard', 'Scratch', 'Comb'],
    },
  };

  function isActive(modeOrState) {
    const mode = typeof modeOrState === 'string'
      ? modeOrState
      : (modeOrState && modeOrState.mode);
    // Arcade / Capital Farm
    return mode === 'arcade';
  }

  function pick(arr) {
    return arr[Math.floor(Math.random() * arr.length)];
  }

  function clamp(v, a, b) {
    return Math.max(a, Math.min(b, v));
  }

  function rnd(min, max) {
    return min + Math.random() * (max - min);
  }

  function generateName(speciesId) {
    const sp = SPECIES[speciesId];
    return `${pick(sp.firstNames)} ${pick(sp.lastNames)}`;
  }

  function adjustConcessionStyle(style, adj) {
    const order = ['slow', 'medium', 'fast'];
    let idx = order.indexOf(style);
    if (idx < 0) idx = 1;
    if (adj <= -0.15) idx = Math.max(0, idx - 1);
    else if (adj >= 0.1) idx = Math.min(2, idx + 1);
    return order[idx];
  }

  function defaultMemory(trust) {
    return {
      promisesKept: 0,
      promisesBroken: 0,
      lastDealQuality: null,
      grievances: [],
      trust: trust != null ? trust : 0.5,
      reliability: 0.5,
      encounters: 0,
    };
  }

  /**
   * Layer species + name + memory + leverage onto an existing counterparty object.
   * No-op if farm theme is inactive.
   */
  function decorateCounterparty(base, state, opts) {
    opts = opts || {};
    if (!isActive(state) || !base) return base;

    // Recurring NPC reuse
    if (opts.reuse && opts.reuse.speciesId && opts.reuse.npcName) {
      const memoryKey = opts.reuse.memoryKey || `${opts.reuse.speciesId}:${opts.reuse.npcName}`;
      if (!state.npcMemory) state.npcMemory = {};
      const mem = state.npcMemory[memoryKey] || defaultMemory(base.trust);
      const sp = SPECIES[opts.reuse.speciesId] || SPECIES.pig;
      return Object.assign({}, base, {
        speciesId: sp.id,
        speciesTraits: sp.traits.slice(),
        npcName: opts.reuse.npcName,
        memoryKey,
        leverage: opts.reuse.leverage != null ? opts.reuse.leverage : clamp(0.45 + rnd(-0.1, 0.2), 0.2, 0.9),
        relationshipMemory: Object.assign({}, mem),
        orgName: opts.orgName || opts.reuse.orgName || null,
        concessionStyle: adjustConcessionStyle(base.concessionStyle, sp.concessionStyleAdj),
        trust: clamp((base.trust + (mem.trust - 0.5) * 0.4), 0.1, 0.95),
      });
    }

    const speciesId = opts.speciesId || pick(Object.keys(SPECIES));
    const sp = SPECIES[speciesId];
    const npcName = opts.npcName || generateName(speciesId);
    const memoryKey = `${speciesId}:${npcName}`;
    if (!state.npcMemory) state.npcMemory = {};
    const mem = state.npcMemory[memoryKey] || defaultMemory(base.trust);
    state.npcMemory[memoryKey] = mem;

    const leverage = clamp(
      0.4 + rnd(-0.12, 0.22) + (base.urgency || 0.3) * 0.25 - (base.trust || 0.4) * 0.1,
      0.15,
      0.92
    );

    return Object.assign({}, base, {
      speciesId: sp.id,
      speciesTraits: sp.traits.slice(),
      npcName,
      memoryKey,
      leverage,
      relationshipMemory: Object.assign({}, mem),
      orgName: opts.orgName || null,
      concessionStyle: adjustConcessionStyle(base.concessionStyle, sp.concessionStyleAdj),
      trust: clamp(base.trust + (speciesId === 'sheep' ? 0.05 : 0) + (mem.trust - 0.5) * 0.3, 0.1, 0.95),
    });
  }

  /** Snapshot for attaching to a business so the same client/supplier can recur. */
  function snapshotNpc(cp) {
    if (!cp || !cp.speciesId) return null;
    return {
      speciesId: cp.speciesId,
      npcName: cp.npcName,
      memoryKey: cp.memoryKey,
      leverage: cp.leverage,
      orgName: cp.orgName || null,
      archetypeId: cp.archetypeId,
    };
  }

  function termHit(terms, re) {
    return (terms || []).some((t) => re.test(String(t).toLowerCase()));
  }

  /**
   * Capped species + relationship bonus (−15…+15) applied after base utility.
   */
  function applyUtilityBonus(utility, offer, counterparty, context, state) {
    if (!counterparty || !counterparty.speciesId) return utility;
    const sp = SPECIES[counterparty.speciesId];
    if (!sp) return utility;

    let bonus = 0;
    const terms = offer && offer.termsOffered ? offer.termsOffered : [];
    const totalPrice = (offer && offer.totalPrice) || 0;
    const cashAtClosing = (offer && offer.cashAtClosing) != null ? offer.cashAtClosing : totalPrice;
    const certainty = cashAtClosing / Math.max(1, totalPrice || 1);

    switch (sp.id) {
      case 'pig':
        if (termHit(terms, /earn.?out|contingent|exclusiv|option|information|upside|royalt/)) bonus += 8;
        if (termHit(terms, /control|governance|renewal/)) bonus += 4;
        break;
      case 'donkey':
        if (termHit(terms, /warrant|inspect|guarantee|trial|retention|verified|diligence/)) bonus += 8;
        if (context && context.diligenceDone) bonus += 4;
        if (counterparty.concessionStyle === 'slow') bonus += 1;
        break;
      case 'sheep': {
        const rep = state && state.reputation != null ? state.reputation : 50;
        bonus += clamp((rep - 50) / 50, -1, 1) * 8;
        if (termHit(terms, /reference|reputation|partner|renew|community/)) bonus += 5;
        const conf = state && state.marketState && state.marketState.businessConfidence;
        if (conf === 'expansion') bonus += 3;
        if (conf === 'contraction') bonus -= 4;
        break;
      }
      case 'goat':
        if (terms.length >= 2) bonus += 5;
        if (termHit(terms, /territor|priority|reopen|option package/)) bonus += 5;
        // Rewards packages; mild penalty for empty soft offers
        if (!terms.length && offer && offer.totalPrice && context && context.price) {
          const cut = (context.price - offer.totalPrice) / context.price;
          if (cut > 0.12) bonus -= 4;
        }
        break;
      case 'horse': {
        if (termHit(terms, /employee|staff|continu|long.?term|legacy|worker|retention/)) bonus += 9;
        const mem = counterparty.relationshipMemory || {};
        bonus += (mem.promisesKept || 0) * 2.5;
        bonus -= (mem.promisesBroken || 0) * 6;
        break;
      }
      case 'hen':
        bonus += certainty * 8;
        if (termHit(terms, /milestone|deposit|escrow|schedule|guarantee|coverage|collateral/)) bonus += 6;
        if (offer && offer.closingSpeed === 'fast') bonus += 3;
        if (offer && offer.closingSpeed === 'extended') bonus -= 3;
        break;
      default:
        break;
    }

    const mem = counterparty.relationshipMemory || {};
    bonus += clamp((mem.trust != null ? mem.trust : 0.5) - 0.5, -0.35, 0.35) * 18;
    if (mem.lastDealQuality != null) bonus += clamp((mem.lastDealQuality - 55) / 45, -1, 1) * 5;
    bonus -= (mem.grievances ? mem.grievances.length : 0) * 5;

    // Leverage: high-leverage NPCs need more to be happy
    if (counterparty.leverage != null) {
      bonus -= (counterparty.leverage - 0.5) * 10;
    }

    bonus = clamp(bonus, -15, 15);
    return utility + bonus;
  }

  function buildPrompt(negotiation, playerMessage, archetype) {
    const c = negotiation.counterparty || {};
    const arch = archetype || {};
    const history = (negotiation.messages || []).filter((m) => m.who !== 'system');
    const price = negotiation.context && negotiation.context.price != null
      ? negotiation.context.price
      : null;
    const preferred = Array.isArray(c.preferredTerms) ? c.preferredTerms.join(', ') : '';
    const sp = c.speciesId ? SPECIES[c.speciesId] : null;
    const mem = c.relationshipMemory || {};
    const diligence = negotiation.context && negotiation.context.diligenceDone;
    const hiddenLine = diligence
      ? `You may allude carefully to this private fact if relevant (never dump it unprompted): ${c.hiddenInfo || 'none'}.`
      : `You have private knowledge you must NOT reveal unless the player has clearly investigated or asked a precise discovery question that earns it: ${c.hiddenInfo || 'none'}.`;

    const speciesBlock = sp
      ? `Species: ${sp.label} (${sp.traits.join(', ')}).
Species voice: ${sp.voice}
Example tone: "${sp.exampleVoice}"
Stay in this animal-character business voice: dry farm-capitalism wit (Stardew meets Bloomberg). Lead with numbers and stakes; one sharp line of personality is enough — never cartoonish, never break the fourth wall.`
      : `Personality: ${arch.name || 'Negotiator'} (${arch.flavor || ''}).`;

    const memoryBlock = `Relationship memory — trust ${((mem.trust != null ? mem.trust : 0.5) * 100).toFixed(0)}%, promises kept ${mem.promisesKept || 0}, promises broken ${mem.promisesBroken || 0}, last deal quality ${mem.lastDealQuality != null ? mem.lastDealQuality : 'n/a'}, grievances: ${(mem.grievances && mem.grievances.length) ? mem.grievances.join('; ') : 'none'}.`;

    const ctx = negotiation.context || {};
    const opp = ctx.opp || {};
    const listing = ctx.listingEconomics || {};
    const ask = ctx.price != null ? ctx.price : listing.askingPrice;
    const rev = listing.quarterlyRevenue != null ? listing.quarterlyRevenue : opp.revenue;
    const marginPct = listing.marginPct != null ? listing.marginPct : (opp.margin != null ? Math.round(opp.margin * 100) : null);
    const listingBlock = ask != null ? `
LISTING ECONOMICS (critical — do NOT confuse with the player's purchase offer):
- Asking price = total purchase price seller wants for the asset: ${ask}
${rev != null ? `- Quarterly revenue = operating income per quarter (NOT a purchase price): ${rev}/qtr` : ''}
${marginPct != null ? `- Estimated margin = profit margin on revenue (NOT a purchase price): ${marginPct}%` : ''}
When the player cites revenue, margin, or maintenance to argue, that is rhetoric — NOT an offer to buy at the revenue figure.
Only use intent "offer" when the player states what they will PAY to acquire the asset. Never put revenue in offer.totalPrice.
You provide dialogue and JSON fields only — the game engine decides acceptance. If unsure, use intent "question".` : '';
    const claimBlock = (typeof global.EconGameAI !== 'undefined' && global.EconGameAI.claimVerificationRules)
      ? global.EconGameAI.claimVerificationRules(
          typeof global.EconGameAI.portfolioFactsFromContext === 'function'
            ? global.EconGameAI.portfolioFactsFromContext(ctx)
            : (ctx.portfolioFacts || '')
        )
      : '';

    return `You are role-playing a counterparty in Capital Farm — a turn-based farm economy where animals negotiate like serious businesspeople.
Name: ${c.npcName || 'Counterparty'}. Role: ${c.role || 'counterparty'}. Situational archetype: ${arch.name || 'Negotiator'} (${arch.flavor || ''}).
${speciesBlock}
${listingBlock}
${price != null ? `Asking/reference price: ${price}.` : ''}
Urgency: ${c.urgency != null ? c.urgency : 0.4}. Trust: ${c.trust != null ? c.trust : 0.45}. Leverage: ${c.leverage != null ? c.leverage : 0.5}. Risk tolerance: ${c.riskTolerance != null ? c.riskTolerance : 0.3}.
You respond to: ${preferred}.
${hiddenLine}
${memoryBlock}
${claimBlock}
Voice: farm-capitalism — concrete dollars, schedules, and leverage first; one dry character beat second. Be concise (1-3 sentences). Never break the fourth wall, never reveal you are an AI, and never invent money, assets, or final deal authority — the game engine decides acceptance.
Conversation so far:
${history.map((m) => `${String(m.who || '').toUpperCase()}: ${m.text || ''}`).join('\n')}
PLAYER: ${playerMessage || ''}

Classify the PLAYER's latest message carefully:
- "question": they asked something, made small talk, or said anything that is not a concrete numeric proposal or explicit agreement. This is the default — most messages are this.
- "offer": ONLY if the player explicitly proposed specific numeric terms (a price, a split, a percentage) in this message.
- "accept": ONLY if the player explicitly agreed to accept the specific terms currently on the table.
- "walk": ONLY if the player explicitly said they are ending the negotiation.
Never invent numbers the player did not say. If intent is "question", every field inside "offer" must be null and termsOffered must be [].

Reply with ONLY a raw JSON object (no markdown fences, no extra text) matching exactly:
{"dialogue": "in-character reply, 1-3 sentences", "intent": "question|offer|accept|walk", "offer": {"totalPrice": number|null, "cashAtClosing": number|null, "closingSpeed": "fast|standard|extended", "termsOffered": [string], "priceAdjustment": number|null, "concessionSize": number|null}}`;
  }

  function renderIdentityStrip(counterparty, archetype) {
    if (!counterparty || !counterparty.speciesId) return '';
    const sp = SPECIES[counterparty.speciesId];
    if (!sp) return '';
    const mem = counterparty.relationshipMemory || {};
    const arch = archetype || {};
    const relBits = [];
    if (mem.encounters > 0) relBits.push(`${mem.encounters} prior meeting${mem.encounters > 1 ? 's' : ''}`);
    if (mem.promisesKept) relBits.push(`${mem.promisesKept} promise${mem.promisesKept > 1 ? 's' : ''} kept`);
    if (mem.promisesBroken) relBits.push(`${mem.promisesBroken} broken`);
    if (mem.grievances && mem.grievances.length) relBits.push('open grievance');
    if (mem.lastDealQuality != null) relBits.push(`last deal ${mem.lastDealQuality}/100`);
    const rel = relBits.length ? relBits.join(' · ') : 'New acquaintance';
    const archLine = arch.name
      ? `<div class="npc-arch">${arch.name}${arch.flavor ? ' · ' + arch.flavor : ''}</div>`
      : '';
    return `<div class="npc-identity">
      <div class="npc-identity-main">
        <span class="npc-emoji" aria-hidden="true">${sp.emoji}</span>
        <div>
          <div class="npc-name">${counterparty.npcName || sp.label}</div>
          <div class="npc-meta">${sp.label} · ${(counterparty.speciesTraits || sp.traits).join(' / ')} · ${counterparty.role || 'counterparty'}${counterparty.orgName ? ' · ' + counterparty.orgName : ''}</div>
          <div class="npc-desc">${sp.descriptor}</div>
          ${archLine}
        </div>
      </div>
      <div class="npc-rel">${rel}</div>
    </div>`;
  }

  function speakerName(counterparty, archetypeName) {
    if (counterparty && counterparty.npcName) return counterparty.npcName;
    return archetypeName || 'Counterparty';
  }

  function intelTips(counterparty) {
    if (!counterparty || !counterparty.speciesId) return [];
    const sp = SPECIES[counterparty.speciesId];
    return sp ? sp.tips.slice() : [];
  }

  /** Farm-absurd urgent problem copy — stakes in $, punchline in barnyard capitalism. */
  function layerFlavorSuffix(state) {
    if (!state || typeof global.FarmSupplyChain === 'undefined') return '';
    const dom = global.FarmSupplyChain.dominantLayer(state);
    if (!dom || !dom.layer || dom.count < 2 || Math.random() > 0.38) return '';
    const lines = {
      infrastructure: [
        'Your repair-shed empire does not fix relationship math.',
        'Cold storage is nice — this invoice still has a due date.',
      ],
      consumer_channel: [
        'Storefront margins are pretty until the supplier shows up angry.',
        'The restaurant line is out the door; this supplier line is out of patience.',
      ],
      primary_production: [
        'Lot of acres on your card — this supplier still wants cash this quarter.',
        'Weather hedges do not pay feed bills on their own.',
      ],
      processing: [
        'Feed mills process grain, not excuses.',
        'Spread operators still negotiate like everyone else.',
      ],
    };
    const pool = lines[dom.layer];
    return pool && pool.length ? ` ${pick(pool)}` : '';
  }

  function urgentProblemText(type, opts) {
    opts = opts || {};
    const biz = opts.businessName || 'the operation';
    const npc = opts.npcName || 'Your counterparty';
    const stake = opts.stakeAmount != null ? opts.stakeAmount : 0;
    const fmt = opts.formatMoney || ((n) => '$' + Math.round(n).toLocaleString());
    const state = opts.escalation || 'strained';
    const layerSuffix = opts.gameState ? layerFlavorSuffix(opts.gameState) : '';

    if (type === 'client') {
      if (state === 'at_risk') {
        return pick([
          `${npc} says ${biz}'s biggest account is packing feed bags elsewhere — ${fmt(stake)}/qtr walks if you don't renegotiate now.`,
          `Your top client at ${biz} is one signature from leaving. That's ${fmt(stake)}/qtr off the ledger, permanently, if this blows over.`,
        ]) + layerSuffix;
      }
      return pick([
        `${npc} at ${biz} wants new terms — margins are thin and they're shopping around (${fmt(stake)}/qtr on the line).`,
        `${biz}'s anchor client is grumbling about price. Fix it before ${npc} forwards the invoice to a competitor.`,
      ]) + layerSuffix;
    }
    if (type === 'supplier') {
      if (state === 'at_risk') {
        return pick([
          `${npc} is done eating the cost — ${biz}'s input bill jumps ${fmt(stake)}/qtr unless you talk them down today.`,
          `Critical supplier for ${biz} is imposing a lasting hike. ${fmt(stake)}/qtr extra opex if you ignore ${npc}.`,
        ]) + layerSuffix;
      }
      return pick([
        `${npc} says hay doesn't grow on goodwill — ${biz} faces a ${fmt(stake)}/qtr cost bump unless terms change.`,
        `Your ${biz} supplier wants more per load. ${npc} has spreadsheets and they're not sentimental.`,
      ]) + layerSuffix;
    }
    if (type === 'lender') {
      return pick([
        `${npc} flagged coverage on your loan — covenant chat now or ${fmt(stake)}/qtr higher payments later.`,
        `The bank (${npc}) wants reassurance on collateral. Ignore it and the payment ratchets up ~${fmt(stake)}/qtr.`,
      ]) + layerSuffix;
    }
    return `${biz}: relationship issue needs negotiation.${layerSuffix}`;
  }

  /** Seller opening tuned to species + stakes tier. */
  function sellerOpeningLine(counterparty, context, archetype) {
    context = context || {};
    archetype = archetype || {};
    const price = context.price != null ? context.price : (context.opp && context.opp.price);
    const fmt = context.formatMoney || ((n) => '$' + Math.round(n).toLocaleString());
    const tier = context.stakesTier || 'standard';
    const sp = counterparty && counterparty.speciesId ? SPECIES[counterparty.speciesId] : null;
    const ask = price != null ? fmt(price) : 'my number';

    let cores;
    if (tier === 'small') {
      cores = [
        `Asking ${ask} — small deal, clean close if the math works.`,
        `${ask} on the sign. I'm not here for a three-act drama.`,
      ];
    } else if (tier === 'major' || tier === 'institutional') {
      cores = [
        `${ask} is the headline — we'll need structure, proof, and patience before anyone signs.`,
        `This is a ${ask} transaction. Expect diligence, not handshake poetry.`,
      ];
    } else {
      cores = [
        `I'm asking ${ask}. Solid asset — I'll listen if your terms are serious.`,
        `${ask} on the table. I'd rather close cleanly than negotiate forever.`,
      ];
    }

    let line = pick(cores);
    const speciesLead = {
      hen: 'Show me the payment calendar, not the vision deck.',
      donkey: 'I want the paperwork before the poetry.',
      horse: 'Tell me what happens to the crew after close.',
      pig: 'Simple terms, fast close — that is how we both eat.',
      sheep: 'Others in the valley are watching how this one prices.',
      goat: 'I move fast — do not waste the turn.',
    };
    if (sp && speciesLead[sp.id] && Math.random() < 0.75) {
      line = `${speciesLead[sp.id]} ${line}`;
    }

    if (archetype.flavor && Math.random() < 0.35) {
      line = `${line} (${archetype.name}: ${archetype.flavor})`;
    }
    return line;
  }

  /** Client / supplier / lender openers for urgent relationship negotiations. */
  function relationshipOpeningLine(counterparty, context) {
    context = context || {};
    const role = (counterparty && counterparty.role) || 'client';
    const sp = counterparty && counterparty.speciesId ? SPECIES[counterparty.speciesId] : null;
    const lines = {
      client: [
        'We need to talk terms — someone else quoted us faster delivery and a kinder invoice.',
        'I will be direct: the current deal is bleeding margin on our side.',
        'Your account is important, but my board reads spreadsheets, not loyalty speeches.',
      ],
      supplier: [
        'Input costs moved — we need to revisit price or volume, today.',
        'I like working with you, but diesel and feed do not discount themselves.',
        'New terms or we ration shipments. Your call before the quarter closes.',
      ],
      lender: [
        'Coverage ratios caught our eye — let us fix this before the covenant letter goes out.',
        'The file is fine until it is not. We should talk collateral and payment schedule.',
        'Internal risk wants a conversation. Better here than after a payment miss.',
      ],
    };
    let line = pick(lines[role] || lines.client);
    if (sp && Math.random() < 0.5) {
      const flavor = sp.exampleVoice;
      if (flavor) line = `${flavor} ${line}`;
    }
    return line;
  }

  function fallbackDialogueFarm(decision, counterparty) {
    const sp = counterparty && counterparty.speciesId ? SPECIES[counterparty.speciesId] : null;
    if (decision === 'accept') {
      return pick([
        'Numbers work — paperwork time.',
        'Fine. My accountant will pretend to be surprised.',
        'Accepted. Do not make me regret the barnyard handshake.',
      ]);
    }
    if (decision === 'reject') return pick(['I appreciate the offer, but', 'Not at those terms —', 'That does not clear my bar —']);
    if (decision === 'counter') {
      return pick([
        'I hear you, but I need something closer to my side of the ledger.',
        'Closer on price or structure — I am not moving on faith alone.',
        'You are in the ballpark; sharpen the terms.',
      ]);
    }
    if (sp && sp.id === 'donkey') return 'Show me evidence, then we will talk price.';
    if (sp && sp.id === 'hen') return 'Give me the numbers — schedule, cash, downside.';
    return 'Go on — but keep it concrete.';
  }

  function speciesOpeningFlavor(counterparty) {
    if (!counterparty || !counterparty.speciesId) return null;
    const sp = SPECIES[counterparty.speciesId];
    return sp ? sp.exampleVoice : null;
  }

  /** One-line callback when this NPC was met before — used in openingLine. */
  function callbackLine(counterparty, context) {
    context = context || {};
    if (!counterparty || !counterparty.speciesId) return null;
    const mem = counterparty.relationshipMemory || {};
    if (!mem.encounters || mem.encounters <= 0) return null;

    const role = counterparty.role || 'counterparty';
    const name = counterparty.npcName || 'You';
    const q = mem.lastDealQuality;

    if (mem.promisesBroken > 0 && mem.grievances && mem.grievances.length) {
      return `${name} remembers the last round ended badly — trust is lower this time.`;
    }
    if (q != null && q >= 75) {
      if (role === 'client') return `${name} nods — last time you held the line without burning the relationship.`;
      if (role === 'supplier') return `${name} recalls you paid on schedule last quarter; that buys you a hearing.`;
      if (role === 'lender') return `${name} notes your last covenant discussion was professional — coverage still matters.`;
      return `${name} remembers closing cleanly with you before (deal quality ~${q}/100).`;
    }
    if (q != null && q < 55) {
      return `${name} is wary — the last negotiation with you felt rough.`;
    }
    if (mem.encounters >= 2) {
      if (role === 'client') return `${name} is back — same account, new terms to settle.`;
      if (role === 'supplier') return `${name} again — input costs have not gotten easier since you last talked.`;
      if (role === 'lender') return `${name} is reviewing your file again; prior quarters are on the record.`;
    }
    if (context.price != null) {
      return `${name} has dealt with you once before — they know your style.`;
    }
    return `${name} recognizes you from a prior deal.`;
  }

  function recordOutcome(state, counterparty, outcome) {
    if (!state || !counterparty || !counterparty.memoryKey) return;
    if (!state.npcMemory) state.npcMemory = {};
    const mem = state.npcMemory[counterparty.memoryKey] || defaultMemory(counterparty.trust);
    mem.encounters = (mem.encounters || 0) + 1;
    if (counterparty.role) mem.lastRole = counterparty.role;
    if (outcome && outcome.accepted) {
      mem.promisesKept = (mem.promisesKept || 0) + 1;
      mem.trust = clamp((mem.trust || 0.5) + 0.08, 0.1, 0.95);
      mem.reliability = clamp((mem.reliability || 0.5) + 0.06, 0.1, 0.95);
      if (outcome.dealQuality != null) mem.lastDealQuality = outcome.dealQuality;
      if (outcome.dealQuality != null && outcome.dealQuality >= 70) {
        mem.grievances = [];
      }
    } else {
      mem.trust = clamp((mem.trust || 0.5) - 0.04, 0.1, 0.95);
      if (outcome && outcome.grievance) {
        mem.grievances = (mem.grievances || []).concat([outcome.grievance]).slice(-3);
        mem.promisesBroken = (mem.promisesBroken || 0) + 1;
      }
      if (outcome && outcome.dealQuality != null) mem.lastDealQuality = outcome.dealQuality;
    }
    state.npcMemory[counterparty.memoryKey] = mem;
    counterparty.relationshipMemory = Object.assign({}, mem);
  }

  global.FarmAnimalNPC = {
    SPECIES,
    isActive,
    decorateCounterparty,
    snapshotNpc,
    applyUtilityBonus,
    buildPrompt,
    renderIdentityStrip,
    speakerName,
    intelTips,
    urgentProblemText,
    sellerOpeningLine,
    relationshipOpeningLine,
    fallbackDialogueFarm,
    speciesOpeningFlavor,
    callbackLine,
    recordOutcome,
  };
})(typeof window !== 'undefined' ? window : globalThis);
