import { getPlan } from './catalog.mjs';

function parseDateOnly(value, fieldName) {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(String(value || ''))) {
    throw new Error(`${fieldName} must be YYYY-MM-DD`);
  }
  const date = new Date(`${value}T00:00:00Z`);
  if (Number.isNaN(date.getTime()) || date.toISOString().slice(0, 10) !== value) {
    throw new Error(`${fieldName} is not a valid date`);
  }
  return date;
}

export function countStayDaysInclusive(startDate, endDate) {
  const start = parseDateOnly(startDate, 'startDate');
  const end = parseDateOnly(endDate, 'endDate');
  const diff = Math.round((end - start) / 86_400_000) + 1;
  if (diff < 1) throw new Error('endDate must not be before startDate');
  return diff;
}

export function resolvePlanForStay({ startDate, endDate }) {
  const stayDays = countStayDaysInclusive(startDate, endDate);
  if (stayDays <= 15) return { ...getPlan('short'), stayDays };
  if (stayDays <= 35) return { ...getPlan('standard'), stayDays };
  throw new Error('Stay longer than 35 days requires a separate pricing rule');
}
