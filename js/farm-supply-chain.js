/**
 * Capital Farm — Business Ecosystem & Supply Chain System.
 *
 * Replaces Arcade business templates with ten connected farm businesses
 * and authored supplier→customer synergies. Simulator mode stays unchanged.
 *
 *   <script src="js/farm-supply-chain.js"></script>
 *
 *   FarmSupplyChain.TEMPLATES
 *   FarmSupplyChain.CONNECTIONS
 *   FarmSupplyChain.computeSynergies(state)
 *   FarmSupplyChain.pickTemplate(state)
 *   FarmSupplyChain.strategicHint(state, templateId)
 *   FarmSupplyChain.pickShock(state)
 *   FarmSupplyChain.classifyStrategy(state)
 */
(function (global) {
  'use strict';

  const TEMPLATES = [
    { id:'grain_farm', name:'Grain Farm', layer:'primary_production', industry:'farm_food',
      inputTags:['seed','fertilizer','equipment_service','bulk_transport'],
      outputTags:['grain','corn','wheat'],
      capabilityTags:['primary_production','weather_exposed'],
      dependencyPartners:['equipment_repair','delivery_cold_storage','general_store'],
      downstreamPartners:['feed_mill','bakery','general_store'],
      riskTags:['weather','commodity_price','machinery'],
      priceRange:[55000,120000], revRange:[12000,22000], marginRange:[0.18,0.30],
      ownerDep:0.5, custConc:[0.08,0.22],
      blurb:'Primary grain production — weather and commodity exposure, foundational for the feed and bakery chains.' },
    { id:'vegetable_farm', name:'Vegetable Farm', layer:'primary_production', industry:'farm_food',
      inputTags:['seed','water','equipment_service','cold_transport'],
      outputTags:['vegetables','herbs'],
      capabilityTags:['primary_production','perishable_production','weather_exposed'],
      dependencyPartners:['equipment_repair','delivery_cold_storage','farmhouse_restaurant'],
      downstreamPartners:['farmhouse_restaurant','general_store'],
      riskTags:['weather','spoilage','labor'],
      priceRange:[60000,130000], revRange:[14000,26000], marginRange:[0.16,0.28],
      ownerDep:0.55, custConc:[0.1,0.28],
      blurb:'Seasonal produce for restaurant and retail — freshness, spoilage, and irrigation risk.' },
    { id:'dairy_barn', name:'Dairy Barn', layer:'primary_production', industry:'farm_food',
      inputTags:['animal_feed','equipment_service','cold_transport'],
      outputTags:['milk','cream','butter','cheese'],
      capabilityTags:['primary_production','perishable_production'],
      dependencyPartners:['feed_mill','equipment_repair','delivery_cold_storage'],
      downstreamPartners:['bakery','farmhouse_restaurant','general_store'],
      riskTags:['animal_health','cold_chain','feed_price'],
      priceRange:[90000,180000], revRange:[18000,34000], marginRange:[0.14,0.26],
      ownerDep:0.58, custConc:[0.12,0.3],
      blurb:'Milk and dairy goods — feed costs, animal health, and cold-chain dependence.' },
    { id:'poultry_coop', name:'Poultry Coop', layer:'primary_production', industry:'farm_food',
      inputTags:['animal_feed','equipment_service','cold_transport'],
      outputTags:['eggs','poultry'],
      capabilityTags:['primary_production','perishable_production'],
      dependencyPartners:['feed_mill','delivery_cold_storage','general_store'],
      downstreamPartners:['bakery','farmhouse_restaurant','general_store'],
      riskTags:['animal_health','cold_chain','feed_price','biosecurity'],
      priceRange:[50000,110000], revRange:[13000,25000], marginRange:[0.15,0.27],
      ownerDep:0.52, custConc:[0.1,0.26],
      blurb:'Eggs and poultry — biosecurity, feed inflation, and refrigerated logistics.' },
    { id:'feed_mill', name:'Feed Mill', layer:'processing', industry:'farm_food',
      inputTags:['grain','equipment_service','bulk_transport'],
      outputTags:['animal_feed'],
      capabilityTags:['processing','machinery_intensive'],
      dependencyPartners:['grain_farm','equipment_repair','delivery_cold_storage'],
      downstreamPartners:['dairy_barn','poultry_coop'],
      riskTags:['commodity_price','machinery','contamination'],
      priceRange:[80000,160000], revRange:[16000,30000], marginRange:[0.16,0.28],
      ownerDep:0.45, custConc:[0.15,0.35],
      blurb:'Converts grain into animal feed — the hinge between crops and livestock.' },
    { id:'equipment_repair', name:'Equipment & Repair Shed', layer:'infrastructure', industry:'farm_services',
      assetClass:'real_estate',
      inputTags:['skilled_labor','spare_parts'],
      outputTags:['equipment_service','maintenance_capacity'],
      capabilityTags:['infrastructure','enabler'],
      dependencyPartners:['grain_farm','vegetable_farm','delivery_cold_storage'],
      downstreamPartners:['grain_farm','vegetable_farm','dairy_barn','poultry_coop','feed_mill','bakery'],
      riskTags:['skilled_labor','parts_shortage'],
      priceRange:[70000,140000], rentRange:[14000,28000], revRange:[14000,28000],
      marginRange:[0.22,0.34], downPct:0.22, opexPct:0.30, vacancyRisk:0.10,
      ownerDep:0.6, custConc:[0.12,0.32],
      blurb:'Yard, bays, and workshop — appreciates like real estate while enabling the whole farm.' },
    { id:'bakery', name:'Bakery', layer:'processing', industry:'farm_food',
      inputTags:['grain','dairy','eggs','cold_transport'],
      outputTags:['bread','pastries','packaged_food'],
      capabilityTags:['processing','finished_goods','perishable_production'],
      dependencyPartners:['grain_farm','dairy_barn','poultry_coop','delivery_cold_storage'],
      downstreamPartners:['farmhouse_restaurant','general_store'],
      riskTags:['spoilage','demand','energy','labor'],
      priceRange:[85000,170000], revRange:[20000,38000], marginRange:[0.14,0.24],
      ownerDep:0.55, custConc:[0.08,0.22],
      blurb:'Turns grain, dairy, and eggs into higher-margin baked goods for restaurant and retail.' },
    { id:'farmhouse_restaurant', name:'Farmhouse Restaurant', layer:'consumer_channel', industry:'farm_food',
      inputTags:['vegetables','dairy','eggs','poultry','bread','cold_transport'],
      outputTags:['prepared_food','hospitality_demand'],
      capabilityTags:['consumer_channel','retail_location'],
      dependencyPartners:['vegetable_farm','dairy_barn','poultry_coop','bakery','delivery_cold_storage'],
      downstreamPartners:['general_store'],
      riskTags:['reputation','demand','food_safety','supplier_concentration'],
      priceRange:[110000,240000], revRange:[35000,70000], marginRange:[0.10,0.20],
      ownerDep:0.62, custConc:[0.05,0.15],
      blurb:'Premium hospitality margins — captures the top of the food chain, with high fixed costs.' },
    { id:'general_store', name:'General Store & Market', layer:'consumer_channel', industry:'farm_food',
      inputTags:['vegetables','dairy','eggs','poultry','bread','packaged_food','cold_transport'],
      outputTags:['retail_channel','consumer_data'],
      capabilityTags:['consumer_channel','distribution','retail_location'],
      dependencyPartners:['vegetable_farm','dairy_barn','poultry_coop','bakery','delivery_cold_storage'],
      downstreamPartners:[],
      riskTags:['demand','inventory_waste','labor'],
      priceRange:[95000,190000], revRange:[24000,48000], marginRange:[0.12,0.22],
      ownerDep:0.48, custConc:[0.04,0.12],
      blurb:'Retail shelf access and consumer demand data for nearly every farm product.' },
    { id:'delivery_cold_storage', name:'Delivery & Cold Storage', layer:'infrastructure', industry:'farm_services',
      assetClass:'real_estate',
      inputTags:['fuel','equipment_service','route_demand'],
      outputTags:['bulk_transport','cold_transport','storage_capacity'],
      capabilityTags:['infrastructure','enabler','logistics'],
      dependencyPartners:['dairy_barn','poultry_coop','farmhouse_restaurant','equipment_repair'],
      downstreamPartners:['vegetable_farm','dairy_barn','poultry_coop','feed_mill','bakery','farmhouse_restaurant','general_store'],
      riskTags:['fuel','cold_chain','machinery','route_concentration'],
      priceRange:[100000,210000], rentRange:[20000,40000], revRange:[20000,40000],
      marginRange:[0.16,0.28], downPct:0.25, opexPct:0.32, vacancyRisk:0.12,
      ownerDep:0.5, custConc:[0.1,0.28],
      blurb:'Warehouses, docks, and cold rooms — property-style growth with logistics rents across the farm.' },
  ];

  const LAYER_LABELS = {
    primary_production: 'Upstream production',
    processing: 'Processing',
    infrastructure: 'Infrastructure',
    consumer_channel: 'Consumer channel',
  };

  /** Abstract demand weight per active owned customer link (not literal units). */
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

  const TEMPLATE_META = {
    grain_farm: { autopilot: 4, capacityUnits: 75, baselineCapacityFrac: 0.42, demandExportWeight: 0.35, marketingEligible: true, complexityProfile: { operational: 'low', supplyDependency: 'low', demandExposure: 'high', perishability: 'low' } },
    vegetable_farm: { autopilot: 3, capacityUnits: 70, baselineCapacityFrac: 0.40, demandExportWeight: 0.4, marketingEligible: true, complexityProfile: { operational: 'medium', supplyDependency: 'medium', demandExposure: 'high', perishability: 'high' } },
    dairy_barn: { autopilot: 2, capacityUnits: 80, baselineCapacityFrac: 0.38, demandExportWeight: 0.3, marketingEligible: true, complexityProfile: { operational: 'medium', supplyDependency: 'medium', demandExposure: 'medium', perishability: 'high' } },
    poultry_coop: { autopilot: 3, capacityUnits: 78, baselineCapacityFrac: 0.38, demandExportWeight: 0.3, marketingEligible: true, complexityProfile: { operational: 'medium', supplyDependency: 'medium', demandExposure: 'medium', perishability: 'high' } },
    feed_mill: { autopilot: 4, capacityUnits: 72, baselineCapacityFrac: 0.36, demandExportWeight: 0.2, marketingEligible: true, complexityProfile: { operational: 'medium', supplyDependency: 'high', demandExposure: 'medium', perishability: 'low' } },
    equipment_repair: { autopilot: 3, capacityUnits: 88, baselineCapacityFrac: 0.28, demandExportWeight: 0, marketingEligible: false, complexityProfile: { operational: 'medium', supplyDependency: 'low', demandExposure: 'medium', perishability: 'low' } },
    bakery: { autopilot: 2, capacityUnits: 68, baselineCapacityFrac: 0.35, demandExportWeight: 0.25, marketingEligible: true, complexityProfile: { operational: 'high', supplyDependency: 'high', demandExposure: 'medium', perishability: 'high' } },
    farmhouse_restaurant: { autopilot: 1, capacityUnits: null, consumerCapacityUnits: 82, baselineCapacityFrac: 0.55, demandExportWeight: 0.85, marketingEligible: true, complexityProfile: { operational: 'high', supplyDependency: 'high', demandExposure: 'high', perishability: 'high' } },
    general_store: { autopilot: 2, capacityUnits: null, consumerCapacityUnits: 88, baselineCapacityFrac: 0.50, demandExportWeight: 0.9, marketingEligible: true, complexityProfile: { operational: 'medium', supplyDependency: 'high', demandExposure: 'high', perishability: 'medium' } },
    delivery_cold_storage: { autopilot: 3, capacityUnits: 95, baselineCapacityFrac: 0.30, demandExportWeight: 0, marketingEligible: false, complexityProfile: { operational: 'medium', supplyDependency: 'medium', demandExposure: 'medium', perishability: 'low' } },
  };

  const SUPPLY_POLICIES = {
    portfolio_first: { id: 'portfolio_first', label: 'Portfolio First', summary: 'Owned downstream gets priority — best for vertical integration.' },
    highest_bidder: { id: 'highest_bidder', label: 'Highest Bidder', summary: 'Capacity goes to the highest-margin links — may starve owned downstream.' },
    contract_first: { id: 'contract_first', label: 'Contract First', summary: 'Stable proportional fill — steady cash flow, less spike upside.' },
    balanced: { id: 'balanced', label: 'Balanced', summary: 'Split capacity proportionally — moderate everything.' },
  };

  const CUSTOMER_ALLOC_PRIORITY = {
    feed_mill: 5, bakery: 4, dairy_barn: 4, poultry_coop: 4,
    farmhouse_restaurant: 3, general_store: 2, grain_farm: 1, vegetable_farm: 1,
  };

  TEMPLATES.forEach((t) => {
    const m = TEMPLATE_META[t.id] || {};
    t.layerLabel = LAYER_LABELS[t.layer] || t.layer;
    t.autopilot = m.autopilot != null ? m.autopilot : 3;
    t.capacityUnits = m.capacityUnits;
    t.consumerCapacityUnits = m.consumerCapacityUnits != null ? m.consumerCapacityUnits : null;
    t.baselineCapacityFrac = m.baselineCapacityFrac != null ? m.baselineCapacityFrac : null;
    t.demandExportWeight = m.demandExportWeight != null ? m.demandExportWeight : 0.25;
    t.marketingEligible = m.marketingEligible !== false;
    t.complexityProfile = m.complexityProfile || {};
  });

  const BUSINESS_TEMPLATES = TEMPLATES.filter((t) => t.assetClass !== 'real_estate');
  const REAL_ESTATE_TEMPLATES = TEMPLATES.filter((t) => t.assetClass === 'real_estate');

  /** Full Section-4 connection register */
  const CONNECTIONS = [
    { id:'grain_to_feed', supplier:'grain_farm', customer:'feed_mill', flow:'Grain',
      effects:{ customerCostReduction:0.15, customerReliabilityBonus:0.15, supplierDemandStability:0.10 },
      riskLinks:['weather','commodity_price'], vulnerabilityLabel:'Weather / commodity shock hits both crop and feed.' },
    { id:'grain_to_bakery', supplier:'grain_farm', customer:'bakery', flow:'Wheat / flour-grade grain',
      effects:{ customerCostReduction:0.12, customerRevenueBonus:0.04 },
      riskLinks:['weather'], vulnerabilityLabel:'Crop quality can lower bakery output quality.' },
    { id:'grain_to_store', supplier:'grain_farm', customer:'general_store', flow:'Packaged grain',
      effects:{ supplierRevenueBonus:0.05, customerRevenueBonus:0.03, supplierDemandStability:0.10 },
      riskLinks:['demand'], vulnerabilityLabel:'Retail inventory may accumulate when demand is weak.' },
    { id:'veg_to_restaurant', supplier:'vegetable_farm', customer:'farmhouse_restaurant', flow:'Vegetables and herbs',
      effects:{ customerCostReduction:0.10, customerRevenueBonus:0.05 },
      riskLinks:['weather','spoilage'], vulnerabilityLabel:'Spoilage and weather become restaurant risks.' },
    { id:'veg_to_store', supplier:'vegetable_farm', customer:'general_store', flow:'Retail produce',
      effects:{ customerRevenueBonus:0.06, supplierDemandStability:0.10 },
      riskLinks:['spoilage','demand'], vulnerabilityLabel:'Waste rises when consumer demand is weak.' },
    { id:'feed_to_dairy', supplier:'feed_mill', customer:'dairy_barn', flow:'Animal feed',
      effects:{ customerCostReduction:0.14, customerReliabilityBonus:0.15 },
      riskLinks:['contamination','feed_price'], vulnerabilityLabel:'Feed quality failure harms animal productivity.' },
    { id:'feed_to_poultry', supplier:'feed_mill', customer:'poultry_coop', flow:'Animal feed',
      effects:{ customerCostReduction:0.14, customerReliabilityBonus:0.15 },
      riskLinks:['contamination','animal_health'], vulnerabilityLabel:'Flock loss leaves unused mill capacity.' },
    { id:'dairy_to_bakery', supplier:'dairy_barn', customer:'bakery', flow:'Milk, cream, butter',
      effects:{ customerCostReduction:0.10, customerRevenueBonus:0.05 },
      riskLinks:['cold_chain','animal_health'], vulnerabilityLabel:'Cold-chain failure damages both dairy and bakery.' },
    { id:'dairy_to_restaurant', supplier:'dairy_barn', customer:'farmhouse_restaurant', flow:'Dairy products',
      effects:{ customerCostReduction:0.08, customerRevenueBonus:0.04 },
      riskLinks:['animal_health','cold_chain'], vulnerabilityLabel:'Animal-health shock reaches restaurant margins.' },
    { id:'dairy_to_store', supplier:'dairy_barn', customer:'general_store', flow:'Milk, cheese, butter',
      effects:{ customerRevenueBonus:0.06, supplierDemandStability:0.10 },
      riskLinks:['spoilage','cold_chain'], vulnerabilityLabel:'Perishable inventory risk at retail.' },
    { id:'poultry_to_bakery', supplier:'poultry_coop', customer:'bakery', flow:'Eggs',
      effects:{ customerCostReduction:0.08, customerReliabilityBonus:0.10 },
      riskLinks:['animal_health','biosecurity'], vulnerabilityLabel:'Disease shock disrupts bakery output.' },
    { id:'poultry_to_restaurant', supplier:'poultry_coop', customer:'farmhouse_restaurant', flow:'Eggs and poultry',
      effects:{ customerCostReduction:0.09, customerReliabilityBonus:0.10 },
      riskLinks:['food_safety','animal_health'], vulnerabilityLabel:'Food-safety event damages restaurant reputation.' },
    { id:'poultry_to_store', supplier:'poultry_coop', customer:'general_store', flow:'Eggs and poultry',
      effects:{ customerRevenueBonus:0.06, supplierDemandStability:0.10 },
      riskLinks:['cold_chain','spoilage'], vulnerabilityLabel:'Refrigeration and waste exposure.' },
    { id:'bakery_to_restaurant', supplier:'bakery', customer:'farmhouse_restaurant', flow:'Bread and desserts',
      effects:{ customerCostReduction:0.06, customerRevenueBonus:0.04 },
      riskLinks:['reputation','spoilage'], vulnerabilityLabel:'Quality problems affect both brands.' },
    { id:'bakery_to_store', supplier:'bakery', customer:'general_store', flow:'Packaged bakery goods',
      effects:{ supplierRevenueBonus:0.15, customerRevenueBonus:0.05 },
      riskLinks:['spoilage','demand'], vulnerabilityLabel:'Unsold short-life inventory.' },
    { id:'restaurant_to_store', supplier:'farmhouse_restaurant', customer:'general_store', flow:'Brand traffic',
      effects:{ customerRevenueBonus:0.05, supplierRevenueBonus:0.04 },
      riskLinks:['reputation','demand'], vulnerabilityLabel:'Shared reputation creates correlated downside.' },
    { id:'equip_to_grain', supplier:'equipment_repair', customer:'grain_farm', flow:'Maintenance service',
      effects:{ customerCostReduction:0.20, customerReliabilityBonus:0.25 },
      riskLinks:['skilled_labor','machinery'], vulnerabilityLabel:'Repair capacity depends on technician availability.' },
    { id:'equip_to_veg', supplier:'equipment_repair', customer:'vegetable_farm', flow:'Irrigation and machinery service',
      effects:{ customerCostReduction:0.12, customerReliabilityBonus:0.20 },
      riskLinks:['parts_shortage','machinery'], vulnerabilityLabel:'Parts shortage can delay harvest.' },
    { id:'equip_to_dairy', supplier:'equipment_repair', customer:'dairy_barn', flow:'Milking / cooling maintenance',
      effects:{ customerReliabilityBonus:0.25, customerCostReduction:0.10 },
      riskLinks:['machinery','cold_chain'], vulnerabilityLabel:'A single cooling failure can still cause large loss.' },
    { id:'equip_to_poultry', supplier:'equipment_repair', customer:'poultry_coop', flow:'Ventilation / processing maintenance',
      effects:{ customerReliabilityBonus:0.20, customerCostReduction:0.08 },
      riskLinks:['biosecurity','parts_shortage'], vulnerabilityLabel:'Specialized parts required.' },
    { id:'equip_to_feed', supplier:'equipment_repair', customer:'feed_mill', flow:'Mill machinery service',
      effects:{ customerReliabilityBonus:0.25, customerRevenueBonus:0.05 },
      riskLinks:['machinery','skilled_labor'], vulnerabilityLabel:'High utilization may strain repair capacity.' },
    { id:'equip_to_bakery', supplier:'equipment_repair', customer:'bakery', flow:'Oven and refrigeration service',
      effects:{ customerCostReduction:0.05, customerReliabilityBonus:0.20 },
      riskLinks:['skilled_labor','energy'], vulnerabilityLabel:'Skilled technician concentration.' },
    { id:'delivery_to_veg', supplier:'delivery_cold_storage', customer:'vegetable_farm', flow:'Cold transport / storage',
      effects:{ customerCostReduction:0.12, supplierDemandStability:0.08, customerRevenueBonus:0.15 },
      riskLinks:['fuel','cold_chain','spoilage'], vulnerabilityLabel:'Fuel and refrigeration shocks.' },
    { id:'delivery_to_dairy', supplier:'delivery_cold_storage', customer:'dairy_barn', flow:'Cold transport',
      effects:{ customerCostReduction:0.14, customerRevenueBonus:0.15 },
      riskLinks:['cold_chain','fuel'], vulnerabilityLabel:'Cold-chain failure causes severe loss.' },
    { id:'delivery_to_poultry', supplier:'delivery_cold_storage', customer:'poultry_coop', flow:'Refrigerated transport',
      effects:{ customerCostReduction:0.12, customerReliabilityBonus:0.15 },
      riskLinks:['cold_chain','food_safety'], vulnerabilityLabel:'Food-safety exposure along the route.' },
    { id:'delivery_to_feed', supplier:'delivery_cold_storage', customer:'feed_mill', flow:'Bulk transport',
      effects:{ customerCostReduction:0.08, customerRevenueBonus:0.10 },
      riskLinks:['fuel','route_concentration'], vulnerabilityLabel:'Route dependence.' },
    { id:'delivery_to_bakery', supplier:'delivery_cold_storage', customer:'bakery', flow:'Route distribution',
      effects:{ customerRevenueBonus:0.15, customerReliabilityBonus:0.10 },
      riskLinks:['fuel','demand'], vulnerabilityLabel:'Overcapacity if sales fall.' },
    { id:'delivery_to_restaurant', supplier:'delivery_cold_storage', customer:'farmhouse_restaurant', flow:'Reliable ingredient delivery',
      effects:{ customerReliabilityBonus:0.25, customerCostReduction:0.08 },
      riskLinks:['fuel','cold_chain'], vulnerabilityLabel:'Restaurant becomes dependent on logistics uptime.' },
    { id:'delivery_to_store', supplier:'delivery_cold_storage', customer:'general_store', flow:'Warehousing and routes',
      effects:{ customerCostReduction:0.10, customerRevenueBonus:0.10 },
      riskLinks:['demand','fuel'], vulnerabilityLabel:'Storage cost and demand mismatch.' },
  ];

  const SHOCKS = [
    { id:'drought', label:'Drought', riskLinks:['weather'],
      initial:['grain_farm','vegetable_farm'],
      primary:{ costMult:1.18, revenueMult:0.88 },
      secondary:{ costMult:1.10, revenueMult:0.94 },
      note:'Drought stresses crops — feed, livestock, and food-channel costs rise along the chain.' },
    { id:'animal_disease', label:'Animal disease outbreak', riskLinks:['animal_health','biosecurity'],
      initial:['dairy_barn','poultry_coop'],
      primary:{ costMult:1.12, revenueMult:0.78 },
      secondary:{ costMult:1.06, revenueMult:0.92 },
      note:'Animal disease cuts livestock output — bakery, restaurant, store, and logistics feel the shortage.' },
    { id:'cold_storage_failure', label:'Cold-storage failure', riskLinks:['cold_chain'],
      initial:['delivery_cold_storage'],
      primary:{ costMult:1.20, revenueMult:0.85 },
      secondary:{ costMult:1.08, revenueMult:0.90 },
      note:'Refrigeration failure — perishable inventory losses cascade across dairy, poultry, produce, bakery, and retail.' },
    { id:'fuel_spike', label:'Fuel-price spike', riskLinks:['fuel'],
      initial:['delivery_cold_storage'],
      primary:{ costMult:1.22 },
      secondary:{ costMult:1.08 },
      note:'Fuel costs jump — transport-dependent businesses pay more across the farm network.' },
    { id:'technician_leaves', label:'Equipment technician leaves', riskLinks:['skilled_labor'],
      initial:['equipment_repair'],
      primary:{ costMult:1.15, revenueMult:0.90 },
      secondary:{ costMult:1.07 },
      note:'Key technician exits — breakdown risk and repair costs rise for machinery-intensive farms.' },
    { id:'restaurant_reputation', label:'Restaurant reputation crisis', riskLinks:['reputation','food_safety'],
      initial:['farmhouse_restaurant'],
      primary:{ revenueMult:0.75 },
      secondary:{ revenueMult:0.92 },
      note:'A food-service reputation hit — branded bakery and store traffic softens with it.' },
    { id:'consumer_slowdown', label:'Consumer slowdown', riskLinks:['demand'],
      initial:['farmhouse_restaurant','general_store'],
      primary:{ revenueMult:0.85 },
      secondary:{ revenueMult:0.92, costMult:1.04 },
      note:'Consumers pull back — upstream producers lose volume and waste rises.' },
    { id:'feed_contamination', label:'Feed contamination', riskLinks:['contamination','feed_price'],
      initial:['feed_mill'],
      primary:{ costMult:1.18, revenueMult:0.82 },
      secondary:{ costMult:1.10, revenueMult:0.88 },
      note:'Contaminated feed — dairy and poultry productivity fall, with quality risk downstream.' },
  ];

  function isActive(state) {
    return !!(state && state.mode === 'arcade');
  }

  function templateById(id) {
    return TEMPLATES.find((t) => t.id === id) || null;
  }

  function isRealEstateAsset(templateId) {
    const t = templateById(templateId);
    return !!(t && t.assetClass === 'real_estate');
  }

  /** Businesses + farm infrastructure held as real estate (for ownership / synergies). */
  function portfolioNodes(state) {
    const biz = state.portfolio.businesses || [];
    const re = (state.portfolio.realEstate || []).filter((r) => isRealEstateAsset(r.templateId));
    return biz.concat(re);
  }

  function ownedIds(state) {
    return new Set(portfolioNodes(state).map((b) => b.templateId).filter(Boolean));
  }

  function pick(arr) {
    return arr[Math.floor(Math.random() * arr.length)];
  }

  function clamp(v, a, b) {
    return Math.max(a, Math.min(b, v));
  }

  /** Weight missing strategic links so opportunities feel purposeful. */
  function templateWeights(state) {
    const owned = ownedIds(state);
    const w = {};
    TEMPLATES.forEach((t) => { w[t.id] = 1; });

    const bump = (id, n) => { if (w[id] != null) w[id] += n; };

    if (owned.has('farmhouse_restaurant')) {
      if (!owned.has('vegetable_farm')) bump('vegetable_farm', 3);
      if (!owned.has('delivery_cold_storage')) bump('delivery_cold_storage', 2.5);
      if (!owned.has('bakery')) bump('bakery', 2);
      if (!owned.has('dairy_barn')) bump('dairy_barn', 1.5);
      if (!owned.has('poultry_coop')) bump('poultry_coop', 1.5);
    }
    if ((owned.has('dairy_barn') || owned.has('poultry_coop')) && !owned.has('feed_mill')) {
      bump('feed_mill', 3.5);
    }
    const perishable = ['vegetable_farm','dairy_barn','poultry_coop','bakery','farmhouse_restaurant','general_store']
      .filter((id) => owned.has(id)).length;
    if (perishable >= 2 && !owned.has('delivery_cold_storage')) bump('delivery_cold_storage', 3.5);

    const machinery = ['grain_farm','vegetable_farm','dairy_barn','poultry_coop','feed_mill','bakery']
      .filter((id) => owned.has(id)).length;
    if (machinery >= 2 && !owned.has('equipment_repair')) bump('equipment_repair', 3);

    const producers = ['grain_farm','vegetable_farm','dairy_barn','poultry_coop','bakery']
      .filter((id) => owned.has(id)).length;
    if (producers >= 2) {
      if (!owned.has('general_store')) bump('general_store', 2.5);
      if (!owned.has('farmhouse_restaurant')) bump('farmhouse_restaurant', 2);
    }
    if ((owned.has('general_store') || owned.has('farmhouse_restaurant')) && producers < 2) {
      bump('vegetable_farm', 1.5);
      bump('dairy_barn', 1.5);
      bump('poultry_coop', 1.5);
      bump('bakery', 1.5);
    }

    // Prefer not to spam duplicates of the same template early
    const nodes = portfolioNodes(state);
    TEMPLATES.forEach((t) => {
      const count = nodes.filter((b) => b.templateId === t.id).length;
      if (count >= 1) w[t.id] *= 0.35;
      if (count >= 2) w[t.id] *= 0.2;
    });

    // Phase B: stronger bias once the player owns 2+ assets — missing links dominate
    if (nodes.length >= 2) {
      CONNECTIONS.forEach((conn) => {
        if (owned.has(conn.supplier) && !owned.has(conn.customer)) bump(conn.customer, 4.5);
        if (owned.has(conn.customer) && !owned.has(conn.supplier)) bump(conn.supplier, 4.5);
      });
      TEMPLATES.forEach((t) => {
        (t.dependencyPartners || []).forEach((depId) => {
          if (!owned.has(depId) && owned.has(t.id)) bump(depId, 3);
          if (owned.has(depId) && !owned.has(t.id)) bump(t.id, 2.5);
        });
      });
      if (!owned.has('delivery_cold_storage') && nodes.length >= 2) bump('delivery_cold_storage', 2);
      if (!owned.has('equipment_repair') && nodes.length >= 2) bump('equipment_repair', 2);
    }

    return w;
  }

  function pickFromWeighted(templates, state) {
    const w = templateWeights(state);
    const entries = templates.map((t) => ({ t, weight: Math.max(0.05, w[t.id] || 0.05) }));
    const total = entries.reduce((a, e) => a + e.weight, 0);
    let r = Math.random() * total;
    for (const e of entries) {
      r -= e.weight;
      if (r <= 0) return e.t;
    }
    return pick(templates);
  }

  /** Operating farm businesses only — infrastructure is offered as real estate. */
  function pickTemplate(state) {
    return pickFromWeighted(BUSINESS_TEMPLATES, state);
  }

  function pickRealEstateTemplate(state) {
    return pickFromWeighted(REAL_ESTATE_TEMPLATES, state);
  }

  function layerFor(templateId) {
    const t = templateById(templateId);
    return t ? t.layerLabel : '';
  }

  function autopilotFor(templateId) {
    const t = templateById(templateId);
    return t && t.autopilot != null ? t.autopilot : 3;
  }

  /** Turns without Improve or relationship resolution before neglect pressure applies. */
  const AUTOPILOT_NEGLECT_TURNS = 4;

  /** Urgent spawn weight — Restaurant ↑, Grain ↓ (autopilot 1 ≈ 1.6×, autopilot 5 ≈ 0.5×). */
  function urgentFreqMultFor(templateId) {
    const ap = autopilotFor(templateId);
    return clamp(1.85 - ap * 0.27, 0.48, 1.85);
  }

  /** How harsh neglect is for this asset type (inverse of autopilot). */
  function neglectSeverity(templateId) {
    const ap = autopilotFor(templateId);
    return clamp(1.4 - ap * 0.22, 0.22, 1.2);
  }

  function turnsSinceCare(business, turn) {
    if (!business) return 0;
    const last = business.lastCareTurn != null
      ? business.lastCareTurn
      : (business.acquiredTurn != null ? business.acquiredTurn : turn);
    return Math.max(0, turn - last);
  }

  function neglectThresholdFor(business) {
    const U = global.BusinessUpgrades;
    if (U && business) return U.neglectThreshold(business, business.templateId);
    return AUTOPILOT_NEGLECT_TURNS;
  }

  function isNeglected(business, turn) {
    return turnsSinceCare(business, turn) >= neglectThresholdFor(business);
  }

  /** Extra urgent pressure when a low-touch asset hasn't received care in N+ turns. */
  function neglectUrgentMult(business, turn) {
    const threshold = neglectThresholdFor(business);
    const since = turnsSinceCare(business, turn);
    if (since < threshold) return 1;
    const sev = neglectSeverity(business.templateId);
    const excess = since - threshold + 1;
    let mult = 1 + sev * 0.18 * Math.min(excess, 4);
    const U = global.BusinessUpgrades;
    if (U && business) mult *= U.neglectUrgentDampen(business);
    return mult;
  }

  /** High-touch assets carry larger stakes when urgent problems fire. */
  function urgentStakeMult(templateId) {
    const ap = autopilotFor(templateId);
    return clamp(1.5 - ap * 0.18, 0.55, 1.5);
  }

  function autopilotBurdenLabel(templateId) {
    const ap = autopilotFor(templateId);
    if (ap <= 1) return 'High-touch asset — needs constant attention';
    if (ap === 2) return 'Management-intensive — neglect shows quickly';
    if (ap >= 4) return 'Mostly self-running — lower urgent pressure';
    return '';
  }

  function markBusinessCare(business, turn) {
    if (business) business.lastCareTurn = turn;
  }

  /** Low-autopilot assets recover more from care-style improvements. */
  function improveCareRecoveryMult(templateId) {
    const ap = autopilotFor(templateId);
    return clamp(1 + (3 - ap) * 0.12, 0.88, 1.36);
  }

  function improveNoteForAutopilot(templateId, baseNote) {
    const ap = autopilotFor(templateId);
    if (ap <= 1) return `${baseNote} High-touch asset — care upgrades restore more reliability here.`;
    if (ap >= 4) return `${baseNote} Mostly automated — smaller relationship swings from upkeep.`;
    return baseNote;
  }

  /**
   * Apply quarterly neglect pressure before urgent-problem generation.
   * Returns log notes for newly strained assets.
   */
  function applyNeglectPressure(state) {
    if (!isActive(state)) return [];
    const notes = [];
    (state.portfolio.businesses || []).forEach((b) => {
      if (!b.templateId || !isNeglected(b, state.turn)) return;
      const sev = neglectSeverity(b.templateId);
      const ap = autopilotFor(b.templateId);
      const threshold = neglectThresholdFor(b);
      const excess = Math.min(turnsSinceCare(b, state.turn) - threshold + 1, 3);
      const touchMult = ap <= 2 ? 1.2 : 0.62;
      const clientDrop = Math.round(2.5 * sev * excess * touchMult);
      const supDrop = Math.round(2 * sev * excess * touchMult);
      b.clientHealth = clamp((b.clientHealth ?? 72) - clientDrop, 0, 100);
      b.supplierHealth = clamp((b.supplierHealth ?? 72) - supDrop, 0, 100);
      if (ap <= 2) {
        b.crisisMult = clamp((b.crisisMult ?? 1) * (1 - 0.035 * sev * excess), 0.45, 1);
      }
      const warnKey = `_neglectWarnTurn_${state.turn}`;
      if (excess >= 1 && b[warnKey] !== true) {
        b[warnKey] = true;
        notes.push({
          name: b.name,
          templateId: b.templateId,
          turns: turnsSinceCare(b, state.turn),
          label: autopilotBurdenLabel(b.templateId),
        });
      }
    });
    return notes;
  }

  function baselineCapacityLoad(templateId, cap) {
    if (!cap || cap <= 0) return 0;
    const t = templateById(templateId);
    const frac = (t && t.baselineCapacityFrac != null) ? t.baselineCapacityFrac : 0.38;
    return Math.round(cap * frac);
  }

  /** UI-only load from existing off-portfolio clients (already in revenuePerTurn). Does not affect allocation. */
  function capacityDisplayMetrics(templateId, chainDemand, cap) {
    const baseline = baselineCapacityLoad(templateId, cap);
    const chain = chainDemand || 0;
    const displayDemand = Math.min(cap || 0, baseline + chain);
    const displayUtilPct = cap > 0 ? Math.round(Math.min(150, (displayDemand / cap) * 100)) : 0;
    return { baselineLoad: baseline, chainDemand: chain, displayDemand, displayUtilPct };
  }

  function capacityFor(templateId) {
    const t = templateById(templateId);
    return t && t.capacityUnits != null ? t.capacityUnits : null;
  }

  function isAllocatableTemplate(templateId) {
    const t = templateById(templateId);
    return !!(t && t.capacityUnits != null && ['primary_production', 'processing', 'infrastructure'].includes(t.layer));
  }

  function defaultSupplyPolicy() {
    return 'portfolio_first';
  }

  function getSupplyPolicy(state, templateId) {
    if (state && state.supplyPolicies && state.supplyPolicies[templateId]) {
      return state.supplyPolicies[templateId];
    }
    if (hasStrategicEdge(state, 'monopoly_tollkeeper') && isInfrastructureTemplate(templateId)) {
      return 'portfolio_first';
    }
    return defaultSupplyPolicy();
  }

  function uniqueOwnedCustomersForSupplier(state, supplierTemplateId) {
    const owned = ownedIds(state);
    const customers = new Set();
    CONNECTIONS.forEach((conn) => {
      if (conn.supplier === supplierTemplateId && owned.has(conn.customer)) {
        customers.add(conn.customer);
      }
    });
    return customers.size;
  }

  /** Agri-Conglomerate: +5% effective capacity per unique owned downstream customer, cap +20%. */
  function agriConglomerateCapacityMult(state, templateId) {
    if (!hasStrategicEdge(state, 'agri_conglomerate') || !isAllocatableTemplate(templateId)) return 1;
    const n = uniqueOwnedCustomersForSupplier(state, templateId);
    return 1 + Math.min(0.2, n * 0.05);
  }

  function effectiveCapacity(state, templateId) {
    const base = capacityFor(templateId);
    if (!base) return base;
    let mult = agriConglomerateCapacityMult(state, templateId);
    const U = global.BusinessUpgrades;
    if (state && U && U.isActive(state)) {
      U.ensurePortfolioUpgrades(state);
      mult *= U.businessCapacityMult(state, templateId);
    }
    return Math.round(base * mult);
  }

  /** Monopoly Tollkeeper: +10% external contract revenue per 3 regional customers served, cap +30%. */
  function monopolyTollkeeperExternalMult(state, templateId) {
    if (!hasStrategicEdge(state, 'monopoly_tollkeeper') || !isInfrastructureTemplate(templateId)) return 1;
    const served = uniqueOwnedCustomersForSupplier(state, templateId);
    return 1 + Math.min(0.3, Math.floor(served / 3) * 0.1);
  }

  function connectionDemandWeight(connectionId, state) {
    const base = CONNECTION_DEMAND[connectionId] != null ? CONNECTION_DEMAND[connectionId] : 20;
    if (!state) return base;
    const U = global.BusinessUpgrades;
    if (!U || !U.isActive(state)) return base;
    const conn = CONNECTIONS.find((c) => c.id === connectionId);
    if (!conn) return base;
    return Math.round(base * U.businessDemandMult(state, conn.customer));
  }

  const INFRASTRUCTURE_TEMPLATES = new Set(['equipment_repair', 'delivery_cold_storage']);
  const EXPORT_VOLUME_CAP_FRAC = 0.28;
  const EXPORT_FLOOR_YIELD = 0.42;
  const INFRA_EXTERNAL_YIELD = 0.58;

  function hasStrategicEdge(state, edgeId) {
    return !!(state && state.strategicEdges && state.strategicEdges.includes(edgeId));
  }

  function isInfrastructureTemplate(templateId) {
    return INFRASTRUCTURE_TEMPLATES.has(templateId);
  }

  function isUpstreamExportEligible(templateId) {
    const t = templateById(templateId);
    return !!(t && (t.layer === 'primary_production' || t.layer === 'processing'));
  }

  function exportChannelEnabled(state, templateId) {
    if (!isUpstreamExportEligible(templateId)) return false;
    if (state.supplyExportDisabled && state.supplyExportDisabled[templateId]) return false;
    return true;
  }

  /** Owned downstream link demand only — export uses spare capacity separately. */
  function computeOwnedDownstreamDemand(state, supplierTemplateId) {
    const owned = ownedIds(state);
    let demand = 0;
    CONNECTIONS.forEach((conn) => {
      if (conn.supplier !== supplierTemplateId || !owned.has(conn.customer)) return;
      demand += connectionDemandWeight(conn.id, state);
    });
    return demand;
  }

  function computeDownstreamDemand(state, supplierTemplateId) {
    return computeOwnedDownstreamDemand(state, supplierTemplateId);
  }

  function computeExportSlotUnits(state, supplierTemplateId, ownedDemand, cap) {
    if (!exportChannelEnabled(state, supplierTemplateId) || !cap || cap <= 0) return 0;
    if (ownedDemand >= cap) return 0;
    const spare = cap - ownedDemand;
    let capExport = Math.round(cap * EXPORT_VOLUME_CAP_FRAC);
    if (hasStrategicEdge(state, 'bulk_commodity_exporter')) {
      capExport = Math.round(capExport * 1.15);
    }
    return Math.min(spare, capExport);
  }

  function nodeForTemplate(state, templateId) {
    return portfolioNodes(state).find((n) => n.templateId === templateId) || null;
  }

  function computeCapacityEconomics(state, templateId, ownedDemand, cap) {
    const utilPct = cap > 0 ? Math.round((ownedDemand / cap) * 100) : 0;
    const spareCapacity = cap > 0 ? Math.max(0, cap - ownedDemand) : 0;
    const exportUnits = computeExportSlotUnits(state, templateId, ownedDemand, cap);
    const result = {
      externalContractRevenue: 0,
      exportRevenue: 0,
      exportUnits,
      exportLabel: '',
      internalServiceValue: 0,
      strainOpexMult: 1,
      externalDropped: false,
      spareCapacity,
      ownedDemand,
      effectiveCapacity: cap,
      agriCapacityMult: agriConglomerateCapacityMult(state, templateId),
    };

    if (utilPct > 100) {
      result.externalDropped = true;
      result.strainOpexMult = 1.12;
      return result;
    }
    if (utilPct > 85) result.strainOpexMult = 1.08;

    if (isInfrastructureTemplate(templateId)) {
      const asset = nodeForTemplate(state, templateId);
      const baseRent = asset
        ? (asset.rentPerTurn || 0) * (1 - (asset.vacancyRisk || 0) * 0.4)
        : ((templateById(templateId)?.rentRange || [14000])[0]);
      let spareRatio = cap > 0 ? spareCapacity / cap : 0;
      let yieldMult = INFRA_EXTERNAL_YIELD * spareRatio;
      if (utilPct > 85) yieldMult *= 0.42;
      result.externalContractRevenue = Math.round(baseRent * yieldMult * monopolyTollkeeperExternalMult(state, templateId));
      if (spareRatio > 0.08) {
        result.exportLabel = `External contracts · ${Math.round(spareRatio * 100)}% spare capacity`;
      }
    }

    if (exportUnits > 0) {
      const asset = nodeForTemplate(state, templateId);
      const baseRev = asset ? (asset.revenuePerTurn || asset.rentPerTurn || 0) : 0;
      const floorPerUnit = cap > 0 ? (baseRev / cap) * EXPORT_FLOOR_YIELD : 0;
      result.exportRevenue = Math.round(floorPerUnit * exportUnits);
      result.exportLabel = `Export (floor) · ${exportUnits} cap units`;
    }

    return result;
  }

  function computeInternalServiceValue(templateId, synergies) {
    return (synergies || [])
      .filter((y) => y.supplierTemplateId === templateId && y.internalLink)
      .reduce((a, y) => a + (y.estimatedCostSaving || 0), 0);
  }

  /** Infrastructure RE: external contract rent + strain opex; internal value stays in synergies. */
  function applyInfrastructureToRealEstate(asset, state, synergies) {
    if (!asset || !isInfrastructureTemplate(asset.templateId)) return null;
    const cap = effectiveCapacity(state, asset.templateId);
    const ownedDemand = computeOwnedDownstreamDemand(state, asset.templateId);
    const econ = computeCapacityEconomics(state, asset.templateId, ownedDemand, cap);
    const baseRent = asset.rentPerTurn * (1 - (asset.vacancyRisk || 0) * 0.4);
    let rent = baseRent + (econ.externalContractRevenue || 0);
    let opex = Math.round(asset.operatingExpenses * (econ.strainOpexMult || 1));
    const U = global.BusinessUpgrades;
    if (U && state && U.isActive(state)) {
      U.ensureBusinessUpgrades(asset);
      opex = Math.round(opex * U.businessOpexMult(asset));
    }
    const internalServiceValue = computeInternalServiceValue(asset.templateId, synergies);
    return {
      rent: Math.round(rent),
      opex,
      baseRent: Math.round(baseRent),
      externalContractRevenue: econ.externalContractRevenue || 0,
      internalServiceValue,
      strainOpexMult: econ.strainOpexMult,
      externalDropped: econ.externalDropped,
      exportLabel: econ.exportLabel,
      utilizationPct: cap > 0 ? Math.round((ownedDemand / cap) * 100) : 0,
    };
  }

  function applyExportToBusiness(biz, state) {
    if (!biz || !isUpstreamExportEligible(biz.templateId)) {
      return { exportRevenue: 0, exportLabel: '' };
    }
    const cap = effectiveCapacity(state, biz.templateId);
    const ownedDemand = computeOwnedDownstreamDemand(state, biz.templateId);
    const econ = computeCapacityEconomics(state, biz.templateId, ownedDemand, cap);
    let exportRevenue = econ.exportRevenue || 0;
    const U = global.BusinessUpgrades;
    if (U && state && U.isActive(state) && exportRevenue > 0) {
      const tmpl = templateById(biz.templateId);
      const exportWeight = tmpl && tmpl.demandExportWeight != null ? tmpl.demandExportWeight : 0.25;
      const demandMult = U.businessDemandMult(state, biz.templateId);
      exportRevenue = Math.round(exportRevenue * (1 + (demandMult - 1) * exportWeight));
    }
    return {
      exportRevenue,
      exportLabel: econ.exportLabel || '',
      externalDropped: econ.externalDropped,
    };
  }

  /** Relationship pressure when infrastructure/upstream exceeds 100% owned demand. */
  function applyOverCapacityPenalties(state) {
    if (!isActive(state)) return [];
    const notes = [];
    const owned = ownedIds(state);
    TEMPLATES.forEach((t) => {
      if (!isAllocatableTemplate(t.id) || !owned.has(t.id)) return;
      const cap = effectiveCapacity(state, t.id);
      const ownedDemand = computeOwnedDownstreamDemand(state, t.id);
      const util = utilizationRatio(ownedDemand, cap);
      if (!util.overCapacity) return;
      CONNECTIONS.filter((c) => c.supplier === t.id).forEach((conn) => {
        (state.portfolio.businesses || []).filter((b) => b.templateId === conn.customer).forEach((b) => {
          if (b._overCapPenaltyTurn === state.turn) return;
          b._overCapPenaltyTurn = state.turn;
          b.supplierHealth = clamp((b.supplierHealth ?? 72) - 8, 0, 100);
          b.clientHealth = clamp((b.clientHealth ?? 72) - 3, 0, 100);
        });
      });
      notes.push(`${t.name} over capacity — downstream relationships strained, external contracts suspended`);
    });
    return notes;
  }

  function utilizationRatio(demand, capacity) {
    if (!capacity || capacity <= 0) {
      return { ratio: 1, overCapacity: false, utilizationPct: 0, demand: demand || 0, capacity: 0 };
    }
    const raw = demand / capacity;
    return {
      ratio: Math.min(1, raw),
      overCapacity: raw > 1,
      utilizationPct: Math.round(Math.min(150, raw * 100)),
      demand,
      capacity,
    };
  }

  function computeSupplierUtilization(state) {
    const out = {};
    const owned = ownedIds(state);
    TEMPLATES.forEach((t) => {
      if (!isAllocatableTemplate(t.id) || !owned.has(t.id)) return;
      const cap = effectiveCapacity(state, t.id);
      const baseCap = capacityFor(t.id);
      const ownedDemand = computeOwnedDownstreamDemand(state, t.id);
      const util = utilizationRatio(ownedDemand, cap);
      const econ = computeCapacityEconomics(state, t.id, ownedDemand, cap);
      const display = capacityDisplayMetrics(t.id, ownedDemand, cap);
      out[t.id] = Object.assign({
        templateId: t.id,
        name: t.name,
        policy: getSupplyPolicy(state, t.id),
        demand: ownedDemand,
        capacity: cap,
        baseCapacity: baseCap,
        baselineLoad: display.baselineLoad,
        displayDemand: display.displayDemand,
        displayUtilPct: display.displayUtilPct,
      }, util, econ);
    });
    return out;
  }

  function bidScoreForConnection(conn) {
    const fx = conn.effects || {};
    return (fx.supplierRevenueBonus || 0) * 100 + (fx.customerRevenueBonus || 0) * 80 + (fx.customerCostReduction || 0) * 40;
  }

  function allocateSupplierCapacity(state, supplierTemplateId, linkRows) {
    const cap = effectiveCapacity(state, supplierTemplateId);
    const policy = getSupplyPolicy(state, supplierTemplateId);
    const links = linkRows.map((l) => Object.assign({}, l, { weight: connectionDemandWeight(l.connectionId, state) }));
    const totalDemand = links.reduce((a, l) => a + l.weight, 0);
    if (!cap || totalDemand <= cap) {
      links.forEach((l) => { l.fulfill = 1; });
      return { links, utilization: utilizationRatio(totalDemand, cap || Math.max(1, totalDemand)), overCapacity: false };
    }
    links.forEach((l) => { l.fulfill = 0; });
    if (policy === 'balanced' || policy === 'contract_first') {
      const frac = cap / totalDemand;
      const mult = policy === 'contract_first' ? Math.min(1, frac * 1.02) : frac;
      links.forEach((l) => { l.fulfill = mult; });
    } else {
      let sorted;
      if (policy === 'highest_bidder') {
        sorted = links.slice().sort((a, b) => bidScoreForConnection(b.conn) - bidScoreForConnection(a.conn));
      } else {
        sorted = links.slice().sort(
          (a, b) => (CUSTOMER_ALLOC_PRIORITY[b.conn.customer] || 0) - (CUSTOMER_ALLOC_PRIORITY[a.conn.customer] || 0)
        );
      }
      let remaining = cap;
      sorted.forEach((l) => {
        if (remaining <= 0) return;
        const take = Math.min(l.weight, remaining);
        l.fulfill = take / l.weight;
        remaining -= take;
      });
    }
    return { links, utilization: utilizationRatio(totalDemand, cap), overCapacity: true };
  }

  function detectSupplyShortages(state) {
    // Shortage resolution: UI blocks Advance Turn until player confirms policy (0 AP).
    // Last-chosen policy persists in state.supplyPolicies until changed on next shortage.
    return Object.values(computeSupplierUtilization(state)).filter((u) => u.overCapacity);
  }

  const LEVERAGE_CAP = 0.55;

  function connectionCriticality(conn) {
    const fx = conn.effects || {};
    return clamp(
      (fx.customerCostReduction || 0) * 2.2
        + (fx.customerReliabilityBonus || 0) * 1.6
        + (fx.customerRevenueBonus || 0) * 1.3
        + (fx.supplierRevenueBonus || 0) * 0.8
        + (fx.supplierDemandStability || 0) * 1.1,
      0.12,
      1
    );
  }

  function flowCategory(flow) {
    const f = (flow || '').toLowerCase();
    if (f.includes('feed')) return 'feed';
    if (f.includes('grain') || f.includes('wheat') || f.includes('corn') || f.includes('flour')) return 'grain';
    if (f.includes('cold') || f.includes('transport') || f.includes('storage') || f.includes('delivery') || f.includes('warehous')) return 'logistics';
    if (f.includes('equipment') || f.includes('maintenance') || f.includes('service') || f.includes('machinery')) return 'equipment';
    if (f.includes('vegetable') || f.includes('herb') || f.includes('produce')) return 'produce';
    if (f.includes('dairy') || f.includes('milk') || f.includes('cream') || f.includes('butter') || f.includes('cheese')) return 'dairy';
    if (f.includes('egg') || f.includes('poultry')) return 'poultry';
    if (f.includes('bread') || f.includes('bakery') || f.includes('dessert')) return 'bakery';
    return 'other';
  }

  function alternativesForCustomer(customerTemplateId, owned, categoryConn) {
    let possible = CONNECTIONS.filter((c) => c.customer === customerTemplateId);
    if (categoryConn) {
      const cat = flowCategory(categoryConn.flow);
      const filtered = possible.filter((c) => flowCategory(c.flow) === cat);
      if (filtered.length) possible = filtered;
    }
    if (!possible.length) return 0.55;
    const unowned = possible.filter((c) => !owned.has(c.supplier)).length;
    return clamp(unowned / possible.length, 0.08, 0.92);
  }

  function playerShareForSupplier(state, supplierTemplateId) {
    if (!ownedIds(state).has(supplierTemplateId)) return 0;
    const util = computeSupplierUtilization(state)[supplierTemplateId];
    if (util && util.capacity > 0) return clamp(util.ratio, 0.4, 1);
    return 0.92;
  }

  function leverageBuffer(context, focalTemplate) {
    let buffer = 0.28;
    const cp = focalTemplate && focalTemplate.complexityProfile;
    if (cp) {
      if (cp.supplyDependency === 'high') buffer += 0.14;
      else if (cp.supplyDependency === 'low') buffer -= 0.06;
      if (cp.perishability === 'high') buffer -= 0.05;
    }
    if (context.problemType === 'supplier' && context.supplierHealth != null) {
      buffer += (context.supplierHealth / 100) * 0.18;
    }
    if (context.problemType === 'client' && context.clientHealth != null) {
      buffer += (context.clientHealth / 100) * 0.12;
    }
    if (context.diligenceDone) buffer -= 0.1;
    if (context.memoryTrust != null) buffer += context.memoryTrust * 0.12;
    return clamp(buffer, 0.06, 0.62);
  }

  function relevantLeverageLinks(state, context) {
    const owned = ownedIds(state);
    const focal = context.businessTemplateId || context.targetTemplateId;
    if (!focal) return [];
    const links = [];
    const add = (conn, role) => {
      if (links.some((l) => l.conn.id === conn.id && l.role === role)) return;
      links.push({ conn, role, supplierId: conn.supplier, customerId: conn.customer });
    };

    if (context.problemType === 'supplier' || context.negotiationKind === 'acquisition'
      || context.negotiationKind === 'realestate' || context.negotiationKind === 'rival_contest'
      || context.negotiationKind === 'levelup') {
      CONNECTIONS.forEach((conn) => {
        if (conn.customer === focal && owned.has(conn.supplier)) add(conn, 'owned_supplier');
      });
    }
    if (context.problemType === 'client') {
      CONNECTIONS.forEach((conn) => {
        if (conn.supplier === focal && owned.has(conn.customer)) add(conn, 'owned_customer');
      });
    }
    if (context.negotiationKind === 'acquisition' || context.negotiationKind === 'realestate') {
      CONNECTIONS.forEach((conn) => {
        if (conn.supplier === focal && owned.has(conn.customer)) add(conn, 'owned_customer');
      });
    }
    return links;
  }

  function qualitativeLeverage(score) {
    if (score >= 0.42) return 'HIGH';
    if (score >= 0.22) return 'MODERATE';
    if (score >= 0.08) return 'LOW';
    return 'MINIMAL';
  }

  function qualitativeInput(criticality) {
    if (criticality >= 0.72) return 'Critical';
    if (criticality >= 0.45) return 'Important';
    return 'Routine';
  }

  function qualitativeAlternatives(altScore) {
    if (altScore >= 0.62) return 'Many';
    if (altScore >= 0.32) return 'Some';
    return 'Limited';
  }

  function qualitativeShare(share) {
    if (share >= 0.78) return 'Strong';
    if (share >= 0.52) return 'Partial';
    return 'Weak';
  }

  /**
   * Deterministic supply-chain leverage for negotiations.
   * Formula: criticality × playerShare × (1 − alternatives) × (1 − buffer), capped at LEVERAGE_CAP.
   */
  function computeSupplyLeverage(state, counterparty, context) {
    context = context || {};
    if (!isActive(state)) {
      return { score: 0, relevant: false, displayLine: '', partialSummary: '' };
    }

    const links = relevantLeverageLinks(state, context);
    if (!links.length) {
      return { score: 0, relevant: false, displayLine: '', partialSummary: '' };
    }

    const owned = ownedIds(state);
    let best = null;
    let bestRaw = 0;

    links.forEach((link) => {
      const crit = connectionCriticality(link.conn);
      const share = link.role === 'owned_supplier'
        ? playerShareForSupplier(state, link.supplierId)
        : clamp(0.55 + (owned.has(link.customerId) ? 0.35 : 0), 0.35, 0.95);
      const alt = alternativesForCustomer(link.customerId, owned, link.conn);
      const partial = crit * share * (1 - alt);
      if (partial > bestRaw) {
        bestRaw = partial;
        best = { link, crit, share, alt, partial };
      }
    });

    const focalId = context.businessTemplateId || context.targetTemplateId;
    const focalTemplate = templateById(focalId);
    const buffer = leverageBuffer(context, focalTemplate);
    const score = Math.min(LEVERAGE_CAP, bestRaw * (1 - buffer));
    const relevant = score >= 0.06;

    const supplierName = best ? (templateById(best.link.supplierId)?.name || best.link.supplierId) : '';
    const customerName = best ? (templateById(best.link.customerId)?.name || best.link.customerId) : '';
    const controlledLink = best
      ? (best.link.role === 'owned_supplier'
        ? `${supplierName} → ${customerName}`
        : `${customerName} buys from ${supplierName || focalTemplate?.name || focalId}`)
      : '';

    const displayLine = relevant
      ? `Input: ${qualitativeInput(best.crit)} · Alternatives: ${qualitativeAlternatives(best.alt)} · Your share: ${qualitativeShare(best.share)} · Leverage: ${qualitativeLeverage(score)}`
      : '';

    const partialSummary = relevant
      ? `Regional supply influence detected (${qualitativeLeverage(score)}). Investigate for the full supply-position read.`
      : '';

    return {
      score,
      relevant,
      criticality: best ? best.crit : 0,
      playerShare: best ? best.share : 0,
      alternatives: best ? best.alt : 0,
      buffer,
      controlledLink,
      displayLine,
      partialSummary,
      leverageLabel: qualitativeLeverage(score),
    };
  }

  /** Adjust counterparty utility from deterministic supply leverage (engine remains authoritative). */
  function applyLeverageToUtility(utility, leverage, direction) {
    const L = clamp(leverage || 0, 0, LEVERAGE_CAP);
    if (L <= 0) return utility;
    const scale = 40;
    if (direction === 'acquisition' || direction === 'realestate' || direction === 'levelup' || direction === 'rival_contest') {
      return utility + L * scale * 0.52;
    }
    if (direction === 'relationship_supplier') {
      return utility - L * scale * 0.62;
    }
    if (direction === 'relationship_client') {
      return utility - L * scale * 0.48;
    }
    return utility;
  }

  function capacityStrainFactor(supplierTemplateId, customerCount, fulfillAvg, utilPct) {
    let strain = 1;
    if (supplierTemplateId === 'equipment_repair' || supplierTemplateId === 'delivery_cold_storage') {
      if (customerCount >= 5) strain = 0.7;
      else if (customerCount >= 3) strain = 0.85;
    }
    if (utilPct != null && utilPct > 85) strain *= 0.82;
    if (utilPct != null && utilPct > 100) strain *= 0.68;
    if (fulfillAvg != null && fulfillAvg < 0.85) strain *= 0.9 + fulfillAvg * 0.1;
    return strain;
  }

  /**
   * Detect active synergies from owned businesses matching the connection register.
   * Returns array of active synergy objects with absolute $ estimates filled later by caller if needed.
   */
  function computeSynergies(state) {
    const businesses = portfolioNodes(state);
    const byTemplate = {};
    businesses.forEach((b) => {
      if (!byTemplate[b.templateId]) byTemplate[b.templateId] = [];
      byTemplate[b.templateId].push(b);
    });

    const supplierLinks = {};
    CONNECTIONS.forEach((conn) => {
      const suppliers = byTemplate[conn.supplier] || [];
      const customers = byTemplate[conn.customer] || [];
      if (!suppliers.length || !customers.length) return;
      const supplier = suppliers[0];
      customers.forEach((customer) => {
        if (supplier.id === customer.id) return;
        if (!supplierLinks[conn.supplier]) supplierLinks[conn.supplier] = [];
        supplierLinks[conn.supplier].push({
          connectionId: conn.id,
          conn,
          supplier,
          customer,
          supplierId: supplier.id,
          customerId: customer.id,
        });
      });
    });

    const fulfillMap = {};
    const supplierUtil = {};
    Object.keys(supplierLinks).forEach((supplierTemplateId) => {
      const alloc = allocateSupplierCapacity(state, supplierTemplateId, supplierLinks[supplierTemplateId]);
      supplierUtil[supplierTemplateId] = alloc.utilization;
      alloc.links.forEach((l) => {
        fulfillMap[l.connectionId + ':' + l.customerId] = l.fulfill != null ? l.fulfill : 1;
      });
    });

    const active = [];
    CONNECTIONS.forEach((conn) => {
      const suppliers = byTemplate[conn.supplier] || [];
      const customers = byTemplate[conn.customer] || [];
      if (!suppliers.length || !customers.length) return;

      const supplier = suppliers[0];
      const util = supplierUtil[conn.supplier] || utilizationRatio(0, effectiveCapacity(state, conn.supplier) || 1);
      const fulfillValues = [];
      customers.forEach((customer) => {
        if (supplier.id === customer.id) return;
        const fulfill = fulfillMap[conn.id + ':' + customer.id];
        const f = fulfill != null ? fulfill : 1;
        fulfillValues.push(f);
        const fx = conn.effects || {};
        const strain = capacityStrainFactor(conn.supplier, customers.length, f, util.utilizationPct);
        const effectScale = f * strain;
        active.push({
          connectionId: conn.id,
          chainId: conn.id,
          supplierId: supplier.id,
          partnerId: supplier.id,
          anchorId: customer.id,
          customerId: customer.id,
          supplierTemplateId: conn.supplier,
          customerTemplateId: conn.customer,
          label: `${supplier.name} → ${customer.name}`,
          flow: conn.flow,
          internalLink: true,
          fulfillRatio: f,
          costReduction: (fx.customerCostReduction || 0) * effectScale,
          revenueBonusCustomer: (fx.customerRevenueBonus || 0) * effectScale,
          revenueBonusSupplier: 0,
          demandStability: 0,
          reliabilityBonus: (fx.customerReliabilityBonus || 0) * effectScale,
          addedRiskLabel: conn.vulnerabilityLabel,
          riskLinks: conn.riskLinks || [],
          capacityStrained: f < 0.85 || util.overCapacity || strain < 0.95,
          supplierUtilizationPct: util.utilizationPct,
          addedCostPerTurn: Math.round((180 + (fx.customerCostReduction || 0) * 800) * Math.max(0.5, f)),
        });
      });
    });

    // Two-link chain bonus: customer that is also a supplier in another active link
    const customerIds = new Set(active.map((a) => a.customerId));
    const supplierIds = new Set(active.map((a) => a.supplierId));
    active.forEach((a) => {
      if (supplierIds.has(a.customerId) && customerIds.has(a.supplierId)) {
        a.chainBonus = 0.04;
      } else if (supplierIds.has(a.customerId) || customerIds.has(a.supplierId)) {
        a.chainBonus = 0.03;
      } else {
        a.chainBonus = 0;
      }
    });

    return active;
  }

  /** Apply synergies to a single business for this turn; returns { rev, cost, notes, crisisMult }. */
  function applyToBusiness(biz, synergies, state, opts) {
    opts = opts || {};
    const asCustomer = synergies.filter((y) => y.customerId === biz.id);
    const asSupplier = synergies.filter((y) => y.supplierId === biz.id);
    let rev = biz.revenuePerTurn;
    let cost = biz.operatingCosts;
    let crisisMult = biz.crisisMult != null ? biz.crisisMult : 1;
    const notes = [];

    let costRed = 0;
    asCustomer.forEach((y) => {
      costRed += y.costReduction || 0;
      costRed += y.chainBonus || 0;
      if (y.revenueBonusCustomer) rev *= (1 + y.revenueBonusCustomer);
      if (y.reliabilityBonus) crisisMult *= (1 - Math.min(0.2, y.reliabilityBonus * 0.5));
      cost += y.addedCostPerTurn || 0;
    });
    asSupplier.forEach((y) => {
      if (y.revenueBonusSupplier && !y.internalLink) rev *= (1 + y.revenueBonusSupplier);
      if (y.demandStability && !y.internalLink) {
        rev *= (1 + y.demandStability * 0.5);
        crisisMult *= (1 - Math.min(0.12, y.demandStability * 0.4));
      }
    });

    // Horizontal: duplicate template
    const same = portfolioNodes(state).filter((b) => b.templateId === biz.templateId);
    if (same.length > 1) {
      cost *= 0.95;
      notes.push('horizontal overhead sharing');
    }

    costRed = clamp(costRed, 0, 0.35);
    if (opts.supplyChainBuilderBonus && asCustomer.length && !biz._firstSynergyBonusUsed) {
      const first = asCustomer[0];
      const fulfill = first.fulfillRatio != null ? first.fulfillRatio : 1;
      costRed = Math.min(0.38, costRed + 0.05 * fulfill);
      biz._firstSynergyBonusUsed = true;
      notes.push('supply-chain builder bonus');
    }
    cost *= (1 - costRed);

    if (hasStrategicEdge(state, 'agri_conglomerate') && isAllocatableTemplate(biz.templateId)) {
      const cap = effectiveCapacity(state, biz.templateId);
      const demand = computeOwnedDownstreamDemand(state, biz.templateId);
      if (cap > 0 && demand >= cap * 0.95 && demand <= cap) {
        cost = Math.round(cost * 0.92);
        notes.push('agri-conglomerate full-utilization opex bonus');
      }
    }

    const U = global.BusinessUpgrades;
    if (U && state && U.isActive(state)) {
      U.ensureBusinessUpgrades(biz);
      cost = Math.round(cost * U.businessOpexMult(biz));
      crisisMult *= U.businessCareCrisisMult(biz);
      const demandFactor = U.consumerDemandRevFactor(biz, state, synergies);
      if (demandFactor !== 1) {
        rev *= demandFactor;
        notes.push('marketing demand lift');
      }
    }

    const savings = Math.max(0, biz.operatingCosts - (cost - asCustomer.reduce((a, y) => a + (y.addedCostPerTurn || 0), 0)));
    // Attach display estimates onto synergy objects
    asCustomer.forEach((y) => {
      y.estimatedCostSaving = Math.round(biz.operatingCosts * ((y.costReduction || 0) + (y.chainBonus || 0)));
      y.estimatedRevenueLift = Math.round(biz.revenuePerTurn * (y.revenueBonusCustomer || 0));
    });
    asSupplier.forEach((y) => {
      y.estimatedSupplierLift = Math.round(biz.revenuePerTurn * ((y.revenueBonusSupplier || 0) + (y.demandStability || 0) * 0.5));
    });

    return {
      rev: Math.round(rev),
      cost: Math.round(Math.max(0, cost)),
      crisisMult: clamp(crisisMult, 0.35, 1.2),
      costReductionTotal: costRed,
      savings: Math.round(savings),
      notes,
    };
  }

  /** Chain-aware quarterly profit for one business (7.0 valuation). */
  function quarterlyProfitForBusiness(biz, state) {
    if (!biz || !state) return (biz.revenuePerTurn || 0) - (biz.operatingCosts || 0);
    const syns = computeSynergies(state);
    const applied = applyToBusiness(biz, syns, state, {});
    const exp = applyExportToBusiness(biz, state);
    return applied.rev + (exp.exportRevenue || 0) - applied.cost;
  }

  function strategicHint(state, templateId) {
    const tmpl = templateById(templateId);
    if (!tmpl) return '';
    const owned = portfolioNodes(state);
    if (!owned.length) {
      return tmpl.assetClass === 'real_estate'
        ? 'Farm infrastructure — grows like property and unlocks supply-chain links.'
        : 'Foundational Capital Farm operation.';
    }

    const hits = [];
    CONNECTIONS.forEach((conn) => {
      if (conn.supplier === templateId) {
        owned.filter((b) => b.templateId === conn.customer).forEach((b) => {
          const red = conn.effects.customerCostReduction || 0;
          const rev = conn.effects.customerRevenueBonus || 0;
          const baseCost = b.operatingCosts != null ? b.operatingCosts : b.operatingExpenses || 0;
          const baseRev = b.revenuePerTurn != null ? b.revenuePerTurn : b.rentPerTurn || 0;
          if (red) hits.push(`Would cut ${b.name} costs ~${Math.round(baseCost * red).toLocaleString('en-US')}/qtr (${conn.flow})`);
          else if (rev) hits.push(`Would lift ${b.name} revenue ~${Math.round(baseRev * rev).toLocaleString('en-US')}/qtr`);
        });
      }
      if (conn.customer === templateId) {
        owned.filter((b) => b.templateId === conn.supplier).forEach((b) => {
          const red = conn.effects.customerCostReduction || 0;
          const rentBase = (tmpl.rentRange || tmpl.revRange || [0])[0] * 0.7;
          if (red) hits.push(`Your ${b.name} would lower this operation's costs ~${Math.round(rentBase * red).toLocaleString('en-US')}/qtr`);
          const srev = conn.effects.supplierRevenueBonus || conn.effects.supplierDemandStability || 0;
          if (srev) hits.push(`Would stabilize demand for ${b.name}`);
        });
      }
    });

    const missing = (tmpl.dependencyPartners || []).filter((id) => !owned.some((b) => b.templateId === id));
    if (missing.length) {
      const names = missing.map((id) => (templateById(id) || { name: id }).name);
      hits.push(`Still needs: ${names.slice(0, 2).join(', ')}`);
    }
    return hits[0] || tmpl.blurb;
  }

  function missingDependencies(biz) {
    const tmpl = templateById(biz.templateId);
    if (!tmpl) return [];
    return (tmpl.dependencyPartners || []).map((id) => templateById(id)).filter(Boolean);
  }

  function pickShock(state) {
    const owned = ownedIds(state);
    const eligible = SHOCKS.filter((sh) => sh.initial.some((id) => owned.has(id)));
    if (!eligible.length) return null;
    return pick(eligible);
  }

  /**
   * Apply a farm shock with propagation through active connections sharing riskLinks.
   * Returns { label, note, affected: [{biz, kind}] }
   */
  function applyShock(state, shock) {
    if (!shock) return null;
    const businesses = portfolioNodes(state);
    const synergies = computeSynergies(state);
    const primary = businesses.filter((b) => shock.initial.includes(b.templateId));
    if (!primary.length) return null;

    const bulkExporter = hasStrategicEdge(state, 'bulk_commodity_exporter');
    const commodityShock = (shock.riskLinks || []).some((r) => r === 'commodity_price' || r === 'weather');

    function dampenMults(mults) {
      if (!bulkExporter || !commodityShock) return mults;
      const m = Object.assign({}, mults);
      if (m.revenueMult != null && m.revenueMult < 1) {
        m.revenueMult = 1 - (1 - m.revenueMult) * 0.6;
      } else if (m.revenueMult != null && m.revenueMult > 1) {
        m.revenueMult = 1 + (m.revenueMult - 1) * 0.75;
      }
      if (m.costMult != null && m.costMult > 1) {
        m.costMult = 1 + (m.costMult - 1) * 0.6;
      }
      return m;
    }

    const affectedIds = new Set();
    const logBits = [];

    function hit(biz, mults, tag) {
      if (affectedIds.has(biz.id)) return;
      affectedIds.add(biz.id);
      const isRe = !!biz.rentPerTurn && biz.assetClass === 'real_estate';
      if (mults.revenueMult) {
        if (isRe) biz.rentPerTurn = Math.round(biz.rentPerTurn * mults.revenueMult);
        else biz.revenuePerTurn = Math.round(biz.revenuePerTurn * mults.revenueMult);
      }
      if (mults.costMult) {
        if (isRe) biz.operatingExpenses = Math.round(biz.operatingExpenses * mults.costMult);
        else biz.operatingCosts = Math.round(biz.operatingCosts * mults.costMult);
      }
      logBits.push(`${biz.name}${tag}`);
    }

    primary.forEach((b) => hit(b, dampenMults(shock.primary || {}), ''));

    // Propagate to connected businesses on matching risk links
    const riskSet = new Set(shock.riskLinks || []);
    synergies.forEach((syn) => {
      const links = syn.riskLinks || [];
      if (!links.some((r) => riskSet.has(r))) return;
      const otherIds = [syn.supplierId, syn.customerId];
      otherIds.forEach((id) => {
        if (affectedIds.has(id)) return;
        // only propagate if one end was primary
        const touched = primary.some((p) => p.id === syn.supplierId || p.id === syn.customerId);
        if (!touched) return;
        const biz = businesses.find((b) => b.id === id);
        if (biz) hit(biz, shock.secondary || { costMult: 1.06 }, ' (chain)');
      });
    });

    return {
      label: shock.label,
      note: `${shock.note} Hit: ${logBits.join(', ')}.`,
      affectedCount: affectedIds.size,
    };
  }

  function layerComposition(state) {
    const counts = {
      primary_production: 0,
      processing: 0,
      infrastructure: 0,
      consumer_channel: 0,
    };
    portfolioNodes(state).forEach((n) => {
      const t = templateById(n.templateId);
      if (t && counts[t.layer] != null) counts[t.layer] += 1;
    });
    (state.portfolio.realEstate || []).forEach((r) => {
      const t = templateById(r.templateId);
      if (t && t.layer === 'infrastructure') counts.infrastructure += 1;
    });
    return counts;
  }

  function dominantLayer(state) {
    const counts = layerComposition(state);
    const total = Object.values(counts).reduce((a, n) => a + n, 0);
    let bestLayer = null;
    let bestCount = 0;
    Object.keys(counts).forEach((layer) => {
      if (counts[layer] > bestCount) {
        bestCount = counts[layer];
        bestLayer = layer;
      }
    });
    return {
      layer: bestLayer,
      label: bestLayer ? (LAYER_LABELS[bestLayer] || bestLayer) : 'Mixed',
      count: bestCount,
      total,
      counts,
    };
  }

  function policySummaryForState(state) {
    const util = computeSupplierUtilization(state);
    const rows = Object.values(util).map((u) => {
      const pol = SUPPLY_POLICIES[u.policy] || { label: u.policy };
      return { name: u.name, policyId: u.policy, policyLabel: pol.label, utilizationPct: u.utilizationPct };
    });
    return rows;
  }

  /** End-of-run supply-chain stats for Capital Farm report panel. */
  function buildRunChainReport(state, runStats) {
    runStats = runStats || {};
    const dom = dominantLayer(state);
    const risk = portfolioRiskSummary(state);
    const utilRows = risk.utilization || [];
    const samples = runStats.utilizationSamples || [];
    const avgUtil = samples.length
      ? Math.round(samples.reduce((a, n) => a + n, 0) / samples.length)
      : (utilRows.length
        ? Math.round(utilRows.reduce((a, u) => a + (u.utilizationPct || 0), 0) / utilRows.length)
        : null);
    const policyRows = policySummaryForState(state);
    const policyCounts = {};
    policyRows.forEach((r) => {
      policyCounts[r.policyLabel] = (policyCounts[r.policyLabel] || 0) + 1;
    });
    const policySummary = Object.keys(policyCounts).map((label) => `${label} (${policyCounts[label]})`).join(', ');
    const leverageWins = runStats.monopolyLeverageWins || 0;
    const policyChanges = runStats.policyChanges || [];
    return {
      dominantLayer: dom.label,
      dominantLayerKey: dom.layer,
      layerCounts: dom.counts,
      avgUtilizationPct: avgUtil,
      strainedAssets: utilRows.filter((u) => u.overCapacity || u.utilizationPct >= 85).map((u) => u.name),
      leverageWins,
      policySummary: policySummary || 'Default allocation (Portfolio First)',
      policyRows,
      policyChangeCount: policyChanges.length,
      externalRevenueTotal: risk.externalRevenueTotal || 0,
      activeLinks: risk.activeLinks || 0,
      shortages: (risk.shortages || []).map((u) => u.name),
    };
  }

  function classifyStrategy(state) {
    const owned = ownedIds(state);
    const has = (id) => owned.has(id);
    const syn = computeSynergies(state);
    const layers = layerComposition(state);

    if (has('grain_farm') && has('feed_mill') && (has('poultry_coop') || has('dairy_barn')) && has('farmhouse_restaurant')) {
      return 'Field-to-table restaurant empire — high captured margin and supply control, with agricultural and food-safety exposure.';
    }
    if (has('general_store') && has('delivery_cold_storage') && (has('vegetable_farm') || has('dairy_barn') || has('bakery'))) {
      return 'Farm retail network — direct-to-consumer pricing and demand data, vulnerable to waste and soft demand.';
    }
    if (has('equipment_repair') && has('delivery_cold_storage') && syn.length >= 4) {
      return 'Infrastructure monopoly — logistics and repair improve nearly every asset, if capacity stays utilized.';
    }
    if (has('feed_mill') && (has('dairy_barn') || has('poultry_coop')) && (has('farmhouse_restaurant') || has('general_store'))) {
      return 'Protein chain — recurring internal demand and cost control, exposed to animal health and cold-chain risk.';
    }
    if (has('bakery') && has('farmhouse_restaurant') && has('general_store') && (has('grain_farm') || has('dairy_barn'))) {
      return 'Artisan brand flywheel — raw inputs become premium products and brand traffic, with shared reputation risk.';
    }

    if (hasStrategicEdge(state, 'bulk_commodity_exporter') && layers.primary_production >= 2) {
      return 'Commodity export floor — upstream volume sold at logistics discount, hedged against weather but never beating a tight vertical link.';
    }
    if (hasStrategicEdge(state, 'monopoly_tollkeeper') && layers.infrastructure >= 1 && syn.length >= 2) {
      return 'Regional tollbooth — external contracts on spare infra capacity; Portfolio First unless you chose otherwise.';
    }
    if (hasStrategicEdge(state, 'agri_conglomerate') && layers.primary_production >= 2) {
      return 'Upstream conglomerate — scale across producers, wins on utilization efficiency, loses on commodity swings.';
    }
    if (layers.infrastructure >= 2 && syn.length >= 2) {
      return 'Regional tollbooth — repair and cold-chain capacity rented across the network; utilization is the whole game.';
    }
    if (layers.primary_production >= 3 || (layers.primary_production >= 2 && layers.processing >= 1)) {
      return 'Upstream scale play — many producers feeding shared demand; wins on utilization, loses on commodity swings.';
    }
    if (layers.consumer_channel >= 2 && (layers.processing >= 1 || layers.primary_production >= 1)) {
      return 'Downstream capture — margin lives at the counter; you own the customer if inputs stay cheap.';
    }
    if (layers.processing >= 2 && layers.primary_production >= 1) {
      return 'Processing hub — spread between farm gate and retail shelf, exposed to input shortages.';
    }
    if (layers.infrastructure >= 1 && layers.primary_production + layers.processing >= 3) {
      return 'Infrastructure-backed integrator — operations lean on your repair and cold-chain tollbooth.';
    }

    if (syn.length >= 2) {
      return 'Vertical/horizontal farm integrator — connected supply chains lowering costs across the Capital Farm.';
    }
    return 'Diversified farm operator — a mix of production, processing, and channels with moderate synergy.';
  }

  function portfolioRiskSummary(state, synergies) {
    synergies = synergies || computeSynergies(state);
    const strained = synergies.filter((y) => y.capacityStrained).length;
    const vulns = [...new Set(synergies.map((y) => y.addedRiskLabel).filter(Boolean))];
    const chainCount = synergies.length;
    const utilization = computeSupplierUtilization(state);
    const utilizationRows = Object.values(utilization).map((u) => ({
      templateId: u.templateId,
      name: u.name,
      utilizationPct: u.utilizationPct,
      overCapacity: u.overCapacity,
      policy: u.policy,
      externalContractRevenue: u.externalContractRevenue || 0,
      exportRevenue: u.exportRevenue || 0,
      exportLabel: u.exportLabel || '',
      externalDropped: u.externalDropped || false,
    }));
    const externalRevenueTotal = utilizationRows.reduce(
      (a, u) => a + (u.externalContractRevenue || 0) + (u.exportRevenue || 0),
      0
    );
    const shortages = utilizationRows.filter((u) => u.overCapacity);
    return {
      activeLinks: chainCount,
      capacityStrain: strained,
      topVulnerabilities: vulns.slice(0, 3),
      utilization: utilizationRows,
      shortages,
      externalRevenueTotal,
    };
  }

  /** Best missing template to complete an active or imminent supply-chain link. */
  function pickCriticalMissingTemplate(state) {
    const owned = ownedIds(state);
    const nodes = portfolioNodes(state);
    if (!nodes.length) return null;

    const scores = {};
    const add = (id, n) => {
      if (owned.has(id)) return;
      scores[id] = (scores[id] || 0) + n;
    };

    CONNECTIONS.forEach((conn) => {
      if (owned.has(conn.supplier) && !owned.has(conn.customer)) add(conn.customer, 6);
      if (owned.has(conn.customer) && !owned.has(conn.supplier)) add(conn.supplier, 6);
    });

    nodes.forEach((n) => {
      const tmpl = templateById(n.templateId);
      (tmpl?.dependencyPartners || []).forEach((depId) => add(depId, 4));
    });

    if (nodes.length >= 2) {
      if (!owned.has('delivery_cold_storage')) add('delivery_cold_storage', 3.5);
      if (!owned.has('equipment_repair')) add('equipment_repair', 3);
    }

    const ranked = Object.entries(scores)
      .map(([id, score]) => ({ id, score, t: templateById(id) }))
      .filter((e) => e.t)
      .sort((a, b) => b.score - a.score);

    return ranked.length ? ranked[0].t : null;
  }

  function hasCriticalChainGap(state) {
    return !!pickCriticalMissingTemplate(state);
  }

  global.FarmSupplyChain = {
    TEMPLATES,
    BUSINESS_TEMPLATES,
    REAL_ESTATE_TEMPLATES,
    CONNECTIONS,
    SHOCKS,
    LAYER_LABELS,
    SUPPLY_POLICIES,
    CONNECTION_DEMAND,
    isActive,
    templateById,
    isRealEstateAsset,
    portfolioNodes,
    ownedIds,
    pickTemplate,
    pickRealEstateTemplate,
    templateWeights,
    layerFor,
    autopilotFor,
    AUTOPILOT_NEGLECT_TURNS,
    urgentFreqMultFor,
    neglectSeverity,
    turnsSinceCare,
    isNeglected,
    neglectUrgentMult,
    urgentStakeMult,
    autopilotBurdenLabel,
    markBusinessCare,
    improveCareRecoveryMult,
    improveNoteForAutopilot,
    applyNeglectPressure,
    capacityFor,
    baselineCapacityLoad,
    capacityDisplayMetrics,
    isAllocatableTemplate,
    defaultSupplyPolicy,
    getSupplyPolicy,
    connectionDemandWeight,
    computeOwnedDownstreamDemand,
    computeDownstreamDemand,
    computeSupplierUtilization,
    effectiveCapacity,
    agriConglomerateCapacityMult,
    monopolyTollkeeperExternalMult,
    uniqueOwnedCustomersForSupplier,
    isInfrastructureTemplate,
    isUpstreamExportEligible,
    exportChannelEnabled,
    applyInfrastructureToRealEstate,
    applyExportToBusiness,
    applyOverCapacityPenalties,
    computeInternalServiceValue,
    detectSupplyShortages,
    computeSupplyLeverage,
    applyLeverageToUtility,
    LEVERAGE_CAP,
    computeSynergies,
    applyToBusiness,
    quarterlyProfitForBusiness,
    neglectThresholdFor,
    strategicHint,
    missingDependencies,
    pickShock,
    applyShock,
    classifyStrategy,
    layerComposition,
    dominantLayer,
    buildRunChainReport,
    policySummaryForState,
    portfolioRiskSummary,
    pickCriticalMissingTemplate,
    hasCriticalChainGap,
  };
})(typeof window !== 'undefined' ? window : globalThis);
