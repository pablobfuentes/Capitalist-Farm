/**
 * Export Capital Farm templates + connections from js/farm-supply-chain.js
 * to godot/data/farm_content.json for the Godot ContentRegistry.
 */
'use strict';

const fs = require('fs');
const path = require('path');
const vm = require('vm');

const root = path.join(__dirname, '..');
const jsPath = path.join(root, 'js', 'farm-supply-chain.js');
const outPath = path.join(root, 'godot', 'data', 'farm_content.json');

const code = fs.readFileSync(jsPath, 'utf8');
const sandbox = { global: {}, globalThis: {}, window: {}, console };
sandbox.global = sandbox.globalThis;
sandbox.window = sandbox.globalThis;

vm.createContext(sandbox);
vm.runInContext(code, sandbox);

const F = sandbox.globalThis.FarmSupplyChain;
if (!F) {
  console.error('FarmSupplyChain not found after loading farm-supply-chain.js');
  process.exit(1);
}

const CONNECTION_DEMAND = {
  grain_to_feed: 38, grain_to_bakery: 28, grain_to_store: 22,
  veg_to_restaurant: 45, veg_to_store: 30,
  feed_to_dairy: 42, feed_to_poultry: 40,
  dairy_to_bakery: 25, dairy_to_restaurant: 22, dairy_to_store: 20,
  poultry_to_bakery: 22, poultry_to_restaurant: 24, poultry_to_store: 20,
  bakery_to_restaurant: 30, bakery_to_store: 28,
  restaurant_to_store: 18,
  equip_to_grain: 16, equip_to_veg: 14, equip_to_dairy: 18, equip_to_poultry: 16,
  equip_to_feed: 18, equip_to_bakery: 14,
  delivery_to_veg: 14, delivery_to_dairy: 18, delivery_to_poultry: 16,
  delivery_to_feed: 12, delivery_to_bakery: 14, delivery_to_restaurant: 20, delivery_to_store: 16,
};

const CUSTOMER_ALLOC_PRIORITY = {
  feed_mill: 5, bakery: 4, dairy_barn: 4, poultry_coop: 4,
  farmhouse_restaurant: 3, general_store: 2, grain_farm: 1, vegetable_farm: 1,
};

const payload = {
  version: 1,
  source: 'js/farm-supply-chain.js',
  exportedAt: new Date().toISOString(),
  templates: F.TEMPLATES.map((t) => ({
    id: t.id,
    name: t.name,
    layer: t.layer,
    layer_label: t.layerLabel,
    industry: t.industry,
    asset_class: t.assetClass || null,
    autopilot: t.autopilot,
    capacity_units: t.capacityUnits,
    consumer_capacity_units: t.consumerCapacityUnits,
    baseline_capacity_frac: t.baselineCapacityFrac,
    demand_export_weight: t.demandExportWeight,
    marketing_eligible: t.marketingEligible,
    input_tags: t.inputTags || [],
    output_tags: t.outputTags || [],
    risk_tags: t.riskTags || [],
    blurb: t.blurb || '',
    price_range: t.priceRange || [50000, 100000],
    rev_range: t.revRange || [10000, 20000],
    margin_range: t.marginRange || [0.15, 0.25],
    owner_dep: t.ownerDep != null ? t.ownerDep : 0.5,
    cust_conc: t.custConc || [0.1, 0.25],
  })),
  connections: F.CONNECTIONS.map((c) => ({
    id: c.id,
    supplier: c.supplier,
    customer: c.customer,
    flow: c.flow,
    effects: c.effects || {},
    risk_links: c.riskLinks || [],
    vulnerability_label: c.vulnerabilityLabel || '',
  })),
  connection_demand: CONNECTION_DEMAND,
  customer_alloc_priority: CUSTOMER_ALLOC_PRIORITY,
};

fs.mkdirSync(path.dirname(outPath), { recursive: true });
fs.writeFileSync(outPath, JSON.stringify(payload, null, 2) + '\n');
console.log('Wrote', outPath, `(${payload.templates.length} templates, ${payload.connections.length} connections)`);
