import { randomInt } from 'node:crypto';

export function loadBankTransferConfig(env = process.env) {
  return {
    iban: String(env.FIO_IBAN || '').replace(/\s+/g, '').toUpperCase(),
    recipientName: String(env.FIO_RECIPIENT_NAME || 'BOHANES TECHNOLOGIES').trim(),
  };
}

export function hasBankTransferAccount(config) {
  return /^CZ\d{22}$/.test(config?.iban || '');
}

export function createVariableSymbol() {
  return String(randomInt(1_000_000_000, 10_000_000_000));
}

function safeSpaydText(value, maxLength) {
  return String(value || '')
    .normalize('NFD').replace(/[\u0300-\u036f]/g, '')
    .toUpperCase()
    .replace(/\*/g, '')
    .replace(/[^0-9A-Z $%+\-./:]/g, ' ')
    .replace(/\s+/g, ' ')
    .trim()
    .slice(0, maxLength);
}

export function buildSpayd({ iban, amountMinor, currency = 'CZK', variableSymbol, message = 'LAZENSKY COMMANDER', recipientName = 'BOHANES TECHNOLOGIES' }) {
  const normalizedIban = String(iban || '').replace(/\s+/g, '').toUpperCase();
  if (!/^CZ\d{22}$/.test(normalizedIban)) throw new Error('Valid Czech IBAN is required');
  if (!Number.isInteger(amountMinor) || amountMinor <= 0) throw new Error('amountMinor must be a positive integer');
  if (!/^\d{1,10}$/.test(String(variableSymbol || ''))) throw new Error('variableSymbol must be 1-10 digits');
  if (currency !== 'CZK') throw new Error('QR bank transfer currently supports CZK only');

  const amount = (amountMinor / 100).toFixed(2);
  const fields = [
    'SPD*1.0',
    `ACC:${normalizedIban}`,
    `AM:${amount}`,
    'CC:CZK',
    'PT:IP',
    `X-VS:${variableSymbol}`,
    `MSG:${safeSpaydText(message, 60)}`,
    `RN:${safeSpaydText(recipientName, 35)}`,
  ];
  return `${fields.join('*')}*`;
}

export function createBankTransferInstruction({ intent, config = loadBankTransferConfig(), variableSymbol = createVariableSymbol() }) {
  if (!hasBankTransferAccount(config)) throw new Error('Fio bank account is not configured');
  const spayd = buildSpayd({
    iban: config.iban,
    amountMinor: intent.priceMinor,
    currency: intent.currency,
    variableSymbol,
    message: `LAZENSKY COMMANDER ${intent.planId}`,
    recipientName: config.recipientName,
  });
  return {
    provider: 'fio-transfer',
    state: 'PENDING',
    refId: intent.refId,
    planId: intent.planId,
    stayDays: intent.stayDays,
    amountMinor: intent.priceMinor,
    currency: intent.currency,
    variableSymbol,
    iban: config.iban,
    recipientName: config.recipientName,
    spayd,
  };
}
