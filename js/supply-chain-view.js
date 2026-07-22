/**
 * Capital Farm — interactive supply chain diagram for MVP dashboard.
 * Requires FarmSupplyChain on window.
 */
(function (global) {
  'use strict';

  const F = () => global.FarmSupplyChain;
  const U = () => global.BusinessUpgrades;

  function upgradesActive(state) {
    return !!(state && U() && U().isActive(state));
  }

  function portfolioBizForTemplate(state, templateId) {
    return (state.portfolio.businesses || []).find((b) => b.templateId === templateId) || null;
  }

  function renderLeverStripHtml(node, attrsPrefix) {
    if (!node || !U()) return '';
    const prefix = attrsPrefix || 'data-sc-lever';
    return `<div class="upgrade-lever-strip">${U().leverStripData(node).map((t) => {
      const cls = t.id === 'manager' && t.tier >= 1 ? 'upgrade-lever mgr-done' : 'upgrade-lever';
      return `<span class="${cls}" ${prefix}-track="${t.id}" ${prefix}-node="${node.id}" data-sc-ghost data-sc-ghost-biz="${node.id}" data-sc-ghost-track="${t.id}">${t.label} ${U().renderTierPips(t.tier, t.max)}</span>`;
    }).join('')}</div>`;
  }

  function renderNodeUpgradeBlock(state, templateId) {
    if (!upgradesActive(state)) return '';
    const farm = F();
    const biz = portfolioBizForTemplate(state, templateId);
    const reNode = !biz && farm
      ? (state.portfolio.realEstate || []).find((r) => r.templateId === templateId && farm.isInfrastructureTemplate(r.templateId))
      : null;
    const node = biz || reNode;
    if (!node) return '';

    U().ensureBusinessUpgrades(node);
    const stats = node.upgradeStats || {};
    let previewLines = '';
    if (biz) {
      ['hire', 'marketing'].forEach((trackId) => {
        const check = U().canApplyTrack(node, trackId, templateId);
        if (!check.ok) return;
        const preview = U().computeUpgradePreview(state, biz.id, trackId);
        if (!preview || !preview.canApply) return;
        const track = U().UPGRADE_TRACKS[trackId];
        const effect = U().formatTrackEffectLine(preview, trackId);
        previewLines += `<div class="sc-upgrade-hint"><strong>${track.name}</strong> → ${effect || U().formatUpgradeRowMeta(preview, trackId, '')}</div>`;
      });
    }

    const improveBtn = biz
      ? `<button type="button" class="mini-btn primary" data-sc-improve="${biz.id}" data-sc-improve-track="hire" data-sc-ghost data-sc-ghost-biz="${biz.id}" data-sc-ghost-track="hire">Improve ${biz.name}</button>`
      : `<span class="sc-hint">Infrastructure capacity scales with property improvements.</span>`;

    return `<div class="sc-upgrade-block">
      <strong>Operational upgrades</strong>
      ${renderLeverStripHtml(node, 'data-sc-lever')}
      <div class="meta">Cap ×${(stats.capacityMult || 1).toFixed(2)} · Dem ×${(stats.demandMult || 1).toFixed(2)} · Opex ×${(stats.opexMult || 1).toFixed(2)} · AP ${stats.effectiveAutopilot || '—'}</div>
      ${previewLines}
      ${improveBtn}
    </div>`;
  }

  function renderLinkUpgradeHints(state, conn, syn) {
    if (!upgradesActive(state) || !conn || !syn || syn.fulfillRatio >= 0.98) return '';
    const biz = portfolioBizForTemplate(state, conn.supplier);
    if (!biz) return '';
    const preview = U().computeUpgradePreview(state, biz.id, 'hire');
    if (!preview || !preview.canApply) return '';
    const linkDelta = (preview.chain || []).find((l) => l.connectionId === conn.id);
    const fillLine = linkDelta
      ? ` · ${linkDelta.label} ${Math.round(linkDelta.fulfillBefore * 100)}%→${Math.round(linkDelta.fulfillAfter * 100)}%`
      : '';
    return `<div class="sc-upgrade-hint">Supplier strained — <button type="button" class="mini-btn" data-sc-improve="${biz.id}" data-sc-improve-track="hire" data-sc-ghost data-sc-ghost-biz="${biz.id}" data-sc-ghost-track="hire">Hire at ${biz.name}</button>${fillLine}</div>`;
  }

  function renderShortageFixButtons(state, shortages) {
    if (!shortages || !shortages.length) return '';
    const Uapi = U();
    const farm = F();
    const btns = [];
    shortages.forEach((s) => {
      const tid = s.templateId;
      if (!tid) return;
      const biz = portfolioBizForTemplate(state, tid);
      const re = !biz && farm
        ? (state.portfolio.realEstate || []).find((r) => r.templateId === tid)
        : null;
      if (biz && Uapi) {
        btns.push(`<button type="button" class="mini-btn primary" data-sc-hire-fix="${tid}">Hire at ${s.name || biz.name}</button>`);
      } else if (re) {
        btns.push(`<button type="button" class="mini-btn" data-sc-hire-fix="${tid}">Upgrade ${s.name || re.name} capacity</button>`);
      }
    });
    if (!btns.length) return '';
    return `<div class="sc-hire-fix-row">${btns.join('')}</div>`;
  }

  const LAYOUT = {
    grain_farm: { x: 80, y: 72, w: 128, h: 72 },
    vegetable_farm: { x: 240, y: 72, w: 128, h: 72 },
    dairy_barn: { x: 560, y: 72, w: 128, h: 72 },
    poultry_coop: { x: 720, y: 72, w: 128, h: 72 },
    feed_mill: { x: 160, y: 200, w: 128, h: 72 },
    bakery: { x: 640, y: 200, w: 128, h: 72 },
    equipment_repair: { x: 200, y: 340, w: 148, h: 72 },
    delivery_cold_storage: { x: 520, y: 340, w: 168, h: 72 },
    farmhouse_restaurant: { x: 280, y: 480, w: 148, h: 72 },
    general_store: { x: 560, y: 480, w: 148, h: 72 },
  };

  const LAYER_BANDS = [
    { y: 48, h: 108, label: 'Upstream production' },
    { y: 176, h: 108, label: 'Processing' },
    { y: 316, h: 108, label: 'Infrastructure tollbooth' },
    { y: 456, h: 108, label: 'Consumer channel' },
  ];

  function fmtMoney(n) {
    if (n == null || isNaN(n)) return '—';
    const sign = n < 0 ? '−' : '';
    return sign + '$' + Math.abs(Math.round(n)).toLocaleString('en-US');
  }

  function pct(n) { return n == null ? '—' : Math.round(n) + '%'; }
  function pctFrac(n) { return n == null ? '—' : Math.round(n * 100) + '%'; }

  function nodeCenter(id) {
    const L = LAYOUT[id];
    return { x: L.x + L.w / 2, y: L.y + L.h / 2, L };
  }

  function linkPath(from, to) {
    const a = nodeCenter(from);
    const b = nodeCenter(to);
    const dy = b.y - a.y;
    const cp = Math.max(40, Math.abs(dy) * 0.45);
    return `M ${a.x} ${a.y + (dy > 0 ? a.L.h / 2 - 4 : -a.L.h / 2 + 4)} C ${a.x} ${a.y + cp}, ${b.x} ${b.y - cp}, ${b.x} ${b.y + (dy > 0 ? -b.L.h / 2 + 4 : b.L.h / 2 - 4)}`;
  }

  function midpoint(from, to) {
    const a = nodeCenter(from);
    const b = nodeCenter(to);
    return { x: (a.x + b.x) / 2, y: (a.y + b.y) / 2 - 6 };
  }

  function effectTags(conn, syn) {
    const fx = conn.effects || {};
    const tags = [];
    const scale = syn ? syn.fulfillRatio : 0;
    if (fx.customerCostReduction) tags.push('−' + pctFrac(fx.customerCostReduction * scale) + ' cost');
    if (fx.customerRevenueBonus) tags.push('+' + pctFrac(fx.customerRevenueBonus * scale) + ' cust rev');
    if (fx.customerReliabilityBonus) tags.push('+' + pctFrac(fx.customerReliabilityBonus * scale) + ' reliability');
    if (fx.supplierRevenueBonus && !syn?.internalLink) tags.push('+' + pctFrac(fx.supplierRevenueBonus) + ' supplier rev');
    if (syn?.internalLink) tags.push('internal — no supplier rev stack');
    return tags;
  }

  /** Compute farm supply-chain economics from live game state. */
  function computeEconomics(state, opts) {
    opts = opts || {};
    const farm = F();
    if (!farm) return null;

    const syns = farm.computeSynergies(state);
    const util = farm.computeSupplierUtilization(state);
    let revenue = 0;
    let costs = 0;
    let exportRev = 0;
    let externalContract = 0;
    const bizRows = [];
    const reRows = [];
    const builder = opts.supplyChainBuilderBonus;

    state.portfolio.businesses.forEach((b) => {
      const applied = farm.applyToBusiness(b, syns, state, { supplyChainBuilderBonus: builder });
      const exp = farm.applyExportToBusiness(b, state);
      const rev = applied.rev + (exp.exportRevenue || 0);
      revenue += rev;
      costs += applied.cost;
      exportRev += exp.exportRevenue || 0;
      bizRows.push({
        id: b.templateId,
        assetId: b.id,
        name: b.name,
        rev,
        cost: applied.cost,
        savings: Math.max(0, b.operatingCosts - applied.cost),
        export: exp.exportRevenue || 0,
      });
    });

    state.portfolio.realEstate.forEach((r) => {
      if (farm.isInfrastructureTemplate(r.templateId)) {
        const infra = farm.applyInfrastructureToRealEstate(r, state, syns);
        revenue += infra.rent;
        costs += infra.opex;
        externalContract += infra.externalContractRevenue || 0;
        reRows.push({
          id: r.templateId,
          assetId: r.id,
          name: r.name,
          rent: infra.rent,
          opex: infra.opex,
          external: infra.externalContractRevenue || 0,
          utilPct: infra.utilizationPct,
        });
      } else {
        revenue += Math.round(r.rentPerTurn * (1 - (r.vacancyRisk || 0) * 0.4));
        costs += r.operatingExpenses;
      }
    });

    return {
      syns,
      util,
      revenue,
      costs,
      profit: revenue - costs,
      exportRev,
      externalContract,
      bizRows,
      reRows,
      shortages: farm.detectSupplyShortages(state),
    };
  }

  function renderGhostOverlay(state, econ, ui) {
    if (!ui || !ui.ghostPreview || !U() || !upgradesActive(state)) return '';
    const { bizId, trackId } = ui.ghostPreview;
    const preview = U().computeUpgradePreview(state, bizId, trackId);
    if (!preview || !preview.canApply) return '';

    const farm = F();
    const node = (state.portfolio.businesses || []).find((b) => b.id === bizId);
    if (!node || !farm) return '';

    let html = '<g class="sc-ghost-layer" pointer-events="none">';
    const templateId = node.templateId;
    const owned = farm.ownedIds(state);

    (preview.chain || []).forEach((link) => {
      if (link.fulfillBefore >= link.fulfillAfter - 0.001 && link.fulfillBefore <= link.fulfillAfter + 0.001) return;
      const conn = farm.CONNECTIONS.find((c) => c.id === link.connectionId);
      if (!conn || !owned.has(conn.supplier) || !owned.has(conn.customer)) return;
      const mid = midpoint(conn.supplier, conn.customer);
      const before = Math.round(link.fulfillBefore * 100);
      const after = Math.round(link.fulfillAfter * 100);
      html += `<path class="sc-link sc-link-ghost" d="${linkPath(conn.supplier, conn.customer)}"/>`;
      html += `<text class="sc-ghost-label" x="${mid.x}" y="${mid.y + 14}" text-anchor="middle">${before}% → ${after}%</text>`;
    });

    if ((trackId === 'hire' || trackId === 'marketing') && farm.isAllocatableTemplate(templateId)) {
      const L = LAYOUT[templateId];
      const u = econ.util[templateId];
      const beforeMult = preview.local?.before?.capacityMult || 1;
      const afterMult = preview.local?.after?.capacityMult || beforeMult;
      if (L && u && afterMult > beforeMult + 0.001) {
        const afterCap = Math.max(1, Math.round(u.capacity * (afterMult / beforeMult)));
        const barW = L.w - 20;
        const ghostUtil = u.demand / afterCap;
        const ghostFillW = Math.min(barW, barW * Math.min(1.15, ghostUtil));
        html += `<rect class="sc-cap-fill ghost" x="${L.x + 10}" y="${L.y + L.h - 14}" width="${ghostFillW}" height="5"/>`;
        html += `<text class="sc-ghost-label" x="${L.x + L.w / 2}" y="${L.y - 4}" text-anchor="middle">Cap ${u.capacity} → ${afterCap}</text>`;
      }
    }

    html += '</g>';
    return html;
  }

  function renderDiagramSvg(state, econ, ui) {
    const farm = F();
    if (!farm || !econ) return '';

    const owned = farm.ownedIds(state);
    const hotLink = ui.selectedLink || ui.hoveredLink;
    const hotNode = ui.selectedNode;
    let html = '';

    LAYER_BANDS.forEach((band) => {
      html += `<rect class="sc-layer-band" x="24" y="${band.y}" width="912" height="${band.h}" rx="4"/>`;
      html += `<text class="sc-layer-label" x="36" y="${band.y + 18}">${band.label}</text>`;
    });

    farm.CONNECTIONS.forEach((conn) => {
      const active = owned.has(conn.supplier) && owned.has(conn.customer);
      const syn = active ? econ.syns.find((s) => s.connectionId === conn.id) : null;
      const fulfill = syn ? syn.fulfillRatio : 0;
      let cls = 'inactive';
      if (active) {
        if (syn && syn.capacityStrained) cls = 'strained';
        else if (fulfill < 0.99) cls = 'partial';
        else cls = 'active';
      }
      if (hotLink === conn.id) cls += ' hot';
      html += `<path class="sc-link ${cls}" data-sc-link="${conn.id}" d="${linkPath(conn.supplier, conn.customer)}"/>`;
      if (active && syn) {
        const mid = midpoint(conn.supplier, conn.customer);
        html += `<text class="sc-link-label" x="${mid.x}" y="${mid.y}" text-anchor="middle">${pctFrac(fulfill)} fill</text>`;
      }
    });

    farm.TEMPLATES.forEach((t) => {
      const L = LAYOUT[t.id];
      if (!L) return;
      const isOwned = owned.has(t.id);
      const u = econ.util[t.id];
      const shortage = u && u.overCapacity;
      const cap = u ? u.capacity : farm.capacityFor(t.id);
      const demand = u ? u.demand : 0;
      const utilPct = u ? u.utilizationPct : 0;
      const row = econ.bizRows.find((r) => r.id === t.id);
      const re = econ.reRows.find((r) => r.id === t.id);
      const selected = hotNode === t.id;

      html += `<g class="sc-node ${isOwned ? 'owned' : 'unowned'} sc-layer-${t.layer}${shortage ? ' shortage' : ''}${selected ? ' selected' : ''}" data-sc-node="${t.id}">`;
      html += `<rect class="sc-node-rect" x="${L.x}" y="${L.y}" width="${L.w}" height="${L.h}"/>`;
      html += `<text class="sc-node-title" x="${L.x + 10}" y="${L.y + 22}">${t.name}</text>`;
      html += `<text class="sc-node-meta" x="${L.x + 10}" y="${L.y + 36}">${t.layerLabel}</text>`;

      if (isOwned) {
        if (re) {
          html += `<text class="sc-node-stat" x="${L.x + 10}" y="${L.y + 50}">Rent ${fmtMoney(re.rent)}/qtr</text>`;
          if (re.external) html += `<text class="sc-node-meta" x="${L.x + 10}" y="${L.y + 62}">+${fmtMoney(re.external)} external</text>`;
        } else if (row) {
          html += `<text class="sc-node-stat" x="${L.x + 10}" y="${L.y + 50}">Rev ${fmtMoney(row.rev)} · Cost ${fmtMoney(row.cost)}</text>`;
        }
        if (farm.isAllocatableTemplate(t.id) && cap) {
          const barW = L.w - 20;
          const baseline = u.baselineLoad || 0;
          const chain = u.demand || 0;
          const displayPct = u.displayUtilPct != null ? u.displayUtilPct : utilPct;
          const fillW = Math.min(barW, barW * Math.min(1.15, displayPct / 100));
          const fillCls = utilPct > 100 ? 'over' : displayPct >= 85 ? 'warn' : 'ok';
          const capLabel = chain > 0
            ? `Base ${baseline} + chain ${chain}/${cap}`
            : `Base ${baseline}/${cap} · chain 0`;
          html += `<text class="sc-node-meta" x="${L.x + 10}" y="${L.y + L.h - 20}">${capLabel} · ${pct(displayPct)}${shortage ? ' SHORTAGE' : ''}</text>`;
          html += `<rect class="sc-cap-bg" x="${L.x + 10}" y="${L.y + L.h - 14}" width="${barW}" height="5"/>`;
          html += `<rect class="sc-cap-fill ${fillCls}" x="${L.x + 10}" y="${L.y + L.h - 14}" width="${fillW}" height="5"/>`;
        }
        if (upgradesActive(state)) {
          const node = portfolioBizForTemplate(state, t.id)
            || (state.portfolio.realEstate || []).find((r) => r.templateId === t.id);
          if (node && U()) {
            const strip = U().formatLeverStripText(node);
            html += `<text class="sc-node-meta" x="${L.x + 10}" y="${L.y + L.h - 6}" font-size="8">${strip.slice(0, 42)}</text>`;
          }
        }
      } else {
        html += `<text class="sc-node-meta sc-unowned" x="${L.x + 10}" y="${L.y + 52}">Not owned</text>`;
      }
      html += `</g>`;
    });

    html += renderGhostOverlay(state, econ, ui);
    return html;
  }

  function renderCenterWrap(state, econ, ui) {
    const farm = F();
    const shortages = econ.shortages || [];
    const ack = state.supplyShortageAckTurn === state.turn;
    let banner = '';
    if (shortages.length && !ack) {
      banner = `<div class="shortage-banner sc-shortage-banner">Supply shortage on ${shortages.map((s) => s.name).join(', ')} — set allocation in the panel, then advance turn (0 AP).
        ${renderShortageFixButtons(state, shortages)}
      </div>`;
    }
    const ownedCount = farm ? farm.ownedIds(state).size : 0;
    const empty = ownedCount === 0
      ? `<div class="empty-hint sc-empty">No farm assets yet. Switch to <strong>View Opportunities</strong> to acquire businesses and build the chain.</div>`
      : '';

    return `${banner}
      <div class="sc-center-head">
        <h2>Supply Chain Map</h2>
        <p class="sc-lead">Manage allocation policies and read flow economics. Capacity bars show existing client load (base) plus owned chain pull. Green links = full fulfillment · amber = partial · red = strained or shortage.</p>
      </div>
      ${empty}
      <div class="sc-graph-wrap">
        <svg id="supplyChainSvg" class="sc-svg" viewBox="0 0 960 620" xmlns="http://www.w3.org/2000/svg">${renderDiagramSvg(state, econ, ui)}</svg>
      </div>`;
  }

  function renderPanelHtml(state, econ, ui, helpers) {
    const farm = F();
    if (!farm || !econ) return '<div class="empty-hint">Supply chain unavailable.</div>';

    const owned = farm.ownedIds(state);
    const allocatable = Object.values(econ.util || {});
    const policyHtml = allocatable.length ? allocatable.map((u) => {
      const pol = farm.getSupplyPolicy(state, u.templateId);
      const opts = Object.keys(farm.SUPPLY_POLICIES).map((k) => {
        const p = farm.SUPPLY_POLICIES[k];
        return `<option value="${k}"${pol === k ? ' selected' : ''}>${p.label}</option>`;
      }).join('');
      return `<div class="sc-policy-row"><label>${u.name}</label><select class="sc-policy-select" data-sc-policy="${u.templateId}">${opts}</select><div class="sc-policy-note">${farm.SUPPLY_POLICIES[pol]?.summary || ''}</div></div>`;
    }).join('') : '<p class="sc-hint">Own upstream producers or infrastructure to set allocation policy.</p>';

    let detailHtml = '<p class="sc-hint">Hover or click a connection to inspect modifiers. Click an owned node to focus allocation.</p>';
    const connId = ui.selectedLink || ui.hoveredLink;
    if (connId) {
      const conn = farm.CONNECTIONS.find((c) => c.id === connId);
      if (conn) {
        const active = owned.has(conn.supplier) && owned.has(conn.customer);
        const syn = active ? econ.syns.find((s) => s.connectionId === conn.id) : null;
        const tags = effectTags(conn, syn);
        detailHtml = `<div class="sc-link-detail">
          <strong>${farm.templateById(conn.supplier).name} → ${farm.templateById(conn.customer).name}</strong><br>
          ${conn.flow}<br>
          ${active ? `Fulfillment <strong>${pctFrac(syn.fulfillRatio)}</strong>` : 'Inactive — need both businesses owned.'}
          <div class="sc-tags">${tags.map((t) => `<span class="sc-tag">${t}</span>`).join('')}</div>
          ${active && syn.internalLink ? '<div class="sc-internal-note">Internal link: cost savings only — not stacked portfolio revenue.</div>' : ''}
          ${active && syn ? renderLinkUpgradeHints(state, conn, syn) : ''}
        </div>`;
      }
    } else if (ui.selectedNode) {
      const t = farm.templateById(ui.selectedNode);
      const pol = farm.getSupplyPolicy(state, ui.selectedNode);
      const u = econ.util[ui.selectedNode];
      if (t) {
        detailHtml = `<div class="sc-link-detail">
          <strong>${t.name}</strong> · ${t.layerLabel}<br>
          ${owned.has(ui.selectedNode) ? (u ? `Capacity base ${u.baselineLoad || 0} + chain ${u.demand}/${u.capacity} (${pct(u.displayUtilPct != null ? u.displayUtilPct : u.utilizationPct)}) · Policy: ${farm.SUPPLY_POLICIES[pol]?.label}` : 'Consumer / non-capacity asset') : 'Not in portfolio — acquire from Opportunities.'}
          ${owned.has(ui.selectedNode) ? renderNodeUpgradeBlock(state, ui.selectedNode) : ''}
        </div>`;
      }
    }

    const activeLinks = econ.syns.filter((s) => s.fulfillRatio > 0);
    const allocLines = activeLinks.slice(0, 10).map((s) =>
      `<li>${s.label}: ${pctFrac(s.fulfillRatio)} · −${pctFrac(s.costReduction)} cost${s.revenueBonusCustomer ? ', +' + pctFrac(s.revenueBonusCustomer) + ' rev' : ''}</li>`
    ).join('');

    const debt = helpers.debtService != null ? helpers.debtService : 0;
    const profitAfterDebt = econ.profit - debt;

    return `
      <h2>Supply Chain P&amp;L</h2>
      <div class="sc-panel">
        <p class="sc-hint">Consolidated external revenue − operating costs. Chain links reduce costs; they do not fake extra top-line.</p>
        <div class="sc-pl-row"><span class="lbl">External revenue</span><span class="val">${fmtMoney(econ.revenue)}</span></div>
        <div class="sc-pl-row"><span class="lbl">Operating costs</span><span class="val neg">${fmtMoney(econ.costs)}</span></div>
        <div class="sc-pl-row"><span class="lbl">Operating profit</span><span class="val ${econ.profit >= 0 ? 'pos' : 'neg'}">${fmtMoney(econ.profit)}</span></div>
        ${debt ? `<div class="sc-pl-row"><span class="lbl">Debt service</span><span class="val neg">${fmtMoney(debt)}</span></div>
        <div class="sc-pl-row sc-pl-total"><span class="lbl">After debt</span><span class="val ${profitAfterDebt >= 0 ? 'pos' : 'neg'}">${fmtMoney(profitAfterDebt)}</span></div>` : ''}
        ${econ.exportRev ? `<div class="sc-pl-row"><span class="lbl">Export (floor)</span><span class="val">${fmtMoney(econ.exportRev)}/qtr</span></div>` : ''}
        ${econ.externalContract ? `<div class="sc-pl-row"><span class="lbl">Infra contracts</span><span class="val">${fmtMoney(econ.externalContract)}/qtr</span></div>` : ''}
        ${econ.shortages.length ? `<div class="sc-pl-row"><span class="lbl warn">Shortage</span><span class="val neg">${econ.shortages.map((s) => s.name).join(', ')}</span></div>
        ${renderShortageFixButtons(state, econ.shortages)}` : ''}
      </div>
      <h2 style="margin-top:16px">Capacity &amp; allocation</h2>
      <div class="sc-panel">${policyHtml}${allocLines ? `<ul class="sc-alloc-list">${allocLines}</ul>` : ''}</div>
      <h2 style="margin-top:16px">Connection detail</h2>
      <div class="sc-panel">${detailHtml}</div>
      ${econ.bizRows.length || econ.reRows.length ? `<h2 style="margin-top:16px">Owned flow</h2>
      <div class="sc-panel">
        ${econ.bizRows.map((r) => `<div class="sc-pl-row"><span class="lbl">${r.name}</span><span class="val">${fmtMoney(r.rev)} · save ${fmtMoney(r.savings)}</span></div>`).join('')}
        ${econ.reRows.map((r) => `<div class="sc-pl-row"><span class="lbl">${r.name}</span><span class="val">${fmtMoney(r.rent)} · ${pct(r.utilPct)} util</span></div>`).join('')}
      </div>` : ''}`;
  }

  function bindDiagram(svgEl, callbacks) {
    if (!svgEl) return;
    svgEl.querySelectorAll('[data-sc-link]').forEach((el) => {
      const id = el.dataset.scLink;
      el.addEventListener('mouseenter', () => callbacks.onLinkHover(id));
      el.addEventListener('mouseleave', () => callbacks.onLinkHover(null));
      el.addEventListener('click', (e) => {
        e.stopPropagation();
        callbacks.onLinkSelect(id);
      });
    });
    svgEl.querySelectorAll('[data-sc-node]').forEach((el) => {
      el.addEventListener('click', () => callbacks.onNodeSelect(el.dataset.scNode));
    });
  }

  function bindPanel(panelEl, callbacks) {
    if (!panelEl) return;
    panelEl.querySelectorAll('[data-sc-policy]').forEach((sel) => {
      sel.addEventListener('change', () => callbacks.onPolicyChange(sel.dataset.scPolicy, sel.value));
    });
    panelEl.querySelectorAll('[data-sc-improve]').forEach((btn) => {
      btn.addEventListener('click', () => {
        if (callbacks.onImproveAsset) {
          callbacks.onImproveAsset(btn.dataset.scImprove, btn.dataset.scImproveTrack || 'hire');
        }
      });
    });
    panelEl.querySelectorAll('[data-sc-hire-fix]').forEach((btn) => {
      btn.addEventListener('click', () => {
        if (callbacks.onHireFix) callbacks.onHireFix(btn.dataset.scHireFix);
      });
    });
    panelEl.querySelectorAll('[data-sc-lever-track]').forEach((el) => {
      el.addEventListener('click', () => {
        if (callbacks.onImproveAsset) {
          callbacks.onImproveAsset(el.dataset.scLeverNode, el.dataset.scLeverTrack);
        }
      });
    });
    panelEl.querySelectorAll('[data-sc-ghost]').forEach((el) => {
      el.addEventListener('mouseenter', () => {
        if (callbacks.onGhostPreview) {
          callbacks.onGhostPreview(el.dataset.scGhostBiz, el.dataset.scGhostTrack);
        }
      });
      el.addEventListener('mouseleave', () => {
        if (callbacks.onGhostClear) callbacks.onGhostClear();
      });
    });
  }

  function bindShortageActions(rootEl, callbacks) {
    if (!rootEl || !callbacks) return;
    rootEl.querySelectorAll('[data-sc-hire-fix]').forEach((btn) => {
      btn.addEventListener('click', () => {
        if (callbacks.onHireFix) callbacks.onHireFix(btn.dataset.scHireFix);
      });
    });
  }

  function highlightLinks(ui) {
    const hot = ui.selectedLink || ui.hoveredLink;
    document.querySelectorAll('[data-sc-link]').forEach((el) => {
      const on = el.dataset.scLink === hot;
      el.style.strokeWidth = on ? '3.5' : '';
      el.style.opacity = hot && !on ? '0.35' : '';
    });
  }

  global.SupplyChainView = {
    computeEconomics,
    renderCenterWrap,
    renderPanelHtml,
    bindDiagram,
    bindPanel,
    bindShortageActions,
    highlightLinks,
    renderLeverStripHtml,
    renderShortageFixButtons,
  };
})(typeof window !== 'undefined' ? window : globalThis);
