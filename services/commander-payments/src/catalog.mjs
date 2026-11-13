export const PAYMENT_CURRENCY = 'CZK';

export const plans = Object.freeze({
  short: Object.freeze({
    id: 'short',
    productCode: 'COMMANDER_SHORT',
    label: 'Commander 1-15',
    name: 'Krátký pobyt',
    daysMin: 1,
    daysMax: 15,
    priceMinor: 12_900,
    currency: PAYMENT_CURRENCY,
  }),
  standard: Object.freeze({
    id: 'standard',
    productCode: 'COMMANDER_STD',
    label: 'Commander 16-35',
    name: 'Standardní pobyt',
    daysMin: 16,
    daysMax: 35,
    priceMinor: 29_900,
    currency: PAYMENT_CURRENCY,
  }),
});

export function getPlan(planId) {
  const plan = plans[planId];
  if (!plan) throw new Error(`Unknown payment plan: ${planId}`);
  return plan;
}

export function publicCatalog() {
  return Object.values(plans).map(({ productCode, ...plan }) => plan);
}
