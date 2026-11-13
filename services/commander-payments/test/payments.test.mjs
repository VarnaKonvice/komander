import test from 'node:test';
import assert from 'node:assert/strict';
import { getPlan, publicCatalog } from '../src/catalog.mjs';
import { countStayDaysInclusive, resolvePlanForStay } from '../src/stay-pricing.mjs';
import { createPaymentIntent, canActivateFromVerifiedStatus, isFinalStatus } from '../src/payment-flow.mjs';
import { buildSpayd, createBankTransferInstruction } from '../src/bank-transfer.mjs';
import { createComgatePayment } from '../src/comgate.mjs';

test('catalog keeps Commander prices in minor CZK units', () => {
  assert.equal(getPlan('short').priceMinor, 12900);
  assert.equal(getPlan('standard').priceMinor, 29900);
  assert.deepEqual(publicCatalog().map(p => p.id), ['short', 'standard']);
});

test('stay duration is inclusive and chooses the price automatically', () => {
  assert.equal(countStayDaysInclusive('2026-11-01', '2026-11-15'), 15);
  assert.equal(resolvePlanForStay({ startDate: '2026-11-01', endDate: '2026-11-15' }).priceMinor, 12900);
  assert.equal(countStayDaysInclusive('2026-11-01', '2026-11-16'), 16);
  assert.equal(resolvePlanForStay({ startDate: '2026-11-01', endDate: '2026-11-16' }).priceMinor, 29900);
  assert.throws(() => resolvePlanForStay({ startDate: '2026-11-01', endDate: '2026-12-06' }), /longer than 35/);
});

test('payment intent does not accept a client-selected price or plan', () => {
  const intent = createPaymentIntent({
    startDate: '2026-11-01',
    endDate: '2026-11-20',
    email: ' Petr@Example.cz ',
    planId: 'short',
    priceMinor: 1,
  });
  assert.equal(intent.planId, 'standard');
  assert.equal(intent.priceMinor, 29900);
  assert.equal(intent.stayDays, 20);
  assert.equal(intent.email, 'petr@example.cz');
});

test('only verified PAID can activate a stay', () => {
  assert.equal(canActivateFromVerifiedStatus('PAID'), true);
  assert.equal(canActivateFromVerifiedStatus('PENDING'), false);
  assert.equal(canActivateFromVerifiedStatus('CANCELLED'), false);
  assert.equal(isFinalStatus('PAID'), true);
  assert.equal(isFinalStatus('CANCELLED'), true);
  assert.equal(isFinalStatus('PENDING'), false);
});

test('Czech QR payment SPAYD contains server price and variable symbol', () => {
  const spayd = buildSpayd({
    iban: 'CZ5855000000001265098001',
    amountMinor: 12900,
    variableSymbol: '1234567890',
    message: 'Lázeňský Commander',
  });
  assert.match(spayd, /^SPD\*1\.0\*/);
  assert.match(spayd, /ACC:CZ5855000000001265098001\*/);
  assert.match(spayd, /AM:129\.00\*/);
  assert.match(spayd, /CC:CZK\*/);
  assert.match(spayd, /X-VS:1234567890\*/);
});

test('bank transfer instruction is pending until bank reconciliation', () => {
  const intent = createPaymentIntent({ startDate: '2026-11-01', endDate: '2026-11-07', email: 'test@example.cz' });
  const bank = createBankTransferInstruction({
    intent,
    config: { iban: 'CZ5855000000001265098001', recipientName: 'BOHANES TECHNOLOGIES' },
    variableSymbol: '9876543210',
  });
  assert.equal(bank.state, 'PENDING');
  assert.equal(bank.amountMinor, 12900);
  assert.equal(bank.variableSymbol, '9876543210');
  assert.match(bank.spayd, /AM:129\.00\*/);
});

test('Comgate request uses server auth and automatically determined amount', async () => {
  let captured;
  const fakeFetch = async (url, options) => {
    captured = { url, options };
    return new Response(JSON.stringify({ code: 0, message: 'OK', transId: 'AAAA-BBBB-CCCC', redirect: 'https://payments.example.test/pay' }), { status: 201 });
  };
  const input = createPaymentIntent({ startDate: '2026-11-01', endDate: '2026-11-20', email: 'test@example.cz' });
  const result = await createComgatePayment(input, {
    config: { merchant: 'merchant', secret: 'secret', test: true, apiBase: 'https://payments.example.test' },
    fetchImpl: fakeFetch,
  });
  assert.equal(result.transId, 'AAAA-BBBB-CCCC');
  const body = JSON.parse(captured.options.body);
  assert.equal(body.price, 29900);
  assert.equal(body.curr, 'CZK');
});
