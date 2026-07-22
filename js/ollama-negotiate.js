/**
 * EconGame shared Ollama negotiation client.
 *
 * Drop into any MVP HTML with:
 *   <script src="js/ollama-negotiate.js"></script>
 *
 * Then:
 *   EconGameAI.begin(negotiation, () => render());
 *   await EconGameAI.negotiate(negotiation, playerMessage, { archetype });
 *   EconGameAI.noteOffline(negotiation); // on catch / fallback
 *
 * Run the game + proxy together:
 *   npm start   (from repo root)
 *   open http://127.0.0.1:8787/
 *
 * Or run ai-proxy only and open the HTML via that URL (not file://).
 */
(function (global) {
  'use strict';

  const FALLBACK_PROXY = 'http://127.0.0.1:8787';
  const OFFLINE_NOTE = 'AI offline — using basic replies. Start with: npm start, then open http://127.0.0.1:8787/';
  const NEGOTIATE_TIMEOUT_MS = 60000;
  const HEALTH_TIMEOUT_MS = 2500;

  /** Same-origin when served by ai-proxy; localhost:8787 when opened as file:// */
  function getProxyUrl() {
    if (global.ECON_GAME_PROXY_URL) return global.ECON_GAME_PROXY_URL;
    if (typeof location !== 'undefined') {
      const origin = location.origin;
      if (origin && origin !== 'null' && !origin.startsWith('file:')) return origin;
    }
    return FALLBACK_PROXY;
  }

  function noteOffline(negotiation) {
    if (!negotiation || negotiation.aiOfflineNoted) return;
    negotiation.aiOfflineNoted = true;
    negotiation.aiStatus = 'offline';
    if (!Array.isArray(negotiation.messages)) negotiation.messages = [];
    negotiation.messages.push({ who: 'system', text: OFFLINE_NOTE });
  }

  async function checkHealth(negotiation, onUpdate) {
    if (negotiation) {
      negotiation.aiStatus = 'checking';
      negotiation.aiModel = null;
    }
    if (typeof onUpdate === 'function') onUpdate(negotiation);
    try {
      const res = await fetch(`${getProxyUrl()}/health`, {
        signal: AbortSignal.timeout(HEALTH_TIMEOUT_MS),
      });
      const data = await res.json().catch(() => ({}));
      if (res.ok && data.ok) {
        if (negotiation) {
          negotiation.aiStatus = 'online';
          negotiation.aiModel = data.model || null;
          negotiation.aiOfflineNoted = false;
        }
      } else {
        noteOffline(negotiation);
      }
    } catch (_) {
      noteOffline(negotiation);
    }
    if (typeof onUpdate === 'function') onUpdate(negotiation);
  }

  /** Mark negotiation for AI use and kick off an early /health check. */
  function begin(negotiation, onUpdate) {
    if (!negotiation) return negotiation;
    negotiation.aiOfflineNoted = false;
    negotiation.aiStatus = 'checking';
    checkHealth(negotiation, onUpdate);
    return negotiation;
  }

  /**
   * Rules for how NPCs handle player factual claims.
   * @param {string} portfolioFactsBlock — multi-line verified in-game state
   */
  function claimVerificationRules(portfolioFactsBlock) {
    const facts = portfolioFactsBlock && String(portfolioFactsBlock).trim()
      ? `VERIFIED IN-GAME FACTS (sole source of truth for portfolio / asset claims):\n${portfolioFactsBlock.trim()}\n`
      : 'VERIFIED IN-GAME FACTS: not provided — treat specific portfolio or asset ownership claims as unverified.\n';

    return `${facts}CLAIM HANDLING (critical — follow exactly):
- The player CANNOT upload documents, spreadsheets, screenshots, or proof. NEVER ask them to "show records," "provide demonstrable results," "send documentation," or "prove it with numbers" unless those numbers already appear in VERIFIED IN-GAME FACTS above.
- OFF-GAME / ROLEPLAY claims (years of management experience, prior career, industry background, personal work ethic, relationships outside this run, general business acumen): if the player asserts them, treat as true for dialogue. You may react in character (skepticism, respect, etc.) but do NOT demand evidence or refuse to proceed until proof is shown.
- IN-GAME claims (owns specific farms/businesses/properties, current cash or debt, portfolio scale, supply-chain control, "I already own every vegetable farm"): ONLY treat as true if consistent with VERIFIED IN-GAME FACTS. If the player exaggerates or lies about in-game assets, challenge in character — reference what you actually know of their position. Do not ask them to produce proof; simply disbelieve or push back on false in-game boasts.
- This rule governs factual assertions, not price haggling. Numeric offers and counter-offers follow normal negotiation.`;
  }

  function formatPortfolioFacts(facts) {
    if (!facts || typeof facts !== 'object') return '';
    const lines = [];
    if (facts.cash != null) lines.push(`Cash: ${facts.cash}`);
    if (facts.reputation != null) lines.push(`Reputation: ${facts.reputation}`);
    if (facts.netWorth != null) lines.push(`Net worth: ${facts.netWorth}`);
    if (facts.dealAsset) lines.push(`Asset under negotiation: ${facts.dealAsset}`);
    if (facts.businesses && facts.businesses.length) {
      lines.push(`Owned businesses (${facts.businesses.length}): ${facts.businesses.join('; ')}`);
    } else {
      lines.push('Owned businesses: none');
    }
    if (facts.realEstate && facts.realEstate.length) {
      lines.push(`Owned properties (${facts.realEstate.length}): ${facts.realEstate.join('; ')}`);
    } else {
      lines.push('Owned properties: none');
    }
    if (facts.templateIds && facts.templateIds.length) {
      lines.push(`Owned asset types (for chain claims): ${facts.templateIds.join(', ')}`);
    }
    return lines.join('\n');
  }

  function portfolioFactsFromContext(context) {
    if (!context) return '';
    if (typeof context.portfolioFacts === 'string') return context.portfolioFacts;
    return formatPortfolioFacts(context.portfolioFacts);
  }

  function buildDefaultPrompt(negotiation, playerMessage, archetype) {
    const c = negotiation.counterparty || {};
    const arch = archetype || {};
    const history = (negotiation.messages || []).filter((m) => m.who !== 'system');
    const price = negotiation.context && negotiation.context.price != null
      ? negotiation.context.price
      : null;
    const preferred = Array.isArray(c.preferredTerms) ? c.preferredTerms.join(', ') : '';
    const claimBlock = claimVerificationRules(portfolioFactsFromContext(negotiation.context));
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

    return `You are role-playing a counterparty in a business negotiation game.
Role: ${c.role || 'counterparty'}. Personality: ${arch.name || 'Negotiator'} (${arch.flavor || ''}).
${listingBlock}
${price != null ? `Asking/reference price: ${price}.` : ''}
You privately know (do not state outright unless it becomes relevant): ${c.hiddenInfo || ''}.
You respond to: ${preferred}.
${claimBlock}
Stay in character, be concise (1-3 sentences), never break the fourth wall, never reveal you are an AI.
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

  /**
   * POST /negotiate via local proxy → Ollama.
   */
  async function negotiate(negotiation, playerMessage, opts) {
    opts = opts || {};
    const archetype = opts.archetype || {};
    const prompt = typeof opts.buildPrompt === 'function'
      ? opts.buildPrompt(negotiation, playerMessage, archetype)
      : buildDefaultPrompt(negotiation, playerMessage, archetype);

    const res = await fetch(`${getProxyUrl()}/negotiate`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      signal: AbortSignal.timeout(NEGOTIATE_TIMEOUT_MS),
      body: JSON.stringify({ prompt }),
    });
    const data = await res.json().catch(() => ({}));
    if (!res.ok) throw new Error(data.error || `AI proxy ${res.status}`);
    if (!data || (data.dialogue == null && !data.intent)) {
      throw new Error('Empty AI reply');
    }
    if (negotiation) {
      negotiation.aiStatus = 'online';
      negotiation.aiOfflineNoted = false;
    }
    return data;
  }

  function speakerLabel(who, npcName) {
    if (who === 'player') return 'You';
    if (who === 'system') return 'System';
    return npcName || 'Counterparty';
  }

  function messageClass(who) {
    return who === 'system' ? 'system' : who;
  }

  function statusLabel(negotiation) {
    const st = negotiation && negotiation.aiStatus;
    if (st === 'online') {
      const model = negotiation.aiModel ? ` · ${negotiation.aiModel}` : '';
      return { text: `AI online${model}`, cls: 'ai-online' };
    }
    if (st === 'checking') return { text: 'AI connecting…', cls: 'ai-checking' };
    return { text: 'AI offline — basic replies', cls: 'ai-offline' };
  }

  global.EconGameAI = {
    FALLBACK_PROXY,
    OFFLINE_NOTE,
    getProxyUrl,
    noteOffline,
    checkHealth,
    begin,
    negotiate,
    buildDefaultPrompt,
    claimVerificationRules,
    formatPortfolioFacts,
    portfolioFactsFromContext,
    speakerLabel,
    messageClass,
    statusLabel,
  };
})(typeof window !== 'undefined' ? window : globalThis);
