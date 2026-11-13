import test from 'node:test';
import assert from 'node:assert/strict';
import { getPlan, publicCatalog } from '../src/catalog.mjs';
import { createPaymentIntent, canActivateFromVerifiedStatus, isFinalStatus } from '../src/payment-flow.mjs';
import { createComgatePayment } from '../src/comgate.mjs';

test('catalog keeps Commander prices in minor CZK units', () => {
  assert.equal(getPlan('short').priceMinor, 12900);
  assert.equal(getPlan('standard').priceMinor, 29900);
  assert.deepEqual(publicCatalog().map(p => p.id), ['short', 'standard']);
});

test('payment intent is server-generated from a trusted plan', () => {
  const intent = createPaymentIntent({ planId: 'short', email: ' Petr@Example.cz ' });
  assert.equal(intent.priceMinor, 12900);
  assert.equal(intent.currency, 'CZK');
  assert.equal(intent.email, 'petr@example.cz');
  assert.match(intent.refId, /^LC-\d+-[0-9a-f]{8}$/);
});

test('only verified PAID can activate a stay', () => {
  assert.equal(canActivateFromVerifiedStatus('PAID'), true);
  assert.equal(canActivateFromVerifiedStatus('PENDING'), false);
  assert.equal(canActivateFromVerifiedStatus('CANCELLED'), false);
  assert.equal(isFinalStatus('PAID'), true);
  assert.equal(isFinalStatus('CANCELLED'), true);
  assert.equal(isFinalStatus('PENDING'), false);
});

test('Comgate request uses server auth and trusted amount', async () => {
  let captured;
  const fakeFetch = async (url, options) => {
    captured = { url, options };
    return new Response(JSON.stringify({ code: 0, message: 'OK', transId: 'AAAA-BBBB-CCCC', redirect: 'https://payments.example.test/pay' }), { status: 201 });
  };
  const input = createPaymentIntent({ planId: 'standard', email: 'test@example.cz' });
  const result = await createComgatePayment(input, {
    config: { merchant: 'merchant', secret: 'secret', test: true, apiBase: 'https://payments.example.test' },
    fetchImpl: fakeFetch,
  });
  assert.equal(result.transId, 'AAAA-BBBB-CCCC');
  assert.equal(captured.url, 'https://payments.example.test/v2.0/payment.json');
  const body = JSON.parse(captured.options.body);
  assert.equal(body.price, 29900);
  assert.equal(body.curr, 'CZK');
  assert.equal(body.method, 'ALL');
  assert.ok(captured.options.headers.Authorization.startsWith('Basic '));
});
