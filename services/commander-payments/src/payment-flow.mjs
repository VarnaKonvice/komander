import { randomUUID } from 'node:crypto';
import { resolvePlanForStay } from './stay-pricing.mjs';

export function createPaymentIntent({ startDate, endDate, email, country = 'CZ' }) {
  const plan = resolvePlanForStay({ startDate, endDate });
  const normalizedEmail = String(email || '').trim().toLowerCase();
  if (!/^\S+@\S+\.\S+$/.test(normalizedEmail)) throw new Error('Valid payer email is required');

  const refId = `LC-${Date.now()}-${randomUUID().slice(0, 8)}`;
  return {
    refId,
    planId: plan.id,
    productCode: plan.productCode,
    label: plan.label,
    stayDays: plan.stayDays,
    startDate,
    endDate,
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
