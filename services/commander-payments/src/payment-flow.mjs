import { randomUUID } from 'node:crypto';
import { getPlan } from './catalog.mjs';

export function createPaymentIntent({ planId, email, country = 'CZ' }) {
  const plan = getPlan(planId);
  const normalizedEmail = String(email || '').trim().toLowerCase();
  if (!/^\S+@\S+\.\S+$/.test(normalizedEmail)) throw new Error('Valid payer email is required');

  const refId = `LC-${Date.now()}-${randomUUID().slice(0, 8)}`;
  return {
    refId,
    planId: plan.id,
    productCode: plan.productCode,
    label: plan.label,
    priceMinor: plan.priceMinor,
    currency: plan.currency,
    email: normalizedEmail,
    country,
    method: 'ALL',
  };
}

export function isFinalStatus(status) {
  return status === 'PAID' || status === 'CANCELLED';
}

export function canActivateFromVerifiedStatus(status) {
  return status === 'PAID';
}
